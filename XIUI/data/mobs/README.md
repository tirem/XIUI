# Mob data

XIUI loads offline Lua snapshots generated from [LandSandBoat](https://github.com/LandSandBoat/server)
and [Phoenix's live branch](https://github.com/phoenixffxi/Phoenix/tree/live).
Select the provider under **Target Bar → Mob Info → Display Options → Mob Data Source**.
The dropdown offers LandSandBoat, Phoenix, and Horizon. LandSandBoat is the default
for the regular build; Horizon is the default for the Horizon build. Existing Horizon
checkbox settings migrate to the matching dropdown selection.

Release downloads include the generated data. Git checkouts must generate it once using
the commands below before loading XIUI. Generated datasets are ignored by Git; source
pins and the importer are tracked. The release workflow generates data from those pins
before making the regular and Horizon packages.

The snapshots require no network connection or YAML parser in Ashita. Only the current
zone is loaded. Entity indices select spawn-specific jobs and levels; names provide a
fallback with the combined level range. Reserved spawns without a template are omitted.
Missing zones and mobs return no information.

The importer merges ecosystem, family, species, template, and spawn attributes in order.
Phoenix also applies the enabled YAML data modules from `modules/init.txt` in order,
including era, Dynamis, and Limbus changes. Lua scripts, runtime modifiers, and private
server configuration are outside these snapshots.

Physical and elemental damage adjustments become damage multipliers. Elemental resistance
ranks stay separate; Mob Info labels them with the magic evasion change LSB applies per rank. Immunities use
`data/enums/immunity.yaml`, including distinct light/dark sleep flags. Detection includes
true sight, true hearing, low HP, and scent tracking.

Each provider's `source.json` records the upstream branch, commit, enabled YAML modules,
and coverage. Source pins are in `tools/mob_data_sources.json`. LSB/Phoenix data is licensed
under GPL-3.0-or-later; the generator includes `COPYING` from the repository license.
Horizon compatibility data retains its MIT attribution.

## Building and updating

Run from the repository root with Python 3.10 or later:

```sh
python -m pip install -r tools/requirements-mob-data.txt
python tools/update_mob_data.py
```

This downloads the pinned sources and generates all three providers, including Horizon
overrides. The local output also works through a symlink into an Ashita addon directory.
To advance the pins to LandSandBoat's `base`, Phoenix's `live`, and the Horizon overlay's
`main` branch heads:

```sh
python tools/update_mob_data.py --refresh
```

To regenerate one provider from a local checkout of its pinned commit:

```sh
python tools/update_mob_data.py --provider phoenix --source /path/to/Phoenix
```

Commit changed source pins and importer code. Generated files stay out of commits and PRs.
Release packaging downloads the pinned sources and includes the generated files, so users
installing release archives need no build tools or internet connection to load Mob Info.

To generate into a separate packaging directory:

```sh
python tools/update_mob_data.py --output /path/to/package/XIUI/data/mobs
```

## Horizon compatibility

The generator extracts name, job, and level overrides from
[Mr-Sithel's overlay](https://github.com/Mr-Sithel/HorizonXI-Dynamis-Mobdb/tree/eb301032372ab28171378569e707c5bdeb5b9006).
Its remaining fields come from LandSandBoat. Selecting **Horizon** applies a zone's overlay
when that file exists; zones without an overlay use LandSandBoat data. It has no submodule
or dependency on the MobDB addon. See `horizon/NOTICE.md` for attribution.
