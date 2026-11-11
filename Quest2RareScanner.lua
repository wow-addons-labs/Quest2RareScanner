-----------------------------------------------------------------------
-- Quest2RareScanner
-- Alt+left-click a Questie world-map icon to add the NPC behind it to
-- RareScanner's custom NPC list.
--
-- v1.5: world-map icons, quest-log entry, and automatic removal.
-----------------------------------------------------------------------

local ADDON_NAME, ns = ...

local L = ns.L
local Data = ns.Data

local GetDB = Data.GetDB
local NpcExists = Data.NpcExists
local NpcName = Data.NpcName
local GetPositionTag = Data.GetPositionTag
local GetNpcDisplayName = Data.GetNpcDisplayName
local ResolveNpcIDs = Data.ResolveNpcIDs
local BuildCoords = Data.BuildCoords
local QuestLabel = Data.QuestLabel
local GetQuestSets = Data.GetQuestSets
local GetQuestTurnInNpcIDs = Data.GetQuestTurnInNpcIDs
local GetQuestCombatNpcIDs = Data.GetQuestCombatNpcIDs
local GetQuestAddableNpcGroups = Data.GetQuestAddableNpcGroups

local PREFIX = "|cFF00FFFFQuest2RareScanner|r: "


local function Print(msg)
    print(PREFIX .. tostring(msg))
end

Quest2RareScannerDB = Quest2RareScannerDB or {}

local questieReady = false
local frameHookReady = false
local iconCreationWrapped = false
local tooltipWrapped = false

local QuestieFrame
local QuestieMap
local TooltipLayout
local ZoneDB




-- RareScanner keeps a runtime "recently seen" cache that has no public
-- removal API. Filtering a deleted NPC hides its map POIs and that cache
-- until it expires; the filter is restored if the NPC is added again.
local function GetRareScannerFilteredNpcs()
    local db = _G.RareScannerDB
    if not db or not db.profile then
        return nil
    end

    local rareFilters = db.profile.rareFilters
    if not rareFilters then
        rareFilters = {}
        db.profile.rareFilters = rareFilters
    end

    local filtered = rareFilters.filteredNpcs
    if not filtered then
        filtered = {}
        rareFilters.filteredNpcs = filtered
    end
    return filtered
end

local function AddAutoFilter(npcID)
    npcID = tonumber(npcID)
    if not npcID then
        return
    end

    local filtered = GetRareScannerFilteredNpcs()
    if not filtered then
        return
    end

    Quest2RareScannerDB.autoFiltered = Quest2RareScannerDB.autoFiltered or {}
    if Quest2RareScannerDB.autoFiltered[npcID] ~= nil then
        return
    end

    local previous = filtered[npcID]
    filtered[npcID] = 1 -- RSConstants.ENTITY_FILTER_ALL
    Quest2RareScannerDB.autoFiltered[npcID] = previous or 0
end

local function ClearAutoFilter(npcID)
    npcID = tonumber(npcID)
    if not npcID then
        return
    end

    local autoFiltered = Quest2RareScannerDB.autoFiltered
    if not autoFiltered or autoFiltered[npcID] == nil then
        return
    end

    local previous = autoFiltered[npcID]
    local filtered = GetRareScannerFilteredNpcs()
    if filtered then
        if previous == 0 then
            filtered[npcID] = nil
        else
            filtered[npcID] = previous
        end
    end
    autoFiltered[npcID] = nil
end

local function AddAutoFilterForAllQ2RS()
    local db = _G.RareScannerDB
    if not db or not db.global then
        return
    end

    local groupKeys = {}
    for key, name in pairs(db.global.custom_npcs_groups or {}) do
        if type(name) == "string" and name:match("^Q2RS_") then
            groupKeys[key] = true
        end
    end

    for npcID, info in pairs(db.global.custom_npcs or {}) do
        if info and info.group and groupKeys[info.group] then
            AddAutoFilter(npcID)
        end
    end
end

local function CleanupAutoFiltersOnLogin()
    local autoFiltered = Quest2RareScannerDB.autoFiltered
    if not autoFiltered then
        return
    end

    local npcs = _G.RareScannerDB and _G.RareScannerDB.global
        and _G.RareScannerDB.global.custom_npcs
    for npcID in pairs(autoFiltered) do
        if not (npcs and npcs[npcID]) then
            ClearAutoFilter(npcID)
        end
    end
end

-----------------------------------------------------------------------
-- Import into RareScanner
-----------------------------------------------------------------------

local function ImportToRareScanner(payload)
    local handler = SlashCmdList["ACECONSOLE_RS"] or SlashCmdList["ACECONSOLE_RARESCANNER"]
    if not handler then
        Print(L.NO_RARESCANNER)
        return false
    end

    local ok, err = pcall(handler, "import " .. payload)
    if not ok then
        Print(L.IMPORT_ERROR .. tostring(err))
        return false
    end
    return true
end

