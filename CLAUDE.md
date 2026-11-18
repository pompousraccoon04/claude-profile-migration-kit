# Claude profile migration: instructions for Claude

You are helping the user carry their Claude Code and Claude desktop history, Git config and SSH
keys from an old Windows account to a new one, typically after their account moved to a new
domain (`OLDDOMAIN\user` with profile `C:\Users\user` becomes `NEWDOMAIN\user` with profile
`C:\Users\user.NEWDOMAIN`). Optionally, you then help move their projects out of the old profile
so nothing depends on it. The scripts in this folder do the work; your job is to inspect the
machine, fill in `migration-settings.psd1`, run the previews, and walk the user through the rest.

## Ground rules

- **You run previews; the user runs `-Run`.** Every script except `diagnose.ps1` prints what it
  would do unless given `-Run`. The `-Run` steps rewrite Claude's own data, so they refuse to
  start while any `claude` process is running, including this session. Give the user the exact
  command for a normal PowerShell window, tell them to quit Claude first (tray icon, then Quit;
  closing the window is not enough), and pick up again when they reopen Claude and paste the output.
- Commands for the user always use `powershell -ExecutionPolicy Bypass -File "<full path to script>"`,
  with this folder's full path filled in.
- Don't open transcript contents, `.credentials.json`, keys, tokens or `.env` files. Folder names,
  file names and counts are all you need.
- Nothing here deletes the old profile. Don't suggest deleting it; the user decides that once
  everything works, and some IT departments do it for them on a schedule (see step 1).

## Step 0. Work out where things stand

1. Compare `$env:USERPROFILE` and `whoami` with the folders in `C:\Users`. The old profile is
   usually the same user name without the domain suffix, and has a `.claude` folder. Confirm it
   with the user.
2. If `migration-settings.psd1` doesn't exist, copy it from `migration-settings.example.psd1` and
   set `OldProfile`.
3. Check whether the copy already happened: does the new profile's `.claude\projects` hold about
   as many `*.jsonl` files as the old one? If so, skip to step 3.

## Step 1. Prerequisites

Check each and tell the user plainly which are missing.

