# Deletes the "<name>.pre-migration-<date>-<time>" leftovers in the new profile. Each run of the
# first migration script set aside what was there before it copied, which is where they came from.
#
# Run signed in as the new account. Without -Run it only lists what it would delete.
# Deletion is permanent (no Recycle Bin).
param(
  [switch]$Run,
  [string[]]$Roots = @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA),
  [string]$ClaudeHome = "$env:USERPROFILE\.claude"
)
$ErrorActionPreference = 'Stop'

function Names($dir) {   # transcript file names under a folder. robocopy's list mode copes with paths over 260 characters, which PowerShell 5.1 does not
  if (Test-Path -LiteralPath $dir) { robocopy $dir NULL *.jsonl /L /S /NJH /NJS /NDL /NC /NS /NP | ForEach-Object { ($_.Trim() -split '\\')[-1] } | Where-Object { $_ } }
}
$live = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($n in Names "$ClaudeHome\projects") { [void]$live.Add($n) }

$rows = foreach ($item in $Roots | ForEach-Object { Get-ChildItem -LiteralPath $_ -Force } | Where-Object { $_.Name -match '\.pre-migration-\d{8}-\d{6}$' }) {
  if ($item.PSIsContainer) {
    $sum = robocopy $item.FullName NULL /L /S /NFL /NDL /NJH /BYTES /NC /NP /XJ
    $mb = [math]::Round([int64](($sum | Select-String '^\s*Bytes\s*:\s*(\d+)').Matches.Groups[1].Value) / 1MB, 1)
  }
  else { $mb = [math]::Round($item.Length / 1MB, 1) }

  # A set-aside copy of .claude is only a duplicate if every conversation in it is also in the live one.
  $unique = @(Names "$($item.FullName)\projects" | Where-Object { -not $live.Contains($_) }).Count
  $action = if ($unique) { "KEPT - $unique conversation(s) exist only here" } elseif ($Run) { 'deleted' } else { 'would delete' }

  if ($Run -and -not $unique) {
    if ($item.PSIsContainer) { cmd /c rd /s /q "\\?\$($item.FullName)" }   # rd copes with long paths and read-only files
    else { Remove-Item -LiteralPath $item.FullName -Force }
    if (Test-Path -LiteralPath $item.FullName) { $action = 'FAILED - something in it is open' }
  }
  [pscustomobject]@{ Action = $action; MB = $mb; Item = $item.FullName }
}

if (-not $rows) { "Nothing to clean up: no .pre-migration items found."; return }
$rows | Format-Table -AutoSize | Out-String -Width 220
"{0} item(s), {1:N0} MB in total." -f @($rows).Count, ($rows | Measure-Object MB -Sum).Sum
if (-not $Run) { "LIST ONLY - nothing was deleted. To delete, run the same command with -Run on the end." }
