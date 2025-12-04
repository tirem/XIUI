# Party List Performance Analysis

## Summary

Investigation into performance issues reported by users when using the party list, especially with alliances (parties B & C enabled). The party list module has several bottlenecks that scale poorly with member count.

**User Context:** Performance issues reported with party list + alliances enabled. With a full alliance (18 members), the issue is 3x worse than a single party.

---

## Status: PENDING FIXES

Critical and high-priority bottlenecks have been identified. See "Recommended Fix Priority" section below.

---

## Critical Bottlenecks

### 1. GetMemberInformation() Called Twice Per Member Per Frame
**Location:** `partylist.lua:379-406` and `partylist.lua:1341-1351`
**Impact:** CRITICAL

```lua
-- In DrawPartyWindow (line 1341-1351):
for i = firstPlayerIndex, lastPlayerIndex do
    if (party:GetMemberIsActive(i) ~= 0) then  -- Check #1
        partyMemberCount = partyMemberCount + 1
    end
end

-- Then in DrawMember (line 379-406):
local memInfo = GetMemberInformation(memIdx);  -- Calls GetMemberIsActive AGAIN
```

**Problem:**
- `GetMemberIsActive()` called twice for each member (once to count, once in GetMemberInformation)
- `GetPartySafe()` and `GetPlayerSafe()` called inside GetMemberInformation for each member (18 calls total)
- All party member data accessed individually per member instead of batched
- Full alliance = 36+ redundant memory manager lookups/frame

**Fix:** Cache party/player references at DrawWindow start, pass to child functions. Cache active member list once per frame.

---

### 2. getReferenceHeight() Recalculates Every Member Every Frame
**Location:** `partylist.lua:456-468`
**Impact:** CRITICAL

```lua
local function getReferenceHeight(fontSize, fontObj, isNumeric)
    local cacheKey = isNumeric and fontSize or (fontSize .. "_text");
    if not referenceTextHeights[cacheKey] then
        local originalText = fontObj.settings.text;
        fontObj:set_text(refString);  -- SET TEXT (expensive)
        local _, refHeight = fontObj:get_text_size();  -- MEASURE (expensive)
        referenceTextHeights[cacheKey] = refHeight;
        fontObj:set_text(originalText or '');  -- SET TEXT AGAIN
    end
    return referenceTextHeights[cacheKey];
end
```

While this function has a cache, it's called 4 times per member to get reference heights:
```lua
local hpRefHeight = getReferenceHeight(fontSizes.hp, memberText[memIdx].hp, true);
local mpRefHeight = getReferenceHeight(fontSizes.mp, memberText[memIdx].mp, true);
local tpRefHeight = getReferenceHeight(fontSizes.tp, memberText[memIdx].tp, true);
local nameRefHeight = getReferenceHeight(fontSizes.name, memberText[memIdx].name, false);
```

**Problem:**
- Cache lookup 4× per member × 18 members = 72 cache lookups/frame
- Cache miss causes 2× `set_text()` + 1× `get_text_size()` - very expensive GDI operations
- Reference height cache is cleared entirely on any font change (line 1709-1711)

**Fix:** Calculate reference heights once in UpdateVisuals() when fonts change, not during drawing. Store in a simple table indexed by party index.

---

### 3. GetEntitySafe() Called Per Member For Distance
**Location:** `partylist.lua:958-961`
**Impact:** HIGH

```lua
if (not isCasting and gConfig.showPartyListDistance and memInfo.inzone) then
    if memInfo.previewDistance then
        distance = memInfo.previewDistance;
    elseif memInfo.index then
        local entity = GetEntitySafe()  -- CALLED FOR EACH MEMBER
        if entity ~= nil then
            distance = math.sqrt(entity:GetDistance(memInfo.index))
        end
    end
end
```

**Problem:**
- `GetEntitySafe()` involves memory manager access
- Called once per in-zone member with distance enabled
- Up to 18 calls/frame with full alliance and distance enabled

**Fix:** Cache entity reference at DrawWindow start, pass down to DrawMember.

---

### 4. Repeated getScale(), getFontSizes(), getBarScales() Calls
**Location:** Multiple locations in DrawMember and DrawPartyWindow
**Impact:** HIGH

```lua
-- In DrawMember (called per member):
local scale = getScale(partyIndex);           -- Line 408
local fontSizes = getFontSizes(partyIndex);   // Line 445

-- getScale() reads layout config EVERY call:
local function getScale(partyIndex)
    local currentLayout = (gConfig.partyListLayout == 1) and gConfig.partyListLayout2 or gConfig.partyListLayout1;
    -- ... creates new table every call
    return {
        x = currentLayout.partyListScaleX,
        y = currentLayout.partyListScaleY,
        icon = currentLayout.partyListJobIconScale,
    }
end
```

**Problem:**
- These helper functions create new tables EVERY call
- Config access pattern repeated 6 members × 3 helper functions = 18 table allocations/frame per party
- Full alliance = 54 table allocations/frame just for scales

