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
    buttonMode = "hover", -- the options button on the map: "show", "hover" (with the mouse over the map), "hide"
    buttonOpacity = 0.8,     -- with the mouse over the map (or always, with "show")
    buttonNearOpacity = 1,   -- with the mouse on the button or right next to it
    buttonSize = 22,
    x = 0, y = 0,    -- position of the map's centre, from the centre of the screen
}

local db
local compact = false   -- the map is open in Overlay Map's look
local hidden = {}       -- frame or texture -> { alpha, mouse } it had before Overlay Map hid it
local stopped = {}      -- frames Overlay Map hid completely (they stop working until shown again)
-- Frames as big as the map area that other addons put on it for their icons (OpenMap draws its
-- vendors, mailboxes, flight points and its own arrow on one): kept, and given the objectives'
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

local function Fade(f)
    if faded[f] == nil then faded[f] = f:GetAlpha() end
    if f:GetAlpha() > 0 then f:SetAlpha(0) end
    -- shielded only while it's there to be clicked
    if f:IsVisible() then
        if not (shields[f] and shields[f]:IsShown()) then Shield(f) end
    elseif shields[f] then
        shields[f]:Hide()
    end
end

local function Unfade(f)
    f:SetAlpha(faded[f])
    faded[f] = nil
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

local function ExtrasLeaveCombat()
    for f in pairs(showLater) do pcall(f.Show, f) end
    wipe(showLater)
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

local function MovePin(pin)
    if not hookedPins[pin] then
        hookedPins[pin] = true
        -- The map puts its markers back on itself whenever it places them again (zooming,
        -- new markers); while Overlay Map shows it, they go straight back to the layer.
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
    -- The game fades the map while you move; Overlay Map does it itself (to half) when
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

-- Soft edges. The map and its markers fade out towards the edges of the map area, like the
-- overlay maps of other games. Every picture in the map area gets a mask: a picture that is
-- solid in the middle and fades to nothing at its edges, laid over the map area. Each frame
-- holding pictures gets its own mask; new pictures (markers appearing, map tiles loading as
-- you zoom) are picked up as they come.
local SHAPE_FILES = { rect = "Edge", diamond = "Diamond", oval = "Oval" }
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local function EdgeFile()
    -- (the torn parchment's edge is always the same; soft edges come in four widths)
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
    if not compact or (not torn and (db.edge or 0) < 1) then
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

local function Follow(force)
    -- With the mouse over the map, it holds still so you can look at the markers (it catches up
    -- with you when the mouse leaves).
    if Canvas():IsMouseOver() then
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
local ApplyClickThrough -- (further down)
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
    HideExtras()
    if db.hideMinimap then HideMinimap() end
    if db.clickThrough then ApplyClickThrough() end -- (in case something gave the mouse back)
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
                if not f:IsMouseMotionEnabled() then pcall(f.SetMouseMotionEnabled, f, true) end
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
    ApplyEdges()
    ApplyClickThrough()
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
    SaveZoom()
    compact = false
    local map = Map()
    RevealAll()
    ShowMinimap()
    ShowExtras()
    Unmask()
    ApplyClickThrough() -- (compact is off: everything takes the mouse again)
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

local mapButton, panel
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

-- Overlay mode: one switch that makes the map big, in the middle of the screen, see-through
-- (markers stay solid) and with large soft edges. Turning it off puts back what you had.
local OVERLAY_KEYS = { "scale", "width", "opacity", "pinOpacity", "edge", "x", "y", "noFade", "clickThrough" }

local function OverlaySize()
    local w, h = (db.areaW or 702), (db.areaH or 467)
    local s = math.min(UIParent:GetWidth() * 0.9 / w, UIParent:GetHeight() * 0.85 / h)
    return math.max(0.3, math.min(2.5, math.floor(s * 20) / 20))
end

local RefreshPanel -- (further down)

local function SyncOverlay()
    if db.overlay and not db.overlayActive then
        db.beforeOverlay = {}
        for _, k in ipairs(OVERLAY_KEYS) do db.beforeOverlay[k] = db[k] end
        db.scale, db.width, db.x, db.y = OverlaySize(), 1, 0, 0
        db.opacity, db.pinOpacity, db.edge, db.noFade = 0.3, 1, 3, true
        db.clickThrough = true
        db.overlayActive = true
    elseif not db.overlay and db.overlayActive then
        for k, v in pairs(db.beforeOverlay or {}) do db[k] = v end
        db.beforeOverlay = nil
        db.overlayActive = false
    else
        return
    end
    if RefreshPanel then RefreshPanel() end
    if compact then ApplyShape() end
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
        SyncOverlay()
        ApplyLook()
    end)
    function cb:Refresh() self:SetChecked(db[key] and true or false) end
    return cb
end