local function ImportNpcIDs(npcIDs, group)
    local lines = {}
    for _, npcID in ipairs(npcIDs) do
        ClearAutoFilter(npcID)
        lines[#lines + 1] = tostring(npcID) .. " " .. BuildCoords(npcID) .. " * * " .. group
    end
    if #lines == 0 then
        return false
    end
    return ImportToRareScanner(table.concat(lines, "\n"))
end

local function HandleIcon(frame)
    local data = frame and frame.data
    if not data then
        return
    end

    local npcIDs = ResolveNpcIDs(data)
    if not npcIDs then
        -- Unsupported icons (objects, events, object-only quests) are silent.
        return
    end

    local questID = tonumber(data.Id)
    local group = questID and ("Q2RS_" .. questID) or "Q2RS_手动"

    if ImportNpcIDs(npcIDs, group) then
        local names = {}
        for index, npcID in ipairs(npcIDs) do
            if index <= 5 then
                names[#names + 1] = GetNpcDisplayName(npcID)
            end
        end

        local message = L.IMPORTED:format(#npcIDs, group)
        if #names > 0 then
            message = message .. " " .. table.concat(names, ", ")
            if #npcIDs > #names then
                message = message .. " ..."
            end
        end
        Print(message)
    end
end

-----------------------------------------------------------------------
-- Questie icon hooks
-----------------------------------------------------------------------

local function HookFrame(frame)
    if not frame or frame.q2rsHooked then
        return
    end
    frame.q2rsHooked = true

    frame:HookScript("OnClick", function(self, button)
        if button == "LeftButton" and IsAltKeyDown() and not self.miniMapIcon then
            HandleIcon(self)
        end
    end)
end

local function HookExistingFrames()
    if not QuestieMap then
        return
    end

    for _, frames in pairs(QuestieMap.questIdFrames or {}) do
        for frameName in pairs(frames) do
            local frame = _G[frameName]
            if frame then
                HookFrame(frame)
            end
        end
    end

    for _, byID in pairs(QuestieMap.manualFrames or {}) do
        for _, frameNames in pairs(byID) do
            if type(frameNames) == "table" then
                for _, frameName in ipairs(frameNames) do
                    local frame = _G[frameName]
                    if frame then
                        HookFrame(frame)
                    end
                end
            end
        end
    end
end

local function WrapIconCreation()
    if iconCreationWrapped then
        return true
    end
    if not QuestieFrame or type(QuestieFrame.CreateIconFrame) ~= "function" then
        return false
    end

    local original = QuestieFrame.CreateIconFrame
    QuestieFrame.CreateIconFrame = function(frameID, onEnter)
        local frame = original(frameID, onEnter)
        HookFrame(frame)
        return frame
    end

    iconCreationWrapped = true
    return true
end

local function WrapTooltip()
    if tooltipWrapped or not TooltipLayout or type(TooltipLayout.Render) ~= "function" then
        return
    end

    local original = TooltipLayout.Render
    TooltipLayout.Render = function(self, tooltip, rows)
        local owner = tooltip and tooltip._owner
        if owner and not owner.miniMapIcon and owner.data and rows and rows.AddLine then
            if ResolveNpcIDs(owner.data) then
                rows:AddLine(L.ALT_HINT, 0.2, 1, 0.2)
            end
        end
        return original(self, tooltip, rows)
    end

    tooltipWrapped = true
end

local function ImportQuestieModule(name)
    if not QuestieLoader then
        return nil
    end
    local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    if ok then
        return module
    end
    return nil
end

local function OnQuestieReady()
    if frameHookReady then
        return
    end

    questieReady = true

    QuestieFrame = ImportQuestieModule("QuestieFrame")
    QuestieMap = ImportQuestieModule("QuestieMap")
    TooltipLayout = ImportQuestieModule("TooltipLayout")
    ZoneDB = ImportQuestieModule("ZoneDB")
    ns.ZoneDB = ZoneDB

    if not QuestieFrame or not QuestieMap then
        Print(L.HOOK_ERROR)
        return
    end

    if not WrapIconCreation() then
        Print(L.HOOK_ERROR)
        return
    end

    HookExistingFrames()
    WrapTooltip()
    frameHookReady = true

    if not ZoneDB then
        Print(L.ZONE_NOT_READY)
    end
end

-----------------------------------------------------------------------
-- Minimap button + delete all Q2RS_ data
-----------------------------------------------------------------------

local minimapButton
local atan2 = math.atan2 or function(y, x)
    return math.atan(y, x)
end

local function GetAddedStats()
    local db = _G.RareScannerDB
    if not db or not db.global then
        return 0, 0
    end

    local groups = db.global.custom_npcs_groups or {}
    local npcs = db.global.custom_npcs or {}

    local groupKeys = {}
    for key, name in pairs(groups) do
        if type(name) == "string" and name:match("^Q2RS_") then
            groupKeys[key] = true
        end
    end

    local groupCount = 0
    for _ in pairs(groupKeys) do
        groupCount = groupCount + 1
    end

    local npcCount = 0
    for _, info in pairs(npcs) do
        if info and info.group and groupKeys[info.group] then
            npcCount = npcCount + 1
        end
    end

    return npcCount, groupCount
end

local function GetRareScannerOptions()
    local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
    if not registry then
        return nil
    end

    local ok, options = pcall(
        registry.GetOptionsTable,
        registry,
        "RareScanner Custom NPCs",
        "dialog",
        "Quest2RareScanner-1.0"
    )
    if ok and type(options) == "table" then
        return options
    end
    return nil
end

local function RemoveFromSavedDB()
    local db = _G.RareScannerDB
    if not db or not db.global then
        return
    end

    local groups = db.global.custom_npcs_groups or {}
    local npcs = db.global.custom_npcs or {}
    local loot = db.global.custom_loot or {}
    local found = db.global.rares_found or {}

    local groupKeys = {}
    for key, name in pairs(groups) do
        if type(name) == "string" and name:match("^Q2RS_") then
            groupKeys[key] = true
        end
    end

    local npcIDs = {}
    for npcID, info in pairs(npcs) do
        if info and info.group and groupKeys[info.group] then
            npcIDs[#npcIDs + 1] = npcID
        end
    end

    for _, npcID in ipairs(npcIDs) do
        npcs[npcID] = nil
        loot[npcID] = nil
        found[npcID] = nil
    end
    for key in pairs(groupKeys) do
        groups[key] = nil
    end
end

local function NotifyOptionsChanged()
    local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
    if registry then
        registry:NotifyChange("RareScanner Custom NPCs")
        registry:NotifyChange("RareScanner NPC Filter")
    end
end

local function RefreshRareScannerMap(silent)
    local handler = SlashCmdList["ACECONSOLE_RS"] or SlashCmdList["ACECONSOLE_RARESCANNER"]
    if not handler then
        return
    end

    -- RareScanner has no public "refresh map" command. Toggling rare icons
    -- off/on forces RSProvider.RefreshAllDataProviders() and restores the setting.
    if not silent then
        Print(L.REFRESHING)
    end
    pcall(handler, "tr")
    pcall(handler, "tr")
end

-----------------------------------------------------------------------
-- Automatic removal (quest accept / complete / turn-in / abandon)
-----------------------------------------------------------------------

local mapRefreshPending = false
local pendingGroupDeletes = {}
local pendingStartItemCleanup = {}
local recentlySeenHintShown = false

local function MaybeShowRecentlySeenHint()
    if recentlySeenHintShown then
        return
    end
    recentlySeenHintShown = true
    Print(L.RECENTLY_SEEN_HINT)
end

local function ScheduleMapRefresh()
    if mapRefreshPending then
        return
    end

    mapRefreshPending = true
    C_Timer.After(0.5, function()
        mapRefreshPending = false
        RefreshRareScannerMap(true)
    end)
end






local function GetGroupInfo(groupName)
    local db = _G.RareScannerDB
    if not db or not db.global then
        return nil
    end

    local groups = db.global.custom_npcs_groups or {}
    local npcs = db.global.custom_npcs or {}

    local groupKey
    for key, name in pairs(groups) do
        if name == groupName then
            groupKey = key
            break
        end
    end
    if not groupKey then
        return nil
    end

    local npcIDs = {}
    for npcID, info in pairs(npcs) do
        if info and info.group == groupKey then
            npcIDs[#npcIDs + 1] = npcID
        end
    end
    return groupKey, npcIDs
end

local function FindGroupOptions(options, groupKey, groupName)
    if not options or type(options.args) ~= "table" then
        return nil
    end

    local group
    if groupKey then
        group = options.args["GROUP" .. groupKey]
    end
    if not group or type(group) ~= "table" or type(group.args) ~= "table" then
        for _, candidate in pairs(options.args) do
            if type(candidate) == "table" and candidate.desc == groupName
                and type(candidate.args) == "table" then
                group = candidate
                break
            end
        end
    end
    return group
end

local function DeleteNpcFromOptions(options, groupKey, groupName, npcID)
    local group = FindGroupOptions(options, groupKey, groupName)
    local npcEntry = group and group.args and group.args["NPC" .. npcID]
    local deleteNpc = npcEntry and npcEntry.args and npcEntry.args.deleteNpc
    if deleteNpc and type(deleteNpc.func) == "function" then
        return pcall(deleteNpc.func)
    end
    return false
end

local function DeleteGroupFromOptions(options, groupKey, groupName)
    local group = FindGroupOptions(options, groupKey, groupName)
    local deleteGroup = group and group.args and group.args.deleteGroup
    if deleteGroup and type(deleteGroup.func) == "function" then
        return pcall(deleteGroup.func)
    end
    return false
end

local function RemoveNpcFromSavedDB(npcID)
    local db = _G.RareScannerDB
    if not db or not db.global then
        return
    end

    AddAutoFilter(npcID)

    if db.global.custom_npcs then
        db.global.custom_npcs[npcID] = nil
    end
    if db.global.custom_loot then
        db.global.custom_loot[npcID] = nil
    end
    if db.global.rares_found then
        db.global.rares_found[npcID] = nil
    end
end

local function RemoveGroupKeyFromSavedDB(groupKey)
    local db = _G.RareScannerDB
    if not db or not db.global or not db.global.custom_npcs_groups then
        return
    end
    db.global.custom_npcs_groups[groupKey] = nil
end

local function RemoveGroupFromSavedDB(groupName)
    local groupKey, npcIDs = GetGroupInfo(groupName)
    if not groupKey then
        return
    end

    for _, npcID in ipairs(npcIDs) do
        RemoveNpcFromSavedDB(npcID)
    end
    RemoveGroupKeyFromSavedDB(groupKey)
end

local function GroupIsEmpty(groupKey)
    local db = _G.RareScannerDB
    if not db or not db.global then
        return true
    end

    for _, info in pairs(db.global.custom_npcs or {}) do
        if info and info.group == groupKey then
            return false
        end
    end
    return true
end

local function RemoveGroupNpcs(groupName, shouldRemove)
    if InCombatLockdown() then
        return 0, 0, nil
    end

    local groupKey, npcIDs = GetGroupInfo(groupName)
    if not groupKey or #npcIDs == 0 then
        return 0, 0, npcIDs
    end

    local toRemove = {}
    for _, npcID in ipairs(npcIDs) do
        if shouldRemove(npcID) then
            toRemove[#toRemove + 1] = npcID
        end
    end
    if #toRemove == 0 then
        return 0, 0, npcIDs
    end

    for _, npcID in ipairs(toRemove) do
        AddAutoFilter(npcID)
    end

    local options = GetRareScannerOptions()
    if options then
        for _, npcID in ipairs(toRemove) do
            DeleteNpcFromOptions(options, groupKey, groupName, npcID)
        end
    end

    local remaining = {}
    local npcDB = _G.RareScannerDB and _G.RareScannerDB.global
        and _G.RareScannerDB.global.custom_npcs
    for _, npcID in ipairs(toRemove) do
        if not npcDB or npcDB[npcID] then
            remaining[#remaining + 1] = npcID
        end
    end

    local failed = #remaining
    if failed > 0 then
        for _, npcID in ipairs(remaining) do
            RemoveNpcFromSavedDB(npcID)
        end
        if GroupIsEmpty(groupKey) then
            RemoveGroupKeyFromSavedDB(groupKey)
        end
        Print(L.CLEANUP_RELOAD)
    end

    NotifyOptionsChanged()
    ScheduleMapRefresh()
    MaybeShowRecentlySeenHint()

    return #toRemove, failed, npcIDs
end

local function RemoveQuestNpcs(questID, shouldRemove)
    return RemoveGroupNpcs("Q2RS_" .. questID, shouldRemove)
end

local function RemoveNonTurnIns(questID)
    local _, turnInSet = GetQuestSets(questID)
    if not turnInSet then
        return
    end

    local removed, _, npcIDs = RemoveQuestNpcs(questID, function(npcID)
        return not turnInSet[npcID]
    end)

    if removed > 0 then
        local kept = 0
        for _, npcID in ipairs(npcIDs or {}) do
            if turnInSet[npcID] then
                kept = kept + 1
            end
        end

        local suffix = ""
        if kept > 0 then
            suffix = L.AUTO_KEPT:format(kept)
        end
        Print(L.AUTO_REMOVED:format(QuestLabel(questID), removed, suffix))
    end
end

local function RemoveGivers(questID)
    local giverSet, turnInSet = GetQuestSets(questID)
    if not giverSet then
        return
    end

    local removed = RemoveQuestNpcs(questID, function(npcID)
        return giverSet[npcID] and not turnInSet[npcID]
    end)

    if removed > 0 then
        Print(L.AUTO_GIVERS_REMOVED:format(QuestLabel(questID), removed))
    end
end

local function GetQuestStartItemDroppers(questID)
    local db = GetDB()
    if not db or not db.Quest or not db.Item then
        return nil
    end
    if db.Quest.Exists and not db.Quest.Exists(questID) then
        return nil
    end

    local startedBy = db.Quest.Get(questID, "startedBy")
    if not startedBy or type(startedBy[3]) ~= "table" then
        return nil
    end

    local droppers = {}
    for _, itemID in ipairs(startedBy[3]) do
        itemID = tonumber(itemID)
        if itemID and (not db.Item.Exists or db.Item.Exists(itemID)) then
            local npcDrops = db.Item.Get and db.Item.Get(itemID, "npcDrops")
            if type(npcDrops) == "table" then
                for _, npcID in ipairs(npcDrops) do
                    npcID = tonumber(npcID)
                    if npcID then
                        droppers[npcID] = true
                    end
                end
            end
        end
    end

    if next(droppers) == nil then
        return nil
    end
    return droppers
end

local function CleanupStartItemDroppers(questID)
    if InCombatLockdown() then
        pendingStartItemCleanup[questID] = true
        return
    end

    local droppers = GetQuestStartItemDroppers(questID)
    if not droppers then
        return
    end

    local _, turnInSet = GetQuestSets(questID)
    local removedTotal = 0
    local questGroup = "Q2RS_" .. questID

    for npcID in pairs(droppers) do
        if not (turnInSet and turnInSet[npcID]) then
            local removedQuest = RemoveGroupNpcs(questGroup, function(id)
                return id == npcID
            end)
            local removedManual = RemoveGroupNpcs("Q2RS_手动", function(id)
                return id == npcID
            end)
            removedTotal = removedTotal + (removedQuest or 0) + (removedManual or 0)
        end
    end

    if removedTotal > 0 then
        Print(L.START_ITEM_CLEANED:format(QuestLabel(questID), removedTotal))
    end
end

local function CleanupStartItemDroppersForQuestLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
        return
    end

    local count = C_QuestLog.GetNumQuestLogEntries()
    for index = 1, count do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            CleanupStartItemDroppers(info.questID)
        end
    end
end

local function DeleteQuestGroup(questID)
    if InCombatLockdown() then
        pendingGroupDeletes[questID] = true
        return
    end

    local groupName = "Q2RS_" .. questID
    local groupKey, npcIDs = GetGroupInfo(groupName)
    if not groupKey then
        return
    end

    for _, npcID in ipairs(npcIDs) do
        AddAutoFilter(npcID)
    end

    local options = GetRareScannerOptions()
    if options then
        DeleteGroupFromOptions(options, groupKey, groupName)
    end

    if GetGroupInfo(groupName) then
        RemoveGroupFromSavedDB(groupName)
        NotifyOptionsChanged()
        Print(L.CLEANUP_RELOAD)
    end

    ScheduleMapRefresh()
    MaybeShowRecentlySeenHint()
    Print(L.AUTO_GROUP_REMOVED:format(QuestLabel(questID), #npcIDs))
end

local function ProcessQuestState(questID)
    if not (C_QuestLog and C_QuestLog.IsOnQuest) then
        return
    end

    if C_QuestLog.IsOnQuest(questID) then
        if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
            RemoveNonTurnIns(questID)
        else
            RemoveGivers(questID)
        end
        CleanupStartItemDroppers(questID)
    elseif C_QuestLog.IsQuestFlaggedCompleted
        and C_QuestLog.IsQuestFlaggedCompleted(questID) then
        DeleteQuestGroup(questID)
    end
end

local function ProcessAllGroups()
    local db = _G.RareScannerDB
    if not db or not db.global then
        return
    end

    local questIDs = {}
    for _, name in pairs(db.global.custom_npcs_groups or {}) do
        if type(name) == "string" then
            local questID = name:match("^Q2RS_(%d+)$")
            if questID then
                questIDs[tonumber(questID)] = true
            end
        end
    end

    for questID in pairs(questIDs) do
        ProcessQuestState(questID)
    end
end

local function ProcessQuestAccepted(questID)
    questID = tonumber(questID)
    if not questID then
        return
    end
    RemoveNonTurnIns(questID)
    CleanupStartItemDroppers(questID)
end

-----------------------------------------------------------------------
-- Quest log details button + category dialog
-----------------------------------------------------------------------

local questLogButton
local questLogDialog
local questLogHooked = false

local function GetQuestLogDetailsFrame()
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    if details then
        return details
    end
    details = QuestMapFrame and QuestMapFrame.QuestsFrame
        and QuestMapFrame.QuestsFrame.DetailsFrame
    if details then
        return details
    end
    return _G.QuestLogDetailFrame or _G.QuestLogExFrame
        or _G.ClassicQuestLog or _G.QuestLogFrame
end

local function GetDetailQuestID()
    if _G.QuestMapFrame_GetDetailQuestID then
        local ok, questID = pcall(_G.QuestMapFrame_GetDetailQuestID)
        if ok and questID and questID ~= 0 then
            return tonumber(questID)
        end
    end
    return nil
end

local function GetSelectedQuestID()
    -- The detail panel is authoritative: C_QuestLog.GetSelectedQuest can lag
    -- behind or point at a different list selection.
    local detailID = GetDetailQuestID()
    if detailID then
        return detailID
    end

    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        local questID = C_QuestLog.GetSelectedQuest()
        if questID and questID ~= 0 then
            return tonumber(questID)
        end
    end

    if _G.GetQuestLogSelection and C_QuestLog and C_QuestLog.GetInfo then
        local index = _G.GetQuestLogSelection()
        if index and index > 0 then
            local info = C_QuestLog.GetInfo(index)
            if info and info.questID and info.questID ~= 0 then
                return tonumber(info.questID)
            end
        end
    end
    return nil
end


local function CreateQuestLogDialog()
    if questLogDialog then
        return questLogDialog
    end

    local dialog = CreateFrame("Frame", "Quest2RareScannerQuestLogDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(420, 300)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dialog:SetBackdropColor(0, 0, 0, 0.9)
    dialog:SetBackdropBorderColor(1, 0.82, 0, 0.9)

    local title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetWidth(340)
    title:SetWordWrap(true)
    title:SetText("加入 RareScanner")
    dialog.title = title

    local questName = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    questName:SetPoint("TOP", 0, -28)
    questName:SetWidth(340)
    questName:SetWordWrap(true)
    dialog.questName = questName

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local scroll = CreateFrame(
        "ScrollFrame",
        "Quest2RareScannerQuestLogScrollFrame",
        dialog,
        "UIPanelScrollFrameTemplate"
    )
    scroll:SetPoint("TOPLEFT", 14, -62)
    scroll:SetPoint("BOTTOMRIGHT", -30, 44)
    dialog.scroll = scroll

    local scrollBar = scroll.ScrollBar or _G[scroll:GetName() .. "ScrollBar"]
    if not scrollBar and scroll.GetChildren then
        for _, child in ipairs({ scroll:GetChildren() }) do
            if child:IsObjectType("Slider") then
                scrollBar = child
                break
            end
        end
    end
    dialog.scrollBar = scrollBar
    if scrollBar then
        scrollBar:Hide()
    end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(340, 1)
    scroll:SetScrollChild(content)
    dialog.content = content
    dialog.rows = {}

    local joinButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    joinButton:SetSize(90, 22)
    joinButton:SetPoint("BOTTOM", dialog, "BOTTOM", -50, 12)
    joinButton:SetText("加入")
    dialog.joinButton = joinButton

    local cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelButton:SetSize(90, 22)
    cancelButton:SetPoint("BOTTOM", dialog, "BOTTOM", 50, 12)
    cancelButton:SetText("取消")
    cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)

    local function UpdateSelection()
        local all = { combat = true, turnIn = true }
        local any = false

        for _, row in ipairs(dialog.rows) do
            if not row.isHeader and row:IsShown() then
                if row:GetChecked() then
                    any = true
                else
                    all[row.category] = false
                end
            end
        end

        for _, row in ipairs(dialog.rows) do
            if row.isHeader and row:IsShown() then
                row:SetChecked(all[row.category] and true or false)
            end
        end

        joinButton:SetEnabled(any)
    end

    function dialog:UpdateSelection()
        UpdateSelection()
    end

    function dialog:GetSelected()
        local ids = {}
        local seen = {}
        local combatCount = 0
        local turnInCount = 0

        for _, row in ipairs(self.rows) do
            if not row.isHeader and row:IsShown() and row:GetChecked() then
                if row.category == "combat" then
                    combatCount = combatCount + 1
                else
                    turnInCount = turnInCount + 1
                end

                if not seen[row.npcID] then
                    seen[row.npcID] = true
                    ids[#ids + 1] = row.npcID
                end
            end
        end

        return ids, combatCount, turnInCount
    end

    local function GetRow(index)
        local row = dialog.rows[index]
        if not row then
            row = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            row:SetSize(18, 18)
            row.label = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", row, "RIGHT", 4, 0)
            row.label:SetWidth(290)
            row.label:SetJustifyH("LEFT")

            row:SetScript("OnClick", function(btn)
                if btn.isHeader then
                    local checked = btn:GetChecked() and true or false
                    for _, other in ipairs(dialog.rows) do
                        if other.isHeader ~= true and other.category == btn.category
                            and other:IsShown() then
                            other:SetChecked(checked)
                        end
                    end
                end
                UpdateSelection()
            end)

            row:SetScript("OnEnter", function(btn)
                if btn.tooltipText then
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(btn.tooltipText, 1, 1, 1)
                    GameTooltip:Show()
                end
            end)

            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            dialog.rows[index] = row
        end
        return row
    end

    function dialog:BuildRows(combatIDs, turnInIDs)
        for _, row in ipairs(self.rows) do
            row:Hide()
        end

        local index = 0
        local y = -2

        local function AddRow(isHeader, category, npcID, text)
            index = index + 1
            local row = GetRow(index)
            row.isHeader = isHeader
            row.category = category
            row.npcID = npcID
            if isHeader then
                row.tooltipText = text .. "\n点击全选 / 取消全选"
            else
                row.tooltipText = text
            end
            row:SetChecked(true)
            row:Show()
            row:ClearAllPoints()
            if isHeader then
                row:SetPoint("TOPLEFT", 2, y)
                row.label:SetWidth(320)
            else
                row:SetPoint("TOPLEFT", 18, y)
                row.label:SetWidth(290)
            end
            row.label:SetText(text)
            y = y - 20
        end

        if #combatIDs > 0 then
            AddRow(true, "combat", nil, ("击杀 / 掉落目标（%d 个）"):format(#combatIDs))
            for _, npcID in ipairs(combatIDs) do
                AddRow(false, "combat", npcID, GetNpcDisplayName(npcID))
            end
        end

        if #turnInIDs > 0 then
            AddRow(true, "turnIn", nil, ("任务交付（%d 个）"):format(#turnInIDs))
            for _, npcID in ipairs(turnInIDs) do
                AddRow(false, "turnIn", npcID, GetNpcDisplayName(npcID))
            end
        end

        local contentHeight = math.max(1, -y + 4)
        self.content:SetSize(340, contentHeight)
        self.scroll:SetVerticalScroll(0)

        local dialogHeight = self:GetHeight() or 300
        local viewHeight = dialogHeight - 62 - 44
        local needsScroll = contentHeight > viewHeight
        if self.scrollBar then
            self.scrollBar:SetShown(needsScroll)
        end

        UpdateSelection()
    end

    joinButton:SetScript("OnClick", function()
        if InCombatLockdown() then
            Print(L.LOG_ADD_IN_COMBAT)
            return
        end

        local questID = dialog.questID
        if not questID then
            dialog:Hide()
            return
        end

        if not (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)) then
            Print(L.LOG_NO_QUEST)
            dialog:Hide()
            return
        end

        local ids, combatCount, turnInCount = dialog:GetSelected()
        if #ids == 0 then
            dialog:Hide()
            return
        end

        table.sort(ids)
        local group = "Q2RS_" .. questID
        local imported = ImportNpcIDs(ids, group)
        dialog:Hide()

        if imported then
            local names = {}
            for index, npcID in ipairs(ids) do
                if index <= 5 then
                    names[#names + 1] = GetNpcDisplayName(npcID)
                end
            end
            local message = L.QUEST_LOG_ADDED:format(
                QuestLabel(questID), #ids, combatCount, turnInCount
            )
            if #names > 0 then
                message = message .. " " .. table.concat(names, ", ")
                if #ids > #names then
                    message = message .. " ..."
                end
            end
            Print(message)
        end
    end)

    if UISpecialFrames then
        local name = dialog:GetName()
        if name then
            local found = false
            for _, frameName in ipairs(UISpecialFrames) do
                if frameName == name then
                    found = true
                    break
                end
            end
            if not found then
                tinsert(UISpecialFrames, name)
            end
        end
    end

    dialog:Hide()
    questLogDialog = dialog
    return dialog
end

local function ShowQuestLogDialog(questID)
    questID = tonumber(questID)
    if not questID then
        return
    end

    if not (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)) then
        Print(L.LOG_NO_QUEST)
        return
    end

    local combatIDs, turnInIDs = GetQuestAddableNpcGroups(questID)
    if #combatIDs == 0 and #turnInIDs == 0 then
        Print(L.LOG_NO_NPCS)
        return
    end

    local dialog = CreateQuestLogDialog()
    dialog.questID = questID

    local complete = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    dialog.title:SetText("加入 RareScanner")
    dialog.questName:SetText(("%s（%s）"):format(
        QuestLabel(questID),
        complete and "可交付" or "进行中"
    ))

    dialog:SetHeight((#combatIDs > 0 and #turnInIDs > 0) and 300 or 250)
    dialog:BuildRows(combatIDs, turnInIDs)
    dialog:Show()
    dialog:Raise()
end

local function UpdateQuestLogButton(forcedQuestID)
    if not questLogButton then
        return
    end

    local questID = tonumber(forcedQuestID) or GetSelectedQuestID()
    if not questID then
        questLogButton:Hide()
        return
    end

    if not (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)) then
        questLogButton:Hide()
        return
    end

    local combatIDs, turnInIDs = GetQuestAddableNpcGroups(questID)
    if #combatIDs == 0 and #turnInIDs == 0 then
        questLogButton:Hide()
        return
    end

    questLogButton.questID = questID
    questLogButton:Show()
end

local function CreateQuestLogButton()
    if questLogButton then
        return questLogButton
    end

    local details = GetQuestLogDetailsFrame()
    if not details then
        return nil
    end

    local button = CreateFrame("Button", "Quest2RareScannerQuestLogButton", details)
    button:SetSize(30, 30)
    button:SetPoint("TOPRIGHT", details, "TOPRIGHT", -6, -6)
    button:SetFrameLevel(details:GetFrameLevel() + 20)

    local iconPath = "Interface\\AddOns\\RareScanner\\Media\\Icons\\OriginalSkull"
    if not _G.RareScanner then
        iconPath = "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(iconPath)
    icon:SetSize(28, 28)
    icon:SetPoint("CENTER", 0, 0)
    button.icon = icon

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:ClearAllPoints()
        highlight:SetPoint("CENTER", 0, 0)
        highlight:SetSize(30, 30)
    end

    button:RegisterForClicks("LeftButtonUp")
    button:Hide()

    button:SetScript("OnEnter", function(self)
        local questID = self.questID
        if not questID then
            return
        end

        local combatIDs, turnInIDs = GetQuestAddableNpcGroups(questID)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("加入 RareScanner", 0.2, 1, 0.2)
        GameTooltip:AddLine(("任务：%s"):format(QuestLabel(questID)), 1, 1, 1)
        if C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
            GameTooltip:AddLine(("任务交付 NPC：%d 个"):format(#turnInIDs), 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine(("击杀 / 掉落目标 %d 个，任务交付 %d 个"):format(#combatIDs, #turnInIDs), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("左键：选择要加入的分类", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        local questID = GetSelectedQuestID() or self.questID
        if questID then
            ShowQuestLogDialog(questID)
        end
    end)

    questLogButton = button
    return button
end

local function InitializeQuestLogButton()
    if questLogHooked then
        UpdateQuestLogButton()
        return
    end

    if not GetQuestLogDetailsFrame() then
        return
    end
    if not CreateQuestLogButton() then
        return
    end

    questLogHooked = true

    if _G.QuestInfo_Display then
        pcall(hooksecurefunc, "QuestInfo_Display", function()
            C_Timer.After(0, UpdateQuestLogButton)
            C_Timer.After(0.1, UpdateQuestLogButton)
        end)
    end
    if _G.QuestMapFrame_ShowQuestDetails then
        pcall(hooksecurefunc, "QuestMapFrame_ShowQuestDetails", function(questID)
            C_Timer.After(0, function()
                UpdateQuestLogButton(questID)
            end)
            C_Timer.After(0.1, function()
                UpdateQuestLogButton(questID)
            end)
        end)
    end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        pcall(hooksecurefunc, C_QuestLog, "SetSelectedQuest", function()
            C_Timer.After(0, UpdateQuestLogButton)
            C_Timer.After(0.1, UpdateQuestLogButton)
        end)
    end
    if QuestMapFrame and QuestMapFrame.HookScript then
        QuestMapFrame:HookScript("OnShow", function()
            C_Timer.After(0, UpdateQuestLogButton)
        end)
    end

    local details = GetQuestLogDetailsFrame()
    if details and details.HookScript then
        details:HookScript("OnShow", function()
            C_Timer.After(0, UpdateQuestLogButton)
        end)
    end

    UpdateQuestLogButton()
end

local questLogInitErrorShown = false
local questLogUpdateErrorShown = false

local function SafeInitializeQuestLogButton()
    local ok, err = pcall(InitializeQuestLogButton)
    if not ok and not questLogInitErrorShown then
        questLogInitErrorShown = true
        Print("任务日志入口初始化失败：" .. tostring(err))
    end
end

local function SafeUpdateQuestLogButton(questID)
    local ok, err = pcall(UpdateQuestLogButton, questID)
    if not ok and not questLogUpdateErrorShown then
        questLogUpdateErrorShown = true
        Print("任务日志入口刷新失败：" .. tostring(err))
    end
end

local function DeleteAllAdded()
    if InCombatLockdown() then
        Print(L.DELETE_IN_COMBAT)
        return
    end

    local npcCount, groupCount = GetAddedStats()
    if npcCount == 0 and groupCount == 0 then
        Print(L.DELETE_NONE)
        return
    end

    AddAutoFilterForAllQ2RS()

    local options = GetRareScannerOptions()
    local deletedGroups = 0
    local failedGroups = 0

    if options and type(options.args) == "table" then
        local groupKeys = {}
        for groupKey, group in pairs(options.args) do
            if type(group) == "table" and type(group.args) == "table"
                and group.args.deleteGroup and type(group.desc) == "string"
                and group.desc:match("^Q2RS_") then
                groupKeys[#groupKeys + 1] = groupKey
            end
        end

        for _, groupKey in ipairs(groupKeys) do
            local group = options.args[groupKey]
            local deleteGroup = group and group.args and group.args.deleteGroup
            if deleteGroup and type(deleteGroup.func) == "function" then
                local ok = pcall(deleteGroup.func)
                if ok then
                    deletedGroups = deletedGroups + 1
                else
                    failedGroups = failedGroups + 1
                end
            else
                failedGroups = failedGroups + 1
            end
        end
    else
        failedGroups = groupCount
    end

    local remainingNpcCount, remainingGroupCount = GetAddedStats()
    if remainingNpcCount > 0 or remainingGroupCount > 0 then
        RemoveFromSavedDB()
        NotifyOptionsChanged()
        RefreshRareScannerMap()
        MaybeShowRecentlySeenHint()
        Print(L.DELETE_PARTIAL)
    else
        NotifyOptionsChanged()
        RefreshRareScannerMap()
        MaybeShowRecentlySeenHint()
        Print(L.DELETE_DONE:format(deletedGroups, npcCount))
    end
end

local function RequestDeleteAll()
    if InCombatLockdown() then
        Print(L.DELETE_IN_COMBAT)
        return
    end

    if not _G.RareScannerDB then
        Print(L.DELETE_NO_RARESCANNER)
        return
    end

    local npcCount, groupCount = GetAddedStats()
    if npcCount == 0 and groupCount == 0 then
        Print(L.DELETE_NONE)
        return
    end

    StaticPopup_Show("QUEST2RARESCANNER_DELETE_ALL", npcCount, groupCount)
end

StaticPopupDialogs["QUEST2RARESCANNER_DELETE_ALL"] = {
    text = L.DELETE_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        DeleteAllAdded()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function UpdateMinimapButtonPosition()
    if not minimapButton then
        return
    end

    local angle = Quest2RareScannerDB.minimapAngle or 225
    local radians = math.rad(angle)
    local radius = (Minimap:GetWidth() / 2) + 6

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(radians) * radius,
        math.sin(radians) * radius
    )
end

local function OnMinimapButtonDrag()
    if not minimapButton then
        return
    end

    local centerX, centerY = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    if not centerX or not centerY or not scale or scale == 0 then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    Quest2RareScannerDB.minimapAngle = math.deg(atan2(cursorY - centerY, cursorX - centerX))
    UpdateMinimapButtonPosition()
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "Quest2RareScannerMinimapButton", Minimap)
    button:SetSize(36, 36)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    background:SetSize(54, 54)
    background:SetPoint("TOPLEFT", 0, 0)

    local questIconPath = "Interface\\AddOns\\Questie\\Icons\\available"
    if not _G.Questie then
        questIconPath = "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(questIconPath)
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER", -2, 2)

    local skullPath = "Interface\\AddOns\\RareScanner\\Media\\Icons\\OriginalSkull"
    if not _G.RareScanner then
        skullPath = "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local badgeShadow = button:CreateTexture(nil, "OVERLAY", nil, 6)
    badgeShadow:SetTexture(skullPath)
    badgeShadow:SetSize(20, 20)
    badgeShadow:SetPoint("BOTTOMRIGHT", 2, -2)
    badgeShadow:SetVertexColor(0, 0, 0, 0.9)

    local badge = button:CreateTexture(nil, "OVERLAY", nil, 7)
    badge:SetTexture(skullPath)
    badge:SetSize(18, 18)
    badge:SetPoint("CENTER", badgeShadow, "CENTER")
    button.badge = badge

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.BUTTON_TITLE, 0.2, 1, 0.2)

        local npcCount, groupCount = GetAddedStats()
        GameTooltip:AddLine(L.BUTTON_COUNT:format(npcCount, groupCount), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L.BUTTON_LEFT, 1, 1, 1)
        GameTooltip:AddLine(L.BUTTON_RIGHT, 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L.BUTTON_DRAG, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self, mouseButton)
        if self.q2rsDidDrag then
            self.q2rsDidDrag = nil
            return
        end

        if mouseButton == "LeftButton" then
            RequestDeleteAll()
        else
            SlashCmdList["QUEST2RARESCANNER"]()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self.q2rsDidDrag = true
        self:SetScript("OnUpdate", OnMinimapButtonDrag)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        C_Timer.After(0.2, function()
            button.q2rsDidDrag = nil
        end)
    end)

    minimapButton = button
    UpdateMinimapButtonPosition()
end

-----------------------------------------------------------------------
-- /q2rs debug
-----------------------------------------------------------------------

local function PrintDebug()
    local db = _G.RareScannerDB
    if not db or not db.global then
        Print("RareScannerDB 未加载")
        return
    end

    local groups = db.global.custom_npcs_groups or {}
    local npcs = db.global.custom_npcs or {}
    local found = db.global.rares_found or {}
    local options = GetRareScannerOptions()

    Print(("debug: options=%s"):format(options and "ok" or "nil"))

    local any = false
    for groupKey, groupName in pairs(groups) do
        if type(groupName) == "string" and groupName:match("^Q2RS_") then
            any = true

            local ids = {}
            for npcID, info in pairs(npcs) do
                if info and info.group == groupKey then
                    ids[#ids + 1] = npcID
                end
            end
            table.sort(ids)

            local groupOptions = FindGroupOptions(options, groupKey, groupName)
            Print(("组 %s (key=%s): %d 个 NPC，选项表=%s"):format(
                groupName,
                tostring(groupKey),
                #ids,
                groupOptions and "找到" or "未找到"
            ))

            for _, npcID in ipairs(ids) do
                local npcEntry = groupOptions and groupOptions.args
                    and groupOptions.args["NPC" .. npcID]
                Print(("  NPC %s: custom=yes found=%s deleteNpc=%s pos=%s"):format(
                    tostring(npcID),
                    found[npcID] and "yes" or "no",
                    npcEntry and npcEntry.args and npcEntry.args.deleteNpc and "yes" or "no",
                    GetPositionTag(npcID)
                ))
            end
        end
    end

    local detailQuest = GetDetailQuestID()
    local apiSelected = C_QuestLog and C_QuestLog.GetSelectedQuest
        and tonumber(C_QuestLog.GetSelectedQuest()) or nil
    Print(("debug quest: detail=%s selected=%s"):format(
        tostring(detailQuest),
        tostring(apiSelected)
    ))

    local selectedQuest = GetSelectedQuestID()
    if selectedQuest then
        local combatIDs, turnInIDs = GetQuestAddableNpcGroups(selectedQuest)
        Print(("selected quest %s: combat=%d turnIn=%d"):format(
            QuestLabel(selectedQuest),
            #combatIDs,
            #turnInIDs
        ))
    end

    if not any then
        Print("没有 Q2RS_ 组")
    end
end

-----------------------------------------------------------------------
-- Startup
-----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("WORLD_MAP_OPEN")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Questie" then
        if Questie and Questie.API and Questie.API.RegisterOnReady then
            Questie.API.RegisterOnReady(OnQuestieReady)
        end
    elseif event == "PLAYER_LOGIN" then
        if Questie and Questie.API and Questie.API.RegisterOnReady then
            Questie.API.RegisterOnReady(OnQuestieReady)
        else
            Print(L.LOAD_ERROR_QUESTIE)
        end

        local ok, err = pcall(CreateMinimapButton)
        if not ok then
            Print("小地图按钮初始化失败：" .. tostring(err))
        end
        SafeInitializeQuestLogButton()

        if not _G.LibQuestieDB then
            Print(L.LOAD_ERROR_DB)
        end

        if not (SlashCmdList["ACECONSOLE_RS"] or SlashCmdList["ACECONSOLE_RARESCANNER"]) then
            Print(L.NO_RARESCANNER)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateMinimapButtonPosition()
        CleanupAutoFiltersOnLogin()
        ProcessAllGroups()
        CleanupStartItemDroppersForQuestLog()
        SafeInitializeQuestLogButton()
        SafeUpdateQuestLogButton()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        UpdateMinimapButtonPosition()
    elseif event == "QUEST_ACCEPTED" then
        ProcessQuestAccepted(arg1)
        SafeUpdateQuestLogButton()
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        local questID = tonumber(arg1)
        if questID then
            DeleteQuestGroup(questID)
        end
        SafeUpdateQuestLogButton()
    elseif event == "QUEST_LOG_UPDATE" then
        ProcessAllGroups()
        SafeInitializeQuestLogButton()
        SafeUpdateQuestLogButton()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if arg1 == "player" then
            ProcessAllGroups()
            SafeUpdateQuestLogButton()
        end
    elseif event == "WORLD_MAP_OPEN" then
        SafeInitializeQuestLogButton()
        SafeUpdateQuestLogButton()
    elseif event == "PLAYER_REGEN_ENABLED" then
        local pending = pendingGroupDeletes
        pendingGroupDeletes = {}
        for questID in pairs(pending) do
            DeleteQuestGroup(questID)
        end

        local pendingStartItems = pendingStartItemCleanup
        pendingStartItemCleanup = {}
        for questID in pairs(pendingStartItems) do
            CleanupStartItemDroppers(questID)
        end

        ProcessAllGroups()
        UpdateQuestLogButton()
    end
end)

SLASH_QUEST2RARESCANNER1 = "/q2rs"
SlashCmdList["QUEST2RARESCANNER"] = function(msg)
    local command = tostring(msg or ""):match("^%s*(.-)%s*$"):lower()
    if command == "delete" then
        RequestDeleteAll()
        return
    elseif command == "debug" then
        PrintDebug()
        return
    end

    local rareReady = (SlashCmdList["ACECONSOLE_RS"] or SlashCmdList["ACECONSOLE_RARESCANNER"]) and true or false
    Print(L.HELP_TITLE)
    Print(L.HELP_MAP)
    Print(L.HELP_GROUP)
    Print(L.HELP_CMD)
    Print(L.HELP_DEBUG)
    Print(L.STATUS:format(
        questieReady and L.READY or L.NOT_READY,
        rareReady and L.READY or L.NOT_READY,
        frameHookReady and L.READY or L.NOT_READY,
        ZoneDB and L.READY or L.NOT_READY
    ))
end
