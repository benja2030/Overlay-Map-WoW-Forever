-- Overlay Map: which other addons show on the map while Overlay Map has it open (the Addons tab). Every map
-- addon adds its own work to the map's opening and to Overlay Map's work on each marker, so one turned off here
-- is kept off the map from the moment Overlay Map opens it to the moment it closes. The normal map (M) keeps
-- every addon. Opened in a fight, nothing is changed: the game doesn't let addons change the map then.
-- The files share one table, ns, and load in the order of OverlayMap.toc (Core.lua first).

local ADDON_NAME, ns = ...
local Keep, Zone = ns.Keep, ns.Zone
local db
ns.dbSetters[#ns.dbSetters + 1] = function(t) db = t end
local Map, Canvas = ns.Map, ns.Canvas

local Addons = {}
ns.Addons = Addons

local function Loaded(name)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded(name) and true or false
end

-- (on: the addon shows, as it always did; each switch's setting is on by default)
local function Shown(key) return not db or db[key] ~= false end

--------------------------------------------------------------------------------
-- Markers drawn through HereBeDragons: Questie (its own copy) and TomTom, RXPGuides (one shared copy)
--------------------------------------------------------------------------------

-- Each copy has one data provider on the map, which draws its addon's markers every time the map is laid out.
-- The provider isn't taken off the map: Questie reads the map through it in many places and would break.
-- Instead, while Overlay Map has the map, its two drawing steps do nothing and its markers are taken away;
-- they're put back as the map closes, and the provider draws everything again at the next opening.
local function QuestieProvider()
    local L = _G.QuestieLoader
    if not (Loaded("Questie") and type(L) == "table" and L.ImportModule) then return end
    local ok, pins = pcall(L.ImportModule, L, "HBDPins")
    local p = ok and type(pins) == "table" and pins.worldmapProvider
    return type(p) == "table" and p or nil
end

local function WaypointProvider()
    local LS = _G.LibStub
    if type(LS) ~= "table" or not LS.GetLibrary then return end
    local ok, lib = pcall(LS.GetLibrary, LS, "HereBeDragons-Pins-2.0", true)
    local p = ok and type(lib) == "table" and lib.worldmapProvider
    return type(p) == "table" and p or nil
end

-- the addons of the shared copy that are here, for the switch's name
local WAYPOINT_ADDONS = { "TomTom", "RXPGuides" }
function Addons.WaypointNames()
    local here = {}
    for _, name in ipairs(WAYPOINT_ADDONS) do if Loaded(name) then here[#here + 1] = name end end
    if #here == 0 then return "Waypoint addons" end
    return table.concat(here, " and ")
end

local function Noop() end
local muted = {}    -- provider -> its own RefreshAllData and HandlePin, while they do nothing

local function Mute(p)
    if muted[p] then return true end
    local refresh, handle = rawget(p, "RefreshAllData"), rawget(p, "HandlePin")
    if type(refresh) ~= "function" or type(handle) ~= "function" then return false end
    muted[p] = { refresh, handle }
    p.RefreshAllData, p.HandlePin = Noop, Noop
    -- (its markers from the last time the map showed, taken away: the map isn't laid out without them otherwise)
    if p.GetMap and p:GetMap() and p.RemoveAllData then pcall(p.RemoveAllData, p) end
    return true
end

local function Unmute(p)
    local saved = muted[p]
    if not saved then return end
    muted[p] = nil
    p.RefreshAllData, p.HandlePin = saved[1], saved[2]
    -- (Questie's copy draws again only when the map changed, or when told to)
    p.forceUpdate = true
    local map = Map()
    if map and map:IsShown() and not InCombatLockdown() and p.GetMap and p:GetMap() then pcall(p.RefreshAllData, p) end
end

--------------------------------------------------------------------------------
-- OpenMap: its map picture, and its icons
--------------------------------------------------------------------------------

-- OpenMap lays its stitched world over the game's map every time the map is laid out, as long as its world map
-- module is on (and the map is one it stitches: off in dungeons, cities without art...). Turned off, it leaves
-- the game's own map as it is, as it does on those maps, its icons and upkeep with it. The module is turned off
-- only while Overlay Map has the map (a flag of OpenMap's, never saved), and the map laid out again each way.
local held = {}     -- om: OpenMap's module, turned off; omLater: laid out again once the fight ends; wph: see below

local function Relayout()
    local c = Canvas()
    if c and c.CreateZoomLevels then pcall(c.CreateZoomLevels, c) end
end

local function HoldOpenMap()
    local om = Zone.OpenMapModule()
    if not om or om.enabled ~= true or om.padWaits then return false end
    om.enabled = false
    held.om, held.omLater = om, nil
    Relayout()   -- (OpenMap leaves the map to the game now, before it opens: its own picture never shows)
    return true
end

local function ReleaseOpenMap()
    local om = held.om
    if not om then return end
    held.om = nil
    if om.enabled == false and not om.padWaits then om.enabled = true end
    -- (in a fight OpenMap leaves the map as it is anyway: once it's over)
    if InCombatLockdown() then held.omLater = true return end
    Relayout()
end

function Addons.OpenMapHeld() return held.om ~= nil end

-- Its icons only (with its map on): OpenMap asks S.WorldPinsHidden whether each group of icons is kept hidden
-- (its own "hide world icons inside dungeons"). While Overlay Map has the map, every group but Overlay Map's
-- own (cave entrances, the fight arrow) is.
local ANY_SET = { "quests", "questoffers", "flight", "routes", "dungeons", "userpins", "overlaymapCaveMouths",
    "overlaymapFightArrow" }
local function ShowSetsAgain(S)
    if not (S.GetPinSet and S.SetPinSetOn) then return end
    for _, key in ipairs(ANY_SET) do
        local ok, set = pcall(S.GetPinSet, key)
        if ok and type(set) == "table" then pcall(S.SetPinSetOn, set, set.on) return end
    end
end

local function HoldOpenMapIcons()
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    if not (S and type(S.WorldPinsHidden) == "function") or held.wph then return held.wph ~= nil end
    local own = S.WorldPinsHidden
    held.wph = own
    S.WorldPinsHidden = function(key, ...)
        if type(key) == "string" and key:sub(1, 10) ~= "overlaymap" then return true end
        return own(key, ...)
    end
    ShowSetsAgain(S)
    return true
end

local function ReleaseOpenMapIcons()
    local own = held.wph
    if not own then return end
    held.wph = nil
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    if not S then return end
    S.WorldPinsHidden = own
    ShowSetsAgain(S)
end

-- OpenMap's icons not on the map now (its map or its icons kept off): Overlay Map's work on them is skipped
function Addons.OpenMapIconsOff() return held.om ~= nil or held.wph ~= nil end

--------------------------------------------------------------------------------
-- Dungeon Journal: its dungeon map, lent to the map window inside its dungeons
--------------------------------------------------------------------------------

-- Its own setting (ForeverDungeonJournalDB.worldMapOverlay) is read every time the map opens; it's set off while
-- Overlay Map has the map, and back as it closes. Overlay Map notes that it did (in its own saved settings), so a
-- reload or crash in between puts it back at the next login.
local function HoldJournal()
    local d = _G.ForeverDungeonJournalDB
    if type(d) ~= "table" or d.worldMapOverlay == false then return false end
    db.addonsHeld = db.addonsHeld or {}
    db.addonsHeld.journal = d.worldMapOverlay == nil and "default" or d.worldMapOverlay
    d.worldMapOverlay = false
    return true
end

local function ReleaseJournal()
    local was = db and db.addonsHeld and db.addonsHeld.journal
    if was == nil then return end
    db.addonsHeld.journal = nil
    if not next(db.addonsHeld) then db.addonsHeld = nil end
    local d = _G.ForeverDungeonJournalDB
    if type(d) == "table" and d.worldMapOverlay == false then
        if was == "default" then d.worldMapOverlay = nil else d.worldMapOverlay = was end
    end
end

--------------------------------------------------------------------------------
-- The switches, as Overlay Map opens and closes the map
--------------------------------------------------------------------------------

-- Each switch: its setting, its name, and whether that addon is here (the switch is greyed out otherwise)
Addons.LIST = {
    { key = "showQuestie", name = "Questie", here = function() return QuestieProvider() ~= nil end },
    { key = "showWaypoints", name = function() return Addons.WaypointNames() end,
        here = function() return WaypointProvider() ~= nil end },
    { key = "showOpenMap", name = "OpenMap's map", here = function() return Zone.OpenMapModule() ~= nil end },
    { key = "showOpenMapIcons", name = "OpenMap's icons",
        here = function() return Zone.OpenMapModule() ~= nil and Shown("showOpenMap") end },
    { key = "showDungeonJournal", name = "Dungeon Journal's dungeon maps",
        here = function() return Loaded("ForeverDungeonJournal") and type(_G.ForeverDungeonJournalDB) == "table" end },
}

-- Just before Overlay Map opens the map (out of combat)
function Addons.Hold()
    Addons.note, Addons.holdMs = nil, nil
    if not db then return end
    if InCombatLockdown() then
        Addons.note = "opened in a fight: every addon left on the map"
        return
    end
    local t0 = debugprofilestop()
    local off = {}
    if not Shown("showQuestie") then
        local p = QuestieProvider()
        if p and Mute(p) then off[#off + 1] = "Questie" end
    end
    if not Shown("showWaypoints") then
        local p = WaypointProvider()
        if p and Mute(p) then off[#off + 1] = Addons.WaypointNames() end
    end
    if not Shown("showOpenMap") then
        if HoldOpenMap() then off[#off + 1] = "OpenMap's map" end
    elseif not Shown("showOpenMapIcons") then
        if HoldOpenMapIcons() then off[#off + 1] = "OpenMap's icons" end
    end
    if not Shown("showDungeonJournal") then
        if HoldJournal() then off[#off + 1] = "Dungeon Journal's map" end
    end
    Addons.holdMs = debugprofilestop() - t0
    Addons.note = #off > 0 and ("kept off: " .. table.concat(off, ", ")) or "none kept off"
end

-- As Overlay Map's map closes (or didn't open after all): everything as it was
function Addons.Release()
    for p in pairs(muted) do Unmute(p) end
    ReleaseOpenMapIcons()
    ReleaseOpenMap()
    ReleaseJournal()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- (a reload or crash with the map open: Dungeon Journal's setting back as it was)
        if db and db.addonsHeld then ReleaseJournal() end
    elseif held.omLater and not held.om then
        held.omLater = nil
        if not ns.compact then Relayout() end
    end
end)

-- For /omap debug
function Addons.DebugLine()
    local parts = {}
    for _, s in ipairs(Addons.LIST) do
        local okHere, here = pcall(s.here)
        if okHere and here then
            local name = type(s.name) == "function" and s.name() or s.name
            parts[#parts + 1] = name .. (Shown(s.key) and " on" or " off")
        end
    end
    local line = "Addons on the map: " .. (#parts > 0 and table.concat(parts, ", ") or "none of the switchable ones here")
    if Addons.note then
        line = line .. "; last opening " .. Addons.note .. (Addons.holdMs and string.format(" (%.1f ms)", Addons.holdMs) or "")
    end
    return line
end
