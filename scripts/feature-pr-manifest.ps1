# Shared list: one entry per upstream PR / logical feature (multiple files per commit).
# Paths are fork-relative. create-upstream-pr-branches.ps1 maps to XIUI/<path> for tirem diffs.
function Get-FeaturePRManifest {
    return @(
        @{
            Branch  = 'pr/01-segment-overrides-data'
            Files   = @(
                'modules/hotbar/data.lua',
                'core/settings/factories.lua'
            )
            Subject = 'Crossbar segment overrides: storage, resolution, and defaults'
            Body    = @'
What changed
- data.lua: hotbarCrossbar.segmentOverrides keyed by job and effective combo mode. Job-Shared (jobsegment:…) and Global palette sources resolve before legacy universal override. Draft editing uses draftByKey + draftTouchedKeys for redirected segment buckets; undo tracks touched keys.
- factories.lua: default segmentOverrides = {}; default mpCostAnchor top-left for new hotbar configs.

Why
- Lets per-job crossbar segments point at shared tiers or global palettes without duplicating slot data; supports draft/undo while editing redirects. MP cost corner defaults match top-left unless the user picks another anchor.
'@
        },
        @{
            Branch  = 'pr/02-segment-overrides-palette-hooks'
            Files   = @('modules/hotbar/palette.lua')
            Subject = 'Crossbar palette: rename/delete sync and copy between Job and Global storage'
            Body    = @'
What changed
- When a universal crossbar palette is renamed or deleted, segmentOverrides entries that referenced it (scope=global + globalPalette) are updated or cleared so stale names cannot linger.
- CopyCrossbarPaletteToUniversal: copy a Job/Subjob-tier crossbar palette into the all-jobs universal [G] namespace (overwrite optional); updates universal order/meta when creating a new name.
- CopyUniversalCrossbarPaletteToJob: copy a Global [G] universal palette into a specific Job/Subjob-tier palette (overwrite optional).

Why
- Rename/delete stayed consistent with segment UI. New copy paths support moving palettes between per-job storage and global crossbar storage without manual file editing.
'@
        },
        @{
            Branch  = 'pr/03-segment-overrides-edit-full-palette-ui'
            Files   = @(
                'config/palettemanager.lua',
                'modules/hotbar/crossbar.lua'
            )
            Subject = 'Edit Full Palette UI, Copy Palette flow, and crossbar preview hooks'
            Body    = @'
What changed
- palettemanager.lua: Override/Pet rows, scroll-safe layout, Job-shared copy, clipped preview rows; job label and warnings when editing a palette that is not active; quick palette switcher; crossbar edit appearance decoupled from in-game crossbar visuals; horizontal resize. Copy Palette uses a non-modal ImGui popup (BeginPopup) instead of BeginPopupModal so the fullscreen dim layer is not drawn (hardware cursor stays visible over FFXI). Crossbar Copy To adds destination scope Job/Subjob [J] vs Global [G] with destination lists wired for each mode.
- crossbar.lua: palette editor row APIs, trigger glyphs, editorClipRect passed into DrawSlot for clipped preview.

Why
- Safer editing UX for segment overrides and palette management; copy targets match how data is stored (job-tier vs universal).
'@
        },
        @{
            Branch  = 'pr/04-smn-horizon-bloodpacts-data'
            Files   = @(
                'modules/hotbar/database/horizon_bloodpacts.lua',
                'modules/hotbar/database/horizon_bloodpacts_xiui.lua',
                'modules/hotbar/database/horizonspells.lua',
                'scripts/gen_horizon_bloodpacts.py'
            )
            Subject = 'SMN: Horizon blood pact tables and regen script'
            Body    = @'
What changed
- horizon_bloodpacts.lua / horizon_bloodpacts_xiui.lua: level/MP/labels and XIUI-only overlays (corner icons, astral flow hints) from Horizon data.
- horizonspells.lua: integration hooks as needed.
- gen_horizon_bloodpacts.py: regen source for the Lua tables.

Why
- Blood pact availability and costs match Horizon progression; data can be regenerated when the source tables change.
'@
        },
        @{
            Branch  = 'pr/05-smn-petregistry-bloodpacts'
            Files   = @('modules/hotbar/petregistry.lua')
            Subject = 'SMN: pet registry blood pact merge and lookup'
            Body    = @'
What changed
- Merge retail avatar metadata with horizon_bloodpacts stats and xiui overlays; GetBloodPactByName / RebuildBloodPactIndex for consistent blood pact rows in UI.

Why
- Single place to resolve blood pact display and gating for SMN commands.
'@
        },
        @{
            Branch  = 'pr/06-smn-actions-bloodpacts'
            Files   = @('modules/hotbar/actions.lua')
            Subject = 'SMN: blood pact action resolution and icons'
            Body    = @'
What changed
- BloodPactRage/BloodPactWard handling, GetBloodPactByName integration, icon resolution for blood pact actions.

Why
- Hotbar and macro layers can resolve correct icons and names for pact abilities.
'@
        },
        @{
            Branch  = 'pr/07-hotbar-slotrenderer-bloodpact-and-palette-clip'
            Files   = @(
                'modules/hotbar/slotrenderer.lua',
                'modules/hotbar/display.lua'
            )
            Subject = 'Hotbar slot renderer: blood pact overlays and Edit Full Palette clip'
            Body    = @'
What changed
- Blood pact corner overlays and status icons; when Edit Full Palette sets editorClipRect, slot body respects ImGui clip (D3D slot.png does not clip by itself).
- Default MP cost / Lv / ninjutsu tool (x###) anchor is top-left; display.lua passes the same default when bar settings omit mpCostAnchor.

Why
- Blood pact state is visible on slots; editor preview matches ImGui window bounds; corner MP text aligns top-left unless overridden in settings.
'@
        },
        @{
            Branch  = 'pr/08-smn-bloodpact-assets'
            Files   = @(
                'assets/pets/bloodpact.png',
                'assets/pets/ward.png',
                'assets/hotbar/SMN/AvatarsFavor.png',
                'assets/status/Tetsouou/35.png',
                'assets/hotbar/items/61467.png',
                'assets/hotbar/items/00092.png',
                'assets/hotbar/items/04165.png',
                'assets/hotbar/items/04378.png',
                'assets/hotbar/items/14430.png',
                'assets/hotbar/items/17011.png',
                'assets/hotbar/items/18600.png',
                'assets/hotbar/items/21759.png',
                'assets/hotbar/items/21919.png'
            )
            Subject = 'Assets: SMN blood pact UI icons and additional item icons'
            Body    = @'
What changed
- Icons for blood pact / ward UI and status corners (e.g. Frost Armor).
- Item icons for hotbar/macro display (e.g. 61467, 00092, 04165, 04378, 14430, 17011, 18600, 21759, 21919) under assets/hotbar/items/.

Why
- SMN blood pact / ward visuals plus correct item art for those item ids in macros and hotbar.
'@
        },
        @{
            Branch  = 'pr/09-horizon-static-databases'
            Files   = @(
                'modules/hotbar/database/horizon_abilities.lua',
                'modules/hotbar/database/ws_weapon_types.lua',
                'modules/hotbar/database/horizon_spell_omissions.lua'
            )
            Subject = 'Horizon static databases: abilities, weaponskills, spell omissions'
            Body    = @'
What changed
- horizon_abilities.lua: job ability unlock levels from Horizon progression (including BST pet commands with level gates).
- ws_weapon_types.lua: weaponskill to weapon category, required skill level, relic-only flags.
- horizon_spell_omissions.lua: spell names excluded from Show All (post-75, retail-only, etc.); kept separate from horizonspells.lua so the core spell DB stays untouched.

Why
- Show All and filters can use accurate Horizon rules without editing the main spell DB.
'@
        },
        @{
            Branch  = 'pr/10-playerdata-show-all-and-spell-sort'
            Files   = @('modules/hotbar/playerdata.lua')
            Subject = 'Player data: Show All lists, spell sort, tooltips, and level display'
            Body    = @'
What changed
- Expanded GetAll* helpers for abilities, weaponskills, spells with status tiers and reason strings for hover tooltips.
- Spell sort: within magic type groups, sort by level then name (availability is color-only, not a secondary sort key).
- Magic type helpers and omission filtering for Show All spells.

Why
- Macro editor and hotbar can show consistent availability and readable lists on Horizon.
'@
        },
        @{
            Branch  = 'pr/11-macro-editor-show-all-and-spell-colors'
            Files   = @(
                'modules/hotbar/macropalette.lua',
                'modules/hotbar/macropalette_macroeditor.lua'
            )
            Subject = 'Macro editor: Show All UI, spell colors, Copy, and JA badge sync'
            Body    = @'
What changed
- Show All toggles and filters (magic type, ability job, WS weapon, pet type); two-color spell rows (magic-type color + status color); group headers; hover reasons on unavailable entries.
- Copy: duplicate selected macro into the editor as a new macro entry.
- Main slot icon: implicit refresh on macro text edit no longer forces overwrite; Sync refreshes main icon; tooltips updated.
- JA badge: separate manual vs implicit sync; Sync JA badge clears manual badge overrides and resolves from /ja line; icon picker marks manual badge when Change is used.

Why
- Large lists stay navigable; Copy speeds palette workflows; icon and badge behavior matches user expectations (manual picks are not silently overwritten).
'@
        },
        @{
            Branch  = 'pr/12-xiui-ws-cache-init'
            Files   = @('XIUI.lua')
            Subject = 'XIUI.lua: weaponskill cache on login; job/pet/zone packets when only crossbar is enabled'
            Body    = @'
What changed
- After charSettings load, call SetKnownWeaponskills() so per-character WS cache is populated immediately (Show All WS colors correct on login instead of after zone or equip).
- Pet sync (0x0068), skillchain action tracking (0x0028), zone-in job init (0x00A), zone-out clear (0x00B), and job change (0x001B) run when either keyboard hotbar or controller crossbar is enabled — not only when hotbar is on — so crossbar-only setups still get palette/pet/skillchain updates.

Why
- Before: gating those handlers on hotbar alone left crossbar-only users with stale palettes after job/zone/pet changes and missed skillchain highlights. After: hotbar and crossbar toggles are independent in settings; packet-driven state stays consistent for whichever UI is on.
'@
        },
        @{
            Branch  = 'pr/13-profile-json-and-hotbar-crossbar'
            Files   = @(
                'libs/json.lua',
                'modules/hotbar/palette_json.lua',
                'config/palettemanager.lua',
                'config.lua',
                'modules/hotbar/palette.lua',
                'modules/hotbar/init.lua'
            )
            Subject = 'Profile JSON backup/transfer and independent hotbar vs crossbar (with import refresh)'
            Body    = @'
What changed
- libs/json.lua: JSON encode/decode used by profile export/import.
- palette_json.lua: Whole-profile JSON (all keyboard palettes, all crossbar palettes, macro library); pretty-printed annotations; merge vs replace import; file list + paste; exports folder helpers; post-import hooks call into palette invalidation.
- palettemanager.lua: Per-palette JSON UI removed; palette manager focuses on named palettes only.
- config.lua: Profiles window Backup / Transfer (export/import modal), larger Profiles size, merge/replace and import toggles.
- palette.lua: InvalidateCachesAfterExternalSlotMutation; RefreshActivePaletteVisualsAfterExternalEdit after external edits (e.g. import).
- init.lua: OnPaletteChanged dedupe includes bar/combo id for same-name refreshes so every bar reloads after import; DrawWindow and controller input gate keyboard bars vs crossbar independently (crossbar does not require keyboard hotbar on).

Why
- Before: no structured way to move an entire character’s bars and macros; disabling the keyboard hotbar also hid the crossbar; import could leave the active bar blank until you switched palettes. After: one JSON file per profile for backup or migration; hotbar and crossbar can be enabled separately; imported layouts refresh the visible UI immediately.
'@
        },
        @{
            Branch  = 'pr/14-shared-macro-and-dual-slot-bindings'
            Files   = @(
                'core/shared_macro_store.lua',
                'core/settings/migration.lua',
                'core/settings/user.lua',
                'handlers/statushandler.lua',
                'modules/hotbar/skillchain.lua',
                'modules/hotbar/equipment_ws.lua',
                'modules/hotbar/macro_palette_buckets.lua',
                'modules/hotbar/macro_xiui_defaults.lua'
            )
            Subject = 'Shared macro file, profile scope, and dual profile/shared per-slot bar bindings'
            Body    = @'
What changed
- shared_macro_store.lua: SharedMacros.lua load/save, frozen profile macroDB in shared mode, id separation vs profile hotbar, disk lookup for cross-scope resolution.
- migration.lua, user settings: macroStorageScope default; run MigrateSlotDualMacroBindings; settings hooks.
- statushandler, skillchain, equipment_ws, macro_palette_buckets, macro_xiui_defaults: integration for macro/hotbar behavior.

Why
- One global shared macro library vs per-profile gConfig.macroDB; each physical hotbar/crossbar slot can hold independent macroBindProfile and macroBindShared (active arm follows scope). Deletes, DnD, JSON import, and Edit Full Palette use the same data paths.
'@
        },
        @{
            Branch  = 'pr/15-pet-palette-avatars-elementals-macro-custom-types'
            Files   = @(
                'config/efp_pets_tab.lua',
                'config/hotbar.lua',
                'config/palettemanager.lua',
                'core/settings/factories.lua',
                'modules/hotbar/crossbar.lua',
                'modules/hotbar/data.lua',
                'modules/hotbar/macropalette.lua',
                'modules/hotbar/pet_palette_allowlist.lua',
                'modules/hotbar/petregistry.lua'
            )
            Subject = 'Pet palette: Avatars and Elementals; EFP pet tabs; custom macro type rename, delete, and slot cleanup'
            Body    = @'
What changed
- pet_palette_allowlist.lua: type tokens avatars, elementals, beasts, wyvern, puppet; legacy "summons" still matches avatars+elementals and upgrades in the editor. Slot Configure and Pet Palette use the same names.
- config/efp_pets_tab.lua, palettemanager.lua, crossbar.lua, petregistry.lua: Edit Full Palette pet family tabs (Avatars, Elementals, Beasts, Wyvern, Puppet); avatars vs spirit elementals; SMN sort and pet-bar omit rules.
- config/hotbar.lua, core/settings/factories.lua: help text and defaults for crossbar hotbar parent petPalettePetKeys; comments for the new type tokens.
- macropalette.lua: add custom type (+) only in popup; for the selected custom type, red remove and Rename on the type row; delete confirms macro count; rename modal; delete and rename save paths; custom grid section header uses Elementals for spirit pets.
- data.lua: ApplyMacroPaletteBucketRemovedToSlotAction clears all macro arms bound to a removed custom bucket (profile+shared sweeps) when a custom type is deleted.

Why
- SMN "summons" split into avatars vs elementals for configuration and EFP; macro custom categories can be managed from the type row, with full cleanup of that palette bucket and only affected hotbar/crossbar slots reverted to empty. Slot bindings keep stable storage keys (custom:N) on rename; delete removes the bucket and clears references.
'@
        },
        @{
            Branch  = 'pr/16-crossbar-edit-palette-draft-live-dragdrop'
            Files   = @(
                'XIUI.lua',
                'config/crossbar.lua',
                'config/crossbar_settings.lua',
                'config/hotbar.lua',
                'core/settings/factories.lua',
                'core/settings/migration.lua',
                'core/settings/user.lua',
                'libs/dragdrop.lua',
                'modules/hotbar/crossbar.lua',
                'modules/hotbar/data.lua',
                'modules/hotbar/init.lua',
                'modules/hotbar/macropalette.lua',
                'modules/hotbar/palette.lua',
                'modules/hotbar/slotrenderer.lua',
                'modules/petbar/display.lua',
                'assets/hotbar/items/01105.png',
                'assets/hotbar/items/03100.png',
                'assets/hotbar/items/04270.png',
                'assets/hotbar/items/04576.png',
                'assets/hotbar/items/17040.png'
            )
            Subject = 'Crossbar Edit Full Palette: draft sentinel vs live HUD, deferred drops, and misc UX'
            Body    = @'
What changed
- data.lua / crossbar.lua: Explicit draft-empty sentinel distinguishes cleared palette slots from sparse untouched slots so overlay swap reads no longer resurrect live binds incorrectly; GetCrossbarSlotRawForSwapOverlay for palette row reads; SyncDraftSlotFromLive merges live gConfig into draft after HUD edits while Edit Full Palette is open so palette stays aligned with gameplay binds.
- crossbar.lua / slotrenderer.lua / init.lua / libs/dragdrop.lua: Palette row stays draft-first with overlapping HUD rects resolved via deferred drops + dropPriority; HUD paths keep raw reads/writes on live while palette uses overlay+draft (FlushDeferredDrops before drag renderer).
- config/hotbar.lua, config/crossbar.lua, config/crossbar_settings.lua: Layout/help/settings tweaks bundled with this UX pass.
- core/settings (factories, migration, user): small migrations or defaults aligned with hotbar/crossbar behavior.
- XIUI.lua, modules/hotbar/macropalette.lua, modules/hotbar/palette.lua, modules/petbar/display.lua: Related hooks or wording/visual tweaks touched alongside palette controller separation.

Assets
- Item PNGs under assets/hotbar/items/ for hotbar/macro display ids bundled here.

Why
- Removes duplicate/wrong swap behavior when draft clears overlapped live-only slots; keeps HUD draggable during palette editing without forcing draft icons onto the on-screen bar; overlapping palette/HUD drop zones pick palette deterministically.
'@
        }
    )
}
