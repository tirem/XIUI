-- Run from the repository root: luajit tools/test_mob_data.lua
package.path = './XIUI/?.lua;' .. package.path;
package.loaded.common = true;
bit = require('bit');
addon = { path = arg[1] or './XIUI' };
gConfig = { mobInfoDataSource = 'lsb' };
local data = require('modules.mobinfo.data');

assert(data.LoadZone(100));
local amanita = assert(data.GetMobInfo('Amanita'));
assert(amanita.MinLevel == 5 and amanita.MaxLevel == 6);
local immunities = data.GetImmunities(amanita);
assert(immunities.DarkSleep and immunities.LightSleep and not immunities.Sleep);
assert(not data.GetImmunities({ Immunities = 1 }).Sleep);
assert(data.GetImmunities({ Immunities = 0x10000 }).Petrify);
local sheep = assert(data.GetMobInfo('Wild Sheep', 179));
assert(sheep.Name == 'Wild Sheep');
assert(sheep.Scent and not sheep.Blood);

assert(data.LoadZone(140));
assert(data.GetMobInfo('Cyranuce M Cutauleon', 272).MinLevel == 20);
gConfig.mobInfoDataSource = 'phoenix';
assert(data.GetMobInfo('Cyranuce M Cutauleon', 272).MinLevel == 32);
assert(data.GetProvider().Url == 'https://github.com/phoenixffxi/Phoenix/tree/live');
gConfig.mobInfoDataSource = 'lsb';
assert(data.GetMobInfo('Cyranuce_M_Cutauleon').MinLevel == 20);

assert(data.LoadZone(185));
local base = assert(data.GetMobInfo('Vanguard Footsoldier', 82));
gConfig.mobInfoDataSource = 'horizon';
local horizon = assert(data.GetMobInfo('V. Footsoldier', 82));
assert(horizon.Name == 'V. Footsoldier' and horizon.Job == 1 and horizon.MinLevel == 90);
assert(horizon.Aggro == base.Aggro and horizon.Immunities == base.Immunities);
assert(data.GetProvider().Name == 'Horizon');
gConfig.mobInfoDataSource = 'lsb';
assert(data.GetMobInfo('Vanguard Footsoldier', 82).Name == base.Name);
gConfig.mobInfoDataSource = 'phoenix';
assert(data.GetMobInfo('V. Footsoldier', 82).Name ~= 'V. Footsoldier');

assert(not data.LoadZone(999));
assert(not data.GetMobInfo('Amanita', 1));
assert(not data.HasData());
assert(not data.LoadZone(0));
data.Cleanup();
assert(data.GetCurrentZoneId() == 0);
print('Mob data runtime checks passed');
