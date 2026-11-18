-- Overlay Map
-- Shows the game's own map of your zone with a key, without its border, buttons and quest log.
-- It uses the real map, so every marker on it shows too, including other addons' (Questie...).
-- The map is put back exactly as it was when Overlay Map closes it, or when you open it normally.

local ADDON_NAME = ...

BINDING_NAME_OVERLAYMAP_SHOW = "Show the map"

local DEFAULTS = {
    mode = "hold",   -- "hold": shown while the key is held; "press": one press shows, the next hides
    scale = 0.8,     -- size of the map
    width = 1,       -- width of the map compared to its usual shape (lower: more square)
    opacity = 0.85,  -- opacity of the map itself
    pinOpacity = 1,  -- opacity of the markers on it (quests, vendors, your arrow...)
    markerSize = 1,  -- size of the markers (the game's own setting for the map's markers)
    onlyMe = false,  -- hide every marker except your own arrow
    arrowCustom = false, -- your own arrow at its own size and opacity (below)
    arrowSize = 1, arrowOpacity = 1,
    noFade = true,   -- keep that opacity while moving (the game fades the map while you move)
    hideMinimap = true, -- hide the minimap while the map is open
    follow = false,  -- keep the map centred on you while it's open, like the minimap
    edge = 2,        -- soft edges, like an overlay map: 0 off, 1 small ... 4 very large
    shape = "rect",  -- shape of those edges: "rect" (rounded rectangle), "diamond" or "oval"
    style = "standard", -- map style: "standard", or "torn" (torn parchment: torn, burnt paper edges)
    rememberZoom = true, -- open at the zoom Overlay Map's map had when it last closed
    clickThrough = false, -- the mouse goes through the map to the world (hold Shift to use the map)
    overlay = false, -- overlay mode: big, in the middle, see-through, soft edges
    hideBars = false, hideUnits = false, hideChat = false, hideQuests = false, -- other parts of the
    hideBuffs = false, hideMenu = false, hideXP = false,                       -- interface hidden too
    hideNames = false, -- the names above characters' heads, hidden while the map is open
    buttonMode = "hover", -- the options button on the map: "show", "hover" (with the mouse over the map), "hide"
    buttonOpacity = 0.8,     -- with the mouse over the map (or always, with "show")
    buttonNearOpacity = 1,   -- with the mouse on the button or right next to it
    buttonSize = 22,
    buttonCorner = "TOPRIGHT", -- the map's corner it sits in: TOPRIGHT, TOPLEFT, BOTTOMRIGHT, BOTTOMLEFT
    x = 0, y = 0,    -- position of the map's centre, from the centre of the screen
}

local db
local compact = false   -- the map is open in Overlay Map's look
local hidden = {}       -- frame or texture -> { alpha, mouse } it had before Overlay Map hid it
local stopped = {}      -- frames Overlay Map hid completely (they stop working until shown again)
-- Frames as big as the map area that other addons put on it for their icons (OpenMap draws its
-- vendors, mailboxes, flight points and its own arrow on one): kept, and given the markers'
-- opacity like the map's markers. frame -> true
local iconLayers = {}
local before = {}       -- the map's own scale and the map area's opacity before Overlay Map changed them

local function Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffOverlay Map:|r " .. msg)
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
        if child ~= c.Child and not iconLayers[child] and not child.overlayMapOwn then
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
-- inside it is moved to Overlay Map's spot. Without it, the window itself is moved.
local function OpenMapLoaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded("OpenMap") and true or false
end

-- The map area is put at Overlay Map's spot, from the middle of the screen. The game draws the
-- map window as one picture cut to the window's own rectangle, so the map area only shows where
-- it lies inside the window. Without OpenMap, the (invisible) window is stretched over the whole
-- screen while Overlay Map shows it, so the map area can go anywhere. OpenMap keeps the window
-- where and how big it saved it, so there the window is left as it is.
local function CoverScreen()
    local map = Map()
    if OpenMapLoaded() then return end
    if not before.windowSize then
        before.windowSize = { map:GetSize() }
    end
    local l, b, w, h = map:GetRect()
    local ul, ub, uw, uh = UIParent:GetRect()
    local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if not l or math.abs(l * k - ul) > 1 or math.abs(b * k - ub) > 1
        or math.abs(w * k - uw) > 1 or math.abs(h * k - uh) > 1 then
        map:ClearAllPoints()
        map:SetAllPoints(UIParent)
    end
end

-- Overlay mode fills the whole screen: its size, width and place come from the screen (worked
-- out again if the screen or the interface scale changes), not from the options, which are kept
-- for when it's turned off.
local function FullScreen()
    if not db.overlay or not before.cw or before.cw == 0 or before.ch == 0 then return end
    local parent = Canvas():GetParent()
    local pe = parent and parent:GetEffectiveScale() or 1
    local ue = UIParent:GetEffectiveScale()
    local s = UIParent:GetHeight() * ue / (before.ch * pe)
    return s, UIParent:GetWidth() * ue / (before.cw * pe * s)
end
local function WantScale() local s = FullScreen() return s or db.scale end
local function WantWidth() local _, w = FullScreen() return w or db.width end

local function AnchorCanvas()
    local c = Canvas()
    CoverScreen()
    c:ClearAllPoints()
    local k = UIParent:GetEffectiveScale() / c:GetEffectiveScale()
    local x, y = db.x, db.y
    if db.overlay then x, y = 0, 0 end
    c:SetPoint("CENTER", UIParent, "CENTER", x * k, y * k)
end

local function Place()
    AnchorCanvas()
end

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

-- Nothing of these can be clicked by mistake while the map is open:
--   * the ones the game protects (action bars, unit frames) can't be hidden by an addon (in
--     combat at all, and in WoW: Forever not even out of combat), so they're made invisible and
--     covered by an invisible shield that takes the clicks meant for them;
--   * the rest (chat, buffs, quest tracker, menu and bags, experience bar) are hidden.
local hiddenExtra = {}  -- frame -> true: Overlay Map hid it
local faded = {}        -- frame -> alpha it had: made invisible (and shielded)
local shields = {}      -- frame -> its shield
local showLater = {}    -- frame -> true: to show when combat ends

local function CanToggle(f)
    return not (InCombatLockdown() and f:IsProtected())
end

local function Unhide(f)
    if CanToggle(f) then
        pcall(f.Show, f)
    else
        showLater[f] = true
    end
end

local function Shield(f)
    local sh = shields[f]
    if not sh then
        sh = CreateFrame("Frame", nil, UIParent)
        sh:EnableMouse(true)          -- takes the clicks...
        sh:EnableMouseWheel(true)     -- ...and the wheel
        sh:SetScript("OnMouseWheel", function() end)
        shields[f] = sh
    end
    sh:ClearAllPoints()
    sh:SetAllPoints(f)
    sh:SetFrameStrata("DIALOG")
    sh:SetFrameLevel(1000)
    sh:Show()
end

-- Another addon (UI Visibility, for one, fading something in on mouse hover) may set the opacity
-- of an invisible part again. It's put back to nothing the moment that happens, in the same
-- step, so it never shows (checking a few times a second instead made it blink).
local fadeHooked = {}
local refading = false
local function KeepFaded(f)
    if refading or faded[f] == nil or f:GetAlpha() == 0 then return end
    refading = true
    f:SetAlpha(0)
    refading = false
end

local function Fade(f)
    if faded[f] == nil then faded[f] = f:GetAlpha() end
    if not fadeHooked[f] then
        fadeHooked[f] = true
        hooksecurefunc(f, "SetAlpha", KeepFaded)
    end
    if f:GetAlpha() > 0 then f:SetAlpha(0) end
    -- shielded only while it's there to be clicked
    if f:IsVisible() then
        if not (shields[f] and shields[f]:IsShown()) then Shield(f) end
    elseif shields[f] then
        shields[f]:Hide()
    end
end

local function Unfade(f)
    local alpha = faded[f]
    faded[f] = nil -- (first, so the hook above lets this one through)
    f:SetAlpha(alpha)
    if shields[f] then shields[f]:Hide() end
end

local function HideExtras()
    local want = {}
    for _, group in ipairs(HIDE_GROUPS) do
        if db[group.key] then
            for _, f in ipairs(GroupFrames(group)) do want[f] = true end
        end
    end
    -- (groups turned off since: back as they were)
    for f in pairs(hiddenExtra) do
        if not want[f] then
            hiddenExtra[f] = nil
            Unhide(f)
        end
    end
    for f in pairs(faded) do
        if not want[f] then Unfade(f) end
    end
    for f in pairs(want) do
        if faded[f] ~= nil then
            Fade(f)
        elseif f:IsShown() then
            -- Hidden if the game allows it; when it doesn't (it can refuse without saying so),
            -- the frame is still shown afterwards, and it's made invisible and shielded instead.
            if not f:IsProtected() then pcall(f.Hide, f) end
            if f:IsShown() then
                hiddenExtra[f] = nil
                Fade(f)
            else
                hiddenExtra[f] = true
            end
        end
    end
end

local function ShowExtras()
    for f in pairs(hiddenExtra) do Unhide(f) end
    wipe(hiddenExtra)
    for f in pairs(faded) do Unfade(f) end
end

local function ExtrasEnterCombat() end

-- Names above characters' heads (players, NPCs, pets...): the game's own options for them,
-- turned off while the map is open and put back as they were when it closes. The game doesn't
-- let addons change them in combat, so then it waits for combat to end. What they were is kept
-- in the saved settings, so if the game closes with the map open they still come back on the
-- next login.
local NAME_CVARS = {
    "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName", "UnitNameHostleNPC",
    "UnitNameInteractiveNPC", "UnitNameFriendlySpecialNPCName", "UnitNameNPC",
    "UnitNameFriendlyPetName", "UnitNameEnemyPetName", "UnitNameFriendlyGuardianName",
    "UnitNameEnemyGuardianName", "UnitNameFriendlyMinionName", "UnitNameEnemyMinionName",
    "UnitNameFriendlyTotemName", "UnitNameEnemyTotemName", "UnitNameNonCombatCreatureName",
    "UnitNameOwn",
}

local function HideNames()
    if db.namesSaved or InCombatLockdown() then return end
    local saved = {}
    for _, name in ipairs(NAME_CVARS) do
        local value = GetCVar(name)
        if value ~= nil then
            saved[name] = value
            pcall(SetCVar, name, "0")
        end
    end
    db.namesSaved = saved
