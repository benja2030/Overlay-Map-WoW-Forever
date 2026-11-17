-- Quick Map
-- Shows the game's own map of your zone with a key, without its border, buttons and quest log.
-- It uses the real map, so every marker on it shows too, including other addons' (Questie...).
-- The map is put back exactly as it was when Quick Map closes it, or when you open it normally.

local ADDON_NAME = ...

BINDING_NAME_QUICKMAP_SHOW = "Show the map"

local DEFAULTS = {
    mode = "hold",   -- "hold": shown while the key is held; "press": one press shows, the next hides
    scale = 0.8,     -- size of the map
    width = 1,       -- width of the map compared to its usual shape (lower: more square)
    opacity = 0.85,  -- opacity of the map itself
    pinOpacity = 1,  -- opacity of the markers on it (quests, vendors, your arrow...)
    noFade = true,   -- keep that opacity while moving (the game fades the map while you move)
    hideMinimap = true, -- hide the minimap while the map is open
    follow = false,  -- keep the map centred on you while it's open, like the minimap
    hideBars = false, hideUnits = false, hideChat = false, hideQuests = false, -- other parts of the
    hideBuffs = false, hideMenu = false, hideXP = false,                       -- interface hidden too
    buttonMode = "hover", -- the options button on the map: "show", "hover" (with the mouse over the map), "hide"
    buttonOpacity = 0.8,
    x = 0, y = 0,    -- position of the map's centre, from the centre of the screen
}

local db
local compact = false   -- the map is open in Quick Map's look
local hidden = {}       -- frame or texture -> { alpha, mouse } it had before Quick Map hid it
local stopped = {}      -- frames Quick Map hid completely (they stop working until shown again)
-- Frames as big as the map area that other addons put on it for their icons (OpenMap draws its
-- vendors, mailboxes, flight points and its own arrow on one): kept, and given the objectives'
-- opacity like the map's markers. frame -> true
local iconLayers = {}
local before = {}       -- the map's own scale and the map area's opacity before Quick Map changed them

local function Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffQuick Map:|r " .. msg)
end

local function Map() return WorldMapFrame end
local function Canvas() return WorldMapFrame and WorldMapFrame.ScrollContainer end

--------------------------------------------------------------------------------
-- Hiding everything around the map area
--------------------------------------------------------------------------------

-- Fades one piece to nothing and stops it from taking the mouse, remembering how it was.
local function Conceal(obj)
    if not obj or obj == Canvas() or hidden[obj] then return end
    local entry = { alpha = obj:GetAlpha() }
    if obj.IsMouseEnabled then entry.mouse = obj:IsMouseEnabled() end
    hidden[obj] = entry
    obj:SetAlpha(0)
    if entry.mouse then pcall(obj.EnableMouse, obj, false) end
end

-- Hides a frame completely, so its scripts stop too (a coordinates display that updates every
-- frame, for example). Shown again on close.
local function Stop(f)
    if not f or f == Canvas() or stopped[f] or not f:IsShown() then return end
    if pcall(f.Hide, f) then stopped[f] = true end
end

-- The game's own pieces that it shows and hides by itself: these are only made invisible,
-- so the game is not confused. Anything else on the map frame comes from other addons.
local function GameOwned(map)
    local owned = {}
    for _, key in ipairs({ "ScrollContainer", "TitleCanvasSpacerFrame", "BlackoutFrame", "NavBar",
                           "SidePanelToggle", "QuestLog" }) do
        if map[key] then owned[map[key]] = true end
    end
    for _, f in ipairs(map.overlayFrames or {}) do owned[f] = true end
    return owned
end

-- Everything on the map frame except the map area itself: its border, title, buttons on the
-- sides, the quest log, and what other addons put there (coordinates, extra buttons...).
-- Markers are inside the map area, so they stay.
local function ConcealAll()
    local map = Map()
    local owned = GameOwned(map)
    -- The border (title, close button, portrait) and other addons' frames are hidden
    -- completely: nothing of theirs keeps running while the map shows.
    Stop(map.BorderFrame)
    for _, child in ipairs({ map:GetChildren() }) do
        if child ~= map.BorderFrame and not owned[child] then Stop(child) end
    end
    for _, child in ipairs({ map:GetChildren() }) do Conceal(child) end
    -- Boxes other addons put inside the map area (a coordinates box, for example) are hidden;
    -- a frame covering the whole map area holds icons, so it stays.
    local c = Canvas()
    local cw, ch = c:GetSize()
    for _, child in ipairs({ c:GetChildren() }) do
        if child ~= c.Child and not iconLayers[child] then
            local w, h = child:GetSize()
            if math.abs(w - cw) < 2 and math.abs(h - ch) < 2 then
                iconLayers[child] = true
            else
                Stop(child)
            end
        end
    end
    for _, region in ipairs({ map:GetRegions() }) do Conceal(region) end
    -- The buttons on the edges are drawn over the map area but belong to the map frame.
    for _, f in ipairs(map.overlayFrames or {}) do Conceal(f) end
end

local function RevealAll()
    for obj, entry in pairs(hidden) do
        obj:SetAlpha(entry.alpha or 1)
        if entry.mouse then pcall(obj.EnableMouse, obj, true) end
    end
    wipe(hidden)
    for f in pairs(stopped) do pcall(f.Show, f) end
    wipe(stopped)
end

--------------------------------------------------------------------------------
-- Size, opacity, position
--------------------------------------------------------------------------------