-- A button that steps through a few choices: "Label: Choice"
local function PanelCycle(parent, y, key, label, choices, enabledIf)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", 10, y)
    b:SetPoint("TOPRIGHT", -10, y)
    function b:Refresh()
        for _, c in ipairs(choices) do
            if c[1] == db[key] then self:SetText(label .. ": " .. c[2]) end
        end
        if enabledIf then self:SetEnabled(enabledIf()) end
    end
    b:SetScript("OnClick", function(self)
        for i, c in ipairs(choices) do
            if c[1] == db[key] then
                db[key] = choices[i % #choices + 1][1]
                break
            end
        end
        self:Refresh()
        SyncOverlay()
        ApplyLook()
        if RefreshPanel then RefreshPanel() end -- (other rows may depend on this one)
    end)
    return b
end

local function BuildPanel()
    panel = CreateFrame("Frame", "OverlayMapPanel", UIParent, "BackdropTemplate")
    panel:SetSize(230, 516)
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

    panel.rows = {
        PanelCycle(panel, -32, "mode", "Key", { { "hold", "Hold to show" }, { "press", "Press to show or hide" } }),
        PanelSlider(panel, -60, "scale", "Size", 0.3, 2.5, 0.05, true),
        PanelSlider(panel, -96, "width", "Width", 0.5, 1.5, 0.05, true),
        PanelSlider(panel, -158, "opacity", "Map Opacity", 0, 1, 0.05),
        PanelSlider(panel, -194, "pinOpacity", "Objectives Opacity", 0.1, 1, 0.05),
        PanelCycle(panel, -230, "style", "Style", STYLE_CHOICES),
        PanelCycle(panel, -254, "edge", "Soft Edges", EDGE_CHOICES, StandardStyle),
        PanelCycle(panel, -278, "shape", "Shape", SHAPE_CHOICES, StandardStyle),
        PanelCheck(panel, -308, "noFade", "Keep Opacity While Moving"),
        PanelCheck(panel, -330, "hideMinimap", "Hide Minimap"),
        PanelCheck(panel, -352, "follow", "Follow Me"),
        PanelCheck(panel, -374, "rememberZoom", "Remember Zoom"),
        PanelCheck(panel, -396, "clickThrough", "Click Through (Shift: use the map)"),
        PanelCycle(panel, -426, "overlay", "Overlay Mode", { { false, "Off" }, { true, "On" } }),
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
    more:SetScript("OnClick", function() SlashCmdList.OVERLAYMAP("move") end)
    local all = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    all:SetHeight(20)
    all:SetPoint("BOTTOMLEFT", 10, 10)
    all:SetPoint("BOTTOMRIGHT", -10, 10)
    all:SetText("All Options")
    all:SetScript("OnClick", function() SlashCmdList.OVERLAYMAP("") end)
    panel:SetScript("OnShow", function(self)
        for _, row in ipairs(self.rows) do row:Refresh() end
        self:UpdateApply()
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
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", mapButton, "TOPRIGHT", 6, 0)
            panel:Show()
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

UpdateMapButton = function()
    if not ButtonWanted() then
        if mapButton then mapButton:Hide() end
        if panel and not compact then panel:Hide() end
        return
    end
    if not mapButton then BuildMapButton() end
    local map = Map()
    mapButton:SetSize(db.buttonSize, db.buttonSize)
    mapButton:ClearAllPoints()
    mapButton:SetPoint("TOPRIGHT", Canvas(), "TOPRIGHT", -4, -4)
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
        Settings.CreateSlider(category, Register(key, name), options, tooltip)
    end

    Settings.CreateDropdown(category, Register("mode", "Key"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("hold", "Hold to show")
        container:Add("press", "Press to show or hide")
        return container:GetData()
    end, "Hold: the map shows while you hold the key. Press: one press shows it, the next one hides it.")

    Slider("scale", "Size", "Size of the map.", 0.3, 2.5, 0.05)
    Slider("width", "Width", "Width of the map compared to its usual shape. Lower makes it more square; "
        .. "the map then zooms in to fill it, centred on you.", 0.5, 1.5, 0.05)
    Slider("opacity", "Map Opacity", "How see-through the map itself is. At 0%, only the markers show, "
        .. "floating over the world.", 0, 1, 0.05)
    Slider("pinOpacity", "Objectives Opacity",
        "How see-through the markers on the map are: quests, vendors, flight points, your arrow and other addons' markers.",
        0.1, 1, 0.05)
    Settings.CreateCheckbox(category, Register("noFade", "Keep Opacity While Moving"),
        "With this off, the map fades to half while you move, like the game's own map.")
    Settings.CreateCheckbox(category, Register("hideMinimap", "Hide Minimap"),
        "Hides the minimap while the map is open.")
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Style"))
    end
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
        .. "With a diamond or an oval, the corners of the map fade away completely. Standard style only.")
    -- (greyed out with the Torn Parchment style)
    for _, init in ipairs({ edgeInit, shapeInit }) do
        if init and init.SetParentInitializer and styleInit then
            init:SetParentInitializer(styleInit, StandardStyle)
        end
    end
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("More"))
    end
    Settings.CreateCheckbox(category, Register("overlay", "Overlay Mode"),
        "One switch for an overlay map: big, in the middle of the screen, see-through, with solid markers "
        .. "and large soft edges. Turning it off puts back the size, width, position, opacities and edges you had.")
    Settings.CreateCheckbox(category, Register("clickThrough", "Click Through"),
        "The mouse goes through the map to the world behind it, so you can click and turn your character "
        .. "with the right button over it. Markers still show their names. Hold Shift to drag and zoom the map. "
        .. "Overlay mode turns this on.")
    Settings.CreateCheckbox(category, Register("rememberZoom", "Remember Zoom"),
        "Opens at the zoom the map had when you last closed it, apart from the normal map's. With OpenMap, "
        .. "OpenMap's own reopen option still decides where it's centred.")
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
    local foci2 = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local f1 = foci2 and foci2[1]
    Say("Mouse focus: " .. tostring(f1 and (f1:GetName() or (f1:GetObjectType() .. " in "
        .. tostring(f1:GetParent() and f1:GetParent():GetName())))))
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
        if db.buttonMode ~= "show" and db.buttonMode ~= "hover" and db.buttonMode ~= "hide" then
            db.buttonMode = "hover"
        end
        BuildOptions()
    elseif event == "PLAYER_LOGIN" then
        HookMap()
        if not GetBindingKey("OVERLAYMAP_SHOW") then
            Say("Choose a key in Options > Keybindings > AddOns > Overlay Map. /omap opens the options.")
        end
    end
end)
