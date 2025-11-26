![HXUI Banner](https://user-images.githubusercontent.com/124013059/220467961-2bcd7ec4-02bc-4ef1-92c5-1ddd98cfc0ac.png)
[![HXUI Discord](https://user-images.githubusercontent.com/124013059/220468014-bb680d46-3083-452e-803f-20f1385c7e72.png)](https://discord.gg/qepeymYw9y)

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

![HXUI Screenshot](https://user-images.githubusercontent.com/124013059/220468124-38323cf6-f6a8-40f8-860c-4420f9632130.png)

***INSTALLATION***
* Download the latest release of HXUI by [visiting our release page](https://github.com/tirem/HXUI/releases).
* Extract the downloaded **HXUI-release.zip** file.
* Once extracted, you will have a directory called HXUI-main.  Open up this directory, and inside of it will be a directory called HXUI.
* Copy the HXUI directory to your Ashita addons folder, located at `HorizonXI\Game\addons`.
* To manually load HXUI, type `/addon load HXUI` in the Final Fantasy XI client.
* To configure HXUI, type `/hxui`.

***FOR HORIZON XI***
* It is recommended that you follow these steps to load HXUI by default:
    * Open up the file `default.txt` in the `HorizonXI\Game\scripts` folder.
    * Navigate to the section titled "Plugin and Addon Configurations"
    * After the `/wait 3` line, and below the block of `=======`, add the following line:
        * `/addon load hxui`
    * Save this file.  HXUI should automatically load when you start Final Fantasy XI.

***UPDATING NOTES***
1) This addon has been recently renamed from ConsolidatedUI to HXUI. If you are upgrading from ConsolidatedUI and would like to keep your old config from before please rename the folder "consolidatedui" in game/config/addons/ to "hxui"
2) It is recommended to delete the "HXUI" folder in game/addons before upgrading to a new version as asset directories may change during development
