# Optional. Moves project folders out of the old profile (and optionally a second folder such as
# C:\tmp) into a private Dest folder, then points Claude's history and settings at the new paths
# so past sessions still resume. Folder lists come from migration-settings.psd1.
#
# Run signed in as the NEW account, after copy-profile.ps1. Without -Run it only prints what it
# would do. With -Run, the old account must be signed out (restart the PC and sign in only as the
# new one) and Claude fully quit. Safe to rerun: it picks up whatever is left.
param(
  [switch]$Run,
  [string]$ClaudeHome = "$env:USERPROFILE\.claude",
  [string[]]$ConfigFiles = @(
    "$env:USERPROFILE\.claude.json",
    "$ClaudeHome\settings.json",
    "$ClaudeHome\settings.local.json",
    "$ClaudeHome\history.jsonl",
    "$env:APPDATA\Claude\claude_desktop_config.json",
    "$env:LOCALAPPDATA\Claude-Data\claude_desktop_config.json"
  )
)
$ErrorActionPreference = 'Stop'
$S = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'migration-settings.psd1')
$OldHome = $S.OldProfile
$Other = $S.OtherRoot
$Dest = $S.Dest
$fromHome = @($S.HomeFolders)
$fromOther = if ($Other) { @($S.OtherFolders) } else { @() }
$roots = @($OldHome) + @($Other | Where-Object { $_ })

if ($env:USERPROFILE -ieq $OldHome) { throw "Run this signed in as the new account. This is the old one." }
if ($Run -and ($ClaudeHome -ieq "$env:USERPROFILE\.claude") -and (Get-Process -Name claude -ErrorAction SilentlyContinue)) {
  throw "Claude is still running. Quit it from the tray icon, and sign the old Windows account out (a restart does both), then rerun."
}
if (-not (Test-Path -LiteralPath "$ClaudeHome\projects")) { throw "No Claude history found at $ClaudeHome\projects. Run copy-profile.ps1 first. Nothing was moved." }
if ((Split-Path $Dest -Qualifier) -ine (Split-Path $OldHome -Qualifier)) { throw "Dest ($Dest) must be on the same drive as OldProfile ($OldHome)." }
if (-not ($fromHome + $fromOther)) { throw "HomeFolders and OtherFolders in migration-settings.psd1 are both empty. Nothing to move." }

# ---- 1. Make Dest private. A new folder at the drive root is open to every account on the PC.
#         Only a folder's owner can change that, so this account has to be the one that creates it.
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if ((Test-Path -LiteralPath $Dest) -and ((Get-Acl -LiteralPath $Dest).Owner -ine $me)) {
  $inside = @(Get-ChildItem -LiteralPath $Dest -Force | ForEach-Object Name)
  if ($inside) {
    $msg = "$Dest was created by another account ($((Get-Acl -LiteralPath $Dest).Owner)), so this account can't make it private. Move these out of it, then rerun: $($inside -join ', ')"
    if ($Run) { throw $msg } else { Write-Warning $msg }
  }
  elseif ($Run) { Remove-Item -LiteralPath $Dest }   # empty, so recreate it below as this account
}
if ($Run) {
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  # Drop the permissions inherited from the drive and allow only this account, SYSTEM and Administrators.
  icacls $Dest /inheritance:r /grant:r "${me}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
  if ($LASTEXITCODE) { throw "Couldn't make $Dest private. Nothing was moved." }
}

# ---- 2. Move the folders.
$items = @(
  $fromHome  | ForEach-Object { [pscustomobject]@{ Root = $OldHome; Name = $_; From = "$OldHome\$_"; To = "$Dest\$_"; State = '' } }
  $fromOther | ForEach-Object { [pscustomobject]@{ Root = $Other;   Name = $_; From = "$Other\$_";   To = "$Dest\$_"; State = '' } }
)
$clash = $items | Group-Object Name | Where-Object Count -gt 1
if ($clash) { throw "These names are in both lists and would collide in ${Dest}: $($clash.Name -join ', ')" }

