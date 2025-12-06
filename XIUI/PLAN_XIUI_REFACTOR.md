# XIUI.lua Refactoring Plan

## Current State Analysis

**File Size:** ~2360 lines, ~30,000+ tokens
**Key Issues:**
1. Massive inline settings definitions (~820 lines for `user_settings` + `default_settings`)
2. Large migration code blocks (~300+ lines) that run on every load
3. Repetitive font settings propagation code (~150 lines in `UpdateUserSettings`)
4. Duplicated party settings structures (partyA/B/C are 90% identical)
5. Legacy settings that should have been removed
6. Module-specific visual update functions that follow identical patterns

---

## Proposed Modularization

### 1. Extract Settings Definitions → `settings_defaults.lua` (NEW)

**Lines to move:** 118-821 (`user_settings`) + 828-1260 (`default_settings`)

**What it contains:**
- `user_settings` table (all user-configurable options)
- `default_settings` table (internal module defaults)
- `defaultUserSettings` copy for reset functionality

**Benefits:**
- Removes ~1140 lines from XIUI.lua
- Settings are easier to review/modify in isolation
- Single source of truth for defaults

**Example structure:**
```lua
-- settings_defaults.lua
local gdi = require('gdifonts.include');

local M = {};

M.user_settings = T{
    patchNotesVer = -1,
    -- ... all user settings
};

M.default_settings = T{
    currentPatchVer = 2,
    -- ... all default settings
};

return M;
```

---

### 2. Extract Settings Migration → `settings_migration.lua` (NEW)

**Lines to move:** 1265-1607 (all migration code)

**What it contains:**
- `MigrateFromHXUI()` function
- Party list layout migration (old → partyListLayout1/2)
- Per-party migration (old → partyA/B/C)
- Per-party color migration
- Individual setting migrations (targetBar settings, etc.)

**Benefits:**
- Removes ~340 lines from XIUI.lua
- Migration logic is isolated and easier to maintain
- Can eventually be deprecated/removed when users have migrated

**Example structure:**
```lua
-- settings_migration.lua
local M = {};

function M.MigrateFromHXUI()
    -- existing code
end

function M.MigratePartyListSettings(gConfig, defaults)
    -- existing partyListLayout1/2 migration
end

function M.MigratePerPartySettings(gConfig, defaults)
    -- existing partyA/B/C migration
end

function M.MigrateColorSettings(gConfig, defaults)
    -- existing color migration
end

function M.RunAllMigrations(gConfig, defaults)
    M.MigrateFromHXUI();
    M.MigratePartyListSettings(gConfig, defaults);
    M.MigratePerPartySettings(gConfig, defaults);
    M.MigrateColorSettings(gConfig, defaults);
    -- individual field migrations
end

return M;
```

---

### 3. Extract Settings Update Logic → `settings_updater.lua` (NEW)

**Lines to move:** 1697-1954 (`UpdateUserSettings` function)

**What it contains:**
- `UpdateUserSettings()` - applies user settings to adjusted settings
- `GetFontWeightFlags()` helper (if not already in helpers.lua)
- Font family/weight/outline propagation logic

**Benefits:**
- Removes ~260 lines from XIUI.lua
- Complex calculation logic is isolated
- Easier to test and modify

**Refactoring opportunity:** The font propagation code is extremely repetitive:
```lua
-- Current (repeated ~30 times):
gAdjustedSettings.targetBarSettings.name_font_settings.font_family = us.fontFamily;
gAdjustedSettings.targetBarSettings.name_font_settings.font_flags = fontWeightFlags;
gAdjustedSettings.targetBarSettings.name_font_settings.outline_width = us.fontOutlineWidth;
```

Could become:
```lua
-- Proposed helper:
local function applyGlobalFontSettings(fontSettings, family, flags, outlineWidth)
    fontSettings.font_family = family;
    fontSettings.font_flags = flags;
    fontSettings.outline_width = outlineWidth;
end

-- Usage:
applyGlobalFontSettings(gAdjustedSettings.targetBarSettings.name_font_settings, us.fontFamily, fontWeightFlags, us.fontOutlineWidth);
```

---

### 4. Consolidate Party Settings Template

**Current issue:** `partyA`, `partyB`, `partyC` in `user_settings` are 95% identical (lines 251-414).

