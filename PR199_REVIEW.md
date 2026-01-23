# PR #199 Code Review: Fix profile deletion and detection

**Reviewer Notes** | Jan 22, 2026

## Summary

This PR addresses profile deletion timing issues and adds disk synchronization. The core changes are sound, with a few edge cases worth consideration.

---

## Issues Identified

### 1. ChangeProfile Failure Not Handled (Medium)

**Location:** `XIUI.lua:878-883`

```lua
ChangeProfile(name);

if pendingProfileDeletion then
    profileManager.DeleteProfile(pendingProfileDeletion);
    pendingProfileDeletion = nil;
end
```

**Issue:** If `ChangeProfile()` fails (returns `false`), the deletion still proceeds. The profile has already been removed from `globalProfiles` in `DeleteProfile()` (lines 745-763), so on failure:
- Profile removed from list
- File may or may not be deleted
- User left in undefined state

**Suggestion:** Check return value:
```lua
if ChangeProfile(name) then
    if pendingProfileDeletion then
        profileManager.DeleteProfile(pendingProfileDeletion);
        pendingProfileDeletion = nil;
    end
end
```

---

### 2. Sync Overwrites Custom Profile Order (Design Decision)

**Location:** `profile_manager.lua:227-228`

```lua
table.sort(profiles.names);
table.sort(profiles.order);
```

**Issue:** Users can reorder profiles via MoveProfileUp/MoveProfileDown. Sync forces alphabetical sort, discarding custom order.

**Suggestion:** Only sort newly added profiles, or append to end without sorting:
```lua
-- Alternative: don't sort order, only sort names for display consistency
table.sort(profiles.names);
-- profiles.order keeps user's custom arrangement
```

---

### 3. Sync Doesn't Remove Stale Profiles (Minor)

**Location:** `profile_manager.lua:198-238`

**Issue:** Function adds profiles found on disk but doesn't remove profiles from list whose files were deleted externally.

**Impact:** Low - stale entries would fail gracefully when selected. Consider adding cleanup in future iteration.

---

## Code Quality Notes

### Good

- **Nil-safe color access** (`targetbar.lua:871`) - Correct defensive pattern
- **Migration added** (`migration.lua:497-500`) - Proper versioning for `subtargetBar`
- **Function hoisting** - Moving `GetDefaultWindowPositions()` before first use (line 512) is correct
- **Deferred deletion pattern** - Avoids D3D resource destruction during render

### Minor

- **Extra blank lines** (`XIUI.lua:572-573`) after function removal - cosmetic
- **Centering calculation** (`config.lua:239`) - `GetWindowWidth()` vs `GetContentRegionAvail()` is fine; both work for this use case

---

## Testing Recommendations

1. Delete active profile → verify switch to Default completes before file removal
2. Add profile file manually to disk → run Sync → verify detection
3. Custom-order profiles → run Sync → check if order preserved (current behavior: reset)
4. Delete profile while not active → verify immediate deletion
5. Edge: corrupt/empty profile file → Sync behavior

---

## Verdict

**Approve with minor suggestions.** The deferred deletion logic fixes the original issue. The ChangeProfile failure case (Issue #1) is the most actionable item - low probability but clean fix.
