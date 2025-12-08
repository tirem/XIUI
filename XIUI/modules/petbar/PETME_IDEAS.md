# PetMe Addon Feature Ideas

Ideas and implementation details from the PetMe addon (github.com/m4thmatic/PetMe) that could enhance XIUI's petbar.

---

## 1. Charm Duration Calculation (BST)

### Current XIUI Behavior
Shows a heart icon for charmed pets with no duration info.

### PetMe Implementation
Calculates actual charm duration using game mechanics:

```lua
function calculateCharmTime(playerCHR, playerLevel, petLevel, charmGearValue)
    -- Base duration from Charisma stat
    local baseDuration = math.floor(1.25 * playerCHR + 150)  -- in seconds

    -- Level difference modifier
    local levelDiff = playerLevel - petLevel
    local levelModifier = 1.0

    if levelDiff >= 9 then
        levelModifier = 6.00
    elseif levelDiff >= 6 then
        levelModifier = 3.00
    elseif levelDiff >= 3 then
        levelModifier = 1.50
    elseif levelDiff >= 0 then
        levelModifier = 1.00
    elseif levelDiff >= -3 then
        levelModifier = 0.50
    elseif levelDiff >= -6 then
        levelModifier = 0.25
    else
        levelModifier = 0.04
    end

    -- Gear bonus multiplier
    local gearBonus = 1 + (0.05 * charmGearValue)

    -- Final duration
    local charmDuration = math.floor(baseDuration * levelModifier * gearBonus)

    -- Return expiration timestamp
    return os.time() + charmDuration
end
```

### Charm Gear Database
PetMe tracks 45+ gear pieces with charm bonus values (1-7):

```lua
local charmGear = {
    -- Head
    ['Beast Helm'] = 2,
    ['Beast Helm +1'] = 3,
    ['Beastly Helm'] = 3,
    ['Monster Helm'] = 4,
    ['Monster Helm +1'] = 5,
    ['Ankusa Helm'] = 5,
    ['Ankusa Helm +1'] = 6,
    ['Totemic Helm'] = 6,
    ['Totemic Helm +1'] = 7,
    -- Body
    ['Beast Jackcoat'] = 2,
    ['Beast Jackcoat +1'] = 3,
    ['Monster Jackcoat'] = 4,
    ['Monster Jackcoat +1'] = 5,
    -- Hands
    ['Beast Gloves'] = 1,
    ['Beast Gloves +1'] = 2,
    ['Monster Gloves'] = 3,
    ['Monster Gloves +1'] = 4,
    -- Accessories
    ['Beast Whistle'] = 1,
    -- ... etc
}
```

### Benefit for XIUI
- Show "Charm: 5:32" countdown instead of just a heart icon
- Warn when charm is about to expire (flash at <30 seconds)
- More useful for BST players

---

## 2. Jug Pet Database

### Current XIUI Behavior
Shows jug icon with no duration info.

### PetMe Implementation
Database of all 27 jug pets with max level and duration:

```lua
local jugPets = {
    -- 90 minute pets (lower level)
    {name = 'FunguarFamiliar', maxLevel = 35, duration = 90},
    {name = 'SheepFamiliar', maxLevel = 35, duration = 90},
    {name = 'TigerFamiliar', maxLevel = 40, duration = 90},
    {name = 'FlytrapFamiliar', maxLevel = 40, duration = 90},
    {name = 'LizardFamiliar', maxLevel = 45, duration = 90},
    {name = 'MayflyFamiliar', maxLevel = 45, duration = 90},

    -- 60 minute pets (mid level)
    {name = 'EftFamiliar', maxLevel = 50, duration = 60},
    {name = 'BeetleFamiliar', maxLevel = 55, duration = 60},
    {name = 'AntlionFamiliar', maxLevel = 55, duration = 60},
    {name = 'MiteFamiliar', maxLevel = 55, duration = 60},
    {name = 'KeenearedSteffi', maxLevel = 75, duration = 60},
    {name = 'LullabyMelodia', maxLevel = 75, duration = 60},
    {name = 'FlowerpotBen', maxLevel = 75, duration = 60},
    {name = 'FlowerpotBill', maxLevel = 75, duration = 60},
    {name = 'Homunculus', maxLevel = 75, duration = 60},
    {name = 'VoraciousAudrey', maxLevel = 75, duration = 60},
    {name = 'AmbusherAllie', maxLevel = 75, duration = 60},
    {name = 'LifedrinkerLars', maxLevel = 75, duration = 60},
    {name = 'PanzerGalahad', maxLevel = 75, duration = 60},

    -- 30 minute pets (high level)
    {name = 'CourierCarrie', maxLevel = 75, duration = 30},
    {name = 'CraftyClyvonne', maxLevel = 75, duration = 30},
    {name = 'BloodclawShasra', maxLevel = 75, duration = 30},
    {name = 'GorefangHobs', maxLevel = 75, duration = 30},
    {name = 'DipperYuly', maxLevel = 75, duration = 30},
    {name = 'SunburstMalfik', maxLevel = 75, duration = 30},
    {name = 'WarlikePatrick', maxLevel = 75, duration = 30},
    {name = 'ScissorlegXerin', maxLevel = 75, duration = 30},
}

function getJugPetInfo(petName)
    for _, pet in ipairs(jugPets) do
        if pet.name == petName then
            return pet
        end
    end
    return nil
end

function calculateJugDuration(petName)
    local petInfo = getJugPetInfo(petName)
    if petInfo then
        return os.time() + (petInfo.duration * 60)  -- Convert minutes to seconds
    end
    return nil
end
```

