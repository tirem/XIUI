# XIUI Notifications Module - Implementation Plan

## Overview

A new notifications module that displays game events with animated slide-in/slide-out transitions, configurable timers, and a separate pinned area for persistent invites.

## Notification Types

| Type | Icon Source | Behavior |
|------|-------------|----------|
| Party Invite | `assets/notifications/party.png` | Minifies to pinned area after timeout |
| Trade Invite | `assets/notifications/trade.png` | Minifies to pinned area after timeout |
| Treasure Pool (new item) | Item icon via `GetItemById()` | Fades out after timeout |
| Treasure Pool (lot/pass) | Item icon via `GetItemById()` | Fades out after timeout |
| Item Obtained | Item icon via `GetItemById()` | Fades out after timeout |
| Key Item Obtained | `assets/notifications/keyitem.png` | Fades out after timeout |
| Gil Obtained | `assets/notifications/gil.png` (or existing gil.png) | Fades out after timeout |

---

## File Structure

### New Files
```
XIUI/
├── libs/
│   └── animation.lua                 # Reusable animation/easing library
├── handlers/
│   └── notificationhandler.lua       # Packet parsing for notifications
├── modules/
│   └── notifications/
│       ├── init.lua                  # Module lifecycle
│       ├── data.lua                  # Notification queue/state management
│       └── display.lua               # Rendering logic
├── config/
│   └── notifications.lua             # Config UI
└── assets/
    └── notifications/
        ├── party.png                 # Party invite icon
        ├── trade.png                 # Trade/bazaar icon
        └── keyitem.png               # Key item icon (generic)
```

### Files to Modify
- `XIUI/XIUI.lua` - Register module, add packet handlers
- `XIUI/modules/init.lua` - Export notifications module
- `XIUI/core/settingsdefaults.lua` - Add notification settings
- `XIUI/core/settingsupdater.lua` - Add font propagation
- `XIUI/config.lua` - Add notifications tab

---

## Phase 1: Animation Library (`libs/animation.lua`)

Create reusable animation system for future use:

```lua
-- Core easing functions
animation.easing = {
    linear, easeOutQuad, easeOutCubic, easeInOutQuad,
    easeOutBack, easeOutElastic
}

-- Animator state machine
animation.Animator.create(duration, easing, onUpdate, onComplete)
animation.Animator.update(anim) -- returns false when complete

-- Tween helper
animation.tween(target, property, start, end, duration, easing)

-- Pulse helper (triangle wave for attention effects)
animation.pulse(period, minValue, maxValue)
```

**Pattern source**: `libs/hp.lua` (lines 136-164) for delta time and easing

---

## Phase 2: Data Layer (`modules/notifications/data.lua`)

### Notification States
```
entering -> visible -> exiting -> complete
                   \-> minified (for invites)
```

### Data Structure
```lua
notification = {
    id, type, createdAt, displayDuration,
    state, animationProgress,
    x, y, alpha, scale,
    data = { -- type-specific fields }
}
```

### Queue Management
- `activeNotifications` - Currently displayed (max 5)
- `pinnedNotifications` - Minified invites in separate area
- `pendingQueue` - Waiting to display
- FIFO processing with invite deduplication

---

## Phase 3: Packet Handlers (`handlers/notificationhandler.lua`)

### Packet IDs (need verification during implementation)
| Packet | ID | Notes |
|--------|-----|-------|
| Party Invite | `0x00DC` | Confirmed from other addons |
| Trade Request | `0x0021` | Needs verification |
| Message Basic | `0x0029` | Item/Gil/Key Item via message types |

### Message Types for 0x0029
- Item obtained: `{6, 9, 65, 69, 145, 149}` (verify)
- Key item: `{658, 659}` (verify)
- Gil: `{8, 10, 11}` (verify)

### Treasure Pool
- Use memory API polling via `GetInventorySafe():GetTreasurePoolItem(i)`
- Track state changes for new items and lot updates

---

## Phase 4: Display (`modules/notifications/display.lua`)

