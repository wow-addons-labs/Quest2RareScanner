-----------------------------------------------------------------------
-- Quest2RareScanner Questie data access
-----------------------------------------------------------------------

local ADDON_NAME, ns = ...

local L = ns.L
local Data = {}
ns.Data = Data

local function GetDB()
    return _G.LibQuestieDB
end

local function NpcExists(npcID)
    npcID = tonumber(npcID)
    if not npcID or npcID <= 0 then
        return false
    end
    local db = GetDB()
    return db and db.Npc and db.Npc.Exists and db.Npc.Exists(npcID) or false
end

local function NpcName(npcID)
    local db = GetDB()
    if db and db.Npc and db.Npc.Get then
        local name = db.Npc.Get(npcID, "name")
        if name then
            return name
        end
    end
    return tostring(npcID)
end

-- Classify Questie position data into a user-facing label.
-- A single spawn point with no waypoint data is called "fixed single point";
-- this is a heuristic, because Questie may simply lack patrol data.
local function GetPositionTag(npcID)
    local db = GetDB()
    if not db or not db.Npc or not db.Npc.Get then
        return L.POS_UNKNOWN
    end

    local spawns = db.Npc.Get(npcID, "spawns")
    local waypoints = db.Npc.Get(npcID, "waypoints")

    local spawnSet = {}
    local spawnCount = 0
    if type(spawns) == "table" then
        for areaID, coords in pairs(spawns) do
            if type(coords) == "table" then
                for _, coord in ipairs(coords) do
                    if type(coord) == "table" and coord[1] and coord[2] then
                        local key = tostring(areaID) .. ":" .. string.format(
                            "%.2f-%.2f",
                            tonumber(coord[1]) or 0,
                            tonumber(coord[2]) or 0
                        )
                        if not spawnSet[key] then
                            spawnSet[key] = true
                            spawnCount = spawnCount + 1
                        end
                    end
                end
            end
        end
    end

    local patrolPaths = 0
    if type(waypoints) == "table" then
        for _, paths in pairs(waypoints) do
            if type(paths) == "table" then
                for _, path in ipairs(paths) do
                    if type(path) == "table" then
                        local pointSet = {}
                        local pointCount = 0
                        for _, coord in ipairs(path) do
                            if type(coord) == "table" and coord[1] and coord[2] then
                                local key = string.format(
                                    "%.2f-%.2f",
                                    tonumber(coord[1]) or 0,
                                    tonumber(coord[2]) or 0
                                )
                                if not pointSet[key] then
                                    pointSet[key] = true
                                    pointCount = pointCount + 1
                                end
                            end
                        end
                        if pointCount >= 2 then
                            patrolPaths = patrolPaths + 1
                        end
                    end
                end
            end
        end
    end

    if patrolPaths > 0 then
        return L.POS_PATROL:format(patrolPaths)
    elseif spawnCount > 1 then
        return L.POS_MULTI:format(spawnCount)
    elseif spawnCount == 1 then
        return L.POS_FIXED
    end
    return L.POS_UNKNOWN
end

local function GetNpcDisplayName(npcID)
    local name = NpcName(npcID)
    local tag = GetPositionTag(npcID)
    if tag and tag ~= "" and tag ~= L.POS_FIXED then
        return name .. "（" .. tag .. "）"
    end
    return name
end

-----------------------------------------------------------------------
-- Resolve the NPC(s) behind a Questie icon
-----------------------------------------------------------------------

