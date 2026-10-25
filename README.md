# nx-native-wrapper

`nxplay` builds a Switch game for the Mac with [nxnative](https://github.com/seedds/nxnative) once, then starts it from the saved run command instead of rebuilding.

## Setup

Check this repo out next to nxnative, in the same parent folder:

```
projects/
├── nxnative/            # https://github.com/seedds/nxnative
└── nx-native-wrapper/   # this repo
```

Put your keys in `~/.switch/prod.keys`.

To keep the repos elsewhere, set `NXNATIVE=/path/to/nxnative`. To use another keys file, set `NX_KEYS=/path/to/prod.keys`.

## Usage

```sh
./nxplay ~/Games/MetroidDread              # start the game, or build it first if needed
./nxplay --rebuild ~/Games/MetroidDread    # force a rebuild
./nxplay --build-only ~/Games/MetroidDread # build if needed, don't start
./nxplay --ipa ~/Games/MetroidDread        # build the iOS IPA into the game folder, to sideload
./nxplay --device <udid> ~/Games/MetroidDread --team-id <team>   # build with Xcode, install and start on a device
./nxplay --fps ~/Games/MetroidDread        # show the Metal performance HUD
./nxplay --lang ja ~/Games/MetroidDread    # play in another language (DM_LANG), no rebuild
./nxplay ~/Games/MetroidDread -l ja        # extra options go to build_ipa_from_nsp.py
```

Each run starts with `git pull` in nxnative. If new commits come in, the game is rebuilt.

The run command is saved in `<game folder>/<title ID>_build/start_mac.sh`. It holds absolute paths, so after you move a game folder (or nxnative), the next run rewrites them to the new location.

## Controls

| Key | Switch button |
| --- | --- |
| W A S D | Left stick |
| Arrow keys | D-pad |
| J / K / U / I | A / B / X / Y |
| Q / E | L / R |
| Z / C | ZL / ZR |
| F / G | Press left stick / press right stick |
| Return / Tab | + / − |
| Space | Shake the controller (while held) |
| Left mouse button | Touchscreen |
| ⌃⌘F | Toggle full screen |
| ⌘Q | Quit the game |

Controllers are detected automatically, with buttons by position (right A, bottom B, top X, left Y). Extra controllers become extra players for local co-op.

## NX Play.app

A macOS app that runs `nxplay` for you. Pick the games folder (one subfolder per game). It shows the extracted games with their icons and the rest with an Extract button. Extract All builds them one after another, and the panel at the bottom shows the selected game's output.

```sh
bin/build        # generate the project and build build/Build/Products/Release/NX Play.app
bin/install      # build and install into /Applications (or: bin/install ~/Applications)
mise run app     # build and open it
mise run test    # NXPlayKit tests
```

To work in Xcode, run `mise run generate` and open `NXPlay.xcodeproj`. The code lives in the `Packages/NXPlayKit` Swift package. The app finds nxnative next to this checkout. You can change that and the keys file in Settings.
