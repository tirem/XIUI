<img width="800" height="200" alt="XIUIBANNER" src="https://github.com/user-attachments/assets/5a7fd14c-adb1-4a4c-8fb0-0f28c804120c" />
<a href="https://discord.gg/PxsTH7ZR97"><img width="800" height="133" alt="Discord" src="https://github.com/user-attachments/assets/8b11b946-7b6d-402c-b19d-a3c24021dddc" /></a>

Contains the following elements:
* Player Bar
* Target Bar (w/ Target of Target and Buffs & Debuffs)
* Party List (w/ Buffs & Debuffs)
* Enemy List (w/ Buffs & Debuffs)
* Cast Bar
* Exp Bar
* Inventory Tracker
* Gil Tracker
* Configuration UI for all elements

<img width="1913" height="1072" alt="image" src="https://github.com/user-attachments/assets/c0c3e8db-d0bd-4522-87ff-ebafafcfe8d8" />

***INSTALLATION***
* Download the latest release of XIUI by [visiting our release page](https://github.com/tirem/XIUI/releases).
* Extract the downloaded **XIUI-release.zip** file.
* Once extracted, you will have a directory called XIUI-release.  Open up this directory, and inside of it will be a directory called XIUI.
* Copy the XIUI directory to your Ashita addons folder, located at `..\addons`.
* To manually load XIUI, type `/addon load XIUI` in the Final Fantasy XI client.
* To configure XIUI, type `/xiui`.

***FOR HORIZON XI***
* It is recommended that you follow these steps to load XIUI by default:
    * Open up the file `default.txt` in the `HorizonXI\Game\scripts` folder.
    * Navigate to the section titled "Plugin and Addon Configurations"
    * After the `/wait 3` line, and below the block of `=======`, add the following line:
        * `/addon load xiui`
    * Save this file.  XIUI should automatically load when you start Final Fantasy XI.

***UPGRADING FROM HXUI***

This addon was recently renamed from HXUI to XIUI. Your settings will be automatically migrated on first load.

1. Download the latest XIUI release
2. Delete your old `HXUI` folder from your addons directory
3. Extract the new `XIUI` folder into your addons directory
4. Load the addon with `/addon load xiui`

You'll see a message in chat confirming the migration: `[XIUI] Successfully migrated settings from HXUI.`

***UPDATING NOTES***

It is recommended to delete the `XIUI` folder in your addons directory before upgrading to a new version, as asset directories may change during development.
