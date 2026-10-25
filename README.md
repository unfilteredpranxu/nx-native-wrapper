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
./nxplay --fps ~/Games/MetroidDread        # show the Metal performance HUD
./nxplay ~/Games/MetroidDread -l ja        # extra options go to build_ipa_from_nsp.py
```

Each run starts with `git pull` in nxnative. If new commits come in, the game is rebuilt.

The run command is saved in `<game folder>/<title ID>_build/start_mac.sh`.

## NX Play.app

A macOS app that runs `nxplay` for you. Pick the games folder (one subfolder per game). It shows the extracted games with their icons and the rest with an Extract button. Extract All builds them one after another, and the panel at the bottom shows the selected game's output.

```sh
bin/build        # generate the project and build build/Build/Products/Release/NX Play.app
bin/install      # build and install into /Applications (or: bin/install ~/Applications)
mise run app     # build and open it
mise run test    # NXPlayKit tests
```

To work in Xcode, run `mise run generate` and open `NXPlay.xcodeproj`. The code lives in the `Packages/NXPlayKit` Swift package. The app finds nxnative next to this checkout. You can change that and the keys file in Settings.
