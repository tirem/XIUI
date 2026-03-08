<img width="800" height="200" alt="XIUIBANNER" src="https://github.com/user-attachments/assets/5a7fd14c-adb1-4a4c-8fb0-0f28c804120c" />
<a href="https://discord.gg/PxsTH7ZR97"><img width="800" height="133" alt="Discord" src="https://github.com/user-attachments/assets/8b11b946-7b6d-402c-b19d-a3c24021dddc" /></a>

A modern UI replacement addon for Final Fantasy XI (Ashita v4). XIUI replaces the default HUD elements with clean, customizable alternatives — all configurable in-game via `/xiui`.

## Features

- **Player Bar** — HP, MP, TP with job and level display
- **Target Bar** — Target info with target-of-target, buffs, and debuffs
- **Party List** — Full party display with buffs and debuffs
- **Enemy List** — Nearby engaged enemies with debuff tracking
- **Cast Bar** — Spell/ability cast progress
- **Cast Cost** — MP/TP cost display for actions
- **Pet Bar** — Pet HP, TP, and target info
- **Hotbar** — Configurable action bar with controller/crossbar support
- **EXP Bar** — Experience and limit point progress
- **Inventory** — Bag capacity across all storage types
- **Gil Tracker** — Current gil display
- **Mob Info** — Mob level, type, and aggro info
- **Treasure Pool** — Loot display with lot/pass support
- **Notifications** — On-screen alerts for game events

## Install

1. Download the latest release from the [releases page](https://github.com/tirem/XIUI/releases)
2. Extract the zip and copy the `XIUI` folder into your Ashita `addons` directory
3. In-game: `/addon load xiui`
4. Configure: `/xiui`

To auto-load on startup, add `/addon load xiui` to your Ashita script or profile.

## Update

1. Delete the existing `XIUI` folder from your addons directory
2. Extract the new release in its place

Deleting first is recommended — asset paths may change between versions.