-- OpenMap keeps the map window where it saved it, and puts it back the moment anything else
-- moves it. With OpenMap, the window is left where it is (invisible) and only the map area
-- inside it is moved to Quick Map's spot. Without it, the window itself is moved.
local function OpenMapLoaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded("OpenMap") and true or false
end

local function AnchorCanvas()
    local map, c = Map(), Canvas()
    c:ClearAllPoints()
    if OpenMapLoaded() then
        local k = UIParent:GetEffectiveScale() / c:GetEffectiveScale()
        c:SetPoint("CENTER", UIParent, "CENTER", db.x * k, db.y * k)
    else
        c:SetPoint("CENTER", map, "CENTER", 0, 0)
    end
end

local function Place()
    local map, canvas = Map(), Canvas()
    if OpenMapLoaded() then
        AnchorCanvas()
        return
    end
    map:ClearAllPoints()
    map:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- Move the frame so the map area, not the whole frame, sits at the chosen spot.
    local fx, fy = map:GetCenter()
    local cx, cy = canvas:GetCenter()
    local s = map:GetScale()
    if fx and cx then
        map:ClearAllPoints()
        map:SetPoint("CENTER", UIParent, "CENTER", fx - cx + db.x / s, fy - cy + db.y / s)
    end
end

-- The minimap is hidden while the map shows, and shown again only if Quick Map hid it.
-- Other parts of the interface hidden while the map is open, each group with its own option.
-- Frames that don't exist (another client, an addon not installed) are skipped.
local HIDE_GROUPS = {
    { key = "hideBars", label = "Action Bars", frames = {
        "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
        "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar",
        "PossessActionBar", "MainMenuBarVehicleLeaveButton" } },
    { key = "hideUnits", label = "Player and Target Frames", frames = {
        "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "TargetFrameToT" } },
    { key = "hideChat", label = "Chat", frames = { "GeneralDockManager", "ChatFrameMenuButton",
        "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
        "QuickJoinToastButton" }, chat = true },
    { key = "hideQuests", label = "Quest Tracker", frames = { "ObjectiveTrackerFrame", "Questie_BaseFrame" } },
    { key = "hideBuffs", label = "Buffs and Debuffs", frames = { "BuffFrame", "DebuffFrame" } },
    { key = "hideMenu", label = "Menu and Bags", frames = { "MicroMenuContainer", "MicroMenu", "BagsBar" } },
    { key = "hideXP", label = "Experience Bar", frames = { "MainStatusTrackingBarContainer",
        "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager", "SmoothExperienceBarFrame" } },
}

local function GroupFrames(group)
    local list = {}
    for _, name in ipairs(group.frames) do
        if _G[name] then list[#list + 1] = _G[name] end
    end
    if group.chat then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            for _, suffix in ipairs({ "", "Tab", "EditBox", "ButtonFrame" }) do
                local f = _G["ChatFrame" .. i .. suffix]
                if f then list[#list + 1] = f end
            end
        end
    end
    return list
end

-- These are faded to nothing rather than hidden: action bars and unit frames can't be hidden by
-- an addon in combat, but they can be made invisible. frame -> alpha it had
local faded = {}

local function HideExtras()
    local want = {}
    for _, group in ipairs(HIDE_GROUPS) do
        if db[group.key] then
            for _, f in ipairs(GroupFrames(group)) do want[f] = true end
        end
    end
    -- (groups turned off since: back as they were)
    for f, alpha in pairs(faded) do
        if not want[f] then
            f:SetAlpha(alpha)
            faded[f] = nil
        end
    end
    for f in pairs(want) do
        if faded[f] == nil then faded[f] = f:GetAlpha() end
        if f:GetAlpha() > 0 then f:SetAlpha(0) end
    end
end

local function ShowExtras()
    for f, alpha in pairs(faded) do f:SetAlpha(alpha) end
    wipe(faded)
end

-- The minimap is hidden while the map shows, and shown again only if Quick Map hid it. Addons
-- like SexyMap take the minimap out of its usual frame (it's then on its own, with its clock,
-- zone name and buttons on it), so both are hidden. In combat, if the minimap holds something
-- protected (SexyMap's zone button can be), it is made invisible instead.
local minimapHidden = {} -- frame -> "hide" or the alpha it had

local function MinimapFrames()
    local list = {}
    if MinimapCluster then list[#list + 1] = MinimapCluster end
    if Minimap and Minimap:GetParent() ~= MinimapCluster then list[#list + 1] = Minimap end
    return list
end

local function HideMinimap()
    if not db.hideMinimap then return end
    for _, f in ipairs(MinimapFrames()) do
        if minimapHidden[f] == nil and f:IsShown() then
            if not (InCombatLockdown() and f:IsProtected()) and pcall(f.Hide, f) and not f:IsShown() then
                minimapHidden[f] = "hide"
            else
                minimapHidden[f] = f:GetAlpha()
                f:SetAlpha(0)
            end
        elseif type(minimapHidden[f]) == "number" and f:GetAlpha() > 0 then
            f:SetAlpha(0)
        end
    end
end

local function ShowMinimap()
    for f, how in pairs(minimapHidden) do
        if how == "hide" then
            if not (InCombatLockdown() and f:IsProtected()) then pcall(f.Show, f) end
        else
            f:SetAlpha(how)
        end
    end
    wipe(minimapHidden)
end

-- Size and shape. Other map addons (OpenMap, for one) keep the map frame at their own scale,
-- so the map frame's scale is left alone: the map area inside it is scaled instead, kept at
-- its own size (or narrower or wider, for the shape) and centred in the frame. Its original
-- anchors are put back on close.
local appliedW -- width the map area was last given, to know when the map must re-fit
local SyncLayer, QueueRefit, Refit, ApplyLook -- (further down)

-- With a different shape, the map is zoomed so it fills the whole area (the edges that don't
-- fit are cut off), centred on you.
local function Fill()
    local map, c = Map(), Canvas()
    if not compact or math.abs(db.width - 1) < 0.001 or not c.InstantPanAndZoom then return end
    local mapID = map.GetMapID and map:GetMapID()
    local layers = mapID and C_Map.GetMapArtLayers(mapID)
    local art = layers and layers[1]
    if not art or not art.layerWidth or art.layerWidth == 0 then return end
    local fill = math.max(c:GetWidth() / art.layerWidth, c:GetHeight() / art.layerHeight)
    local x, y = 0.5, 0.5
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if ok and pos then
        local px, py = pos:GetXY()
        local secret = issecretvalue and (issecretvalue(px) or issecretvalue(py))
        if not secret and px and py and px > 0 and py > 0 then x, y = px, py end
    end
    pcall(c.InstantPanAndZoom, c, fill, x, y, true)
end

local function ApplySize()
    local map, c = Map(), Canvas()
    if not before.points then
        before.points = {}
        for i = 1, c:GetNumPoints() do before.points[i] = { c:GetPoint(i) } end
        before.cw, before.ch = c:GetSize()
        before.cscale = c:GetScale()
        -- Remembered for the "Move" box: the map area's size on screen at 100%.
        local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        db.areaW, db.areaH = before.cw * k, before.ch * k
    end
    c:SetScale(db.scale)
    local w = before.cw * db.width
    c:SetSize(w, before.ch)
    AnchorCanvas()
    if appliedW ~= w then
        appliedW = w
        Refit()
    end
    SyncLayer()
end

local function RestoreSize()
    if not before.points then return end
    local map, c = Map(), Canvas()
    c:SetScale(before.cscale or 1)
    c:ClearAllPoints()
    c:SetSize(before.cw, before.ch)
    for _, pt in ipairs(before.points) do c:SetPoint(unpack(pt)) end
    if appliedW and appliedW ~= before.cw and map.OnFrameSizeChanged then
        pcall(map.OnFrameSizeChanged, map)
    end
    appliedW = nil
end

-- Opacity. The map frame is drawn as one picture and then faded as a whole (the game made it
-- that way so its layers don't show through each other), so the map's opacity is set on the
-- map frame. Everything inside it fades with it, markers too, so when the markers need a
-- different opacity they are moved onto a see-through layer of Quick Map's own, laid exactly
-- over the map area, with the same size and zoom. They stay anchored to the same spots on
-- the map, and go back to the map when it closes.
local MAP_ART = {
    MapExplorationPinTemplate = true, FogOfWarPinTemplate = true, MapHighlightPinTemplate = true,
    WorldMapInvasionOverlayPinTemplate = true, WorldMapThreatOverlayPinTemplate = true,
}
local layer         -- Quick Map's layer for the markers
local moved = {}    -- marker -> true while it is on that layer
local hookedPins = setmetatable({}, { __mode = "k" })
local reparenting = false

local function Content() return Canvas().Child end

-- Keeps the layer over the map area, at the zoom the map has right now.
-- The same for icon frames that don't zoom with the map (they sit on the map area itself).
local viewLayer
local viewMoved = {} -- frame -> { level } while it is on viewLayer

-- Markers go one frame strata above the map, so the map (drawn as one picture) can never end
-- up over them.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local function Above(strata)
    for i, name in ipairs(STRATA) do
        if name == strata then return STRATA[math.min(i + 1, #STRATA - 1)] end
    end
    return "DIALOG"
end

SyncLayer = function()
    local map = Map()
    if viewLayer then
        viewLayer:SetScale(Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale())
        viewLayer:ClearAllPoints()
        viewLayer:SetAllPoints(Canvas())
        viewLayer:SetFrameStrata(Above(map:GetFrameStrata()))
        viewLayer:SetFrameLevel(map:GetFrameLevel() + 1)
    end
    if not layer then return end
    local content = Content()
    layer:SetScale(content:GetEffectiveScale() / UIParent:GetEffectiveScale())
    layer:ClearAllPoints()
    layer:SetAllPoints(Canvas())
    layer:SetFrameStrata(Above(map:GetFrameStrata()))
    layer:SetFrameLevel(map:GetFrameLevel() + 1)
end

local function MovePin(pin)
    if not hookedPins[pin] then
        hookedPins[pin] = true
        -- The map puts its markers back on itself whenever it places them again (zooming,
        -- new markers); while Quick Map shows it, they go straight back to the layer.
        hooksecurefunc(pin, "SetParent", function(self, parent)
            if reparenting or not compact or not moved[self] or parent == layer then return end
            local level = self:GetFrameLevel()
            reparenting = true
            self:SetParent(layer)
            reparenting = false
            self:SetFrameLevel(level)
        end)
    end
    if pin:GetParent() ~= layer then
        -- A new parent resets a frame's level, which would put the marker under the map
        -- (out of reach of the mouse, so no tooltip); it keeps the level the map gave it.
        local level = pin:GetFrameLevel()
        moved[pin] = true
        reparenting = true
        pin:SetParent(layer)
        reparenting = false
        pin:SetFrameLevel(level)
    end
end

local function ReturnPins()
    local content = Content()
    reparenting = true
    for pin in pairs(moved) do
        local level = pin:GetFrameLevel()
        pin:SetParent(content)
        pin:SetFrameLevel(level)
    end
    reparenting = false
    wipe(moved)
    if layer then layer:Hide() end
    local c = Canvas()
    for f, was in pairs(viewMoved) do
        f:SetParent(c)
        f:SetFrameLevel(was.level)
    end
    wipe(viewMoved)
    if viewLayer then viewLayer:Hide() end
end

-- For a moment after opening, the game and other addons are still laying the map out; it stays
-- invisible until that is done, so the normal map doesn't flash on screen.
local settling = false

-- A new width: the map works out its zoom again for the new shape. That's done once the width
-- stops changing (not on every step of a slider), with the map hidden for that moment, since
-- the map (and OpenMap) lay it out over a few frames.
local refitTimer

local function RefitNow()
    local map = Map()
    if map.OnFrameSizeChanged then pcall(map.OnFrameSizeChanged, map) end
    Fill()
end

-- While the map is still hidden (just opened), at once; otherwise once the width settles.
Refit = function()
    if settling then RefitNow() else QueueRefit() end
end

QueueRefit = function()
    if refitTimer then refitTimer:Cancel() end
    refitTimer = C_Timer.NewTimer(0.25, function()
        refitTimer = nil
        if not compact then return end
        local map = Map()
        local wasSettling = settling
        settling = true
        map:SetAlpha(0)
        if layer then layer:SetAlpha(0) end
        if viewLayer then viewLayer:SetAlpha(0) end
        RefitNow()
        C_Timer.After(0.15, function()
            if not compact then return end
            settling = wasSettling
            ApplyLook()
        end)
    end)
end

local function ApplyOpacity()
    local map = Map()
    -- The game fades the map while you move; Quick Map does it itself (to half) when
    -- "Keep Opacity While Moving" is off, so it works with these opacities.
    local fade = (not db.noFade and IsPlayerMoving and IsPlayerMoving()) and 0.5 or 1
    if settling then fade = 0 end
    local mapAlpha = db.opacity * fade
    if math.abs(map:GetAlpha() - mapAlpha) > 0.001 then map:SetAlpha(mapAlpha) end

    if math.abs(db.pinOpacity - db.opacity) < 0.001 then
        if next(moved) then ReturnPins() end
        return
    end
    if not layer then
        layer = CreateFrame("Frame", "QuickMapMarkers", UIParent)
        layer:SetClipsChildren(true) -- markers outside the map area are cut off, like on the map
    end
    if not viewLayer then
        viewLayer = CreateFrame("Frame", "QuickMapIcons", UIParent)
        viewLayer:SetClipsChildren(true)
    end
    SyncLayer()
    layer:SetAlpha(db.pinOpacity * fade)
    layer:Show()
    viewLayer:SetAlpha(db.pinOpacity * fade)
    viewLayer:Show()
    for f in pairs(iconLayers) do
        if f:GetParent() ~= viewLayer then
            local level = f:GetFrameLevel()
            viewMoved[f] = viewMoved[f] or { level = level }
            f:SetParent(viewLayer)
            f:SetFrameLevel(level)
        end
    end
    for template, pool in pairs(map.pinPools or {}) do
        if not MAP_ART[template] and pool.EnumerateActive then
            for pin in pool:EnumerateActive() do MovePin(pin) end
        end
    end
end

local function RestoreOpacity()
    ReturnPins()
end

-- While the map is open, a few times a second: new markers get their opacity, and anything the
-- game or another addon showed again is hidden again. Nothing runs while the map is closed.
local watcher = CreateFrame("Frame")
watcher:Hide()
local watchAcc = 0
-- Following you: the map's view is moved to where you are, ten times a second, only while you
-- move. With OpenMap its own API glides its map there (it doesn't let other addons move its view
-- any other way). Without it, the game's map pans there; it can only pan when it is zoomed in
-- (zoomed all the way out, the whole zone already fits).
local followAcc, lastX, lastY = 0, nil, nil

local function PlayerOnMap(mapID)
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then return end
    local x, y = pos:GetXY()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end -- (hidden in instances)
    if not x or not y or (x == 0 and y == 0) then return end
    return x, y
end

local function Follow(force)
    local api = OpenMapLoaded() and _G.OpenMapAPI
    if api and api.IsStitched and api.IsStitched() then
        local best = C_Map.GetBestMapForUnit("player")
        if not best then return end
        local x, y = PlayerOnMap(best)
        if not x then return end
        if not force and lastX and math.abs(x - lastX) < 1e-4 and math.abs(y - lastY) < 1e-4 then return end
        lastX, lastY = x, y
        local u, v = api.WorldFromMap(best, x, y)
        if u then pcall(api.ShowWorld, u, v) end
        return
    end
    local map, c = Map(), Canvas()
    local x, y = PlayerOnMap(map:GetMapID())
    if not x or not c.SetPanTarget then return end
    if not force and lastX and math.abs(x - lastX) < 1e-4 and math.abs(y - lastY) < 1e-4 then return end
    lastX, lastY = x, y
    pcall(c.SetPanTarget, c, x, y)
end

watcher:SetScript("OnUpdate", function(self, elapsed)
    if not compact then self:Hide(); return end
    if db.follow and not settling then
        followAcc = followAcc + elapsed
        if followAcc >= 0.1 then
            followAcc = 0
            Follow(lastX == nil)
        end
    else
        lastX, lastY = nil, nil -- (turned on again: centred at once, even standing still)
    end
    watchAcc = watchAcc + elapsed
    if watchAcc < 0.2 then return end
    watchAcc = 0
    for obj in pairs(hidden) do
        if obj:GetAlpha() > 0 then obj:SetAlpha(0) end
    end
    if math.abs(Canvas():GetScale() - db.scale) > 0.001 then ApplySize() end
    ApplyOpacity()
    for f in pairs(faded) do
        if f:GetAlpha() > 0 then f:SetAlpha(0) end
    end
    if db.hideMinimap then HideMinimap() end
end)

local UpdateMapButton -- (the options button on the map, further down)

ApplyLook = function()
    if not compact then return end
    local map = Map()
    ApplySize()
    ApplyOpacity()
    if PlayerMovementFrameFader and PlayerMovementFrameFader.RemoveFrame then
        PlayerMovementFrameFader.RemoveFrame(map)
    end
    Place()
    if db.hideMinimap then HideMinimap() else ShowMinimap() end
    HideExtras()
    UpdateMapButton()
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

local DISPLAY_MINIMIZED_NO_LOG = 2 -- the game's own state: small map without the quest log

local function Blocked()
    if InCombatLockdown() and Map():IsProtected() then
        Say("The map can't be opened by an addon in combat right now.")
        return true
    end
end

-- Takes the map out of Quick Map's look and gives it back to the game.
local function Restore()
    if not compact then return end
    compact = false
    local map = Map()
    RevealAll()
    ShowMinimap()
    ShowExtras()
    RestoreSize()
    RestoreOpacity()
    wipe(iconLayers)
    settling = false
    map:SetAlpha(before.alpha or 1)
    if before.mouse then map:EnableMouse(true) end
    UpdateMapButton()
    wipe(before)
    if map:IsShown() then
        map:ClearAllPoints()
        if UpdateUIPanelPositions then UpdateUIPanelPositions(map) end
    end
end

local function Open()
    local map = Map()
    if not map or compact then return end
    if map:IsShown() then return end -- already open the normal way: leave it alone
    if Blocked() then return end

    -- Open it small and without the quest log. The game decides small or full screen from
    -- "miniWorldMap" as it opens, so that setting is set for this one opening and put back
    -- right after; nothing else reads it.
    local mini = GetCVar("miniWorldMap")
    if mini ~= "1" then pcall(SetCVar, "miniWorldMap", "1") end
    local ok = pcall(map.SetDisplayState, map, DISPLAY_MINIMIZED_NO_LOG)
    if mini ~= "1" then pcall(SetCVar, "miniWorldMap", mini) end
    if not ok or not map:IsShown() then return end

    compact = true
    before.alpha = map:GetAlpha()
    -- The map frame stays its full size around the smaller map area; it must not take clicks.
    before.mouse = map:IsMouseEnabled()
    if before.mouse then map:EnableMouse(false) end
    settling = true
    ConcealAll()
    ApplyLook()
    watchAcc = 0
    lastX, lastY = nil, nil
    watcher:Show()
    -- The game's window layout and other map addons may still change things during the next
    -- frames: hide and apply everything once more, then show the map.
    C_Timer.After(0.05, function()
        if not compact then return end
        ConcealAll()
        for obj in pairs(hidden) do
            if obj:GetAlpha() > 0 then obj:SetAlpha(0) end
        end
        settling = false
        ApplyLook()
    end)
end

local function Close()
    if not compact then return end
    local map = Map()
    if HideUIPanel then HideUIPanel(map) else map:Hide() end
    Restore() -- in case hiding did not reach the OnHide hook
end

function QuickMap_OnKey(keystate)
    if not db or not Map() then return end
    if db.mode == "hold" then
        if keystate == "down" then Open() else Close() end
    elseif keystate == "down" then
        if compact then Close() else Open() end
    end
end

local function HookMap()
    local map = Map()
    if not map or map.QuickMapHooked then return end
    map.QuickMapHooked = true
    -- Closed by Esc, by another window, or anything else: put everything back.
    map:HookScript("OnHide", Restore)
    -- Opened the normal way (M, L, a quest link) while Quick Map shows it: the game takes over.
    for _, method in ipairs({ "HandleUserActionToggleSelf", "HandleUserActionToggleQuestLog",
                              "HandleUserActionOpenSelf", "HandleUserActionOpenQuestLog" }) do
        if map[method] then hooksecurefunc(map, method, Restore) end
    end
    -- Zooming the map: the markers' layer zooms with it right away.
    if map.OnCanvasScaleChanged then
        hooksecurefunc(map, "OnCanvasScaleChanged", function()
            if compact and layer and layer:IsShown() then SyncLayer() end
        end)
    end
    -- New markers: move them onto the layer on the next frame instead of waiting.
    if map.AcquirePin then
        local pending = false
        hooksecurefunc(map, "AcquirePin", function()
            if not compact or pending or not (layer and layer:IsShown()) then return end
            pending = true
            C_Timer.After(0, function()
                pending = false
                if compact then ApplyOpacity() end
            end)
        end)
    end
    -- Another zone shown while Quick Map shows the map: fill the shape again.
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function()
            if compact then C_Timer.After(0, Fill) end
        end)
    end
    -- Other windows opening move the map back to its usual spot; keep it where it was put.
    if UpdateUIPanelPositions then
        hooksecurefunc("UpdateUIPanelPositions", function()
            if compact then Place() end
        end)
    end
end

--------------------------------------------------------------------------------
-- Moving it: a box the size of the map that can be dragged
--------------------------------------------------------------------------------

local mover

local function ShowMover()
    if not mover then
        mover = CreateFrame("Frame", "QuickMapMover", UIParent, "BackdropTemplate")
        mover:SetFrameStrata("FULLSCREEN")
        mover:SetMovable(true)
        mover:EnableMouse(true)
        mover:RegisterForDrag("LeftButton")
        mover:SetClampedToScreen(true)
        mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        mover:SetBackdropColor(0.1, 0.4, 0.8, 0.35)
        mover:SetBackdropBorderColor(0.4, 0.75, 1, 1)
        local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("CENTER")
        text:SetText("Quick Map\nDrag to move. Right-click when done.")
        -- The box's centre is the map's: saved, and the open map follows it as it's dragged.
        local function Save(self)
            local x, y = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            local k = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            db.x, db.y = x * k - ux, y * k - uy
            if compact then
                Place()
                SyncLayer()
                UpdateMapButton()
            end
        end
        mover:SetScript("OnDragStart", function(self)
            self:StartMoving()
            self:SetScript("OnUpdate", Save)
        end)
        mover:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self:StopMovingOrSizing()
            self:SetUserPlaced(false)
            Save(self)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        end)
        mover:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then self:Hide() end
        end)
    end
    -- The map area's size, as measured the last time Quick Map opened it.
    mover:SetSize((db.areaW or 702) * db.scale * db.width, (db.areaH or 467) * db.scale)
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    mover:Show()
end

--------------------------------------------------------------------------------
-- The options button on the map, and the small panel it opens
--------------------------------------------------------------------------------

local mapButton, panel

local function Round(v, step) return math.floor(v / step + 0.5) * step end

-- Size and width from the panel wait for its Apply button (changing them is a whole new layout
-- of the map); key -> value chosen, not applied yet
local pending = {}

-- Applies a new size or width with the map hidden for a moment, so the new layout isn't seen
-- being worked out.
local function ApplyShape()
    if not compact then return end
    settling = true
    ApplyOpacity()   -- (hidden while settling)
    ApplyLook()      -- (the map re-fits at once while it's hidden)
    C_Timer.After(0.15, function()
        if not compact then return end
        settling = false
        ApplyLook()
    end)
end

-- A plain slider: label on the left, value on the right, the bar under them.
local function PanelSlider(parent, y, key, label, minValue, maxValue, step, deferred)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 12, y)
    text:SetText(label)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("TOPRIGHT", -12, y)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 12, y - 16)
    s:SetPoint("TOPRIGHT", -12, y - 16)
    s:SetHeight(14)
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.5, 0.4, 0.18, 1)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    s:GetThumbTexture():SetSize(8, 14)
    s:GetThumbTexture():SetVertexColor(1, 0.85, 0.3, 1)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.max(minValue, math.min(maxValue, self:GetValue() + delta * step)))
    end)
    s:SetScript("OnValueChanged", function(self, v)
        v = Round(v, step)
        value:SetText(string.format("%d%%", v * 100 + 0.5))
        if self.silent then return end
        if deferred then
            pending[key] = math.abs((db[key] or 0) - v) > 0.0001 and v or nil
            if parent.UpdateApply then parent:UpdateApply() end
            return
        end
        if math.abs((db[key] or 0) - v) < 0.0001 then return end
        db[key] = v
        ApplyLook()
    end)
    function s:Refresh()
        pending[key] = nil
        self.silent = true
        self:SetValue(db[key])
        self.silent = false
        value:SetText(string.format("%d%%", db[key] * 100 + 0.5))
    end
    return s
end

local function PanelCheck(parent, y, key, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", 8, y)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        ApplyLook()
    end)
    function cb:Refresh() self:SetChecked(db[key] and true or false) end
    return cb
end

-- A button that steps through a few choices: "Label: Choice"
local function PanelCycle(parent, y, key, label, choices)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", 10, y)
    b:SetPoint("TOPRIGHT", -10, y)
    function b:Refresh()
        for _, c in ipairs(choices) do
            if c[1] == db[key] then self:SetText(label .. ": " .. c[2]) end
        end
    end
    b:SetScript("OnClick", function(self)
        for i, c in ipairs(choices) do
            if c[1] == db[key] then
                db[key] = choices[i % #choices + 1][1]
                break
            end
        end
        self:Refresh()
        ApplyLook()
    end)
    return b
end

local function BuildPanel()
    panel = CreateFrame("Frame", "QuickMapPanel", UIParent, "BackdropTemplate")
    panel:SetSize(230, 440)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.05, 0.045, 0.04, 0.95)
    panel:SetBackdropBorderColor(0.75, 0.55, 0.15, 0.9)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Quick Map")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() panel:Hide() end)

    panel.rows = {
        PanelCycle(panel, -32, "mode", "Key", { { "hold", "Hold to show" }, { "press", "Press to show or hide" } }),
        PanelSlider(panel, -60, "scale", "Size", 0.3, 1.5, 0.05, true),
        PanelSlider(panel, -96, "width", "Width", 0.5, 1.5, 0.05, true),
        PanelSlider(panel, -158, "opacity", "Map Opacity", 0.1, 1, 0.05),
        PanelSlider(panel, -194, "pinOpacity", "Objectives Opacity", 0.1, 1, 0.05),
        PanelCheck(panel, -230, "noFade", "Keep Opacity While Moving"),
        PanelCheck(panel, -252, "hideMinimap", "Hide Minimap"),
        PanelCheck(panel, -274, "follow", "Follow Me"),
        PanelCycle(panel, -304, "buttonMode", "This Button",
            { { "hover", "On hover" }, { "show", "Always" }, { "hide", "Hidden" } }),
        PanelSlider(panel, -330, "buttonOpacity", "Button Opacity", 0.1, 1, 0.05),
    }
    -- Apply for size and width, lit only while there is something to apply
    local apply = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    apply:SetHeight(20)
    apply:SetPoint("TOPLEFT", 10, -130)
    apply:SetPoint("TOPRIGHT", -10, -130)
    apply:SetText("Apply Size & Width")
    apply:SetScript("OnClick", function()
        for key, v in pairs(pending) do db[key] = v end
        wipe(pending)
        panel:UpdateApply()
        ApplyShape()
    end)
    function panel:UpdateApply()
        if next(pending) then apply:Enable() else apply:Disable() end
    end
    local more = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    more:SetHeight(20)
    more:SetPoint("BOTTOMLEFT", 10, 34)
    more:SetPoint("BOTTOMRIGHT", -10, 34)
    more:SetText("Move the Map")
    more:SetScript("OnClick", function() SlashCmdList.QUICKMAP("move") end)
    local all = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    all:SetHeight(20)
    all:SetPoint("BOTTOMLEFT", 10, 10)
    all:SetPoint("BOTTOMRIGHT", -10, 10)
    all:SetText("All Options")
    all:SetScript("OnClick", function() SlashCmdList.QUICKMAP("") end)
    panel:SetScript("OnShow", function(self)
        for _, row in ipairs(self.rows) do row:Refresh() end
        self:UpdateApply()
    end)
    panel:Hide()
end

local function ButtonWanted()
    return compact and db.buttonMode ~= "hide" and (not settling or (panel and panel:IsShown()))
end

local function MapButtonAlpha()
    if db.buttonMode == "show" or (panel and panel:IsShown()) then return db.buttonOpacity end
    local over = Canvas():IsMouseOver() or mapButton:IsMouseOver()
    return over and db.buttonOpacity or 0
end

local function BuildMapButton()
    mapButton = CreateFrame("Button", "QuickMapButton", UIParent)
    mapButton:SetSize(22, 22)
    local bg = mapButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local icon = mapButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(16, 16)
    icon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    mapButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    mapButton:SetScript("OnClick", function()
        if not panel then BuildPanel() end
        if panel:IsShown() then
            panel:Hide()
        else
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", mapButton, "TOPRIGHT", 6, 0)
            panel:Show()
        end
    end)
    mapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Quick Map options")
        GameTooltip:Show()
    end)
    mapButton:SetScript("OnLeave", GameTooltip_Hide)
    -- With "On hover", it shows while the mouse is over the map (checked ten times a second,
    -- only while the map is open).
    local acc = 0
    mapButton:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        local a = MapButtonAlpha()
        if math.abs(self:GetAlpha() - a) > 0.001 then self:SetAlpha(a) end
    end)
end

UpdateMapButton = function()
    if not ButtonWanted() then
        if mapButton then mapButton:Hide() end
        if panel and not compact then panel:Hide() end
        return
    end
    if not mapButton then BuildMapButton() end
    local map = Map()
    mapButton:ClearAllPoints()
    mapButton:SetPoint("TOPRIGHT", Canvas(), "TOPRIGHT", -4, -4)
    mapButton:SetFrameStrata("FULLSCREEN")
    mapButton:SetAlpha(MapButtonAlpha())
    mapButton:Show()
end

--------------------------------------------------------------------------------
-- Options: Options > AddOns > Quick Map
--------------------------------------------------------------------------------

local category

local function BuildOptions()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Quick Map")

    local function Register(key, name)
        local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db,
            type(DEFAULTS[key]), name, DEFAULTS[key])
        setting:SetValueChangedCallback(function()
            ApplyLook()
            if mover and mover:IsShown() then ShowMover() end
        end)
        return setting
    end

    local function Slider(key, name, tooltip, minValue, maxValue, step)
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return string.format("%d%%", value * 100 + 0.5)
        end)
        Settings.CreateSlider(category, Register(key, name), options, tooltip)
    end

    Settings.CreateDropdown(category, Register("mode", "Key"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("hold", "Hold to show")
        container:Add("press", "Press to show or hide")
        return container:GetData()
    end, "Hold: the map shows while you hold the key. Press: one press shows it, the next one hides it.")

    Slider("scale", "Size", "Size of the map.", 0.3, 1.5, 0.05)
    Slider("width", "Width", "Width of the map compared to its usual shape. Lower makes it more square; "
        .. "the map then zooms in to fill it, centred on you.", 0.5, 1.5, 0.05)
    Slider("opacity", "Map Opacity", "How see-through the map itself is.", 0.1, 1, 0.05)
    Slider("pinOpacity", "Objectives Opacity",
        "How see-through the markers on the map are: quests, vendors, flight points, your arrow and other addons' markers.",
        0.1, 1, 0.05)
    Settings.CreateCheckbox(category, Register("noFade", "Keep Opacity While Moving"),
        "With this off, the map fades to half while you move, like the game's own map.")
    Settings.CreateCheckbox(category, Register("hideMinimap", "Hide Minimap"),
        "Hides the minimap while the map is open.")
    Settings.CreateCheckbox(category, Register("follow", "Follow Me"),
        "Keeps the map centred on you while it's open, like the minimap. Zoom in with the mouse wheel "
        .. "to see it move: zoomed all the way out, the whole zone already fits.")
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Also Hide While the Map Is Open"))
    end
    for _, group in ipairs(HIDE_GROUPS) do
        Settings.CreateCheckbox(category, Register(group.key, group.label),
            "Hidden while the map is open, and back when it closes.")
    end
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Options Button"))
    end
    Settings.CreateDropdown(category, Register("buttonMode", "Options Button"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("hover", "On hover")
        container:Add("show", "Always")
        container:Add("hide", "Hidden")
        return container:GetData()
    end, "The arrow button in the corner of the map, which opens a small panel with these options. "
        .. "On hover: it shows while the mouse is over the map.")
    Slider("buttonOpacity", "Options Button Opacity", "How see-through the options button is.", 0.1, 1, 0.05)

    if CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer("Position", "Move",
            ShowMover, "Shows a box the size of the map. Drag it, then right-click it when done.", false))
        layout:AddInitializer(CreateSettingsButtonInitializer("", "Reset Position", function()
            db.x, db.y = 0, 0
            if mover and mover:IsShown() then ShowMover() end
            ApplyLook()
        end, "Puts the map back in the middle of the screen.", false))
    end

    Settings.RegisterAddOnCategory(category)
end

local function OpenOptions()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        Say("Options: Options > AddOns > Quick Map.")
    end
end

-- /qmap debug: what the map looks like from the inside, to find out why something doesn't apply.
function QuickMap_Debug()
    local map, canvas = Map(), Canvas()
    local function f(v) return type(v) == "number" and string.format("%.2f", v) or tostring(v) end
    local function try(obj, method)
        if not obj or not obj[method] then return "n/a" end
        local ok, a, b = pcall(obj[method], obj)
        if not ok then return "error" end
        return b ~= nil and (f(a) .. ", " .. f(b)) or f(a)
    end
    Say("debug. Client " .. tostring((select(4, GetBuildInfo()))) .. ", Quick Map open: " .. tostring(compact))
    Say("Saved: size " .. f(db.scale) .. ", map " .. f(db.opacity) .. ", objectives " .. f(db.pinOpacity))
    Say("Map frame: shown " .. try(map, "IsShown") .. ", scale " .. try(map, "GetScale")
        .. ", effective " .. try(map, "GetEffectiveScale") .. ", size " .. try(map, "GetSize")
        .. ", alpha " .. try(map, "GetAlpha"))
    Say("Map area: parent " .. tostring(canvas and canvas:GetParent() and canvas:GetParent():GetName())
        .. ", effective scale " .. try(canvas, "GetEffectiveScale")
        .. ", ignores parent scale " .. try(canvas, "IsIgnoringParentScale")
        .. ", alpha " .. try(canvas, "GetAlpha")
        .. ", ignores parent alpha " .. try(canvas, "IsIgnoringParentAlpha"))
    local sample
    for template, pool in pairs(map and map.pinPools or {}) do
        if template:find("Questie") and pool.EnumerateActive then
            for pin in pool:EnumerateActive() do sample = pin; break end
        end
    end
    Say("One Questie marker: alpha " .. try(sample, "GetAlpha") .. ", on screen " .. try(sample, "GetEffectiveAlpha")
        .. ", on Quick Map's layer " .. tostring(sample and moved[sample] or false) .. ". Width " .. f(db.width))
    local layers, layerAlpha = 0, nil
    if map and map.detailLayerPool and map.detailLayerPool.EnumerateActive then
        for layer in map.detailLayerPool:EnumerateActive() do
            layers = layers + 1
            layerAlpha = layer:GetAlpha()
        end
    end
    Say("Map layers: " .. layers .. ", alpha of one: " .. f(layerAlpha))
    local pools, pins, kinds = 0, 0, {}
    if map and map.pinPools then
        for template, pool in pairs(map.pinPools) do
            pools = pools + 1
            local n = 0
            if pool.EnumerateActive then for _ in pool:EnumerateActive() do n = n + 1 end end
            pins = pins + n
            if n > 0 then kinds[#kinds + 1] = template .. " " .. n end
        end
    end
    Say("Markers: " .. pins .. " in " .. pools .. " kinds, map area scale " .. f(Canvas() and Canvas():GetScale()) .. ", " .. #kinds .. " kinds shown:")
    for i = 1, math.min(#kinds, 12) do DEFAULT_CHAT_FRAME:AddMessage("   " .. kinds[i]) end
    local list = {}
    local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
    for i = 1, num do
        local name = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)(i)
        if loaded and name and (name:lower():find("map") or name:lower():find("questie") or name:lower():find("coord")) then
            list[#list + 1] = name
        end
    end
    Say("Map-related addons loaded: " .. (#list > 0 and table.concat(list, ", ") or "none"))
end

SLASH_QUICKMAP1 = "/quickmap"
SLASH_QUICKMAP2 = "/qmap"
SlashCmdList.QUICKMAP = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" then
        QuickMap_Debug()
    elseif msg == "move" then
        ShowMover()
    elseif msg == "reset" then
        db.x, db.y = 0, 0
        ApplyLook()
        Say("Map back in the middle of the screen.")
    else
        OpenOptions()
    end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        QuickMapDB = QuickMapDB or {}
        db = QuickMapDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        if db.mode ~= "hold" and db.mode ~= "press" then db.mode = "hold" end
        if db.buttonMode ~= "show" and db.buttonMode ~= "hover" and db.buttonMode ~= "hide" then
            db.buttonMode = "hover"
        end
        BuildOptions()
    elseif event == "PLAYER_LOGIN" then
        HookMap()
        if not GetBindingKey("QUICKMAP_SHOW") then
            Say("Choose a key in Options > Keybindings > AddOns > Quick Map. /qmap opens the options.")
        end
    end
end)
