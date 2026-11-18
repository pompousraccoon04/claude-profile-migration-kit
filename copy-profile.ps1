# Copies Claude Code + Claude desktop data, Git config and SSH keys from the old Windows profile
# into the profile you are signed in to now. Repos are not touched: they stay at their old paths,
# so nothing inside the copied data needs rewriting.
#
# Run signed in as the NEW account, in a normal (not "Run as administrator") PowerShell window.
# Without -Run it only prints what it would do. With -Run, Claude must be fully quit first
# (desktop app including its tray icon, and any claude CLI).
param([switch]$Run)
$ErrorActionPreference = 'Stop'
$S = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'migration-settings.psd1')
$old = $S.OldProfile
$new = $env:USERPROFILE

if ($new -ieq $old) { throw "You're signed in as the old account ($old). Sign in as the new one and rerun." }
if (-not (Test-Path -LiteralPath "$old\.claude")) { throw "Can't find or read $old\.claude. Check OldProfile in migration-settings.psd1, and that this account owns the old profile (see README)." }
if ($Run -and (Get-Process -Name claude -ErrorAction SilentlyContinue)) { throw "Close Claude first (desktop app including the tray icon, and any claude CLI), then rerun." }

# The Claude desktop app (MSIX install) keeps its data in %LOCALAPPDATA%\Claude-Data if that folder
# has anything in it, which is what happens when it first starts on a profile with no older data.
# Otherwise it uses %APPDATA%\Claude. The same rule picks the source on the old profile.
function First-NonEmpty([string[]]$paths) {
  foreach ($p in $paths) { if ((Test-Path -LiteralPath $p) -and (Get-ChildItem -LiteralPath $p -Force | Select-Object -First 1)) { return $p } }
}
$source = First-NonEmpty "$old\AppData\Local\Claude-Data", "$old\AppData\Roaming\Claude"
$target = First-NonEmpty "$env:LOCALAPPDATA\Claude-Data"
if (-not $target) { $target = "$env:APPDATA\Claude" }
function Git-Configs($dir) {   # .gitconfig and its includeIf files, not leftovers from an earlier run
  Get-ChildItem -LiteralPath $dir -Force -Filter '.gitconfig*' -File | Where-Object Name -notmatch '\.pre-migration-'
}
"Old profile:      $old"
"Desktop app data: " + $(if ($source) { "$source  ->  $target" } else { 'none found on the old profile, skipped' })

# Set aside anything the new profile already created, so nothing gets merged or overwritten.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$existing = @("$new\.claude", "$new\.claude.json", "$env:APPDATA\Claude", $target, "$new\.ssh") +
            @(Git-Configs $new | ForEach-Object FullName) |
            Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ }
foreach ($p in $existing) {
  if ($Run) { Rename-Item -LiteralPath $p -NewName ((Split-Path $p -Leaf) + ".pre-migration-$stamp"); "Set aside:        $p" }
  else { "Will set aside:   $p" }
}

function Count-Files($dir, $pattern) {   # long-path-safe; Windows PowerShell 5.1 trips over paths > 260 chars
  if (Test-Path -LiteralPath $dir) { @([IO.Directory]::EnumerateFiles("\\?\$dir", $pattern, 'AllDirectories')).Count } else { 0 }
}
$t = Count-Files "$old\.claude\projects" '*.jsonl'
$s = if ($source) { Count-Files "$source\claude-code-sessions" '*.json' } else { 0 }
$k = if (Test-Path -LiteralPath "$old\.ssh") { @(Get-ChildItem -LiteralPath "$old\.ssh" -Force -File).Count } else { 0 }
$g = @(Git-Configs $old).Count

if (-not $Run) {
  ""
  "Would copy: $t conversation transcripts, $s desktop session files, $k SSH files, $g Git config files."
  "PREVIEW ONLY - nothing was changed. Quit Claude, then run the same command with -Run on the end."
  return
}

