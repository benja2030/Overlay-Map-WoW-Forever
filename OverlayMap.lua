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
    zoneBorder = false, -- the map cut to your zone's outline (on top of the shape and style)
    zoneSoft = true, -- the zone's outline faded in from the border (off: cut sharp)
    zoneDim = 0.3,   -- with the zone border: how much of the rest of the map shows (0: hidden; 5% steps)
    zoneFitMode = "enter", -- with the zone border, the map zoomed to fit your zone: "off", "enter" (each
                           -- new zone you enter) or "open" (that, and every time the map opens)
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
    local ue, ce = UIParent:GetEffectiveScale(), c:GetEffectiveScale()
    local x, y = db.x, db.y
    if db.overlay then x, y = 0, 0 end
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

local Keep = {}
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
local mouseLater = {}   -- frame -> true: mouse to give back when combat ends

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

-- Size and shape. Other map addons (OpenMap, for one) keep the map frame at their own scale,
-- so the map frame's scale is left alone: the map area inside it is scaled instead, kept at
-- its own size (or narrower or wider, for the shape) and centred in the frame. Its original
-- anchors are put back on close.
local appliedW -- width the map area was last given, to know when the map must re-fit
local SyncLayer, QueueRefit, Refit, ApplyLook -- (further down)
local Outline = {} -- the Outlines style (further down)
local Zone = {} -- the zone border (further down; declared here as the map's opacity uses it)
local Wizard = {} -- the setup wizard (further down)

-- With a different shape, the map is zoomed so it fills the whole area (the edges that don't
-- fit are cut off), centred on you.
local function Fill()
    local map, c = Map(), Canvas()
    if not compact or math.abs(WantWidth() - 1) < 0.001 or not c.InstantPanAndZoom then return end
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
    SyncLayer()
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
    if not Zone.presizing or not Zone.orig or not OpenMapLoaded() then return end
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
    elseif appliedW and appliedW ~= before.cw and Zone.presizeWorks and not map:IsShown() then
        -- (closed: only the zoom steps for the map's own size; it's shown at that size next time)
        if c.CreateZoomLevels then pcall(c.CreateZoomLevels, c) end
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
-- (above: how many levels over the map frame. Both layers cut their contents off at the map area's
-- edges, and the game draws a frame that does that as one block, at its own level: the markers'
-- layer must be over the icons' layer, or which one came out on top changed from one opening to
-- the next. As on OpenMap's own map, the markers go over its icons.)
local function Sync(f, scale, above)
    local map, c = Map(), Canvas()
    if math.abs(f:GetScale() - scale) > 0.0001 then f:SetScale(scale) end
    if f.syncedTo ~= c then
        f:ClearAllPoints()
        f:SetAllPoints(c)
        f.syncedTo = c
    end
    local strata = Above(map:GetFrameStrata())
    if f:GetFrameStrata() ~= strata then f:SetFrameStrata(strata) end
    local level = map:GetFrameLevel() + above
    if f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
end

SyncLayer = function()
    if Outline.layer and Outline.layer:IsShown() then
        Sync(Outline.layer, Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale(), 0)
        Outline.Place()
    end
    if viewLayer then Sync(viewLayer, Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale(), 1) end
    if layer then Sync(layer, Content():GetEffectiveScale() / UIParent:GetEffectiveScale(), 2) end
    if Zone.arrowLayer then Sync(Zone.arrowLayer, Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale(), 3) end
end

-- OpenMap draws your arrow on its icon layer, which goes under the markers' layer (Questie's icons
-- over OpenMap's, as on OpenMap's own map): with the markers on their own layer, quest icons
-- covered your arrow. The arrow gets a layer of its own, over the markers. (Its frame: the one on an
-- addon's icon layer holding the minimap's arrow picture.)
function Zone.FindArrow()
    local a = Zone.arrowFrame
    if a and Zone.arrowLayer and a:GetParent() == Zone.arrowLayer then return a end
    for f in pairs(iconLayers) do
        for _, child in ipairs(Zone.Children(f)) do
            for _, r in ipairs({ child:GetRegions() }) do
                if r:GetObjectType() == "Texture" then
                    local path = r.GetTextureFilePath and r:GetTextureFilePath() or r:GetTexture()
                    if type(path) == "string" and path:lower():find("minimaparrow") then return child end
                end
            end
        end
    end
end

function Zone.RaiseArrow(alpha)
    local a = Zone.FindArrow()
    if not a then return end
    if not Zone.arrowLayer then
        Zone.arrowLayer = CreateFrame("Frame", "OverlayMapArrow", UIParent)
        Zone.arrowLayer:SetClipsChildren(true)
    end
    local L = Zone.arrowLayer
    Sync(L, Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale(), 3)
    if math.abs(L:GetAlpha() - alpha) > 0.001 then L:SetAlpha(alpha) end
    L:Show()
    if a:GetParent() ~= L then
        Zone.arrowFrame, Zone.arrowParent = a, a:GetParent()
        Keep.Reparent(a, L, 2)
    end
end

function Zone.LowerArrow()
    local a, parent = Zone.arrowFrame, Zone.arrowParent
    if a and parent and a:GetParent() == Zone.arrowLayer then Keep.Reparent(a, parent, 2) end
    Zone.arrowFrame, Zone.arrowParent = nil, nil
    if Zone.arrowLayer then Zone.arrowLayer:Hide() end
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
    if want and not fixed and f:GetFrameLevel() ~= want and want >= 0 and want <= 65535 then
        pcall(f.SetFrameLevel, f, want)
    end
    if depth > 0 then
        for _, child in ipairs({ f:GetChildren() }) do LoadLevels(child, levels, depth - 1) end
    end
end

-- (a protected marker, like your group's in combat, can't be moved by an addon then: left where it is, and
-- false said, instead of an error)
local function Reparent(f, parent, depth)
    if InCombatLockdown() and f.IsProtected and f:IsProtected() then return false end
    local levels = {}
    SaveLevels(f, levels, depth)
    if not pcall(f.SetParent, f, parent) then return false end
    LoadLevels(f, levels, depth)
    return true
end
Keep.Reparent = Reparent -- (for your arrow's layer, further up)

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
    for f in pairs(viewMoved) do
        Reparent(f, c, 5)
    end
    wipe(viewMoved)
    if viewLayer then viewLayer:Hide() end
    Zone.LowerArrow()
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
    if reshaping and not settling then Zone.refitAgain = true return end -- (laid out after that one)
    if settling then RefitNow() else QueueRefit() end
end

QueueRefit = function()
    if refitTimer then refitTimer:Cancel() end
    refitTimer = C_Timer.NewTimer(0.25, function()
        refitTimer = nil
        if not compact or reshaping then return end
        -- (already hidden for a layout: re-fitted now, and that one shows it again)
        if settling then RefitNow() return end
        -- (a fade out and in around the new layout, keeping OpenMap's view, instead of a blink)
        if Zone.Reshape then Zone.Reshape(true) return end
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
local FadeTo -- (below)

local function ApplyOpacity()
    local map = Map()
    -- The game fades the map while you move; Overlay Map does it itself (to half) when
    -- "Don't fade while moving" is off, so it works with these opacities.
    local fade = (not db.noFade and IsPlayerMoving and IsPlayerMoving()) and 0.5 or 1
    if settling or Zone.shelved then fade = 0 end
    -- (opening: hidden until the edges are laid, so the map isn't seen uncut for a moment, then a
    -- quick fade in; a second at most)
    if Zone.opening then
        -- (inside a dungeon with OpenMap: also until its dungeon map is up and tidied, a moment after)
        local hold = Zone.holdFor and GetTime() < Zone.holdFor
        if (settling or Zone.walking or hold) and GetTime() - Zone.opening < 1 then
            fade = 0
        else
            Zone.opening = nil
            transition = 0
            FadeTo(1, 0.15)
        end
    end
    fade = fade * transition
    -- (the setup wizard's key step: the map faint until you press the key you chose)
    if Wizard.dimNow then fade = fade * Wizard.dimNow end
    local mapAlpha = db.opacity * fade
    -- (Outlines: the map's painting hidden, the lines drawn on their own layer, the markers on theirs)
    if db.style == "outlines" then mapAlpha = 0 end
    -- (the live minimap in a dungeon: shown instead of the map, at its opacity)
    if Zone.live then
        mapAlpha = 0
        if Minimap and math.abs(Minimap:GetAlpha() - db.opacity * fade) > 0.001 then Minimap:SetAlpha(db.opacity * fade) end
        -- (redrawn once it actually shows: while the map was still invisible as it opened, the minimap's redraw
        -- was lost, and it showed black or blank from the second opening on)
        if not Zone.live.drawn and db.opacity * fade > 0.05 then
            Zone.live.drawn = true
            C_Timer.After(0.05, function() if Zone.live then Zone.MinimapRedraw(0) end end)
        end
    end
    if math.abs(map:GetAlpha() - mapAlpha) > 0.001 then map:SetAlpha(mapAlpha) end
    Outline.Apply(db.opacity * fade)

    -- (the same opacity: the markers stay on the map. Not with an addon's icon layer, like OpenMap's:
    -- on the map it's over the markers, so its icons covered your arrow, which is the game's marker
    -- when OpenMap doesn't draw its own; on Overlay Map's layers your arrow goes over them)
    if math.abs(db.pinOpacity - db.opacity) < 0.001 and db.style ~= "outlines" and not next(iconLayers) then
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
    -- (over OpenMap's dungeon map: the world's markers underneath kept off it)
    -- (also while inside a dungeon its map is only away in the journal's window for a moment)
    local pinFade = (Zone.live or Zone.DungeonViewShown() or (Zone.underAlpha ~= nil and Zone.InDungeon())) and 0 or 1
    if math.abs(layer:GetAlpha() - db.pinOpacity * fade * pinFade) > 0.001 then layer:SetAlpha(db.pinOpacity * fade * pinFade) end
    layer:Show()
    if math.abs(viewLayer:GetAlpha() - db.pinOpacity * fade * pinFade) > 0.001 then viewLayer:SetAlpha(db.pinOpacity * fade * pinFade) end
    viewLayer:Show()
    -- Going through every marker (with Questie, hundreds) is the costly part: only when there are new ones
    -- (Keep.pinsDirty: the map acquired a marker, an option changed, the map opened) and once a second as a
    -- safety net, not on every opacity change (a fade sets it every frame) nor on every upkeep. A marker the map
    -- puts back on itself goes straight back to the layer anyway (MovePin's hook).
    local now = GetTime()
    if Keep.pinsDirty or now - (Keep.pinsAt or 0) >= 1 then
        Keep.pinsDirty, Keep.pinsAt = false, now
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
    Zone.RaiseArrow(db.pinOpacity * fade * pinFade)
end

local function RestoreOpacity()
    ReturnPins()
    Outline.Hide()
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

FadeTo = function(target, time, done)
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

-- Zone border: the map cut to the outline of a zone, one per zone and capital city. Each zone's is
-- the land its map paints: all its exploration pieces put together, from the game's own pictures.
-- The capitals have none: Ironforge and Undercity are cut from their indoor minimap pictures
-- (placed with TerrainWorldMap's tables, MIT licence: Media\Zone\LICENSE-TerrainWorldMap.txt),
-- Thunder Bluff and Darnassus from which zone each piece of ground belongs to, and Stormwind and
-- Orgrimmar come from Waymark's outlines (MIT licence: Media\Zone\LICENSE-Waymark.txt). Each is over
-- the zone map's whole picture: <uiMapID>.tga sharp, <uiMapID>s.tga with a soft edge inside the
-- border. The outline is laid over the zone's place on the map shown, so it moves and zooms with the
-- map: on the game's map, the zone shown; with OpenMap's whole world, the zone you're in. Where
-- there's no outline, the rectangle is used.
-- The outlines are a separate download (an addon of their own, loaded only when needed), as their
-- pictures are much bigger than the rest of Overlay Map.
Zone.ADDON = "OverlayMap_ZoneBorders"
Zone.MEDIA = "Interface\\AddOns\\" .. Zone.ADDON .. "\\Zone\\"

-- Where the outlines stand: "loaded", "ready" (installed and on, not loaded yet), "disabled"
-- (installed, but off in the AddOns list) or "missing" (not installed)
function Zone.Status(addon)
    addon = addon or Zone.ADDON
    local api = C_AddOns or {}
    local IsLoaded = api.IsAddOnLoaded or IsAddOnLoaded
    if IsLoaded and IsLoaded(addon) then return "loaded" end
    local Info = api.GetAddOnInfo or GetAddOnInfo
    if not Info then return "missing" end
    local ok, name, _, _, _, reason = pcall(Info, addon)
    if not ok or not name or reason == "MISSING" then return "missing" end
    if reason == "DISABLED" then return "disabled" end
    return "ready"
end

function Zone.Installed() return Zone.Status() ~= "missing" end

-- Said in the chat and in the middle of the screen (the chat may be hidden while the map is open)
function Zone.Tell(msg)
    Say(msg)
    if UIErrorsFrame then UIErrorsFrame:AddMessage("Overlay Map: " .. msg, 1, 0.82, 0) end
end

-- Whether the outlines can be used: loaded the first time they're wanted. (When the download is off
-- in the AddOns list, choosing Zone Border asks to turn it on and reload: Zone.CheckDownload.)
function Zone.Available()
    if Zone.available then return true end
    if Zone.triedAt and GetTime() - Zone.triedAt < 5 then return false end -- (not tried over and over)
    Zone.triedAt = GetTime()
    local api = C_AddOns or {}
    local Load = api.LoadAddOn or LoadAddOn
    if Zone.Status() == "ready" and Load then
        local ok, _, why = pcall(Load, Zone.ADDON)
        Zone.loadReason = ok and why or "error"
    end
    Zone.available = Zone.Status() == "loaded"
    return Zone.available
end

Zone.ZONE_MASKS = {
    [1411] = true, [1412] = true, [1413] = true, [1416] = true, [1417] = true, [1418] = true,
    [1419] = true, [1420] = true, [1421] = true, [1422] = true, [1423] = true, [1424] = true,
    [1425] = true, [1426] = true, [1427] = true, [1428] = true, [1429] = true, [1430] = true,
    [1431] = true, [1432] = true, [1433] = true, [1434] = true, [1435] = true, [1436] = true,
    [1437] = true, [1438] = true, [1439] = true, [1440] = true, [1441] = true, [1442] = true,
    [1443] = true, [1444] = true, [1445] = true, [1446] = true, [1447] = true, [1448] = true,
    [1449] = true, [1450] = true, [1451] = true, [1452] = true, [1453] = true, [1459] = true,
    [1455] = true, [1456] = true, [1457] = true, [1458] = true, -- (our own: see above)
    [2482] = true, [2521] = true, [2548] = true, [2652] = true,
}



function Zone.WorldRect(id)
    if id == 947 then return 0, 1, 0, 1 end
    if type(id) == "string" then -- (a cave: "cave<key>", see Zone.CaveKeyAt)
        local r = Zone.CaveRectOf(tonumber(id:match("^cave(%-?%d+)$")))
        if r then return r[1], r[3], r[2], r[4] end
        return
    end
    -- (with OpenMap's whole world, where OpenMap itself places each map: for cities it uses their
    -- corners' world positions, which on WoW: Forever are tens of yards off the game's own rect)
    local S = Zone.OpenMapStitched() and _G.OpenMap and _G.OpenMap.MapStitch
    if S and S.Rect then
        local okS, sl, sr, st, sb = pcall(S.Rect, id)
        if okS and sl and sr > sl and sb > st then return sl, sr, st, sb end
    end
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, id, 947)
    if ok and l and r > l and b > t then return l, r, t, b end
end

function Zone.OpenMapStitched()
    local api = OpenMapLoaded() and _G.OpenMapAPI
    return api and api.IsStitched and api.IsStitched() and true or false
end

-- The capital cities, with the zone around each, to tell whether the view is on your zone (a city
-- and its zone count as the same place).
Zone.CITY_ZONE = { [1455] = 1426, [1456] = 1412, [1457] = 1438, [1458] = 1420 } -- Ironforge, Thunder Bluff, Darnassus, Undercity
Zone.SAME_PLACE = { [1453] = 1429, [1454] = 1411 } -- Stormwind in Elwynn Forest, Orgrimmar in Durotar
-- With OpenMap's whole world: a zone is outlined while it fills at least FILL_ON of the view (1: it
-- just fits; the Whole Map When Zoomed Out option, db.zoneWhole), and keeps it until it fills less than
-- FILL_OFF, 10% less (two values, so it doesn't switch back
-- and forth at one). Below that (about two to three zones across), the next zone around it is
-- tried (from a city, the zone it's in), and the whole map shows when none is big enough.
function Zone.FillOn() return db.zoneWhole or 0.45 end
function Zone.FillOff() return math.max(0.05, Zone.FillOn() - 0.1) end
Zone.FIT_MARGIN = 0.9 -- entering a zone: zoomed so it fills 90% of the view

function Zone.Same(id)
    id = Zone.CITY_ZONE[id] or id
    return Zone.SAME_PLACE[id] or id
end

-- The zone at a point of the world (normalized), as deep as the game's maps go
function Zone.ZoneAt(u, v)
    local id = 947
    for _ = 1, 4 do
        local l, r, t, b = Zone.WorldRect(id)
        if not l then break end
        local ok, info = pcall(C_Map.GetMapInfoAtPosition, id, (u - l) / (r - l), (v - t) / (b - t))
        if not ok or not info or not info.mapID or info.mapID == id then break end
        id = info.mapID
    end
    return id ~= 947 and id or nil
end

-- The map around one (a city: the zone it's in; a zone: its continent)
function Zone.Around(id)
    local near = Zone.CITY_ZONE[id] or Zone.SAME_PLACE[id]
    if near then return near end
    local info = C_Map.GetMapInfo(id)
    return info and info.parentMapID
end

-- The nearest map with an outline, from one outwards (a dungeon's map or a part of a zone has none)
function Zone.Outlined(id)
    for _ = 1, 6 do
        if not id then return end
        if Zone.ZONE_MASKS[id] then return id end
        id = Zone.Around(id)
    end
end

-- Where you are: the zone with an outline you're in (inside a capital, the city)
function Zone.PlayerZone()
    return Zone.Outlined(C_Map.GetBestMapForUnit("player"))
end

function Zone.OpenMapModule()
    local OM = _G.OpenMap
    if not (OM and OM.GetModule) then return end
    local ok, mod = pcall(OM.GetModule, OM, "worldmap")
    return ok and type(mod) == "table" and mod or nil
end

-- Where each outline's painted part is in its zone map's picture (left, right, top, bottom, 0 to 1):
-- a zone's map has wide margins around it, so fitting the whole picture left the zone small
Zone.BOUNDS = {
    [1411] = { 0.262, 0.727, 0.000, 1.000 },
    [1412] = { 0.234, 0.730, 0.008, 0.961 },
    [1413] = { 0.324, 0.664, 0.012, 0.988 },
    [1416] = { 0.000, 0.953, 0.020, 1.000 },
    [1417] = { 0.109, 0.840, 0.113, 0.922 },
    [1418] = { 0.008, 0.957, 0.043, 0.957 },
    [1419] = { 0.234, 0.723, 0.043, 0.910 },
    [1420] = { 0.020, 0.961, 0.188, 0.906 },
    [1421] = { 0.312, 0.812, 0.035, 0.957 },
    [1422] = { 0.156, 0.855, 0.043, 1.000 },
    [1423] = { 0.000, 0.992, 0.000, 1.000 },
    [1424] = { 0.023, 0.965, 0.031, 0.957 },
    [1425] = { 0.035, 0.840, 0.059, 0.902 },
    [1426] = { 0.176, 0.898, 0.258, 0.844 },
    [1427] = { 0.098, 0.859, 0.031, 1.000 },
    [1428] = { 0.055, 0.996, 0.098, 0.855 },
    [1429] = { 0.035, 0.980, 0.023, 1.000 },
    [1430] = { 0.270, 0.672, 0.141, 0.844 },
    [1431] = { 0.039, 0.977, 0.086, 0.930 },
    [1432] = { 0.137, 0.887, 0.055, 0.980 },
    [1433] = { 0.000, 1.000, 0.000, 0.938 },
    [1434] = { 0.172, 0.547, 0.000, 0.895 },
    [1435] = { 0.008, 0.992, 0.000, 0.973 },
    [1436] = { 0.215, 0.785, 0.027, 0.945 },
    [1437] = { 0.031, 0.934, 0.074, 0.848 },
    [1438] = { 0.117, 0.730, 0.164, 0.945 },
    [1439] = { 0.258, 0.680, 0.027, 0.988 },
    [1440] = { 0.039, 1.000, 0.070, 0.918 },
    [1441] = { 0.027, 0.914, 0.031, 0.973 },
    [1442] = { 0.230, 0.895, 0.008, 1.000 },
    [1443] = { 0.188, 0.938, 0.000, 1.000 },
    [1444] = { 0.211, 0.957, 0.008, 0.977 },
    [1445] = { 0.250, 0.836, 0.020, 0.902 },
    [1446] = { 0.223, 0.766, 0.000, 0.996 },
    [1447] = { 0.055, 0.918, 0.031, 0.973 },
    [1448] = { 0.285, 0.699, 0.004, 0.988 },
    [1449] = { 0.141, 0.852, 0.035, 0.973 },
    [1450] = { 0.266, 0.777, 0.164, 0.863 },
    [1451] = { 0.125, 0.852, 0.059, 1.000 },
    [1452] = { 0.242, 0.742, 0.035, 0.938 },
    [1453] = { 0.090, 0.902, 0.039, 0.996 },
    [1455] = { 0.148, 0.887, 0.008, 0.992 },
    [1456] = { 0.109, 0.879, 0.023, 0.984 },
    [1457] = { 0.070, 0.887, 0.000, 1.000 },
    [1458] = { 0.125, 0.898, 0.082, 0.992 },
    [1459] = { 0.355, 0.613, 0.047, 0.969 },
    [2482] = { 0.000, 0.980, 0.133, 0.996 },
    [2521] = { 0.266, 0.859, 0.047, 1.000 },
    [2548] = { 0.043, 0.938, 0.004, 1.000 },
    [2652] = { 0.098, 0.898, 0.008, 1.000 },
}

-- The part of the world the zone's outline takes (its map's rect, without the margins)
function Zone.Box(id)
    local l, r, t, b = Zone.WorldRect(id)
    if not l then return end
    local k = Zone.BOUNDS[id]
    if not k then return l, r, t, b end
    local w, h = r - l, b - t
    return l + k[1] * w, l + k[2] * w, t + k[3] * h, t + k[4] * h
end

-- The OpenMap zoom at which a zone's outline just fits the view (OpenMap's own sums: zoom 1 is the
-- whole world fitting the view)
function Zone.FitZoom(id)
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    local c = Canvas()
    local l, r, t, b = Zone.Box(id)
    if S and S.Size and c and l then
        local okS, W, H = pcall(S.Size)
        local cw, ch = c:GetWidth(), c:GetHeight()
        if okS and type(W) == "number" and type(H) == "number" and W > 0 and H > 0 and cw > 0 and ch > 0 then
            local z = math.min(cw / ((r - l) * W), ch / ((b - t) * H)) / math.min(cw / W, ch / H)
            if z > 0 and z < math.huge then return z end
        end
    end
    local om = Zone.OpenMapModule()
    if not (om and om.FitZoom) then return end
    local ok, fit = pcall(om.FitZoom, id)
    if ok and type(fit) == "number" and fit > 0 and fit < math.huge then return fit end
end

-- OpenMap's zoom counts from the whole world just fitting the map area, so the same zoom shows the
-- land bigger in a wider area. This is that fit (map area units per world unit), to keep the land's
-- size on screen when the area's width changes: zoom * FitPx() stays the same.
function Zone.FitPx()
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    local c = Canvas()
    if not (S and S.Size and c) then return end
    local ok, W, H = pcall(S.Size)
    local cw, ch = c:GetWidth(), c:GetHeight()
    if ok and type(W) == "number" and type(H) == "number" and W > 0 and H > 0 and cw > 0 and ch > 0 then
        return math.min(cw / W, ch / H)
    end
end

-- How much of the view a zone fills at OpenMap's zoom z (1: it just fits)
function Zone.Fill(id, z)
    local fit = Zone.FitZoom(id)
    if fit then return z / fit end
    local l, r = Zone.WorldRect(id)
    return l and (r - l) * z or 1
end

-- Follow Me with the zone border (OpenMap): the view follows you but doesn't leave your zone's outline.
-- While the whole zone fits, it stays centred on the zone and doesn't move; zoomed in closer, it
-- follows you up to the zone's edges.
function Zone.Clamp(u, v, zoom)
    -- (no outline, zoomed out to the whole map: just following you)
    if not db.zoneBorder or not (Zone.shown or Zone.want) then return u, v end
    -- (on a flight, or in no outlined zone: just following you, so you don't leave the view)
    if UnitOnTaxi("player") then return u, v end
    local mine = Zone.PlayerZone()
    if not mine then return u, v end
    -- Kept inside the zone you're in, not the outline shown: entering a new zone, the outline takes
    -- half a second to change over, and until then the view followed you freely, then jumped back
    -- (and fought the zoom of Fit Zone, which centres on the new zone at once).
    -- (inside a city with its zone outlined, zoomed out: the zone's box, as shown)
    local box = (Zone.shown and Zone.Same(Zone.shown) == Zone.Same(mine)) and Zone.shown or mine
    local l, r, t, b = Zone.Box(box)
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    local c = Canvas()
    if not l or not (S and S.Size and c) then return u, v end
    local okS, W, H = pcall(S.Size)
    if not zoom then
        local okV, _, _, z = pcall(_G.OpenMapAPI.GetView)
        zoom = okV and z
    end
    local cw, ch = c:GetWidth(), c:GetHeight()
    if not okS or type(W) ~= "number" or type(H) ~= "number" or W <= 0 or H <= 0 or type(zoom) ~= "number"
        or zoom <= 0 or cw <= 0 or ch <= 0 then return u, v end
    local px = zoom * math.min(cw / W, ch / H) -- (view px per world unit)
    local hu, hv = cw / px / W / 2, ch / px / H / 2 -- (half the view, in the world's 0..1)
    if r - l <= 2 * hu then u = (l + r) / 2 else u = math.max(l + hu, math.min(r - hu, u)) end
    if b - t <= 2 * hv then v = (t + b) / 2 else v = math.max(t + hv, math.min(b - hv, v)) end
    return u, v
end

-- The deepest map at a point of OpenMap's world
function Zone.DeepestAt(u, v)
    local api = _G.OpenMapAPI
    if api and api.MapAt then
        local ok, id = pcall(api.MapAt, u, v)
        if ok and id then return id end
    end
    return Zone.ZoneAt(u, v)
end

-- The zone to cut to (nil: none fits; Zone.why says why, for /omap debug)
function Zone.MaskZone()
    -- (inside a cave: the cave's own outline, as a cave can reach past its zone's, which cut it off; the
    -- whole map in one OpenMap has no place for)
    -- Only while the cave is big enough in the view (as a zone's outline): zoomed out to the zone, a cave is a
    -- speck, and cutting the map to it left almost nothing; then the zone's outline as usual.
    if Zone.inCave then
        local cave = Zone.caveKey and ("cave" .. Zone.caveKey)
        local okV, _, _, z = pcall(function() return _G.OpenMapAPI.GetView() end)
        local fit = cave and okV and type(z) == "number" and Zone.FitZoom(cave)
        if cave and fit and z / fit >= ((Zone.want == cave) and Zone.FillOff() or Zone.FillOn()) then return cave end
        if not cave then
            Zone.why = "in a cave"
            return
        end
    end
    local shown = Map():GetMapID()
    if not Zone.OpenMapStitched() then
        if shown and Zone.ZONE_MASKS[shown] then return shown end
        Zone.why = "no outline for the map shown (" .. tostring(shown) .. ")"
        return
    end
    local ok, u, v, z = pcall(_G.OpenMapAPI.GetView)
    if not ok or type(u) ~= "number" or type(z) ~= "number" then
        local zone = Zone.PlayerZone()
        if not zone then Zone.why = "no outline for where you are" end
        return zone
    end
    local here = Zone.DeepestAt(u, v)
    -- From the zone in the middle of the view (or where you are), outwards: the first with an
    -- outline that's big enough in the view
    local id = db.zoneView and here or C_Map.GetBestMapForUnit("player")
    local first, zone, tried = id, nil, nil
    for _ = 1, 6 do
        if not id then break end
        if Zone.ZONE_MASKS[id] then
            local fill = Zone.Fill(id, z)
            if fill >= ((id == Zone.want) and Zone.FillOff() or Zone.FillOn()) then zone = id break end
            tried = tried or string.format("%d fills %d%% of the view", id, fill * 100 + 0.5)
        end
        id = Zone.Around(id)
    end
    if not zone and not tried and db.zoneKeep then
        -- (nothing with an outline in the middle of the view, like the sea or a gap between zones:
        -- the zone it had, or yours, while still big enough in view, so the rest of the map stays
        -- at its opacity instead of the whole map coming back)
        for _, keep in ipairs({ Zone.want or false, Zone.PlayerZone() or false }) do
            if keep and Zone.Fill(keep, z) >= Zone.FillOff() then zone = keep break end
        end
    end
    if zone and not db.zoneView and not db.zoneKeep and not Zone.Outlined(here) then
        Zone.why = "no zone in the middle of the view (" .. tostring(here) .. ")"
        zone = nil
    elseif zone and not db.zoneView and Zone.Outlined(here) then
        -- (your zone only: the whole map while the middle of the view is on another zone; over the
        -- sea or a gap between zones it stays)
        local same, at = false, here
        for _ = 1, 6 do
            if not at then break end
            if Zone.Same(at) == Zone.Same(zone) then same = true break end
            at = Zone.Around(at)
        end
        if not same then
            Zone.why = "looking at another zone (" .. tostring(here) .. ")"
            zone = nil
        end
    elseif not zone then
        Zone.why = tried and ("zoomed out (" .. tried .. ")")
            or ("no outline for " .. (db.zoneView and "the middle of the view" or "where you are")
            .. " (" .. tostring(first) .. ")")
    end
    return zone
end

-- Lays the anchor over the zone's place on the map shown (in the map's own units, so it pans and
-- zooms with it). False when the zone can't be placed there.
function Zone.RectOnHost(zone)
    local host = Map():GetMapID()
    if not host then return end
    if zone == host then return 0, 1, 0, 1 end
    local zl, zr, zt, zb = Zone.WorldRect(zone)
    local hl, hr, ht, hb = Zone.WorldRect(host)
    if not zl or not hl then return end
    return (zl - hl) / (hr - hl), (zr - hl) / (hr - hl), (zt - ht) / (hb - ht), (zb - ht) / (hb - ht)
end

function Zone.PlaceZoneAnchor(zone)
    local content = Canvas().Child
    if not content then return false end
    local l, r, t, b = Zone.RectOnHost(zone)
    if not l then return false end
    local cw, ch = content:GetSize()
    if not cw or cw == 0 then return false end
    if not Zone.zoneAnchor then
        Zone.zoneAnchor = CreateFrame("Frame", nil, content)
        Zone.zoneAnchor.overlayMapOwn = true
    end
    if Zone.zoneAnchor:GetParent() ~= content then Zone.zoneAnchor:SetParent(content) end
    local key = string.format("%.5f %.5f %.5f %.5f %.1f %.1f", l, r, t, b, cw, ch)
    if Zone.zoneAnchor.placed ~= key then
        Zone.zoneAnchor.placed = key
        Zone.zoneAnchor:ClearAllPoints()
        Zone.zoneAnchor:SetPoint("TOPLEFT", content, "TOPLEFT", l * cw, -t * ch)
        Zone.zoneAnchor:SetSize((r - l) * cw, (b - t) * ch)
    end
    return true
end

-- Changing outline (another zone, or the whole map) goes through the rest of the map's opacity: up
-- to 90% (another zone) or 100% (no cut), the new outline, and down to its opacity again, in steps a quarter of a second
-- each way. Zone.want: the zone wanted; Zone.shown: the one laid; Zone.level: the rest of the map's
-- opacity now (100: no cut); Zone.zoneNow: the zone cut to (nil while at 100). The steps past 60%
-- have smaller pictures (<id>d70, d80, d90), only seen for a moment.
-- A step only comes once its picture is loaded (a mask whose picture isn't loaded yet hides the whole
-- map for a moment): each zone's pictures are loaded ahead on hidden textures as soon as it's wanted,
-- for the last few zones. And a new zone is only taken once it has stayed the one wanted for SETTLE
-- seconds, so moving along a border doesn't switch back and forth.
Zone.STEPS = { 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80, 90, 100 }
Zone.STEP_TIME = 0.025
Zone.SETTLE = 0.25
Zone.KEEP_LOADED = 4

function Zone.FileFor(zone, level)
    if type(zone) == "string" then return Zone.CaveFile(zone) end
    return Zone.MEDIA .. zone .. ((level > 0 and level < 100) and ("d" .. level) or "")
        .. (db.zoneSoft and "s" or "")
end

Zone.loaded, Zone.loadOrder, Zone.spare = {}, {}, {}
function Zone.Preload(zone)
    local key = zone .. (db.zoneSoft and "s" or "")
    if Zone.loaded[key] then return Zone.loaded[key] end
    if not Zone.holder then
        Zone.holder = CreateFrame("Frame", nil, UIParent)
        Zone.holder:SetSize(1, 1)
        Zone.holder:SetPoint("BOTTOMLEFT")
    end
    if #Zone.loadOrder >= Zone.KEEP_LOADED then Zone.Unload(Zone.loadOrder[1]) end
    local set = { at = GetTime() }
    for _, level in ipairs(Zone.STEPS) do
        if level < 100 then
            local t = table.remove(Zone.spare) or Zone.holder:CreateTexture(nil, "BACKGROUND")
            t:ClearAllPoints()
            t:SetPoint("BOTTOMLEFT")
            t:SetSize(1, 1)
            t:SetAlpha(0)
            t:SetTexture(Zone.FileFor(zone, level))
            t:Show()
            set[level] = t
        end
    end
    Zone.loaded[key] = set
    Zone.loadOrder[#Zone.loadOrder + 1] = key
    return set
end

function Zone.Unload(key)
    local set = Zone.loaded[key]
    Zone.loaded[key] = nil
    for i, k in ipairs(Zone.loadOrder) do
        if k == key then table.remove(Zone.loadOrder, i) break end
    end
    if not set then return end
    for level, t in pairs(set) do
        if type(level) == "number" then
            t:SetTexture(nil)
            t:Hide()
            Zone.spare[#Zone.spare + 1] = t
        end
    end
end

-- Whether a zone's picture at a level is loaded (no picture at 100: nothing to wait for)
function Zone.Ready(zone, level)
    if not zone or level >= 100 then return true end
    local set = Zone.Preload(zone)
    local t = set[level]
    if t and t.IsObjectLoaded then
        local ok, done = pcall(t.IsObjectLoaded, t)
        if ok and type(done) == "boolean" then return done end
    end
    return GetTime() - set.at > 0.15 -- (a client that can't tell: a moment after asking for it)
end

-- The rest of the map's opacity set (to the nearest one there's a picture for: 5% steps to 60%)
function Zone.Target()
    -- (a cave's outline has no faded steps: outside it, nothing)
    if type(Zone.shown or Zone.want) == "string" then return 0 end
    local level = math.floor((db.zoneDim or 0) * 100 / 5 + 0.5) * 5
    return math.max(0, math.min(60, level))
end

function Zone.DimSuffix()
    local level = Zone.level or Zone.Target()
    return (level > 0 and level < 100) and ("d" .. level) or ""
end

function Zone.NextStep(level, target)
    local steps = Zone.STEPS
    if target > level then
        for i = 1, #steps do if steps[i] > level then return math.min(steps[i], target) end end
    else
        for i = #steps, 1, -1 do if steps[i] < level then return math.max(steps[i], target) end end
    end
    return target
end

function Zone.Goal()
    -- (from one zone to another, the change happens at 90%, so the whole map doesn't show for a
    -- moment in between; to or from the whole map, at 100%)
    if Zone.want ~= Zone.shown then return (Zone.want and Zone.shown) and 90 or 100 end
    return Zone.shown and Zone.Target() or 100
end

function Zone.SetNow()
    Zone.zoneNow = (Zone.shown and Zone.level and Zone.level < 100) and Zone.shown or nil
end

function Zone.Reset(keepLoaded)
    Zone.want, Zone.shown, Zone.level, Zone.zoneNow, Zone.pending = nil, nil, nil, nil, nil
    if Zone.anim then Zone.anim:Hide() end
    if keepLoaded then return end
    while Zone.loadOrder[1] do Zone.Unload(Zone.loadOrder[1]) end
end

-- Which zone the outline is for (worked out each time the edges are laid)
function Zone.UpdateZone()
    Zone.why = nil
    if not db.zoneBorder then Zone.Reset() return end
    if not Zone.Available() then
        Zone.Reset()
        Zone.why = "the Overlay Map: Zone Borders download isn't installed or enabled"
        return
    end
    local want = Zone.MaskZone()
    if want and want ~= Zone.want and not Zone.RectOnHost(want) then
        -- (the game's map changes underneath while OpenMap zooms, and for a moment the zone can't
        -- be placed on it: the outline stays as it was)
        Zone.why = "zone " .. want .. " couldn't be placed on the map shown (" .. tostring(Map():GetMapID()) .. ")"
        want = Zone.want
    end
    -- (a zone's pictures for the fade are loaded once it's wanted instead of the one shown)
    if want and want ~= Zone.shown and Zone.level ~= nil then Zone.Preload(want) end
    if Zone.level == nil then -- (the map just opened, or the shape just chosen: straight there)
        Zone.want, Zone.pending = want, nil
        Zone.shown, Zone.level = want, want and Zone.Target() or 100
    elseif (want or false) == (Zone.want or false) then
        Zone.pending = nil
    elseif type(want) == "string" or type(Zone.shown) == "string" then
        -- (into or out of a cave: the new outline at once, as the map glides there. A cave's outline has no
        -- faded steps, so stepping through them kept the cave's shape over the surface's map for a moment)
        Zone.want, Zone.pending = want, nil
        Zone.shown, Zone.level = want, want and Zone.Target() or 100
    else
        -- (taken once it has stayed the one wanted for a moment)
        if Zone.pending ~= (want or false) then Zone.pending, Zone.pendingAt = want or false, GetTime() end
        if GetTime() - Zone.pendingAt >= Zone.SETTLE then Zone.want, Zone.pending = want, nil end
    end
    if Zone.shown then Zone.PlaceZoneAnchor(Zone.shown) end -- (if it can't, it stays where it was)
    Zone.SetNow()
    if Zone.level ~= Zone.Goal() or Zone.want ~= Zone.shown or Zone.pending ~= nil then Zone.anim:Show() end
end

Zone.anim = CreateFrame("Frame")
Zone.anim:Hide()
Zone.anim.acc = 0
Zone.anim:SetScript("OnUpdate", function(self, elapsed)
    if not compact or Zone.level == nil then self:Hide() return end
    self.acc = self.acc + elapsed
    if self.acc < Zone.STEP_TIME then return end
    self.acc = 0
    if Zone.pending ~= nil and GetTime() - Zone.pendingAt >= Zone.SETTLE then
        Zone.UpdateZone() -- (still the one wanted: taken now)
    end
    local goal = Zone.Goal()
    if Zone.level ~= goal then
        local nextLevel = Zone.NextStep(Zone.level, goal)
        if not Zone.Ready(Zone.shown, nextLevel) then return end -- (its picture is still loading)
        Zone.level = nextLevel
    elseif Zone.want ~= Zone.shown then
        if not Zone.Ready(Zone.want, Zone.level) then return end
        Zone.shown = Zone.want -- (the new outline, from where it goes down again)
        if Zone.shown then Zone.PlaceZoneAnchor(Zone.shown) end
    elseif Zone.pending == nil then
        self:Hide()
        return
    else
        return
    end
    Zone.SetNow()
    if Zone.Redraw then Zone.Redraw() end
end)

-- Two masks on the map: the shape (the torn parchment's edge, or the soft edges' shape; none for a
-- plain rectangle) over the whole map area, and the zone's outline over the zone's place.
local function ShapeFile()
    -- (the torn parchment's edge is always the same; soft edges come in four widths, and with
    -- them off a diamond or an oval is cut sharp)
    if db.style == "torn" then return MEDIA .. "Torn" end
    return MEDIA .. (SHAPE_FILES[db.shape] or "Edge") .. db.edge
end

local function ZoneFile()
    -- (the outline gone while the edges were being laid, a few frames at a time: cutting nothing)
    if not Zone.zoneNow then return Zone.NEUTRAL end
    if type(Zone.zoneNow) == "string" then return Zone.CaveFile(Zone.zoneNow) end
    return Zone.MEDIA .. Zone.zoneNow .. Zone.DimSuffix() .. (db.zoneSoft and "s" or "")
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

-- Outlines style: the map's painting hidden, and instead white lines for cliffs, water and
-- roads, made from the game's terrain, over a dark background, like other games' overlay maps. Its
-- own layer over the map area (as the markers' layers: the map itself is made invisible), with the
-- background filling it and each zone's lines laid over the zone's place on the map, moving and
-- zooming with it. Each zone's picture holds only its own land's lines (so neighbours don't draw
-- over each other on OpenMap's world), grey on black, drawn adding light (black adds nothing).
Outline.ADDON = "OverlayMap_Outlines"
Outline.ZONES = {} -- (filled below: every zone of Kalimdor and the Eastern Kingdoms with lines)
for _, id in ipairs({ 1411, 1412, 1413, 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426,
    1427, 1428, 1429, 1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444,
    1445, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 2482, 2548, 2652 }) do
    Outline.ZONES[id] = true
end
Outline.frames = {}

function Outline.Hide()
    if Outline.layer then Outline.layer:Hide() end
end

function Outline.Apply(alpha)
    if not compact or db.style ~= "outlines" or not Outline.available then Outline.Hide() return end
    if not Outline.layer then
        local f = CreateFrame("Frame", "OverlayMapOutlines", UIParent)
        f:SetClipsChildren(true)
        f.back = f:CreateTexture(nil, "BACKGROUND")
        f.back:SetAllPoints()
        f.back:SetColorTexture(0, 0, 0, 1)
        Outline.layer = f
    end
    local f = Outline.layer
    if not f:IsShown() then
        f:Show()
        SyncLayer()
    end
    if math.abs(f:GetAlpha() - alpha) > 0.001 then f:SetAlpha(alpha) end
    f.back:SetAlpha(db.outlineBack or 0.6)
    for _, z in pairs(Outline.frames) do z.tex:SetAlpha(db.outlineLines or 1) end
end

-- Each zone's lines over its place on the map shown (with OpenMap's whole world, every zone's)
function Outline.Place()
    local f, content = Outline.layer, Content()
    if not (f and f:IsShown() and content) then return end
    local cw, ch = content:GetSize()
    if not cw or cw == 0 then return end
    local scale = content:GetEffectiveScale() / f:GetEffectiveScale()
    for id in pairs(Outline.ZONES) do
        local z = Outline.frames[id]
        if not z then
            z = CreateFrame("Frame", nil, f)
            z.tex = z:CreateTexture(nil, "ARTWORK")
            z.tex:SetAllPoints()
            z.tex:SetTexture("Interface\\AddOns\\" .. Outline.ADDON .. "\\Outlines\\" .. id)
            z.tex:SetBlendMode("ADD")
            z.tex:SetAlpha(db.outlineLines or 1)
            Outline.frames[id] = z
        end
        local l, r, t, b = Zone.RectOnHost(id)
        if l then
            if math.abs(z:GetScale() - scale) > 0.0001 then z:SetScale(scale) end
            local key = string.format("%.5f %.5f %.5f %.5f %.1f %.1f", l, r, t, b, cw, ch)
            if z.placed ~= key then
                z.placed = key
                z:ClearAllPoints()
                z:SetPoint("TOPLEFT", content, "TOPLEFT", l * cw, -t * ch)
                z:SetSize((r - l) * cw, (b - t) * ch)
            end
            -- (inside a cave, cut to it: the surface's lines would run across it)
            z:SetShown(type(Zone.zoneNow) ~= "string")
        else
            z:Hide()
        end
    end
    Outline.PlaceCave(content, cw, ch, scale)
end

-- Inside a cave: its own lines (walls and water, from the game's minimap pictures of it; for a cave with a
-- Blizzard cave map, the edge of its map), over the cave's place, from the Outlines download's CaveList.lua
function Outline.CaveFile()
    local key = Zone.inCave and Zone.caveKey
    local list = _G.OverlayMap_OutlinesCaves
    if not (key and list) then return end
    local n
    if key > 0 then n = list["map " .. key] else n = Zone.CaveShape(key, list) end
    if n then return "Interface\\AddOns\\" .. Outline.ADDON .. "\\Caves\\" .. n, "cave" .. key end
end

function Outline.PlaceCave(content, cw, ch, scale)
    local file, cave = Outline.CaveFile()
    local l, r, t, b
    if file then l, r, t, b = Zone.RectOnHost(cave) end
    local z = Outline.caveFrame
    if not l then
        if z then z:Hide() end
        return
    end
    if not z then
        z = CreateFrame("Frame", nil, Outline.layer)
        z.tex = z:CreateTexture(nil, "ARTWORK")
        z.tex:SetAllPoints()
        z.tex:SetBlendMode("ADD")
        Outline.caveFrame = z
        Outline.frames.cave = z -- (its opacity with the others': Outline.Apply)
    end
    if z.file ~= file then
        z.file = file
        z.tex:SetTexture(file)
        z.tex:SetAlpha(db.outlineLines or 1)
    end
    if math.abs(z:GetScale() - scale) > 0.0001 then z:SetScale(scale) end
    local key = string.format("%.5f %.5f %.5f %.5f %.1f %.1f", l, r, t, b, cw, ch)
    if z.placed ~= key then
        z.placed = key
        z:ClearAllPoints()
        z:SetPoint("TOPLEFT", content, "TOPLEFT", l * cw, -t * ch)
        z:SetSize((r - l) * cw, (b - t) * ch)
    end
    z:Show()
end
local masks = { shape = {}, zone = {} }                  -- kind -> frame -> its mask
local maskedTex = {                                      -- kind -> picture -> the mask on it
    shape = setmetatable({}, { __mode = "k" }),
    zone = setmetatable({}, { __mode = "k" }),
}

local function MaskFor(frame, kind)
    local m = masks[kind][frame]
    if not m then
        local ok, made = pcall(frame.CreateMaskTexture, frame)
        if not ok or not made then return end
        m = made
        masks[kind][frame] = m
        Zone.ours[m] = true
    end
    local file = kind == "zone" and ZoneFile() or ShapeFile()
    if m.file ~= file then
        -- (past its picture a mask hides everything; the dimmed zone outlines repeat their outer
        -- pixels instead, so the rest of the map stays faded, not hidden)
        local wrap = (kind == "zone" and Zone.DimSuffix() ~= "" and type(Zone.zoneNow) ~= "string") and "CLAMP"
            or "CLAMPTOBLACKADDITIVE"
        m:SetTexture(file, wrap, wrap)
        m.file = file
    end
    local over = kind == "zone" and Zone.zoneAnchor or Canvas()
    if m.syncedTo ~= over then
        m:ClearAllPoints()
        m:SetAllPoints(over)
        m.syncedTo = over
    end
    if not m:IsShown() then m:Show() end
    return m
end

-- A picture only takes a few masks, and OpenMap's already carry up to three of their own: one more
-- may not fit. Whether it took is told by the count going up (or, on a client without it, by no error).
local function AddMask(r, m)
    local before = r.GetNumMaskTextures and r:GetNumMaskTextures()
    if not pcall(r.AddMaskTexture, r, m) then return false end
    if before and r:GetNumMaskTextures() <= before then return false end
    return true
end

-- No room left on a picture (OpenMap's carry up to three masks of their own): one of OpenMap's is
-- taken off while Overlay Map's are on, and put back when they come off. Without it, with Torn
-- Parchment or soft edges and the zone border both on, OpenMap's pictures got only the zone's
-- outline and showed past the map's edges. The one taken: the hole under a city's banner if
-- there's one, else the colour-matching band, else the last.
Zone.dropped = setmetatable({}, { __mode = "k" }) -- picture -> OpenMap's masks taken off it
Zone.ours = setmetatable({}, { __mode = "k" }) -- Overlay Map's masks (told from OpenMap's at once)
function Zone.MakeRoom(r)
    if not (r.GetNumMaskTextures and r.GetMaskTexture) then return false end
    if Zone.dropped[r] and #Zone.dropped[r] >= 2 then return false end -- (ours are two at most)
    local n = r:GetNumMaskTextures()
    if n == 0 then return false end
    local pick, pickRank
    for i = 1, n do
        local mk = r:GetMaskTexture(i)
        if mk and not Zone.ours[mk] then
            local file = tostring(mk.GetTexture and mk:GetTexture() or ""):lower()
            local rank = file:find("hole") and 3 or file:find("band") and 2 or 1
            if not pickRank or rank > pickRank or (rank == pickRank) then pick, pickRank = mk, rank end
        end
    end
    if not pick then return false end
    pcall(r.RemoveMaskTexture, r, pick)
    Zone.dropped[r] = Zone.dropped[r] or {}
    table.insert(Zone.dropped[r], pick)
    return true
end

-- Put back OpenMap's masks taken off pictures, as Overlay Map's come off
function Zone.GiveBack()
    for r, list in pairs(Zone.dropped) do
        -- (as many back as there's room for, now that ours are fewer)
        while #list > 0 and AddMask(r, list[#list]) do table.remove(list) end
        if #list == 0 then Zone.dropped[r] = nil end
    end
end

-- One frame's pictures: each gets the mask (once)
-- Pictures with no room left for the soft edges (OpenMap's surface, carrying masks of its own and the
-- zone's outline). Inside a cave they showed unfaded through the cave's faded edges, brown: there they're
-- hidden (the surface over a cave is of no use), and back as they were outside it.
Zone.noEdge = setmetatable({}, { __mode = "k" })
Zone.bare = {} -- picture -> the opacity it had (hidden by Zone.HideBare)
Zone.bareHooked = setmetatable({}, { __mode = "k" })
function Zone.KeepBare(r, a)
    if Zone.bareSetting or Zone.bare[r] == nil then return end
    Zone.bare[r] = a -- (its own new opacity, for when it comes back)
    Zone.bareSetting = true
    r:SetAlpha(0)
    Zone.bareSetting = false
end
function Zone.HideBare()
    local want = compact and type(Zone.zoneNow) == "string" and Zone.WantShape()
    if want then
        for r in pairs(Zone.noEdge) do
            if Zone.bare[r] == nil then
                Zone.bare[r] = r:GetAlpha()
                if not Zone.bareHooked[r] then
                    Zone.bareHooked[r] = true
                    hooksecurefunc(r, "SetAlpha", Zone.KeepBare)
                end
                Zone.bareSetting = true
                r:SetAlpha(0)
                Zone.bareSetting = false
            end
        end
    end
    for r, a in pairs(Zone.bare) do
        if not (want and Zone.noEdge[r]) then
            Zone.bare[r] = nil
            Zone.bareSetting = true
            r:SetAlpha(a)
            Zone.bareSetting = false
        end
    end
end

local function MaskRegions(frame, kind, m)
    local on = maskedTex[kind]
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local old = on[r]
            if old ~= m then
                if old then pcall(r.RemoveMaskTexture, r, old) end
                on[r] = nil
                if AddMask(r, m) then
                    on[r] = m
                elseif Zone.MakeRoom(r) and AddMask(r, m) then
                    on[r] = m
                elseif kind == "zone" and maskedTex.shape[r] then
                    -- (no room for the zone's outline: it matters more than the soft edges, which
                    -- make room for it and go back on if they still fit)
                    local edge = maskedTex.shape[r]
                    pcall(r.RemoveMaskTexture, r, edge)
                    maskedTex.shape[r] = nil
                    Zone.walked.shape[frame] = nil
                    if AddMask(r, m) then on[r] = m end
                    if AddMask(r, edge) then maskedTex.shape[r] = edge end
                end
            end
            -- (pictures left without the soft edges: see Zone.HideBare)
            if kind == "shape" or maskedTex.shape[r] == nil then Zone.noEdge[r] = (maskedTex.shape[r] == nil) or nil end
        end
    end
end

-- Going through every picture again each time was slow (OpenMap's map is thousands of them): a
-- frame's pictures are only gone through when it has a different number than last time (its mask
-- itself follows any change of picture or place without that), and its list of children is kept
-- until their number changes.
Zone.walked = { shape = setmetatable({}, { __mode = "k" }), zone = setmetatable({}, { __mode = "k" }) }
Zone.kids = setmetatable({}, { __mode = "k" })
function Zone.Children(frame)
    local n = frame:GetNumChildren()
    local c = Zone.kids[frame]
    if not c or c.n ~= n then
        c = { frame:GetChildren() }
        c.n = n
        Zone.kids[frame] = c
    end
    return c
end
Zone.ForgetWalked = function() wipe(Zone.kids) end -- (now and then, for children swapped one for one)

local function MaskTree(frame, depth, kind)
    if depth > 5 or frame:IsForbidden() then return end
    Zone.Breathe()
    local count = frame:GetNumRegions()
    if count > 0 then
        local m = MaskFor(frame, kind)
        if m and Zone.walked[kind][frame] ~= count then
            Zone.walked[kind][frame] = count
            MaskRegions(frame, kind, m)
        end
    end
    local c = Zone.Children(frame)
    for i = 1, #c do MaskTree(c[i], depth + 1, kind) end
end

local function UnmaskKind(kind)
    for tex, m in pairs(maskedTex[kind]) do pcall(tex.RemoveMaskTexture, tex, m) end
    wipe(maskedTex[kind])
    wipe(Zone.walked[kind])
    Zone.GiveBack()
    -- (the soft edges may have made room for the zone's outline on some pictures: back on them)
    if kind == "zone" then wipe(Zone.walked.shape) end
    for _, m in pairs(masks[kind]) do m:Hide() end
end

local function Unmask()
    HideRim()
    UnmaskKind("shape")
    UnmaskKind("zone")
end

-- Taking every mask off when the map closed, and putting them all back when it opened, meant
-- thousands of pictures each time (a freeze of about a second as it opened, with OpenMap). Instead,
-- the masks stay on the pictures, given a plain white picture that cuts nothing (the normal map
-- looks as always), and get theirs back when Overlay Map opens again. Only the pictures OpenMap's
-- masks were taken off for room get theirs back, and lose Overlay Map's.
Zone.NEUTRAL = "Interface\\Buttons\\WHITE8X8"
function Zone.Neutral(kind)
    for _, m in pairs(masks[kind]) do
        if m.file ~= Zone.NEUTRAL then
            m:SetTexture(Zone.NEUTRAL, "CLAMP", "CLAMP")
            m.file = Zone.NEUTRAL
        end
    end
end

function Zone.Rest()
    HideRim()
    Zone.HideBare() -- (compact is off: back)
    Zone.Neutral("shape")
    Zone.Neutral("zone")
    for r, list in pairs(Zone.dropped) do
        local parent = r.GetParent and r:GetParent()
        for _, kind in ipairs({ "shape", "zone" }) do
            local m = maskedTex[kind][r]
            if m then pcall(r.RemoveMaskTexture, r, m) end
            maskedTex[kind][r] = nil
            if parent then Zone.walked[kind][parent] = nil end
        end
        while #list > 0 and AddMask(r, list[#list]) do table.remove(list) end
        if #list == 0 then Zone.dropped[r] = nil end
    end
end

-- Whether the map needs a shape mask (a plain rectangle without soft edges doesn't)
local function WantShapeMask()
    if db.style == "outlines" then return false end
    return db.style == "torn" or (db.edge or 0) >= 1 or (db.shape or "rect") ~= "rect"
end
Zone.WantShape = WantShapeMask

Zone.cost = { n = 0, ms = 0, since = 0 } -- (for /omap debug: how often the edges are laid, and the time)
-- Laying the edges can mean going through thousands of OpenMap's pictures (as the map opens, and
-- when it shows new ones). Done all at once, that froze the game for a moment; it's now spread over
-- frames, EDGE_BUDGET milliseconds each, while the map waits to fade in (Zone.walking).
Zone.EDGE_BUDGET = 4
function Zone.Breathe()
    if Zone.co and coroutine.running() == Zone.co and debugprofilestop() - Zone.sliceAt > Zone.EDGE_BUDGET then
        coroutine.yield()
    end
end
Zone.driver = CreateFrame("Frame")
Zone.driver:Hide()
function Zone.Step()
    local cost = Zone.cost
    Zone.sliceAt = debugprofilestop()
    local ok, err = coroutine.resume(Zone.co)
    cost.ms = cost.ms + debugprofilestop() - Zone.sliceAt
    if not ok then geterrorhandler()(err) end
    if coroutine.status(Zone.co) == "dead" then
        Zone.co, Zone.walking = nil, false
        Zone.driver:Hide()
        if Zone.opening and compact then ApplyOpacity() end -- (the map can fade in now)
        if Zone.again ~= nil then
            local keep = Zone.again
            Zone.again = nil
            Zone.StartEdges(keep)
        end
    end
end
Zone.driver:SetScript("OnUpdate", function() if Zone.co then Zone.Step() else Zone.driver:Hide() end end)
function Zone.StartEdges(keepZone)
    local cost = Zone.cost
    if GetTime() - cost.since > 10 then cost.n, cost.ms, cost.since = 0, 0, GetTime() end
    cost.n = cost.n + 1
    Zone.co = coroutine.create(function() Zone.ApplyEdgesNow(keepZone) end)
    Zone.walking, Zone.walkStart = true, GetTime()
    Zone.Step()
    if Zone.co then Zone.driver:Show() end
end
local function ApplyEdges(keepZone)
    if not compact then
        -- (closing: done at once, and anything half done dropped)
        Zone.co, Zone.again, Zone.walking = nil, nil, false
        Zone.driver:Hide()
        Zone.ApplyEdgesNow(keepZone)
        return
    end
    if Zone.co then
        -- (one under way: another pass after it; a full one wins over a "keep the zone" one)
        Zone.again = (Zone.again == nil) and (keepZone and true or false) or (Zone.again and keepZone and true or false)
        return
    end
    Zone.StartEdges(keepZone)
end
function Zone.ApplyEdgesNow(keepZone)
    if compact and not keepZone then Zone.UpdateZone() end
    if not compact then Zone.Rest() return end
    if db.style == "torn" then ShowRim() else HideRim() end
    local content = Canvas().Child
    for _, kind in ipairs({ "zone", "shape" }) do -- (the zone's outline first: see MaskTree)
        local on
        if kind == "shape" then on = WantShapeMask() else on = Zone.zoneNow ~= nil end
        if on then
            if content then MaskTree(content, 0, kind) end
            if kind == "shape" and Zone.DungeonViewShown() then MaskTree(Zone.DungeonView(), 0, kind) end
            -- (the map area's own pictures, under the map: a background some map addons put there
            -- showed uncut outside your zone, brown, and past the soft edges)
            local cv = Canvas()
            if cv:GetNumRegions() > 0 then
                local m = MaskFor(cv, kind)
                if m and Zone.walked[kind][cv] ~= cv:GetNumRegions() then
                    Zone.walked[kind][cv] = cv:GetNumRegions()
                    MaskRegions(cv, kind, m)
                end
            end
            if layer and layer:IsShown() then MaskTree(layer, 0, kind) end
            if viewLayer and viewLayer:IsShown() then MaskTree(viewLayer, 0, kind) end
            -- (Torn Parchment's burnt rim: faded outside your zone like the rest of the map)
            if kind == "zone" and rim and rim:IsShown() then MaskTree(rim, 0, kind) end
            -- (Outlines style: its lines and background faded outside your zone too)
            if kind == "zone" and Outline.layer and Outline.layer:IsShown() then MaskTree(Outline.layer, 0, kind) end
        elseif kind == "zone" and db.zoneBorder then
            Zone.Neutral("zone") -- (no outline for now, the whole map: kept for when there is)
        elseif next(maskedTex[kind]) then
            UnmaskKind(kind)
        end
    end
    Zone.HideBare()
end

Zone.Redraw = function() ApplyEdges(true) end

-- Laying the edges walks every picture on the map (OpenMap's are thousands), so it's done at most
-- every EDGE_GAP seconds: the map moving (Follow Me, dragging, zooming) asks for it every frame.
local edgesPending, edgesLast = false, 0
local EDGE_GAP = 0.25
local function QueueEdges()
    if edgesPending or not compact or (not WantShapeMask() and not db.zoneBorder) then return end
    edgesPending = true
    C_Timer.After(math.max(0, edgesLast + EDGE_GAP - GetTime()), function()
        edgesPending = false
        edgesLast = GetTime()
        if compact then ApplyEdges() end
    end)
end

-- OpenMap's view moved: only which zone is outlined is worked out again (ten times a second at most),
-- and the pictures are only gone through when that changes; the outline itself moves with the map.
function Zone.ViewMoved()
    if not compact or not db.zoneBorder or Zone.viewQueued then return end
    local wait = (Zone.viewAt or 0) + 0.1 - GetTime()
    if wait > 0 then
        Zone.viewQueued = true
        C_Timer.After(wait, function()
            Zone.viewQueued = false
            Zone.ViewMoved()
        end)
        return
    end
    Zone.viewAt = GetTime()
    local before, level = Zone.zoneNow, Zone.level
    Zone.UpdateZone()
    if Zone.zoneNow ~= before or Zone.level ~= level then Zone.Redraw() end
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

-- now: as the map opens, at once and even with the mouse over the map, so it opens where Follow Me
-- keeps it (it used to open where OpenMap reopens, and jump to Follow Me's view once the mouse left)
local function Follow(force, now)
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
    if hold and not now then
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
        -- (while the map zooms to fit a new zone, towards that zoom, not the one it's passing)
        local zoom = Zone.fitUntil and GetTime() < Zone.fitUntil and Zone.fitZoom or nil
        if u then u, v = Zone.Clamp(u, v, zoom) end
        if u and now then
            local om = Zone.OpenMapModule()
            local okV, _, _, z = pcall(api.GetView)
            local want = zoom or (okV and z)
            if want and om and om.ShowNow and pcall(om.ShowNow, u, v, want) then return end
        end
        if u then pcall(api.ShowWorld, u, v, zoom) end
        return
    end
    local map, c = Map(), Canvas()
    local x, y = PlayerOnMap(map:GetMapID())
    if not x or not c.SetPanTarget then return end
    if not force and lastX and math.abs(x - lastX) < 1e-4 and math.abs(y - lastY) < 1e-4 then return end
    lastX, lastY = x, y
    pcall(c.SetPanTarget, c, x, y)
end

-- Entering a new zone (with the zone border): the map zoomed so the zone fits, centred on it. With OpenMap a glide (instant as the map opens); without it, the game's
-- map shows the zone, all of it.
function Zone.Fit(zone, instant)
    if Zone.OpenMapStitched() then
        local fit = Zone.FitZoom(zone)
        local l, r, t, b = Zone.Box(zone)
        local api = _G.OpenMapAPI
        if not fit or not l then return end
        local zoom = fit * Zone.FIT_MARGIN
        local u, v = (l + r) / 2, (t + b) / 2
        Zone.fitZoom, Zone.fitUntil = zoom, GetTime() + 1
        local om = Zone.OpenMapModule()
        if instant and om and om.ShowNow and pcall(om.ShowNow, u, v, zoom) then return end
        if api.ShowWorld then pcall(api.ShowWorld, u, v, zoom) end
        return
    end
    local map, c = Map(), Canvas()
    if map:GetMapID() ~= zone then
        pcall(map.SetMapID, map, zone) -- (it opens zoomed out; Fill lays it for the map's shape)
    elseif type(c.zoomLevels) == "table" and c.zoomLevels[1] and c.InstantPanAndZoom then
        pcall(c.InstantPanAndZoom, c, c.zoomLevels[1].scale, 0.5, 0.5, true)
        C_Timer.After(0, Fill)
    end
end

-- Whether you've entered a new zone since the map last looked (the first time, only noted)
-- Your own zoom: a zoom of the map while no fit is under way (OpenMap's view, or the mouse wheel on
-- the game's map), kept against Fit Zone for Keep Your Zoom's seconds (db.keepZoomTime)
function Zone.KeepMyZoom() return db.keepZoomTime or 30 end
-- (only with the mouse over the map, as zooming yourself needs it there: OpenMap's own zoom changes, a
-- glide still finishing, or another addon's, counted as yours too, and a cave went unfitted)
function Zone.NoteZoom(z)
    if type(z) == "number" and Zone.lastZoom and math.abs(z - Zone.lastZoom) > Zone.lastZoom * 0.01
        and not (Zone.fitUntil and GetTime() < Zone.fitUntil) and not settling and Canvas():IsMouseOver() then
        Zone.zoomedAt = GetTime()
    end
    Zone.lastZoom = z
end

function Zone.CheckFit(instant)
    -- (on a flight, not each zone you fly over: the one you land in, once you land)
    if UnitOnTaxi("player") then return end
    local zone = Zone.PlayerZone()
    if not zone or zone == Zone.fittedFor then return end
    local first = Zone.fittedFor == nil
    Zone.fittedFor = zone
    if first or db.zoneFitMode == "off" or not db.zoneBorder or not Zone.Available() then return end
    -- (you zoomed the map yourself a moment ago: your zoom is kept)
    if not instant and Zone.zoomedAt and GetTime() - Zone.zoomedAt < Zone.KeepMyZoom() then return end
    Zone.Fit(zone, instant)
end

-- Caves and dungeons (Fit Caves and Dungeons): entering one, the map zooms so all of it shows.
-- * A dungeon or raid: the game shows its own map (OpenMap leaves those to the game), zoomed all the way
--   out, so the whole layout fits (and again on another floor). The game hides your position there.
-- * A cave or mine out in the world (with OpenMap, which draws them in its world): zoomed in till the
--   cave fills the view, as OpenMap lets you over a cave; walking out, back to your zone (Fit Zone) or
--   to the zoom you had.
-- Once per place you enter (your own zoom after that is kept), not on a flight. (A dungeon: not if you
-- zoomed the map yourself a moment ago (Keep Your Zoom); a cave always, as Fit Zone's pause kept it from fitting.)
Zone.CAVE_FILL = 0.9

-- OpenMap's own map of a dungeon (WoW: Forever's game has none): a frame of its own over the map area,
-- shown as the map opens inside one. Shown in Overlay Map's look too: its bar, side panel and hint
-- hidden, the markers of the world underneath kept off it, and cut to the soft edges or torn parchment.
function Zone.DungeonView()
    local v = _G.OpenMapDungeonView
    if v and v.GetParent and v:GetParent() == Canvas() and v:IsShown() then return v end
    -- (Dungeon Journal's, when it has the dungeon: OpenMap then leaves it to the journal. Its map is lent
    -- to the map window on a backdrop over the map area, which follows Overlay Map's map area)
    local ns, fdj = _G.ForeverDungeonJournal_NS, _G.ForeverDungeonJournalFrame
    local panel = fdj and fdj.dungeonMapPanel
    if ns and ns.IsWorldMapOverlayAttached and ns.IsWorldMapOverlayAttached() and panel then
        local back = panel:GetParent()
        if back and back ~= fdj and back:IsShown() then return back end
    end
    if v and v.GetParent and v:GetParent() == Canvas() then return v end
end

-- (for /omap debug: when OpenMap's dungeon map showed and hid, from the last opening)
function Zone.WatchDungeonView()
    local v = _G.OpenMapDungeonView
    if not v or Zone.dvHooked then return end
    Zone.dvHooked = true
    Zone.dvLog = Zone.dvLog or {}
    local function Note(what)
        local P = Zone.openParts
        local t = Zone.dvLog
        if #t < 12 then t[#t + 1] = string.format("%s +%.2f", what, P and (GetTime() - P.start) or -1) end
    end
    v:HookScript("OnShow", function()
        Note("shown")
        -- (tidied the moment it shows: its bar was seen for a moment before)
        if compact then
            Zone.TidyDungeonView()
            Zone.Unframe()
            Zone.dvShown, Zone.holdFor = true, nil
            ApplyOpacity()
        end
    end)
    v:HookScript("OnHide", function() Note("hidden") end)
end

function Zone.DungeonViewShown()
    local v = Zone.DungeonView()
    return v and v:IsShown() and true or false
end

function Zone.TidyDungeonView()
    local v = Zone.DungeonView()
    -- (only OpenMap's: Dungeon Journal's map keeps its floor buttons and boxes)
    if not (v and v:IsShown() and v == _G.OpenMapDungeonView) then return end
    iconLayers[v] = nil
    for _, child in ipairs({ v:GetChildren() }) do
        -- (its picture's area, and the line under it naming who drew the map, stay)
        if child ~= v.port and not (child.GetNumPoints and child:GetNumPoints() == 1 and select(2, child:GetPoint(1)) == v.port) then
            Stop(child)
        end
    end
end

-- The dungeon map's dark frame around its picture (Dungeon Journal's backdrop and its panels' borders,
-- OpenMap's dark page): made clear while Overlay Map shows it, so only the picture (its parchment) shows
-- over the world. Put back as the map closes.
Zone.unframed = {} -- object -> what it had
-- Dungeon Journal lays its map out again whenever its window opens over the map (a quest or a boss
-- clicked on it), and its frame came back: kept clear the moment it does, and the world's map under it
-- hidden or back as its dungeon map comes and goes.
-- Dungeon Journal switches to the world map on a right-click on its dungeon map (as the game's map zooms
-- out). With Click Through, a right-click over the map is turning the camera: switched back to the dungeon's
-- map at once (by its own button) when it happens that way. (Hold Shift to use the map: the right-click works.)
-- Dungeon Journal goes to the world map on a right-click on its dungeon map (Shift held with Click Through).
-- Inside a dungeon the world map is of no use: Overlay Map takes it straight back to the dungeon's map (its
-- own Dungeon Map / World Map button still switches on purpose), and every opening starts on it.
function Zone.JournalBack()
    local ns = _G.ForeverDungeonJournal_NS
    local toggle = _G.ForeverDungeonJournalWorldMapToggle
    if not (compact and ns and ns.IsWorldMapOverlayAttached and toggle and toggle:IsShown()) then return end
    if ns.IsWorldMapOverlayAttached() then return end
    Zone.journalBack = true
    toggle:Click()
    Zone.journalBack = nil
end

function Zone.WatchRightPress()
    if Zone.rightWatch then return end
    Zone.rightWatch = CreateFrame("Frame")
    pcall(Zone.rightWatch.RegisterEvent, Zone.rightWatch, "GLOBAL_MOUSE_DOWN")
    Zone.rightWatch:SetScript("OnEvent", function(_, _, button)
        if button == "RightButton" and compact then Zone.rightDownAt = GetTime() end
    end)
end

function Zone.HookJournal()
    Zone.WatchRightPress()
    local ns, fdj = _G.ForeverDungeonJournal_NS, _G.ForeverDungeonJournalFrame
    if Zone.journalHooked or not (ns and fdj) then return end
    Zone.journalHooked = true
    if type(ns.RefreshWorldMapOverlay) == "function" then
        hooksecurefunc(ns, "RefreshWorldMapOverlay", function()
            if not compact then return end
            -- (gone to the world map right after a right-click: back to the dungeon's map)
            if not Zone.journalBack and Zone.rightDownAt and GetTime() - Zone.rightDownAt < 1.5
                and ns.IsWorldMapOverlayAttached and not ns.IsWorldMapOverlayAttached() then
                Zone.rightDownAt = nil
                C_Timer.After(0, Zone.JournalBack)
            end
            if Zone.DungeonViewShown() then Zone.Unframe() else Zone.Reframe(Zone.InDungeon()) end
            ApplyOpacity() -- (the markers kept off it, at once)
        end)
    end
    for _, f in ipairs({ fdj.dungeonMapPanel, fdj.dungeonMapCanvas }) do
        if f and f.SetBackdropColor then
            local function Again(self, r, g, b, a, border)
                local saved = Zone.unframed[self]
                if Zone.reclearing or not saved or not compact or (a or 1) <= 0 then return end
                saved[border and "border" or "back"] = { r, g, b, a }
                Zone.reclearing = true
                if border then self:SetBackdropBorderColor(r, g, b, 0) else self:SetBackdropColor(r, g, b, 0) end
                Zone.reclearing = false
            end
            hooksecurefunc(f, "SetBackdropColor", function(self, r, g, b, a) Again(self, r, g, b, a, false) end)
            hooksecurefunc(f, "SetBackdropBorderColor", function(self, r, g, b, a) Again(self, r, g, b, a, true) end)
        end
    end
end

function Zone.Unframe()
    Zone.HookJournal()
    local v = Zone.DungeonView()
    if not (v and v:IsShown()) then return end
    -- (the world's map under it, which showed round the picture once its frame was clear: hidden too)
    local child = Canvas().Child
    if child and Zone.underAlpha == nil then
        Zone.underAlpha = child:GetAlpha()
        child:SetAlpha(0)
    end
    local fdj = _G.ForeverDungeonJournalFrame
    local list = { v }
    if fdj and v ~= _G.OpenMapDungeonView then
        list[#list + 1] = fdj.dungeonMapPanel
        list[#list + 1] = fdj.dungeonMapCanvas
    end
    for _, f in ipairs(list) do
        local had = f and Zone.unframed[f]
        if had then
            -- (cleared already: again, in case its addon laid it out anew)
            if had.back and f.SetBackdropColor then
                f:SetBackdropColor(had.back[1] or 0, had.back[2] or 0, had.back[3] or 0, 0)
                f:SetBackdropBorderColor(had.border[1] or 0, had.border[2] or 0, had.border[3] or 0, 0)
            end
            for r in pairs(had.tex) do r:SetAlpha(0) end
        elseif f then
            local saved = {}
            if f.GetBackdropColor and f:GetBackdrop() then
                saved.back = { f:GetBackdropColor() }
                saved.border = { f:GetBackdropBorderColor() }
                local b = saved.back
                f:SetBackdropColor(b[1] or 0, b[2] or 0, b[3] or 0, 0)
                local e = saved.border
                f:SetBackdropBorderColor(e[1] or 0, e[2] or 0, e[3] or 0, 0)
            end
            -- (plain colour fills of its own: no picture file)
            saved.tex = {}
            for _, r in ipairs({ f:GetRegions() }) do
                if r:GetObjectType() == "Texture" and (r:GetDrawLayer() == "BACKGROUND" or r:GetDrawLayer() == "BORDER") then
                    local file = r.GetTextureFilePath and r:GetTextureFilePath() or r:GetTexture()
                    if (file == nil or file == "") and r:GetAlpha() > 0 then
                        saved.tex[r] = r:GetAlpha()
                        r:SetAlpha(0)
                    end
                end
            end
            Zone.unframed[f] = saved
        end
    end
end

-- keepUnder: the world's map under it stays hidden (inside a dungeon, while its map is only lent to the
-- journal's own window for a moment: the world's map there is of no use, and it showed behind the window)
function Zone.Reframe(keepUnder)
    if Zone.underAlpha ~= nil and not keepUnder then
        local child = Canvas().Child
        if child then child:SetAlpha(Zone.underAlpha) end
        Zone.underAlpha = nil
    end
    Zone.reclearing = true -- (its own colours back: not cleared again by the hooks above)
    for f, saved in pairs(Zone.unframed) do
        if saved.back and f.SetBackdropColor then
            f:SetBackdropColor(unpack(saved.back))
            f:SetBackdropBorderColor(unpack(saved.border))
        end
        for r, a in pairs(saved.tex or {}) do r:SetAlpha(a) end
    end
    Zone.reclearing = false
    wipe(Zone.unframed)
end

-- Live minimap in dungeons (Live Minimap in Dungeons): inside an instance the game won't tell addons where
-- you are, so no map can show your arrow there. The minimap is drawn by the game itself, arrow and all, so
-- it's lent to Overlay Map's map: moved over the map area, as big as it (square), zoomed all the way out,
-- with the map's edges and opacity, its buttons hidden; the map itself hidden meanwhile. It shows the area
-- around you (the minimap's own range), not the whole dungeon. Put back exactly as it was when the map
-- closes or you leave. Started out of combat only (moving it in combat isn't safe on every client).
function Zone.WantLive()
    return compact and db.liveMinimap and Minimap and Zone.InDungeon() and not Zone.shelved
end

function Zone.LiveMinimap()
    local m = Minimap
    if not m then return end
    if Zone.live and not Zone.WantLive() then Zone.MinimapBack() return end
    if not Zone.live then
        if not Zone.WantLive() or InCombatLockdown() then return end
        local saved = { parent = m:GetParent(), points = {}, size = { m:GetSize() }, scale = m:GetScale(),
            strata = m:GetFrameStrata(), level = m:GetFrameLevel(), alpha = m:GetAlpha(), shown = m:IsShown(),
            zoom = m.GetZoom and m:GetZoom(), kids = {} }
        for i = 1, m:GetNumPoints() do saved.points[i] = { m:GetPoint(i) } end
        Zone.live = saved
        m.overlayMapLive = true
        for _, kid in ipairs({ m:GetChildren() }) do
            if kid:IsShown() and pcall(kid.Hide, kid) then saved.kids[kid] = true end
        end
        m:SetParent(UIParent)
        if m.SetZoom then pcall(m.SetZoom, m, 0) end
        m:Show()
    end
    -- (over the map area, as big as it fits; above the map. Placed
    -- on the screen from where the map area is now, and again whenever that changes: as the map first
    -- opens, the map area takes its size and place a moment after)
    -- (in the minimap's own units: it may not take UIParent's scale, which left it small and off to the side)
    local c = Canvas()
    if math.abs(m:GetScale() - 1) > 0.001 then m:SetScale(1) end
    local k = c:GetEffectiveScale() / m:GetEffectiveScale()
    local side = math.min(c:GetWidth(), c:GetHeight()) * k
    local cx, cy = c:GetCenter()
    if side > 1 and cx then
        cx, cy = cx * k, cy * k
        local key = string.format("%.1f %.1f %.1f", cx, cy, side)
        if Zone.live.placed ~= key then
            Zone.live.placed = key
            m:ClearAllPoints()
            m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
            m:SetSize(side, side)
            Zone.MinimapRedraw(0)
            Zone.live.drawn = false -- (and again once it's on screen: ApplyOpacity)
        end
    end
    -- (square, or the map's soft edges or torn parchment, as its cut; its own round one back after.
    -- Not with SexyMap, which has a shape of its own)
    local mask = WantShapeMask() and ShapeFile() or "Interface\\Buttons\\WHITE8X8"
    if Zone.live.mask ~= mask and m.SetMaskTexture and not (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)("SexyMap") then
        pcall(m.SetMaskTexture, m, mask)
        Zone.live.mask = mask
    end
    -- (Click Through: the minimap lets the mouse through too, Shift held to use it)
    local pass = db.clickThrough and not IsShiftKeyDown()
    if Zone.live.pass ~= pass then
        if Zone.live.mouse == nil then
            Zone.live.mouse = { m:IsMouseEnabled(), m.IsMouseWheelEnabled and m:IsMouseWheelEnabled() or false }
        end
        Zone.live.pass = pass
        local was = Zone.live.mouse
        pcall(m.EnableMouse, m, not pass and was[1] or false)
        pcall(m.EnableMouseWheel, m, not pass and was[2] or false)
    end
    -- (its shape is left as it is: the game has no way to read the minimap's own cut-out, and putting
    -- back a guessed one left it blank)
    local map = Map()
    m:SetFrameStrata(Above(map:GetFrameStrata()))
    m:SetFrameLevel(map:GetFrameLevel() + 4)
end

-- The game only redraws the minimap at a new size or place when its zoom changes: without this it kept
-- drawing at the old size, in a corner of its frame (and, put back, off its ring). Zoomed one step and back.
Zone.MINIMAP_ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- (the minimap's own sharp round cut-out on WoW: Forever)
function Zone.MinimapRedraw(zoom)
    local m = Minimap
    if not (m and m.SetZoom and m.GetZoomLevels) then return end
    zoom = zoom or m:GetZoom()
    local other = (zoom > 0) and (zoom - 1) or math.min(1, m:GetZoomLevels() - 1)
    pcall(m.SetZoom, m, other)
    pcall(m.SetZoom, m, zoom)
    -- (both steps in the same frame weren't always enough: in some dungeons it stayed blank until its zoom was
    -- changed by hand. Again over the next frames, each step in a frame of its own)
    Zone.redrawGen = (Zone.redrawGen or 0) + 1
    local gen = Zone.redrawGen
    C_Timer.After(0, function()
        if gen ~= Zone.redrawGen then return end
        pcall(m.SetZoom, m, other)
        C_Timer.After(0.05, function()
            if gen ~= Zone.redrawGen then return end
            pcall(m.SetZoom, m, zoom)
        end)
    end)
end

function Zone.MinimapBack()
    local m, saved = Minimap, Zone.live
    if not (m and saved) then return end
    Zone.live = nil
    m.overlayMapLive = nil
    m:SetParent(saved.parent)
    m:ClearAllPoints()
    for _, pt in ipairs(saved.points) do m:SetPoint(unpack(pt)) end
    m:SetScale(saved.scale)
    m:SetSize(saved.size[1], saved.size[2])
    m:SetFrameStrata(saved.strata)
    m:SetFrameLevel(saved.level)
    m:SetAlpha(saved.alpha)
    if saved.mask and m.SetMaskTexture then pcall(m.SetMaskTexture, m, Zone.MINIMAP_ROUND) end
    Zone.MinimapRedraw(saved.zoom)
    for kid in pairs(saved.kids) do pcall(kid.Show, kid) end
    if saved.mouse then
        pcall(m.EnableMouse, m, saved.mouse[1] and true or false)
        pcall(m.EnableMouseWheel, m, saved.mouse[2] and true or false)
    end
    if not saved.shown then m:Hide() end
    -- (turned off with the map still open: the map back in its place at once, its dungeon map laid out
    -- again and cleared, and its edges)
    if compact then
        C_Timer.After(0, function()
            if not compact or Zone.live then return end
            local fdj = _G.ForeverDungeonJournal_NS
            if fdj and fdj.RefreshWorldMapOverlay then pcall(fdj.RefreshWorldMapOverlay) end
            if Zone.DungeonViewShown() then
                Zone.TidyDungeonView()
                Zone.Unframe()
            end
            ApplyOpacity()
            wipe(Zone.walked.shape)
            wipe(Zone.walked.zone)
            ApplyEdges()
        end)
    end
end

function Zone.InDungeon()
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end

-- Where you are in OpenMap's world (normalized), if it can tell
function Zone.PlayerWorld()
    local api = _G.OpenMapAPI
    local best = C_Map.GetBestMapForUnit("player")
    if not (best and api and api.WorldFromMap) then return end
    local x, y = PlayerOnMap(best)
    if not x then return end
    return api.WorldFromMap(best, x, y)
end

-- The cave you're in (OpenMap's rect of it: left, top, right, bottom in its world), if any
-- Caves (Zone Border inside one): OpenMap's own lists of them, Blizzard's cave maps (OpenMap.MapCaves, each
-- with its outline among OpenMap's pictures: MapCave\<id>, MIT licence) and every other one as the
-- minimap draws it (OpenMap.MapCaveMinimap, cut to its box). Keys: a cave map's ID, or minus the place in
-- the minimap's list (as OpenMap keys them). Their boxes, in OpenMap's world, worked out once.
Zone.caveRects = {}
Zone.CAVE_SKIP = { [34] = true, [35] = true } -- (OpenMap's: floors of one place it doesn't show)
function Zone.CaveRectOf(key)
    if not key then return end
    local r = Zone.caveRects[key]
    if r ~= nil then return r or nil end
    local OM = _G.OpenMap
    local S = OM and OM.MapStitch
    if not (S and S.FromYards) then return end
    local c, u0, v0, u1, v1
    if key > 0 then
        c = OM.MapCaves and OM.MapCaves[key]
        if c then
            local ok1, a, b = pcall(S.FromYards, c[2], c[5], c[6])
            local ok2, d, e = pcall(S.FromYards, c[2], c[3], c[4])
            if ok1 and ok2 then u0, v0, u1, v1 = a, b, d, e end
        end
    else
        c = OM.MapCaveMinimap and OM.MapCaveMinimap[-key]
        if c then
            local ok1, a, b = pcall(S.FromYards, c[1], c[4], c[5])
            local ok2, d, e = pcall(S.FromYards, c[1], c[2], c[3])
            if ok1 and ok2 then u0, v0, u1, v1 = a, b, d, e end
        end
    end
    if u0 and u1 and v0 and v1 then
        r = { math.min(u0, u1), math.min(v0, v1), math.max(u0, u1), math.max(v0, v1) }
    else
        r = false
    end
    Zone.caveRects[key] = r
    return r or nil
end

-- The cave at a point of OpenMap's world: the biggest whose box holds it (a small piece of another
-- place's minimap can lie inside a big cave's box: picking the smallest cut the map to that piece)
function Zone.CaveKeyAt(u, v)
    local OM = _G.OpenMap
    if not OM then return end
    local best, area
    local function Try(key)
        local r = Zone.CaveRectOf(key)
        if r and u >= r[1] and u <= r[3] and v >= r[2] and v <= r[4] then
            local a = (r[3] - r[1]) * (r[4] - r[2])
            if not area or a > area then best, area = key, a end
        end
    end
    for id in pairs(OM.MapCaves or {}) do
        if not Zone.CAVE_SKIP[id] then Try(id) end
    end
    for i in ipairs(OM.MapCaveMinimap or {}) do Try(-i) end
    return best
end

-- A cave's outline: OpenMap's picture of a cave map's shape (soft-edged already), or, for a cave the
-- minimap draws, its own shape from the Zone Borders download (made from the minimap's pictures of it,
-- found by its box, as OpenMap may number its caves differently in another version); without one, its
-- box (soft-edged with Soft Border)
function Zone.CaveShape(key, list)
    list = list or _G.OverlayMap_ZoneBordersCaves
    local c = list and _G.OpenMap and _G.OpenMap.MapCaveMinimap and _G.OpenMap.MapCaveMinimap[-key]
    if not c then return end
    local function R(v) return math.floor((tonumber(v) or 0) + 0.5) end
    local n = list[string.format("%d %d %d %d %d", R(c[1]), R(c[2]), R(c[3]), R(c[4]), R(c[5]))]
    if n then return n end
    -- (a box a few yards off, from another OpenMap version: the nearest one on the same continent)
    local best, gap
    for box, i in pairs(list) do
        local t, k = {}, 0
        for v in box:gmatch("%-?%d+") do k = k + 1 t[k] = tonumber(v) end
        if t[1] == R(c[1]) then
            local d = math.max(math.abs(t[2] - c[2]), math.abs(t[3] - c[3]), math.abs(t[4] - c[4]), math.abs(t[5] - c[5]))
            if d <= 8 and (not gap or d < gap) then best, gap = i, d end
        end
    end
    return best
end

function Zone.CaveFile(zone)
    local key = tonumber(zone:match("^cave(%-?%d+)$"))
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    if key and key > 0 and S and S.CaveMasks then return S.CaveMasks .. key end
    local n = key and key < 0 and Zone.CaveShape(key)
    if n then return "Interface\\AddOns\\" .. Zone.ADDON .. "\\Cave\\" .. n .. (db.zoneSoft and "s" or "") end
    -- (sharp: a plain box of Overlay Map's own, big enough that its cut has no soft rim; the game's small
    -- white square faded over a sixteenth of the box at each edge, a glow round the cave)
    return MEDIA .. (db.zoneSoft and "Edge2" or "Box")
end

-- The cave you're in: its box (left, top, right, bottom) and key; Zone.caveKey keeps the key
function Zone.CaveHere()
    Zone.caveKey = nil
    if not (IsIndoors and IsIndoors()) or not Zone.OpenMapStitched() then return end
    local u, v = Zone.PlayerWorld()
    if not u then return end
    local key = Zone.CaveKeyAt(u, v)
    local r = key and Zone.CaveRectOf(key)
    if r then
        Zone.caveKey = key
        return r[1], r[2], r[3], r[4], key
    end
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    if not (S and S.CaveRectAt) then return end
    local ok, u0, v0, u1, v1 = pcall(S.CaveRectAt, u, v)
    if ok and type(u0) == "number" and u1 > u0 and v1 > v0 then return u0, v0, u1, v1 end
end

-- OpenMap's zoom at which a part of its world (left, right, top, bottom) just fits the view
function Zone.ZoomForBox(l, r, t, b)
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    local c = Canvas()
    if not (S and S.Size and c) then return end
    local okS, W, H = pcall(S.Size)
    local cw, ch = c:GetWidth(), c:GetHeight()
    if not okS or type(W) ~= "number" or type(H) ~= "number" or W <= 0 or H <= 0 or cw <= 0 or ch <= 0 then return end
    local z = math.min(cw / ((r - l) * W), ch / ((b - t) * H)) / math.min(cw / W, ch / H)
    if z > 0 and z < math.huge then return z end
end

-- OpenMap's view to (u, v) at a zoom: at once (opening) or a glide
function Zone.ViewTo(u, v, zoom, instant)
    Zone.fitZoom, Zone.fitUntil = zoom, GetTime() + 1 -- (Follow Me heads for this zoom meanwhile)
    local om = Zone.OpenMapModule()
    if instant and om and om.ShowNow and pcall(om.ShowNow, u, v, zoom) then return end
    pcall(_G.OpenMapAPI.ShowWorld, u, v, zoom)
end

function Zone.FitDungeon(id)
    -- (only a dungeon map of the game's own: WoW: Forever has none, and OpenMap shows its own dungeon
    -- maps, which fit themselves; changing the map under it showed the zone outside instead)
    if OpenMapLoaded() then return end
    local info = id and C_Map.GetMapInfo(id)
    if not (info and Enum and Enum.UIMapType and (info.mapType == Enum.UIMapType.Dungeon
        or info.mapType == Enum.UIMapType.Micro)) then return end
    local map = Map()
    if map:GetMapID() ~= id then pcall(map.SetMapID, map, id) end
    C_Timer.After(0, function()
        local c = Canvas()
        if compact and type(c.zoomLevels) == "table" and c.zoomLevels[1] and c.InstantPanAndZoom then
            pcall(c.InstantPanAndZoom, c, c.zoomLevels[1].scale, 0.5, 0.5, true)
        end
    end)
end

function Zone.FitCave(u0, v0, u1, v1, instant)
    local okV, _, _, z = pcall(_G.OpenMapAPI.GetView)
    if not Zone.beforeCave and okV and type(z) == "number" then Zone.beforeCave = z end
    local fit = Zone.ZoomForBox(u0, u1, v0, v1)
    if Zone.caveNote then Zone.caveNote.from, Zone.caveNote.ask = okV and z, fit and fit * Zone.CAVE_FILL end
    if fit then Zone.ViewTo((u0 + u1) / 2, (v0 + v1) / 2, fit * Zone.CAVE_FILL, instant) end
    -- (for /omap debug: the zoom OpenMap actually took, a moment later)
    C_Timer.After(1.2, function()
        local ok2, _, _, z2 = pcall(_G.OpenMapAPI.GetView)
        if Zone.caveNote then Zone.caveNote.got = ok2 and z2 end
    end)
end

function Zone.LeaveCave(instant)
    local before = Zone.beforeCave
    Zone.beforeCave = nil
    local zone = Zone.PlayerZone()
    if db.zoneBorder and db.zoneFitMode ~= "off" and zone and Zone.Available() then
        Zone.Fit(zone, instant)
        return
    end
    local u, v = Zone.PlayerWorld()
    if before and u then Zone.ViewTo(u, v, before, instant) end
end

-- force: as the map opens with Fit Zone on each opening, the cave fitted again over the zone
function Zone.CheckPlaces(instant, force)
    if not db.fitPlaces or UnitOnTaxi("player") then return end
    local mine = not instant and Zone.zoomedAt and GetTime() - Zone.zoomedAt < Zone.KeepMyZoom()
    if Zone.InDungeon() then
        Zone.caveFor, Zone.beforeCave = nil, nil
        local id = C_Map.GetBestMapForUnit("player") or Map():GetMapID()
        if id and id ~= Zone.dungeonFor then
            Zone.dungeonFor = id
            if not mine then Zone.FitDungeon(id) end
        end
        return
    end
    Zone.dungeonFor = nil
    if not Zone.OpenMapStitched() then return end
    local u0, v0, u1, v1 = Zone.CaveHere()
    if u0 then
        local key = string.format("%.5f %.5f", u0, v0)
        if key ~= Zone.caveFor or force then
            Zone.caveFor = key
            -- (fitted even after a zoom of your own, with the Zone Border or without)
            mine = false
            Zone.caveNote = { at = GetTime(), mine = mine and true or false, instant = instant and true or false,
                size = string.format("%.5f x %.5f", u1 - u0, v1 - v0) }
            if not mine then Zone.FitCave(u0, v0, u1, v1, instant) end
        end
    elseif Zone.caveFor then
        Zone.caveFor = nil
        -- (back out even after a zoom of your own inside, as going in)
        mine = false
        if not mine then Zone.LeaveCave(instant) end
    end
end

local edgeSweeps = 0
local Watch -- (below)
local ApplyClickThrough, ApplyOnlyMe, ApplyMarkerSize, ApplyArrow -- (further down)
watcher:SetScript("OnUpdate", function(self, elapsed)
    if not compact then self:Hide(); return end
    if Zone.openParts and GetTime() - Zone.openParts.start < 1.5 and elapsed > (Zone.worstFrame or 0) then
        Zone.worstFrame = elapsed
    end
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
    if not settling then Zone.CheckFit() end
    if Zone.live then Zone.LiveMinimap() end -- (kept over the map area; cheap when nothing moved)
    if not reshaping and not Keep.sizing and math.abs(Canvas():GetScale() - WantScale()) > 0.001 then ApplySize() end -- (also a new screen size)
    -- (a fade left half-way, which nothing is finishing: the map shown again)
    -- (the map fades in once its edges are laid, or after a second whatever happens)
    if not reshaping and not settling and transition < 1 and not fader:IsShown()
        and (not Zone.walking or GetTime() - (Zone.walkStart or 0) > 1) then FadeTo(1, 0.2) end
    -- (the markers' click through, Show only my arrow and size: each kept by hooks the moment the game or an
    -- addon changes them; gone through again for new markers, and once a second)
    local fresh = Keep.markersDirty
    ApplyOpacity()
    if slow or fresh then
        Keep.markersDirty = false
        if db.clickThrough then ApplyClickThrough() end
        ApplyOnlyMe()
        ApplyMarkerSize()
    end
    if not slow then return end
    if not settling then
        -- (caves and dungeons, once a second; whether you're in a cave, for the zone border)
        local before = Zone.caveKey
        local cave = Zone.CaveHere() ~= nil
        if cave ~= (Zone.inCave or false) or Zone.caveKey ~= before then
            Zone.inCave = cave
            if db.zoneBorder then ApplyEdges() end
        end
        if db.style == "outlines" then Outline.Place() end -- (into or out of a cave: its lines)
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
            ApplyOpacity()
            QueueEdges()
        end
    end
    CoverScreen() -- (in case the game's window layout moved it back)
    if not Zone.shelved then -- (closed in combat: the interface is back meanwhile)
        HideExtras()
        if db.hideMinimap then HideMinimap() end
    end
    ApplyArrow()
    if mapButton and mapButton:IsShown() then PlaceMapButton() end -- (the map grew past the screen)
    -- (once a second, for anything the events missed; every five, the lists of children read again,
    -- for any swapped one for one)
    edgeSweeps = edgeSweeps + 1
    if edgeSweeps % 5 == 0 then Zone.ForgetWalked() end
    ApplyEdges()
end

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

Zone.passNoHover = setmetatable({}, { __mode = "k" })
local function PassFrames()
    local c = Canvas()
    local list = { c }
    if c.Child then list[#list + 1] = c.Child end
    for f in pairs(iconLayers) do list[#list + 1] = f end
    -- (the dungeon maps too, Dungeon Journal's and OpenMap's: with Click Through they let the mouse through
    -- like the rest of the map; Shift held gives it back, and a right-click then goes back to the world map,
    -- as they intend)
    local fdj = _G.ForeverDungeonJournalFrame
    local back = fdj and fdj.dungeonMapPanel and fdj.dungeonMapPanel:GetParent()
    local pieces = { _G.OpenMapDungeonView or false }
    if fdj and back and back ~= fdj then
        for _, f in ipairs({ back, fdj.dungeonMapPanel, fdj.dungeonMapCanvas or false, fdj.dungeonMapArtHolder or false }) do
            pieces[#pieces + 1] = f
        end
    end
    for _, f in ipairs(pieces) do
        if f and f.IsMouseClickEnabled then
            Zone.passNoHover[f] = true
            list[#list + 1] = f
        end
    end
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
            for _, child in ipairs(Zone.Children(f)) do Walk(child, depth - 1) end
        end
    end
    for _, pool in pairs(Map().pinPools or {}) do
        if pool.EnumerateActive then
            for pin in pool:EnumerateActive() do Walk(pin, 2) end
        end
    end
    for f in pairs(iconLayers) do
        for _, child in ipairs(Zone.Children(f)) do Walk(child, 2) end
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
                if Zone.passNoHover[f] then
                    -- (a dungeon's map: no hover either, nothing on it needs it there)
                    if f:IsMouseMotionEnabled() then pcall(f.SetMouseMotionEnabled, f, false) end
                elseif not f:IsMouseMotionEnabled() and not (iconLayers[f] and not passSaved[f][2]) then
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
        for _, child in ipairs(Zone.Children(f)) do HideMarkerTree(child, depth - 1) end
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
        for _, child in ipairs(Zone.Children(f)) do
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
        for _, child in ipairs(Zone.Children(f)) do
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

local Arrow = {}
-- My arrow: its own size and opacity, when chosen (My Arrow's Own Size). With OpenMap's map it's
-- OpenMap's own arrow (a picture on its icon layer); otherwise the game's, drawn by the group
-- members' marker, whose size for the player is set on it (its opacity is the whole marker's, so
-- the party's dots take it too). Put back as it was on close.
Arrow.arrowBase = setmetatable({}, { __mode = "k" })    -- arrow picture or marker -> its own size
Arrow.arrowHooked = setmetatable({}, { __mode = "k" })
Arrow.arrowApplied = setmetatable({}, { __mode = "k" })   -- marker -> the size factor last set on it
Arrow.arrowSetting = false

function Arrow.ArrowWant()
    if compact and db.arrowCustom then return db.arrowSize or 1, db.arrowOpacity or 1 end
    return 1, 1
end

function Arrow.OpenMapArrow()
    local a = Zone.arrowFrame
    if a and a:GetParent() == Zone.arrowLayer then
        for _, r in ipairs({ a:GetRegions() }) do
            if r:GetObjectType() == "Texture" then return r end
        end
    end
    for f in pairs(iconLayers) do
        for _, child in ipairs(Zone.Children(f)) do
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
    local k, a = Arrow.ArrowWant()
    local tex = Arrow.OpenMapArrow()
    if tex then
        if not Arrow.arrowBase[tex] then
            if k == 1 and a == 1 then tex = nil else Arrow.arrowBase[tex] = tex:GetWidth() end
        end
        if tex then
            local want = Arrow.arrowBase[tex] * k
            if math.abs(tex:GetWidth() - want) > 0.01 then tex:SetSize(want, want) end
            if math.abs(tex:GetAlpha() - a) > 0.001 then tex:SetAlpha(a) end
            if k == 1 and a == 1 then Arrow.arrowBase[tex] = nil end
        end
    end
    local pool = Map().pinPools and Map().pinPools.GroupMembersPinTemplate
    if not (pool and pool.EnumerateActive) then return end
    for pin in pool:EnumerateActive() do
        if pin.SetPinSize then
            if not Arrow.arrowHooked[pin] then
                Arrow.arrowHooked[pin] = true
                -- (the game sets the player's size again now and then: noted as its own, ours on top)
                hooksecurefunc(pin, "SetPinSize", function(self, unit, size)
                    if Arrow.arrowSetting or unit ~= "player" or type(size) ~= "number" then return end
                    Arrow.arrowBase[self] = size
                    local kk = Arrow.ArrowWant()
                    if kk ~= 1 then
                        Arrow.arrowSetting = true
                        pcall(self.SetPinSize, self, "player", size * kk)
                        Arrow.arrowSetting = false
                    end
                end)
                if pin.UpdateAppearanceData then pcall(pin.UpdateAppearanceData, pin) end
            end
            local base = Arrow.arrowBase[pin]
            if base and Arrow.arrowApplied[pin] ~= k then
                Arrow.arrowApplied[pin] = k
                Arrow.arrowSetting = true
                pcall(pin.SetPinSize, pin, "player", base * k)
                Arrow.arrowSetting = false
            end
        end
        if math.abs(pin:GetAlpha() - a) > 0.001 then pin:SetAlpha(a) end
    end
end

local UpdateMapButton -- (the options button on the map, further down)

ApplyLook = function()
    Keep.pinsDirty, Keep.markersDirty = true, true -- (all the markers gone through again)
    Zone.CheckDownload() -- (Zone Border chosen without its download ready: asked, or told, at once)
    Outline.CheckDownload() -- (the same for the Outlines style)
    if not compact then return end
    local map = Map()
    ApplyMarkerSize()
    ApplySize()
    Zone.LiveMinimap()
    ApplyOpacity()
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
    ApplyEdges()
    ApplyClickThrough()
    ApplyOnlyMe()
    ApplyArrow()
    UpdateMapButton()
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
        if not z.openmap then return end
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
    if not compact then return end
    Zone.Unshelve(false)
    Zone.Reframe() -- (the dungeon map's frame, as it was)
    Zone.MinimapBack() -- (the minimap back in its corner, if it was lent to the map)
    StopFade()
    SaveZoom()
    compact = false
    Zone.Reset(true) -- (the outlines' pictures stay loaded for next time)
    Zone.lastZoom, Zone.zoomedAt = nil, nil -- (your own zoom counts only while the map is open)
    local map = Map()
    RevealAll()
    ShowMinimap()
    ShowExtras()
    ShowNames()
    Zone.Rest() -- (the masks stay on, cutting nothing: see Zone.Rest)
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
    -- (closed in combat, so only made invisible: shown again)
    if map and compact and Zone.shelved then Zone.Unshelve(true) return end
    if not map or compact then return end
    Zone.opening = GetTime()
    local t0 = debugprofilestop()
    if map:IsShown() then return end -- already open the normal way: leave it alone
    if Blocked() then return end

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
    if small then
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
        return
    end

    -- (the first time: the map area's size without the quest log the small map shows beside it, so
    -- Size and Width mean the same as before; the log is hidden while Overlay Map shows the map)
    if not Zone.orig then Zone.orig = Zone.Measure(map) end

    compact = true
    before.alpha = map:GetAlpha()
    -- The map frame stays its full size around the smaller map area; it must not take clicks.
    before.mouse = map:IsMouseEnabled()
    if before.mouse then map:EnableMouse(false) end
    settling = true
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
        if not compact then return end
        local tl = debugprofilestop()
        ApplyLook()
        P.look = debugprofilestop() - tl
    end)
    watchAcc = 0
    lastX, lastY = nil, nil
    watcher:Show()
    Zone.openMs = debugprofilestop() - t0
    -- The game's window layout and other map addons may still change things during the next
    -- frames: hide and apply everything once more, then show the map.
    C_Timer.After(0.05, function()
        if not compact then return end
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
        Zone.inCave = Zone.CaveHere() ~= nil -- (in a cave: no zone outline, see Zone.MaskZone)
        -- (inside a dungeon: Dungeon Journal's map, even if it was left on the world map last time)
        if Zone.InDungeon() then
            Zone.HookJournal()
            Zone.JournalBack()
        end
        RestoreZoom()
        if db.zoneBorder and db.zoneFitMode == "open" and Zone.PlayerZone() then
            Zone.fittedFor = Zone.PlayerZone()
            Zone.Fit(Zone.fittedFor, true) -- (every time: fitted to your zone)
        else
            Zone.CheckFit(true) -- (a new zone since it last closed: fitted to it instead)
        end
        -- (in a cave or a dungeon: fitted to it, over the zone)
        Zone.CheckPlaces(true, db.zoneBorder and db.zoneFitMode == "open")
        -- (Follow Me: the view where it keeps it, from the start)
        if db.follow then
            lastX, lastY = nil, nil
            Follow(true, true)
        end
        P2.zoom = debugprofilestop() - tm2
        settling = false
        tm2 = debugprofilestop()
        ApplyLook()
        P2.look2 = debugprofilestop() - tm2
        Zone.openMs2 = debugprofilestop() - t1
        -- The map and other addons finish setting up their frames' mouse while it opens; the
        -- click-through is laid again from scratch on top of that.
        C_Timer.After(0.1, function()
            local tm3 = debugprofilestop()
            if compact then ApplyClickThrough(true) end
            -- (OpenMap's dungeon map, opened by now inside a dungeon: tidied and its markers off)
            Zone.holdFor = nil -- (its dungeon map tidied by now, if it's up: the map can fade in)
            if compact and Zone.DungeonViewShown() then
                Zone.TidyDungeonView()
                Zone.Unframe()
                Zone.dvShown = true
                ApplyOpacity()
                QueueEdges()
            end
            P2.click = debugprofilestop() - tm3
        end)
    end)
end

-- In combat the game doesn't let an addon hide the map while it holds a protected marker (your group's):
-- closing it then left it open, and Overlay Map handed it back to the game, so the normal map with its
-- border showed up. Now it's kept open but invisible, without the mouse, and closed as combat ends; the
-- key shows it again meanwhile.
function Zone.Shelve()
    if Zone.shelved then return end
    Zone.shelved = true
    local c = Canvas()
    Zone.shelfMouse = { c:IsMouseEnabled(), c.IsMouseWheelEnabled and c:IsMouseWheelEnabled() or false }
    pcall(c.EnableMouse, c, false)
    pcall(c.EnableMouseWheel, c, false)
    Zone.MinimapBack()
    ApplyOpacity()
    if mapButton then mapButton:Hide() end
    if panel then panel:Hide() end
    -- (what's hidden while the map is open comes back, as if it had closed)
    ShowMinimap()
    ShowExtras()
end

-- show: back on screen (the key pressed again); otherwise only its mouse back (it's being closed)
function Zone.Unshelve(show)
    if not Zone.shelved then return end
    Zone.shelved = false
    local c, m = Canvas(), Zone.shelfMouse
    Zone.shelfMouse = nil
    if m then
        pcall(c.EnableMouse, c, m[1] and true or false)
        pcall(c.EnableMouseWheel, c, m[2] and true or false)
    end
    if show and compact then ApplyLook() end
end

local function Close()
    if not compact then return end
    local map = Map()
    if InCombatLockdown() and map:IsProtected() then Zone.Shelve() return end
    if HideUIPanel then HideUIPanel(map) else map:Hide() end
    if map:IsShown() and InCombatLockdown() then Zone.Shelve() return end -- (refused without a word)
    Zone.Unshelve(false)
    Restore() -- in case hiding did not reach the OnHide hook
end

function OverlayMap_OnKey(keystate)
    if not db or not Map() then return end
    -- (the setup wizard keeps the map open behind it: the key only shows it at full strength, held
    -- or pressed as chosen, instead of opening and closing it)
    if Wizard.frame and Wizard.frame:IsShown() and compact then
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
        if compact then Close() else Open() end
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
            if compact then Zone.zoomedAt = GetTime() end
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
            if compact and Zone.shown then Zone.PlaceZoneAnchor(Zone.shown) end
            if compact and db.style == "outlines" then Outline.Place() end
        end)
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
            if compact then
                QueueEdges()
                Keep.pinsDirty, Keep.markersDirty = true, true -- (a new marker: gone through at the next upkeep)
            end
            if not compact or pending or not (layer and layer:IsShown()) then return end
            pending = true
            C_Timer.After(0, function()
                pending = false
                Keep.pinsDirty, Keep.markersDirty = true, true
                if compact then ApplyOpacity() end
            end)
        end)
    end
    -- Another zone shown while Overlay Map shows the map: fill the shape again.
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function()
            if compact then
                C_Timer.After(0, Fill)
                -- (a zone border follows the map shown: at once, as OpenMap changes the map under
                -- its view while it moves, or the outline is a frame behind, out of place)
                if db.zoneBorder then ApplyEdges() end
                if db.style == "outlines" then Outline.Place() end
                QueueEdges()
            end
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
        Say("In full-screen overlay the map fills the whole screen: turn it off to move the map.")
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
local STYLE_CHOICES = { { "standard", "Standard" }, { "torn", "Torn parchment" }, { "outlines", "Outlines (beta)" } }
local function StandardStyle() return db.style == "standard" end
local function OutlineStyle() return db.style == "outlines" end

local function Round(v, step) return math.floor(v / step + 0.5) * step end

-- Size and width from the panel wait for its Apply button (changing them is a whole new layout
-- of the map); key -> value chosen, not applied yet
local pending = {}

-- Applies a new size or width with the map hidden for a moment, so the new layout isn't seen
-- being worked out.
-- The map fades out, is laid out again while hidden (OpenMap and the game take a few frames to
-- settle), and fades back in.
local function ApplyShape(refit)
    if not compact then return end
    Zone.refitAgain = nil
    shapeGen = shapeGen + 1
    local gen = shapeGen
    reshaping = true
    if refitTimer then refitTimer:Cancel() refitTimer = nil end
    FadeTo(0, 0.12, function()
        if gen ~= shapeGen then return end
        if not compact then StopFade() return end
        -- (with OpenMap: the view kept where it was, with the land the same size on screen; OpenMap
        -- keeps its zoom number, which in a wider area made the land bigger)
        local view
        if Zone.OpenMapStitched() then
            local ok, u, v, z = pcall(_G.OpenMapAPI.GetView)
            if ok and type(u) == "number" and type(z) == "number" then view = { u, v, z, Zone.FitPx() } end
        end
        settling = true
        ApplyLook()      -- (the map re-fits at once while it's hidden)
        if refit then RefitNow() end
        C_Timer.After(0.15, function()
            if gen ~= shapeGen then return end
            if not compact then StopFade() return end
            local fit = Zone.FitPx()
            if view and view[4] and fit then
                local om = Zone.OpenMapModule()
                local zoom = view[3] * view[4] / fit
                if not (om and om.ShowNow and pcall(om.ShowNow, view[1], view[2], zoom)) then
                    pcall(_G.OpenMapAPI.ShowWorld, view[1], view[2], zoom)
                end
            end
            settling = false
            reshaping = false
            ApplyLook()
            FadeTo(1, 0.2)
            -- (the width changed again meanwhile: once more)
            if Zone.refitAgain then
                Zone.refitAgain = nil
                QueueRefit()
            end
        end)
    end)
end
Zone.Reshape = ApplyShape

-- Overlay mode: one switch that makes the map fill the whole screen (FullScreen: size, width and
-- place come from the screen while it's on). It keeps its own look, apart from the normal map's:
-- the settings below are swapped when it's turned on or off, so a change made in one mode stays in
-- that mode. The other mode's values wait in the saved settings (beforeOverlay: the normal map's,
-- while Overlay Mode is on; overlaySet: Overlay Mode's, while it's off).
local OVERLAY_KEYS = { "opacity", "pinOpacity", "markerSize", "arrowCustom", "arrowSize", "arrowOpacity", "style",
    "edge", "shape", "zoneBorder", "zoneSoft", "zoneDim", "clickThrough", "noFade", "outlineLines", "outlineBack" }
-- Overlay Mode the first time it's turned on: see-through, solid markers, large soft edges,
-- click-through (the rest as the normal map has them)
local OVERLAY_START = { opacity = 0.3, pinOpacity = 1, edge = 3, clickThrough = true, noFade = true }

local RefreshPanel -- (further down)
-- The small panel and the main options read the settings again (an option may grey out or show others)
function Keep.RefreshAll()
    if RefreshPanel then RefreshPanel() end
    if Keep.RefreshOptions then Keep.RefreshOptions() end
end

-- Zone Border on, but its download not ready: off in the AddOns list, a window asks to turn it on
-- and reload (Zone Border stays off unless that's accepted); not installed, it's turned off and
-- said where to get it. Asked once a session.
StaticPopupDialogs.OVERLAYMAP_ZONEBORDERS = {
    text = "Zone borders need \"Overlay Map: Zone Borders\", which is turned off in your AddOns list.\n\n"
        .. "Turn it on and reload the interface?",
    button1 = "Turn on and reload",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        -- (as the AddOns list does: turned on, for this character and for all, then saved, which
        -- the reload alone doesn't do)
        Zone.EnableAndReload(Zone.ADDON, function() db.zoneBorder = true end)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Zone.EnableAndReload(addon, before)
    local api = C_AddOns or {}
    local Enable = api.EnableAddOn or EnableAddOn
    if Enable then
        pcall(Enable, addon, UnitName("player"))
        pcall(Enable, addon)
    end
    local Save = api.SaveAddOns or SaveAddOns
    if Save then pcall(Save) end
    if before then before() end
    ReloadUI()
end

-- The Outlines style's pictures are a separate download too (Overlay Map: Outlines), asked for the
-- same way: off in the AddOns list, a window to turn it on and reload; not installed, the style goes
-- back to Standard and it's said where to get it.
StaticPopupDialogs.OVERLAYMAP_OUTLINES = {
    text = "The Outlines style needs \"Overlay Map: Outlines\", which is turned off in your AddOns list.\n\n"
        .. "Turn it on and reload the interface?",
    button1 = "Turn on and reload",
    button2 = CANCEL or "Cancel",
    OnAccept = function() Zone.EnableAndReload(Outline.ADDON, function() db.style = "outlines" end) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Outline.CheckDownload()
    if db.style ~= "outlines" or Outline.available then return end
    local api = C_AddOns or {}
    local status = Zone.Status(Outline.ADDON)
    if status == "ready" then
        local Load = api.LoadAddOn or LoadAddOn
        if Load then pcall(Load, Outline.ADDON) end
        status = Zone.Status(Outline.ADDON)
    end
    if status == "loaded" then Outline.available = true return end
    if Outline.styleSetting and Outline.styleSetting.SetValue then
        pcall(Outline.styleSetting.SetValue, Outline.styleSetting, "standard")
    end
    db.style = "standard"
    Keep.RefreshAll()
    if status == "disabled" then
        StaticPopup_Show("OVERLAYMAP_OUTLINES")
    else
        Zone.Tell("The Outlines style needs the \"Overlay Map: Outlines\" addon, a separate download (from "
            .. "where you got Overlay Map). Install it next to Overlay Map and restart the game.")
    end
end

function Zone.SetBorderOff()
    if Zone.borderSetting and Zone.borderSetting.SetValue then
        pcall(Zone.borderSetting.SetValue, Zone.borderSetting, false)
    end
    db.zoneBorder = false
    Keep.RefreshAll()
end

function Zone.CheckDownload()
    if not db.zoneBorder or Zone.available then return end
    local status = Zone.Status()
    if status == "loaded" or status == "ready" then return end -- (loaded when the outline is wanted)
    Zone.SetBorderOff()
    if status == "disabled" then
        StaticPopup_Show("OVERLAYMAP_ZONEBORDERS")
    elseif not Zone.told then
        Zone.told = true
        Zone.Tell("Zone borders need the \"Overlay Map: Zone Borders\" addon, a separate download (from where "
            .. "you got Overlay Map). Install it next to Overlay Map and restart the game.")
    end
end

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
    Keep.RefreshAll()
    if compact then ApplyShape() end
end

-- Each option's line of help, shown when hovering it in the small panel and the setup wizard
Keep.TIPS = {
    overlay = "The map fills the whole screen, see-through and click-through. It keeps settings of its own.",
    scale = "Size of the map. Applied when you let go of the slider.",
    width = "Width of the map compared to its usual shape (lower: more square). Applied when you let go.",
    opacity = "How see-through the map itself is. At 0%, only the markers show.",
    pinOpacity = "How see-through the markers are: quests, vendors, your arrow and other addons' icons.",
    markerSize = "Size of the markers, Questie's and OpenMap's icons too.",
    onlyMe = "Hides every marker except your own arrow.",
    style = "Standard, Torn parchment (torn, burnt paper edges) or Outlines (white lines of cliffs, water and roads; needs the Overlay Map: Outlines download).",
    edge = "The map fades out towards its edges, like other games' overlay maps. Standard style only.",
    shape = "The shape the map's edges fade into. With \"Fade at the edges\" off, it's cut sharp in that shape.",
    outlineLines = "How strong the white lines are.",
    outlineBack = "How dark the background behind the lines is. At 0%, only the lines.",
    zoneBorder = "Cuts the map to your zone's outline (inside a cave, to the cave's).",
    zoneSoft = "The zone fades in from its border, instead of a sharp cut.",
    zoneDim = "How much of the map outside your zone shows. At 0% it's hidden.",
    zoneFitMode = "Zooms the map so all of your zone fits: when you enter a zone, or also each time the map opens.",
    clickThrough = "Clicks go through the map to the world. Hold Shift to drag and zoom the map.",
    follow = "Keeps the map centred on you as you move. It holds still while the mouse is over the map.",
    fitPlaces = "Entering a cave or mine, the map zooms in on it, and back out as you leave.",
    liveMinimap = "Inside dungeons, the game's own minimap (with your arrow) shown big in the map's place.",
    mode = "Hold to show: the map shows while you hold the key. Toggle: one press shows it, the next hides it.",
}

-- A tooltip on a control (its text: the option's line of help, or `text`)
function Keep.Tip(frame, key, text)
    frame:HookScript("OnEnter", function(self)
        local tip = (frame.offTip and frame.IsEnabled and not frame:IsEnabled() and frame.offTip) or text or Keep.TIPS[key]
        if not tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Size and Width from a slider: laid out again (with the fade) once you let go, or a moment after the
-- last turn of the mouse wheel, instead of on every step
function Keep.ShapeSoon(delay)
    if Keep.shapeTimer then Keep.shapeTimer:Cancel() end
    Keep.shapeTimer = C_Timer.NewTimer(delay or 0, function()
        Keep.shapeTimer = nil
        Keep.sizing = nil
        if compact then Zone.Reshape() end
    end)
end

-- The small panel. Its options are on four tabs (Map, Look, Zone, Behavior), and rows that don't apply
-- right now aren't shown (Size and Width in Overlay Mode, the Outlines style's sliders with another
-- style). The panel keeps the height of its tallest tab, so it doesn't jump as you switch.
-- A plain slider: label on the left, value on the right, the bar under them. reshape: Size and Width,
-- laid out again once you let go (Keep.ShapeSoon)
-- (fmt: how its value reads, a percentage if none; parent.enabledIf: greyed out while it says no)
local function PanelSlider(parent, key, label, minValue, maxValue, step, reshape, fmt)
    local function Show(fs, v) fs:SetText(fmt and fmt(v) or string.format("%d%%", v * 100 + 0.5)) end
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 12, 0)
    text:SetText(label)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPRIGHT", -12, 0)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 12, -19)
    s:SetPoint("TOPRIGHT", -12, -19)
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
        Show(value, v)
        if self.silent then return end
        if math.abs((db[key] or 0) - v) < 0.0001 then return end
        db[key] = v
        if reshape then
            Keep.sizing = true -- (not laid out meanwhile: Watch)
            -- (dragging: once you let go; the mouse wheel: a moment after the last turn)
            if not IsMouseButtonDown("LeftButton") then Keep.ShapeSoon(0.4) end
            return
        end
        ApplyLook()
    end)
    if reshape then s:SetScript("OnMouseUp", function() Keep.ShapeSoon(0) end) end
    Keep.Tip(s, key)
    function parent:Refresh()
        pending[key] = nil
        s.silent = true
        s:SetValue(db[key])
        s.silent = false
        Show(value, db[key])
        local on = not parent.enabledIf or parent.enabledIf()
        if on then s:Enable() else s:Disable() end
        s:SetAlpha(on and 1 or 0.4)
        text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
        value:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
    end
end

-- enabledIf: greyed out while it says no, with offLabel and offTip (hovered) saying why
local function PanelCheck(parent, key, label, enabledIf, offLabel, offTip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 8, 0)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb.offTip = offTip
    cb:SetMotionScriptsWhileDisabled(true)
    Keep.Tip(cb, key)
    cb:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        SyncOverlay()
        ApplyLook()
        Keep.RefreshAll() -- (rows may show or go with it)
        if Wizard.Changed then Wizard.Changed(key) end
    end)
    function parent:Refresh()
        local cond = enabledIf or parent.enabledIf
        local on = not cond or cond()
        cb:SetEnabled(on)
        cb:SetChecked(on and db[key] and true or false)
        text:SetText(on and label or (offLabel or label))
        text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
    end
end

-- A choice among a few: "< Label: Choice >", the arrows (or a click on the text) stepping through them
local function PanelCycle(parent, key, label, choices, enabledIf)
    local function Arrow(side)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(20, 22)
        b:SetPoint(side == "left" and "TOPLEFT" or "TOPRIGHT", side == "left" and 10 or -10, 0)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        t:SetPoint("CENTER", 0, 1)
        t:SetText(side == "left" and "<" or ">")
        b:SetFontString(t)
        b:SetNormalFontObject("GameFontNormalLarge")
        b:SetHighlightFontObject("GameFontHighlightLarge")
        b:SetDisabledFontObject("GameFontDisableLarge")
        b:SetMotionScriptsWhileDisabled(true)
        Keep.Tip(b, key)
        return b
    end
    local back = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    back:SetPoint("TOPLEFT", 8, 1)
    back:SetPoint("TOPRIGHT", -8, 1)
    back:SetHeight(24)
    back:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    back:SetBackdropColor(1, 0.85, 0.3, 0.07)
    local left, right = Arrow("left"), Arrow("right")
    local mid = CreateFrame("Button", nil, parent)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 2, 0)
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -2, 0)
    local text = mid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
    mid:SetFontString(text)
    mid:SetMotionScriptsWhileDisabled(true)
    Keep.Tip(mid, key)
    local function Step(by)
        for i, c in ipairs(choices) do
            if c[1] == db[key] then
                db[key] = choices[(i - 1 + by) % #choices + 1][1]
                break
            end
        end
        SyncOverlay()
        ApplyLook()
        Keep.RefreshAll() -- (other rows may depend on this one)
        if Wizard.Changed then Wizard.Changed(key) end
    end
    left:SetScript("OnClick", function() Step(-1) end)
    right:SetScript("OnClick", function() Step(1) end)
    mid:SetScript("OnClick", function() Step(1) end)
    function parent:Refresh()
        for _, c in ipairs(choices) do
            if c[1] == db[key] then text:SetText(label .. ": |cffffd100" .. c[2] .. "|r") end
        end
        local cond = enabledIf or parent.enabledIf
        local on = not cond or cond()
        left:SetEnabled(on)
        right:SetEnabled(on)
        mid:SetEnabled(on)
        text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
        if not on then
            for _, c in ipairs(choices) do
                if c[1] == db[key] then text:SetText(label .. ": " .. c[2]) end
            end
        end
    end
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

Keep.TABS = { "Map", "Look", "Zone", "Behavior" }

local function BuildPanel()
    panel = CreateFrame("Frame", "OverlayMapPanel", UIParent, "BackdropTemplate")
    panel:SetWidth(280)
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

    if not tContains(Keep.TABS, db.panelTab) then db.panelTab = "Map" end
    -- the tabs: a row of buttons under the title, the one shown in gold and underlined
    local tabs = {}
    local tabW = (280 - 20) / #Keep.TABS
    for i, name in ipairs(Keep.TABS) do
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(tabW, 22)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * tabW, -30)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("CENTER")
        t:SetText(name)
        b.text = t
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(1, 0.82, 0, 0.9)
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 4, 0)
        b.line:SetPoint("BOTTOMRIGHT", -4, 0)
        b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
        b:GetHighlightTexture():SetAlpha(0.2)
        b:SetScript("OnClick", function()
            db.panelTab = name
            RefreshPanel()
        end)
        tabs[name] = b
    end
    local base = panel:CreateTexture(nil, "ARTWORK")
    base:SetColorTexture(0.75, 0.55, 0.15, 0.4)
    base:SetHeight(1)
    base:SetPoint("TOPLEFT", 10, -52)
    base:SetPoint("TOPRIGHT", -10, -52)

    local rows, tab = {}, nil
    -- a row: a frame across the panel, `height` tall; shown on its tab when `when` (if any) says so
    local function Row(height, when)
        local f = CreateFrame("Frame", nil, panel)
        f:SetHeight(height)
        f.height, f.tab, f.when = height, tab, when
        f.Refresh = function() end
        rows[#rows + 1] = f
        return f
    end
    local function Gap(h) Row(h) end

    tab = "Map"
    PanelCheck(Row(32), "overlay", "Full-screen overlay")
    PanelSlider(Row(42, NotOverlay), "scale", "Size", 0.3, 2.5, 0.05, true)
    PanelSlider(Row(44, NotOverlay), "width", "Width", 0.5, 1.5, 0.05, true)
    PanelSlider(Row(44), "opacity", "Map opacity", 0, 1, 0.05)
    PanelSlider(Row(42), "pinOpacity", "Marker opacity", 0.1, 1, 0.05)
    PanelSlider(Row(44), "markerSize", "Marker size", 0.5, 2.5, 0.05)
    PanelCheck(Row(28), "onlyMe", "Show only my arrow")
    tab = "Look"
    PanelCycle(Row(30), "style", "Style", STYLE_CHOICES)
    PanelCycle(Row(30), "edge", "Fade at the edges", EDGE_CHOICES, StandardStyle)
    PanelCycle(Row(34), "shape", "Edge shape", SHAPE_CHOICES, StandardStyle)
    PanelSlider(Row(44, OutlineStyle), "outlineLines", "Line strength", 0.1, 1, 0.05)
    PanelSlider(Row(44, OutlineStyle), "outlineBack", "Background darkness", 0, 1, 0.05)
    tab = "Zone"
    local function ZoneOn() return db.zoneBorder and Zone.Installed() end
    PanelCheck(Row(28), "zoneBorder", "Apply borders to zones", Zone.Installed, "Apply borders to zones (needs download)",
        "Zone borders need the Overlay Map: Zone Borders addon, a separate download (from where you got "
        .. "Overlay Map). Install it next to Overlay Map and restart the game.")
    PanelCheck(Row(30, ZoneOn), "zoneSoft", "Fade at the zone edges")
    PanelSlider(Row(46, ZoneOn), "zoneDim", "Rest of map visibility", 0, 0.6, 0.05)
    PanelCycle(Row(30, ZoneOn), "zoneFitMode", "Auto-zoom to zone", Wizard.FIT_CHOICES)
    tab = "Behavior"
    PanelCycle(Row(32), "mode", "Key", Wizard.MODE_CHOICES)
    PanelCheck(Row(28), "clickThrough", "Click through the map (Shift: use it)")
    PanelCheck(Row(28), "follow", "Center on me")
    PanelCheck(Row(28), "fitPlaces", "Auto-zoom caves", OpenMapLoaded, "Auto-zoom caves (needs OpenMap)",
        "\"Auto-zoom caves\" needs OpenMap, which draws the caves and mines out in the world. Install OpenMap to use it.")
    PanelCheck(Row(28), "liveMinimap", "Minimap as map in dungeons")
    panel.rows = rows

    local move = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    move:SetHeight(20)
    move:SetPoint("BOTTOMLEFT", 10, 34)
    move:SetPoint("BOTTOMRIGHT", -10, 34)
    move:SetText("Move the map")
    move:SetScript("OnClick", function() SlashCmdList.OVERLAYMAP("move") end)
    local all = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    all:SetHeight(20)
    all:SetPoint("BOTTOMLEFT", 10, 10)
    all:SetPoint("BOTTOMRIGHT", -10, 10)
    all:SetText("All options")
    all:SetScript("OnClick", function() SlashCmdList.OVERLAYMAP("") end)

    local TOP = 60
    local function Layout()
        local tall = 0
        for _, name in ipairs(Keep.TABS) do
            local h = 0
            for _, f in ipairs(rows) do
                if f.tab == name and (not f.when or f.when()) then h = h + f.height end
            end
            tall = math.max(tall, h)
        end
        local y = -TOP
        for _, f in ipairs(rows) do
            local shown = f.tab == db.panelTab and (not f.when or f.when())
            f:SetShown(shown)
            if shown then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
                f:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
                y = y - f.height
            end
        end
        for name, b in pairs(tabs) do
            local on = name == db.panelTab
            b.text:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
            b.line:SetShown(on)
        end
        panel:SetHeight(TOP + tall + 4 + 58)
        move:SetEnabled(not db.overlay)
    end

    panel:SetScript("OnShow", function(self)
        for _, f in ipairs(self.rows) do f:Refresh() end
        Layout()
        PlacePanel()
    end)
    RefreshPanel = function()
        if panel:IsShown() then panel:GetScript("OnShow")(panel) end
    end
    panel:Hide()
end

--------------------------------------------------------------------------------
-- Setup wizard: a window that walks through the key and the main options, with the map open
-- behind it so every change shows at once. Shown once, the first time Overlay Map is installed;
-- again from the options ("Setup wizard") or /omap setup.
-- It always starts from the default settings: what you had is kept aside, and comes back if you
-- close it midway and choose not to keep its settings (or if the game closes during it).
--------------------------------------------------------------------------------

Wizard.MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
Wizard.MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
Wizard.FIT_CHOICES = { { "off", "Off" }, { "enter", "When entering" }, { "open", "When entering or opening" } }
Wizard.MODE_CHOICES = { { "hold", "Hold to show" }, { "press", "Toggle" } }
Wizard.BOOKKEEPING = { "beforeOverlay", "overlaySet", "overlayActive" } -- (Overlay Mode's swapped settings)
Wizard.DIM = 0.35 -- the key step: the map's strength until you press your key
-- Where the wizard starts: the default settings, with no soft edges, a sharp zone border with
-- nothing outside it, and a bigger map
-- (and zoomed in on you as it opens: Wizard.ZoomIn)
Wizard.PRESET = { overlayActive = false, edge = 0, zoneSoft = false, zoneDim = 0, scale = 1.2 }
Wizard.ZOOM_IN = 1.6 -- (how much closer than the whole zone fitting)

function Wizard.Copy(v) return type(v) == "table" and CopyTable(v) or v end

-- Every setting, as it is now
function Wizard.Snapshot()
    local t = {}
    for k in pairs(DEFAULTS) do t[k] = Wizard.Copy(db[k]) end
    for _, k in ipairs(Wizard.BOOKKEEPING) do t[k] = Wizard.Copy(db[k]) end
    return t
end

function Wizard.Load(t)
    for k in pairs(DEFAULTS) do
        if t[k] ~= nil then db[k] = Wizard.Copy(t[k]) else db[k] = Wizard.Copy(DEFAULTS[k]) end
    end
    for _, k in ipairs(Wizard.BOOKKEEPING) do db[k] = Wizard.Copy(t[k]) end
    wipe(pending)
    if compact then ApplyShape(true) else ApplyLook() end
    Keep.RefreshAll()
    -- (the options window isn't told setting by setting: that runs each option's change again, and
    -- it reads the settings anew when it's next opened)
end

-- The key with what's held with it, as the game writes it (ALT-CTRL-SHIFT-K)
function Wizard.Combo(key)
    local mods = ""
    if IsAltKeyDown() then mods = mods .. "ALT-" end
    if IsControlKeyDown() then mods = mods .. "CTRL-" end
    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
    return mods .. key
end

function Wizard.KeyText(key)
    return key and (GetBindingText and GetBindingText(key) or key) or "none"
end

function Wizard.CurrentKey()
    return (GetBindingKey("OVERLAYMAP_SHOW"))
end

-- What a key does now (nil: nothing, or already Overlay Map)
function Wizard.UsedFor(key)
    local action = GetBindingAction(key)
    if not action or action == "" or action == "OVERLAYMAP_SHOW" then return end
    return _G["BINDING_NAME_" .. action] or action
end

function Wizard.Bind(key)
    if InCombatLockdown() then
        Zone.Tell("Keys can't be changed in combat: try again after it.")
        return false
    end
    for _, old in ipairs({ GetBindingKey("OVERLAYMAP_SHOW") }) do
        if old ~= key then SetBinding(old, nil) end
    end
    if not SetBinding(key, "OVERLAYMAP_SHOW") then return false end
    SaveBindings(GetCurrentBindingSet())
    Wizard.full = false
    return true
end

-- How strong the map shows behind the wizard: faint on the key step once there's a key, until you
-- use it; full everywhere else
function Wizard.DimTarget()
    if Wizard.frame and Wizard.frame:IsShown() and Wizard.step == 1 and Wizard.CurrentKey() and not Wizard.full then
        return Wizard.DIM
    end
    return 1
end

-- Every control that shows a setting is read again (an option may grey out others), and the
-- options window is told too.
function Wizard.Refresh()
    if not (Wizard.frame and Wizard.frame:IsShown()) then return end
    local page = Wizard.pages[Wizard.step]
    for _, row in ipairs(page.rows) do row:Refresh() end
    Wizard.Layout(page)
end

-- An option changed with a checkbox or a choice button (the wizard's or the small panel's)
function Wizard.Changed(key)
    -- (once at a time: telling the options window about a change can come back here)
    if Wizard.changing then return end
    Wizard.changing = true
    Wizard.Refresh()
    if Keep.RefreshOptions then Keep.RefreshOptions() end
    Wizard.changing = false
    -- (Zone Border turned on or off with the map open: every picture's cut-outs laid again from
    -- scratch, the zone's first, as when the map opens; added on top of the soft edges, OpenMap's
    -- pictures could run out of room and show the map uncut, brown, outside your zone)
    if key == "zoneBorder" and compact then
        UnmaskKind("zone")
        UnmaskKind("shape")
        ApplyEdges()
    end
    -- (Follow Me with Fit Zone: how the two go together)
    if key == "follow" and db.follow and db.zoneBorder and db.zoneFitMode ~= "off" then
        StaticPopup_Show("OVERLAYMAP_FOLLOW_FIT")
    end
    -- (Zone Border turned on: the map glides to your zone, so you see it at once)
    if key == "zoneBorder" and db.zoneBorder and compact and Zone.Available() and not Zone.inCave then
        C_Timer.After(0.3, function()
            local zone = compact and db.zoneBorder and Zone.PlayerZone()
            if zone then
                Zone.fittedFor = zone
                Zone.Fit(zone)
            end
        end)
    end
end

-- A row on a page, `height` tall, shown while `when` (if any) says so
function Wizard.Row(page, height, when)
    local f = CreateFrame("Frame", nil, page)
    f:SetHeight(height)
    f.height, f.when = height, when
    f.Refresh = function() end
    page.rows[#page.rows + 1] = f
    return f
end

function Wizard.Text(page, text, height, font, justify)
    height = math.floor((height or 30) * 1.25 + 0.5) -- (the bigger letters)
    local f = Wizard.Row(page, height)
    local fs = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 12, 0)
    fs:SetPoint("TOPRIGHT", -12, 0)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(2)
    fs:SetWordWrap(true)
    fs:SetHeight(height) -- (a fixed height: wrapped in it, not cut short before the row is laid out)
    if type(text) == "function" then
        f.Refresh = function() fs:SetText(text()) end
    else
        fs:SetText(text)
    end
    f.fs = fs
    return f
end

-- A short grey line under an option, saying what it does
function Wizard.Note(page, text, height, when)
    local f = Wizard.Text(page, text, height or 28, "GameFontDisable")
    f.fs:SetPoint("TOPLEFT", 36, 0)
    f.when = when
    return f
end

function Wizard.Button(page, label, onClick, when)
    local f = Wizard.Row(page, 28, when)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetHeight(22)
    b:SetPoint("TOPLEFT", 10, 0)
    b:SetPoint("TOPRIGHT", -10, 0)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    f.button = b
    return f
end

function Wizard.Layout(page)
    local y = 0
    for _, f in ipairs(page.rows) do
        local shown = not f.when or f.when()
        f:SetShown(shown)
        if shown then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
            f:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y)
            y = y - f.height
        end
    end
    if page.scroll then
        page:SetSize(math.max(100, page.scroll:GetWidth() or 360), math.max(1, -y))
        Keep.ScrollFit(page.scroll, page)
    end
end

-- The key step: a button that waits for the next key pressed, a warning when that key does
-- something else already, Hold or Press, and a try-it line.
function Wizard.KeyPage(page)
    Wizard.Text(page, "Choose the key that shows the map. Click the button, then press the key you want "
        .. "(Shift, Ctrl and Alt combinations work too). Escape cancels.", 44)
    Wizard.Text(page, function()
        return "Your key now: |cffffd100" .. Wizard.KeyText(Wizard.CurrentKey()) .. "|r"
    end, 22, "GameFontNormal")
    local row = Wizard.Button(page, "Set key", function(self)
        if InCombatLockdown() then Zone.Tell("Keys can't be changed in combat: try again after it.") return end
        Wizard.capturing = true
        Wizard.asked = nil
        self:SetText("Press a key...")
        Wizard.catcher:EnableKeyboard(true)
        Wizard.catcher:Show()
        Wizard.Refresh()
    end)
    Wizard.keyButton = row.button
    -- (the key pressed does something else: replace it, or choose another)
    Wizard.Text(page, function()
        return Wizard.asked and ("|cffff8040" .. Wizard.KeyText(Wizard.asked) .. "|r is used for |cffffd100"
            .. tostring(Wizard.UsedFor(Wizard.asked)) .. "|r. Use it for Overlay Map instead?") or ""
    end, 34).when = function() return Wizard.asked ~= nil end
    local ask = Wizard.Row(page, 34, function() return Wizard.asked ~= nil end)
    local yes = CreateFrame("Button", nil, ask, "UIPanelButtonTemplate")
    yes:SetSize(140, 22)
    yes:SetPoint("TOPLEFT", 10, 0)
    yes:SetText("Use it")
    yes:SetScript("OnClick", function()
        local key = Wizard.asked
        Wizard.asked = nil
        if key and Wizard.Bind(key) then Say("Map key: " .. Wizard.KeyText(key) .. ".") end
        Wizard.Refresh()
    end)
    local no = CreateFrame("Button", nil, ask, "UIPanelButtonTemplate")
    no:SetSize(140, 22)
    no:SetPoint("TOPRIGHT", -10, 0)
    no:SetText("Choose another")
    no:SetScript("OnClick", function()
        Wizard.asked = nil
        Wizard.Refresh()
    end)
    Wizard.Text(page, "", 6)
    PanelCycle(Wizard.Row(page, 32), "mode", "Key", Wizard.MODE_CHOICES)
    Wizard.Text(page, "Hold to show: the map shows while you hold the key, for a quick look. Toggle: one press "
        .. "shows it, the next one hides it.", 40)
    -- (try it: the map is faint behind the wizard until the key is used)
    Wizard.Text(page, function()
        local key = Wizard.CurrentKey()
        if not key then return "" end
        return "|cff66ff66Try it:|r " .. (db.mode == "press" and "press" or "hold") .. " |cffffd100"
            .. Wizard.KeyText(key) .. "|r to see the map at full strength."
    end, 36, "GameFontHighlight").when = function() return Wizard.CurrentKey() ~= nil end
end

-- Catches the next key (or mouse button) while "Set key" waits for it
function Wizard.Catch(key)
    Wizard.catcher:EnableKeyboard(false)
    Wizard.catcher:Hide()
    Wizard.capturing = false
    if Wizard.keyButton then Wizard.keyButton:SetText("Set key") end
    if key and key ~= "ESCAPE" then
        local combo = Wizard.Combo(key)
        if Wizard.UsedFor(combo) then
            Wizard.asked = combo
        elseif Wizard.Bind(combo) then
            Say("Map key: " .. Wizard.KeyText(combo) .. ".")
        end
    end
    Wizard.Refresh()
end

-- The last step: centred, with your key in a box
function Wizard.DonePage(p)
    Wizard.Text(p, "You're all set!", 34, "GameFontNormalHuge", "CENTER")
    Wizard.Text(p, function()
        return (db.mode == "press" and "Press" or "Hold") .. " this key to show the map:"
    end, 22, "GameFontHighlight", "CENTER")
    local keyRow = Wizard.Row(p, 56)
    local cap = CreateFrame("Frame", nil, keyRow, "BackdropTemplate")
    cap:SetPoint("TOP", 0, -4)
    cap:SetHeight(40)
    cap:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    cap:SetBackdropColor(0.12, 0.1, 0.07, 1)
    cap:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    local capText = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    capText:SetPoint("CENTER")
    keyRow.Refresh = function()
        local key = Wizard.CurrentKey()
        capText:SetText(key and Wizard.KeyText(key) or "|cffff8040No key yet|r")
        cap:SetWidth(math.max(90, capText:GetStringWidth() + 36))
    end
    Wizard.Text(p, function()
        return Wizard.CurrentKey() and "" or "Go back to the first step to choose one."
    end, 20, "GameFontDisable", "CENTER").when = function() return not Wizard.CurrentKey() end
    -- (what you chose, one row each, lined up on the middle: the setting in grey on the left, your
    -- choice in gold on the right)
    local function Pick(list, v) for _, c in ipairs(list) do if c[1] == v then return c[2] end end return tostring(v) end
    local function OnOff(v) return v and "On" or "Off" end
    local SUMMARY = {
        { "Map", function() return db.overlay and "Full-screen overlay" or string.format("%d%% size", db.scale * 100 + 0.5) end },
        { "Style", function() return Pick(STYLE_CHOICES, db.style) end },
        { "Map opacity", function() return string.format("%d%%", db.opacity * 100 + 0.5) end },
        { "Markers", function() return string.format("%d%%", db.pinOpacity * 100 + 0.5) end },
        { "Zone borders", function() return OnOff(db.zoneBorder and Zone.Installed()) end },
        { "Center on me", function() return OnOff(db.follow) end },
        { "Click through the map", function() return OnOff(db.clickThrough) end },
    }
    Wizard.Text(p, "", 8)
    for _, item in ipairs(SUMMARY) do
        local r = Wizard.Row(p, 18)
        local label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPRIGHT", r, "TOP", -8, 0)
        label:SetJustifyH("RIGHT")
        label:SetTextColor(0.67, 0.67, 0.67)
        label:SetText(item[1])
        local value = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        value:SetPoint("TOPLEFT", r, "TOP", 8, 0)
        value:SetJustifyH("LEFT")
        r.Refresh = function() value:SetText(item[2]()) end
    end
    Wizard.Text(p, "", 14)
    Wizard.Text(p, "Change anything later in Options > AddOns > Overlay Map, with the button in the "
        .. "map's corner, or with /omap setup.", 40, "GameFontDisable", "CENTER")
end

function Wizard.Build()
    local f = CreateFrame("Frame", "OverlayMapSetup", UIParent, "BackdropTemplate")
    Wizard.frame = f
    f:SetSize(390, 640)
    f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.045, 0.04, 0.96)
    f:SetBackdropBorderColor(0.75, 0.55, 0.15, 0.9)
    tinsert(UISpecialFrames, "OverlayMapSetup") -- (Escape closes it)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Overlay Map setup")
    f.stepText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.stepText:SetPoint("TOPLEFT", 14, -34)
    f.stepText:SetPoint("TOPRIGHT", -14, -34)
    f.stepText:SetJustifyH("LEFT")
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.75, 0.55, 0.15, 0.4)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, -52)
    line:SetPoint("TOPRIGHT", -12, -52)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.back:SetSize(96, 22)
    f.back:SetPoint("BOTTOMLEFT", 12, 12)
    f.back:SetText("Back")
    f.back:SetScript("OnClick", function() Wizard.Show(Wizard.step - 1) end)
    f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.next:SetSize(96, 22)
    f.next:SetPoint("BOTTOMRIGHT", -12, 12)
    f.next:SetScript("OnClick", function()
        if Wizard.step < #Wizard.pages then
            Wizard.Show(Wizard.step + 1)
        else
            Wizard.done = true
            f:Hide()
        end
    end)
    f.dots = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.dots:SetPoint("BOTTOM", 0, 18)

    -- (the map's strength behind the wizard, eased: faint on the key step until you use your key)
    f:SetScript("OnUpdate", function(_, elapsed)
        local want, now = Wizard.DimTarget(), Wizard.dimNow or 1
        if math.abs(want - now) < 0.001 then return end
        local step = elapsed * 3
        now = want > now and math.min(want, now + step) or math.max(want, now - step)
        Wizard.dimNow = now
        if compact then ApplyOpacity() end
    end)

    -- (catches the next key while "Set key" waits: over everything, taking the keyboard)
    local catcher = CreateFrame("Button", nil, f)
    Wizard.catcher = catcher
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:Hide()
    catcher:SetScript("OnKeyDown", function(_, key)
        if Wizard.MODIFIERS[key] then return end
        Wizard.Catch(key)
    end)
    catcher:SetScript("OnMouseDown", function(_, button)
        Wizard.Catch(Wizard.MOUSE[button]) -- (a left or right click cancels)
    end)

    local pages = {}
    Wizard.pages = pages
    -- (each step scrolls, if it doesn't fit the window)
    local function Page(name)
        local sf, p = Keep.Scroller(f, "OverlayMapSetupStep" .. (#pages + 1))
        sf:SetPoint("TOPLEFT", 0, -62)
        sf:SetPoint("BOTTOMRIGHT", -28, 44)
        p.scroll = sf
        p.rows, p.name = {}, name
        sf:Hide()
        pages[#pages + 1] = p
        return p
    end

    Wizard.KeyPage(Page("Your key"))

    local p = Page("Size and place")
    Wizard.Text(p, "The map is open behind this window, so you see each change. Drag this window by "
        .. "its title if it's in the way.", 40)
    PanelCheck(Wizard.Row(p, 28), "overlay", "Full-screen overlay")
    Wizard.Note(p, "The map fills the whole screen, see-through, with soft edges and click through. It "
        .. "keeps settings of its own.", 44)
    PanelSlider(Wizard.Row(p, 42, NotOverlay), "scale", "Size", 0.3, 2.5, 0.05)
    PanelSlider(Wizard.Row(p, 42, NotOverlay), "width", "Width", 0.5, 1.5, 0.05)
    Wizard.Button(p, "Move the map", function() ShowMover() end, NotOverlay)
    Wizard.Note(p, "Drag the box, then right-click it when done.", 28, NotOverlay)

    p = Page("Map look")
    PanelSlider(Wizard.Row(p, 44), "opacity", "Map opacity", 0, 1, 0.05)
    PanelCycle(Wizard.Row(p, 30), "style", "Style", STYLE_CHOICES)
    Wizard.Note(p, "Torn parchment: torn, burnt paper edges. Outlines (beta): only white lines for cliffs, "
        .. "water and roads (needs the Overlay Map: Outlines download).", 44)
    PanelCycle(Wizard.Row(p, 30, StandardStyle), "edge", "Fade at the edges", EDGE_CHOICES)
    PanelCycle(Wizard.Row(p, 34, StandardStyle), "shape", "Edge shape", SHAPE_CHOICES)
    PanelSlider(Wizard.Row(p, 42, OutlineStyle), "outlineLines", "Line strength", 0.1, 1, 0.05)
    PanelSlider(Wizard.Row(p, 42, OutlineStyle), "outlineBack", "Background darkness", 0, 1, 0.05)

    p = Page("Markers")
    Wizard.Text(p, "Quests, vendors, flight points and other addons' icons on the map.", 30)
    PanelSlider(Wizard.Row(p, 42), "pinOpacity", "Marker opacity", 0.1, 1, 0.05)
    PanelSlider(Wizard.Row(p, 44), "markerSize", "Marker size", 0.5, 2.5, 0.05)
    PanelCheck(Wizard.Row(p, 28), "onlyMe", "Show only my arrow")
    Wizard.Note(p, "Hides every marker except your own arrow.", 24)
    PanelCheck(Wizard.Row(p, 28), "arrowCustom", "Custom arrow size")
    Wizard.Note(p, "Your arrow at a size and opacity of its own, apart from the other markers.", 30)
    PanelSlider(Wizard.Row(p, 42, ArrowOwn), "arrowSize", "My arrow size", 0.5, 3, 0.05)
    PanelSlider(Wizard.Row(p, 42, ArrowOwn), "arrowOpacity", "My arrow opacity", 0.1, 1, 0.05)

    p = Page("Zone borders")
    local function ZoneOn() return db.zoneBorder and Zone.Installed() end
    Wizard.Text(p, "Cuts the map to the outline of your zone or city, so it stands out from the rest.", 32)
    PanelCheck(Wizard.Row(p, 30), "zoneBorder", "Apply borders to zones", Zone.Installed, "Apply borders to zones (needs download)",
        "Zone borders need the Overlay Map: Zone Borders addon, a separate download (from where you got "
        .. "Overlay Map). Install it next to Overlay Map and restart the game.")
    Wizard.Note(p, "Needs the Overlay Map: Zone Borders download, from where you got Overlay Map.", 30,
        function() return not Zone.Installed() end)
    PanelCheck(Wizard.Row(p, 28, ZoneOn), "zoneSoft", "Fade at the zone edges")
    Wizard.Note(p, "The zone fades in from its edge, instead of a sharp cut.", 24, ZoneOn)
    PanelSlider(Wizard.Row(p, 44, ZoneOn), "zoneDim", "Rest of map visibility", 0, 0.6, 0.05)
    PanelCycle(Wizard.Row(p, 30, ZoneOn), "zoneFitMode", "Auto-zoom to zone", Wizard.FIT_CHOICES)
    Wizard.Note(p, "Zooms the map so your whole zone fits, when you enter it (or also each time the "
        .. "map opens).", 30, ZoneOn)

    p = Page("While it's open")
    PanelCheck(Wizard.Row(p, 28), "clickThrough", "Click through the map")
    Wizard.Note(p, "Clicks go through the map to the world, so you can keep turning and clicking. "
        .. "Hold Shift to drag and zoom the map.", 44)
    PanelCheck(Wizard.Row(p, 28), "follow", "Center on me")
    Wizard.Note(p, "The map stays centred on you as you move, like the minimap.", 30)
    PanelCheck(Wizard.Row(p, 28), "fitPlaces", "Auto-zoom caves", OpenMapLoaded, "Auto-zoom caves (needs OpenMap)",
        "\"Auto-zoom caves\" needs OpenMap, which draws the caves and mines out in the world. Install OpenMap to use it.")
    Wizard.Note(p, OpenMapLoaded() and "Entering a cave or mine, the map zooms in on it."
        or "Needs OpenMap, which draws the caves and mines out in the world.", 30)
    Wizard.Text(p, "Also hide while the map is open:", 20, "GameFontNormal")
    PanelCheck(Wizard.Row(p, 26), "hideMinimap", "Minimap")
    for _, group in ipairs(HIDE_GROUPS) do PanelCheck(Wizard.Row(p, 26), group.key, group.label) end
    PanelCheck(Wizard.Row(p, 26), "hideNames", "Character names")

    Wizard.DonePage(Page("All set"))

    f:SetScript("OnHide", function()
        if Wizard.capturing then Wizard.Catch(nil) end
        if Wizard.done then
            Wizard.Finish(true)
        else
            StaticPopup_Show("OVERLAYMAP_SETUP_KEEP")
        end
    end)
end

StaticPopupDialogs.OVERLAYMAP_FOLLOW_FIT = {
    text = "\"Center on me\" and \"Auto-zoom to zone\" together:\n\nentering a new zone, the map zooms so all of it fits, and "
        .. "while it fits, the map stays still, centred on the zone. Zoom in to have it follow you (up to the zone's "
        .. "edges). If you zoom yourself, auto-zoom leaves your zoom alone for a while (\"Auto-zoom pause\" in the options).",
    button1 = OKAY or "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Closed before the last step: keep what was chosen, or go back to what you had
StaticPopupDialogs.OVERLAYMAP_SETUP_KEEP = {
    text = "Keep the settings you chose in the setup so far?\n\nNo puts back the settings you had before it.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() Wizard.Finish(true) end,
    OnCancel = function() Wizard.Finish(false) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
}

function Wizard.Show(step)
    Wizard.step = math.max(1, math.min(#Wizard.pages, step))
    local f = Wizard.frame
    for i, p in ipairs(Wizard.pages) do
        p.scroll:SetShown(i == Wizard.step)
        if i == Wizard.step then p.scroll:SetVerticalScroll(0) end
    end
    f.stepText:SetText(string.format("Step %d of %d: %s", Wizard.step, #Wizard.pages, Wizard.pages[Wizard.step].name))
    f.back:SetEnabled(Wizard.step > 1)
    f.next:SetText(Wizard.step < #Wizard.pages and "Next" or "Done")
    local dots = {}
    for i = 1, #Wizard.pages do dots[i] = i == Wizard.step and "|cffffd100o|r" or "|cff806030o|r" end
    f.dots:SetText(table.concat(dots, " "))
    Wizard.Refresh()
end

function Wizard.Open()
    if InCombatLockdown() then
        Say("The setup opens after combat.")
        Wizard.afterCombat = true
        return
    end
    if Wizard.frame and Wizard.frame:IsShown() then return end
    if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
    if not Wizard.frame then Wizard.Build() end
    -- (what you have now, kept aside, also in the saved settings in case the game closes meanwhile;
    -- the wizard starts from the defaults)
    if not db.setupBackup then db.setupBackup = Wizard.Snapshot() end
    Wizard.done, Wizard.full, Wizard.dimNow = false, false, 1
    Wizard.Load(Wizard.PRESET)
    -- (the map open behind it, to see the changes)
    if not compact then
        Open()
        Wizard.openedMap = compact
    end
    Wizard.frame:Show()
    Wizard.Show(1)
    C_Timer.After(0.2, Wizard.ZoomIn)
end

-- The map zoomed in on you (with OpenMap's world; the game's own map shows the zone as it is)
function Wizard.ZoomIn()
    if not compact or not Zone.OpenMapStitched() then return end
    local zone = Zone.PlayerZone()
    local fit = zone and Zone.FitZoom(zone)
    local best = C_Map.GetBestMapForUnit("player")
    local api = _G.OpenMapAPI
    if not (fit and best and api.WorldFromMap) then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, best, "player")
    if not ok or not pos then return end
    local x, y = pos:GetXY()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end
    local u, v = api.WorldFromMap(best, x, y)
    if not u then return end
    Zone.fittedFor = zone
    pcall(api.ShowWorld, u, v, fit * Wizard.ZOOM_IN)
end

-- keep: the wizard's settings stay (Done, or Yes when closed midway); otherwise yours come back
function Wizard.Finish(keep)
    if not keep and db.setupBackup then Wizard.Load(db.setupBackup) end
    db.setupBackup = nil
    db.setupDone = true
    Wizard.dimNow, Wizard.full = nil, false
    if compact then ApplyOpacity() end
    if Wizard.openedMap and compact then Close() end
    Wizard.openedMap = nil
    if mover and mover:IsShown() then mover:Hide() end
end

-- At login: settings left from a setup the game closed in the middle of are put back; the first
-- time Overlay Map is installed, the setup opens (a moment after the world shows); someone who
-- already used it is told it's there, once.
function Wizard.AtLogin()
    if db.setupBackup then
        Wizard.Load(db.setupBackup)
        db.setupBackup = nil
    end
    if db.setupDone then return end
    if Wizard.fresh then
        C_Timer.After(2, function()
            if not db.setupDone then Wizard.Open() end
        end)
    else
        db.setupDone = true
        Say("New: a setup wizard, with the map key and the main options in a few steps. Type |cffffd100/omap setup|r to open it.")
    end
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

-- A page's options (or every one) back to their defaults, through the options themselves, so the window
-- and the map follow
function Keep.ResetSettings(list)
    for _, item in ipairs(list) do
        local setting, key = item[1], item[2]
        local default = DEFAULTS[key]
        if type(default) == "table" then default = CopyTable(default) end
        if setting.SetValue then pcall(setting.SetValue, setting, default) else db[key] = default end
    end
    SyncOverlay()
    ApplyLook()
    Keep.RefreshAll()
end

-- One of the options' sub-pages, by its name
function Keep.OpenPage(name)
    for _, page in ipairs(Keep.pages or {}) do
        if page.name == name and page.cat ~= category then
            if not (SettingsPanel and SettingsPanel.SelectCategory and pcall(SettingsPanel.SelectCategory, SettingsPanel, page.cat)) then
                pcall(Settings.OpenToCategory, page.cat:GetID())
            end
            return
        end
    end
end

function Keep.ResetAll()
    for _, page in ipairs(Keep.pages or {}) do Keep.ResetSettings(page.settings) end
    for _, name in ipairs(Keep.options and Keep.OPTION_TABS or {}) do Keep.ResetTab(name) end
    db.x, db.y = 0, 0
    ApplyLook()
    Say("Every option is back to its default.")
end

StaticPopupDialogs.OVERLAYMAP_RESET_ALL = {
    text = "Put every Overlay Map option back to its default?\n\n(Your map key stays as it is.)",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() Keep.ResetAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- "Open on the map" (main options): the game doesn't let the map and the options window be open together
-- (opening one closes the other), so the options window closes, and the map opens with its small panel,
-- where the main options can be changed while you see them
function Keep.Preview()
    if InCombatLockdown() then Say("Not in combat: try again after it.") return end
    if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
    C_Timer.After(0, function()
        if not compact then Open() end
        -- (its panel once the map has settled; beside the options button, or the map if the button is hidden)
        C_Timer.After(0.3, function()
            if not compact then return end
            if not panel then BuildPanel() end
            UpdateMapButton()
            panel:Show()
            if not (mapButton and mapButton:IsShown()) then
                panel:ClearAllPoints()
                panel:SetPoint("TOPLEFT", Canvas(), "TOPRIGHT", 8, 0)
            end
        end)
    end)
end

-- Set Key (main options, on a client without the game's key rows there): waits for the next key
function Keep.CatchKey()
    if InCombatLockdown() then Say("Keys can't be changed in combat: try again after it.") return end
    local c = Keep.catcher
    if not c then
        c = CreateFrame("Button", nil, UIParent)
        c:SetAllPoints(UIParent)
        c:SetFrameStrata("TOOLTIP")
        c:EnableKeyboard(true)
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        c.text:SetPoint("CENTER", 0, 80)
        c:SetScript("OnKeyDown", function(self, key)
            if Wizard.MODIFIERS[key] then return end
            self:Hide()
            Keep.GotKey(key)
        end)
        c:SetScript("OnMouseDown", function(self, button)
            self:Hide()
            Keep.GotKey(Wizard.MOUSE[button]) -- (a left or right click cancels)
        end)
        Keep.catcher = c
    end
    c.text:SetText("Press the key that shows the map\n\n|cffaaaaaaEscape or a click cancels|r")
    c:Show()
end

function Keep.GotKey(key)
    if not key or key == "ESCAPE" then return end
    local combo = Wizard.Combo(key)
    local used = Wizard.UsedFor(combo)
    if Wizard.Bind(combo) then
        Say("Map key: " .. Wizard.KeyText(combo) .. (used and (" (it was used for " .. used .. ")") or "") .. ".")
    end
    Keep.RefreshAll()
end

function Keep.ListOptions()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Overlay Map")
    -- The options are split over pages (the main one and sub-pages under it in the AddOns list), each
    -- with a button putting it back to its defaults. P: the page being built (its category, layout and
    -- settings). A client without sub-pages gets them as sections of one page.
    local P = { cat = category, layout = layout, settings = {}, name = "Overlay Map" }
    Keep.pages = { P }

    local function Register(key, name)
        local setting = Settings.RegisterAddOnSetting(P.cat, ADDON_NAME .. "_" .. key, key, db,
            type(DEFAULTS[key]), name, DEFAULTS[key])
        P.settings[#P.settings + 1] = { setting, key }
        if key == "zoneBorder" then Zone.borderSetting = setting end
        if key == "style" then Outline.styleSetting = setting end
        setting:SetValueChangedCallback(function()
            SyncOverlay()
            ApplyLook()
            if Wizard.Changed then Wizard.Changed(key) end
            if mover and mover:IsShown() then ShowMover() end
        end)
        return setting
    end

    local function Slider(key, name, tooltip, minValue, maxValue, step)
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return string.format("%d%%", value * 100 + 0.5)
        end)
        return Settings.CreateSlider(P.cat, Register(key, name), options, tooltip)
    end

    -- (an option that needs OpenMap: its name says so when OpenMap isn't there, and it's greyed out)
    local function NeedsOM(name) return OpenMapLoaded() and name or (name .. " (needs OpenMap)") end

    local function Header(name)
        if P.layout and CreateSettingsListSectionHeaderInitializer then
            P.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
        end
    end

    local function Button(name, label, fn, tooltip)
        if not (P.layout and CreateSettingsButtonInitializer) then return end
        local init = CreateSettingsButtonInitializer(name, label, fn, tooltip, false)
        P.layout:AddInitializer(init)
        return init
    end

    -- A page's last row: its settings back to their defaults
    local function ResetRow()
        local page = P
        Button("", "Reset this page", function() Keep.ResetSettings(page.settings) end,
            "Puts every option on this page back to its default.")
    end

    -- The next page: a sub-page of Overlay Map's, or (without sub-pages) a section of the one page
    local function Page(name)
        ResetRow()
        if Settings.RegisterVerticalLayoutSubcategory then
            local ok, cat, lay = pcall(Settings.RegisterVerticalLayoutSubcategory, category, name)
            if ok and cat and lay then
                P = { cat = cat, layout = lay, settings = {}, name = name }
                Keep.pages[#Keep.pages + 1] = P
                return
            end
        end
        P = { cat = category, layout = layout, settings = {}, name = name }
        Keep.pages[#Keep.pages + 1] = P
        Header(name)
    end

    -- greyed out while the parent's predicate says no
    local function Under(parent, init, predicate)
        if parent and init and init.SetParentInitializer then init:SetParentInitializer(parent, predicate) end
    end

    -- (with sub-pages: a button to each, at the top)
    if Settings.RegisterVerticalLayoutSubcategory then
        Header("More options")
        for _, item in ipairs({
            { "Style", "Map style, Fade at the edges, Edge shape, and the Outlines style's lines." },
            { "Zone borders", "The map cut to your zone's outline, and how it fits and follows the zone." },
            { "Behavior", "Click through the map, Center on me, Auto-zoom caves, Minimap as map, and what to hide while the map is open." },
            { "Panel button", "The button on the map that opens the small panel." },
        }) do
            Button(item[1], "Open", function() Keep.OpenPage(item[1]) end, item[2])
        end
        Header("General")
    end
    Button("Setup wizard", "Open", function() Wizard.Open() end,
        "The map key and the main options in a few steps, with the map open to see each change.")
    Button("Open on the map", "Open", function() Keep.Preview() end,
        "Closes this window and opens the map with its small options panel, to change the main options while you see them.")
    -- the map key: the game's own key row (as in Keybindings) if this client lets addons use it, else a
    -- button that waits for the next key pressed
    local okKey = pcall(function()
        local idx = C_KeyBindings and C_KeyBindings.GetBindingIndex and C_KeyBindings.GetBindingIndex("OVERLAYMAP_SHOW")
        if not (idx and CreateKeybindingEntryInitializer) then error("no key rows") end
        local init = CreateKeybindingEntryInitializer(idx, true)
        if not init then error("no key row") end
        P.layout:AddInitializer(init)
    end)
    if not okKey then
        Button("Map key", "Set key", function() Keep.CatchKey() end,
            "Click, then press the key (or Shift, Ctrl, Alt combination) that shows the map. Escape cancels.")
    end

    local overlayInit = Settings.CreateCheckbox(P.cat, Register("overlay", "Full-screen overlay"),
        "One switch for an overlay map: the map fills the whole screen, see-through and click-through, "
        .. "with solid markers and large soft edges. It keeps its own Map opacity, Marker opacity, Marker size, My Arrow, "
        .. "Style, Fade at the edges, Shape, Click through the map and Don't fade while moving: what you change while it's "
        .. "on stays with Full-screen overlay, and the normal map keeps its own. Size, width and position don't apply "
        .. "while it's on.")

    Header("Map")
    Settings.CreateDropdown(P.cat, Register("mode", "Key"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("hold", "Hold to show")
        container:Add("press", "Toggle")
        return container:GetData()
    end, "Hold to show: the map shows while you hold the key. Toggle: one press shows it, the next one hides it.")
    Under(overlayInit, Slider("scale", "Size", "Size of the map. In full-screen overlay, the map fills the screen instead.", 0.3, 2.5, 0.05), NotOverlay)
    Under(overlayInit, Slider("width", "Width", "Width of the map compared to its usual shape. Lower makes it "
        .. "more square; the map then zooms in to fill it, centred on you. In full-screen overlay, the map fills the screen instead.",
        0.5, 1.5, 0.05), NotOverlay)
    Slider("opacity", "Map opacity", "How see-through the map itself is. At 0%, only the markers show, "
        .. "floating over the world.", 0, 1, 0.05)
    Under(overlayInit, Button("Position", "Move", ShowMover,
        "Shows a box the size of the map. Drag it, then right-click it when done."), NotOverlay)
    Under(overlayInit, Button("", "Reset position", function()
        db.x, db.y = 0, 0
        if mover and mover:IsShown() then ShowMover() end
        ApplyLook()
    end, "Puts the map back in the middle of the screen."), NotOverlay)

    Header("Markers")
    Slider("pinOpacity", "Marker opacity",
        "How see-through the markers on the map are: quests, vendors, flight points, your arrow and other addons' markers.",
        0.1, 1, 0.05)
    Slider("markerSize", "Marker size", "Size of the markers on the map, Questie's and OpenMap's icons too "
        .. "(on top of OpenMap's own Icon size).", 0.5, 2.5, 0.05)
    Settings.CreateCheckbox(P.cat, Register("onlyMe", "Show only my arrow"),
        "Hides every marker on the map (quests, vendors, Questie's and OpenMap's icons) except your own "
        .. "arrow. The map's picture stays.")
    local arrowInit = Settings.CreateCheckbox(P.cat, Register("arrowCustom", "Custom arrow size"),
        "Your arrow on the map at a size and opacity of its own, apart from the other markers. "
        .. "On the game's map (without OpenMap), the opacity is also your party's dots'.")
    for _, init in ipairs({
        Slider("arrowSize", "My arrow size", "Size of your arrow on the map.", 0.5, 3, 0.05),
        Slider("arrowOpacity", "My arrow opacity", "How see-through your arrow on the map is.", 0.1, 1, 0.05),
    }) do
        Under(arrowInit, init, ArrowOwn)
        if init and init.AddShownPredicate then init:AddShownPredicate(ArrowOwn) end
    end

    Button("", "Reset everything", function() StaticPopup_Show("OVERLAYMAP_RESET_ALL") end,
        "Puts every Overlay Map option, on every page, back to its default.")
    Page("Style")
    local styleInit = Settings.CreateDropdown(P.cat, Register("style", "Map style"), function()
        local container = Settings.CreateControlTextContainer()
        for _, c in ipairs(STYLE_CHOICES) do container:Add(c[1], c[2]) end
        return container:GetData()
    end, "Standard: the map as it is, with the soft edges below. Torn parchment: torn, burnt paper edges, "
        .. "like an old map (the soft edges don't apply then). Outlines (beta): the map's painting hidden, only "
        .. "white lines for cliffs, water and roads over a dark background (needs the Overlay Map: Outlines "
        .. "download). Made automatically from the game's terrain: some lines may be missing or wrong.")
    local edgeInit = Settings.CreateDropdown(P.cat, Register("edge", "Fade at the edges"), function()
        local container = Settings.CreateControlTextContainer()
        for _, c in ipairs(EDGE_CHOICES) do container:Add(c[1], c[2]) end
        return container:GetData()
    end, "The map and its markers fade out towards the edges, like the overlay maps of other games. "
        .. "Standard style only.")
    local shapeInit = Settings.CreateDropdown(P.cat, Register("shape", "Edge shape"), function()
        local container = Settings.CreateControlTextContainer()
        for _, c in ipairs(SHAPE_CHOICES) do container:Add(c[1], c[2]) end
        return container:GetData()
    end, "The shape the map fades into: a rectangle with rounded corners, a diamond or an oval. "
        .. "With \"Fade at the edges\" off, the map is cut sharp in that shape. Standard style only.")
    Under(styleInit, edgeInit, StandardStyle)
    Under(styleInit, shapeInit, StandardStyle)
    Under(styleInit, Slider("outlineLines", "Line strength", "Outlines style: how strong the white lines "
        .. "of cliffs, water and roads are.", 0.1, 1, 0.05), OutlineStyle)
    Under(styleInit, Slider("outlineBack", "Background darkness", "Outlines style: how dark the background "
        .. "behind the lines is. At 0%, only the lines over the world.", 0, 1, 0.05), OutlineStyle)

    Page("Zone borders")
    local zoneInit = Settings.CreateCheckbox(P.cat, Register("zoneBorder",
        Zone.Installed() and "Apply borders to zones" or "Apply borders to zones (needs download)"),
        "Cuts the map to the outline of your zone or capital city, on top of the style and shape above "
        .. "(Torn parchment too). Needs the Overlay Map: Zone Borders download (a separate addon). "
        .. "On the game's map it's the zone shown; with OpenMap, the zone you're in, "
        .. "and the whole map shows again when you zoom out to two or three zones across. Outlines made "
        .. "from the game's own map pictures (Stormwind's and Orgrimmar's from Waymark).")
    -- (greyed out without the download)
    if zoneInit and zoneInit.AddModifyPredicate then zoneInit:AddModifyPredicate(Zone.Installed) end
    local function ZoneOn() return db.zoneBorder and Zone.Installed() end
    for i, init in ipairs({
        Settings.CreateCheckbox(P.cat, Register("zoneSoft", "Fade at the zone edges"),
            "The zone fades in from its border. Off: cut sharp."),
        Slider("zoneDim", "Rest of map visibility", "How much of the rest of the map shows behind your zone, "
            .. "which stands out. At 0% it's hidden.", 0, 0.6, 0.05),
        Settings.CreateDropdown(P.cat, Register("zoneFitMode", "Auto-zoom to zone"), function()
            local container = Settings.CreateControlTextContainer()
            container:Add("off", "Off")
            container:Add("enter", "When entering")
            container:Add("open", "When entering or opening")
            return container:GetData()
        end, "Zooms the map so all of your zone fits. When entering: each time you enter a new zone or "
            .. "city (not if you zoomed the map yourself a moment before, see \"Auto-zoom pause\", nor during a flight: when "
            .. "you land). When entering or opening: also every time the map opens, instead of \"Open at last zoom\"."),
        Settings.CreateCheckbox(P.cat, Register("zoneKeep", NeedsOM("Keep the border over the sea and between zones")),
            "With OpenMap: while the middle of the view is over the sea or land that belongs to no zone, the "
            .. "outline you had stays (the rest of the map at \"Rest of map visibility\"). Off: the whole map shows there."),
        Slider("zoneWhole", NeedsOM("Show the whole map below this zone size"), "With OpenMap: the whole map shows once you zoom "
            .. "out until your zone fills less than this much of the view (it comes back a little further in). "
            .. "Higher: the whole map sooner; lower: the outline stays further out.", 0.15, 0.85, 0.05),
        Settings.CreateCheckbox(P.cat, Register("zoneView", NeedsOM("Border the zone in the middle of the view")),
            "With OpenMap: the outline is for the zone in the middle of the view, so moving the map to "
            .. "another zone outlines that one (over the sea or between zones, the last one stays). "
            .. "Off: your zone is outlined, and the whole map shows while you look at another."),
    }) do
        -- (the last three need OpenMap: greyed out without it)
        local om = i > 3
        Under(zoneInit, init, om and function() return ZoneOn() and OpenMapLoaded() end or ZoneOn)
    end

    Page("Behavior")
    Settings.CreateCheckbox(P.cat, Register("clickThrough", "Click through the map"),
        "The mouse goes through the map to the world behind it, so you can click and turn your character "
        .. "with the right button over it. Markers still show their names. Hold Shift to drag and zoom the map. "
        .. "\"Full-screen overlay\" turns this on.")
    Settings.CreateCheckbox(P.cat, Register("follow", "Center on me"),
        "Keeps the map centred on you while it's open, like the minimap. With zone borders and OpenMap it "
        .. "stays inside your zone: still while all of it fits, following you up to its edges when zoomed in. "
        .. "It holds still while the mouse is "
        .. "over the map (in full-screen overlay, over a marker, or with Shift held). Without OpenMap, zoom in "
        .. "with the mouse wheel to see it move: zoomed all the way out, the whole zone already fits.")
    local fitInit = Settings.CreateCheckbox(P.cat, Register("fitPlaces", NeedsOM("Auto-zoom caves")),
        "Needs OpenMap, which draws the caves and mines out in the world. Entering one, the map zooms in till "
        .. "the cave fills it, and back out when you leave (to your zone with \"Auto-zoom to zone\" and zone borders, else to the "
        .. "zoom you had). Works with zone borders or without it.")
    if fitInit and fitInit.AddModifyPredicate then fitInit:AddModifyPredicate(OpenMapLoaded) end
    Settings.CreateCheckbox(P.cat, Register("liveMinimap", "Minimap as map in dungeons"),
        "Inside dungeons and raids the game doesn't let addons know where you are, so no map can show your "
        .. "arrow there. With this on, the game's own minimap (which can) is shown big in the map's place, "
        .. "with your arrow, your party and the layout around you. It shows the minimap's range around you, "
        .. "not the whole dungeon (Dungeon Journal's or OpenMap's map of it does that).")
    Settings.CreateCheckbox(P.cat, Register("rememberZoom", "Open at last zoom"),
        "Opens at the zoom the map had when you last closed it, apart from the normal map's. With OpenMap, "
        .. "OpenMap's own reopen option still decides where it's centred.")
    Settings.CreateCheckbox(P.cat, Register("noFade", "Don't fade while moving"),
        "With this off, the map fades to half while you move, like the game's own map.")
    Settings.CreateCheckbox(P.cat, Register("hideMinimap", "Hide minimap"),
        "Hides the minimap while the map is open.")

    Header("Also hide while the map is open")
    for _, group in ipairs(HIDE_GROUPS) do
        Settings.CreateCheckbox(P.cat, Register(group.key, group.label),
            "Hidden while the map is open, and back when it closes.")
    end
    Settings.CreateCheckbox(P.cat, Register("hideNames", "Character names"),
        "The names above players', NPCs' and pets' heads, hidden while the map is open and back as they "
        .. "were when it closes. The game doesn't allow changing them in combat: then they're hidden, or "
        .. "come back, when combat ends.")

    Page("Panel button")
    Settings.CreateDropdown(P.cat, Register("buttonMode", "Panel button"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("hover", "On hover")
        container:Add("show", "Always")
        container:Add("hide", "Hidden")
        return container:GetData()
    end, "The arrow button in the corner of the map, which opens a small panel with these options. "
        .. "On hover: it shows while the mouse is over the map.")
    Settings.CreateDropdown(P.cat, Register("buttonCorner", "Panel button corner"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("TOPRIGHT", "Top right")
        container:Add("TOPLEFT", "Top left")
        container:Add("BOTTOMRIGHT", "Bottom right")
        container:Add("BOTTOMLEFT", "Bottom left")
        return container:GetData()
    end, "The corner of the map the options button sits in. The small panel opens beside it, or into the "
        .. "map when there's no room outside (always, in full-screen overlay).")
    Slider("buttonOpacity", "Panel button opacity",
        "How see-through the options button is with the mouse over the map (or all the time, with Always). "
        .. "At 0% it only shows when the mouse gets close to it.", 0, 1, 0.05)
    Slider("buttonNearOpacity", "Panel button opacity up close",
        "How see-through the options button is with the mouse on it or right next to it.", 0, 1, 0.05)
    do
        local options = Settings.CreateSliderOptions(14, 48, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
            return string.format("%d", v)
        end)
        Settings.CreateSlider(P.cat, Register("buttonSize", "Panel button size"), options,
            "Size of the options button, in pixels.")
    end

    ResetRow()
    Settings.RegisterAddOnCategory(category)
end

-- The main options (Options > AddOns > Overlay Map) on one page of Overlay Map's own, with tabs like the
-- small panel's, and a search box that finds an option on any tab. Each option has a line of help beside it.
-- (Keep.ListOptions is the game's own list of options, over several pages: used if this client can't show a
-- page of an addon's own, or with Keep.USE_TABS off.)
Keep.USE_TABS = true
Keep.OPTION_TABS = { "General", "Markers", "Style", "Zone borders", "Behavior", "Hide while open", "Panel button" }
Keep.DESC = {
    overlay = "One switch for an overlay map: the map fills the whole screen, see-through and click-through, with solid markers and large soft edges. It keeps its own opacities, marker size, style and edges: what you change while it's on stays with it, and the normal map keeps its own.",
    mode = "Hold to show: the map shows while you hold the key. Toggle: one press shows it, the next one hides it.",
    scale = "Size of the map. In full-screen overlay, the map fills the screen instead.",
    width = "Width of the map compared to its usual shape. Lower makes it more square.",
    opacity = "How see-through the map itself is. At 0%, only the markers show, floating over the world.",
    rememberZoom = "Opens at the zoom the map had when you last closed it, apart from the normal map's.",
    noFade = "With this off, the map fades to half while you move, like the game's own map.",
    pinOpacity = "How see-through the markers are: quests, vendors, flight points, your arrow and other addons' markers.",
    markerSize = "Size of the markers, Questie's and OpenMap's icons too (on top of OpenMap's own Icon size).",
    onlyMe = "Hides every marker on the map except your own arrow. The map's picture stays.",
    arrowCustom = "Your arrow at a size and opacity of its own, apart from the other markers.",
    arrowSize = "Size of your arrow on the map.",
    arrowOpacity = "How see-through your arrow on the map is.",
    style = "Standard: the map as it is. Torn parchment: torn, burnt paper edges. Outlines (beta): only white lines for cliffs, water and roads over a dark background (needs the Overlay Map: Outlines download).",
    edge = "The map and its markers fade out towards the edges, like other games' overlay maps. Standard style only.",
    shape = "The shape the map fades into. With \"Fade at the edges\" off, the map is cut sharp in that shape.",
    outlineLines = "Outlines style: how strong the white lines are.",
    outlineBack = "Outlines style: how dark the background behind the lines is. At 0%, only the lines.",
    zoneBorder = "Cuts the map to the outline of your zone or city (inside a cave, the cave's). Needs the Overlay Map: Zone Borders download.",
    zoneSoft = "The zone fades in from its border. Off: cut sharp.",
    zoneDim = "How much of the rest of the map shows behind your zone. At 0% it's hidden.",
    zoneFitMode = "Zooms the map so all of your zone fits: each time you enter a new zone, or also every time the map opens.",
    keepZoomTime = "After you zoom the map yourself, how long auto-zoom leaves your zoom alone before it fits a new zone again. Off: auto-zoom always fits the zone you enter.",
    zoneKeep = "With OpenMap: while the middle of the view is over the sea or land that belongs to no zone, the border you had stays. Off: the whole map shows there.",
    zoneWhole = "With OpenMap: zoomed out until your zone fills less than this much of the view, the border goes and the whole map shows. Higher: sooner; lower: the border stays further out.",
    zoneView = "With OpenMap: the border is for the zone in the middle of the view, so moving the map to another zone borders that one. Off: the zone you're in.",
    clickThrough = "The mouse goes through the map to the world, so you can click and turn with it over the map. Markers still show their names. Hold Shift to drag and zoom the map.",
    follow = "Keeps the map centred on you while it's open, like the minimap. It holds still while the mouse is over the map.",
    fitPlaces = "Needs OpenMap. Entering a cave or mine, the map zooms in till the cave fills it, and back out when you leave.",
    liveMinimap = "Inside dungeons the game hides where you are from addons. With this on, the game's own minimap (with your arrow) is shown big in the map's place.",
    hideMinimap = "Hides the minimap while the map is open.",
    hideNames = "The names above players', NPCs' and pets' heads, hidden while the map is open (in combat, once it ends).",
    buttonMode = "The arrow button in the map's corner that opens the small panel: always, only with the mouse over the map, or never.",
    buttonCorner = "The corner of the map the panel button sits in.",
    buttonOpacity = "How see-through the button is with the mouse over the map. At 0%, it only shows up close.",
    buttonNearOpacity = "How see-through the button is with the mouse on it or right next to it.",
    buttonSize = "Size of the panel button, in pixels.",
}

-- A scrolling area: the frame to anchor, and the one to put things in (its height set by whoever fills it);
-- the scroll bar only while it doesn't all fit
function Keep.Scroller(parent, name)
    local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf:EnableMouseWheel(true)
    return sf, content
end

function Keep.ScrollFit(sf, content)
    local bar = sf.ScrollBar or (sf:GetName() and _G[sf:GetName() .. "ScrollBar"])
    local fits = content:GetHeight() <= (sf:GetHeight() or 0) + 1
    if bar then bar:SetShown(not fits) end
    if fits then sf:SetVerticalScroll(0) end
end

function Keep.TabOptions()
    local canvas = CreateFrame("Frame")
    canvas:Hide()
    category = Settings.RegisterCanvasLayoutCategory(canvas, "Overlay Map")
    Settings.RegisterAddOnCategory(category)
    local O = { rows = {}, tabs = {} }
    Keep.options = O

    canvas:SetScript("OnShow", function()
        if not O.built then Keep.BuildTabs(canvas, O) end
        Keep.RefreshOptions()
    end)
    canvas:SetScript("OnHide", function() GameTooltip:Hide() end)
end

function Keep.RefreshOptions()
    local O = Keep.options
    if not (O and O.built and O.canvas:IsVisible()) then return end
    for _, f in ipairs(O.rows) do f:Refresh() end
    O.Top()
    O.Layout()
end

function Keep.NeedsOMName(name) return OpenMapLoaded() and name or (name .. " (needs OpenMap)") end

function Keep.BuildTabs(canvas, O)
    O.built, O.canvas = true, canvas
    local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    -- top: title, version, search; then the buttons and the tabs
    local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Overlay Map")
    local ver = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
    ver:SetText(GetMeta and GetMeta(ADDON_NAME, "Version") or "")

    local search = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    search:SetSize(180, 22)
    search:SetPoint("TOPRIGHT", -20, -14)
    search:SetAutoFocus(false)
    local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("Search options...")
    search:SetScript("OnTextChanged", function(self)
        O.query = self:GetText():lower():match("^%s*(.-)%s*$")
        hint:SetShown(self:GetText() == "")
        O.Layout()
        if O.scroll then O.scroll:SetVerticalScroll(0) end
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    O.search = search

    local function TopButton(text, width, fn, tip)
        local b = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        Keep.Tip(b, nil, tip)
        return b
    end
    local wizard = TopButton("Setup wizard", 120, function() Wizard.Open() end,
        "The map key and the main options in a few steps, with the map open to see each change.")
    wizard:SetPoint("TOPLEFT", 16, -48)
    local preview = TopButton("Open on the map", 130, function() Keep.Preview() end,
        "Closes this window and opens the map with its small options panel, to change the main options while you see "
        .. "them (the game doesn't let the map and this window be open together).")
    preview:SetPoint("LEFT", wizard, "RIGHT", 6, 0)
    local key = TopButton("Map key", 150, function() Keep.CatchKey() end,
        "Click, then press the key (or a Shift, Ctrl or Alt combination) that shows the map. Escape cancels.")
    key:SetPoint("LEFT", preview, "RIGHT", 6, 0)
    local resetAll = TopButton("Reset everything", 130, function() StaticPopup_Show("OVERLAYMAP_RESET_ALL") end,
        "Puts every Overlay Map option back to its default (asks first; your key stays).")
    resetAll:SetPoint("TOPRIGHT", -20, -48)
    function O.Top()
        local k = Wizard.CurrentKey()
        key:SetText("Map key: " .. (k and Wizard.KeyText(k) or "|cffff8040none|r"))
    end

    -- tabs
    local tabY = -82
    local x = 16
    for _, name in ipairs(Keep.OPTION_TABS) do
        local b = CreateFrame("Button", nil, canvas)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("CENTER")
        t:SetText(name)
        b:SetSize(t:GetStringWidth() + 20, 24)
        b:SetPoint("TOPLEFT", x, tabY)
        x = x + b:GetWidth() + 2
        b.text = t
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(1, 0.82, 0, 0.9)
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 4, 0)
        b.line:SetPoint("BOTTOMRIGHT", -4, 0)
        b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
        b:GetHighlightTexture():SetAlpha(0.2)
        b:SetScript("OnClick", function()
            db.optionsTab = name
            if O.search:GetText() ~= "" then O.search:SetText("") end
            O.Layout()
            O.scroll:SetVerticalScroll(0)
        end)
        O.tabs[name] = b
    end
    local base = canvas:CreateTexture(nil, "ARTWORK")
    base:SetColorTexture(0.75, 0.55, 0.15, 0.4)
    base:SetHeight(1)
    base:SetPoint("TOPLEFT", 16, tabY - 24)
    base:SetPoint("TOPRIGHT", -20, tabY - 24)
    O.top = -(-tabY + 24 + 12)
    -- (the options of a tab scroll between the tabs and the reset button at the bottom, if they don't fit)
    local sf, content = Keep.Scroller(canvas, "OverlayMapOptionsScroll")
    sf:SetPoint("TOPLEFT", 0, O.top)
    sf:SetPoint("BOTTOMRIGHT", -30, 48)
    O.scroll, O.content = sf, content
    if not tContains(Keep.OPTION_TABS, db.optionsTab) then db.optionsTab = "General" end

    -- rows: a control on the left (CONTROL wide), its line of help on the right
    local CONTROL = 330
    local tab
    local function Row(height, key, label, enabledIf)
        local f = CreateFrame("Frame", nil, content)
        f:SetSize(CONTROL, height)
        f.height, f.tab, f.key, f.enabledIf = height, tab, key, enabledIf
        f.Refresh = function() end
        local desc = key and (Keep.DESC[key] or Keep.TIPS[key])
        if desc then
            f.desc = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            f.desc:SetJustifyH("LEFT")
            f.desc:SetJustifyV("TOP")
            f.desc:SetSpacing(2)
            f.desc:SetText(desc)
        end
        f.search = ((label or "") .. " " .. (desc or "") .. " " .. tab):lower()
        O.rows[#O.rows + 1] = f
        return f
    end
    local function Check(key, label, enabledIf, offLabel, offTip)
        PanelCheck(Row(30, key, label, enabledIf), key, label, enabledIf, offLabel, offTip)
    end
    local function Slider(key, label, minValue, maxValue, step, enabledIf, reshape, fmt)
        PanelSlider(Row(46, key, label, enabledIf), key, label, minValue, maxValue, step, reshape, fmt)
    end
    local function Cycle(key, label, choices, enabledIf)
        PanelCycle(Row(32, key, label, enabledIf), key, label, choices, enabledIf)
    end
    local function Buttons(list, enabledIf, label)
        local f = Row(30, nil, label, enabledIf)
        local w = (CONTROL - 20 - (#list - 1) * 6) / #list
        local made = {}
        for i, item in ipairs(list) do
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(w, 22)
            b:SetPoint("TOPLEFT", 10 + (i - 1) * (w + 6), 0)
            b:SetText(item[1])
            b:SetScript("OnClick", item[2])
            if item[3] then Keep.Tip(b, nil, item[3]) end
            made[i] = b
        end
        f.Refresh = function() for _, b in ipairs(made) do b:SetEnabled(not enabledIf or enabledIf()) end end
        return f
    end
    local function TabReset()
        local name = tab
        local f = Buttons({ { "Reset this tab", function() StaticPopup_Show("OVERLAYMAP_RESET_TAB", name, nil, name) end,
            "Puts every option on this tab back to its default." } })
        f.isReset = true
        -- (narrower than the options' column: just its words)
        f:SetWidth(170)
        local b = select(1, f:GetChildren())
        if b then b:SetWidth(150) end
    end
    local function ZoneOn() return db.zoneBorder and Zone.Installed() end
    local function ZoneOM() return ZoneOn() and OpenMapLoaded() end

    tab = "General"
    Check("overlay", "Full-screen overlay")
    Cycle("mode", "Key", Wizard.MODE_CHOICES)
    Slider("scale", "Size", 0.3, 2.5, 0.05, NotOverlay, true)
    Slider("width", "Width", 0.5, 1.5, 0.05, NotOverlay, true)
    Slider("opacity", "Map opacity", 0, 1, 0.05)
    Buttons({ { "Move the map", function() ShowMover() end, "Shows a box the size of the map: drag it, then right-click it when done." },
        { "Reset position", function() db.x, db.y = 0, 0 if mover and mover:IsShown() then ShowMover() end ApplyLook() end,
            "Puts the map back in the middle of the screen." } }, NotOverlay, "Move Reset position")
    Check("rememberZoom", "Open at last zoom")
    Check("noFade", "Don't fade while moving")
    TabReset()

    tab = "Markers"
    Slider("pinOpacity", "Marker opacity", 0.1, 1, 0.05)
    Slider("markerSize", "Marker size", 0.5, 2.5, 0.05)
    Check("onlyMe", "Show only my arrow")
    Check("arrowCustom", "Custom arrow size")
    Slider("arrowSize", "My arrow size", 0.5, 3, 0.05, ArrowOwn)
    Slider("arrowOpacity", "My arrow opacity", 0.1, 1, 0.05, ArrowOwn)
    TabReset()

    tab = "Style"
    Cycle("style", "Style", STYLE_CHOICES)
    Cycle("edge", "Fade at the edges", EDGE_CHOICES, StandardStyle)
    Cycle("shape", "Edge shape", SHAPE_CHOICES, StandardStyle)
    Slider("outlineLines", "Line strength", 0.1, 1, 0.05, OutlineStyle)
    Slider("outlineBack", "Background darkness", 0, 1, 0.05, OutlineStyle)
    TabReset()

    tab = "Zone borders"
    Check("zoneBorder", "Apply borders to zones", Zone.Installed, "Apply borders to zones (needs download)",
        "Zone borders need the Overlay Map: Zone Borders addon, a separate download (from where you got "
        .. "Overlay Map). Install it next to Overlay Map and restart the game.")
    Check("zoneSoft", "Fade at the zone edges", ZoneOn)
    Slider("zoneDim", "Rest of map visibility", 0, 0.6, 0.05, ZoneOn)
    Cycle("zoneFitMode", "Auto-zoom to zone", Wizard.FIT_CHOICES, ZoneOn)
    Slider("keepZoomTime", "Auto-zoom pause", 0, 120, 5, function() return ZoneOn() and db.zoneFitMode ~= "off" end, nil,
        function(v) return v < 0.5 and "Off" or string.format("%d s", v + 0.5) end)
    Check("zoneKeep", Keep.NeedsOMName("Keep the border over the sea and between zones"), ZoneOM)
    Slider("zoneWhole", Keep.NeedsOMName("Show the whole map below this zone size"), 0.15, 0.85, 0.05, ZoneOM)
    Check("zoneView", Keep.NeedsOMName("Border the zone in the middle of the view"), ZoneOM)
    TabReset()

    tab = "Behavior"
    Check("clickThrough", "Click through the map")
    Check("follow", "Center on me")
    Check("fitPlaces", "Auto-zoom caves", OpenMapLoaded, "Auto-zoom caves (needs OpenMap)",
        "\"Auto-zoom caves\" needs OpenMap, which draws the caves and mines out in the world. Install OpenMap to use it.")
    Check("liveMinimap", "Minimap as map in dungeons")
    TabReset()

    tab = "Hide while open"
    Check("hideMinimap", "Minimap")
    for _, group in ipairs(HIDE_GROUPS) do
        Keep.DESC[group.key] = Keep.DESC[group.key] or "Hidden while the map is open, and back when it closes."
        Check(group.key, group.label)
    end
    Check("hideNames", "Character names")
    TabReset()

    tab = "Panel button"
    Cycle("buttonMode", "Panel button", { { "hover", "On hover" }, { "show", "Always" }, { "hide", "Hidden" } })
    Cycle("buttonCorner", "Corner", { { "TOPRIGHT", "Top right" }, { "TOPLEFT", "Top left" },
        { "BOTTOMRIGHT", "Bottom right" }, { "BOTTOMLEFT", "Bottom left" } })
    Slider("buttonOpacity", "Opacity", 0, 1, 0.05)
    Slider("buttonNearOpacity", "Opacity up close", 0, 1, 0.05)
    Slider("buttonSize", "Size", 14, 48, 1, nil, nil, function(v) return string.format("%d", v + 0.5) end)
    TabReset()

    local none = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    none:SetText("No option matches.")

    -- the rows of the tab chosen, or every row the search finds (with its tab's name over each group)
    O.headers = {}
    local function Header(i, text, y)
        local h = O.headers[i]
        if not h then
            h = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            O.headers[i] = h
        end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 16, y)
        h:SetText(text)
        h:Show()
        return h
    end
    function O.Layout()
        local q = O.query ~= "" and O.query or nil
        for name, b in pairs(O.tabs) do
            local on = not q and name == db.optionsTab
            b.text:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
            b.line:SetShown(on)
        end
        for _, h in ipairs(O.headers) do h:Hide() end
        local y, lastTab, nh, found = 0, nil, 0, false
        local firstInGroup = true
        local descX = 16 + CONTROL + 14
        local width = math.max(300, (sf:GetWidth() or 570))
        local descW = math.max(120, width - descX - 8)
        for _, f in ipairs(O.rows) do
            local shown
            if q then shown = not f.isReset and f.search:find(q, 1, true) ~= nil
            else shown = f.tab == db.optionsTab end
            f:SetShown(shown)
            if f.desc then f.desc:SetShown(shown) end
            if shown then
                found = true
                if q and f.tab ~= lastTab then
                    lastTab, nh = f.tab, nh + 1
                    Header(nh, f.tab, y - 6)
                    y = y - 24
                    firstInGroup = true
                end
                -- (a faint line between options, and room around each, so each line of help reads as its own)
                do
                    if not f.sep then
                        f.sep = content:CreateTexture(nil, "ARTWORK")
                        f.sep:SetColorTexture(0.75, 0.55, 0.15, 0.18)
                        f.sep:SetHeight(1)
                    end
                end
                if f.sep then
                    f.sep:ClearAllPoints()
                    f.sep:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
                    f.sep:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y)
                    f.sep:SetShown(not firstInGroup)
                end
                f:ClearAllPoints()
                if f.isReset then
                    -- (at the bottom of the window, centred, away from the options so it isn't pressed by mistake;
                    -- the line closes the tab's options)
                    if f:GetParent() ~= canvas then f:SetParent(canvas) end
                    f:SetPoint("BOTTOM", canvas, "BOTTOM", 0, 14)
                else
                    f:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y - 10)
                end
                local h = f.height
                if f.desc then
                    f.desc:ClearAllPoints()
                    f.desc:SetPoint("TOPLEFT", content, "TOPLEFT", descX, y - 10)
                    f.desc:SetWidth(descW)
                    h = math.max(h, f.desc:GetStringHeight() + 4)
                end
                if not f.isReset then y = y - h - 12 end
                firstInGroup = false
            elseif f.sep then
                f.sep:Hide()
            end
        end
        none:ClearAllPoints()
        none:SetPoint("TOPLEFT", 20, -8)
        none:SetShown(q ~= nil and not found)
        content:SetSize(width, math.max(1, -y + 8))
        Keep.ScrollFit(sf, content)
    end
    O.Top()
end

StaticPopupDialogs.OVERLAYMAP_RESET_TAB = {
    text = "Put the options on the %s tab back to their defaults?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, name) Keep.ResetTab(name) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- A tab's options back to their defaults (Size and Width laid out again with the fade)
function Keep.ResetTab(name)
    local shape = false
    for _, f in ipairs(Keep.options.rows) do
        if f.tab == name and f.key and DEFAULTS[f.key] ~= nil then
            if f.key == "scale" or f.key == "width" then shape = true end
            db[f.key] = DEFAULTS[f.key]
        end
    end
    if name == "General" then db.x, db.y = 0, 0 end
    SyncOverlay()
    if shape and compact then Zone.Reshape() else ApplyLook() end
    Keep.RefreshAll()
end

local function BuildOptions()
    if not Settings then return end
    if Keep.USE_TABS and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, err = pcall(Keep.TabOptions)
        if ok then return end
        geterrorhandler()(err)
    end
    Keep.ListOptions()
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
    do
        local cost = Zone.cost
        Say(string.format("Edges laid: %d times in the last %d s, %.0f ms in all", cost.n,
            math.floor(GetTime() - cost.since + 0.5), cost.ms))
        Say(string.format("Last opening: %.0f ms, then %.0f ms", Zone.openMs or 0, Zone.openMs2 or 0))
        local P = Zone.openParts or {}
        Say("  opened with the game's state " .. tostring(P.state or "?")
            .. (P.why and (", the small map action gave: " .. P.why) or "")
            .. (Zone.smallFails and " (the small map action opened it full screen)" or ""))
        Say("  map sized before the game laid it out: " .. (P.pre == "done" and "yes"
            or P.pre == "sized" and "yes, before it opened (zoom steps only after)" or "no"))
        Say(string.format("  game's map %.0f, hiding the interface %.0f + %.0f, look %.0f + %.0f, zoom %.0f, "
            .. "click through %.0f ms; slowest frame in the first 1.5 s: %.0f ms", P.game or 0, P.hide or 0,
            P.hide2 or 0, P.look or 0, P.look2 or 0, P.zoom or 0, P.click or 0, (Zone.worstFrame or 0) * 1000))
        local w = Zone.watchCost
        Say(string.format("Upkeep (5 times a second): %d times in the last %d s, %.1f ms each on average", w.n,
            math.floor(GetTime() - w.since + 0.5), w.n > 0 and w.ms / w.n or 0))
    end
    do
        -- (your arrow: OpenMap's on a layer of its own over the markers, or the game's among them)
        local a, L = Zone.arrowFrame, Zone.arrowLayer
        local group = Map().pinPools and Map().pinPools.GroupMembersPinTemplate
        local gp
        if group and group.EnumerateActive then for pin in group:EnumerateActive() do gp = pin break end end
        Say("Your arrow: " .. (a and string.format("OpenMap's, on %s (%s %d, shown %s); markers' layer %s",
            a:GetParent() == L and "its own layer" or "another frame", L and L:GetFrameStrata() or "?",
            L and L:GetFrameLevel() or 0, tostring(L and L:IsShown()),
            layer and layer:IsShown() and (layer:GetFrameStrata() .. " " .. layer:GetFrameLevel()) or "not in use")
            or ("OpenMap's not found" .. (Zone.FindArrow() and " (but it's there)" or "")))
            .. (gp and string.format("; the game's arrow pin: %s %d, on %s", gp:GetFrameStrata(), gp:GetFrameLevel(),
                gp:GetParent() == layer and "the markers' layer" or "the map") or "; no game arrow pin"))
    end
    do
        -- (pictures on the map area itself and right inside it, shown, without Overlay Map's cut-outs)
        local list = {}
        local cv = Canvas()
        for _, fr in ipairs({ cv, cv.Child, Map() }) do
            for _, r in ipairs({ fr:GetRegions() }) do
                if r:GetObjectType() == "Texture" and r:IsShown() and r:GetAlpha() * fr:GetEffectiveAlpha() > 0.01 then
                    local file = r.GetTextureFilePath and r:GetTextureFilePath() or r:GetTexture()
                    local cut = (maskedTex.zone[r] and "z" or "") .. (maskedTex.shape[r] and "s" or "")
                    list[#list + 1] = string.format("%s:%s %s (%.0fx%.0f, %d masks%s)",
                        fr == cv and "area" or fr == Map() and "window" or "inside", tostring(r:GetDrawLayer()),
                        tostring(file):match("[^\\/]*$") or "?", r:GetWidth(), r:GetHeight(),
                        r.GetNumMaskTextures and r:GetNumMaskTextures() or -1, cut ~= "" and (", ours " .. cut) or "")
                    if #list >= 8 then break end
                end
            end
        end
        Say("Shown under the map: " .. (#list > 0 and table.concat(list, "; ") or "nothing"))
    end
    do
        local u0 = Zone.CaveHere()
        Say("Caves and dungeons: " .. (db.fitPlaces and "on" or "off") .. "; "
            .. (Zone.InDungeon() and ("in a dungeon, map " .. tostring(C_Map.GetBestMapForUnit("player")))
                or u0 and "in a cave" or ("not in a cave" .. ((IsIndoors and IsIndoors()) and " (indoors)" or "")))
            .. (Zone.caveKey and (", cave " .. Zone.caveKey .. ((Zone.caveKey < 0 and Zone.CaveShape(Zone.caveKey))
                and (" (its own shape " .. Zone.CaveShape(Zone.caveKey) .. ")")
                or (_G.OverlayMap_ZoneBordersCaves and " (box: no shape for it)"
                    or " (box: the cave shapes of Zone Borders 1.1.0 aren't loaded)"))) or "")
            .. (Zone.caveFor and ", cave fitted" or "") .. (Zone.dungeonFor and ", dungeon fitted" or ""))
        local n = Zone.caveNote
        if n then
            local okV, _, _, z = pcall(function() return _G.OpenMapAPI.GetView() end)
            Say(string.format("  last cave: %.0f s ago, %s, cave %s; zoom from %s, asked %s, took %s; now %s",
                GetTime() - n.at, n.mine and "skipped (you zoomed yourself)" or (n.instant and "as the map opened" or "while open"),
                n.size, tostring(n.from and string.format("%.2f", n.from)), tostring(n.ask and string.format("%.2f", n.ask)),
                tostring(n.got and string.format("%.2f", n.got)), tostring(okV and z and string.format("%.2f", z))))
        end
    end
    do
        -- (Dungeon Journal's dungeon map on the world map: lent or not, its button, and which pieces take clicks)
        local ns, fdj = _G.ForeverDungeonJournal_NS, _G.ForeverDungeonJournalFrame
        if ns and fdj then
            local toggle = _G.ForeverDungeonJournalWorldMapToggle
            local back = fdj.dungeonMapPanel and fdj.dungeonMapPanel:GetParent()
            local parts = {}
            for name, f in pairs({ back = back ~= fdj and back or nil, panel = fdj.dungeonMapPanel, canvas = fdj.dungeonMapCanvas,
                art = fdj.dungeonMapArtHolder }) do
                parts[#parts + 1] = string.format("%s %s%s", name, f:IsVisible() and "shown" or "hidden",
                    f.IsMouseClickEnabled and (f:IsMouseClickEnabled() and ", clicks" or ", no clicks") or "")
            end
            Say("Dungeon Journal: dungeon " .. tostring(ns.CurrentDungeon and ns.CurrentDungeon()) .. ", on the map: "
                .. tostring(ns.IsWorldMapOverlayAttached and ns.IsWorldMapOverlayAttached()) .. ", button: "
                .. (toggle and toggle:IsShown() and ("\"" .. tostring(toggle:GetText()) .. "\"") or "none")
                .. ", world map under it hidden: " .. tostring(Zone.underAlpha ~= nil) .. "; " .. table.concat(parts, "; "))
        end
    end
    do
        -- (Live Minimap in Dungeons: whether it's wanted, and where the minimap is)
        local m = Minimap
        local why = not db.liveMinimap and "option off" or not compact and "map closed" or not Zone.InDungeon() and "not in a dungeon"
            or Zone.shelved and "map closed in combat" or (not Zone.live and InCombatLockdown()) and "waiting for combat to end" or nil
        local where = "?"
        if m then
            local l, b, w, h = m:GetRect()
            local p, rel = m:GetPoint(1)
            where = string.format("shown %s, visible %s, alpha %.2f (on screen %.2f), %s %d, parent %s, at %s of %s, %.0f,%.0f %.0fx%.0f, scale %.2f (on screen %.2f), zoom %s",
                tostring(m:IsShown()), tostring(m:IsVisible()), m:GetAlpha(), m:GetEffectiveAlpha(), m:GetFrameStrata(), m:GetFrameLevel(),
                tostring(m:GetParent() and (m:GetParent():GetName() or "?")), tostring(p), tostring(rel and (rel.GetName and rel:GetName() or "?")),
                l or -1, b or -1, w or 0, h or 0, m:GetScale(), m:GetEffectiveScale(), tostring(m.GetZoom and m:GetZoom()))
        end
        Say("Live minimap: " .. (Zone.live and "on the map" or ("not on the map (" .. tostring(why or "?") .. ")"))
            .. (Zone.live and Zone.live.mask and (", mask " .. tostring(Zone.live.mask):match("[^\\]*$")) or "") .. "; minimap " .. where)
    end
    do
        local v = _G.OpenMapDungeonView
        local inside, kind = IsInInstance()
        Say("OpenMap's dungeon map: " .. (v and string.format("there, shown %s, alpha %.2f, on %s, %.0fx%.0f",
            tostring(v:IsShown()), v:GetAlpha(), v:GetParent() == Canvas() and "the map area" or tostring(v:GetParent() and v:GetParent():GetName()),
            v:GetWidth(), v:GetHeight()) or "not made yet") .. "; in an instance: " .. tostring(inside) .. " " .. tostring(kind)
            .. "; since opening: " .. ((Zone.dvLog and #Zone.dvLog > 0) and table.concat(Zone.dvLog, ", ") or "nothing"))
    end
    do
        -- (what Overlay Map hid on the map's window and in the map area: other addons' frames among them)
        local names = {}
        for f in pairs(stopped) do
            if #names >= 14 then break end
            local w, h = f:GetSize()
            local parent = f:GetParent()
            names[#names + 1] = string.format("%s (%s, %.0fx%.0f)", f:GetName() or (f.GetDebugName and f:GetDebugName()) or "?",
                parent == Map() and "window" or parent == Canvas() and "area" or "other", w or 0, h or 0)
        end
        Say("Hidden while open: " .. (#names > 0 and table.concat(names, "; ") or "nothing"))
    end
    Say("Zone Borders download: " .. Zone.Status() .. (Zone.loadReason and (" (" .. tostring(Zone.loadReason) .. ")") or ""))
    if db.zoneBorder then
        local info = type(Zone.zoneNow) == "number" and C_Map.GetMapInfo(Zone.zoneNow)
            or (Zone.zoneNow and { name = "a cave" })
        Say("Zone border: " .. (Zone.zoneNow and (Zone.zoneNow .. " " .. tostring(info and info.name)
            .. (Zone.zoneAnchor and string.format(", placed at %.0f, %.0f, %.0f x %.0f", Zone.zoneAnchor:GetLeft() or 0,
                Zone.zoneAnchor:GetTop() or 0, Zone.zoneAnchor:GetWidth(), Zone.zoneAnchor:GetHeight()) or ""))
            or ("none, " .. tostring(Zone.why or "?"))))
        local okV, _, _, z = pcall(function() return _G.OpenMapAPI.GetView() end)
        if Zone.zoneNow and okV and type(z) == "number" then
            Say(string.format("  fills %d%% of the view; rest of the map at %s%%%s", Zone.Fill(Zone.zoneNow, z) * 100 + 0.5,
                tostring(Zone.level), Zone.want ~= Zone.shown and (", changing to " .. tostring(Zone.want)) or ""))
        end
    end
    -- the draw order of the two layers: the markers' icons and the other addons' icons (levels)
    do
        local low, high, n = nil, nil, 0
        local function Scan(fr, depth)
            local l = fr:GetFrameLevel()
            low, high = math.min(low or l, l), math.max(high or l, l)
            if depth > 0 then for _, c in ipairs({ fr:GetChildren() }) do Scan(c, depth - 1) end end
        end
        for pin in pairs(moved) do
            local w, h = pin:GetSize()
            if pin:IsShown() and (w or 0) < 200 and (h or 0) < 200 then n = n + 1 Scan(pin, 2) end
        end
        Say(string.format("Order: marker layer %s, icon layer %s; %d markers, levels %s to %s",
            layer and layer:IsShown() and (layer:GetFrameStrata() .. " " .. layer:GetFrameLevel()) or "not in use",
            viewLayer and viewLayer:IsShown() and (viewLayer:GetFrameStrata() .. " " .. viewLayer:GetFrameLevel()) or "not in use",
            n, tostring(low), tostring(high)))
        for f in pairs(iconLayers) do
            local levels = {}
            SaveLevels(f, levels, 5)
            local bottom, top = nil, nil
            for fr, l in pairs(levels) do
                if fr ~= f then bottom, top = math.min(bottom or l, l), math.max(top or l, l) end
            end
            Say(string.format("   icon layer: on %s (%s), level %d, its icons %s to %s",
                f:GetParent() == viewLayer and "Overlay Map's icon layer" or "the map", f:GetFrameStrata(), f:GetFrameLevel(),
                tostring(bottom), tostring(top)))
        end
    end
    if top and top.GetFrameLevel then
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
        local low = name and name:lower() or ""
        if loaded and name and (low:find("map") or low:find("questie") or low:find("coord") or low:find("journal")
            or low:find("dungeon")) then
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
                        .. (mouseOff[fr] and ", mouse off" or "") .. (mouseLater[fr] and ", mouse back after combat" or "")
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
        local fixed = fr.HasFixedFrameLevel and fr:HasFixedFrameLevel()
        return string.format("%s  %.0fx%.0f, scale %.2f (on screen %.2f), alpha %.2f, %s %d%s%s", what, w or 0, h or 0,
            fr:GetScale(), fr:GetEffectiveScale(), fr:GetEffectiveAlpha(), fr:GetFrameStrata(), fr:GetFrameLevel(),
            fixed and " fixed" or "", fr:IsShown() and "" or ", hidden")
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
    elseif msg == "names" then
        Keep.NamesBack()
    elseif msg == "setup" then
        Wizard.Open()
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
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_REGEN_DISABLED" then
        ExtrasEnterCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ExtrasLeaveCombat()
        if Zone.shelved then Close() end -- (closed during combat: now for real)
        if Wizard.afterCombat then
            Wizard.afterCombat = nil
            Wizard.Open()
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if compact and db.clickThrough then ApplyClickThrough() end
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
        -- (the two fit options are one now)
        if db.zoneFitMode ~= "off" and db.zoneFitMode ~= "enter" and db.zoneFitMode ~= "open" then
            if db.zoneFitOpen then db.zoneFitMode = "open"
            elseif db.zoneFit == false then db.zoneFitMode = "off"
            else db.zoneFitMode = "enter" end
        end
        db.zoneFit, db.zoneFitOpen = nil, nil
        if db.zoneViewOff == nil then db.zoneView, db.zoneViewOff = false, true end -- (a test version had it on)
        if not SHAPE_FILES[db.shape] then db.shape = DEFAULTS.shape end
        if db.zoneOutside == "hide" then db.zoneDim = 0 end -- (an earlier test's setting)
        db.zoneOutside = nil
        if type(db.zoneDim) ~= "number" then db.zoneDim = DEFAULTS.zoneDim end
        if db.style ~= "standard" and db.style ~= "torn" and db.style ~= "outlines" then db.style = DEFAULTS.style end
        local corners = { TOPRIGHT = true, TOPLEFT = true, BOTTOMRIGHT = true, BOTTOMLEFT = true }
        if not corners[db.buttonCorner] then db.buttonCorner = DEFAULTS.buttonCorner end
        if db.buttonMode ~= "show" and db.buttonMode ~= "hover" and db.buttonMode ~= "hide" then
            db.buttonMode = "hover"
        end
        BuildOptions()
    elseif event == "PLAYER_LOGOUT" then
        -- (logging out or quitting with the map open: names back before the game saves its options)
        if db and db.namesSaved then
            for n, v in pairs(db.namesSaved) do pcall(SetCVar, n, v) end
            db.namesSaved = nil
        end
    elseif event == "PLAYER_LOGIN" then
        HookMap()
        ShowNames() -- (names left hidden if the game closed with the map open)
        Keep.NamesAfterCrash()
        -- OpenMap's view moved: the zone border follows at once (not only once a second)
        local api = _G.OpenMapAPI
        if api and api.RegisterCallback then
            pcall(api.RegisterCallback, Zone, "OpenMap_ViewChanged", function()
                if compact and api.GetView then
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
