-- Overlay Map
-- Shows the game's own map of your zone with a key, without its border, buttons and quest log.
-- It uses the real map, so every marker on it shows too, including other addons' (Questie...).
-- The map is put back exactly as it was when Overlay Map closes it, or when you open it normally.

local ADDON_NAME, ns = ...
-- The tables every file adds to, made first so any file can use them as it loads
ns.Keep, ns.Zone, ns.Wizard, ns.Outline, ns.Arrow = {}, {}, {}, {}, {}
-- The saved settings: each file keeps its own db, set as they load (ADDON_LOADED: ns.SetDB)
ns.dbSetters = {}
function ns.SetDB(t) for _, set in ipairs(ns.dbSetters) do set(t) end end
local Keep, Zone, Wizard, Outline = ns.Keep, ns.Zone, ns.Wizard, ns.Outline
local db
ns.dbSetters[#ns.dbSetters + 1] = function(t) db = t end

BINDING_NAME_OVERLAYMAP_SHOW = "Show the map"

local DEFAULTS = {
    mode = "hold",   -- "hold": shown while the key is held; "press": one press shows, the next hides
    scale = 0.8,     -- size of the map
    width = 1,       -- width of the map compared to its usual shape (lower: more square)
    opacity = 0.85,  -- opacity of the map itself
    pinOpacity = 1,  -- opacity of the markers on it (quests, vendors, your arrow...)
    markerSize = 1,  -- size of the markers (the game's own setting for the map's markers)
    onlyMe = false,  -- hide every marker except your own arrow
    caveMouths = true, -- a marker at each cave entrance Overlay Map knows (with OpenMap)
    arrowCustom = false, -- your own arrow at its own size and opacity (below)
    arrowSize = 1, arrowOpacity = 1,
    arrowNoFade = false, -- your arrow (and your party's) not faded with the map while you move (Fade while moving)
    moveFade = 0,    -- how much the map fades while you move (0: not at all, to 0.9)
    moveFadeHover = true, -- Fade while moving: the map solid again with the mouse over it
    moveFadeCombat = false, -- Fade while moving: the same fade all through combat, moving or not
    moveFadeFlight = false, -- Fade while moving: not on a flight (the map solid while you fly)
    combatReady = false, -- the map opened unseen as combat starts (in a group, or with OpenMap), so it opens right in the fight
    moveFadeMarkers = false, -- Fade while moving: the markers fade with the map (off: only the map, as Map opacity)
    hideMinimap = true, -- hide the minimap while the map is open
    follow = false,  -- keep the map centred on you while it's open, like the minimap
    edge = 2,        -- soft edges, like an overlay map: 0 off, 1 small ... 4 very large
    shape = "rect",  -- shape of those edges: "rect" (rounded rectangle), "diamond" or "oval"
    zoneBorder = false, -- the map cut to your zone's outline (on top of the shape and style)
    zoneSoft = true, -- the zone's outline faded in from the border (off: cut sharp)
    zoneDim = 0.3,   -- with the zone border: how much of the rest of the map shows (0: hidden; 5% steps)
    -- with the zone border, the map zoomed to fit your zone (Auto-zoom to zone, any of them): entering a new
    -- zone, every time the map opens, leaving a town or capital (back to the zone around it)
    fitEnter = true, fitOpen = false, fitLeave = true,
    keepZoomTime = 30, -- with Fit Zone: seconds your own zoom is kept before Fit Zone may zoom again (0: never kept)
    zoneView = false, -- with the zone border and OpenMap: the outline is the zone in the middle of the view
    zoneKeep = true, -- with the zone border and OpenMap: over the sea or land of no zone, the outline stays
    zoneWhole = 0.45, -- with the zone border and OpenMap: the whole map once the zone fills less of the view
    style = "standard", -- map style: "standard", "torn" (torn parchment: torn, burnt paper edges) or
                        -- "outlines" (white lines of cliffs, water and roads; Overlay Map: Outlines download)
    outlineLines = 1,  -- Outlines style: the lines' opacity
    outlineBack = 0.6, -- Outlines style: the dark background's opacity
    rememberZoom = true, -- open at the zoom Overlay Map's map had when it last closed
    fitPlaces = true, -- caves (with OpenMap) and dungeons: zoomed to fit as you enter them
    fitTowns = true, -- towns (with OpenMap): zoomed in on as you enter them (a town: an innkeeper or flight master)
    fitFlights = true, -- Auto-zoom to zone during flights too (each zone you fly into, flying out of a town)
    townSize = 400,  -- Auto-zoom towns: how many yards across the view shows
    liveMinimap = false, -- inside dungeons: the game's own minimap, big, in the map's place (with your arrow)
    clickThrough = false, -- the mouse goes through the map to the world (hold Shift to use the map)
    overlay = false, -- overlay mode: big, in the middle, see-through, soft edges
    hideBars = false, hideUnits = false, hideChat = false, hideQuests = false, -- other parts of the
    hideBuffs = false, hideMenu = false, hideXP = false,                       -- interface hidden too
    hideNames = false, -- the names above characters' heads, hidden while the map is open
    buttonMode = "hover", -- the options button on the map: "show", "hover" (with the mouse over the map), "hide"
    buttonOpacity = 0.8,     -- with the mouse over the map (or always, with "show")
    buttonNearOpacity = 1,   -- with the mouse on the button or right next to it
    buttonSize = 22,
    -- other addons on the map while Overlay Map shows it (Addons.lua): off, kept off it till the map closes
    showQuestie = true, showWaypoints = true, showOpenMap = true, showOpenMapIcons = true, showDungeonJournal = true,
    buttonCorner = "TOPRIGHT", -- the map's corner it sits in: TOPRIGHT, TOPLEFT, BOTTOMRIGHT, BOTTOMLEFT
    x = 0, y = 0,    -- position of the map's centre, from the centre of the screen
}
ns.DEFAULTS = DEFAULTS

-- (db: at the top of the file)
ns.compact = false   -- the map is open in Overlay Map's look
local hidden = {}       -- frame or texture -> { alpha, mouse } it had before Overlay Map hid it
local stopped = {}      -- frames Overlay Map hid completely (they stop working until shown again)
ns.stopped = stopped
-- Frames as big as the map area that other addons put on it for their icons (OpenMap draws its
-- vendors, mailboxes, flight points and its own arrow on one): kept, and given the markers'
-- opacity like the map's markers. frame -> true
local iconLayers = {}
ns.iconLayers = iconLayers
local before = {}       -- the map's own scale and the map area's opacity before Overlay Map changed them

local function Say(msg)
    -- (while a bug report is being put together, Keep.BugReport: into the report, not the chat)
    local cap = rawget(_G, "OVERLAYMAP_CAPTURE")
    if cap then cap[#cap + 1] = msg return end
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffOverlay Map:|r " .. msg)
end
ns.Say = Say

local function Map() return WorldMapFrame end
ns.Map = Map
local function Canvas() return WorldMapFrame and WorldMapFrame.ScrollContainer end
ns.Canvas = Canvas

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
ns.Stop = Stop

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
    -- (the quest log beside the small map: hidden completely, not only made invisible, or its
    -- invisible entries under the mouse lit up quests on the map; the game gets it back on close)
    Stop(map.QuestLog)
    -- (Dungeon Journal's dungeon map, lent to the map window inside its dungeons: it stays, see
    -- Zone.DungeonView)
    local fdj = _G.ForeverDungeonJournalFrame
    local fdjBack = fdj and fdj.dungeonMapPanel and fdj.dungeonMapPanel:GetParent()
    -- (and its Dungeon Map / World Map button, in the map's corner: inside a dungeon it's the way back to the
    -- dungeon's map, if you or the journal chose the world map)
    local fdjToggle = _G.ForeverDungeonJournalWorldMapToggle
    for _, child in ipairs({ map:GetChildren() }) do
        if child ~= map.BorderFrame and not owned[child] and child ~= fdjBack and child ~= fdjToggle then Stop(child) end
    end
    for _, child in ipairs({ map:GetChildren() }) do
        if child ~= fdjBack and child ~= fdjToggle then Conceal(child) end
    end
    -- Boxes other addons put inside the map area (a coordinates box, for example) are hidden;
    -- a frame covering the whole map area holds icons, so it stays.
    local c = Canvas()
    local cw, ch = c:GetSize()
    for _, child in ipairs({ c:GetChildren() }) do
        if child ~= c.Child and not iconLayers[child] and not child.overlayMapOwn
            and child ~= _G.OpenMapDungeonView then -- (OpenMap's dungeon map: see Zone.DungeonView)
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
ns.OpenMapLoaded = OpenMapLoaded
-- OpenMap there and laying its world over the map: not while its map is kept off Overlay Map's (the Addons tab,
-- Addons.lua), when the map is the game's own as without OpenMap. (Its window is still OpenMap's: OpenMapLoaded)
local function OpenMapDrives()
    return OpenMapLoaded() and not (ns.Addons and ns.Addons.OpenMapHeld()) or false
end
ns.OpenMapDrives = OpenMapDrives

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
    local ue, ce = UIParent:GetEffectiveScale(), c:GetEffectiveScale()
    local x, y = db.x, db.y
    if db.overlay then x, y = 0, 0 end
    -- (already where it belongs, on its one point: left alone. In a fight the game may refuse the new point after
    -- the old ones were cleared, and the map area fell back on the game's own place for it, lower and to the left)
    local cx, cy = c:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and ux and c:GetNumPoints() == 1 and math.abs(cx * ce - (ux + x) * ue) < 1 and math.abs(cy * ce - (uy + y) * ue) < 1 then
        return
    end
    -- (in a fight, on its one point already: moved by that point, without clearing it first)
    if InCombatLockdown() and c:GetNumPoints() == 1 and c:GetPoint(1) == "CENTER" then
        if pcall(c.SetPoint, c, "CENTER", UIParent, "CENTER", x * ue / ce, y * ue / ce) then return end
    end
    c:ClearAllPoints()
    if pcall(c.SetPoint, c, "CENTER", UIParent, "CENTER", x * ue / ce, y * ue / ce) then return end
    -- The game can refuse anchoring the map area to the screen ("anchor family connection": with some markers
    -- or another addon's frames on the map, it counts as part of the map window's family): then to the map
    -- window itself, its own parent, at the same place on the screen.
    local p = c:GetParent()
    local ux, uy = UIParent:GetCenter()
    local px, py = p:GetCenter()
    if not (ux and px) then return end
    local pe = p:GetEffectiveScale()
    local dx = ((ux + x) * ue - px * pe) / ce
    local dy = ((uy + y) * ue - py * pe) / ce
    if pcall(c.SetPoint, c, "CENTER", p, "CENTER", dx, dy) then return end
    -- (refused too: back on its own anchors, where the game had it, rather than nowhere)
    for _, pt in ipairs(before.points or {}) do pcall(c.SetPoint, c, unpack(pt)) end
end

local function Place()
    AnchorCanvas()
end


-- Other parts of the interface hidden while the map is open, each group with its own option.
-- Frames that don't exist (another client, an addon not installed) are skipped.
local HIDE_GROUPS = {
    { key = "hideBars", label = "Action bars", frames = {
        "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
        "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar",
        "PossessActionBar", "MainMenuBarVehicleLeaveButton",
        "MirrorBarsFrame" } },  -- (Mirror Bars' copies of the bars)
    { key = "hideUnits", label = "Player and target frames", frames = {
        "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "TargetFrameToT" } },
    { key = "hideChat", label = "Chat", frames = { "GeneralDockManager", "ChatFrameMenuButton",
        "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
        "QuickJoinToastButton" }, chat = true },
    { key = "hideQuests", label = "Quest tracker", frames = { "ObjectiveTrackerFrame", "Questie_BaseFrame" } },
    { key = "hideBuffs", label = "Buffs and debuffs", frames = { "BuffFrame", "DebuffFrame" } },
    { key = "hideMenu", label = "Menu and bags", frames = { "MicroMenuContainer", "MicroMenu", "BagsBar" } },
    { key = "hideXP", label = "Experience bar", frames = { "MainStatusTrackingBarContainer",
        "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager", "SmoothExperienceBarFrame" } },
}
ns.HIDE_GROUPS = HIDE_GROUPS

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
ns.GroupFrames = GroupFrames

-- Nothing of these can be clicked by mistake while the map is open:
--   * the ones the game protects (action bars, unit frames) can't be hidden by an addon (in
--     combat at all, and in WoW: Forever not even out of combat), so they're made invisible and
--     covered by an invisible shield that takes the clicks meant for them;
--   * the rest (chat, buffs, quest tracker, menu and bags, experience bar) are hidden.
local hiddenExtra = {}  -- frame -> true: Overlay Map hid it
ns.hiddenExtra = hiddenExtra
local faded = {}        -- frame -> alpha it had: made invisible (and shielded)
ns.faded = faded
local shields = {}      -- frame -> its shield
ns.shields = shields
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

-- (Keep: at the top of the file)

-- The map area where it belongs on screen? Anchored to the map window (when the game refused the screen, as it
-- can in a fight), it went along when the game moved that window (opening the map as a fight starts, Ready in
-- combat): checked once a second, and placed again when it's off
function Keep.CheckPlace()
    local c = Canvas()
    if not c then return end
    local cx, cy = c:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return end
    local ce, ue = c:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local x, y = db.x or 0, db.y or 0
    if db.overlay then x, y = 0, 0 end
    if math.abs(cx * ce - (ux + x) * ue) > 2 or math.abs(cy * ce - (uy + y) * ue) > 2 then
        pcall(Place)
        if Keep.AfterPlace then Keep.AfterPlace() end
    end
end
-- Other addons' frames: an addon may hide its own frames, even protected ones, out of combat (the
-- game's own protected frames are left alone: hiding them from an addon caused trouble). Kept
-- hidden while the map is open: if the addon shows one again, it's hidden again at once.
Keep.ADDON_FRAMES = { MirrorBarsFrame = true }
function Keep.AddonFrame(f)
    local name = f.GetName and f:GetName()
    return name and Keep.ADDON_FRAMES[name] or false
end

-- What a shield covers: the frame, or, for a frame that is only a point holding others (Mirror
-- Bars' copies hang around a 1x1 frame), the box around what it holds.
function Keep.ShieldBox(sh, f)
    sh:ClearAllPoints()
    local w, h = f:GetSize()
    if (w or 0) > 2 and (h or 0) > 2 then
        sh:SetAllPoints(f)
        return
    end
    local u = UIParent:GetEffectiveScale()
    local l, b, r, t
    for _, child in ipairs({ f:GetChildren() }) do
        if child:IsShown() then
            local cl, cb, cw, ch = child:GetRect()
            if cl and cw and cw > 0 then
                local k = child:GetEffectiveScale() / u
                cl, cb, cw, ch = cl * k, cb * k, cw * k, ch * k
                l, b = math.min(l or cl, cl), math.min(b or cb, cb)
                r, t = math.max(r or cl + cw, cl + cw), math.max(t or cb + ch, cb + ch)
            end
        end
    end
    if l then
        sh:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
        sh:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", r, t)
    else
        sh:SetAllPoints(f)
    end
end

Keep.hideHooked = {}
Keep.rehiding = false
function Keep.Rehide(f)
    if Keep.rehiding or not hiddenExtra[f] or not f:IsShown() then return end
    if f:IsProtected() and InCombatLockdown() then return end -- (the watcher fades it instead)
    Keep.rehiding = true
    pcall(f.Hide, f)
    Keep.rehiding = false
end
function Keep.KeepHidden(f)
    if Keep.hideHooked[f] then return end
    Keep.hideHooked[f] = true
    hooksecurefunc(f, "Show", Keep.Rehide)
    hooksecurefunc(f, "SetShown", Keep.Rehide)
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
    Keep.ShieldBox(sh, f)
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

-- The mouse of an invisible part: turned off on every piece of it that uses it (as UI Visibility
-- does), so clicks and the camera go through to the world, remembering which pieces, so exactly
-- those get it back. The game doesn't let addons change it on protected frames in combat: then
-- the part is covered by the shield instead, and its mouse comes back once combat ends.
local mouseOff = {}     -- frame -> { piece -> true }: pieces whose mouse Overlay Map turned off
ns.mouseOff = mouseOff
local mouseLater = {}   -- frame -> true: mouse to give back when combat ends
ns.mouseLater = mouseLater

local function Locked(f)
    return InCombatLockdown() and f:IsProtected()
end

local function MouseOff(f)
    local list = mouseOff[f] or {}
    mouseOff[f] = list
    local function Walk(piece, depth)
        if piece:IsForbidden() then return end
        local on = piece:IsMouseEnabled()
        if not (issecretvalue and issecretvalue(on)) and on then
            if pcall(piece.EnableMouse, piece, false) then list[piece] = true end
        end
        if depth > 0 then
            for _, child in ipairs({ piece:GetChildren() }) do Walk(child, depth - 1) end
        end
    end
    Walk(f, 4)
end

local function MouseBack(f)
    local list = mouseOff[f]
    if not list then return end
    if Locked(f) then
        mouseLater[f] = true
        return
    end
    for piece in pairs(list) do pcall(piece.EnableMouse, piece, true) end
    mouseOff[f] = nil
    mouseLater[f] = nil
end

local function Fade(f)
    if faded[f] == nil then faded[f] = f:GetAlpha() end
    if not fadeHooked[f] then
        fadeHooked[f] = true
        hooksecurefunc(f, "SetAlpha", KeepFaded)
    end
    if f:GetAlpha() > 0 then f:SetAlpha(0) end
    mouseLater[f] = nil
    if not Locked(f) then
        -- (again each time: another addon, or the game, may have given a piece its mouse back)
        MouseOff(f)
        if shields[f] then shields[f]:Hide() end
    elseif mouseOff[f] then
        -- (its mouse was already off before combat: nothing to cover)
        if shields[f] then shields[f]:Hide() end
    elseif f:IsVisible() then
        -- shielded only in combat, while it's there to be clicked
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
    MouseBack(f)
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
            if not f:IsProtected() or (Keep.AddonFrame(f) and not InCombatLockdown()) then pcall(f.Hide, f) end
            if f:IsShown() then
                hiddenExtra[f] = nil
                Fade(f)
            else
                hiddenExtra[f] = true
                if Keep.AddonFrame(f) then Keep.KeepHidden(f) end
            end
        end
    end
end

local function ShowExtras()
    -- (forgotten first, so the keep-hidden hook lets them show)
    local list = {}
    for f in pairs(hiddenExtra) do list[#list + 1] = f end
    wipe(hiddenExtra)
    for _, f in ipairs(list) do Unhide(f) end
    for f in pairs(faded) do Unfade(f) end
end
ns.ShowExtras = ShowExtras

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
    -- (a lasting copy of how names normally are: kept even if this session's saved settings are lost)
    db.namesNormal = CopyTable and CopyTable(saved) or saved
end

local function ShowNames()
    if not db.namesSaved or InCombatLockdown() then return end
    for name, value in pairs(db.namesSaved) do pcall(SetCVar, name, value) end
    db.namesSaved = nil
end

-- The game closed with the map open and names hidden, without saving Overlay Map's settings (a crash,
-- Alt+F4, the game killed): the names stay off and what they were is lost with that session. At
-- login, if every name option is off but they normally aren't, they're put back as they normally
-- are (from the lasting copy) and it's said in the chat.
function Keep.NamesAfterCrash()
    if db.namesSaved or not db.namesNormal or InCombatLockdown() then return end
    local allOff, normallyOn = true, false
    for _, name in ipairs(NAME_CVARS) do
        local v = GetCVar(name)
        if v ~= nil and v ~= "0" then allOff = false end
        if db.namesNormal[name] and db.namesNormal[name] ~= "0" then normallyOn = true end
    end
    if allOff and normallyOn then
        for name, value in pairs(db.namesNormal) do pcall(SetCVar, name, value) end
        Say("Names above heads were left off (the game seems to have closed with the map open): they're back.")
    end
end

-- Put names back as they normally are (/omap names)
function Keep.NamesBack()
    if InCombatLockdown() then Say("Not in combat: try again after it.") return end
    local from = db.namesSaved or db.namesNormal
    if not from then
        for _, name in ipairs(NAME_CVARS) do pcall(SetCVar, name, GetCVarDefault and GetCVarDefault(name) or "1") end
    else
        for name, value in pairs(from) do pcall(SetCVar, name, value) end
    end
    db.namesSaved = nil
    Say("Names above heads are back as they normally are.")
end

local function ExtrasLeaveCombat()
    for f in pairs(showLater) do pcall(f.Show, f) end
    wipe(showLater)
    -- (mouse waiting for combat to end: back, unless the part is invisible again)
    for f in pairs(mouseLater) do
        if faded[f] == nil then MouseBack(f) end
    end
    -- (names waiting for combat to end: hidden if the map is open with the option, back if not)
    if ns.compact and db.hideNames then HideNames() else ShowNames() end
end

-- The minimap is hidden while the map shows, and shown again only if Overlay Map hid it. Addons
-- like SexyMap take the minimap out of its usual frame (it's then on its own, with its clock,
-- zone name and buttons on it), so both are hidden. In combat, if the minimap holds something
-- protected (SexyMap's zone button can be), it is made invisible instead.
local minimapHidden = {} -- frame -> "hide" or the alpha it had

local function MinimapFrames()
    local list = {}
    if MinimapCluster then list[#list + 1] = MinimapCluster end
    -- (not while it's lent to the map as the live minimap: Zone.LiveMinimap)
    if Minimap and Minimap:GetParent() ~= MinimapCluster and not Minimap.overlayMapLive then list[#list + 1] = Minimap end
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
ns.ShowMinimap = ShowMinimap

-- Size and shape. Other map addons (OpenMap, for one) keep the map frame at their own scale,
-- so the map frame's scale is left alone: the map area inside it is scaled instead, kept at
-- its own size (or narrower or wider, for the shape) and centred in the frame. Its original
-- anchors are put back on close.
local appliedW -- width the map area was last given, to know when the map must re-fit
local Refit
ns.SyncLayer, ns.QueueRefit, Refit, ns.ApplyLook = nil, nil, nil, nil -- (further down)
-- Outline (made at the top of the file): the Outlines style (further down)
-- Zone (made at the top of the file): the zone border (further down; declared here as the map's opacity uses it)
-- Wizard (made at the top of the file): the setup wizard (further down)

-- With a different shape, the map is zoomed so it fills the whole area (the edges that don't
-- fit are cut off), centred on you.
local function Fill()
    local map, c = Map(), Canvas()
    if not ns.compact or math.abs(WantWidth() - 1) < 0.001 or not c.InstantPanAndZoom then return end
    -- (not with OpenMap's world: it has no margins to fill, and zooming the map underneath to fill its
    -- zone made OpenMap's view jump to that zone or continent each time the map underneath changed)
    if Zone.OpenMapStitched() then return end
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
ns.Fill = Fill

local function ApplySize()
    local map, c = Map(), Canvas()
    if not before.points then
        before.points = {}
        for i = 1, c:GetNumPoints() do before.points[i] = { c:GetPoint(i) } end
        before.cw, before.ch = c:GetSize()
        before.cscale = c:GetScale()
        -- (the map area's own size, as measured as it opened: with the quest log beside it, without)
        if Zone.orig then before.cw, before.ch = Zone.orig.cw, Zone.orig.ch end
        -- Remembered for the "Move" box: the map area's size on screen at 100%.
        local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        db.areaW, db.areaH = before.cw * k, before.ch * k
        -- (the small map's own size, the same at every opening: the next ones are sized before
        -- the game lays the map out, see Zone.PreSize)
        if not Zone.orig and before.cw > 0 and before.ch > 0 then
            Zone.orig = { cw = before.cw, ch = before.ch, cscale = before.cscale }
        end
        Zone.orig.cscale = Zone.orig.cscale or before.cscale
    end
    -- Sized before the game laid the map out (Zone.PreSize): if the game then laid it out, the
    -- map is right already and only the fill for a wider or narrower shape is left; if not, the
    -- map is laid out again here as before.
    local pre = Zone.presized
    Zone.presized = nil
    if pre and Zone.openParts then Zone.openParts.pre = pre end
    c:SetScale(WantScale())
    local w = before.cw * WantWidth()
    c:SetSize(w, before.ch)
    AnchorCanvas()
    if appliedW ~= w then
        appliedW = w
        Refit()
    elseif pre == "sized" then
        -- (the game didn't lay the map out again, but it showed it already at this size, so the view
        -- is right: only its zoom steps are worked out for the size, not the whole layout with every
        -- addon's icons)
        local cv = Canvas()
        if cv.CreateZoomLevels then pcall(cv.CreateZoomLevels, cv) end
        Zone.presizeWorks = true
        Fill()
    elseif pre == "done" then
        Fill()
    end
    ns.SyncLayer()
end

function Zone.Measure(map)
    local c = Canvas()
    local w, h = c:GetSize()
    if not w or w <= 0 or not h or h <= 0 then return end
    local log = map.QuestLog
    if log and log:IsShown() and log:GetRight() and c:GetLeft() and c:GetRight() then
        local ce = c:GetEffectiveScale()
        local right = log:GetRight() * log:GetEffectiveScale() / ce
        if right > c:GetRight() + 1 then w = right - c:GetLeft() end
    end
    return { cw = w, ch = h, cscale = c:GetScale() }
end

-- Opening the map lays it out (every addon's map icons with it) for the game's own size of the
-- map area. Overlay Map's size given right after that made a second full layout, about doubling
-- the time the map takes to open. So, from the second opening on, the map area gets Overlay
-- Map's size in between: once the game has set the small map's frame, before it lays it out.
function Zone.PreSize()
    -- (with OpenMap only: that's where a layout is slow, and without it the game's zoom levels
    -- are trimmed for Overlay Map's look, which needs the map open as Overlay Map's first)
    if not Zone.presizing or not Zone.orig or not OpenMapDrives() then return end
    local c = Canvas()
    if not c then return end
    if not before.points then
        before.points = {}
        for i = 1, c:GetNumPoints() do before.points[i] = { c:GetPoint(i) } end
        before.cw, before.ch, before.cscale = Zone.orig.cw, Zone.orig.ch, Zone.orig.cscale
    end
    c:SetScale(WantScale())
    local w = before.cw * WantWidth()
    c:SetSize(w, before.ch)
    AnchorCanvas()
    appliedW = w
    Zone.presized = "sized"
end

-- Without OpenMap, the game's map can zoom out until the whole zone fits, leaving empty
-- margins on the sides or at the top and bottom when the map area isn't the zone's shape. With
-- soft edges or torn parchment those margins look broken, so while Overlay Map shows the map,
-- the furthest zoom is the one where the map fills the area. (OpenMap shows the world around the
-- zone, so it has no margins.)
local function TrimZoomLevels(c)
    if not ns.compact or OpenMapDrives() or type(c.zoomLevels) ~= "table" or not c.mapID then return end
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
    if not OpenMapDrives() and map.OnFrameSizeChanged then
        -- (the game's map works out its zoom levels again, as they were)
        pcall(map.OnFrameSizeChanged, map)
    elseif appliedW and appliedW ~= before.cw and Zone.presizeWorks and not map:IsShown() then
        -- (closed: only the zoom steps for the map's own size; it's shown at that size next time)
        if c.CreateZoomLevels then pcall(c.CreateZoomLevels, c) end
    elseif appliedW and appliedW ~= before.cw and map.OnFrameSizeChanged then
        pcall(map.OnFrameSizeChanged, map)
    end
    appliedW = nil
end

-- For a moment after opening, the game and other addons are still laying the map out; it stays
-- invisible until that is done, so the normal map doesn't flash on screen.
ns.settling = false
-- While the map fades out to be laid out again (ApplyShape), nothing else lays it out meanwhile:
-- a second layout in between left it hidden. shapeGen: the latest one (an older one's steps stop).
ns.reshaping, ns.shapeGen = false, 0
ns.mapButton, ns.panel = nil, nil -- (the options button on the map and its small panel, further down)
ns.PlaceMapButton = nil -- (further down)

-- A new width: the map works out its zoom again for the new shape. That's done once the width
-- stops changing (not on every step of a slider), with the map hidden for that moment, since
-- the map (and OpenMap) lay it out over a few frames.
ns.refitTimer = nil

local function RefitNow()
    local map = Map()
    if map.OnFrameSizeChanged then pcall(map.OnFrameSizeChanged, map) end
    Fill()
end
ns.RefitNow = RefitNow

-- While the map is still hidden (just opened), at once; otherwise once the width settles.
Refit = function()
    if ns.reshaping and not ns.settling then Zone.refitAgain = true return end -- (laid out after that one)
    if ns.settling then RefitNow() else ns.QueueRefit() end
end

ns.QueueRefit = function()
    if ns.refitTimer then ns.refitTimer:Cancel() end
    ns.refitTimer = C_Timer.NewTimer(0.25, function()
        ns.refitTimer = nil
        if not ns.compact or ns.reshaping then return end
        -- (already hidden for a layout: re-fitted now, and that one shows it again)
        if ns.settling then RefitNow() return end
        -- (a fade out and in around the new layout, keeping OpenMap's view, instead of a blink)
        if Zone.Reshape then Zone.Reshape(true) return end
        local map = Map()
        ns.settling = true
        map:SetAlpha(0)
        if ns.layer then ns.layer:SetAlpha(0) end
        if ns.viewLayer then ns.viewLayer:SetAlpha(0) end
        RefitNow()
        C_Timer.After(0.15, function()
            if not ns.compact or ns.reshaping then return end
            ns.settling = false
            ns.ApplyLook()
        end)
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
local followAcc
followAcc, ns.lastX, ns.lastY = 0, nil, nil

local function PlayerOnMap(mapID)
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then return end
    local x, y = pos:GetXY()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end -- (hidden in instances)
    if not x or not y or (x == 0 and y == 0) then return end
    return x, y
end
ns.PlayerOnMap = PlayerOnMap

-- Whether the mouse is on a marker (the game's, Questie's or OpenMap's), not just on the map.
local function OverMarker()
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local f = foci and foci[1]
    local c = Canvas()
    if not f or f == c or f == c.Child or iconLayers[f] or f == ns.layer or f == ns.viewLayer then return false end
    local up, n = f:GetParent(), 0
    while up and n < 8 do
        if up == c or up == ns.layer or up == ns.viewLayer then return true end
        up, n = up:GetParent(), n + 1
    end
    return false
end
ns.OverMarker = OverMarker

-- now: as the map opens, at once and even with the mouse over the map, so it opens where Follow Me
-- keeps it (it used to open where OpenMap reopens, and jump to Follow Me's view once the mouse left)
-- Fade while moving (db.moveFade): the map fades while you move, smoothly, and comes back as you stop,
-- like OpenMap's own "Fade while moving", with or without OpenMap. Held solid with the mouse over the map
-- (not while steering with it: the cursor's hidden then), in full-screen overlay only over a marker or with
-- Shift held. OpenMap's own fade is held off while Overlay Map shows the map (Keep.HoldOMFade): both setting
-- the map's opacity, OpenMap's won and Overlay Map's opacity did nothing.
Keep.MOVE_FADE_RATE = 6 -- the fade's approach, per second (as OpenMap's)
Keep.moveFader = CreateFrame("Frame")
Keep.moveFader:Hide()
Keep.moveFader:SetScript("OnUpdate", function(self, elapsed)
    if not ns.compact then
        Keep.moveFaded = 1
        self:Hide()
        return
    end
    -- (the game can hand these back as "secret" values, in combat on this client: comparing one is an error,
    -- so a secret answer is left out and the next way asked)
    local function Plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
    local moving = false
    local speed = GetUnitSpeed and GetUnitSpeed("player")
    if Plain(speed) then moving = speed > 0 end
    if not moving and IsPlayerMoving then
        local m = IsPlayerMoving()
        if Plain(m) then moving = m and true or false end
    end
    -- ("Not on flights": a flight isn't moving, for the fade)
    if moving and db.moveFadeFlight and UnitOnTaxi("player") then moving = false end
    -- ("Also in combat": the fade held all through a fight, standing still too)
    if not moving and db.moveFadeCombat then
        local fight = UnitAffectingCombat("player")
        if Plain(fight) and fight then moving = true end
    end
    local hold = false
    if not db.moveFadeHover then
        hold = false -- (the mouse over the map doesn't stop the fade: "Solid under the mouse" off)
    elseif db.overlay then
        hold = IsShiftKeyDown() or OverMarker()
    else
        hold = Canvas():IsMouseOver() and not (IsMouselooking and IsMouselooking())
    end
    local want = (moving and not hold) and 1 - (db.moveFade or 0) or 1
    local now = Keep.moveFaded or 1
    if math.abs(now - want) < 0.005 then
        now = want
    else
        now = now + (want - now) * math.min(1, elapsed * Keep.MOVE_FADE_RATE)
    end
    if now ~= Keep.moveFaded then
        Keep.moveFaded = now
        ns.ApplyOpacity()
    end
end)
function Keep.MoveFade()
    -- (the small panel's rows that only show with it on: shown or hidden as it goes on or off)
    local fading = (db.moveFade or 0) > 0
    if Keep.wasFading ~= nil and Keep.wasFading ~= fading and Keep.RefreshAll then Keep.RefreshAll() end
    Keep.wasFading = fading
    if ns.compact and (db.moveFade or 0) > 0 then
        Keep.moveFader:Show()
    else
        Keep.moveFader:Hide()
        if Keep.moveFaded and Keep.moveFaded ~= 1 then
            Keep.moveFaded = 1
            if ns.compact then ns.ApplyOpacity() end
        end
    end
end

-- OpenMap's "Fade while moving" off while Overlay Map shows the map, and back as it closes (its setting
-- kept in Overlay Map's saved settings meanwhile, so a crash or a reload with the map open doesn't lose it)
function Keep.OMFadeDB()
    local om = Zone.OpenMapModule()
    return om and type(om.db) == "table" and om.db, om
end
function Keep.HoldOMFade()
    local odb, om = Keep.OMFadeDB()
    if not odb or (odb.moveFade or 0) <= 0 then return end
    db.omMoveFade = odb.moveFade
    odb.moveFade = 0
    if om.RefreshExtras then pcall(om.RefreshExtras) end
end
function Keep.GiveOMFade()
    if db.omMoveFade == nil then return end
    local odb, om = Keep.OMFadeDB()
    if not odb then return end
    if (odb.moveFade or 0) == 0 then odb.moveFade = db.omMoveFade end -- (unless changed in OpenMap meanwhile)
    db.omMoveFade = nil
    if om.RefreshExtras then pcall(om.RefreshExtras) end
end

local edgeSweeps = 0
local Watch -- (below)
ns.ApplyClickThrough, ns.ApplyOnlyMe, ns.ApplyMarkerSize, ns.ApplyArrow = nil, nil, nil, nil -- (further down)
watcher:SetScript("OnUpdate", function(self, elapsed)
    if not ns.compact then self:Hide(); return end
    if Zone.openParts and GetTime() - Zone.openParts.start < 1.5 and elapsed > (Zone.worstFrame or 0) then
        Zone.worstFrame = elapsed
    end
    if db.follow and not ns.settling then
        followAcc = followAcc + elapsed
        if followAcc >= 0.1 then
            followAcc = 0
            ns.Follow(ns.lastX == nil)
        end
    else
        ns.lastX, ns.lastY = nil, nil -- (turned on again: centred at once, even standing still)
    end
    watchAcc = watchAcc + elapsed
    if watchAcc < 0.2 then return end
    watchAcc = 0
    local t0 = debugprofilestop()
    Watch()
    local cost = Zone.watchCost
    if GetTime() - cost.since > 10 then cost.n, cost.ms, cost.since = 0, 0, GetTime() end
    cost.n, cost.ms = cost.n + 1, cost.ms + debugprofilestop() - t0
end)

-- Five times a second while the map is open. What's only a safety net (something put back by the
-- game or another addon) is done once a second; new markers get theirs from the lists kept of each
-- frame's children (Zone.Children), so going through OpenMap's icons costs little.
Zone.watchCost = { n = 0, ms = 0, since = 0 }
local slowAcc = 0
Watch = function()
    slowAcc = slowAcc + 1
    local slow = slowAcc >= 5
    if slow then slowAcc = 0 end
    for obj in pairs(hidden) do
        if obj:GetAlpha() > 0 then obj:SetAlpha(0) end
    end
    if not ns.settling then Zone.CheckFit() end
    if Zone.live then Zone.LiveMinimap() end -- (kept over the map area; cheap when nothing moved)
    if not ns.reshaping and not Keep.sizing and math.abs(Canvas():GetScale() - WantScale()) > 0.001 then ApplySize() end -- (also a new screen size)
    -- (a fade left half-way, which nothing is finishing: the map shown again)
    -- (the map fades in once its edges are laid, or after a second whatever happens)
    if not ns.reshaping and not ns.settling and ns.transition < 1 and not ns.fader:IsShown()
        and (not Zone.walking or GetTime() - (Zone.walkStart or 0) > 1) then ns.FadeTo(1, 0.2) end
    -- (the markers' click through, Show only my arrow and size: each kept by hooks the moment the game or an
    -- addon changes them; gone through again for new markers, and once a second)
    local fresh = Keep.markersDirty
    ns.ApplyOpacity()
    if slow or fresh then
        Keep.markersDirty = false
        if db.clickThrough then ns.ApplyClickThrough() end
        ns.ApplyOnlyMe()
        ns.ApplyMarkerSize()
    end
    if not slow then return end
    if not ns.settling then
        -- (caves and dungeons, once a second; whether you're in a cave, for the zone border)
        local before = Zone.caveKey
        local cave = Zone.CaveHere() ~= nil
        if cave ~= (Zone.inCave or false) or Zone.caveKey ~= before then
            Zone.inCave = cave
            if db.zoneBorder then ns.ApplyEdges() end
        end
        if db.style == "outlines" then Outline.Place() end -- (into or out of a cave: its lines)
        Keep.CaveWheel()
        if not Zone.shelved then Keep.CheckPlace() end
        Zone.CheckPlaces()
        if Zone.live or db.liveMinimap then Zone.LiveMinimap() end -- (entered or left a dungeon with the map open)
        -- (OpenMap's dungeon map, opened a moment after the map)
        Zone.WatchDungeonView()
        local dv = Zone.DungeonViewShown()
        if dv then
            Zone.TidyDungeonView()
            Zone.Unframe()
        end
        if dv ~= (Zone.dvShown or false) then
            Zone.dvShown = dv
            if not dv then Zone.Reframe(Zone.InDungeon()) end -- (the dungeon map gone: the world back under, outside dungeons)
            ns.ApplyOpacity()
            ns.QueueEdges()
        end
    end
    CoverScreen() -- (in case the game's window layout moved it back)
    if not Zone.shelved then -- (closed in combat: the interface is back meanwhile)
        HideExtras()
        if db.hideMinimap then HideMinimap() end
    end
    ns.ApplyArrow()
    if ns.mapButton and ns.mapButton:IsShown() then ns.PlaceMapButton() end -- (the map grew past the screen)
    -- (once a second, for anything the events missed; every five, the lists of children read again,
    -- for any swapped one for one)
    edgeSweeps = edgeSweeps + 1
    if edgeSweeps % 5 == 0 then Zone.ForgetWalked() end
    ns.ApplyEdges()
end

ns.UpdateMapButton = nil -- (the options button on the map, further down)

ns.ApplyLook = function()
    Keep.pinsDirty, Keep.markersDirty = true, true -- (all the markers gone through again)
    Zone.CheckDownload() -- (Zone Border chosen without its download ready: asked, or told, at once)
    Outline.CheckDownload() -- (the same for the Outlines style)
    Zone.CaveMouthPins() -- (on while Overlay Map shows the map, off when it closes)
    if not ns.compact then return end
    local map = Map()
    Keep.MoveFade()
    ns.ApplyMarkerSize()
    ApplySize()
    Zone.LiveMinimap()
    ns.ApplyOpacity()
    if PlayerMovementFrameFader and PlayerMovementFrameFader.RemoveFrame then
        PlayerMovementFrameFader.RemoveFrame(map)
    end
    Place()
    if Zone.shelved then
        ShowMinimap()
        ShowExtras()
    else
        if db.hideMinimap then HideMinimap() else ShowMinimap() end
        HideExtras()
    end
    if db.hideNames then HideNames() else ShowNames() end
    ns.ApplyEdges()
    ns.ApplyClickThrough()
    ns.ApplyOnlyMe()
    ns.ApplyArrow()
    ns.UpdateMapButton()
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

-- The game's map states: Overlay Map opened state 2 and turned it small through "miniWorldMap", but 2
-- is the full screen map in the game's Classic clients, so the game laid the map out five times as it
-- opened (small, then full screen again), every addon's map icons each time. It's now opened with the
-- game's own minimize action (as the map's minimize button), which opens it small at once. If that
-- ever leaves it full screen, state 2 and "miniWorldMap" are used from then on, as before.
local DISPLAY_MINIMIZED_NO_LOG = 2

local function Blocked()
    if InCombatLockdown() and Map():IsProtected() then
        Say("The map can't be opened by an addon in combat right now"
            .. (db.combatReady and "." or " (\"Ready in combat\" in the options lets your key open it in fights)."))
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
    -- (not inside a dungeon: the map there is the game's world map behind the dungeon's own, and its zoom,
    -- saved over OpenMap's, left the map all the way out once you were back outside)
    if Zone.InDungeon() then return end
    local api = OpenMapLoaded() and _G.OpenMapAPI
    if api and api.IsStitched and api.IsStitched() and api.GetView then
        local ok, _, _, zoom = pcall(api.GetView)
        if ok and type(zoom) == "number" then db.zoom = { openmap = zoom, fit = Zone.FitPx() } end
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
        if not z.openmap or InCombatLockdown() then return end -- (in combat OpenMap doesn't move its map)
        local ok, u, v = pcall(api.GetView)
        if not ok or not u then return end
        -- (the land at the size it had on screen, even if the map's width changed since)
        local zoom, fit = z.openmap, Zone.FitPx()
        if z.fit and fit then zoom = zoom * z.fit / fit end
        -- At once if OpenMap allows it, otherwise a short glide.
        local om = _G.OpenMap and _G.OpenMap.GetModule and select(2, pcall(_G.OpenMap.GetModule, _G.OpenMap, "worldmap"))
        if type(om) == "table" and om.ShowNow and pcall(om.ShowNow, u, v, zoom) then return end
        if api.ShowWorld then pcall(api.ShowWorld, u, v, zoom) end
        return
    end
    local c = Canvas()
    if z.scale and z.mapID == Map():GetMapID() and c.InstantPanAndZoom then
        pcall(c.InstantPanAndZoom, c, z.scale, z.x, z.y, true)
    end
end

local function Restore()
    if not ns.compact then return end
    Keep.GiveOMFade()
    Keep.moveFader:Hide()
    Keep.moveFaded = 1
    Zone.Unshelve(false)
    Zone.Reframe() -- (the dungeon map's frame, as it was)
    Zone.MinimapBack() -- (the minimap back in its corner, if it was lent to the map)
    ns.StopFade()
    SaveZoom()
    ns.compact = false
    Keep.EscapeOn(false)
    Keep.CaveWheel()
    Keep.combatMismatch, Zone.omAllOut, Zone.fightZone = false, nil, nil
    Zone.FightArrow(false)
    Zone.CaveMouthPins()
    Zone.Reset(true) -- (the outlines' pictures stay loaded for next time)
    Zone.lastZoom, Zone.zoomedAt = nil, nil -- (your own zoom counts only while the map is open)
    local map = Map()
    RevealAll()
    ShowMinimap()
    ShowExtras()
    ShowNames()
    Zone.Rest() -- (the masks stay on, cutting nothing: see Zone.Rest)
    ns.ApplyClickThrough() -- (compact is off: everything takes the mouse again)
    ns.ShowMarkers()
    RestoreSize()
    ns.RestoreOpacity()
    ns.ApplyMarkerSize() -- (compact is off: markers back to their size)
    ns.ApplyArrow()      -- (... and your arrow)
    wipe(iconLayers)
    -- (the addons kept off it back on the map, its size back first: OpenMap lays its world over it again)
    ns.Addons.Release()
    ns.settling = false
    map:SetAlpha(before.alpha or 1)
    if before.mouse then map:EnableMouse(true) end
    ns.UpdateMapButton()
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
    -- (closed in combat, so only made invisible: shown again)
    if map and ns.compact and Zone.shelved then Zone.Unshelve(true) return end
    if not map or ns.compact then return end
    -- (the map area's mouse as the click through puts it back on close, Save: the game's map always takes the mouse
    -- and its wheel. Noted from the map instead, a moment the map was kept unseen for a fight noted it off, and the
    -- map couldn't be moved any more, till a reload; this also mends one left so)
    Keep.canvasMouse = { true, true, true }
    Zone.opening = GetTime()
    local t0 = debugprofilestop()
    if map:IsShown() then return end -- already open the normal way: leave it alone
    if Blocked() then return end
    -- (the addons turned off in the Addons tab kept off the map, before it opens: Addons.lua)
    ns.Addons.Hold()
    Keep.HoldOMFade()

    -- Open it small and without the quest log. The game decides small or full screen from
    -- "miniWorldMap" as it opens, so that setting is set for this one opening and put back
    -- right after; nothing else reads it.
    local mini = GetCVar("miniWorldMap")
    if mini ~= "1" then pcall(SetCVar, "miniWorldMap", "1") end
    -- (for /omap debug: where an opening's time goes, and the slowest frame just after it)
    local P = { start = GetTime() }
    Zone.openParts, Zone.worstFrame = P, 0
    Zone.WatchDungeonView()
    Zone.dvLog = {}
    Zone.holdFor = nil
    if OpenMapLoaded() and Zone.InDungeon() and not (_G.ForeverDungeonJournal_NS and _G.ForeverDungeonJournal_NS.CurrentDungeon
        and _G.ForeverDungeonJournal_NS.CurrentDungeon()) then
        Zone.holdFor = GetTime() + 0.4
    end
    local tm = debugprofilestop()
    Zone.presizing, Zone.presized = true, nil
    Zone.anchoring = true
    Zone.PreSize() -- (before the game shows it; again if the game sets up the small map's frame)
    Zone.anchoring = false
    -- (the game's own "make the map small" action: it opens the small map with whatever number the
    -- game gives that state, as the map's minimize button does)
    local small = not Zone.smallFails and map.HandleUserActionMinimizeSelf
    local ok
    Keep.directShown = false
    if InCombatLockdown() then
        -- (in combat the game's window system, which its own map key uses, refuses addons, without a word,
        -- even with the map not protected: the map shown directly instead, outside that system; Overlay Map
        -- places it itself anyway. Closed the same way, Close)
        ok = pcall(map.Show, map)
        Keep.directShown = ok and map:IsShown()
        -- (OpenMap leaves the game's map as it is in a fight: its picture at its last view, the markers and the
        -- border at the game's, the whole zone. Till the fight ends: no border, markers hidden if chosen)
        Keep.combatMismatch = Keep.directShown and OpenMapLoaded() or false
        Keep.markersDirty = true -- (the game's markers hidden on the next upkeep: ApplyOnlyMe)
        P.why = "shown directly (in combat)"
        small = nil
    elseif small then
        ok = pcall(small, map)
        if ok and map:IsShown() then
            local big = map.IsMaximized and map:IsMaximized()
            local log = map.QuestLog and map.QuestLog:IsShown()
            P.why = (big and "full screen" or "small") .. (log and ", quest log shown" or ", no quest log")
            -- (the quest log beside the small map is hidden with the rest of the window anyway)
            if big then
                Zone.smallFails = true -- (as before, from now on)
                ok = pcall(map.SetDisplayState, map, DISPLAY_MINIMIZED_NO_LOG)
            end
        end
    else
        ok = pcall(map.SetDisplayState, map, DISPLAY_MINIMIZED_NO_LOG)
    end
    P.state = (small and not Zone.smallFails) and "small" or "2"
    Zone.presizing, Zone.anchoring = false, false
    P.game = debugprofilestop() - tm
    P.pre = Zone.presized
    if mini ~= "1" then pcall(SetCVar, "miniWorldMap", mini) end
    if not ok or not map:IsShown() then
        if Zone.presized then RestoreSize() wipe(before) Zone.presized = nil end -- (sized for nothing)
        ns.Addons.Release()
        return
    end

    -- (the first time: the map area's size without the quest log the small map shows beside it, so
    -- Size and Width mean the same as before; the log is hidden while Overlay Map shows the map)
    if not Zone.orig then Zone.orig = Zone.Measure(map) end

    ns.compact = true
    Keep.EscapeOn(true)
    before.alpha = map:GetAlpha()
    -- The map frame stays its full size around the smaller map area; it must not take clicks.
    before.mouse = map:IsMouseEnabled()
    if before.mouse then map:EnableMouse(false) end
    ns.settling = true
    tm = debugprofilestop()
    ConcealAll()
    -- (a dungeon's map, put up by Dungeon Journal as the map showed: its dark frame cleared at once, not
    -- seen for a moment as the map fades in)
    Zone.Unframe()
    P.hide = debugprofilestop() - tm
    -- (Overlay Map's look laid on the next frame, not the one the game spent opening its map, so the
    -- two don't add up into one long stop; the map is kept invisible until then)
    map:SetAlpha(0)
    C_Timer.After(0, function()
        if not ns.compact then return end
        local tl = debugprofilestop()
        ns.ApplyLook()
        P.look = debugprofilestop() - tl
    end)
    watchAcc = 0
    ns.lastX, ns.lastY = nil, nil
    watcher:Show()
    Zone.openMs = debugprofilestop() - t0
    -- The game's window layout and other map addons may still change things during the next
    -- frames: hide and apply everything once more, then show the map.
    C_Timer.After(0.05, function()
        if not ns.compact then return end
        local t1 = debugprofilestop()
        local P2 = Zone.openParts or {}
        local tm2 = debugprofilestop()
        ConcealAll()
        for obj in pairs(hidden) do
            if obj:GetAlpha() > 0 then obj:SetAlpha(0) end
        end
        P2.hide2 = debugprofilestop() - tm2
        tm2 = debugprofilestop()
        -- (Dungeon Journal laid its dungeon's map out as the map showed, at the map area's size then: the
        -- first time, before Overlay Map's size, so it came out small and zoomed out. Laid out again now)
        -- (only when the map area wasn't at Overlay Map's size yet as the map showed: the first opening after
        -- a reload; laying it out again costs a moment every time)
        local fdj = _G.ForeverDungeonJournal_NS
        if P2.pre ~= "sized" and fdj and fdj.IsWorldMapOverlayAttached and fdj.IsWorldMapOverlayAttached()
            and fdj.RefreshWorldMapOverlay then
            pcall(fdj.RefreshWorldMapOverlay)
            Zone.Unframe()
        end
        -- (already done as the fight started, Ready in combat: not asked again in the fight, which would only wait for
        -- its end)
        if not (InCombatLockdown() and Keep.readyViewAt and GetTime() - Keep.readyViewAt < 2) then Keep.OpeningView() end
        P2.zoom = debugprofilestop() - tm2
        ns.settling = false
        tm2 = debugprofilestop()
        ns.ApplyLook()
        P2.look2 = debugprofilestop() - tm2
        Zone.openMs2 = debugprofilestop() - t1
        -- The map and other addons finish setting up their frames' mouse while it opens; the
        -- click-through is laid again from scratch on top of that.
        C_Timer.After(0.1, function()
            local tm3 = debugprofilestop()
            if ns.compact then ns.ApplyClickThrough(true) end
            C_Timer.After(0.5, Zone.FreshLook)
            C_Timer.After(2, Zone.FreshLook)
            -- (OpenMap's dungeon map, opened by now inside a dungeon: tidied and its markers off)
            Zone.holdFor = nil -- (its dungeon map tidied by now, if it's up: the map can fade in)
            if ns.compact and Zone.DungeonViewShown() then
                Zone.TidyDungeonView()
                Zone.Unframe()
                Zone.dvShown = true
                ns.ApplyOpacity()
                ns.QueueEdges()
            end
            P2.click = debugprofilestop() - tm3
        end)
    end)
end
ns.Open = Open

local function Close()
    if not ns.compact then return end
    Keep.EscapeOn(false)
    local map = Map()
    if InCombatLockdown() and map:IsProtected() then Zone.Shelve() return end
    -- (Ready in combat with OpenMap: kept, unseen, till the fight ends, so opening it again in the fight shows it set up)
    if InCombatLockdown() and db.combatReady and OpenMapDrives() and not Keep.combatMismatch then Zone.Shelve() return end
    -- (shown directly in combat: hidden directly too, the window system never having had it)
    if Keep.directShown or InCombatLockdown() then
        pcall(map.Hide, map)
    end
    if map:IsShown() then
        if HideUIPanel then pcall(HideUIPanel, map) else map:Hide() end
    end
    Keep.directShown, Keep.combatMismatch = false, false
    if map:IsShown() and InCombatLockdown() then Zone.Shelve() return end -- (refused without a word)
    Zone.Unshelve(false)
    Restore() -- in case hiding did not reach the OnHide hook
end
ns.Close = Close
Keep.Close = Close

-- Escape: the game's window system closes the map with it, but not one shown in a fight (shown directly, outside
-- that system) nor one kept for the fight (Ready in combat). A small frame of Overlay Map's on Escape's list
-- while the map shows: Escape hides it, and that closes the map (in a fight: kept unseen, as the key does).
function Keep.EscapeOn(on)
    local e = Keep.escape
    if not e then
        if not on then return end
        e = CreateFrame("Frame", "OverlayMapEscape", UIParent)
        e:SetSize(1, 1)
        e:Hide()
        tinsert(UISpecialFrames, "OverlayMapEscape")
        e:SetScript("OnHide", function()
            if Keep.escQuiet then return end
            if ns.compact and not Zone.shelved and Keep.Close then Keep.Close() end
        end)
        Keep.escape = e
    end
    Keep.escQuiet = true
    e:SetShown(on and true or false)
    Keep.escQuiet = false
end

-- The view as the map opens: your zoom kept, your zone or cave fitted, centred on you. A moment after the map shows,
-- and with Ready in combat at once too, as the fight starts: a moment later the fight has begun, and OpenMap doesn't
-- move its map in one, so the map stayed where OpenMap had left it
function Keep.OpeningView()
    Zone.inCave = Zone.CaveHere() ~= nil -- (in a cave: no zone outline, see Zone.MaskZone)
    -- (inside a dungeon: Dungeon Journal's map, even if it was left on the world map last time)
    if Zone.InDungeon() then
        Zone.HookJournal()
        Zone.JournalBack()
    end
    RestoreZoom()
    if db.zoneBorder and db.fitOpen and Zone.PlayerZone() then
        Zone.fittedFor = Zone.PlayerZone()
        Zone.Fit(Zone.fittedFor, true) -- (every time: fitted to your zone)
    else
        Zone.CheckFit(true) -- (a new zone since it last closed: fitted to it instead)
    end
    -- (in a cave or a dungeon: fitted to it, over the zone; in a cave, every time the map opens, whatever zoom
    -- you left it at)
    Zone.CheckPlaces(true, (db.zoneBorder and db.fitOpen) or Zone.inCave)
    -- (Follow Me: the view where it keeps it, from the start)
    if db.follow then
        ns.lastX, ns.lastY = nil, nil
        ns.Follow(true, true)
    end
end

function OverlayMap_OnKey(keystate)
    if not db or not Map() then return end
    -- (the setup wizard keeps the map open behind it: the key only shows it at full strength, held
    -- or pressed as chosen, instead of opening and closing it)
    if Wizard.frame and Wizard.frame:IsShown() and ns.compact then
        if db.mode == "press" then
            if keystate == "down" then Wizard.full = not Wizard.full end
        else
            Wizard.full = keystate == "down"
        end
        return
    end
    if db.mode == "hold" then
        if keystate == "down" then Open() else Close() end
    elseif keystate == "down" then
        -- (kept unseen for a fight, Ready in combat or closed in one: the key shows it, not closes it again)
        if ns.compact and not Zone.shelved then Close() else Open() end
    end
end

local function HookMap()
    local map = Map()
    if not map or map.OverlayMapHooked then return end
    map.OverlayMapHooked = true
    -- Closed by Esc, by another window, or anything else: put everything back.
    map:HookScript("OnHide", Restore)
    -- (for /omap debug: the map's own shows and hides around an opening)
    local function NoteMap(what)
        local P, t = Zone.openParts, Zone.dvLog
        if t and #t < 12 then t[#t + 1] = string.format("map %s +%.2f", what, P and (GetTime() - P.start) or -1) end
    end
    map:HookScript("OnShow", function() NoteMap("shown") end)
    map:HookScript("OnHide", function() NoteMap("hidden") end)
    -- Opened the normal way (M, L, a quest link) while Overlay Map shows it: the game takes over.
    for _, method in ipairs({ "HandleUserActionToggleSelf", "HandleUserActionToggleQuestLog",
                              "HandleUserActionOpenSelf", "HandleUserActionOpenQuestLog" }) do
        if map[method] then hooksecurefunc(map, method, Restore) end
    end
    -- The map's picture resized (another map under OpenMap's view): the outline laid again at once
    -- (the mouse wheel on the game's map: your own zoom, kept against Fit Zone)
    if map.ScrollContainer then
        map.ScrollContainer:HookScript("OnMouseWheel", function()
            if ns.compact then Zone.zoomedAt = GetTime() end
        end)
    end
    -- (No hooks on the map's own display steps (SynchronizeDisplayState, Minimize...): Veilmap's
    -- author found that wrapping SynchronizeDisplayState alone, even with an empty hook, breaks the
    -- game's minimize step the first time the map opens in combat on WoW: Forever.)
    -- (the game anchors the map area to its window as it sets up the small map, just before it lays
    -- it out: while Overlay Map opens it, Overlay Map's size and place are put back at once, so the
    -- game lays it out at that size, once, instead of at its own and then again at Overlay Map's)
    if map.ScrollContainer then
        hooksecurefunc(map.ScrollContainer, "SetPoint", function()
            if not Zone.presizing or Zone.anchoring then return end
            Zone.anchoring = true
            Zone.PreSize()
            Zone.anchoring = false
        end)
    end
    local child = map.ScrollContainer and map.ScrollContainer.Child
    if child then
        child:HookScript("OnSizeChanged", function()
            if ns.compact and Zone.shown then Zone.PlaceZoneAnchor(Zone.shown) end
            if ns.compact and db.style == "outlines" then Outline.Place() end
        end)
    end
    -- Zooming the map: the markers' layer zooms with it right away.
    if map.OnCanvasScaleChanged then
        if map.ScrollContainer and map.ScrollContainer.CreateZoomLevels then
            hooksecurefunc(map.ScrollContainer, "CreateZoomLevels", TrimZoomLevels)
        end
        hooksecurefunc(map, "OnCanvasScaleChanged", function()
            if ns.compact and ns.layer and ns.layer:IsShown() then ns.SyncLayer() end
            if ns.compact then ns.QueueEdges() end -- (map tiles load as you zoom)
        end)
    end
    -- New markers: move them onto the layer on the next frame instead of waiting.
    if map.AcquirePin then
        local pending = false
        hooksecurefunc(map, "AcquirePin", function()
            if ns.compact then
                ns.QueueEdges()
                Keep.pinsDirty, Keep.markersDirty = true, true -- (a new marker: gone through at the next upkeep)
            end
            if not ns.compact or pending or not (ns.layer and ns.layer:IsShown()) then return end
            pending = true
            C_Timer.After(0, function()
                pending = false
                Keep.pinsDirty, Keep.markersDirty = true, true
                if ns.compact then ns.ApplyOpacity() end
            end)
        end)
    end
    -- Another zone shown while Overlay Map shows the map: fill the shape again.
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function()
            if ns.compact then
                C_Timer.After(0, Fill)
                -- (a zone border follows the map shown: at once, as OpenMap changes the map under
                -- its view while it moves, or the outline is a frame behind, out of place)
                if db.zoneBorder then ns.ApplyEdges() end
                if db.style == "outlines" then Outline.Place() end
                ns.QueueEdges()
            end
        end)
    end
    -- Other windows opening move the map back to its usual spot; keep it where it was put.
    if UpdateUIPanelPositions then
        hooksecurefunc("UpdateUIPanelPositions", function()
            if ns.compact then Place() end
        end)
    end
end

--------------------------------------------------------------------------------
-- Moving it: a box the size of the map that can be dragged
--------------------------------------------------------------------------------

ns.mover = nil

local function ShowMover()
    if db.overlay then
        Say("In full-screen overlay the map fills the whole screen: turn it off to move the map.")
        return
    end
    if not ns.mover then
        ns.mover = CreateFrame("Frame", "OverlayMapMover", UIParent, "BackdropTemplate")
        ns.mover:SetFrameStrata("FULLSCREEN")
        ns.mover:SetMovable(true)
        ns.mover:EnableMouse(true)
        ns.mover:RegisterForDrag("LeftButton")
        ns.mover:SetClampedToScreen(true)
        ns.mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        ns.mover:SetBackdropColor(0.1, 0.4, 0.8, 0.35)
        ns.mover:SetBackdropBorderColor(0.4, 0.75, 1, 1)
        local text = ns.mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("CENTER")
        text:SetText("Overlay Map\nDrag to move. Right-click when done.")
        -- The box's centre is the map's: saved, and the open map follows it as it's dragged.
        local function Save(self)
            local x, y = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            local k = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            db.x, db.y = x * k - ux, y * k - uy
            if ns.compact then
                Place()
                ns.SyncLayer()
                ns.UpdateMapButton()
            end
        end
        ns.mover:SetScript("OnDragStart", function(self)
            self:StartMoving()
            self:SetScript("OnUpdate", Save)
        end)
        ns.mover:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self:StopMovingOrSizing()
            self:SetUserPlaced(false)
            Save(self)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        end)
        ns.mover:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then self:Hide() end
        end)
    end
    -- The map area's size, as measured the last time Overlay Map opened it.
    ns.mover:SetSize((db.areaW or 702) * db.scale * db.width, (db.areaH or 467) * db.scale)
    ns.mover:ClearAllPoints()
    ns.mover:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    ns.mover:Show()
end
ns.ShowMover = ShowMover

SLASH_OVERLAYMAP1 = "/overlaymap"
SLASH_OVERLAYMAP2 = "/omap"
SlashCmdList.OVERLAYMAP = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" then
        OverlayMap_Debug()
    elseif msg == "report" or msg == "bug" then
        Keep.BugReport()
    elseif msg == "github" then
        Keep.BugReport(true)
    elseif msg == "move" then
        ShowMover()
    elseif msg == "names" then
        Keep.NamesBack()
    elseif msg == "setup" then
        Wizard.Open()
    elseif msg == "reset" then
        db.x, db.y = 0, 0
        ns.ApplyLook()
        Say("Map back in the middle of the screen.")
    else
        ns.OpenOptions()
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
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_REGEN_DISABLED" then
        Keep.ReadyForCombat()
        Keep.markersDirty = true -- (the map open as the fight starts: OpenMap's quest icons, Keep.FightQuests)
        ExtrasEnterCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ExtrasLeaveCombat()
        if Zone.shelved then Close() end -- (closed during combat: now for real)
        C_Timer.After(0.1, Zone.AfterCombat) -- (a fit asked for in the fight: now, after OpenMap's own catch-up)
        if Wizard.afterCombat then
            Wizard.afterCombat = nil
            Wizard.Open()
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if ns.compact and db.clickThrough then ns.ApplyClickThrough() end
        if ns.compact then Keep.CaveWheel() end
        if Zone.live then Zone.LiveMinimap() end
    elseif event == "ADDON_LOADED" and name == ADDON_NAME then
        -- Settings from when the addon was called Quick Map (its saved file renamed to OverlayMap.lua
        -- in the WTF folder), taken over once.
        if OverlayMapDB == nil and type(QuickMapDB) == "table" then OverlayMapDB = QuickMapDB end
        QuickMapDB = nil
        -- (nothing saved yet: a new install, which gets the setup wizard)
        Wizard.fresh = OverlayMapDB == nil or next(OverlayMapDB) == nil
        OverlayMapDB = OverlayMapDB or {}
        db = OverlayMapDB
        ns.SetDB(db) -- (every file's db)
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        if db.mode ~= "hold" and db.mode ~= "press" then db.mode = "hold" end
        if type(db.edge) ~= "number" or db.edge < 0 or db.edge > 4 then db.edge = DEFAULTS.edge end
        if db.shape == "torn" then db.shape, db.style = DEFAULTS.shape, "torn" end -- (it was a shape before)
        -- (the zone border was a shape before: now its own option, on top of the shape)
        for _, t in ipairs({ db, db.beforeOverlay or false, db.overlaySet or false }) do
            if t and t.shape == "zone" then
                t.shape, t.zoneBorder, t.zoneSoft = "rect", true, (t.edge or 0) > 0
            end
        end
        -- (the two fit options became one choice, now a list of when: entering, opening, leaving a town or city)
        if db.zoneFitMode == nil and (db.zoneFitOpen ~= nil or db.zoneFit ~= nil) then
            db.zoneFitMode = db.zoneFitOpen and "open" or (db.zoneFit == false and "off") or "enter"
        end
        if db.zoneFitMode ~= nil then
            local mode = db.zoneFitMode
            db.fitEnter = mode ~= "off"
            db.fitOpen = mode == "open"
            db.fitLeave = mode ~= "off" -- (leaving a town fitted the zone with any of the old choices)
            db.zoneFitMode = nil
        end
        db.zoneFit, db.zoneFitOpen = nil, nil
        if db.zoneViewOff == nil then db.zoneView, db.zoneViewOff = false, true end -- (a test version had it on)
        if not ns.SHAPE_FILES[db.shape] then db.shape = DEFAULTS.shape end
        -- ("Don't fade while moving" is now "Fade while moving", by how much: off was half)
        for _, t in ipairs({ db, db.beforeOverlay or false, db.overlaySet or false }) do
            if t and t.noFade ~= nil then
                if t.moveFade == nil or t == db then t.moveFade = t.noFade == false and 0.5 or 0 end
                t.noFade = nil
            end
        end
        if type(db.moveFade) ~= "number" then db.moveFade = 0 end
        if db.zoneOutside == "hide" then db.zoneDim = 0 end -- (an earlier test's setting)
        db.zoneOutside = nil
        if type(db.zoneDim) ~= "number" then db.zoneDim = DEFAULTS.zoneDim end
        if db.style ~= "standard" and db.style ~= "torn" and db.style ~= "outlines" then db.style = DEFAULTS.style end
        local corners = { TOPRIGHT = true, TOPLEFT = true, BOTTOMRIGHT = true, BOTTOMLEFT = true }
        if not corners[db.buttonCorner] then db.buttonCorner = DEFAULTS.buttonCorner end
        if db.buttonMode ~= "show" and db.buttonMode ~= "hover" and db.buttonMode ~= "hide" then
            db.buttonMode = "hover"
        end
        ns.BuildOptions()
    elseif event == "PLAYER_LOGOUT" then
        Keep.GiveOMFade() -- (OpenMap's fade back before it saves)
        -- (logging out or quitting with the map open: names back before the game saves its options)
        if db and db.namesSaved then
            for n, v in pairs(db.namesSaved) do pcall(SetCVar, n, v) end
            db.namesSaved = nil
        end
    elseif event == "PLAYER_LOGIN" then
        HookMap()
        ShowNames() -- (names left hidden if the game closed with the map open)
        Keep.NamesAfterCrash()
        Keep.GiveOMFade() -- (OpenMap's fade, if the game closed with the map open)
        -- OpenMap's view moved: the zone border follows at once (not only once a second)
        local api = _G.OpenMapAPI
        if api and api.RegisterCallback then
            pcall(api.RegisterCallback, Zone, "OpenMap_ViewChanged", function()
                if ns.compact and api.GetView then
                    local okV, _, _, z = pcall(api.GetView)
                    if okV then Zone.NoteZoom(z) end
                end
                Zone.ViewMoved()
            end)
        end
        Wizard.AtLogin()
        if db.setupDone and not GetBindingKey("OVERLAYMAP_SHOW") then
            Say("No map key yet: choose one with |cffffd100/omap setup|r, or in Options > Keybindings > Overlay Map.")
        end
    end
end)