**Fix:** Cache scale/fontSizes/barScales per party at DrawPartyWindow start, pass to DrawMember. Avoid creating new tables - use module-level cached tables.

---

### 5. Selection Box Gradient Drawn With 8 Rectangles Per Targeted Member
**Location:** `partylist.lua:555-581`
**Impact:** MEDIUM-HIGH

```lua
local gradientSteps = 8;
local stepHeight = selectionHeight / gradientSteps;
for i = 1, gradientSteps do
    -- Color interpolation per step
    local r = startColor[1] + (endColor[1] - startColor[1]) * t;
    local g = startColor[2] + (endColor[2] - startColor[2]) * t;
    local b = startColor[3] + (endColor[3] - startColor[3]) * t;
    local alpha = 0.35 - t * 0.25;
    local stepColor = imgui.GetColorU32({r, g, b, alpha});  -- NEW TABLE + conversion
    drawList:AddRectFilled(...);
end
```

**Problem:**
- 8 rectangles drawn per targeted member
- 8 `imgui.GetColorU32()` calls with new table creation each
- Color interpolation math repeated every frame

**Fix:** Pre-calculate gradient colors once when selection colors change. Use ImGui's native gradient support if available, or reduce step count.

---

## High Priority Bottlenecks

### 6. HP Interpolation Logic Runs Every Frame For All 18 Members
**Location:** `partylist.lua:622-758`
**Impact:** HIGH

```lua
-- Initialize interpolation for this member if not set
if not memberInterpolation[memIdx] then
    memberInterpolation[memIdx] = {  -- NEW TABLE
        currentHpp = hppPercent,
        interpolationDamagePercent = 0,
        interpolationHealPercent = 0
    };
end
```

The HP interpolation logic (~135 lines) runs for EVERY member EVERY frame, even when:
- HP hasn't changed
- Interpolation is not active (no recent damage/heal)
- Member is out of zone

**Problem:**
- ~20 conditional checks per member
- Multiple `os.clock()` calls per member
- Math operations for decay calculations even when interpolation is 0

**Fix:** Add early exit when no interpolation is active. Only run interpolation logic when `interpolationDamagePercent > 0` or `interpolationHealPercent > 0`.

---

### 7. GetTargets(), GetSubTargetActive(), GetStPartyIndex() Called Per Member
**Location:** `partylist.lua:337-348`
**Impact:** HIGH

```lua
if (playerTarget ~= nil) then
    local t1, t2 = GetTargets();          -- Memory read operations
    local sActive = GetSubTargetActive();  // Memory read + GetStPartyIndex()
    local stPartyIdx = GetStPartyIndex(); // Memory read (called AGAIN)
    memberInfo.targeted = (t1 == thisIdx and not sActive) or (t2 == thisIdx and sActive);
    memberInfo.subTargeted = (t1 == thisIdx and sActive) or (stPartyIdx ~= nil and stPartyIdx == memIdx);
end
```

**Problem:**
- These functions read from game memory
- `GetStPartyIndex()` called twice per member (in GetSubTargetActive + directly)
- Target info doesn't change per member - same for all 18

**Fix:** Cache target info once at DrawWindow start, pass to GetMemberInformation.

---

### 8. Buff/Debuff Separation Creates New Tables Per Member
**Location:** `partylist.lua:1187-1195`
**Impact:** MEDIUM-HIGH

```lua
local buffs = {};    -- NEW TABLE
local debuffs = {};  -- NEW TABLE
for i = 0, #memInfo.buffs do
    if (buffTable.IsBuff(memInfo.buffs[i])) then
        table.insert(buffs, memInfo.buffs[i]);
    else
        table.insert(debuffs, memInfo.buffs[i]);
    end
end
```

**Problem:**
- 2 new tables allocated per member with buffs
- `table.insert()` causes internal array resizing
- `buffTable.IsBuff()` lookup per buff (~32 buffs × 6 members = 192 lookups)

**Fix:** Pre-allocate and reuse buff/debuff tables. Clear instead of recreate.

---

### 9. deep_copy_table() Used Extensively in UpdateVisuals
**Location:** `partylist.lua:1680-1702`
**Impact:** MEDIUM

```lua
-- For each member whose party's size changed:
local name_font_settings = deep_copy_table(settings.name_font_settings);
local hp_font_settings = deep_copy_table(settings.hp_font_settings);
local mp_font_settings = deep_copy_table(settings.mp_font_settings);
local tp_font_settings = deep_copy_table(settings.tp_font_settings);
local distance_font_settings = deep_copy_table(settings.name_font_settings);
local zone_font_settings = deep_copy_table(settings.name_font_settings);
```

**Problem:**
- 6 deep copies × 18 members = 108 deep copies when all fonts need recreation
- Recursive table traversal for each copy
- Same settings copied repeatedly for each member

**Fix:** Copy font settings once per party (not per member), then modify height only.

---

### 10. ashita_settings.save() Called On Window Move
**Location:** `partylist.lua:1541-1548`
**Impact:** MEDIUM (I/O blocking)