### Benefit for XIUI
- Show "Jug: 45:00" countdown for jug pets
- Know exactly when pet will despawn
- Different display for 30/60/90 minute pets

---

## 3. Pet Level Display

### Current XIUI Behavior
No pet level shown.

### PetMe Implementation
```lua
function getPetLevel(playerLevel, petName)
    -- For jug pets, level is min(playerLevel, petMaxLevel)
    local petInfo = getJugPetInfo(petName)
    if petInfo then
        return math.min(playerLevel, petInfo.maxLevel)
    end

    -- For charmed pets, need to track from charm action
    -- (stored when charm succeeds)
    return charmedPetLevel or '??'
end
```

### Benefit for XIUI
- Show "Lv.75 FunguarFamiliar" or "FunguarFamiliar Lv.35"
- Useful for knowing pet effectiveness

---

## 4. Ready Charges Tracking (BST)

### Current XIUI Behavior
Shows Ready timer as single ability.

### PetMe Implementation
BST's Ready ability can accumulate charges (up to 3 with merits):

```lua
function getReadyCharges()
    local recast = AshitaCore:GetMemoryManager():GetRecast()

    -- Ready is ability ID 102, timer ID 102
    local timer = recast:GetAbilityTimer(102)
    local maxCharges = 1 + getMeritLevel('Ready')  -- 1-3 charges

    if timer <= 0 then
        return maxCharges, 0  -- All charges ready
    end

    -- Calculate charges based on recast
    local chargeTime = 30  -- 30 seconds per charge (base)
    local usedCharges = math.ceil(timer / (chargeTime * 60))  -- timer is in frames
    local availableCharges = maxCharges - usedCharges

    return math.max(0, availableCharges), timer
end
```

### Benefit for XIUI
- Show "Ready (2)" when 2 charges available
- Show "Ready (0) 15s" when recharging
- More useful than simple ready/not-ready

---

## 5. Healing Tick Counter

### Current XIUI Behavior
No healing tick tracking.

### PetMe Implementation
Tracks pet HP regen ticks when using "Stay" command:

```lua
local healTickTimer = nil
local HEAL_TICK_INTERVAL = 10  -- seconds

function onPetCommand(command)
    if command == 'Stay' then
        -- Start tracking heal ticks
        healTickTimer = os.time()
    elseif command == 'Follow' or command == 'Attack' then
        -- Stop tracking
        healTickTimer = nil
    end
end

function getNextHealTick()
    if healTickTimer == nil then
        return nil
    end

    local elapsed = os.time() - healTickTimer
    local nextTick = HEAL_TICK_INTERVAL - (elapsed % HEAL_TICK_INTERVAL)
    return nextTick
end
```

### Benefit for XIUI
- Show "Heal: 7s" countdown to next regen tick
- Useful for knowing when to resume combat

---

## 6. Session Persistence

### Current XIUI Behavior
Timers reset on addon reload.

### PetMe Implementation
Saves timestamps to config file:

```lua
-- On charm/jug summon
gConfig.params.charmUntil = os.time() + charmDuration
settings.save()

-- On addon load
function restoreTimers()
    if gConfig.params.charmUntil then
        local remaining = gConfig.params.charmUntil - os.time()
        if remaining > 0 then
            -- Timer still valid, restore it
            charmExpiration = gConfig.params.charmUntil
        else
            -- Timer expired, clear it
            gConfig.params.charmUntil = nil
        end
    end
end
```

### Benefit for XIUI
- Charm/jug timers survive `/addon reload xiui`
- Don't lose tracking on accidental reload
- Could also persist ability recast times

---

## 7. Reward Recast with Modifier

### Current XIUI Behavior
Shows basic Reward timer.

### PetMe Implementation
Tracks Reward with gear modifiers:

```lua
function getRewardRecast()
    local recast = AshitaCore:GetMemoryManager():GetRecast()

    -- Reward is ability ID 103
    local timer = recast:GetAbilityTimer(103)
    local modifier = recast:GetAbilityTimerModifier(103)  -- Gear reduction

    -- Base recast is 90 seconds, gear can reduce
    local effectiveRecast = 90 * (1 - modifier/100)

    return timer, effectiveRecast
end
```

### Benefit for XIUI
- Show accurate recast based on equipped gear
- Account for Reward recast reduction gear

---

## Implementation Priority

### High Value / Low Effort
1. **Jug pet database** - Static data, easy to implement
2. **Pet level display** - Simple calculation
3. **Session persistence** - Just save/load timestamps

### High Value / Medium Effort
4. **Charm duration calculation** - Need CHR stat access, gear tracking
5. **Ready charges tracking** - Need merit level access

### Medium Value / Higher Effort
6. **Healing tick counter** - Need to intercept pet commands
7. **Charm gear database** - Maintenance burden, 45+ items

---

## Data Requirements

### What We Need Access To
| Data | Used For | How to Get |
|------|----------|------------|
| Player CHR stat | Charm duration | `player:GetStat(stat_id)` |
| Player level | Pet level calc | `player:GetMainJobLevel()` |
| Pet level (charmed) | Charm duration | Packet parsing on charm |
| Equipped gear | Charm gear bonus | Inventory/equipment check |
| Merit levels | Ready charges | Memory read |
| Pet commands | Heal tick tracking | Outgoing packet hook |

---

## Notes

- PetMe is Ashita v4 addon, same framework as XIUI
- Most memory access patterns should work the same
- Charm gear list may need updating for HorizonXI-specific items
- Consider making jug database configurable for private server variations