end

local function ShowNames()
    if not db.namesSaved or InCombatLockdown() then return end
    for name, value in pairs(db.namesSaved) do pcall(SetCVar, name, value) end
    db.namesSaved = nil
end

local function ExtrasLeaveCombat()
    for f in pairs(showLater) do pcall(f.Show, f) end
    wipe(showLater)
    -- (names waiting for combat to end: hidden if the map is open with the option, back if not)
    if compact and db.hideNames then HideNames() else ShowNames() end
end

-- The minimap is hidden while the map shows, and shown again only if Overlay Map hid it. Addons
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
    if not compact or math.abs(WantWidth() - 1) < 0.001 or not c.InstantPanAndZoom then return end
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
    c:SetScale(WantScale())
    local w = before.cw * WantWidth()
    c:SetSize(w, before.ch)
    AnchorCanvas()
    if appliedW ~= w then
        appliedW = w
        Refit()
    end
    SyncLayer()
end

-- Without OpenMap, the game's map can zoom out until the whole zone fits, leaving empty
-- margins on the sides or at the top and bottom when the map area isn't the zone's shape. With
-- soft edges or torn parchment those margins look broken, so while Overlay Map shows the map,
-- the furthest zoom is the one where the map fills the area. (OpenMap shows the world around the
-- zone, so it has no margins.)
local function TrimZoomLevels(c)
    if not compact or OpenMapLoaded() or type(c.zoomLevels) ~= "table" or not c.mapID then return end
    local layers = C_Map.GetMapArtLayers(c.mapID)
    local art = layers and layers[1]
    if not art or not art.layerWidth or art.layerWidth == 0 or art.layerHeight == 0 then return end
    local fill = math.max(c:GetWidth() / art.layerWidth, c:GetHeight() / art.layerHeight)
    local kept = {}
    for _, level in ipairs(c.zoomLevels) do
        if level.scale >= fill * 0.999 then kept[#kept + 1] = level end
    end
    if not kept[1] or kept[1].scale > fill * 1.001 then
        table.insert(kept, 1, { scale = fill, layerIndex = (kept[1] and kept[1].layerIndex) or 1 })
    end
    c.zoomLevels = kept
    local ok, now = pcall(c.GetCanvasScale, c)
    if ok and now and now < fill * 0.999 then
        local okX, x = pcall(c.GetNormalizedHorizontalScroll, c)
        local okY, y = pcall(c.GetNormalizedVerticalScroll, c)
        pcall(c.InstantPanAndZoom, c, fill, okX and x or 0.5, okY and y or 0.5, true)
    end
end

local function RestoreSize()
    if not before.points then return end
    local map, c = Map(), Canvas()
    c:SetScale(before.cscale or 1)
    c:ClearAllPoints()
    c:SetSize(before.cw, before.ch)
    for _, pt in ipairs(before.points) do c:SetPoint(unpack(pt)) end
    if not OpenMapLoaded() and map.OnFrameSizeChanged then
        -- (the game's map works out its zoom levels again, as they were)
        pcall(map.OnFrameSizeChanged, map)
    elseif appliedW and appliedW ~= before.cw and map.OnFrameSizeChanged then
        pcall(map.OnFrameSizeChanged, map)
    end
    appliedW = nil
end

-- Opacity. The map frame is drawn as one picture and then faded as a whole (the game made it
-- that way so its layers don't show through each other), so the map's opacity is set on the
-- map frame. Everything inside it fades with it, markers too, so when the markers need a
-- different opacity they are moved onto a see-through layer of Overlay Map's own, laid exactly
-- over the map area, with the same size and zoom. They stay anchored to the same spots on
-- the map, and go back to the map when it closes.
local MAP_ART = {
    MapExplorationPinTemplate = true, FogOfWarPinTemplate = true, MapHighlightPinTemplate = true,
    WorldMapInvasionOverlayPinTemplate = true, WorldMapThreatOverlayPinTemplate = true,
}
local layer         -- Overlay Map's layer for the markers
local moved = {}    -- marker -> true while it is on that layer
local hookedPins = setmetatable({}, { __mode = "k" })
local reparenting = false

local function Content() return Canvas().Child end

-- Keeps the layer over the map area, at the zoom the map has right now.
-- The same for icon frames that don't zoom with the map (they sit on the map area itself).
local viewLayer
local viewMoved = {} -- frames moved onto viewLayer

-- Markers go one frame strata above the map, so the map (drawn as one picture) can never end
-- up over them.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local function Above(strata)
    for i, name in ipairs(STRATA) do
        if name == strata then return STRATA[math.min(i + 1, #STRATA - 1)] end
    end
    return "DIALOG"
end

-- Only what actually changed is set again: re-anchoring or re-layering a frame makes the game
-- work out again what's under the mouse, which made hovered markers blink.
local function Sync(f, scale)
    local map, c = Map(), Canvas()
    if math.abs(f:GetScale() - scale) > 0.0001 then f:SetScale(scale) end
    if f.syncedTo ~= c then
        f:ClearAllPoints()
        f:SetAllPoints(c)
        f.syncedTo = c
    end
    local strata = Above(map:GetFrameStrata())
    if f:GetFrameStrata() ~= strata then f:SetFrameStrata(strata) end
    local level = map:GetFrameLevel() + 1
    if f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
end

SyncLayer = function()
    if viewLayer then Sync(viewLayer, Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale()) end
    if layer then Sync(layer, Content():GetEffectiveScale() / UIParent:GetEffectiveScale()) end
end

-- A new parent puts a frame, and the frames inside it, at new frame levels. Inside OpenMap's
-- icon layer that left its icons under Questie's icons for the same townsfolk (which OpenMap
-- keeps under its own), so both showed. Every frame keeps the level it had, down the tree.
local function SaveLevels(f, out, depth)
    out[f] = f:GetFrameLevel()
    if depth > 0 then
        for _, child in ipairs({ f:GetChildren() }) do SaveLevels(child, out, depth - 1) end
    end
end

local function LoadLevels(f, levels, depth)
    local want = levels[f]
    local fixed = f.HasFixedFrameLevel and f:HasFixedFrameLevel()
    if want and not fixed and f:GetFrameLevel() ~= want then f:SetFrameLevel(want) end
    if depth > 0 then
        for _, child in ipairs({ f:GetChildren() }) do LoadLevels(child, levels, depth - 1) end
    end
end

local function Reparent(f, parent, depth)
    local levels = {}
    SaveLevels(f, levels, depth)
    f:SetParent(parent)
    LoadLevels(f, levels, depth)
end

local function MovePin(pin)
    if not hookedPins[pin] then
        hookedPins[pin] = true
        -- The map puts its markers back on itself whenever it places them again (zooming,
        -- new markers); while Overlay Map shows it, they go straight back to the layer.
        hooksecurefunc(pin, "SetParent", function(self, parent)
            if reparenting or not compact or not moved[self] or parent == layer then return end
            reparenting = true
            Reparent(self, layer, 2)
            reparenting = false
        end)
    end
    if pin:GetParent() ~= layer then
        -- A new parent resets a frame's level, which would put the marker under the map
        -- (out of reach of the mouse, so no tooltip); it keeps the level the map gave it.
        moved[pin] = true
        reparenting = true
        Reparent(pin, layer, 2)
        reparenting = false
    end
end

local function ReturnPins()
    local content = Content()
    reparenting = true
    for pin in pairs(moved) do Reparent(pin, content, 2) end
    reparenting = false
    wipe(moved)
    if layer then layer:Hide() end
    local c = Canvas()
    for f in pairs(viewMoved) do Reparent(f, c, 5) end
    wipe(viewMoved)
    if viewLayer then viewLayer:Hide() end
end

-- For a moment after opening, the game and other addons are still laying the map out; it stays
-- invisible until that is done, so the normal map doesn't flash on screen.
local settling = false
-- While the map fades out to be laid out again (ApplyShape), nothing else lays it out meanwhile:
-- a second layout in between left it hidden. shapeGen: the latest one (an older one's steps stop).
local reshaping, shapeGen = false, 0
local mapButton, panel -- (the options button on the map and its small panel, further down)
local PlaceMapButton -- (further down)

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
    if reshaping and not settling then return end -- (ApplyShape lays it out once it's hidden)
    if settling then RefitNow() else QueueRefit() end
end

QueueRefit = function()
    if refitTimer then refitTimer:Cancel() end
    refitTimer = C_Timer.NewTimer(0.25, function()
        refitTimer = nil
        if not compact or reshaping then return end
        -- (already hidden for a layout: re-fitted now, and that one shows it again)
        if settling then RefitNow() return end
        local map = Map()
        settling = true
        map:SetAlpha(0)
        if layer then layer:SetAlpha(0) end
        if viewLayer then viewLayer:SetAlpha(0) end
        RefitNow()
        C_Timer.After(0.15, function()
            if not compact or reshaping then return end
            settling = false
            ApplyLook()
        end)
    end)
end

-- A quick fade of the whole map (and its markers) while it's laid out again, instead of it going
-- off and on at once: 1 shown, 0 hidden (FadeTo, further down).
local transition = 1

local function ApplyOpacity()
    local map = Map()
    -- The game fades the map while you move; Overlay Map does it itself (to half) when
    -- "Keep Opacity While Moving" is off, so it works with these opacities.
    local fade = (not db.noFade and IsPlayerMoving and IsPlayerMoving()) and 0.5 or 1
    if settling then fade = 0 end
    fade = fade * transition
    local mapAlpha = db.opacity * fade
    if math.abs(map:GetAlpha() - mapAlpha) > 0.001 then map:SetAlpha(mapAlpha) end

    if math.abs(db.pinOpacity - db.opacity) < 0.001 then
        if next(moved) then ReturnPins() end
        return
    end
    if not layer then
        layer = CreateFrame("Frame", "OverlayMapMarkers", UIParent)
        layer:SetClipsChildren(true) -- markers outside the map area are cut off, like on the map
    end
    if not viewLayer then
        viewLayer = CreateFrame("Frame", "OverlayMapIcons", UIParent)
        viewLayer:SetClipsChildren(true)
    end
    SyncLayer()
    if math.abs(layer:GetAlpha() - db.pinOpacity * fade) > 0.001 then layer:SetAlpha(db.pinOpacity * fade) end
    layer:Show()
    if math.abs(viewLayer:GetAlpha() - db.pinOpacity * fade) > 0.001 then viewLayer:SetAlpha(db.pinOpacity * fade) end
    viewLayer:Show()
    for f in pairs(iconLayers) do
        if f:GetParent() ~= viewLayer then
            viewMoved[f] = true
            Reparent(f, viewLayer, 5)
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

local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self)
    local k = math.min(1, (GetTime() - self.t0) / self.time)
    transition = self.from + (self.to - self.from) * k
    if compact then ApplyOpacity() end
    if k >= 1 then
        self:Hide()
        local done = self.done
        self.done = nil
        if done then done() end
    end
end)

local function FadeTo(target, time, done)
    fader.from, fader.to, fader.t0, fader.time, fader.done = transition, target, GetTime(), time, done
    fader:Show()
end

local function StopFade()
    fader:Hide()
    fader.done = nil
    transition = 1
    reshaping = false
    shapeGen = shapeGen + 1
end


-- Soft edges. The map and its markers fade out towards the edges of the map area, like the
-- overlay maps of other games. Every picture in the map area gets a mask: a picture that is
-- solid in the middle and fades to nothing at its edges, laid over the map area. Each frame
-- holding pictures gets its own mask; new pictures (markers appearing, map tiles loading as
-- you zoom) are picked up as they come.
local SHAPE_FILES = { rect = "Edge", diamond = "Diamond", oval = "Oval" }
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local function EdgeFile()
    -- (the torn parchment's edge is always the same; soft edges come in four widths, and with
    -- them off a diamond or an oval is cut sharp)
    if db.style == "torn" then return MEDIA .. "Torn" end
    return MEDIA .. (SHAPE_FILES[db.shape] or "Edge") .. db.edge
end

-- The old map look: torn edges, with a burnt brown rim drawn along them, over the map's picture
-- and under the markers. It fades with the map.
local rim
local function ShowRim()
    local c = Canvas()
    if not rim then
        rim = CreateFrame("Frame", nil, c)
        rim.overlayMapOwn = true
        rim.tex = rim:CreateTexture(nil, "OVERLAY")
        rim.tex:SetAllPoints()
        rim.tex:SetTexture(MEDIA .. "TornRim")
    end
    rim:ClearAllPoints()
    rim:SetAllPoints(c)
    local content = c.Child or c
    local level = content:GetFrameLevel() + 100
    if rim:GetFrameLevel() ~= level then rim:SetFrameLevel(level) end
    rim:Show()
end

local function HideRim()
    if rim then rim:Hide() end
end
local masks = {}                                         -- frame -> its mask
local maskedTex = setmetatable({}, { __mode = "k" })     -- picture -> the mask on it

local function MaskFor(frame)
    local m = masks[frame]
    if not m then
        local ok, made = pcall(frame.CreateMaskTexture, frame)
        if not ok or not made then return end
        m = made
        masks[frame] = m
    end
    local file = EdgeFile()
    if m.file ~= file then
        m:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m.file = file
    end
    if m.syncedTo ~= Canvas() then
        m:ClearAllPoints()
        m:SetAllPoints(Canvas())
        m.syncedTo = Canvas()
    end
    if not m:IsShown() then m:Show() end
    return m
end

local function MaskTree(frame, depth)
    if depth > 5 or frame:IsForbidden() then return end
    local m
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            m = m or MaskFor(frame)
            if not m then break end
            local old = maskedTex[r]
            if old ~= m then
                if old then pcall(r.RemoveMaskTexture, r, old) end
                if pcall(r.AddMaskTexture, r, m) then maskedTex[r] = m end
            end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do MaskTree(child, depth + 1) end
end

local function Unmask()
    HideRim()
    for tex, m in pairs(maskedTex) do pcall(tex.RemoveMaskTexture, tex, m) end
    wipe(maskedTex)
    for _, m in pairs(masks) do m:Hide() end
end

local function ApplyEdges()
    local torn = db.style == "torn"
    -- (soft edges off with a rectangle: nothing to do; with a diamond or an oval: a sharp cut)
    local plain = (db.edge or 0) < 1 and (db.shape or "rect") == "rect"
    if not compact or (not torn and plain) then
        if next(maskedTex) then Unmask() end
        HideRim()
        return
    end
    if torn then ShowRim() else HideRim() end
    local content = Canvas().Child
    if content then MaskTree(content, 0) end
    if layer and layer:IsShown() then MaskTree(layer, 0) end
    if viewLayer and viewLayer:IsShown() then MaskTree(viewLayer, 0) end
end

local edgesPending = false
local function QueueEdges()
    if edgesPending or not compact or (db.edge or 0) < 1 then return end
    edgesPending = true
    C_Timer.After(0, function()
        edgesPending = false
        ApplyEdges()
    end)
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

-- Whether the mouse is on a marker (the game's, Questie's or OpenMap's), not just on the map.
local function OverMarker()
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local f = foci and foci[1]
    local c = Canvas()
    if not f or f == c or f == c.Child or iconLayers[f] or f == layer or f == viewLayer then return false end
    local up, n = f:GetParent(), 0
    while up and n < 8 do
        if up == c or up == layer or up == viewLayer then return true end
        up, n = up:GetParent(), n + 1
    end
    return false
end

local function Follow(force)
    -- With the mouse over the map, it holds still so you can look at the markers (it catches up
    -- with you when the mouse leaves). In Overlay Mode the map fills the screen, so the mouse is
    -- always over it: there it holds still only with the mouse on a marker, or with Shift held
    -- (using the map).
    local hold
    if db.overlay then
        hold = IsShiftKeyDown() or OverMarker()
    else
        hold = Canvas():IsMouseOver()
    end
    if hold then
        lastX, lastY = nil, nil
        return
    end
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

local edgeAcc = 0
local ApplyClickThrough, ApplyOnlyMe, ApplyMarkerSize, ApplyArrow -- (further down)
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
    if not reshaping and math.abs(Canvas():GetScale() - WantScale()) > 0.001 then ApplySize() end -- (also a new screen size)
    -- (a fade left half-way, which nothing is finishing: the map shown again)
    if not reshaping and not settling and transition < 1 and not fader:IsShown() then FadeTo(1, 0.2) end
    CoverScreen() -- (in case the game's window layout moved it back)
    ApplyOpacity()
    HideExtras()
    if db.hideMinimap then HideMinimap() end
    if db.clickThrough then ApplyClickThrough() end -- (in case something gave the mouse back)
    ApplyOnlyMe() -- (new markers)
    ApplyMarkerSize() -- (new markers)
    ApplyArrow()
    if mapButton and mapButton:IsShown() then PlaceMapButton() end -- (the map grew past the screen)
    edgeAcc = edgeAcc + 1
    if edgeAcc >= 5 then -- (once a second, for anything the events missed)
        edgeAcc = 0
        ApplyEdges()
    end
end)

-- Click-through: clicks go through the map to the world behind it (right-click turning, left
-- clicks), while the map still notices the mouse moving over it, so its markers show their names
-- when hovered. Markers can't be clicked either (a click on one would get stuck, the map not
-- getting the release, or send the map somewhere else): they keep showing their names, and a
-- click on one goes to the world too. The map and other addons set their markers' mouse up again
-- now and then; that is caught the moment it happens (changing it later, while hovered, made
-- their tooltips flicker). Holding Shift makes the whole map usable again (dragging, clicking,
-- zooming with the wheel) while it's held.
-- (On a client without separate click and hover settings, the map area ignores the mouse
-- entirely instead, and markers keep it.)
local passSaved = {} -- frame -> { click, motion, wheel } it had
local SPLIT = UIParent.SetMouseClickEnabled ~= nil

local function PassFrames()
    local c = Canvas()
    local list = { c }
    if c.Child then list[#list + 1] = c.Child end
    for f in pairs(iconLayers) do list[#list + 1] = f end
    return list
end

local function Save(f)
    if passSaved[f] then return end
    if SPLIT then
        passSaved[f] = { f:IsMouseClickEnabled(), f:IsMouseMotionEnabled(),
            f.IsMouseWheelEnabled and f:IsMouseWheelEnabled() }
    else
        passSaved[f] = { f:IsMouseEnabled(), nil, f.IsMouseWheelEnabled and f:IsMouseWheelEnabled() }
    end
end

-- Markers that take clicks: the map's own and other addons' that use them (Questie's, through
-- HereBeDragons), the frames inside them, and the icons other addons draw on their own layers
-- (OpenMap's), a few levels down.
local function ClickableMarkers()
    local list = {}
    local function Walk(f, depth)
        if f:IsForbidden() then return end
        if f:IsMouseClickEnabled() then list[#list + 1] = f end
        if depth > 0 then
            for _, child in ipairs({ f:GetChildren() }) do Walk(child, depth - 1) end
        end
    end
    for _, pool in pairs(Map().pinPools or {}) do
        if pool.EnumerateActive then
            for pin in pool:EnumerateActive() do Walk(pin, 2) end
        end
    end
    for f in pairs(iconLayers) do
        for _, child in ipairs({ f:GetChildren() }) do Walk(child, 2) end
    end
    return list
end

local markersOff = false   -- markers are kept from taking clicks
local keeping = false
local hookedMouse = setmetatable({}, { __mode = "k" })

local function KeepNoClick(f)
    if markersOff and not keeping and passSaved[f] and f:IsMouseClickEnabled() then
        keeping = true
        pcall(f.SetMouseClickEnabled, f, false)
        keeping = false
    end
end

local function NoClick(f)
    Save(f)
    if not hookedMouse[f] then
        hookedMouse[f] = true
        hooksecurefunc(f, "EnableMouse", KeepNoClick)
        hooksecurefunc(f, "SetMouseClickEnabled", KeepNoClick)
    end
    pcall(f.SetMouseClickEnabled, f, false)
end

local function NoWheel(f)
    if f.IsMouseWheelEnabled and f:IsMouseWheelEnabled() then pcall(f.EnableMouseWheel, f, false) end
end

ApplyClickThrough = function(force)
    local on = compact and db.clickThrough and not IsShiftKeyDown()
    if not on then markersOff = false end
    -- force: start over (everything back as it was, then click-through again), the same as
    -- turning the option off and on; used once the map has finished opening.
    if force and on and next(passSaved) then
        compact = false
        ApplyClickThrough()
        compact = true
    end
    if on then
        for _, f in ipairs(PassFrames()) do
            Save(f)
            if SPLIT then
                -- hover yes, clicks no
                if f:IsMouseClickEnabled() then pcall(f.SetMouseClickEnabled, f, false) end
                -- (an addon's icon layer that didn't notice the mouse is left so: covering the whole
                -- map, it would take the hover from the markers under it, like Questie's)
                if not f:IsMouseMotionEnabled() and not (iconLayers[f] and not passSaved[f][2]) then
                    pcall(f.SetMouseMotionEnabled, f, true)
                end
            elseif f:IsMouseEnabled() then
                pcall(f.EnableMouse, f, false)
            end
            NoWheel(f)
        end
        if SPLIT then
            markersOff = true
            for _, f in ipairs(ClickableMarkers()) do NoClick(f) end
        end
    elseif next(passSaved) then
        markersOff = false
        for f, was in pairs(passSaved) do
            if SPLIT then
                pcall(f.SetMouseClickEnabled, f, was[1] and true or false)
                pcall(f.SetMouseMotionEnabled, f, was[2] and true or false)
            else
                pcall(f.EnableMouse, f, was[1] and true or false)
            end
            if was[3] ~= nil then pcall(f.EnableMouseWheel, f, was[3] and true or false) end
        end
        wipe(passSaved)
    end
end

-- Only my arrow: every marker on the map is hidden except your own arrow (the game's, or
-- OpenMap's when it draws its own). The map's picture (explored areas, highlights) stays. Hidden
-- markers are made invisible and stop noticing the mouse (no tooltips from invisible markers);
-- the map and other addons set those up again now and then, which is undone the moment it
-- happens, so nothing blinks.
local onlyHidden = {}  -- frame -> { alpha, motion } it had
local onlyKeeping = false

local function KeepOnlyHidden(f)
    local was = onlyHidden[f]
    if onlyKeeping or not was then return end
    onlyKeeping = true
    if f:GetAlpha() > 0 then f:SetAlpha(0) end
    if f.IsMouseMotionEnabled and f:IsMouseMotionEnabled() then pcall(f.SetMouseMotionEnabled, f, false) end
    onlyKeeping = false
end

local onlyHooked = setmetatable({}, { __mode = "k" })
local function HideMarker(f)
    if onlyHidden[f] or f:IsForbidden() then return end
    onlyHidden[f] = { alpha = f:GetAlpha(), motion = f.IsMouseMotionEnabled and f:IsMouseMotionEnabled() }
    if not onlyHooked[f] then
        onlyHooked[f] = true
        for _, method in ipairs({ "SetAlpha", "EnableMouse", "SetMouseMotionEnabled" }) do
            if f[method] then hooksecurefunc(f, method, KeepOnlyHidden) end
        end
    end
    KeepOnlyHidden(f)
end

-- A marker and the frames inside it (Questie's icon sits inside its marker).
local function HideMarkerTree(f, depth)
    HideMarker(f)
    if depth > 0 then
        for _, child in ipairs({ f:GetChildren() }) do HideMarkerTree(child, depth - 1) end
    end
end

-- OpenMap's own arrow: a frame holding just the minimap's arrow picture.
local function IsArrow(f)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local path = r.GetTextureFilePath and r:GetTextureFilePath() or r:GetTexture()
            if type(path) == "string" and path:lower():find("minimaparrow") then return true end
        end
    end
    return false
end

-- (keep: the ones to leave hidden, if any)
local function ShowMarkers(keep)
    if not next(onlyHidden) then return end
    onlyKeeping = true
    for f, was in pairs(onlyHidden) do
        if keep and keep(f) then
            -- (stays hidden)
        else
        onlyHidden[f] = nil
        f:SetAlpha(was.alpha or 1)
        if was.motion ~= nil and f.SetMouseMotionEnabled then pcall(f.SetMouseMotionEnabled, f, was.motion) end
        end
    end
    onlyKeeping = false
end

-- OpenMap draws its own icons for townsfolk (vendors, trainers, mailboxes) from Questie's
-- database, and Questie draws its own for the same NPCs. On its map OpenMap keeps Questie's
-- under its own, so only one shows; over the world, with the markers on their own layers, both
-- showed. While Overlay Map shows OpenMap's map, Questie's townsfolk icons are hidden (Questie's
-- quest icons stay).
local function IsTownsfolk(f) return f.isManualIcon == true end

local function HideTownsfolkTwins()
    local api = OpenMapLoaded() and _G.OpenMapAPI
    if not (api and api.IsStitched and api.IsStitched()) then return false end
    for template, pool in pairs(Map().pinPools or {}) do
        if type(template) == "string" and template:find("HereBeDragons", 1, true) and pool.EnumerateActive then
            for pin in pool:EnumerateActive() do
                local icon = pin.icon
                if icon and IsTownsfolk(icon) then HideMarker(icon) end
            end
        end
    end
    return true
end

ApplyOnlyMe = function()
    if not compact then
        ShowMarkers()
        return
    end
    if not db.onlyMe then
        if HideTownsfolkTwins() then ShowMarkers(IsTownsfolk) else ShowMarkers() end
        return
    end
    for template, pool in pairs(Map().pinPools or {}) do
        if not MAP_ART[template] and template ~= "GroupMembersPinTemplate" and pool.EnumerateActive then
            for pin in pool:EnumerateActive() do HideMarkerTree(pin, 2) end
        end
    end
    for f in pairs(iconLayers) do
        for _, child in ipairs({ f:GetChildren() }) do
            if not IsArrow(child) then HideMarkerTree(child, 2) end
        end
    end
end

-- Marker size. Each of the game's markers works out its own size (and then its place, which
-- depends on it) whenever the map zooms; Overlay Map's size is added on top each time it does,
-- so markers stay exactly where they belong. Markers placed by HereBeDragons (Questie's) are
-- placed again by OpenMap its own way, so for those only the icon inside them is resized (it sits
-- at the marker's centre). OpenMap's own icons (vendors, mailboxes...) sit at their spot's
-- centre too, so they're simply resized, on top of OpenMap's own Icon size. (Resizing only some
-- of them showed the others underneath: OpenMap and Questie often mark the same NPC.) All of it
-- only while Overlay Map shows the map.
local sizeHooked = setmetatable({}, { __mode = "k" })
local sizedPins = setmetatable({}, { __mode = "k" })  -- pins resized (to put back on close)
local iconBase = setmetatable({}, { __mode = "k" })   -- HereBeDragons icon -> its own scale
local omBase = setmetatable({}, { __mode = "k" })     -- OpenMap icon -> { its own scale, the one set }

-- Questie's icons are placed by OpenMap at a distance from a fixed point, which a new scale
-- would stretch (the icon drifted away from its spot, beside OpenMap's icon for the same NPC):
-- their size is changed instead, which keeps their centre where it is.
local function SizeQuestieIcon(icon, k)
    local rec = iconBase[icon]
    local w, h = icon:GetSize()
    if not w or w == 0 then return end
    if not rec then
        if k == 1 then return end
        rec = { w = w, h = h }
        iconBase[icon] = rec
    elseif rec.sw and (math.abs(w - rec.sw) > 0.01 or math.abs(h - rec.sh) > 0.01) then
        rec.w, rec.h = w, h -- (Questie sized it again: that's its own size now)
    end
    local ww, wh = rec.w * k, rec.h * k
    if math.abs(w - ww) > 0.01 or math.abs(h - wh) > 0.01 then icon:SetSize(ww, wh) end
    rec.sw, rec.sh = ww, wh
    if k == 1 then iconBase[icon] = nil end
end

local function SizeOpenMapIcon(pin, k)
    local rec = omBase[pin]
    local cur = pin:GetScale()
    if not rec then
        if k == 1 then return end
        rec = { base = cur }
        omBase[pin] = rec
    elseif rec.set and math.abs(cur - rec.set) > 0.0001 then
        rec.base = cur -- (OpenMap set its size again: that's its own size now)
    end
    local want = rec.base * k
    if math.abs(cur - want) > 0.0001 then pin:SetScale(want) end
    rec.set = want
    if k == 1 then omBase[pin] = nil end
end

local function SizeAfterScale(pin)
    if not compact or (db.markerSize or 1) == 1 then return end
    -- (a marker that doesn't work out a size of its own was left as it was: nothing to add to)
    if not (pin.startScale and pin.endScale) and pin.IsIgnoringGlobalPinScale and pin:IsIgnoringGlobalPinScale() then
        return
    end
    pin:SetScale(pin:GetScale() * db.markerSize)
    if pin.ApplyCurrentPosition then pin:ApplyCurrentPosition() end
end

ApplyMarkerSize = function()
    local k = compact and db.markerSize or 1
    local map = Map()
    for template, pool in pairs(map.pinPools or {}) do
        if pool.EnumerateActive and not MAP_ART[template] then
            local hbd = type(template) == "string" and template:find("HereBeDragons", 1, true)
            for pin in pool:EnumerateActive() do
                if hbd then
                    local icon = pin.icon
                    if icon and icon.SetSize then SizeQuestieIcon(icon, k) end
                elseif pin.ApplyCurrentScale then
                    if not sizeHooked[pin] then
                        sizeHooked[pin] = true
                        hooksecurefunc(pin, "ApplyCurrentScale", SizeAfterScale)
                    end
                    -- (worked out again: by the game, then this size on top)
                    if math.abs((sizedPins[pin] or 1) - k) > 0.0001 then
                        sizedPins[pin] = k ~= 1 and k or nil
                        pin:ApplyCurrentScale()
                    end
                end
            end
        end
    end
    -- OpenMap's icons: its layer, its sets, their cells, the icons (each with its picture and the
    -- spot it's anchored to)
    local function Walk(f, depth)
        for _, child in ipairs({ f:GetChildren() }) do
            if child.Icon and child.anchor then
                SizeOpenMapIcon(child, k)
            elseif depth > 0 then
                Walk(child, depth - 1)
            end
        end
    end
    for f in pairs(iconLayers) do Walk(f, 3) end
    if k == 1 then
        for pin in pairs(omBase) do SizeOpenMapIcon(pin, 1) end
        for icon in pairs(iconBase) do SizeQuestieIcon(icon, 1) end
    end
end

-- My arrow: its own size and opacity, when chosen (My Arrow's Own Size). With OpenMap's map it's
-- OpenMap's own arrow (a picture on its icon layer); otherwise the game's, drawn by the group
-- members' marker, whose size for the player is set on it (its opacity is the whole marker's, so
-- the party's dots take it too). Put back as it was on close.
local arrowBase = setmetatable({}, { __mode = "k" })    -- arrow picture or marker -> its own size
local arrowHooked = setmetatable({}, { __mode = "k" })
local arrowApplied = setmetatable({}, { __mode = "k" })   -- marker -> the size factor last set on it
local arrowSetting = false

local function ArrowWant()
    if compact and db.arrowCustom then return db.arrowSize or 1, db.arrowOpacity or 1 end
    return 1, 1
end

local function OpenMapArrow()
    for f in pairs(iconLayers) do
        for _, child in ipairs({ f:GetChildren() }) do
            for _, r in ipairs({ child:GetRegions() }) do
                if r:GetObjectType() == "Texture" then
                    local path = r.GetTextureFilePath and r:GetTextureFilePath() or r:GetTexture()
                    if type(path) == "string" and path:lower():find("minimaparrow") then return r end
                end
            end
        end
    end
end

ApplyArrow = function()
    local k, a = ArrowWant()
    local tex = OpenMapArrow()
    if tex then
        if not arrowBase[tex] then
            if k == 1 and a == 1 then tex = nil else arrowBase[tex] = tex:GetWidth() end
        end
        if tex then
            local want = arrowBase[tex] * k
            if math.abs(tex:GetWidth() - want) > 0.01 then tex:SetSize(want, want) end
            if math.abs(tex:GetAlpha() - a) > 0.001 then tex:SetAlpha(a) end
            if k == 1 and a == 1 then arrowBase[tex] = nil end
        end
    end
    local pool = Map().pinPools and Map().pinPools.GroupMembersPinTemplate
    if not (pool and pool.EnumerateActive) then return end
    for pin in pool:EnumerateActive() do
        if pin.SetPinSize then
            if not arrowHooked[pin] then
                arrowHooked[pin] = true
                -- (the game sets the player's size again now and then: noted as its own, ours on top)
                hooksecurefunc(pin, "SetPinSize", function(self, unit, size)
                    if arrowSetting or unit ~= "player" or type(size) ~= "number" then return end
                    arrowBase[self] = size
                    local kk = ArrowWant()
                    if kk ~= 1 then
                        arrowSetting = true
                        pcall(self.SetPinSize, self, "player", size * kk)
                        arrowSetting = false
                    end
                end)
                if pin.UpdateAppearanceData then pcall(pin.UpdateAppearanceData, pin) end
            end
            local base = arrowBase[pin]
            if base and arrowApplied[pin] ~= k then
                arrowApplied[pin] = k
                arrowSetting = true
                pcall(pin.SetPinSize, pin, "player", base * k)
                arrowSetting = false
            end
        end
        if math.abs(pin:GetAlpha() - a) > 0.001 then pin:SetAlpha(a) end
    end
end

local UpdateMapButton -- (the options button on the map, further down)

ApplyLook = function()
    if not compact then return end
    local map = Map()
    ApplyMarkerSize()
    ApplySize()
    ApplyOpacity()
    if PlayerMovementFrameFader and PlayerMovementFrameFader.RemoveFrame then
        PlayerMovementFrameFader.RemoveFrame(map)
    end
    Place()
    if db.hideMinimap then HideMinimap() else ShowMinimap() end
    HideExtras()
    if db.hideNames then HideNames() else ShowNames() end
    ApplyEdges()
    ApplyClickThrough()
    ApplyOnlyMe()
    ApplyArrow()
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

-- Takes the map out of Overlay Map's look and gives it back to the game.
--------------------------------------------------------------------------------
-- Remembered zoom: Overlay Map's map opens at the zoom it had when it last closed, apart from the
-- normal map's. With OpenMap, through its own API (its view of the whole world: centre and
-- zoom); its own "reopen" option still decides where the view is centred. Without it, the
-- game's map, for the same zone only.
--------------------------------------------------------------------------------

local function SaveZoom()
    if not db.rememberZoom then return end
    local api = OpenMapLoaded() and _G.OpenMapAPI
    if api and api.IsStitched and api.IsStitched() and api.GetView then
        local ok, _, _, zoom = pcall(api.GetView)
        if ok and type(zoom) == "number" then db.zoom = { openmap = zoom } end
        return
    end
    local c = Canvas()
    if not c.GetCanvasScale then return end
    local ok, scale = pcall(c.GetCanvasScale, c)
    local okX, x = pcall(c.GetNormalizedHorizontalScroll, c)
    local okY, y = pcall(c.GetNormalizedVerticalScroll, c)
    if ok and okX and okY and scale and x and y then
        db.zoom = { mapID = Map():GetMapID(), scale = scale, x = x, y = y }
    end
end

local function RestoreZoom()
    local z = db.rememberZoom and db.zoom
    if not z then return end
    local api = OpenMapLoaded() and _G.OpenMapAPI
    if api and api.IsStitched and api.IsStitched() then
        if not z.openmap then return end
        local ok, u, v = pcall(api.GetView)
        if not ok or not u then return end
        -- At once if OpenMap allows it, otherwise a short glide.
        local om = _G.OpenMap and _G.OpenMap.GetModule and select(2, pcall(_G.OpenMap.GetModule, _G.OpenMap, "worldmap"))
        if type(om) == "table" and om.ShowNow and pcall(om.ShowNow, u, v, z.openmap) then return end
        if api.ShowWorld then pcall(api.ShowWorld, u, v, z.openmap) end
        return
    end
    local c = Canvas()
    if z.scale and z.mapID == Map():GetMapID() and c.InstantPanAndZoom then
        pcall(c.InstantPanAndZoom, c, z.scale, z.x, z.y, true)
    end
end

local function Restore()
    if not compact then return end
    StopFade()
    SaveZoom()
    compact = false
    local map = Map()
    RevealAll()
    ShowMinimap()
    ShowExtras()
    ShowNames()
    Unmask()
    ApplyClickThrough() -- (compact is off: everything takes the mouse again)
    ShowMarkers()
    RestoreSize()
    RestoreOpacity()
    ApplyMarkerSize() -- (compact is off: markers back to their size)
    ApplyArrow()      -- (... and your arrow)
    wipe(iconLayers)
    settling = false
    map:SetAlpha(before.alpha or 1)
    if before.mouse then map:EnableMouse(true) end
    UpdateMapButton()
    local size = before.windowSize
    wipe(before)
    if size then
        -- (the window back to its size; the game puts it back in its place)
        map:ClearAllPoints()
        map:SetSize(size[1], size[2])
    end
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
        RestoreZoom()
        settling = false
        ApplyLook()
        -- The map and other addons finish setting up their frames' mouse while it opens; the
        -- click-through is laid again from scratch on top of that.
        C_Timer.After(0.1, function()
            if compact then ApplyClickThrough(true) end
        end)
    end)
end

local function Close()
    if not compact then return end
    local map = Map()
    if HideUIPanel then HideUIPanel(map) else map:Hide() end
    Restore() -- in case hiding did not reach the OnHide hook
end

function OverlayMap_OnKey(keystate)
    if not db or not Map() then return end
    if db.mode == "hold" then
        if keystate == "down" then Open() else Close() end
    elseif keystate == "down" then
        if compact then Close() else Open() end
    end
end

local function HookMap()
    local map = Map()
    if not map or map.OverlayMapHooked then return end
    map.OverlayMapHooked = true
    -- Closed by Esc, by another window, or anything else: put everything back.
    map:HookScript("OnHide", Restore)
    -- Opened the normal way (M, L, a quest link) while Overlay Map shows it: the game takes over.
    for _, method in ipairs({ "HandleUserActionToggleSelf", "HandleUserActionToggleQuestLog",
                              "HandleUserActionOpenSelf", "HandleUserActionOpenQuestLog" }) do
        if map[method] then hooksecurefunc(map, method, Restore) end
    end
    -- Zooming the map: the markers' layer zooms with it right away.
    if map.OnCanvasScaleChanged then
        if map.ScrollContainer and map.ScrollContainer.CreateZoomLevels then
            hooksecurefunc(map.ScrollContainer, "CreateZoomLevels", TrimZoomLevels)
        end
        hooksecurefunc(map, "OnCanvasScaleChanged", function()
            if compact and layer and layer:IsShown() then SyncLayer() end
            if compact then QueueEdges() end -- (map tiles load as you zoom)
        end)
    end
    -- New markers: move them onto the layer on the next frame instead of waiting.
    if map.AcquirePin then
        local pending = false
        hooksecurefunc(map, "AcquirePin", function()
            if compact then QueueEdges() end
            if not compact or pending or not (layer and layer:IsShown()) then return end
            pending = true
            C_Timer.After(0, function()
                pending = false
                if compact then ApplyOpacity() end
            end)
        end)
    end
    -- Another zone shown while Overlay Map shows the map: fill the shape again.
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
    if db.overlay then
        Say("Overlay Mode fills the whole screen: turn it off to move the map.")
        return
    end
    if not mover then
        mover = CreateFrame("Frame", "OverlayMapMover", UIParent, "BackdropTemplate")
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
        text:SetText("Overlay Map\nDrag to move. Right-click when done.")
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
    -- The map area's size, as measured the last time Overlay Map opened it.
    mover:SetSize((db.areaW or 702) * db.scale * db.width, (db.areaH or 467) * db.scale)
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    mover:Show()
end

--------------------------------------------------------------------------------
-- The options button on the map, and the small panel it opens
--------------------------------------------------------------------------------

local EDGE_CHOICES = { { 0, "Off" }, { 1, "Small" }, { 2, "Medium" }, { 3, "Large" }, { 4, "Very large" } }
local SHAPE_CHOICES = { { "rect", "Rectangle" }, { "diamond", "Diamond" }, { "oval", "Oval" } }
local STYLE_CHOICES = { { "standard", "Standard" }, { "torn", "Torn Parchment" } }
local function StandardStyle() return db.style ~= "torn" end

local function Round(v, step) return math.floor(v / step + 0.5) * step end

-- Size and width from the panel wait for its Apply button (changing them is a whole new layout
-- of the map); key -> value chosen, not applied yet
local pending = {}

-- Applies a new size or width with the map hidden for a moment, so the new layout isn't seen
-- being worked out.
-- The map fades out, is laid out again while hidden (OpenMap and the game take a few frames to
-- settle), and fades back in.
local function ApplyShape()
    if not compact then return end
    shapeGen = shapeGen + 1
    local gen = shapeGen
    reshaping = true
    if refitTimer then refitTimer:Cancel() refitTimer = nil end
    FadeTo(0, 0.12, function()
        if gen ~= shapeGen then return end
        if not compact then StopFade() return end
        settling = true
        ApplyLook()      -- (the map re-fits at once while it's hidden)
        C_Timer.After(0.15, function()
            if gen ~= shapeGen then return end
            if not compact then StopFade() return end
            settling = false
            reshaping = false
            ApplyLook()
            FadeTo(1, 0.2)
        end)
    end)
end

-- Overlay mode: one switch that makes the map fill the whole screen (FullScreen: size, width and
-- place come from the screen while it's on). It keeps its own look, apart from the normal map's:
-- the settings below are swapped when it's turned on or off, so a change made in one mode stays in
-- that mode. The other mode's values wait in the saved settings (beforeOverlay: the normal map's,
-- while Overlay Mode is on; overlaySet: Overlay Mode's, while it's off).
local OVERLAY_KEYS = { "opacity", "pinOpacity", "markerSize", "arrowCustom", "arrowSize", "arrowOpacity", "style",
    "edge", "shape", "clickThrough", "noFade" }
-- Overlay Mode the first time it's turned on: see-through, solid markers, large soft edges,
-- click-through (the rest as the normal map has them)
local OVERLAY_START = { opacity = 0.3, pinOpacity = 1, edge = 3, clickThrough = true, noFade = true }

local RefreshPanel -- (further down)

-- The options window shows the swapped values (if it's open, its controls are told to read them again).
local function NotifyOptions()
    if not (Settings and Settings.NotifyUpdate) then return end
    for _, k in ipairs(OVERLAY_KEYS) do pcall(Settings.NotifyUpdate, ADDON_NAME .. "_" .. k) end
end

local function SyncOverlay()
    if db.overlay and not db.overlayActive then
        db.beforeOverlay = {}
        for _, k in ipairs(OVERLAY_KEYS) do db.beforeOverlay[k] = db[k] end
        local saved = db.overlaySet or {}
        for _, k in ipairs(OVERLAY_KEYS) do
            if saved[k] ~= nil then
                db[k] = saved[k]
            elseif OVERLAY_START[k] ~= nil then
                db[k] = OVERLAY_START[k]
            end
        end
        db.overlayActive = true
    elseif not db.overlay and db.overlayActive then
        db.overlaySet = {}
        for _, k in ipairs(OVERLAY_KEYS) do db.overlaySet[k] = db[k] end
        -- (from an older version, the normal map's size, width and place may be here too)
        for k, v in pairs(db.beforeOverlay or {}) do db[k] = v end
        db.beforeOverlay = nil
        db.overlayActive = false
    else
        return
    end
    NotifyOptions()
    if RefreshPanel then RefreshPanel() end
    if compact then ApplyShape() end
end

-- The small panel. Its rows are grouped in sections whose titles fold and unfold them (remembered),
-- and rows that don't apply right now aren't shown at all: Size and Width in Overlay Mode, your
-- arrow's size and opacity until you choose to set them. The panel grows and shrinks to fit.
-- A plain slider: label on the left, value on the right, the bar under them.
local function PanelSlider(parent, key, label, minValue, maxValue, step, deferred)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 12, 0)
    text:SetText(label)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("TOPRIGHT", -12, 0)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 12, -16)
    s:SetPoint("TOPRIGHT", -12, -16)
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
            if panel and panel.UpdateApply then panel:UpdateApply() end
            return
        end
        if math.abs((db[key] or 0) - v) < 0.0001 then return end
        db[key] = v
        ApplyLook()
    end)
    function parent:Refresh()
        pending[key] = nil
        s.silent = true
        s:SetValue(db[key])
        s.silent = false
        value:SetText(string.format("%d%%", db[key] * 100 + 0.5))
    end
end

local function PanelCheck(parent, key, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", 8, 0)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        SyncOverlay()
        ApplyLook()
        if RefreshPanel then RefreshPanel() end -- (rows may show or go with it)
    end)
    function parent:Refresh() cb:SetChecked(db[key] and true or false) end
end

-- A button that steps through a few choices: "Label: Choice"
local function PanelCycle(parent, key, label, choices, enabledIf)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", 10, 0)
    b:SetPoint("TOPRIGHT", -10, 0)
    function parent:Refresh()
        for _, c in ipairs(choices) do
            if c[1] == db[key] then b:SetText(label .. ": " .. c[2]) end
        end
        if enabledIf then b:SetEnabled(enabledIf()) end
    end
    b:SetScript("OnClick", function()
        for i, c in ipairs(choices) do
            if c[1] == db[key] then
                db[key] = choices[i % #choices + 1][1]
                break
            end
        end
        SyncOverlay()
        ApplyLook()
        if RefreshPanel then RefreshPanel() end -- (other rows may depend on this one)
    end)
end

local function NotOverlay() return not db.overlay end
local function ArrowOwn() return db.arrowCustom and true or false end

-- Next to the options button, on the outside of the map; inside it (under the button) in Overlay
-- Mode, which fills the screen, or when there's no room outside.
local function PlacePanel()
    if not panel or not mapButton then return end
    local corner = db.buttonCorner or "TOPRIGHT"
    local right, bottom = corner:find("RIGHT") ~= nil, corner:find("BOTTOM") ~= nil
    local inside = db.overlay
    if not inside then
        -- (room beside the button, on the outside of the map's corner)
        local need = (panel:GetWidth() + 6) * panel:GetEffectiveScale()
        local b, u = mapButton:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if right then
            inside = (mapButton:GetRight() or 0) * b + need > (UIParent:GetRight() or 0) * u
        else
            inside = (mapButton:GetLeft() or 0) * b - need < 0
        end
    end
    local v = bottom and "BOTTOM" or "TOP"
    panel:ClearAllPoints()
    if inside then
        -- (into the map: under the button, or above it in a bottom corner)
        local side = right and "RIGHT" or "LEFT"
        panel:SetPoint(v .. side, mapButton, (bottom and "TOP" or "BOTTOM") .. side, 0, bottom and 6 or -6)
    else
        panel:SetPoint(v .. (right and "LEFT" or "RIGHT"), mapButton, v .. (right and "RIGHT" or "LEFT"), right and 6 or -6, 0)
    end
end

local function BuildPanel()
    panel = CreateFrame("Frame", "OverlayMapPanel", UIParent, "BackdropTemplate")
    panel:SetWidth(230)
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
    title:SetText("Overlay Map")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() panel:Hide() end)

    -- (the first time: the sections changed less often start folded)
    if type(db.panelFolded) ~= "table" then db.panelFolded = { Style = true, Behavior = true } end
    local rows, section = {}, nil
    -- a row: a frame across the panel, `height` tall; shown when its section is unfolded and
    -- `when` (if any) says so
    local function Row(height, when)
        local f = CreateFrame("Frame", nil, panel)
        f:SetHeight(height)
        f.height, f.section, f.when = height, section, when
        f.Refresh = function() end
        rows[#rows + 1] = f
        return f
    end
    -- a section title: click it to fold or unfold the rows under it
    local function Section(name)
        section = nil
        local f = Row(22)
        local b = CreateFrame("Button", nil, f)
        b:SetPoint("TOPLEFT", 8, -4)
        b:SetPoint("BOTTOMRIGHT", -8, 0)
        local sign = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sign:SetPoint("LEFT", 4, 0)
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", 16, 0)
        text:SetText(name)
        local line = b:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.75, 0.55, 0.15, 0.4)
        line:SetHeight(1)
        line:SetPoint("LEFT", text, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
        b:GetHighlightTexture():SetAlpha(0.25)
        b:SetScript("OnClick", function()
            db.panelFolded[name] = not db.panelFolded[name] or nil
            RefreshPanel()
        end)
        f.Refresh = function() sign:SetText(db.panelFolded[name] and "+" or "-") end
        section = name
    end

    PanelCheck(Row(28), "overlay", "Overlay Mode (full screen)")
    Section("Map")
    PanelSlider(Row(36, NotOverlay), "scale", "Size", 0.3, 2.5, 0.05, true)
    PanelSlider(Row(36, NotOverlay), "width", "Width", 0.5, 1.5, 0.05, true)
    do
        -- Apply for size and width, lit only while there is something to apply
        local f = Row(28, NotOverlay)
        local apply = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        apply:SetHeight(20)
        apply:SetPoint("TOPLEFT", 10, 0)
        apply:SetPoint("TOPRIGHT", -10, 0)
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
    end
    PanelSlider(Row(38), "opacity", "Map Opacity", 0, 1, 0.05)
    Section("Markers")
    PanelSlider(Row(36), "pinOpacity", "Marker Opacity", 0.1, 1, 0.05)
    PanelSlider(Row(38), "markerSize", "Marker Size", 0.5, 2.5, 0.05)
    PanelCheck(Row(22), "onlyMe", "Only My Arrow")
    PanelCheck(Row(26), "arrowCustom", "My Arrow: Own Size & Opacity")
    PanelSlider(Row(36, ArrowOwn), "arrowSize", "My Arrow Size", 0.5, 3, 0.05)
    PanelSlider(Row(38, ArrowOwn), "arrowOpacity", "My Arrow Opacity", 0.1, 1, 0.05)
    Section("Style")
    PanelCycle(Row(24), "style", "Style", STYLE_CHOICES)
    PanelCycle(Row(24), "edge", "Soft Edges", EDGE_CHOICES, StandardStyle)
    PanelCycle(Row(28), "shape", "Shape", SHAPE_CHOICES, StandardStyle)
    Section("Behavior")
    PanelCheck(Row(22), "clickThrough", "Click Through (Shift: use the map)")
    PanelCheck(Row(22), "follow", "Follow Me")
    PanelCheck(Row(26), "rememberZoom", "Remember Zoom")
    panel.rows = rows

    local move = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    move:SetHeight(20)
    move:SetPoint("BOTTOMLEFT", 10, 34)
    move:SetPoint("BOTTOMRIGHT", -10, 34)
    move:SetText("Move the Map")
    move:SetScript("OnClick", function() SlashCmdList.OVERLAYMAP("move") end)
    local all = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    all:SetHeight(20)
    all:SetPoint("BOTTOMLEFT", 10, 10)
    all:SetPoint("BOTTOMRIGHT", -10, 10)
    all:SetText("All Options")
    all:SetScript("OnClick", function() SlashCmdList.OVERLAYMAP("") end)

    local function Layout()
        local y = -32
        for _, f in ipairs(rows) do
            local shown = not (f.section and db.panelFolded[f.section]) and (not f.when or f.when())
            f:SetShown(shown)
            if shown then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
                f:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
                y = y - f.height
            end
        end
        panel:SetHeight(-y + 4 + 58)
        move:SetEnabled(not db.overlay)
    end

    panel:SetScript("OnShow", function(self)
        for _, f in ipairs(self.rows) do f:Refresh() end
        Layout()
        self:UpdateApply()
        PlacePanel()
    end)
    RefreshPanel = function()
        if panel:IsShown() then panel:GetScript("OnShow")(panel) end
    end
    panel:Hide()
end

local function ButtonWanted()
    return compact and db.buttonMode ~= "hide" and (not settling or (panel and panel:IsShown()))
end

-- Two opacities: one with the mouse on the button or close to it (its own size around it),
-- one otherwise: always ("Always") or only with the mouse over the map ("On hover").
local function MapButtonAlpha()
    local near = db.buttonSize
    if (panel and panel:IsShown()) or mapButton:IsMouseOver(near, -near, -near, near) then
        return db.buttonNearOpacity
    end
    if db.buttonMode == "show" or Canvas():IsMouseOver() then return db.buttonOpacity end
    return 0
end

local function BuildMapButton()
    mapButton = CreateFrame("Button", "OverlayMapButton", UIParent)
    mapButton:SetClampedToScreen(true) -- (never off the screen, wherever the map is)
    mapButton:SetSize(db.buttonSize, db.buttonSize)
    local bg = mapButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local icon = mapButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    mapButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    mapButton:SetScript("OnClick", function()
        if not panel then BuildPanel() end
        if panel:IsShown() then
            panel:Hide()
        else
            panel:Show() -- (placed as it shows: PlacePanel)
        end
    end)
    mapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Overlay Map options")
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

-- In the map's top right corner; when the map is bigger than the screen there (a large Size or
-- Width, or moved near an edge), in the corner of the part of the map that's on screen, so it can
-- always be reached.
PlaceMapButton = function()
    local c = Canvas()
    local corner = db.buttonCorner or "TOPRIGHT"
    local right, top = corner:find("RIGHT") ~= nil, corner:find("TOP") ~= nil
    local k = c:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local r, t, l, b = c:GetRight(), c:GetTop(), c:GetLeft(), c:GetBottom()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local x, y
    if r and t then
        r, t, l, b = r * k, t * k, l * k, b * k
        if (right and r > w) or (not right and l < 0) or (top and t > h) or (not top and b < 0) then
            -- the corner of the part of the map on screen (and room for the button in it)
            local room = db.buttonSize + 8
            local vl, vr = math.max(l, 0), math.min(r, w)
            local vb, vt = math.max(b, 0), math.min(t, h)
            x = right and math.max(vr, vl + room) - 4 or math.min(vl, vr - room) + 4
            y = top and math.max(vt, vb + room) - 4 or math.min(vb, vt - room) + 4
        end
    end
    local want = corner .. (x and (":" .. math.floor(x * 10) .. ":" .. math.floor(y * 10)) or ":map")
    if mapButton.placedAt == want and mapButton:GetNumPoints() > 0 then return end
    mapButton.placedAt = want
    mapButton:ClearAllPoints()
    if x then
        mapButton:SetPoint(corner, UIParent, "BOTTOMLEFT", x, y)
    else
        mapButton:SetPoint(corner, c, corner, right and -4 or 4, top and -4 or 4)
    end
    if panel and panel:IsShown() then PlacePanel() end
end

UpdateMapButton = function()
    if not ButtonWanted() then
        if mapButton then mapButton:Hide() end
        if panel and not compact then panel:Hide() end
        return
    end
    if not mapButton then BuildMapButton() end
    local map = Map()
    mapButton:SetSize(db.buttonSize, db.buttonSize)
    PlaceMapButton()
    -- (once more next frame, when the map's new size and place are laid out)
    if not mapButton.recheck then
        mapButton.recheck = true
        C_Timer.After(0, function()
            mapButton.recheck = nil
            if mapButton:IsShown() then PlaceMapButton() end
        end)
    end
    mapButton:SetFrameStrata("FULLSCREEN")
    mapButton:SetAlpha(MapButtonAlpha())
    mapButton:Show()
end

--------------------------------------------------------------------------------
-- Options: Options > AddOns > Overlay Map
--------------------------------------------------------------------------------

local category

local function BuildOptions()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Overlay Map")

    local function Register(key, name)
        local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db,
            type(DEFAULTS[key]), name, DEFAULTS[key])
        setting:SetValueChangedCallback(function()
            SyncOverlay()
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
        return Settings.CreateSlider(category, Register(key, name), options, tooltip)
    end

    local function Header(name)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
        end
    end

    local function Button(name, label, fn, tooltip)
        if not (layout and CreateSettingsButtonInitializer) then return end
        local init = CreateSettingsButtonInitializer(name, label, fn, tooltip, false)
        layout:AddInitializer(init)
        return init
    end

    -- greyed out while the parent's predicate says no
    local function Under(parent, init, predicate)
        if parent and init and init.SetParentInitializer then init:SetParentInitializer(parent, predicate) end
    end

    local overlayInit = Settings.CreateCheckbox(category, Register("overlay", "Overlay Mode"),
        "One switch for an overlay map: the map fills the whole screen, see-through and click-through, "
        .. "with solid markers and large soft edges. It keeps its own Map Opacity, Marker Opacity, Marker Size, My Arrow, "
        .. "Style, Soft Edges, Shape, Click Through and Keep Opacity While Moving: what you change while it's "
        .. "on stays with Overlay Mode, and the normal map keeps its own. Size, width and position don't apply "
        .. "while it's on.")

    Header("Map")
    Settings.CreateDropdown(category, Register("mode", "Key"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("hold", "Hold to show")
        container:Add("press", "Press to show or hide")
        return container:GetData()
    end, "Hold: the map shows while you hold the key. Press: one press shows it, the next one hides it.")
    Under(overlayInit, Slider("scale", "Size", "Size of the map. Overlay Mode fills the screen instead.", 0.3, 2.5, 0.05), NotOverlay)
    Under(overlayInit, Slider("width", "Width", "Width of the map compared to its usual shape. Lower makes it "
        .. "more square; the map then zooms in to fill it, centred on you. Overlay Mode fills the screen instead.",
        0.5, 1.5, 0.05), NotOverlay)
    Slider("opacity", "Map Opacity", "How see-through the map itself is. At 0%, only the markers show, "
        .. "floating over the world.", 0, 1, 0.05)
    Under(overlayInit, Button("Position", "Move", ShowMover,
        "Shows a box the size of the map. Drag it, then right-click it when done."), NotOverlay)
    Under(overlayInit, Button("", "Reset Position", function()
        db.x, db.y = 0, 0
        if mover and mover:IsShown() then ShowMover() end
        ApplyLook()
    end, "Puts the map back in the middle of the screen."), NotOverlay)

    Header("Markers")
    Slider("pinOpacity", "Marker Opacity",
        "How see-through the markers on the map are: quests, vendors, flight points, your arrow and other addons' markers.",
        0.1, 1, 0.05)
    Slider("markerSize", "Marker Size", "Size of the markers on the map, Questie's and OpenMap's icons too "
        .. "(on top of OpenMap's own Icon size).", 0.5, 2.5, 0.05)
    Settings.CreateCheckbox(category, Register("onlyMe", "Only My Arrow"),
        "Hides every marker on the map (quests, vendors, Questie's and OpenMap's icons) except your own "
        .. "arrow. The map's picture stays.")
    local arrowInit = Settings.CreateCheckbox(category, Register("arrowCustom", "My Arrow: Own Size & Opacity"),
        "Your arrow on the map at a size and opacity of its own, apart from the other markers. "
        .. "On the game's map (without OpenMap), the opacity is also your party's dots'.")
    for _, init in ipairs({
        Slider("arrowSize", "My Arrow Size", "Size of your arrow on the map.", 0.5, 3, 0.05),
        Slider("arrowOpacity", "My Arrow Opacity", "How see-through your arrow on the map is.", 0.1, 1, 0.05),
    }) do
        Under(arrowInit, init, ArrowOwn)
        if init and init.AddShownPredicate then init:AddShownPredicate(ArrowOwn) end
    end

    Header("Style")
    local styleInit = Settings.CreateDropdown(category, Register("style", "Map Style"), function()
        local container = Settings.CreateControlTextContainer()
        for _, c in ipairs(STYLE_CHOICES) do container:Add(c[1], c[2]) end
        return container:GetData()
    end, "Standard: the map as it is, with the soft edges below. Torn Parchment: torn, burnt paper edges, "
        .. "like an old map (the soft edges don't apply then).")
    local edgeInit = Settings.CreateDropdown(category, Register("edge", "Soft Edges"), function()
        local container = Settings.CreateControlTextContainer()
        for _, c in ipairs(EDGE_CHOICES) do container:Add(c[1], c[2]) end
        return container:GetData()
    end, "The map and its markers fade out towards the edges, like the overlay maps of other games. "
        .. "Standard style only.")
    local shapeInit = Settings.CreateDropdown(category, Register("shape", "Soft Edges Shape"), function()
        local container = Settings.CreateControlTextContainer()
        for _, c in ipairs(SHAPE_CHOICES) do container:Add(c[1], c[2]) end
        return container:GetData()
    end, "The shape the map fades into: a rectangle with rounded corners, a diamond or an oval. "
        .. "With a diamond or an oval, the corners of the map fade away completely; with Soft Edges off, "
        .. "the map is cut sharp in that shape. Standard style only.")
    Under(styleInit, edgeInit, StandardStyle)
    Under(styleInit, shapeInit, StandardStyle)

    Header("Behavior")
    Settings.CreateCheckbox(category, Register("clickThrough", "Click Through"),
        "The mouse goes through the map to the world behind it, so you can click and turn your character "
        .. "with the right button over it. Markers still show their names. Hold Shift to drag and zoom the map. "
        .. "Overlay Mode turns this on.")
    Settings.CreateCheckbox(category, Register("follow", "Follow Me"),
        "Keeps the map centred on you while it's open, like the minimap. It holds still while the mouse is "
        .. "over the map (in Overlay Mode, over a marker, or with Shift held). Without OpenMap, zoom in "
        .. "with the mouse wheel to see it move: zoomed all the way out, the whole zone already fits.")
    Settings.CreateCheckbox(category, Register("rememberZoom", "Remember Zoom"),
        "Opens at the zoom the map had when you last closed it, apart from the normal map's. With OpenMap, "
        .. "OpenMap's own reopen option still decides where it's centred.")
    Settings.CreateCheckbox(category, Register("noFade", "Keep Opacity While Moving"),
        "With this off, the map fades to half while you move, like the game's own map.")
    Settings.CreateCheckbox(category, Register("hideMinimap", "Hide Minimap"),
        "Hides the minimap while the map is open.")

    Header("Also Hide While the Map Is Open")
    for _, group in ipairs(HIDE_GROUPS) do
        Settings.CreateCheckbox(category, Register(group.key, group.label),
            "Hidden while the map is open, and back when it closes.")
    end
    Settings.CreateCheckbox(category, Register("hideNames", "Character Names"),
        "The names above players', NPCs' and pets' heads, hidden while the map is open and back as they "
        .. "were when it closes. The game doesn't allow changing them in combat: then they're hidden, or "
        .. "come back, when combat ends.")

    Header("Options Button")
    Settings.CreateDropdown(category, Register("buttonMode", "Options Button"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("hover", "On hover")
        container:Add("show", "Always")
        container:Add("hide", "Hidden")
        return container:GetData()
    end, "The arrow button in the corner of the map, which opens a small panel with these options. "
        .. "On hover: it shows while the mouse is over the map.")
    Settings.CreateDropdown(category, Register("buttonCorner", "Options Button Corner"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("TOPRIGHT", "Top right")
        container:Add("TOPLEFT", "Top left")
        container:Add("BOTTOMRIGHT", "Bottom right")
        container:Add("BOTTOMLEFT", "Bottom left")
        return container:GetData()
    end, "The corner of the map the options button sits in. The small panel opens beside it, or into the "
        .. "map when there's no room outside (always, in Overlay Mode).")
    Slider("buttonOpacity", "Options Button Opacity",
        "How see-through the options button is with the mouse over the map (or all the time, with Always). "
        .. "At 0% it only shows when the mouse gets close to it.", 0, 1, 0.05)
    Slider("buttonNearOpacity", "Options Button Opacity Up Close",
        "How see-through the options button is with the mouse on it or right next to it.", 0, 1, 0.05)
    do
        local options = Settings.CreateSliderOptions(14, 48, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
            return string.format("%d", v)
        end)
        Settings.CreateSlider(category, Register("buttonSize", "Options Button Size"), options,
            "Size of the options button, in pixels.")
    end

    Settings.RegisterAddOnCategory(category)
end

local function OpenOptions()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        Say("Options: Options > AddOns > Overlay Map.")
    end
end

-- /omap debug: what the map looks like from the inside, to find out why something doesn't apply.
function OverlayMap_Debug()
    local map, canvas = Map(), Canvas()
    local function f(v) return type(v) == "number" and string.format("%.2f", v) or tostring(v) end
    local function try(obj, method)
        if not obj or not obj[method] then return "n/a" end
        local ok, a, b = pcall(obj[method], obj)
        if not ok then return "error" end
        return b ~= nil and (f(a) .. ", " .. f(b)) or f(a)
    end
    Say("debug. Client " .. tostring((select(4, GetBuildInfo()))) .. ", Overlay Map open: " .. tostring(compact))
    Say("Saved: size " .. f(db.scale) .. ", map " .. f(db.opacity) .. ", markers " .. f(db.pinOpacity)
        .. ", overlay mode " .. tostring(db.overlay and true or false))
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
        .. ", on Overlay Map's layer " .. tostring(sample and moved[sample] or false) .. ". Width " .. f(db.width))
    local layers, layerAlpha = 0, nil
    if map and map.detailLayerPool and map.detailLayerPool.EnumerateActive then
        for layer in map.detailLayerPool:EnumerateActive() do
            layers = layers + 1
            layerAlpha = layer:GetAlpha()
        end
    end
    Say("Map layers: " .. layers .. ", alpha of one: " .. f(layerAlpha))
    local function MouseState(obj)
        if not obj then return "n/a" end
        if obj.IsMouseClickEnabled then
            return "click " .. tostring(obj:IsMouseClickEnabled()) .. ", hover " .. tostring(obj:IsMouseMotionEnabled())
        end
        return "mouse " .. tostring(obj:IsMouseEnabled())
    end
    Say("Click through: " .. tostring(db.clickThrough) .. ". Map area: " .. MouseState(canvas)
        .. ". Inside: " .. MouseState(canvas and canvas.Child) .. ". One Questie marker: " .. MouseState(sample)
        .. (sample and (", strata " .. sample:GetFrameStrata() .. ", level " .. sample:GetFrameLevel()) or ""))
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local top = foci and foci[1]
    Say("Under the mouse: " .. tostring(top and (top:GetName() or (top.pinTemplate and ("marker " .. top.pinTemplate))
        or tostring(top:GetObjectType()) .. " of " .. tostring(top:GetParent() and top:GetParent():GetName()))))
    local twins = 0
    for f in pairs(onlyHidden) do if IsTownsfolk(f) then twins = twins + 1 end end
    Say("Questie's townsfolk icons hidden (OpenMap draws its own): " .. twins)
    if top then
        Say("  townsfolk icon: " .. tostring(top.isManualIcon) .. ", level " .. top:GetFrameLevel() .. ", strata " .. top:GetFrameStrata()
            .. ", hidden by Overlay Map: " .. tostring(onlyHidden[top] ~= nil))
    end
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
    for _, group in ipairs(HIDE_GROUPS) do
        if db[group.key] then
            local parts = {}
            for _, fr in ipairs(GroupFrames(group)) do
                if fr:IsShown() or hiddenExtra[fr] or faded[fr] ~= nil then
                    local how = hiddenExtra[fr] and "hidden" or (faded[fr] ~= nil and "invisible") or "untouched"
                    local sh = shields[fr]
                    parts[#parts + 1] = (fr:GetName() or "?") .. " " .. how
                        .. (fr:IsProtected() and " (protected)" or "")
                        .. (sh and sh:IsShown() and (", shield " .. sh:GetFrameStrata() .. " "
                            .. string.format("%.0fx%.0f", sh:GetWidth(), sh:GetHeight())) or "")
                end
            end
            Say(group.label .. ": " .. (#parts > 0 and table.concat(parts, "; ") or "nothing shown"))
        end
    end
    -- What's under the mouse, and what holds it, up to the screen: who made it, its size and scale.
    local function Describe(fr)
        local what = fr:GetName() or fr:GetObjectType()
        if fr.pinTemplate then what = what .. " [marker " .. tostring(fr.pinTemplate) .. "]" end
        if fr.Icon and fr.anchor then what = what .. " [OpenMap icon]" end
        if fr.icon then what = what .. " [holds an icon]" end
        if fr == layer then what = what .. " [Overlay Map's marker layer]" end
        if fr == viewLayer then what = what .. " [Overlay Map's icon layer]" end
        if iconLayers[fr] then what = what .. " [an addon's icon layer]" end
        local w, h = fr:GetSize()
        return string.format("%s  %.0fx%.0f, scale %.2f (on screen %.2f), alpha %.2f%s", what, w or 0, h or 0,
            fr:GetScale(), fr:GetEffectiveScale(), fr:GetEffectiveAlpha(), fr:IsShown() and "" or ", hidden")
    end
    local foci2 = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local f1 = foci2 and foci2[1]
    if f1 then
        Say("Under the mouse, and what holds it:")
        local fr, n = f1, 0
        while fr and n < 7 do
            DEFAULT_CHAT_FRAME:AddMessage("   " .. string.rep("  ", n) .. Describe(fr))
            fr, n = fr:GetParent(), n + 1
        end
    else
        Say("Under the mouse: nothing")
    end
    Say("Map-related addons loaded: " .. (#list > 0 and table.concat(list, ", ") or "none"))
end

SLASH_OVERLAYMAP1 = "/overlaymap"
SLASH_OVERLAYMAP2 = "/omap"
SlashCmdList.OVERLAYMAP = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" then
        OverlayMap_Debug()
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
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_REGEN_DISABLED" then
        ExtrasEnterCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ExtrasLeaveCombat()
    elseif event == "MODIFIER_STATE_CHANGED" then
        if compact and db.clickThrough then ApplyClickThrough() end
    elseif event == "ADDON_LOADED" and name == ADDON_NAME then
        -- Settings from when the addon was called Quick Map (its saved file renamed to OverlayMap.lua
        -- in the WTF folder), taken over once.
        if OverlayMapDB == nil and type(QuickMapDB) == "table" then OverlayMapDB = QuickMapDB end
        QuickMapDB = nil
        OverlayMapDB = OverlayMapDB or {}
        db = OverlayMapDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        if db.mode ~= "hold" and db.mode ~= "press" then db.mode = "hold" end
        if type(db.edge) ~= "number" or db.edge < 0 or db.edge > 4 then db.edge = DEFAULTS.edge end
        if db.shape == "torn" then db.shape, db.style = DEFAULTS.shape, "torn" end -- (it was a shape before)
        if not SHAPE_FILES[db.shape] then db.shape = DEFAULTS.shape end
        if db.style ~= "standard" and db.style ~= "torn" then db.style = DEFAULTS.style end
        local corners = { TOPRIGHT = true, TOPLEFT = true, BOTTOMRIGHT = true, BOTTOMLEFT = true }
        if not corners[db.buttonCorner] then db.buttonCorner = DEFAULTS.buttonCorner end
        if db.buttonMode ~= "show" and db.buttonMode ~= "hover" and db.buttonMode ~= "hide" then
            db.buttonMode = "hover"
        end
        BuildOptions()
    elseif event == "PLAYER_LOGIN" then
        HookMap()
        ShowNames() -- (names left hidden if the game closed with the map open)
        if not GetBindingKey("OVERLAYMAP_SHOW") then
            Say("Choose a key in Options > Keybindings > AddOns > Overlay Map. /omap opens the options.")
        end
    end
end)