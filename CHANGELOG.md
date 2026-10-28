# Changelog

User-visible changes to NX Play, `nxplay` and the setup. The format follows [Keep a Changelog](https://keepachangelog.com).

## Unreleased

### Changed

- **Settings has tabs:** General, Playing, Saves, Devices and Updates. With everything on one page, the window was taller than a laptop screen, and Check Now ended up behind the Dock.

## 1.7 — 2026-10-28

### Added

- **Download and set up from the app:** NX Play comes as a signed, notarized DMG. On first launch **Setup** (NX Play › Setup…) checks the Mac and Xcode, and **Install Missing** installs the Metal Toolchain, Homebrew's tools, Python with nxnative's packages, and nxnative itself. Homebrew is the one thing to install by hand. What Setup installs, apart from Homebrew's tools, goes into `~/Library/Application Support/NX Play`. A copy built from the source keeps using the checkout, as before.
- **Automatic updates** for the downloaded app: NX Play checks GitHub for a new release at launch and once a day, then downloads its DMG and checks it: the checksum GitHub publishes, the developer's signature, and notarization. The update installs when you quit, or now with **Restart to Update** (Settings › Updates, or the banner), which waits until no game or build is running. Copies built from the source update with `git pull` and `bin/install`.
- **Save backup to a private Git repository** (Settings): pick a clone of your own repository. While a game plays, NX Play copies its save into a folder named after the game and its title ID each time the game saves, then commits and pushes. It does this once more when the game quits. If another Mac pushed in the meantime, its commits are pulled in first. Pushing uses your own Git credentials, and each backup shows in the log.

### Changed

- **`bin/install` replaces a running NX Play safely.** It used to swap the app out from under a running game or build. Now it asks NX Play to quit once nothing is running in it (games, builds, Free Up Space deletions, save transfers), waits until it has, installs, and reopens it. Ctrl-C while it waits cancels the install and leaves NX Play open. NX Play 1.6 and older don't respond, so quit those by hand once.

### Fixed

- **A build no longer plays against files another build rewrote.** Install on Device, Build IPA and Make Mac App build in the same folder as the Mac build, and rewrite its patched game code and shader tables with the nxnative they run. If one of them pulled an nxnative update, the next Play skipped the rebuild and started the old Mac host with the new files. `nxplay` now records the nxnative code each Mac build was made with, in `start_mac.sh`, and rebuilds when the checkout's differs, whichever run pulled it. Builds made before this change don't have that record yet and pick it up at their next rebuild.
- **Keep This Build protects the build from those other builds too.** While a game is kept, Install on Device, Build IPA and Make Mac App are disabled, and `nxplay --ipa`, `--mac-app` and `--device` refuse to run. Turn off Keep This Build to use them.
- Console Mode keeps the game tiles in the middle of the screen. They used to jump up whenever a build's progress bar appeared under the selected game.

## 1.6 — 2026-10-27

### Added

- **Keep This Build** (Game menu and right-click menu): keeps a game that works from being rebuilt when nxnative updates, since an update can break a game that played fine. A lock badge marks it on the icon, and `nxplay` plays the kept build as it is, saying it does so without the new nxnative changes. Rebuild (`nxplay --rebuild`) still replaces it. It's a `keep` file in `<title ID>_build`.
- **Console Mode starts at the game you played last:** the carousel lists games by when you last played them, newest first, then the ones you haven't played yet by name. Below the title it shows when you last played the selected game. `nxplay` records the time when a game starts and when it ends, in `<title ID>_build/run/last_played`, so plays from the Terminal count too.
- **Progress on the Dock icon:** a bar along the bottom of NX Play's icon while extractions, rebuilds, IPAs or installs run (their average when there are several). A **!** badge marks a build that failed while NX Play was in the background, until you open it again.
- **Allow a Metal compiler nxnative didn't test** (Settings, and `nxplay --allow-other-metal`). nxnative now stops every build when Xcode's Metal compiler isn't the version it tested its shaders with, and a newer Xcode than that is common. The setting is off by default, as nxnative's. When a build stops for this reason, NX Play points to the setting, and `bin/setup --check` reports the mismatch.

## 1.5 — 2026-10-26

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
