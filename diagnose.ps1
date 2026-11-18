# Read-only check of where Claude's data ended up in the new profile. Changes nothing.
# Writes diagnose-output.txt next to this script (folder names and counts only, no file contents).
$out = Join-Path $PSScriptRoot 'diagnose-output.txt'
$pkg = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc"

function Count-Files($dir) { if (Test-Path -LiteralPath $dir) { @([IO.Directory]::EnumerateFiles("\\?\$dir", '*', 'AllDirectories')).Count } else { 'absent' } }
function Show-Sessions($root) {
  $s = "$root\claude-code-sessions"
  if (-not (Test-Path -LiteralPath $s)) { "    claude-code-sessions: absent"; return }
  Get-ChildItem -LiteralPath $s -Directory | ForEach-Object { $a = $_
    Get-ChildItem -LiteralPath $a.FullName -Directory | ForEach-Object { "    sessions\{0}\{1}  files={2}" -f $a.Name, $_.Name, @(Get-ChildItem -LiteralPath $_.FullName -File).Count } }
}
function Show-Claude($label, $root) {
  "== $label : $root"
  if (-not (Test-Path -LiteralPath $root)) { "    absent"; return }
  "    created=" + (Get-Item -LiteralPath $root).CreationTime + "  files=" + (Count-Files $root)
  Show-Sessions $root
  "    top-level: " + ((Get-ChildItem -LiteralPath $root -Force | Select-Object -ExpandProperty Name) -join ', ')
}

& {
  "whoami=$(whoami)  run=$(Get-Date)"
  "USERPROFILE=$env:USERPROFILE  APPDATA=$env:APPDATA"
  "Claude running: " + [bool](Get-Process -Name claude -ErrorAction SilentlyContinue)
  ""
  Show-Claude 'LOCALAPPDATA Claude-Data' "$env:LOCALAPPDATA\Claude-Data"
  Show-Claude 'REAL Roaming'            "$env:APPDATA\Claude"
  Show-Claude 'PACKAGE-PRIVATE Roaming' "$pkg\LocalCache\Roaming\Claude"
  Show-Claude 'PACKAGE-PRIVATE Local'   "$pkg\LocalCache\Local\Claude"
  ""
  "== ~\.claude\projects files: " + (Count-Files "$env:USERPROFILE\.claude\projects")
  "== ~\.claude.json exists: " + (Test-Path "$env:USERPROFILE\.claude.json")
  "== set-aside items:"
  Get-ChildItem $env:USERPROFILE, $env:APPDATA -Force -Filter '*pre-migration*' -ErrorAction SilentlyContinue | ForEach-Object { "    " + $_.FullName }
  "== package folder exists: " + (Test-Path $pkg)
} *>&1 | Out-File -FilePath $out -Encoding utf8

"Wrote $out"
