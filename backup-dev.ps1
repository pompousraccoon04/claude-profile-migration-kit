# Optional. Backs up everything in the projects folder (Dest in migration-settings.psd1) that is
# not safely on a Git host:
#   - folders that are not Git repos
#   - repos with no remote, unpushed commits, uncommitted changes or stashes
# Repos that are clean and fully pushed are skipped, because the Git host already has them.
#
# Writes one zip per folder to OneDrive\Dev-Backup and replaces it on each run.
# Add -List to see what would be backed up without writing anything.
param(
  [switch]$List,
  [string]$Root,
  [string]$BackupTo = $(if ($env:OneDrive) { "$env:OneDrive\Dev-Backup" })
)
if (-not $Root) { $Root = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'migration-settings.psd1')).Dest }
if (-not $BackupTo) { throw "OneDrive isn't set up for this account. Name a folder instead:  -BackupTo 'X:\some\folder'" }
$Dest = $BackupTo

$tar = "$env:SystemRoot\System32\tar.exe"                       # Windows' own tar writes zips; Git's tar can't
$exclude = '.venv', 'venv', 'node_modules', '__pycache__' | ForEach-Object { "--exclude=$_" }   # rebuilt from requirements, not worth storing
function G { git -c safe.directory=* @args 2>$null }           # read repos owned by either account, without changing git config

if (-not $List) { New-Item -ItemType Directory -Force -Path $Dest | Out-Null }
$skipped = 0
$rows = foreach ($d in Get-ChildItem -LiteralPath $Root -Directory -Force | Sort-Object Name) {
  $p = $d.FullName
  $why = if (-not (Test-Path -LiteralPath "$p\.git")) {
    if (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1) { 'not in Git' }   # empty folders have nothing to back up
  }
  else {
    $r = @()
    if (-not (G -C $p remote)) { $r += 'no remote' }
    elseif ([int](G -C $p rev-list --count --branches --not --remotes)) { $r += 'unpushed commits' }
    if (G -C $p status --porcelain) { $r += 'uncommitted changes' }
    if (G -C $p stash list) { $r += 'stash' }
    $r -join ', '
  }
  if (-not $why) { $skipped++; continue }

  $result = ''
  if (-not $List) {
    # Build the zip in the temp folder and swap it in only if tar succeeded, so a failed run
    # never replaces a good backup. The zip includes the .git folder, so history comes with it.
    $tmp = Join-Path $env:TEMP "dev-backup-$($d.Name).zip"
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    & $tar -a -c -f $tmp @exclude -C $Root $d.Name
    if ($LASTEXITCODE -eq 0) {
      Move-Item -LiteralPath $tmp -Destination (Join-Path $Dest "$($d.Name).zip") -Force
      $result = '{0:N1} MB' -f ((Get-Item -LiteralPath (Join-Path $Dest "$($d.Name).zip")).Length / 1MB)
    }
    else { $result = 'FAILED - previous backup kept' }
  }
  [pscustomobject]@{ Folder = $d.Name; Why = $why; Backup = $result }
}

if ($List) { $rows | Format-Table Folder, Why -AutoSize | Out-String -Width 160 } else { $rows | Format-Table -AutoSize | Out-String -Width 160 }
"$(@($rows).Count) folder(s) need a backup. $skipped skipped (fully pushed, or empty)."
if ($List) { "LIST ONLY - nothing was written. Run without -List to back up to $Dest" }
else {
  $failed = @($rows | Where-Object { $_.Backup -like 'FAILED*' })
  if ($failed) { Write-Warning "$($failed.Count) folder(s) failed, usually because a file is open in a program. Close it and rerun." }
  "Backups are in $Dest. To restore one, unzip it."
}
