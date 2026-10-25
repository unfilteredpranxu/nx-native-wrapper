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
./nxplay ~/Games/MetroidDread -l ja        # extra options go to build_ipa_from_nsp.py
```

Each run starts with `git pull` in nxnative. If new commits come in, the game is rebuilt.

The run command is saved in `<game folder>/<title ID>_build/start_mac.sh`.
