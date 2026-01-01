# Pet-Aware Hotbar Palette System Implementation Plan

## Problem Statement
Pet classes (SMN, DRG, PUP, BST) need hotbars that change based on the active pet. Summoner is especially challenging because each of the 14 avatars has completely different Blood Pacts.

## User Requirements
1. **Both auto-switch AND manual cycling** - Hotbars auto-switch when pet changes, but users can also manually cycle
2. **Per-avatar palettes for Summoner** - Each avatar (Ifrit, Shiva, etc.) gets its own hotbar configuration
3. **Per-bar toggle** - Each hotbar independently enables/disables pet-aware mode
4. **Fall back to base job palette** - When no pet active, show regular job-specific actions

## Solution: Extended Storage Key System

### Storage Key Format
```
"{jobId}:{petCategory}:{petName}"
```

Examples:
- `"15:avatar:ifrit"` - SMN with Ifrit
- `"15:avatar:shiva"` - SMN with Shiva
- `"14:wyvern"` - DRG with wyvern
- `"18:automaton"` - PUP with automaton
- `"9:jug:funguarfamiliar"` - BST with jug pet
- `"15"` - SMN with no pet (base palette)
- `"global"` - Non-job-specific

### Fallback Resolution Order
```
1. "{jobId}:{petCategory}:{petName}"  -- Full pet-specific key
2. "{jobId}"                          -- Base job palette
3. "global"                           -- If not job-specific
```

## Implementation Plan

### Phase 1: Core Infrastructure

#### 1.1 Create `modules/hotbar/petregistry.lua` (NEW FILE ~80 lines)
Centralized pet name-to-key mapping, reusing data from petbar:
```lua
local PetRegistry = {
    avatars = {  -- petName -> key
        ['Carbuncle'] = 'carbuncle', ['Ifrit'] = 'ifrit', ...
    },
    spirits = {
        ['Fire Spirit'] = 'fire', ['Ice Spirit'] = 'ice', ...
    },
    jobPetCategories = {
        [15] = { 'avatar', 'spirit' },  -- SMN
        [14] = { 'wyvern' },             -- DRG
        [18] = { 'automaton' },          -- PUP
        [9]  = { 'jug', 'charm' },        -- BST
    },
};

function PetRegistry.GetPetKey(petEntity, jobId)
    -- Returns "avatar:ifrit", "wyvern", "jug:funguarfamiliar", etc.
end
```

#### 1.2 Create `modules/hotbar/petpalette.lua` (NEW FILE ~150 lines)
Pet detection and palette state management:
```lua
local state = {
    currentPet = nil,           -- Current pet key
    manualOverrides = {},       -- [barIndex] = paletteKey
    cycleIndices = {},          -- [barIndex] = index
};

function petpalette.CheckPetState()
    -- Called on packet hint, verifies via GetPetSafe()
    -- Compares to lastKnownPet, triggers OnPetChanged if different
end

function petpalette.CyclePalette(barIndex, direction)
    -- Manual cycling through available palettes
end

function petpalette.ClearManualOverride(barIndex)
    -- Return to auto mode
end

function petpalette.GetPaletteDisplayName(barIndex)
    -- Returns "Ifrit", "Wyvern", etc. for indicator
end
```

#### 1.3 Modify `modules/hotbar/data.lua` (~50 lines changed)
Extend storage key resolution:
```lua
-- NEW: Build storage key with pet awareness
function data.GetStorageKeyForBar(barIndex)
    local barSettings = gConfig['hotbarBar' .. barIndex];
    local jobId = M.jobId or 1;

    if barSettings.jobSpecific == false then
        return 'global';
    end

    if not barSettings.petAware then
        return tostring(jobId);
    end

    -- Check manual override first
    local manualPalette = petpalette.GetManualOverride(barIndex);
    if manualPalette then
        return manualPalette;
    end

    -- Auto-detect current pet
    local petKey = petpalette.GetCurrentPetKey();
    if petKey then
        return string.format('%d:%s', jobId, petKey);
    end

    return tostring(jobId);
end

-- NEW: Get available palettes for cycling
function data.GetAvailablePalettes(barIndex)
    local barSettings = gConfig['hotbarBar' .. barIndex];
    local palettes = {};
    for key, _ in pairs(barSettings.slotActions or {}) do
        table.insert(palettes, key);
    end
    table.sort(palettes);
    return palettes;
end
```

### Phase 2: Detection & Events