foreach ($i in $items) {
  $f = Test-Path -LiteralPath $i.From; $t = Test-Path -LiteralPath $i.To
  # An OtherRoot folder present on both sides was half-copied by an earlier run, so carry on with it.
  $i.State = if ($f -and $t -and $i.Root -ne $Other) { 'CONFLICT' } elseif ($f) { 'move' } elseif ($t) { 'already moved' } else { 'not found' }
}
if ($Run) {
  foreach ($i in $items | Where-Object State -eq 'move') {
    if ($i.Root -eq $Other) {
      # Copy then delete. The copies are new files, so they belong to this account and take on
      # Dest's private permissions. A rename would keep the old folder's open ones and old owner.
      robocopy $i.From $i.To /E /MOVE /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
      $i.State = if ($LASTEXITCODE -ge 8 -or (Test-Path -LiteralPath $i.From)) { 'IN USE' } else { 'moved' }
    }
    else {
      # Same drive, so this is a rename: instant and all-or-nothing. Profile folders are already
      # private to this account (once it owns them), and they stay that way.
      try { Move-Item -LiteralPath $i.From -Destination $i.To; $i.State = 'moved' } catch { $i.State = 'IN USE' }
    }
  }
}
$items | Where-Object State -ne 'not found' | Format-Table State, From, To -AutoSize | Out-String -Width 200
$ok = @($items | Where-Object { 'move', 'moved', 'already moved' -contains $_.State })
function Where-Is($i) { if (Test-Path -LiteralPath $i.To) { $i.To } else { $i.From } }

# ---- 3. Rename Claude's history folders. Claude names each one after the project path with every
#         non-alphanumeric character turned into '-', e.g. C:\dev\myrepo -> C--dev-myrepo.
function Enc($s) { $s -replace '[^A-Za-z0-9]', '-' }
$destPrefix = (Enc $Dest) + '-'
$renamed = 0
$histDirs = @(foreach ($d in Get-ChildItem -LiteralPath "$ClaudeHome\projects" -Directory) {
  if ($d.Name.StartsWith($destPrefix, 'OrdinalIgnoreCase')) { $d.FullName; continue }   # from an earlier run
  foreach ($root in $roots) {
    $pre = (Enc $root) + '-'
    if (-not $d.Name.StartsWith($pre, 'OrdinalIgnoreCase')) { continue }
    $rest = $d.Name.Substring($pre.Length)
    # Match the project folder itself, its subfolders and its worktrees.
    $hit = $ok | Where-Object { $_.Root -eq $root } | Where-Object { $e = Enc $_.Name; $rest -ieq $e -or $rest.StartsWith("$e-", 'OrdinalIgnoreCase') }
    if (-not $hit) { continue }
    $target = Join-Path $d.Parent.FullName ($destPrefix + $rest)
    if (Test-Path -LiteralPath $target) { Write-Warning "History folder already exists, left alone: $target"; break }
    $renamed++
    if ($Run) { Rename-Item -LiteralPath $d.FullName -NewName ($destPrefix + $rest); $target } else { $d.FullName }
    break
  }
})

# ---- 4. Rewrite old paths. One pattern per source root, matching C:\x, C:\\x (JSON) and C:/x, and
#         writing the new path back with the same separator. The lookahead stops 'app' from
#         matching inside 'app-data'.
$destRepl = (($Dest -split '\\') -join '${1}') + '${1}${2}'
$patterns = @(foreach ($root in $roots) {
  $names = @($ok | Where-Object { $_.Root -eq $root } | ForEach-Object Name | Sort-Object Length -Descending)
  if (-not $names) { continue }
  $segs = @($root -split '\\' | ForEach-Object { [regex]::Escape($_) })
  $alt = ($names | ForEach-Object { [regex]::Escape($_) }) -join '|'
  '(?i)' + $segs[0] + '(\\\\|\\|/)' + ((@($segs | Select-Object -Skip 1) + "($alt)") -join '\1') + '(?![A-Za-z0-9_.-])'
})
function Convert-Text($text, $lead) {
  foreach ($p in $patterns) { $text = [regex]::Replace($text, $lead + $p, $destRepl) }
  $text
}
$utf8 = New-Object Text.UTF8Encoding $false
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# Transcripts: only the "cwd" field on each line, which the resume list filters on. Message text is untouched.
$transcripts = 0
foreach ($dir in $histDirs) {
  foreach ($file in [IO.Directory]::EnumerateFiles("\\?\$dir", '*.jsonl', 'AllDirectories')) {
    $old = [IO.File]::ReadAllText($file); $new = Convert-Text $old '(?<="cwd":")'
    if ($new -cne $old) { $transcripts++; if ($Run) { [IO.File]::WriteAllText($file, $new, $utf8) } }
  }
}

