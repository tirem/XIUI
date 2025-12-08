# Petbar Code Review - Extraction Candidates

Review Date: 2025-12-07

This document identifies code in the petbar module that could be extracted to shared libraries (`libs/`), handlers, or core modules for reuse across XIUI.

---

## HIGH PRIORITY - Significant Duplication

### 1. Background Primitive Management System

**Location:**
- `petbar/data.lua:578-794` - `UpdateBackground()`, `HideBackground()`
- `petbar/pettarget.lua:33-123` - Duplicate `UpdateBackground()`, `HideBackground()`
- `partylist/init.lua:89-151` - Initialize backgrounds
- `partylist/display.lua:1007-1046` - Update backgrounds inline

**Issue:** Three modules (petbar, pettarget, partylist) have nearly identical code for managing window backgrounds with the 5-piece border system. Total duplicated code: ~300+ lines.

**What it does:**
- Manages 5 primitives: `bg`, `tl`, `tr`, `br`, `bl` (background + 4 L-shaped corners)
- Handles theme detection (`Window1-8` vs `Plain` vs `-None-`)
- Calculates border positioning with padding, offset, and scale
- Applies opacity and color tinting to backgrounds/borders
- Uses shared constant: `bgImageKeys = { 'bg', 'tl', 'tr', 'br', 'bl' }`

**Comparison of implementations:**

| Feature | Petbar/Pettarget | Partylist |
|---------|------------------|-----------|
| Theme detection | Yes (`Plain` hides borders) | No (always shows borders) |
| Opacity handling | Separate from color | Combined with color |
| Organization | Dedicated functions | Inline in DrawPartyWindow |
| Instances | 2 windows | 3 windows |

**Suggested extraction:** `libs/windowbackground.lua`

**IMPORTANT - Render Layer Consideration:**

Ashita primitives render in creation order. The API creates primitives in layers:
```
Bottom:  background (bg)
Middle:  [consumer creates their own content here - optional]
Top:     borders (tl, tr, br, bl)
```

```lua
local windowBg = require('libs.windowbackground')

-- ============================================
-- Initialization (in module Initialize)
-- ============================================

-- 1. Create background first (renders at bottom)
local bgPrim = windowBg.createBackground(primData, themeName, bgScale)

-- 2. Consumer creates their middle-layer content here (optional)
-- Petbar: creates pet image primitives
-- Partylist: nothing (or could add party emblems later)

-- 3. Create borders last (render on top)
local borderPrims = windowBg.createBorders(primData, themeName)

-- ============================================
-- Per-frame update (in module DrawWindow)
-- ============================================

-- Update background position/visibility
windowBg.updateBackground(bgPrim, x, y, width, height, {
    theme = 'Window1',        -- '-None-', 'Plain', 'Window1-8'
    padding = 8,              -- horizontal padding
    paddingY = 8,             -- vertical padding (defaults to padding)
    bgScale = 1.0,            -- background texture scale
    bgOpacity = 1.0,          -- background opacity (0-1)
    bgColor = 0xFFFFFFFF,     -- background tint (ARGB)
})

-- Update middle layer content here (if any)
-- ...

-- Update borders position/visibility
windowBg.updateBorders(borderPrims, x, y, width, height, {
    theme = 'Window1',        -- must match background theme
    padding = 8,
    paddingY = 8,
    borderSize = 21,          -- corner piece size
    bgOffset = 1,             -- border offset from background
    borderOpacity = 1.0,      -- border opacity (0-1)
    borderColor = 0xFFFFFFFF, -- border tint (ARGB)
})

-- ============================================
-- Utility functions
-- ============================================

-- Hide primitives
windowBg.hideBackground(bgPrim)
windowBg.hideBorders(borderPrims)

-- Change theme (reloads textures)
windowBg.setBackgroundTheme(bgPrim, themeName, bgScale)
windowBg.setBordersTheme(borderPrims, themeName)

-- Cleanup (in module Cleanup)
windowBg.destroyBackground(bgPrim)
windowBg.destroyBorders(borderPrims)
```

