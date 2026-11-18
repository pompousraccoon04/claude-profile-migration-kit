# Copy this file to migration-settings.psd1 (same folder) and fill it in, or ask Claude to.
# Every script in this folder reads it. Folder and file names only, no full paths, in the lists.
@{
  # The old Windows profile folder: the one that has your repos and Claude history in it.
  OldProfile   = 'C:\Users\olduser'

  # --- Only needed for the optional move step (move-projects.ps1, move-home-root.ps1). ---

  # Where projects end up. Must be on the same drive as OldProfile.
  Dest         = 'C:\dev'

  # Project folders directly inside OldProfile to move into Dest.
  HomeFolders  = @()

  # An optional second place that holds project folders (for example 'C:\tmp'), and which of
  # its folders to move. Leave OtherRoot empty if there isn't one.
  OtherRoot    = ''
  OtherFolders = @()

  # Loose work files sitting directly in OldProfile, moved to Dest\home by move-home-root.ps1.
  HomeFiles    = @()
}