**Proposed solution:** Create a factory function:
```lua
local function createPartyDefaults(overrides)
    local defaults = T{
        layout = 0,
        showDistance = false,
        distanceHighlight = 0,
        showJobIcon = true,
        jobIconScale = 1,
        -- ... all common settings
    };
    if overrides then
        for k, v in pairs(overrides) do
            defaults[k] = v;
        end
    end
    return defaults;
end

-- Usage:
partyA = createPartyDefaults(),
partyB = createPartyDefaults({ scaleX = 0.7, scaleY = 0.7, jobIconScale = 0.8, entrySpacing = 6, showTP = false }),
partyC = createPartyDefaults({ scaleX = 0.7, scaleY = 0.7, jobIconScale = 0.8, entrySpacing = 6, showTP = false }),
```

**Benefits:**
- Reduces ~100 lines of duplication
- Changes to defaults only need to happen in one place
- Makes differences between parties explicit and easy to see

---

### 5. Remove Legacy Settings

**Lines to remove:** 450-597 (legacy settings that are marked for removal)
- `partyListLayout` (line 451)
- `partyListDistanceHighlight` through `partyListBorderColor` (lines 452-470)
- `partyListLayout1` (lines 473-530)
- `partyListLayout2` (lines 532-597)

These are only kept for migration and can be removed once migration code handles them.

**Note:** This requires ensuring migration code runs BEFORE these are accessed and that migrated settings are saved.

---

### 6. Clean Up Module Visual Update Functions

**Current pattern (lines 1980-2018):**
```lua
function UpdatePlayerBarVisuals()
    SaveSettingsOnly();
    playerBar.UpdateVisuals(gAdjustedSettings.playerBarSettings);
end

function UpdateTargetBarVisuals()
    SaveSettingsOnly();
    targetBar.UpdateVisuals(gAdjustedSettings.targetBarSettings);
end
-- ... repeated 8 times
```

**Proposed refactor:**
```lua
local function createVisualUpdater(module, settingsKey)
    return function()
        SaveSettingsOnly();
        module.UpdateVisuals(gAdjustedSettings[settingsKey]);
    end
end

UpdatePlayerBarVisuals = createVisualUpdater(playerBar, 'playerBarSettings');
UpdateTargetBarVisuals = createVisualUpdater(targetBar, 'targetBarSettings');
-- etc.
```

Or expose a single generic function:
```lua
function UpdateModuleVisuals(moduleName)
    SaveSettingsOnly();
    local moduleMap = {
        playerBar = { module = playerBar, settings = 'playerBarSettings' },
        targetBar = { module = targetBar, settings = 'targetBarSettings' },
        -- etc.
    };
    local m = moduleMap[moduleName];
    if m then m.module.UpdateVisuals(gAdjustedSettings[m.settings]); end
end
```

---

## Summary of Changes

| New File | Lines Moved | Purpose |
|----------|-------------|---------|
| `settings_defaults.lua` | ~1140 | Default settings definitions |
| `settings_migration.lua` | ~340 | Migration code |
| `settings_updater.lua` | ~260 | UpdateUserSettings logic |

| Refactoring | Lines Affected | Impact |
|-------------|----------------|--------|
| Party settings factory | ~160 | Reduces duplication |
| Remove legacy settings | ~150 | Cleaner defaults |
| Visual update consolidation | ~40 | DRY pattern |

**Estimated final XIUI.lua size:** ~400-500 lines (down from ~2360)

---

## Implementation Order

1. **Extract `settings_defaults.lua`** - Lowest risk, pure extraction
2. **Extract `settings_migration.lua`** - Self-contained, runs once per load
3. **Consolidate party settings** - Reduces settings_defaults.lua size
4. **Remove legacy settings** - After confirming migration works
5. **Extract `settings_updater.lua`** - Higher complexity, depends on step 1
6. **Consolidate visual update functions** - Optional cleanup

---

## Testing Checklist

- [ ] Fresh install works (no existing settings)
- [ ] Existing settings migrate correctly
- [ ] HXUI migration still works
- [ ] Settings reset (`ResetSettings()`) works
- [ ] All UI modules render correctly
- [ ] Font changes propagate to all modules
- [ ] Hot reload still works (dev mode)
- [ ] Settings save/load correctly across sessions