- **The new account must own the old profile, not just have access.** Git refuses repos owned by
  another account ("detected dubious ownership"), and the copy needs to read everything. Check
  with `(Get-Acl <OldProfile>).Owner`. To fix, the user (if they're a local admin) or IT runs
  this signed in as the new account, in an elevated PowerShell:
  ```
  takeown /f "C:\Users\olduser" /r /d y
  icacls "C:\Users\olduser" /grant "NEWDOMAIN\user:(OI)(CI)F" /t /c /q
  ```
- **The old profile must survive.** Windows still registers it to the old account, and many
  domains delete profiles unused for N days, which would take the repos with it. The user should
  ask IT to exclude it, or do the optional move (step 4) soon.
- **Work is pushed.** If you can still reach the old account's repos, list any with uncommitted
  changes, unpushed commits, stashes or worktrees (`.git\worktrees`) so the user can push first.
  Use `git -c safe.directory=* ...` so ownership doesn't block the check.
- **Wrap up on the old account.** Anything done there after the copy won't carry over.

## Step 2. Copy Claude, Git and SSH into the new profile

1. Run `diagnose.ps1` and read the `diagnose-output.txt` it writes. It shows which Claude data
   folders exist on this profile. The desktop app (MSIX install) uses `%LOCALAPPDATA%\Claude-Data`
   if that folder has anything in it, otherwise `%APPDATA%\Claude`.
2. Run `copy-profile.ps1` (preview). Check that the desktop-data source and target look right and
   the counts are plausible, then explain to the user what it will set aside and copy.
3. Hand over the `-Run` command. When the user comes back, the two sides of each count line in
   its summary must match.

What it does: anything the new profile already has (`.claude`, `.claude.json`, the Claude app
folders, `.ssh`, `.gitconfig*`) is renamed with a `.pre-migration-<timestamp>` suffix, never
merged or overwritten. It copies `~\.claude`, `~\.claude.json`, the desktop app data (minus
caches, VM image, binaries, sign-in tokens and cookies), `.gitconfig*` and `.ssh`. It grants the
new account read access to SSH files that only granted the old one, and rewrites
`IdentityFile` paths in `.ssh\config` to `~/.ssh/...`.

## Step 3. Verify

Walk the user through these, one at a time:

- **Claude:** start the app and sign in to the same Claude account and org (session files are
  stored per account). Known limit: the desktop sidebar may not show copied sessions
  ([anthropics/claude-code#69585](https://github.com/anthropics/claude-code/issues/69585)).
  `cd` into a project and run `claude --resume`; it should list that project's past sessions.
- **Git:** `git status` and `git fetch` in a repo. Git Credential Manager asks to sign in once.
- **SSH:** `ssh -T git@github.com`, and any other host in `~\.ssh\config`. Re-add keys with
  `ssh-add` if they used an agent.
- **Other sign-ins:** `gh auth login`, MCP connectors in Claude, anything else with saved logins.
  None of these carry over between Windows accounts.

At this point the user can keep opening projects from the old profile path and stop here. Steps
4 and 5 are for users who want everything off the old profile.

## Step 4 (optional). Move projects to a private folder such as `C:\dev`

1. Inventory the old profile's top-level folders. Leave out dot-folders, `AppData`, `OneDrive*`
   and the standard shell folders (Desktop, Documents, Downloads, Music, Pictures, Videos,
   Favorites, Links, Contacts, Searches, Saved Games, 3D Objects). For each remaining folder, note
   whether it is a Git repo and whether `.claude\projects` has a history folder for it (Claude
   names those after the path with every non-alphanumeric character turned into `-`, so
   `C:\Users\olduser\myrepo` is `C--Users-olduser-myrepo`).
2. Look at `.claude\projects` for history folders that don't start with the old profile's encoded
   path, such as `C--tmp-...`. That suggests a second place with projects; ask whether to include
   it as `OtherRoot`.
3. Show the user the proposed lists, get their confirmation, and write them into
   `HomeFolders`, `OtherRoot` and `OtherFolders`. `Dest` must be on the same drive as the old profile.
4. Run `move-projects.ps1` (preview). Every row should say `move`. If it warns that `Dest` was
   created by another account, the user must move its contents out first, since only the
   creating account can make it private.
5. Before the `-Run`: the user restarts the PC and signs in **only** as the new account (the old
   account's programs hold files open otherwise), quits Claude, and closes editors and terminals.
6. Afterwards, check with `cd <Dest>\<some project>` and `claude --resume`.

What it does: creates `Dest` readable only by the user, SYSTEM and Administrators; renames
profile folders into it (instant, same drive); copies-then-deletes `OtherRoot` folders so they
pick up the private permissions; renames the matching history folders; updates the `cwd` field
in those transcripts (message text untouched); rewrites old paths in `~\.claude.json`,
`~\.claude\settings*.json`, `~\.claude\history.jsonl` and `claude_desktop_config.json` after
saving originals to `claude-config-before-move-<timestamp>`; runs `git worktree repair`.

Left for the user, which you should list for them afterwards:
- Python virtual environments (the script lists them) store their own path; delete and recreate.
- Shortcuts, scheduled tasks and editor "recent" lists pointing at old paths.
- User environment variables set on the old account don't exist on the new one. Ask which they
  set (you can grep the moved projects for the old profile path to find likely ones).
- Don't work on moved projects from the old account; its Claude history still has old paths.

## Step 5 (optional). Home-folder conversations and files

Conversations started from the old home folder itself (history folder named exactly after the
old profile, e.g. `C--Users-olduser`) match no project, so step 4 leaves them. List the loose
non-dot files directly in the old profile, ask which are work files, write them into `HomeFiles`,
then preview `move-home-root.ps1` and hand over its `-Run`. It moves them and those conversations
to `<Dest>\home`.

Then list the old profile's dot-files and dot-folders that weren't copied (tool configs, tokens,
certificates, `.bash_history` and so on) by name only, and ask which the user still uses. Those
are read from the home folder, so they belong in the new profile, not in `Dest`.

## Step 6 (optional). Housekeeping

- `backup-dev.ps1 -List` shows which folders in `Dest` exist only on this PC (not Git, no remote,
  unpushed or uncommitted). Without `-List` it zips them into `OneDrive\Dev-Backup`. Warn the user
  the zips include `.env` files.
- `cleanup-pre-migration.ps1` lists the `.pre-migration-*` leftovers; `-Run` deletes them
  permanently. A set-aside `.claude` with conversations not in the live one is kept. If the user
  made an SSH key on the new account before migrating, it's in `.ssh.pre-migration-*`; check first.
- The `claude-config-before-*` folders are the user's settings backups. They delete those by hand
  when happy.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Close Claude first...` / `Claude is still running` | Quit from the tray icon, or end `claude.exe` in Task Manager, then rerun. |
| `You're signed in as the old account` | Sign out and back in as the new account. |
| `Can't find or read ...\.claude` | Wrong `OldProfile`, or the new account doesn't own the old profile yet (step 1). |
| `Counts don't match` | Don't delete anything. Rerunning is safe: it sets the partial copy aside and copies again. |
| Git: `detected dubious ownership` | Ownership wasn't transferred (step 1). Stopgap: `git config --global --add safe.directory <repo path with forward slashes>`. |
| SSH: `UNPROTECTED PRIVATE KEY FILE` | `icacls "$HOME\.ssh\<key>" /inheritance:r /grant:r "${env:USERDOMAIN}\${env:USERNAME}:F"` |
| Claude opens with no chats | The app may be using the other data folder. Run `diagnose.ps1`; if the populated folder isn't the one the app uses, quit Claude and rerun `copy-profile.ps1 -Run` (its first lines name the target). Also confirm the same Claude account and org. |
| A folder shows `IN USE` | A program has files open. Restart, sign in only as the new account, rerun. |

**Undo:** steps 2 and 3 change nothing in the old profile except the read access on a few SSH
files: delete the new copies and rename the `.pre-migration-*` items back. Step 4 has no
automatic undo: move folders back, restore settings from `claude-config-before-move-<timestamp>`,
and rename the history folders back. The original transcripts are still in the old profile's
`.claude`.