### Layout
- **Position**: User configurable (corner + direction)
- **Notifications stack**: In chosen corner, stacking in chosen direction
- **Pinned area**: Separate fixed position (user configurable)

### Animation Timings
- Enter duration: 0.3s (easeOutBack for bounce effect)
- Exit duration: 0.2s (easeInOutQuad)
- Display duration: 3.0s default (user configurable)
- Minify timeout: 10s for invites before going to pinned area

### Rendering
- GDI fonts for all text (mandatory)
- ImGui window for layout/dragging
- ImGui draw list for backgrounds, icons
- Item icons via `D3DXCreateTextureFromFileInMemoryEx` (pattern from `statushandler.lua:63-68`)

---

## Phase 5: Settings (`core/settingsdefaults.lua`)

```lua
-- Visibility toggles
showNotifications = true,
notificationsShowPartyInvite = true,
notificationsShowTradeInvite = true,
notificationsShowTreasure = true,
notificationsShowItems = true,
notificationsShowKeyItems = true,
notificationsShowGil = true,

-- Position
notificationsPosition = 'topright',      -- Corner
notificationsDirection = 'down',         -- Stack direction
notificationsPinnedPosition = {x, y},    -- Pinned area position

-- Timing
notificationsDisplayDuration = 3.0,
notificationsInviteMinifyTimeout = 10.0,
notificationsEnterDuration = 0.3,
notificationsExitDuration = 0.2,

-- Visual
notificationsScale = 1.0,
notificationsSettings = T{
    maxVisible = 5,
    width = 300,
    iconSize = 32,
    font_settings = T{...},
    title_font_settings = T{...},
},

-- Colors
colorCustomization.notifications = T{
    bgColor, borderColor, textColor, subtitleColor,
    partyInviteColor, tradeInviteColor, treasurePoolColor,
    itemObtainedColor, keyItemColor, gilColor,
}
```

---

## Phase 6: Config UI (`config/notifications.lua`)

- Enable/disable toggle
- Position dropdown (corner)
- Direction dropdown (up/down)
- Scale slider
- Display duration slider
- Per-type toggles (party, trade, treasure, items, key items, gil)
- Invite minify timeout slider
- Color pickers for each type

---

## Implementation Order

### Step 1: Foundation
1. Create `libs/animation.lua` with easing functions
2. Create stub `modules/notifications/` structure
3. Add settings to `settingsdefaults.lua`
4. Register module in `XIUI.lua` and `modules/init.lua`

### Step 2: Basic Notifications
1. Implement `data.lua` queue management
2. Implement basic `display.lua` with enter/exit animations
3. Add item icon loading function
4. Test with hardcoded test notifications

### Step 3: Packet Integration
1. Add message packet handler for item/gil/key item
2. Hook into `XIUI.lua` packet_in
3. Test with real game events

### Step 4: Treasure Pool
1. Add treasure pool polling
2. Create treasure notification display
3. Handle lot/pass updates

### Step 5: Invites
1. Add party invite packet handler
2. Add trade invite packet handler
3. Implement minification behavior
4. Create pinned area display

### Step 6: Polish
1. Create config UI
2. Add to config.lua tab system
3. Create/add notification icons
4. Font propagation in settingsupdater.lua
5. Testing and refinement

---

## Key Reference Files

| File | Purpose |
|------|---------|
| `handlers/statushandler.lua:50-71` | D3D texture loading from game resources |
| `libs/hp.lua:136-164` | Delta time, easing patterns |
| `modules/petbar/` | Multi-file module structure |
| `modules/giltracker.lua` | Simple module lifecycle |
| `handlers/debuffhandler.lua` | Message packet handling pattern |
| `core/settingsdefaults.lua` | Settings structure |
| `config/components.lua` | Config UI helpers |

---

## Notes

- Packet IDs need verification during implementation (some from addon research, some need testing)
- Treasure pool uses memory polling, not packet-based
- Item icons come from game resources via `GetItemById().Bitmap`
- Key items don't have icons - use generic key item asset
- Animation library should be generic for reuse in other features
