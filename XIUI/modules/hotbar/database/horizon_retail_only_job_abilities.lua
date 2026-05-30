-- Job abilities and pet-style commands that exist on retail but are omitted on HorizonXI progression.
-- Used to filter HasAbility-driven JA lists and `/ja` macro availability so retail-only rows never read as usable here.
-- Level 76+ abilities generally never appear on Horizon due to level cap; this covers sub-cap retail additions.

return {
    ['Bestial Loyalty'] = true,
    ['Feral Howl'] = true,
    ['Killer Instinct'] = true,
    ['Unleash'] = true,
    ['Snarl'] = true,
    ['Spur'] = true,
    ['Run Wild'] = true,
};