#### 2.1 Modify `modules/hotbar/init.lua` (~30 lines)
Integrate pet detection into packet handling:
```lua
local petpalette = require('modules.hotbar.petpalette');

-- In HandlePacketIn:
if e.id == 0x0068 then  -- Pet sync packet
    ashita.tasks.once(0.3, function()
        petpalette.CheckPetState();
    end);
end

if e.id == 0x000B then  -- Zone packet
    petpalette.CheckPetState();  -- Will detect no pet
end

-- In HandleCommand - add palette commands:
-- /xiui hotbar cycle [barIndex] [direction]
-- /xiui hotbar auto [barIndex]
```

### Phase 3: Display Updates

#### 3.1 Modify `modules/hotbar/display.lua` (~40 lines)
Add palette indicator overlay:
```lua
local function DrawPaletteIndicator(barIndex, x, y, settings)
    if not settings.showPetPaletteIndicator then return; end
    local barSettings = gConfig['hotbarBar' .. barIndex];
    if not barSettings.petAware then return; end

    local paletteName = petpalette.GetPaletteDisplayName(barIndex);
    local isManual = petpalette.HasManualOverride(barIndex);

    -- Draw small indicator above hotbar showing "Ifrit", "Wyvern", etc.
    -- Yellow border if manual override active
end
```

#### 3.2 Modify `modules/hotbar/crossbar.lua` (~20 lines)
Same pet-awareness for crossbar - uses same `data.GetStorageKeyForBar()`.

### Phase 4: Configuration

#### 4.1 Modify `core/settings/factories.lua` (~15 lines)
Add new default settings:
```lua
-- Per-bar settings
petAware = false,               -- Enable pet-aware palettes
petPaletteMode = 'both',        -- 'auto' | 'manual' | 'both'
perAvatarPalettes = true,       -- SMN: per-avatar vs shared

-- Global hotbar settings
showPetPaletteIndicator = true,
clearOverrideOnPetChange = true,
```

#### 4.2 Modify `config/hotbar.lua` (~80 lines)
Add pet palette configuration UI:
- **Per-bar section**: "Pet Palettes"
  - Checkbox: "Enable Pet-Aware Palettes"
  - Dropdown: Mode (Auto/Manual/Both)
  - Checkbox: "Per-Avatar Palettes" (SMN only)
  - List: Defined palettes with delete buttons

- **Global section**: "Pet Palette Settings"
  - Checkbox: "Show Palette Indicator"
  - Checkbox: "Clear Override on Pet Change"

#### 4.3 Modify `modules/hotbar/macropalette.lua` (~60 lines)
Add palette selector to macro palette view:
- Dropdown showing all defined palettes + "Auto" option
- Button to create new palette for specific pet

### Phase 5: Commands & Polish

#### 5.1 Chat Commands
```
/xiui hotbar cycle [barIndex] [direction]  -- Cycle palette
/xiui hotbar auto [barIndex]               -- Return to auto mode
```

## Files Summary

| File | Action | Estimated Lines |
|------|--------|-----------------|
| `modules/hotbar/petregistry.lua` | CREATE | ~80 |
| `modules/hotbar/petpalette.lua` | CREATE | ~150 |
| `modules/hotbar/data.lua` | MODIFY | ~50 |
| `modules/hotbar/init.lua` | MODIFY | ~30 |
| `modules/hotbar/display.lua` | MODIFY | ~40 |
| `modules/hotbar/crossbar.lua` | MODIFY | ~20 |
| `modules/hotbar/macropalette.lua` | MODIFY | ~60 |
| `core/settings/factories.lua` | MODIFY | ~15 |
| `config/hotbar.lua` | MODIFY | ~80 |

**Total: ~525 lines** (2 new files, 7 modified files)

## Pet Detection Strategy

**Reliable detection via entity check, not packet alone:**
1. Packet 0x0068 (Pet Sync) triggers check
2. Verify via `GetPetSafe()` entity lookup
3. Compare pet name to registry
4. Only switch after entity confirms pet exists

This avoids premature switching if summon fails (interrupted, no MP, etc.)

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Pet dies | Entity check returns nil, fall back to base job |
| Player zones | Clear pet state on zone packet |
| Player dies | Pet dismissed, entity returns nil |
| JA fails | Entity never appears, no switch occurs |
| Manual then pet changes | Option to clear override or keep it |
| No palettes defined | Fall back to base job storage key |

## Testing Plan

1. Test SMN with multiple avatars - verify each gets own palette
2. Test DRG with wyvern - single palette
3. Test BST with jug pets - per-pet palettes
4. Test PUP with automaton - single palette
5. Test manual cycling - keybind/command works
6. Test auto+manual - manual override, then pet change
7. Test edge cases - pet death, zone, failed summon
