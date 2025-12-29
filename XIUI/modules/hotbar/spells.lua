--[[
* XIUI hotbar - Spells Data
* Contains spell definitions with icon mappings
]]--

local spells = {};

-- White Magic Spells
spells.whiteMagic = {
    ['Cure'] = {
        id = 1,
        name = 'Cure',
        icon = '00086.png',
        type = 'WhiteMagic',
        element = 'Light',
        castTime = 2.0,
        mpCost = 8,
        range = 12,
        recast = 5,
        levels = {
            WHM = 1,
            RDM = 3,
            SCH = 5,
            PLD = 5
        },
        command = '/ma "Cure" <t>'
    },
    ['Cure II'] = {
        id = 2,
        name = 'Cure II',
        icon = '00087.png',
        type = 'WhiteMagic',
        element = 'Light',
        castTime = 2.25,
        mpCost = 24,
        range = 12,
        recast = 5.5,
        levels = {
            WHM = 11,
            RDM = 14,
            SCH = 17,
            PLD = 17
        },
        command = '/ma "Cure II" <t>'
    },
    ['Cure III'] = {
        id = 3,
        name = 'Cure III',
        icon = '00088.png',
        type = 'WhiteMagic',
        element = 'Light',
        castTime = 2.5,
        mpCost = 46,
        range = 12,
        recast = 6,
        levels = {
            WHM = 21,
            RDM = 26,
            SCH = 30,
            PLD = 30
        },
        command = '/ma "Cure III" <t>'
    }
};

-- Get spell by name
function spells.getSpell(name)
    -- Check white magic
    if spells.whiteMagic[name] then
        return spells.whiteMagic[name];
    end
    
    -- Add more spell types here later (black magic, blue magic, etc.)
    
    return nil;
end

-- Get all spells available for a job at a given level
function spells.getSpellsForJobLevel(job, level)
    local availableSpells = {};
    
    -- Check white magic spells
    for name, spell in pairs(spells.whiteMagic) do
        if spell.levels[job] and spell.levels[job] <= level then
            table.insert(availableSpells, spell);
        end
    end
    
    -- Add more spell types here later
    
    return availableSpells;
end

return spells;