**Implementation notes:**
- Single layered API - consumers decide if they need middle content
- Petbar: uses middle layer for pet images
- Partylist: skips middle layer (could add party emblems/icons later)
- Pettarget: skips middle layer
- Unify theme detection logic (`Plain` hides borders, `Window1-8` shows them)
- Separate opacity from color for consistency
- Handle all three theme types: `-None-`, `Plain`, `Window1-8`

**Impact:**
- Eliminates ~300 lines of duplicated code
- Consistent behavior across all windowed modules
- Easy to add windowed backgrounds to new modules
- Single place to fix bugs or add features (e.g., new themes)

**Note on enemylist:** Uses a simpler pattern - single-color backgrounds per entry (not the 5-piece border system). Could potentially be enhanced to use this lib in the future, but it's a different use case (per-item backgrounds vs per-window backgrounds).

---

### 2. Entity Lookup by Server ID

**Location:** `data.lua:278-287`

**Current code:**
```lua
function data.GetEntityByServerId(sid)
    if sid == nil or sid == 0 then return nil; end
    for x = 0, 2303 do
        local ent = GetEntity(x);
        if ent ~= nil and ent.ServerId == sid then
            return ent;
        end
    end
    return nil;
end
```

**Issue:** This is a generic utility that performs O(n) linear search. Already needed in multiple places (petbar's pet target tracking, debuffhandler, etc.).

**Suggested extraction:** Add to `libs/entity.lua`
```lua
function M.GetEntityByServerId(serverId)
    -- Implementation with caching consideration
end
```

**Note:** Consider whether a cached lookup table would help performance if called frequently.

---

### 3. Ability Recast Memory Reading

**Location:** `data.lua:432-470`

**What it does:**
- Memory scans for `AbilityRecastPointer` using pattern matching
- Reads ability recast timers directly from game memory by ability ID
- Based on PetMe addon's implementation

**Current code:**
```lua
local function InitAbilityRecastPointer()
    local pointer = ashita.memory.find('FFXiMain.dll', 0,
        '894124E9????????8B46??6A006A00508BCEE8', 0x19, 0);
    -- ...
end

local function GetAbilityTimerById(abilityId)
    for i = 1, 31 do
        local compId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        if compId == abilityId then
            local recast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);
            return recast;
        end
    end
    return 0;
end
```

**Suggested extraction:** `libs/recast.lua` (new file)
```lua
local M = {}

-- Initialize memory pointers (lazy, on first use)
function M.Initialize() end

-- Get ability recast by ID (returns frames remaining)
function M.GetAbilityRecastById(abilityId) end

-- Get all ability recasts as table
function M.GetAllAbilityRecasts() end

-- Future: spell recasts if needed
-- function M.GetSpellRecastById(spellId) end

return M
```

**Impact:** Could be useful for any ability cooldown display features.

---

## MEDIUM PRIORITY - Useful Utilities

### 4. Timer Formatting

**Location:** `data.lua:347-357`

**Current code:**
```lua
function data.FormatTimer(frames)
    if frames <= 0 then return 'Ready'; end
    local seconds = frames / 60;
    if seconds >= 60 then
        local mins = math.floor(seconds / 60);
        local secs = math.floor(seconds % 60);
        return string.format('%d:%02d', mins, secs);
    else
        return string.format('%ds', math.floor(seconds));
    end
end
```

**Suggested extraction:** Add to `libs/format.lua`
```lua
-- Convert frames to formatted time string
function M.FormatFramesToTime(frames, readyText)
    readyText = readyText or 'Ready'
    -- Implementation
end

-- Convert seconds to formatted time string (more generic)
function M.FormatSecondsToTime(seconds)
    -- Implementation
end
```

**Note:** Already have `libs/format.lua` with `SeparateNumbers`, `FormatInt`, etc.

---

### 5. Base Window Flags Builder

**Location:** `data.lua:253-266`

**Current code:**
```lua
function data.getBaseWindowFlags()
    if baseWindowFlags == nil then
        baseWindowFlags = bit.bor(
            ImGuiWindowFlags_NoDecoration,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav,
            ImGuiWindowFlags_NoBackground,
            ImGuiWindowFlags_NoBringToFrontOnFocus,
            ImGuiWindowFlags_NoDocking
        );
    end
    return baseWindowFlags;
end
```

**Issue:** This pattern (cached flags combination) is repeated in multiple modules.

**Suggested extraction:** `libs/imgui.lua` or similar
```lua
local M = {}

-- Pre-computed common flag combinations
M.OVERLAY_WINDOW_FLAGS = bit.bor(...)
M.TRANSPARENT_WINDOW_FLAGS = bit.bor(...)

return M
```

---

## LOW PRIORITY - Config/UI Patterns

### 7. Tab Rendering UI Pattern

**Location:** `config/petbar.lua:340-421` and `config/petbar.lua:600-681`

**Issue:** The tab button rendering code (Pet Bar / Pet Target tabs) is duplicated twice - once for settings and once for color settings. Nearly identical ~80 lines each.

**Suggested extraction:** `config/components.lua`
```lua
-- Add tab rendering helper
function components.DrawTabButtons(tabs, selectedIndex, onSelect)
    -- Returns new selectedIndex
    -- Handles styling, underline indicator, etc.
end
```

**Usage would be:**
```lua
state.selectedPetBarTab = components.DrawTabButtons(
    {'Pet Bar', 'Pet Target'},
    state.selectedPetBarTab,
    function(newTab) return newTab end
)
```

---

### 8. Color Config Initialization Pattern

**Location:** `config/petbar.lua:424-561` (many nil checks and defaults)

**Issue:** Large blocks of code ensuring color config tables exist with defaults:
```lua
if gConfig.colorCustomization.petBar == nil then
    gConfig.colorCustomization.petBar = T{ ... }
end
if gConfig.colorCustomization.petBar.borderColor == nil then
    gConfig.colorCustomization.petBar.borderColor = 0xFFFFFFFF;
end
-- etc.
```

**Suggested:** This is partially handled by `settingsdefaults.lua` but the config menu still does defensive checks. Could use a helper:
```lua
function EnsureColorConfig(module, defaults)
    -- Deep merge defaults into gConfig.colorCustomization[module]
end
```

---

## CODE QUALITY OBSERVATIONS

### Things Done Well

1. **Module separation** - Clean split between `data.lua` (state/data), `display.lua` (rendering), `pettarget.lua` (sub-component)

2. **Preview mode pattern** - `GetPetData()` handles preview internally, matching partylist pattern

3. **Color caching** - `lastNameColor`, `lastHpColor` etc. prevent expensive `set_font_color()` calls

4. **Packet handling** - Clean packet parsing in `init.lua:228-268` for pet target tracking

5. **Jug pet database** - Comprehensive lookup table with duration/level info

### Potential Improvements (Not Extraction)

1. **`GetEntityByServerId` performance** - O(n) search every frame for pet target. Consider caching.

2. **`data.petImageTextures`** - Preloads all avatar textures on init. Could lazy-load only when needed.

3. **Magic numbers** - Some hardcoded values like `2303` (max entity index), `60` (frames per second)

---

## SUMMARY TABLE

| Item | Priority | Location | Extract To | Impact |
|------|----------|----------|------------|--------|
| Background Primitives | HIGH | petbar/data.lua, petbar/pettarget.lua, partylist/init.lua, partylist/display.lua | libs/windowbackground.lua | ~300 lines dedup, 3 modules |
| GetEntityByServerId | HIGH | petbar/data.lua | libs/entity.lua | Generic utility |
| Ability Recast Memory | HIGH | petbar/data.lua | libs/recast.lua | Reusable for cooldowns |
| Timer Formatting | MEDIUM | petbar/data.lua | libs/format.lua | Small utility |
| Window Flags | MEDIUM | petbar/data.lua | libs/imgui.lua | Common pattern |
| Tab UI Pattern | LOW | config/petbar.lua | config/components.lua | Config DRY |
| Color Config Init | LOW | config/petbar.lua | config helper | Defensive coding |

---

## RECOMMENDED NEXT STEPS

1. **Start with Background Primitives** - Highest impact, most duplicated code (~300 lines across 3 modules)
   - Create `libs/windowbackground.lua` with unified API
   - Refactor petbar/pettarget first (they have the most complete implementation)
   - Then refactor partylist (minor API changes needed)
2. **Add GetEntityByServerId to entity.lua** - Quick win, simple extraction
3. **Create libs/recast.lua** - Useful for future ability tracking features
4. **Job constants** - Simple but prevents future bugs