# Caches, the VM image and app binaries re-download on their own. Sign-in tokens and cookies are
# encrypted to the old account and can't be used here, so they're skipped too.
robocopy "$old\.claude" "$new\.claude" /E /XJ /R:1 /W:1 /NFL /NDL /NP /XF .credentials.json
if ($LASTEXITCODE -ge 8) { throw "Copy of .claude failed (robocopy exit $LASTEXITCODE)" }
if (Test-Path -LiteralPath "$old\.claude.json") { Copy-Item -LiteralPath "$old\.claude.json" -Destination "$new\.claude.json" }

if ($source) {
  $skipDirs = 'vm_bundles','claude-code','claude-code-vm','Cache','Code Cache','GPUCache','GrShaderCache',
              'ShaderCache','DawnGraphiteCache','DawnWebGPUCache','GPUPersistentCache','Crashpad','logs','dxt-install-*'
  robocopy $source $target /E /XJ /R:1 /W:1 /NFL /NDL /NP /XD $skipDirs /XF Cookies Cookies-journal
  if ($LASTEXITCODE -ge 8) { throw "Copy of $source failed (robocopy exit $LASTEXITCODE)" }
}

# Git config, including any files pulled in by includeIf (.gitconfig-work, .gitconfig-personal...).
Git-Configs $old | Copy-Item -Destination $new

# SSH. Private keys often have inheritance turned off and grant only the old account. This account
# owns them, and an owner can always edit permissions, so it grants itself read access first.
if (Test-Path -LiteralPath "$old\.ssh") {
  $me = whoami
  Get-ChildItem -LiteralPath "$old\.ssh" -Force -File |
    Where-Object { (Get-Acl -LiteralPath $_.FullName).AreAccessRulesProtected } |
    ForEach-Object { icacls $_.FullName /grant "${me}:R" | Out-Null; if ($LASTEXITCODE) { throw "Couldn't grant read on $($_.FullName)" } }
  # .ssh\agent only holds Git Bash's ssh-agent socket, which is recreated on demand.
  robocopy "$old\.ssh" "$new\.ssh" /E /XJ /R:1 /W:1 /NFL /NDL /NP /XD agent
  if ($LASTEXITCODE -ge 8) { throw "Copy of .ssh failed (robocopy exit $LASTEXITCODE)" }

  # An ssh config that names keys by their old full path would keep using the old copy, which
  # OpenSSH rejects because another account can read it. Point it at this profile's copy instead.
  $cfg = "$new\.ssh\config"
  if (Test-Path -LiteralPath $cfg) {
    $text = [regex]::Replace([IO.File]::ReadAllText($cfg), [regex]::Escape("$old\.ssh\"), '~/.ssh/', 'IgnoreCase')
    [IO.File]::WriteAllText($cfg, $text)   # UTF-8 without BOM; a BOM breaks OpenSSH's config parser
  }
}

$tn = Count-Files "$new\.claude\projects" '*.jsonl'
$sn = if ($source) { Count-Files "$target\claude-code-sessions" '*.json' } else { 0 }
$kn = if (Test-Path -LiteralPath "$new\.ssh") { @(Get-ChildItem -LiteralPath "$new\.ssh" -Force -File).Count } else { 0 }
$gn = @(Git-Configs $new).Count
""
"Conversation transcripts: $tn of $t"
"Desktop session files:    $sn of $s"
"SSH files:                $kn of $k"
"Git config files:         $gn of $g"
if ($tn -ne $t -or $sn -ne $s -or $kn -ne $k -or $gn -ne $g) { Write-Warning "Counts don't match - don't delete anything from the old profile. Rerunning is safe." }
else {
  "All copied. Start Claude, sign in, and open your projects from $old\<repo> as before."
  "Test SSH with:  ssh -T git@github.com   (if you used ssh-agent, re-add keys with ssh-add)"
}