```lua
-- Update if the state changed
if (partyListState == nil or
        imguiPosX ~= partyListState.x or imguiPosY ~= partyListState.y or
        menuWidth ~= partyListState.width or menuHeight ~= partyListState.height) then
    gConfig.partyListState[partyIndex] = { ... };
    ashita_settings.save();  // FILE I/O EVERY FRAME DURING MOVE
end
```

**Problem:**
- Settings saved to disk every frame when window is being moved/resized
- Blocks rendering thread during file I/O
- 3 parties = 3 potential saves per frame during resize

**Fix:** Debounce settings save - only save after move/resize stops (e.g., 0.5s delay).

---

## Medium Priority Bottlenecks

### 11. Color Conversion Every Frame
**Location:** `partylist.lua:550-552`
**Impact:** MEDIUM

```lua
local selectionGradient = GetCustomGradient(...);
local startColor = HexToImGui(selectionGradient[1]);  // String parsing
local endColor = HexToImGui(selectionGradient[2]);    // String parsing
```

**Problem:**
- Hex string parsing every frame for targeted member
- `GetCustomGradient()` creates new table

**Fix:** Cache converted colors, only reconvert when config changes.

---

### 12. Zone Name Lookup Via Resource Manager
**Location:** `partylist.lua:871`
**Impact:** MEDIUM

```lua
local zoneName = encoding:ShiftJIS_To_UTF8(
    AshitaCore:GetResourceManager():GetString("zones.names", memInfo.zone),
    true
);
```

**Problem:**
- Resource manager lookup + encoding conversion per out-of-zone member
- Zone doesn't change frequently

**Fix:** Cache zone names by zone ID.

---

### 13. Job Icon Lookup Per Member
**Location:** `partylist.lua:604`
**Impact:** LOW-MEDIUM

```lua
local jobIcon = statusHandler.GetJobIcon(memInfo.job);
```

The function already caches, but is called per member every frame. Could cache by member index.

---

## Performance Impact Summary

| Rank | Issue | Per-Frame Cost (18 members) |
|------|-------|---------------------------|
| 1 | Redundant GetMemberInformation checks | 36+ memory lookups |
| 2 | getReferenceHeight() cache lookups | 72 cache lookups |
| 3 | GetEntitySafe() for distance | 18 memory lookups |
| 4 | Scale/FontSize helper table allocations | 54 table allocations |
| 5 | Selection gradient rectangles | 8 rectangles × targeted |
| 6 | HP interpolation for inactive members | 20+ conditionals × 18 |
| 7 | Target info recalculation | 54+ memory reads |
| 8 | Buff/debuff table allocations | 12 tables + 192 lookups |
| 9 | deep_copy_table() in UpdateVisuals | 108 recursive copies |
| 10 | Settings save on move | I/O blocking |

---

## Recommended Fix Priority

### Phase 1 - Immediate (Highest Impact)
1. **Cache party/player/entity at DrawWindow start** - Pass to all child functions
2. **Cache target info once per frame** - t1, t2, sActive, stPartyIdx
3. **Cache scale/fontSizes/barScales per party** - Don't recreate tables
4. **Pre-calculate reference heights in UpdateVisuals** - Not during drawing

### Phase 2 - High Value
5. **Early exit HP interpolation** - Skip when no active interpolation
6. **Reuse buff/debuff separation tables** - Clear instead of allocate
7. **Debounce settings save** - Only save after movement stops
8. **Reduce gradient steps or pre-calculate colors**

### Phase 3 - Polish
9. **Cache zone names by ID**
10. **Optimize deep_copy_table usage** - Copy once per party, not per member
11. **Cache selection gradient colors** - Only recalculate on config change
12. **Add member change detection** - Skip unchanged members

---

## Root Causes

1. **No frame-level caching** - Same data fetched repeatedly for each member
2. **Table allocation in hot paths** - Helper functions return new tables
3. **No early exits** - Complex logic runs even when not needed
4. **Per-member operations that should be per-party** - Target info, scales
5. **Synchronous I/O** - Settings saved during rendering

---

## Comparison with Enemy List Fixes

The enemy list module had similar issues that were fixed:

| Pattern | Enemy List Fix | Party List Status |
|---------|---------------|-------------------|
| Regex visibility loops | Numeric index tracking | N/A (different architecture) |
| Table allocations | Reusable tables | **Needs fix** |
| Redundant GetEntitySafe | Single call + cache | **Needs fix** |
| Color caching | Per-enemy cache | Partial (has memberTextColorCache) |
| Name truncation cache | Cache by (name, width) | N/A |
| Party member cache | O(1) lookup | N/A |

The party list can benefit from similar caching strategies but applied to:
- Party/player/entity references
- Target state
- Scale/font configuration
- Reference text heights
- Buff/debuff tables

---

## Estimated Impact

With a full alliance (18 members, 3 parties), implementing Phase 1 fixes should reduce:
- Memory manager calls by ~75%
- Table allocations by ~60%
- Redundant calculations by ~50%

This should significantly improve frame times when alliances are enabled.