local function ResolveNpcIDs(data)
    if type(data) ~= "table" then
        return nil
    end

    local db = GetDB()
    if not db or not db.Npc or not db.Quest then
        return nil
    end

    local ids = {}
    local function add(id)
        id = tonumber(id)
        if NpcExists(id) then
            ids[id] = true
        end
    end

    local iconType = data.Type

    if iconType == "monster" or iconType == "killcredit" or iconType == "item" then
        add(data.ObjectiveTargetId)
        if iconType == "killcredit" and type(data.ObjectiveData) == "table"
            and type(data.ObjectiveData.IdList) == "table" then
            for _, id in ipairs(data.ObjectiveData.IdList) do
                add(id)
            end
        end
    elseif iconType == "available" then
        local questID = tonumber(data.Id)
        if questID then
            local startedBy = db.Quest.Get(questID, "startedBy")
            if startedBy then
                if type(startedBy[1]) == "table" then
                    for _, id in ipairs(startedBy[1]) do
                        add(id)
                    end
                end

                -- Item-started quests have no NPC giver in startedBy[1].
                -- Add the NPCs that drop the starting item(s) instead.
                if type(startedBy[3]) == "table" and db.Item and db.Item.Get then
                    for _, itemID in ipairs(startedBy[3]) do
                        itemID = tonumber(itemID)
                        if itemID and (not db.Item.Exists or db.Item.Exists(itemID)) then
                            local npcDrops = db.Item.Get(itemID, "npcDrops")
                            if type(npcDrops) == "table" then
                                for _, npcID in ipairs(npcDrops) do
                                    add(npcID)
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif iconType == "complete" then
        local questID = tonumber(data.Id)
        if questID then
            local finishedBy = db.Quest.Get(questID, "finishedBy")
            if finishedBy and type(finishedBy[1]) == "table" then
                for _, id in ipairs(finishedBy[1]) do
                    add(id)
                end
            end
        end
    elseif iconType == "manual" then
        add(data.id)
    else
        return nil
    end

    local result = {}
    for id in pairs(ids) do
        result[#result + 1] = id
    end
    table.sort(result)

    if #result == 0 then
        return nil
    end
    return result
end

-----------------------------------------------------------------------
-- Coordinate string for RareScanner's import format
-----------------------------------------------------------------------

local function ToFourDigits(value)
    local number = math.floor((tonumber(value) or 0) * 100 + 0.5)
    if number < 0 then
        number = 0
    elseif number > 9999 then
        number = 9999
    end
    return string.format("%04d", number)
end

local function BuildCoords(npcID)
    local db = GetDB()
    local zoneDB = ns.ZoneDB
    if not db or not db.Npc or not zoneDB then
        return "*"
    end

    local spawns = db.Npc.Get(npcID, "spawns")
    local waypoints = db.Npc.Get(npcID, "waypoints")
    if not spawns and not waypoints then
        return "*"
    end

    local byMap = {}
    local function addCoord(areaID, x, y)
        if not areaID or not x or not y then
            return
        end
        local uiMapID = zoneDB:GetUiMapIdByAreaId(areaID)
        if not uiMapID then
            return
        end
        byMap[uiMapID] = byMap[uiMapID] or {}
        byMap[uiMapID][ToFourDigits(x) .. "-" .. ToFourDigits(y)] = true
    end

    if spawns then
        for areaID, coords in pairs(spawns) do
            if type(coords) == "table" then
                for _, coord in ipairs(coords) do
                    if type(coord) == "table" then
                        addCoord(areaID, coord[1], coord[2])
                    end
                end
            end
        end
    end

    if waypoints then
        for areaID, paths in pairs(waypoints) do
            if type(paths) == "table" then
                for _, path in ipairs(paths) do
                    if type(path) == "table" then
                        for _, coord in ipairs(path) do
                            if type(coord) == "table" then
                                addCoord(areaID, coord[1], coord[2])
                            end
                        end
                    end
                end
            end
        end
    end

    local parts = {}
    for uiMapID, coordSet in pairs(byMap) do
        local coords = {}
        for coord in pairs(coordSet) do
            coords[#coords + 1] = coord
        end
        if #coords > 0 then
            table.sort(coords)
            parts[#parts + 1] = tostring(uiMapID) .. ":" .. table.concat(coords, ",")
        end
    end

    if #parts == 0 then
        return "*"
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function QuestLabel(questID)
    local db = GetDB()
    if db and db.Quest and db.Quest.Exists and not db.Quest.Exists(questID) then
        return tostring(questID)
    end
    if db and db.Quest and db.Quest.Get then
        local name = db.Quest.Get(questID, "name")
        if name then
            return name
        end
    end
    return tostring(questID)
end

local function GetQuestSets(questID)
    local db = GetDB()
    if not db or not db.Quest or not db.Quest.Get then
        return nil
    end
    if db.Quest.Exists and not db.Quest.Exists(questID) then
        return nil
    end

    local giverSet = {}
    local turnInSet = {}

    local startedBy = db.Quest.Get(questID, "startedBy")
    if startedBy and type(startedBy[1]) == "table" then
        for _, npcID in ipairs(startedBy[1]) do
            npcID = tonumber(npcID)
            if npcID then
                giverSet[npcID] = true
            end
        end
    end

    local finishedBy = db.Quest.Get(questID, "finishedBy")
    if finishedBy and type(finishedBy[1]) == "table" then
        for _, npcID in ipairs(finishedBy[1]) do
            npcID = tonumber(npcID)
            if npcID then
                turnInSet[npcID] = true
            end
        end
    end

    return giverSet, turnInSet
end

local function GetQuestTurnInNpcIDs(questID)
    local db = GetDB()
    if not db or not db.Quest or not db.Quest.Get then
        return {}
    end
    if db.Quest.Exists and not db.Quest.Exists(questID) then
        return {}
    end

    local ids = {}
    local finishedBy = db.Quest.Get(questID, "finishedBy")
    if finishedBy and type(finishedBy[1]) == "table" then
        for _, npcID in ipairs(finishedBy[1]) do
            npcID = tonumber(npcID)
            if npcID and NpcExists(npcID) then
                ids[npcID] = true
            end
        end
    end

    local result = {}
    for npcID in pairs(ids) do
        result[#result + 1] = npcID
    end
    table.sort(result)
    return result
end

local function GetQuestCombatNpcIDs(questID)
    local db = GetDB()
    if not db or not db.Quest or not db.Quest.Get then
        return {}
    end
    if db.Quest.Exists and not db.Quest.Exists(questID) then
        return {}
    end

    local giverSet, turnInSet = GetQuestSets(questID)
    giverSet = giverSet or {}
    turnInSet = turnInSet or {}

    local ids = {}
    local function add(npcID)
        npcID = tonumber(npcID)
        if npcID and NpcExists(npcID) and not giverSet[npcID] and not turnInSet[npcID] then
            ids[npcID] = true
        end
    end

    local objectives = db.Quest.Get(questID, "objectives")
    if type(objectives) == "table" then
        for _, obj in ipairs(objectives[1] or {}) do
            if type(obj) == "table" then
                add(obj[1])
            end
        end

        for _, obj in ipairs(objectives[3] or {}) do
            if type(obj) == "table" then
                local itemID = tonumber(obj[1])
                if itemID and db.Item and db.Item.Get
                    and (not db.Item.Exists or db.Item.Exists(itemID)) then
                    local npcDrops = db.Item.Get(itemID, "npcDrops")
                    if type(npcDrops) == "table" then
                        for _, npcID in ipairs(npcDrops) do
                            add(npcID)
                        end
                    end
                end
            end
        end

        for _, obj in ipairs(objectives[5] or {}) do
            if type(obj) == "table" then
                if type(obj[1]) == "table" then
                    for _, npcID in ipairs(obj[1]) do
                        add(npcID)
                    end
                end
                add(obj[2])
            end
        end
    end

    local extraObjectives = db.Quest.Get(questID, "extraObjectives")
    if type(extraObjectives) == "table" then
        for _, extra in ipairs(extraObjectives) do
            local references = type(extra) == "table" and extra[5]
            if type(references) == "table" then
                for _, ref in ipairs(references) do
                    if type(ref) == "table" and ref[1] == "monster" then
                        add(ref[2])
                    end
                end
            end
        end
    end

    local result = {}
    for npcID in pairs(ids) do
        result[#result + 1] = npcID
    end
    table.sort(result)
    return result
end

local function GetQuestAddableNpcGroups(questID)
    questID = tonumber(questID)
    if not questID then
        return {}, {}
    end

    local turnInIDs = GetQuestTurnInNpcIDs(questID)
    local combatIDs = {}
    local complete = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    if not complete then
        combatIDs = GetQuestCombatNpcIDs(questID)
    end
    return combatIDs, turnInIDs
end

Data.GetDB = GetDB
Data.NpcExists = NpcExists
Data.NpcName = NpcName
Data.GetPositionTag = GetPositionTag
Data.GetNpcDisplayName = GetNpcDisplayName
Data.ResolveNpcIDs = ResolveNpcIDs
Data.BuildCoords = BuildCoords
Data.QuestLabel = QuestLabel
Data.GetQuestSets = GetQuestSets
Data.GetQuestTurnInNpcIDs = GetQuestTurnInNpcIDs
Data.GetQuestCombatNpcIDs = GetQuestCombatNpcIDs
Data.GetQuestAddableNpcGroups = GetQuestAddableNpcGroups
