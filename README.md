# Claude profile migration kit

Your Windows account moved to a new domain and you now sign in to a fresh profile, for example
`C:\Users\you.NEWDOMAIN` instead of `C:\Users\you`. Claude Code and the Claude desktop app start
empty there, and so do Git and SSH. This kit copies your Claude history and settings, Git config
and SSH keys from the old profile into the new one, so `claude --resume` finds your past sessions.
Optionally, it then moves your projects to something like `C:\dev` and updates Claude's history
to the new paths, so nothing depends on the old profile.

## The easy way: let Claude drive

1. Get this folder onto the PC somewhere the new account can read, for example `C:\Users\Public\claude-profile-migration-kit`.
2. Signed in as the **new** account, open the folder in Claude Code (desktop app: pick it as the
   project folder; terminal: `cd` into it and run `claude`).
3. Say: **"Help me migrate my Claude profile from my old Windows account."**

`CLAUDE.md` in this folder tells Claude what to check, what to fill in and in what order. Claude
runs the previews itself. For the steps that change files, it gives you a command to run in a
normal PowerShell window with Claude closed, because those steps rewrite Claude's own data.

## Before you start

- **The new account has to own the old profile folder**, not just be able to open it, or Git will
  refuse your repos. If you're a local admin, run this as the new account in an elevated
  PowerShell (otherwise ask IT):
  ```
  takeown /f "C:\Users\olduser" /r /d y
  icacls "C:\Users\olduser" /grant "NEWDOMAIN\you:(OI)(CI)F" /t /c /q
  ```
- **Ask IT not to delete the old profile.** Windows still thinks it belongs to the old account,
  and profile-cleanup policies would take your repos with it.
- Commit and push everything first.

## Doing it by hand

Copy `migration-settings.example.psd1` to `migration-settings.psd1` and set `OldProfile`. Then,
with Claude fully quit (tray icon, then Quit), run each script once without `-Run` to preview
and once with it:

| Script | What it does |
|---|---|
| `diagnose.ps1` | Read-only. Writes `diagnose-output.txt` showing where Claude's data lives on this profile. |
| `copy-profile.ps1` | Copies `.claude`, `.claude.json`, the desktop app's data, `.gitconfig*` and `.ssh` into the new profile. Anything already there is set aside as `.pre-migration-<timestamp>`, never overwritten. |
| `move-projects.ps1` | Optional. Moves the folders listed in the settings file into a private `Dest` folder and rewrites Claude's history and settings to match. |
| `move-home-root.ps1` | Optional. Moves conversations started from the old home folder itself, and listed loose files, to `Dest\home`. |
| `backup-dev.ps1` | Optional. Zips anything in `Dest` that isn't safely pushed into `OneDrive\Dev-Backup`. |
| `cleanup-pre-migration.ps1` | Optional. Deletes the `.pre-migration-*` leftovers once you're happy. |

Each script is commented, and `CLAUDE.md` has the full walkthrough and a troubleshooting table.

Things that never carry over between Windows accounts, whatever you do: saved sign-ins (Claude,
`gh`, Git Credential Manager, MCP connectors) and user environment variables. Expect to sign in
again. The desktop app's sidebar may also not show copied sessions
([anthropics/claude-code#69585](https://github.com/anthropics/claude-code/issues/69585));
`claude --resume` from a project folder does. To move a conversation back into the desktop app,
resume it in the terminal and type `/desktop`; it continues there. That works one conversation
at a time, so do it for the ones you're still working in.

Tested on Windows 11 with Windows PowerShell 5.1 and the Claude desktop app (MSIX install).
