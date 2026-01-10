--[[
* XIUI Fast Cast Utilities
* Fast cast calculation for spell casting
]]--

require('common');

local M = {};

-- ========================================
-- Shared Spell Lists
-- ========================================
-- Cure spells that benefit from WHM Cure Speed trait
M.CURE_SPELLS = T{ 'Cure','Cure II','Cure III','Cure IV','Cure V','Cure VI','Full Cure','Curaga','Curaga II','Curaga III','Curaga IV','Curaga V' };

-- ========================================
-- RDM Fast Cast Trait Tiers
-- ========================================
-- RDM gains Fast Cast at levels 15, 35, 55 (76 and 89 beyond 75-cap)
-- Each tier provides cumulative cast time reduction
M.RDM_FAST_CAST_TIERS = {
    { level = 15, reduction = 0.10 },  -- Fast Cast I: 10%
    { level = 35, reduction = 0.15 },  -- Fast Cast II: 15%
    { level = 55, reduction = 0.20 },  -- Fast Cast III: 20%
};

-- ========================================
-- Helper: Get RDM Fast Cast by Level
-- ========================================
-- Returns the fast cast reduction for RDM at the given level
-- @param rdmLevel: RDM job level
-- @return: Fast cast reduction (0.0 to 0.20 for 75-cap)
function M.GetRDMFastCastByLevel(rdmLevel)
    if not rdmLevel or rdmLevel < 15 then
        return 0;
    end

    local fastCast = 0;
    for _, tier in ipairs(M.RDM_FAST_CAST_TIERS) do
        if rdmLevel >= tier.level then
            fastCast = tier.reduction;
        else
            break;
        end
    end
    return fastCast;
end

-- ========================================
-- Fast Cast Calculation
-- ========================================
-- Calculates total fast cast percentage based on job, subjob, and spell info
-- Returns the fast cast multiplier (0.0 to 0.80, clamped)
-- @param mainJob: Main job ID (1-22)
-- @param subJob: Sub job ID (1-22)
-- @param spellType: Magic skill type (33=Healing, 40=Singing, etc.) - optional
-- @param spellName: Spell name string - optional (for cure speed check)
-- @param mainJobLevel: Main job level - optional (for RDM sub fast cast calculation)
-- @param subJobLevel: Sub job level - optional (for RDM sub fast cast calculation)
function M.CalculateFastCast(mainJob, subJob, spellType, spellName, mainJobLevel, subJobLevel)
    if not gConfig.castBarFastCastEnabled then
        return 0;
    end

    local fastCast = 0;

    -- RDM main job: Use level-based Fast Cast trait
    if mainJob == 5 and mainJobLevel then
        fastCast = fastCast + M.GetRDMFastCastByLevel(mainJobLevel);
    -- Non-RDM main job: Use user config value
    elseif (gConfig.castBarFastCast and mainJob and gConfig.castBarFastCast[mainJob]) then
        fastCast = fastCast + (gConfig.castBarFastCast[mainJob] or 0);
    end

    -- WHM main job + Healing Magic (skill 33) = Cure Speed bonus (multiplicative with fast cast)
    if (mainJob == 3 and spellType == 33) then
        if (spellName and M.CURE_SPELLS:contains(spellName)) then
            local cureSpeed = gConfig.castBarFastCastWHMCureSpeed or 0;
            fastCast = 1 - ((1 - fastCast) * (1 - cureSpeed));
        end
    -- BRD main job + Singing (skill 40) = Singing Speed bonus (multiplicative with fast cast)
    elseif (mainJob == 10 and spellType == 40) then
        local singSpeed = gConfig.castBarFastCastBRDSingSpeed or 0;
        fastCast = 1 - ((1 - fastCast) * (1 - singSpeed));
    end

    -- RDM sub-job fast cast bonus (level-based)
    -- Sub job level determines which Fast Cast tier is available
    if subJob == 5 and subJobLevel then
        fastCast = fastCast + M.GetRDMFastCastByLevel(subJobLevel);
    end

    -- Clamp fast cast to prevent negative/inverted results
    return math.min(fastCast, 0.80);
end

return M;
