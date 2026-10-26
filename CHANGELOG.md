# Changelog

User-visible changes to NX Play, `nxplay` and the setup. The format follows [Keep a Changelog](https://keepachangelog.com).

## Unreleased

### Added

- **Console Mode** (toolbar, View › Console Mode ⇧⌘F, or a controller's Menu button): NX Play goes full screen with the games as a carousel of their artwork over a blurred backdrop of the selected one. It lists only the games ready to play, and shows the clock, the connected controller and its battery, and button hints in the controller's own symbols. Games started from it open full screen. B or Esc leaves it.
- **Start games in full screen:** a setting, and `nxplay --fullscreen` (nxnative's `DM_FULLSCREEN`).
- **Controller navigation** in the library and in Console Mode, with any controller macOS supports (Joy-Con, Pro Controller, Xbox, DualShock, DualSense, 8BitDo): the D-pad or left stick moves through the games, A plays or extracts, B backs out, Menu toggles Console Mode.
- **Game menu** in the menu bar with the selected game's commands, the same as its right-click menu, with shortcuts: Play or Extract ⌘↩, Stop or Cancel ⌘., Rebuild ⌘B, Transfer Saves ⇧⌘T, Show in Finder ⇧⌘R.
- **Xcode builds** in Tools › Free Up Space: the copy of the game that Install on Device keeps (`<title ID>_build/xcode-derived-data`, 5–10 GB for a big game). Deleting it only makes the next install slower.
- **Xcode badge** on the icon of games that have that build, next to the IPA badge.
- **List view** for the library, next to the grid (the toolbar switch, or View › as Grid ⌘1 / as List ⌘2). It shows one row per game with its icon, version, title ID, status and Play or Extract button. Like the grid, it has an Extracted section and a Not Extracted section with Extract All, each sortable by any column. The arrow keys move the selection, and double-click and the right-click menu work as on a card. NX Play remembers which view you chose.
- **Make Mac App** (and `nxplay --mac-app`): packs a standalone, double-clickable app of the game into its folder with nxnative's `--platform mac-app`, for the Dock or Launchpad. It's made of APFS clones, so it takes almost no extra space, and it keeps its own save in `~/Library/Application Support/nxnative`. An **App** badge marks games that have one, and the menus can open it or show it in Finder. NX Play itself still plays from the game folder.
- **Show or hide the log** with the toolbar button or View › Show Log (⇧⌘Y). The log opens by itself, on the failed game, when a build or game fails. NX Play remembers whether it's shown and how tall you dragged it.
- `bin/setup` downloads Xcode's Metal Toolchain when it's missing, since every build compiles shaders with it; `bin/setup --check` reports it.

- **Copying…** badge on a game while Finder is still copying it in, either the whole game folder or one of its files. Extract, Rebuild, Install on Device and Build IPA wait until the copy is complete, and the card updates by itself when it is.

### Changed

- Tools › Remove Game Files and Remove IPAs are now one window, **Free Up Space**. It lists every game's files of each kind, selectable one by one, per game or per kind. The full warning about game files shows only when they're selected.
- In the right-click menu, Stop and Cancel moved up next to Play.

### Fixed

- Transfer Saves with no paired device explains how to pair it with this Mac. It used to show every file as "Only on Mac".

## 1.0 — 2026-10-26

First public release.

### NX Play

- A library of the games in a folder, with their icons: extract them, play them on the Mac, rebuild them, Extract All. The selected game's output is shown live, in color.
- **Install on Device:** builds the game with Xcode, signed with your Apple team, then installs and starts it on an iPhone or iPad.
- **Build IPA** for sideloading, with an IPA badge on the game's icon.
- **Transfer Saves** between this Mac and a device. It compares the saves file by file, shows which one is newer, and keeps the replaced save in `run/save-backups`.
- **Tools › Remove Game Files / Remove IPAs** to free space. Game files go only for games built for the Mac, and only after typing "yes, I'm sure".
- Settings for the games folder, nxnative, `prod.keys`, the game language, the Apple team and the Metal performance HUD. **Game Controls** shows the keyboard controls.

### nxplay

- Builds a game once and starts it from the saved launcher afterwards, with `--build-only`, `--rebuild`, `--ipa`, `--device`, `--fps` and `--lang`.
- Updates nxnative before each run, lists the new commits, and rebuilds only when they change files. It also follows upstream force pushes when the checkout has no commits of its own.
- Repairs saved launchers after a game folder or nxnative moves.
- Keeps playing the existing build when a game's original files are gone, instead of failing to rebuild.

### Setup

- `bin/setup` installs everything in one go: Homebrew tools, nxnative's Python packages in a project `.venv` with uv, and a clone of nxnative. Then it builds and installs the app. `--check` only reports what is missing.
