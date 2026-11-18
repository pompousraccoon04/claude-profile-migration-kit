# Optional, after move-projects.ps1. Claude files each conversation under the folder it was started
# in, so conversations started from the old home folder itself match nothing in Dest. This moves
# them, plus the loose work files listed as HomeFiles in migration-settings.psd1, to Dest\home.
#
# Run signed in as the NEW account. Without -Run it only prints what it would do. With -Run,
# Claude must be fully quit. Safe to rerun.
param(
  [switch]$Run,
  [string]$ClaudeHome = "$env:USERPROFILE\.claude",
  [string[]]$ConfigFiles = @("$env:USERPROFILE\.claude.json", "$ClaudeHome\history.jsonl")
)
$ErrorActionPreference = 'Stop'
$S = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'migration-settings.psd1')
$OldHome = $S.OldProfile
$Dest = "$($S.Dest)\home"
# Work files only. Files that tools read from the home folder (.gitconfig, .bash_history, tokens,
# certificates) are not project files; copy the ones still in use into the new profile instead.
$files = @($S.HomeFiles)

if ($env:USERPROFILE -ieq $OldHome) { throw "Run this signed in as the new account. This is the old one." }
if ($Run -and ($ClaudeHome -ieq "$env:USERPROFILE\.claude") -and (Get-Process -Name claude -ErrorAction SilentlyContinue)) {
  throw "Claude is still running. Quit it from the tray icon, then rerun."
}
if (-not (Test-Path -LiteralPath (Split-Path $Dest))) { throw "$(Split-Path $Dest) doesn't exist yet. Run move-projects.ps1 first." }

# ---- 1. Files. Dest\home is created inside Dest, so it is private like the rest of it.
if ($Run) { New-Item -ItemType Directory -Force -Path $Dest | Out-Null }
$moved = 0; $skipped = @()
foreach ($f in $files | Where-Object { Test-Path -LiteralPath "$OldHome\$_" }) {
  if (Test-Path -LiteralPath "$Dest\$f") { $skipped += $f; continue }
  try { if ($Run) { Move-Item -LiteralPath "$OldHome\$f" -Destination "$Dest\$f" }; $moved++ } catch { $skipped += $f }
}

# ---- 2. Conversations. Claude keeps them in a folder named after the path they were started from.
function Enc($s) { $s -replace '[^A-Za-z0-9]', '-' }
function J($s) { $s -replace '\\', '\\' }                  # a path as it is written inside JSON
$copied = "$ClaudeHome\projects\$(Enc $OldHome)"           # what copy-profile.ps1 brought over
$fresh  = "$OldHome\.claude\projects\$(Enc $OldHome)"      # the old account's own, which may be newer
$target = "$ClaudeHome\projects\$(Enc $Dest)"
if ($Run) {
  if ((Test-Path -LiteralPath $copied) -and -not (Test-Path -LiteralPath $target)) { Rename-Item -LiteralPath $copied -NewName (Enc $Dest) }
  # Bring across anything the old account has that is missing here or newer (/XO never overwrites newer).
  foreach ($src in $copied, $fresh | Where-Object { Test-Path -LiteralPath $_ }) {
    robocopy $src $target /E /XO /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Couldn't copy conversations from $src" }
  }
}
$convos = @($copied, $fresh, $target | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter *.jsonl -File } | ForEach-Object Name | Select-Object -Unique).Count

# Update the "cwd" field on each transcript line, exact matches of the old home folder only.
$utf8 = New-Object Text.UTF8Encoding $false
$cwdRx = '(?i)(?<="cwd":")' + [regex]::Escape((J $OldHome)) + '(?=")'
$cwdNew = (J $Dest).Replace('$', '$$')
$transcripts = 0
if ($Run -and (Test-Path -LiteralPath $target)) {
  foreach ($file in [IO.Directory]::EnumerateFiles("\\?\$target", '*.jsonl', 'AllDirectories')) {
    $old = [IO.File]::ReadAllText($file); $new = [regex]::Replace($old, $cwdRx, $cwdNew)
    if ($new -cne $old) { $transcripts++; [IO.File]::WriteAllText($file, $new, $utf8) }
  }
}

# ---- 3. Settings: the entry for the old home folder itself, in either slash style. Entries for
#         folders underneath it are not touched. Originals are saved first.
$segs = @($OldHome -split '\\' | ForEach-Object { [regex]::Escape($_) })
$cfgRx = '(?i)"' + $segs[0] + '(\\\\|/)' + (@($segs | Select-Object -Skip 1) -join '\1') + '"'
$cfgNew = '"' + (($Dest -split '\\') -join '${1}') + '"'
$backupDir = Join-Path (Split-Path $ClaudeHome) "claude-config-before-home-move-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$configs = 0
foreach ($file in $ConfigFiles | Where-Object { Test-Path -LiteralPath $_ }) {
  $old = [IO.File]::ReadAllText($file); $new = [regex]::Replace($old, $cfgRx, $cfgNew)
  if ($new -ceq $old) { continue }
  $configs++
  if ($Run) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -LiteralPath $file -Destination (Join-Path $backupDir "$configs-$(Split-Path $file -Leaf)")
    [IO.File]::WriteAllText($file, $new, $utf8)
  }
}

# ---- 4. Report.
"Files moved to ${Dest}:     $moved"
"Conversations:              $convos"
if ($Run) { "Transcripts updated:        $transcripts" }
"Settings files updated:     $configs" + $(if ($Run -and $configs) { "   (originals in $backupDir)" })
if ($skipped) { Write-Warning "Not moved (already in $Dest, or open in a program): $($skipped -join ', ')" }

if (-not $Run) { "`nPREVIEW ONLY - nothing was changed. To do it, run the same command with -Run on the end." }
else { "`nDone. To resume those conversations:  cd $Dest ; claude --resume" }