# Settings: per-project settings, MCP server paths, permission modes. Originals are saved first.
$backupDir = Join-Path (Split-Path $ClaudeHome) "claude-config-before-move-$stamp"
$configs = 0
foreach ($file in $ConfigFiles | Where-Object { Test-Path -LiteralPath $_ }) {
  $old = [IO.File]::ReadAllText($file); $new = Convert-Text $old ''
  if ($new -ceq $old) { continue }
  $configs++
  if ($Run) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -LiteralPath $file -Destination (Join-Path $backupDir "$configs-$(Split-Path $file -Leaf)")
    [IO.File]::WriteAllText($file, $new, $utf8)
  }
}

# ---- 5. Git. Worktrees store absolute paths in both directions; 'worktree repair' rewrites them.
$worktrees = 0
foreach ($i in $ok) {
  $at = Where-Is $i
  $wtDir = Join-Path $at '.git\worktrees'
  if (Test-Path -LiteralPath $wtDir) {
    $paths = @(Get-ChildItem -LiteralPath $wtDir -Directory | ForEach-Object {
      $g = Join-Path $_.FullName 'gitdir'
      if (Test-Path -LiteralPath $g) { (Convert-Text ([IO.File]::ReadAllText($g).Trim()) '') -replace '[\\/]\.git$', '' }
    })
    if (-not $Run) { $worktrees += $paths.Count }
    else {
      $paths = @($paths | Where-Object { Test-Path -LiteralPath $_ })   # skips worktrees whose folder was already deleted
      if ($paths) {
        git -C $at worktree repair @paths
        if ($LASTEXITCODE) { Write-Warning "git worktree repair failed in $at" } else { $worktrees += $paths.Count }
      }
    }
  }
}

# ---- 6. Report.
$wanted = @($items | Where-Object State -ne 'not found').Count
"Folders in ${Dest}:         $(@($ok).Count) of $wanted"
"History folders renamed:    $renamed"
"Transcripts updated:        $transcripts"
"Settings files updated:     $configs" + $(if ($Run -and $configs) { "   (originals in $backupDir)" })
"Worktrees re-linked:        $worktrees"
if ($Run) { "Who can open ${Dest}:       " + (((Get-Acl -LiteralPath $Dest).Access | ForEach-Object { $_.IdentityReference.Value } | Select-Object -Unique) -join ', ') }
else { "Who can open ${Dest}:       will be limited to $me, SYSTEM and Administrators" }

$missing = @($items | Where-Object State -eq 'not found' | ForEach-Object Name)
if ($missing) { "`nNot found, skipped: $($missing -join ', ')" }
$stuck = @($items | Where-Object { 'IN USE', 'CONFLICT' -contains $_.State })
if ($stuck) {
  Write-Warning "$($stuck.Count) folder(s) were not moved (see State above)."
  "  IN USE   = a program has files open in it. Sign the old account out or restart, then rerun."
  "  CONFLICT = a folder with that name is already in $Dest. Rename one of them, then rerun."
}
$venvs = @($ok | ForEach-Object { $at = Where-Is $_; Get-ChildItem -LiteralPath $at -Directory -Force | Where-Object { Test-Path -LiteralPath "$($_.FullName)\pyvenv.cfg" } | ForEach-Object { "$Dest\$(Split-Path $at -Leaf)\$($_.Name)" } })
if ($venvs) { "`nPython virtual environments keep their old path inside and must be rebuilt (delete the folder, recreate it):"; $venvs | ForEach-Object { "  $_" } }

if (-not $Run) { "`nPREVIEW ONLY - nothing was changed. To do it, run the same command with -Run on the end." }
elseif (-not $stuck -and $ok) { "`nDone. Open projects from $Dest from now on. Test with:  cd $Dest\$($ok[0].Name) ; claude --resume" }
