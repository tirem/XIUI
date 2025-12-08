# Petbar Module Overview

Review Date: 2025-12-07

## Module Structure

```
petbar/
  init.lua      - Entry point, lifecycle (Initialize, UpdateVisuals, DrawWindow, Cleanup)
  data.lua      - State, constants, helpers, pet data, ability timers, background management
  display.lua   - Main pet bar rendering (HP/MP/TP bars, ability icons, BST timers)
  pettarget.lua - Pet target window (separate from main bar)
config/
  petbar.lua    - Config menu with tabs (Pet Bar / Pet Target for both settings and colors)
```

## Overall Assessment: GOOD

The module is well-structured and follows XIUI patterns consistently.

---

## What's Done Well

### 1. Clean Architecture
- Clear separation: data (state/logic) vs display (rendering) vs pettarget (sub-component)
- Entry point (`init.lua`) delegates to sub-modules cleanly
- Follows the partylist pattern for module organization

### 2. XIUI Pattern Compliance
- Uses `FontManager.create/recreate/destroy` correctly
- Preview mode handled inside data functions (like partylist's `GetMemberInformation`)
- Color caching to avoid expensive `set_font_color()` calls
- Proper primitive lifecycle (create in order for layering, cleanup on destroy)

### 3. Comprehensive Features
- Supports all 4 pet jobs: SMN, BST, DRG, PUP
- Per-job ability timer configuration
- Per-avatar image settings (scale, opacity, offset, clipping)
- Session persistence for jug/charm timers
- Separate pet target window with independent theme settings

### 4. Render Layer Handling
- Explicit creation order comment: `background -> pet images -> borders`
- Pet images correctly render between background and borders

### 5. Config Menu
- Well-organized with collapsing sections
- Tab UI for Pet Bar / Pet Target separation
- Per-job settings sections (BST, SMN, DRG, PUP)
- Comprehensive color customization

---

## Items for Future Improvement

### HIGH - Extraction Candidates (see CODE_REVIEW_EXTRACTION.md)
1. **Background primitive system** → `libs/windowbackground.lua`
2. **GetEntityByServerId** → `libs/entity.lua`
3. **Ability recast memory reading** → `libs/recast.lua`

### MEDIUM - Code Quality

#### 1. Debug Print Statement
**Location:** `data.lua:626`
```lua
print('[PetBar] AbilityRecastPointer initialized: ' .. string.format('0x%X', AbilityRecastPointer));
```
Should be removed or wrapped in a debug flag.

#### 2. Tab Rendering Duplication
**Location:** `config/petbar.lua:361-442` and `config/petbar.lua:621-702`

The tab button rendering code is duplicated between `DrawSettings` and `DrawColorSettings`. Could extract to a helper:
```lua
local function DrawTabButtons(tabs, selectedTab, onSelect)
    -- Shared tab rendering logic
end
```

### LOW - Minor Items

#### 1. Unused Variable
**Location:** `data.lua:373`
```lua
data.petImagePrim = nil;  -- Appears unused, petImagePrims (plural) is used
```

#### 2. Hardcoded Fallbacks
Some color fallbacks are hardcoded in multiple places. Could consolidate in settingsdefaults.

---

## Feature Completeness

| Feature | Status | Notes |
|---------|--------|-------|
| SMN Support | Complete | Avatars, spirits, images, BP timers |
| BST Support | Complete | Jug pets, charm tracking, Ready/Sic/Reward |
| DRG Support | Complete | Wyvern, Spirit Link, etc. |
| PUP Support | Complete | Automaton, Deploy/Retrieve, etc. |
| Pet Target | Complete | Separate window, tracks pet's target |
| Preview Mode | Complete | All pet types previewable |
| Background Themes | Complete | -None-, Plain, Window1-8 |
| Color Customization | Complete | Per-component colors, timer categories |
| Timer Persistence | Complete | Survives addon reload |

---

## Recommended Next Steps

1. **Extract background system** - Biggest win, benefits partylist too
2. **Remove debug print** - Quick fix
3. **Extract tab rendering helper** - Reduces config code duplication

---

## Dependencies

- `handlers.helpers` - FontManager, LoadTexture, color helpers
- `libs.progressbar` - Bar rendering
- `libs.color` - ARGBToImGui conversion
- `submodules.gdifonts` - Text rendering
- `primitives` - Ashita primitive objects
- `config.components` - Config UI helpers
