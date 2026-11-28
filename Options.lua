-- Overlay Map: the small panel on the map, its button, the setup wizard and the main options.
-- The files share one table, ns, and load in the order of OverlayMap.toc (Core.lua first).

local ADDON_NAME, ns = ...
local Keep, Zone, Wizard, Outline = ns.Keep, ns.Zone, ns.Wizard, ns.Outline
local db
ns.dbSetters[#ns.dbSetters + 1] = function(t) db = t end
-- From the files before this one
local DEFAULTS, Say, Map, Canvas, OpenMapLoaded, HIDE_GROUPS = ns.DEFAULTS, ns.Say, ns.Map, ns.Canvas, ns.OpenMapLoaded, ns.HIDE_GROUPS
local RefitNow, ApplyOpacity, StopFade, UnmaskKind, ApplyEdges, Open = ns.RefitNow, ns.ApplyOpacity, ns.StopFade, ns.UnmaskKind, ns.ApplyEdges, ns.Open
local Close, ShowMover = ns.Close, ns.ShowMover

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
    if not ns.compact then return end
    Zone.refitAgain = nil
    ns.shapeGen = ns.shapeGen + 1
    local gen = ns.shapeGen
    ns.reshaping = true
    if ns.refitTimer then ns.refitTimer:Cancel() ns.refitTimer = nil end
    ns.FadeTo(0, 0.12, function()
        if gen ~= ns.shapeGen then return end
        if not ns.compact then StopFade() return end
        -- (with OpenMap: the view kept where it was, with the land the same size on screen; OpenMap
        -- keeps its zoom number, which in a wider area made the land bigger)
        local view
        if Zone.OpenMapStitched() then
            local ok, u, v, z = pcall(_G.OpenMapAPI.GetView)
            if ok and type(u) == "number" and type(z) == "number" then view = { u, v, z, Zone.FitPx() } end
        end
        ns.settling = true
        ns.ApplyLook()      -- (the map re-fits at once while it's hidden)
        if refit then RefitNow() end
        C_Timer.After(0.15, function()
            if gen ~= ns.shapeGen then return end
            if not ns.compact then StopFade() return end
            local fit = Zone.FitPx()
            if view and view[4] and fit then
                local om = Zone.OpenMapModule()
                local zoom = view[3] * view[4] / fit
                if not (om and om.ShowNow and pcall(om.ShowNow, view[1], view[2], zoom)) then
                    pcall(_G.OpenMapAPI.ShowWorld, view[1], view[2], zoom)
                end
            end
            ns.settling = false
            ns.reshaping = false
            ns.ApplyLook()
            ns.FadeTo(1, 0.2)
            -- (the width changed again meanwhile: once more)
            if Zone.refitAgain then
                Zone.refitAgain = nil
                ns.QueueRefit()
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
    "edge", "shape", "zoneBorder", "zoneSoft", "zoneDim", "clickThrough", "moveFade", "outlineLines", "outlineBack" }
-- Overlay Mode the first time it's turned on: see-through, solid markers, large soft edges,
-- click-through (the rest as the normal map has them)
local OVERLAY_START = { opacity = 0.3, pinOpacity = 1, edge = 3, clickThrough = true, moveFade = 0 }

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
    if ns.compact then ApplyShape() end
end

-- Each option's line of help, shown when hovering it in the small panel and the setup wizard
Keep.TIPS = {
    sticky = "The map stays open until you click its small X. The key and Escape don't close it.",
    stickyCorner = "The corner of the map the X sits in.",
    moveFadeFlight = "With Fade while moving: the map doesn't fade while you're on a flight.",
    overlay = "The map fills the whole screen, see-through and click-through. It keeps settings of its own.",
    scale = "Size of the map. Applied when you let go of the slider.",
    width = "Width of the map compared to its usual shape (lower: more square). Applied when you let go.",
    opacity = "How see-through the map itself is. At 0%, only the markers show.",
    pinOpacity = "How see-through the markers are: quests, vendors, your arrow and other addons' icons.",
    markerSize = "Size of the markers, Questie's and OpenMap's icons too.",
    onlyMe = "Hides every marker except your own arrow.",
    caveMouths = "A small marker at the entrance of caves and mines on the map (hover it for the name). Needs OpenMap.",
    style = "Standard, Torn parchment (torn, burnt paper edges) or Outlines (white lines of cliffs, water and roads; needs the Overlay Map: Outlines download).",
    edge = "The map fades out towards its edges, like other games' overlay maps. Standard style only.",
    shape = "The shape the map's edges fade into. With \"Fade at the edges\" off, it's cut sharp in that shape.",
    outlineLines = "How strong the white lines are.",
    outlineBack = "How dark the background behind the lines is. At 0%, only the lines.",
    zoneBorder = "Cuts the map to your zone's outline (inside a cave, to the cave's).",
    zoneSoft = "The zone fades in from its border, instead of a sharp cut.",
    zoneDim = "How much of the map outside your zone shows. At 0% it's hidden.",
    zoneFit = "Zooms the map so all of your zone fits: when you enter a new zone, every time the map opens, or as you leave a town or capital. Choose any of them.",
    fitEnter = "Each time you enter a new zone (not right after you zoomed the map yourself, nor during a flight).",
    fitOpen = "Every time the map opens, instead of \"Open at last zoom\".",
    fitLeave = "As you leave a town (Auto-zoom towns) or a capital, back out to all of the zone around it.",
    clickThrough = "Clicks go through the map to the world. Hold Shift to drag and zoom the map.",
    follow = "Keeps the map centred on you as you move. It holds still while the mouse is over the map.",
    fitPlaces = "Entering a cave or mine, the map zooms in on it, and back out as you leave.",
    fitFlights = "Auto-zoom to zone during flights too: each zone you fly into fits the map, and flying out of a town fits its zone. Towns aren't zoomed into on the way. Off: the map waits until you land.",
    fitPlacesList = "Zooms the map in on places as you enter them, and back out as you leave: caves and mines, towns (a place with an innkeeper or flight master), and the zones you fly over on a flight. My arrow: zoomed in on you every time the map opens. Choose any of them.",
    fitTowns = "Entering a town (a place with an innkeeper or flight master), the map zooms in on it, and back out as you leave.",
    townSize = "How much the map shows around a town it zooms in on, in yards across.",
    fitArrow = "Every time the map opens, it zooms in on your arrow, over the zoom it had and your zone. A cave or town you're in still zooms in on that.",
    arrowZoom = "How much the map shows around you as it opens, in yards across.",
    liveMinimap = "Inside dungeons, the game's own minimap (with your arrow) shown big in the map's place. It doesn't fade while you move.",
    mode = "Hold to show: the map shows while you hold the key. Toggle: one press shows it, the next hides it.",
}

-- A tooltip on a control (its text: the option's line of help, or `text`; frame.tipKey: a key set later, for a
-- control used for several options)
function Keep.Tip(frame, key, text)
    frame:HookScript("OnEnter", function(self)
        local tip = (frame.offTip and frame.IsEnabled and not frame:IsEnabled() and frame.offTip) or text
            or Keep.TIPS[key or frame.tipKey or ""]
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
        if ns.compact then Zone.Reshape() end
    end)
end

-- The small panel. Its options are on four tabs (Map, Look, Zone, Behavior), and rows that don't apply
-- right now aren't shown (Size and Width in Overlay Mode, the Outlines style's sliders with another
-- style). The panel keeps the height of its tallest tab, so it doesn't jump as you switch.
-- A plain slider: label on the left, value on the right, the bar under them. reshape: Size and Width,
-- laid out again once you let go (Keep.ShapeSoon)
-- (fmt: how its value reads, a percentage if none; parent.enabledIf: greyed out while it says no)
Keep.SLIDER_TOP = 6
Keep.INDENT = 20

-- An option that belongs to the one above it (shown only, or only usable, with it): moved in, with a
-- small branch line from the left, as many games show sub-options (rows: indent set by the menu)
function Keep.Branch(parent)
    local ind = parent.indent or 0
    if ind <= 0 or parent.branched then return ind end
    parent.branched = true
    local x = ind - 6
    local v = parent:CreateTexture(nil, "ARTWORK")
    v:SetColorTexture(0.75, 0.55, 0.15, 0.5)
    v:SetWidth(1)
    v:SetPoint("TOPLEFT", x, 2)
    v:SetHeight(16)
    local h = parent:CreateTexture(nil, "ARTWORK")
    h:SetColorTexture(0.75, 0.55, 0.15, 0.5)
    h:SetHeight(1)
    h:SetWidth(7)
    h:SetPoint("TOPLEFT", x, -14)
    return ind
end

-- The game's own slider look (the thin bar and its diamond, as its settings and many addons have it), when
-- this client has it; else the plain bar from before
Keep.ATLAS_OK = {}
function Keep.HasAtlas(name)
    if Keep.ATLAS_OK[name] == nil then
        Keep.ATLAS_OK[name] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true or false
    end
    return Keep.ATLAS_OK[name]
end
function Keep.StyleSlider(s)
    if Keep.HasAtlas("Minimal_SliderBar_Button") and Keep.HasAtlas("Minimal_SliderBar_Left")
        and Keep.HasAtlas("_Minimal_SliderBar_Middle") and Keep.HasAtlas("Minimal_SliderBar_Right") then
        local l = s:CreateTexture(nil, "BACKGROUND")
        l:SetAtlas("Minimal_SliderBar_Left", true)
        l:SetPoint("LEFT", 0, 0)
        local r = s:CreateTexture(nil, "BACKGROUND")
        r:SetAtlas("Minimal_SliderBar_Right", true)
        r:SetPoint("RIGHT", 0, 0)
        local m = s:CreateTexture(nil, "BACKGROUND")
        m:SetAtlas("_Minimal_SliderBar_Middle", true)
        m:SetPoint("LEFT", l, "RIGHT")
        m:SetPoint("RIGHT", r, "LEFT")
        local thumb = s:CreateTexture(nil, "ARTWORK")
        thumb:SetAtlas("Minimal_SliderBar_Button", true)
        s:SetThumbTexture(thumb)
        return
    end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.5, 0.4, 0.18, 1)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    s:GetThumbTexture():SetSize(8, 14)
    s:GetThumbTexture():SetVertexColor(1, 0.85, 0.3, 1)
end

-- The arrows at each end of a slider: one step a click
function Keep.Stepper(parent, side)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local atlas = side == "left" and "Minimal_SliderBar_Button_Left" or "Minimal_SliderBar_Button_Right"
    if Keep.HasAtlas(atlas) then
        b:SetNormalAtlas(atlas)
        b:SetHighlightAtlas(atlas, "ADD")
        b:SetDisabledAtlas(atlas)
        local d = b:GetDisabledTexture()
        if d then d:SetDesaturated(true) d:SetAlpha(0.5) end
    else
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("CENTER")
        t:SetText(side == "left" and "<" or ">")
        b:SetFontString(t)
        b:SetNormalFontObject("GameFontNormal")
        b:SetHighlightFontObject("GameFontHighlight")
        b:SetDisabledFontObject("GameFontDisable")
    end
    return b
end

-- A slider row: its name and value above, the bar with an arrow at each end, and the lowest and highest
-- values under its ends
local function PanelSlider(parent, key, label, minValue, maxValue, step, reshape, fmt)
    local function Format(v) return fmt and fmt(v) or string.format("%d%%", v * 100 + 0.5) end
    local function Show(fs, v) fs:SetText(Format(v)) end
    local ind = Keep.Branch(parent)
    -- (a little room above its name: apart from the option or line over it)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 12 + ind, -Keep.SLIDER_TOP)
    text:SetText(label)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPRIGHT", -12, -Keep.SLIDER_TOP)
    local barY = -19 - Keep.SLIDER_TOP
    local back, fwd = Keep.Stepper(parent, "left"), Keep.Stepper(parent, "right")
    back:SetPoint("TOPLEFT", 8 + ind, barY)
    fwd:SetPoint("TOPRIGHT", -8, barY)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", back, "TOPRIGHT", 2, 0)
    s:SetPoint("TOPRIGHT", fwd, "TOPLEFT", -2, 0)
    s:SetHeight(16)
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    Keep.StyleSlider(s)
    local low = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -1)
    low:SetText(Format(minValue))
    local high = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -1)
    high:SetText(Format(maxValue))
    -- (the row tall enough for all of it)
    local need = Keep.SLIDER_TOP + 19 + 16 + 14
    if (parent.height or 0) < need then parent.height = need parent:SetHeight(need) end
    local function Nudge(by)
        s:SetValue(math.max(minValue, math.min(maxValue, Round(s:GetValue(), step) + by * step)))
    end
    back:SetScript("OnClick", function() Nudge(-1) end)
    fwd:SetScript("OnClick", function() Nudge(1) end)
    Keep.Tip(back, key)
    Keep.Tip(fwd, key)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta) Nudge(delta) end)
    s:SetScript("OnValueChanged", function(self, v)
        v = Round(v, step)
        Show(value, v)
        if self.silent then return end
        if math.abs((db[key] or 0) - v) < 0.0001 then return end
        db[key] = v
        if reshape then
            Keep.sizing = true -- (not laid out meanwhile: Watch)
            -- (dragging: once you let go; the mouse wheel or the arrows: a moment after the last step)
            if not IsMouseButtonDown("LeftButton") then Keep.ShapeSoon(0.4) end
            return
        end
        ns.ApplyLook()
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
        back:SetEnabled(on)
        fwd:SetEnabled(on)
        s:SetAlpha(on and 1 or 0.4)
        text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
        value:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
    end
end

-- enabledIf: greyed out while it says no, with offLabel and offTip (hovered) saying why
local function PanelCheck(parent, key, label, enabledIf, offLabel, offTip)
    local ind = Keep.Branch(parent)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 8 + ind, 0)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb.offTip = offTip
    cb:SetMotionScriptsWhileDisabled(true)
    Keep.Tip(cb, key)
    cb:SetScript("OnClick", function(self)
        -- (some options ask before going on: Keep.ASK_ON, the box unticked until you say yes)
        if self:GetChecked() and Keep.ASK_ON[key] and not db[key] then
            self:SetChecked(false)
            Keep.AskOn(key)
            return
        end
        db[key] = self:GetChecked() and true or false
        SyncOverlay()
        ns.ApplyLook()
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

-- A list of switches in a drop-down: "Label: Choice, Choice  v", a click opens the list with a checkbox each
-- (items: { key, label, short [, here = function, off = label] }: here false greys it out, with the off label),
-- any number of them on. One list window, shared, closed by a click elsewhere or Escape. An owner with menuRight
-- has it opening under its right edge.
Keep.MULTI_W = 230
function Keep.MultiMenu()
    if Keep.multi then return Keep.multi end
    local m = CreateFrame("Frame", "OverlayMapChecklist", UIParent, "BackdropTemplate")
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetToplevel(true)
    m:SetClampedToScreen(true)
    m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    m:SetBackdropColor(0.05, 0.045, 0.04, 0.97)
    m:SetBackdropBorderColor(0.75, 0.55, 0.15, 0.9)
    m:EnableMouse(true)
    m:Hide()
    m.boxes = {}
    tinsert(UISpecialFrames, "OverlayMapChecklist")
    m:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
    end)
    m:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    m:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") self.owner = nil end)
    Keep.multi = m
    return m
end
function Keep.OpenMulti(owner, items, onChange)
    local m = Keep.MultiMenu()
    if m:IsShown() and m.owner == owner then m:Hide() return end
    for _, b in ipairs(m.boxes) do b:Hide() end
    for i, item in ipairs(items) do
        local b = m.boxes[i]
        if not b then
            b = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
            b:SetSize(24, 24)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            b.text:SetPoint("LEFT", b, "RIGHT", 2, 0)
            m.boxes[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 26)
        b:SetMotionScriptsWhileDisabled(true)
        b:SetScript("OnClick", function(self)
            db[item[1]] = self:GetChecked() and true or false
            onChange()
            m.Update() -- (one may grey out another)
        end)
        if not b.tipped then b.tipped = true Keep.Tip(b, nil) end
        b.tipKey = item[1]
        b:Show()
    end
    -- each box as its setting is, greyed out when its item says so
    function m.Update()
        for i, item in ipairs(items) do
            local b = m.boxes[i]
            local on = not item.here or item.here()
            b:SetEnabled(on)
            b:SetChecked(on and db[item[1]] and true or false)
            b.text:SetText(on and item[2] or (item.off or item[2]))
            b.text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
        end
    end
    m.Update()
    -- (wide enough for its longest name)
    local w = Keep.MULTI_W
    for i = 1, #items do w = math.max(w, m.boxes[i].text:GetStringWidth() + 50) end
    m:SetSize(w, 16 + #items * 26)
    m:ClearAllPoints()
    if owner.menuRight then
        m:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    else
        m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    end
    m.owner = owner
    -- (over the menu it opens from: in the same layer as the small panel, it was drawn under the panel's
    -- own rows, the options below showing through it)
    m:SetFrameStrata(owner:GetFrameStrata())
    m:SetFrameLevel(math.min(9000, owner:GetFrameLevel() + 100))
    m:Raise()
    m:Show()
end

function Keep.PanelMulti(parent, tipKey, label, items, enabledIf)
    local ind = Keep.Branch(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", 8 + ind, 1)
    b:SetPoint("TOPRIGHT", -8, 1)
    b:SetHeight(24)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    b:SetBackdropColor(1, 0.85, 0.3, 0.07)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    b:GetHighlightTexture():SetAlpha(0.15)
    local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -24, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")
    b:SetMotionScriptsWhileDisabled(true)
    Keep.Tip(b, tipKey)
    local function Words()
        local on = {}
        for _, item in ipairs(items) do if db[item[1]] then on[#on + 1] = item[3] or item[2] end end
        return label .. ": " .. (#on > 0 and table.concat(on, ", ") or "Off")
    end
    local function Changed()
        ns.ApplyLook()
        Keep.RefreshAll() -- (other rows may depend on it)
        text:SetText(Words())
    end
    b:SetScript("OnClick", function(self) Keep.OpenMulti(self, items, Changed) end)
    function parent:Refresh()
        local on = not (enabledIf or parent.enabledIf) or (enabledIf or parent.enabledIf)()
        b:SetEnabled(on)
        text:SetText(Words())
        text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
        arrow:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
        if not on and Keep.multi and Keep.multi.owner == b then Keep.multi:Hide() end
    end
end

-- A choice among a few: "< Label: Choice >", the arrows (or a click on the text) stepping through them
local function PanelCycle(parent, key, label, choices, enabledIf)
    local ind = Keep.Branch(parent)
    local function Arrow(side)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(20, 22)
        b:SetPoint(side == "left" and "TOPLEFT" or "TOPRIGHT", side == "left" and 10 + ind or -10, 0)
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
    back:SetPoint("TOPLEFT", 8 + ind, 1)
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
        ns.ApplyLook()
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
    if not ns.panel or not ns.mapButton then return end
    local corner = db.buttonCorner or "TOPRIGHT"
    local right, bottom = corner:find("RIGHT") ~= nil, corner:find("BOTTOM") ~= nil
    local inside = db.overlay
    if not inside then
        -- (room beside the button, on the outside of the map's corner)
        local need = (ns.panel:GetWidth() + 6) * ns.panel:GetEffectiveScale()
        local b, u = ns.mapButton:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if right then
            inside = (ns.mapButton:GetRight() or 0) * b + need > (UIParent:GetRight() or 0) * u
        else
            inside = (ns.mapButton:GetLeft() or 0) * b - need < 0
        end
    end
    local v = bottom and "BOTTOM" or "TOP"
    ns.panel:ClearAllPoints()
    if inside then
        -- (into the map: under the button, or above it in a bottom corner)
        local side = right and "RIGHT" or "LEFT"
        ns.panel:SetPoint(v .. side, ns.mapButton, (bottom and "TOP" or "BOTTOM") .. side, 0, bottom and 6 or -6)
    else
        ns.panel:SetPoint(v .. (right and "LEFT" or "RIGHT"), ns.mapButton, v .. (right and "RIGHT" or "LEFT"), right and 6 or -6, 0)
    end
end

Keep.TABS = { "Map", "Markers", "Style", "Zone", "Behavior" } -- (named as the main options' tabs)
Keep.PANEL_W = 300 -- (five tabs across)

local function BuildPanel()
    ns.panel = CreateFrame("Frame", "OverlayMapPanel", UIParent, "BackdropTemplate")
    ns.panel:SetWidth(Keep.PANEL_W)
    ns.panel:SetFrameStrata("FULLSCREEN_DIALOG")
    ns.panel:SetClampedToScreen(true)
    ns.panel:EnableMouse(true)
    ns.panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    ns.panel:SetBackdropColor(0.05, 0.045, 0.04, 0.95)
    ns.panel:SetBackdropBorderColor(0.75, 0.55, 0.15, 0.9)
    local title = ns.panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Overlay Map")
    local close = CreateFrame("Button", nil, ns.panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() ns.panel:Hide() end)

    if not tContains(Keep.TABS, db.panelTab) then db.panelTab = "Map" end
    -- the tabs: a row of buttons under the title, the one shown in gold and underlined
    -- (each as wide as its name plus the same room: the gaps between the names alike, not the buttons)
    local tabs = {}
    local list = {}
    for i, name in ipairs(Keep.TABS) do
        local b = CreateFrame("Button", nil, ns.panel)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("CENTER")
        t:SetText(name)
        b.text = t
        list[i] = b
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
    local names = 0
    for _, b in ipairs(list) do names = names + b.text:GetStringWidth() end
    local room = math.max(0, (Keep.PANEL_W - 20 - names) / #list)
    local x = 10
    for _, b in ipairs(list) do
        local w = b.text:GetStringWidth() + room
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x, -30)
        x = x + w
    end
    local base = ns.panel:CreateTexture(nil, "ARTWORK")
    base:SetColorTexture(0.75, 0.55, 0.15, 0.6) -- (3:1 against the panel: a line that groups things must be seen)
    base:SetHeight(1)
    base:SetPoint("TOPLEFT", 10, -52)
    base:SetPoint("TOPRIGHT", -10, -52)

    local rows, tab, indent = {}, nil, 0
    -- a row: a frame across the panel, `height` tall; shown on its tab when `when` (if any) says so; moved in
    -- under the option it belongs to while made inside Sub
    local function Row(height, when)
        local f = CreateFrame("Frame", nil, ns.panel)
        f:SetHeight(height)
        f.height, f.tab, f.when, f.indent = height, tab, when, indent
        f.Refresh = function() end
        rows[#rows + 1] = f
        return f
    end
    local function Sub(make) indent = Keep.INDENT make() indent = 0 end
    local function Gap(h) Row(h) end
    -- a thin line between groups of rows (shown when `when` says so, as a row)
    -- a group's title, with the faint line after it (decoration, not held to 3:1)
    local function Head(title, when)
        local f = Row(26, when)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 12, -8)
        t:SetText(title)
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.75, 0.55, 0.15, 0.3)
        line:SetHeight(1)
        line:SetPoint("LEFT", t, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    end

    local function Fading() return (db.moveFade or 0) > 0 end
    tab = "Map"
    Head("Size")
    PanelCheck(Row(32), "overlay", "Full-screen overlay")
    PanelSlider(Row(56, NotOverlay), "scale", "Size", 0.3, 2.5, 0.05, true)
    PanelSlider(Row(56, NotOverlay), "width", "Width", 0.5, 1.5, 0.05, true)
    Head("Fading")
    PanelSlider(Row(56), "opacity", "Map opacity", 0, 1, 0.05)
    PanelSlider(Row(56), "moveFade", "Fade while moving", 0, 0.9, 0.05, nil,
        function(v) return v < 0.025 and "Off" or string.format("%d%%", v * 100 + 0.5) end)
    Sub(function()
        PanelCheck(Row(28, Fading), "moveFadeHover", "Solid under the mouse")
        PanelCheck(Row(28, Fading), "moveFadeCombat", "Also in combat")
        PanelCheck(Row(28, Fading), "moveFadeFlight", "Not on flights")
    end)
    tab = "Markers"
    Head("All markers")
    PanelSlider(Row(56), "pinOpacity", "Marker opacity", 0.1, 1, 0.05)
    PanelSlider(Row(56), "markerSize", "Marker size", 0.5, 2.5, 0.05)
    PanelCheck(Row(28), "onlyMe", "Show only my arrow")
    PanelCheck(Row(28, Fading), "moveFadeMarkers", "Fade markers too")
    PanelCheck(Row(28), "caveMouths", "Cave entrances", OpenMapLoaded, "Cave entrances (needs OpenMap)")
    Head("Your arrow")
    PanelCheck(Row(28), "arrowCustom", "Custom arrow size")
    Sub(function()
        PanelSlider(Row(56, ArrowOwn), "arrowSize", "My arrow size", 0.5, 3, 0.05)
        PanelSlider(Row(56, ArrowOwn), "arrowOpacity", "My arrow opacity", 0.1, 1, 0.05)
    end)
    PanelCheck(Row(28, function() return Fading() and db.moveFadeMarkers end), "arrowNoFade", "My arrow doesn't fade")
    tab = "Style"
    PanelCycle(Row(30), "style", "Style", STYLE_CHOICES)
    Sub(function()
        PanelCycle(Row(30), "edge", "Fade at the edges", EDGE_CHOICES, StandardStyle)
        PanelCycle(Row(34), "shape", "Edge shape", SHAPE_CHOICES, StandardStyle)
        PanelSlider(Row(56, OutlineStyle), "outlineLines", "Line strength", 0.1, 1, 0.05)
        PanelSlider(Row(56, OutlineStyle), "outlineBack", "Background darkness", 0, 1, 0.05)
    end)
    tab = "Zone"
    local function ZoneOn() return db.zoneBorder and Zone.Installed() end
    PanelCheck(Row(28), "zoneBorder", "Apply borders to zones", Zone.Installed, "Apply borders to zones (needs download)",
        "Zone borders need the Overlay Map: Zone Borders addon, a separate download (from where you got "
        .. "Overlay Map). Install it next to Overlay Map and restart the game.")
    Sub(function()
        PanelCheck(Row(30, ZoneOn), "zoneSoft", "Fade at the zone edges")
        PanelSlider(Row(56, ZoneOn), "zoneDim", "Rest of map visibility", 0, 0.6, 0.05)
        Keep.PanelMulti(Row(30, ZoneOn), "zoneFit", "Auto-zoom", Keep.FIT_ITEMS)
    end)
    tab = "Behavior"
    Head("Controls")
    PanelCycle(Row(32), "mode", "Key", Wizard.MODE_CHOICES)
    PanelCheck(Row(28), "sticky", "Sticky map")
    Sub(function()
        PanelCycle(Row(32, function() return db.sticky end), "stickyCorner", "X corner", Keep.CORNER_CHOICES)
    end)
    PanelCheck(Row(28), "clickThrough", "Click through the map (Shift: use it)")
    PanelCheck(Row(28), "follow", "Center on me")
    Head("Places")
    Keep.PanelMulti(Row(30), "fitPlacesList", OpenMapLoaded() and "Auto-zoom" or "Auto-zoom (needs OpenMap)",
        Keep.PLACE_ITEMS, OpenMapLoaded)
    Sub(function()
        PanelSlider(Row(56, function() return OpenMapLoaded() and db.fitTowns end), "townSize", "Town zoom", 200, 1000, 50, nil,
            function(v) return string.format("%d yd", v + 0.5) end)
        PanelSlider(Row(56, function() return OpenMapLoaded() and db.fitArrow end), "arrowZoom", "Arrow zoom", 100, 2000, 50,
            nil, function(v) return string.format("%d yd", v + 0.5) end)
    end)
    PanelCheck(Row(28), "liveMinimap", "Minimap as map in dungeons")
    ns.panel.rows = rows

    local move = CreateFrame("Button", nil, ns.panel, "UIPanelButtonTemplate")
    move:SetHeight(20)
    move:SetPoint("BOTTOMLEFT", 10, 34)
    move:SetPoint("BOTTOMRIGHT", -10, 34)
    move:SetText("Move the map")
    move:SetScript("OnClick", function() SlashCmdList.OVERLAYMAP("move") end)
    local all = CreateFrame("Button", nil, ns.panel, "UIPanelButtonTemplate")
    all:SetHeight(20)
    all:SetPoint("BOTTOMLEFT", 10, 10)
    all:SetPoint("BOTTOMRIGHT", ns.panel, "BOTTOM", -3, 10)
    all:SetText("All options")
    all:SetScript("OnClick", function() SlashCmdList.OVERLAYMAP("") end)
    local bug = CreateFrame("Button", nil, ns.panel, "UIPanelButtonTemplate")
    bug:SetHeight(20)
    bug:SetPoint("BOTTOMLEFT", ns.panel, "BOTTOM", 3, 10)
    bug:SetPoint("BOTTOMRIGHT", -10, 10)
    bug:SetText("Report a bug")
    bug:SetScript("OnClick", function() Keep.BugReport() end)
    Keep.Tip(bug, nil, "A window with the link to report a bug and a report of your setup, ready to copy.")

    local TOP = 64 -- (the first row a little apart from the tabs' line)
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
                f:SetPoint("TOPLEFT", ns.panel, "TOPLEFT", 0, y)
                f:SetPoint("TOPRIGHT", ns.panel, "TOPRIGHT", 0, y)
                y = y - f.height
            end
        end
        for name, b in pairs(tabs) do
            local on = name == db.panelTab
            b.text:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
            b.line:SetShown(on)
        end
        ns.panel:SetHeight(TOP + tall + 4 + 58)
        move:SetEnabled(not db.overlay)
    end

    ns.panel:SetScript("OnShow", function(self)
        for _, f in ipairs(self.rows) do f:Refresh() end
        Layout()
        PlacePanel()
    end)
    RefreshPanel = function()
        if ns.panel:IsShown() then ns.panel:GetScript("OnShow")(ns.panel) end
    end
    ns.panel:Hide()
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
-- (Auto-zoom to zone: when, any of them)
-- (Auto-zoom places: which places, any of them)
Keep.PLACE_ITEMS = {
    { "fitPlaces", "Caves and mines", "Caves" },
    { "fitTowns", "Towns", "Towns" },
    { "fitFlights", "Zones on flights", "Flights" },
    { "fitArrow", "My arrow, as the map opens", "My arrow" },
}
Keep.FIT_ITEMS = {
    { "fitEnter", "Entering a zone", "Entering" },
    { "fitOpen", "Opening the map", "Opening" },
    { "fitLeave", "Leaving a town or city", "Leaving towns" },
}
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
    if ns.compact then ApplyShape(true) else ns.ApplyLook() end
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
    if key == "zoneBorder" and ns.compact then
        UnmaskKind("zone")
        UnmaskKind("shape")
        ApplyEdges()
    end
    -- (Follow Me with Fit Zone: how the two go together)
    if key == "follow" and db.follow and db.zoneBorder and Zone.AnyFit() then
        StaticPopup_Show("OVERLAYMAP_FOLLOW_FIT")
    end
    -- (Zone Border turned on: the map glides to your zone, so you see it at once)
    if key == "zoneBorder" and db.zoneBorder and ns.compact and Zone.Available() and not Zone.inCave then
        C_Timer.After(0.3, function()
            local zone = ns.compact and db.zoneBorder and Zone.PlayerZone()
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
    line:SetColorTexture(0.75, 0.55, 0.15, 0.6) -- (3:1 against the panel: a line that groups things must be seen)
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
        if ns.compact then ApplyOpacity() end
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
    PanelSlider(Wizard.Row(p, 48, NotOverlay), "scale", "Size", 0.3, 2.5, 0.05)
    PanelSlider(Wizard.Row(p, 48, NotOverlay), "width", "Width", 0.5, 1.5, 0.05)
    Wizard.Button(p, "Move the map", function() ShowMover() end, NotOverlay)
    Wizard.Note(p, "Drag the box, then right-click it when done.", 28, NotOverlay)

    p = Page("Map look")
    PanelSlider(Wizard.Row(p, 50), "opacity", "Map opacity", 0, 1, 0.05)
    PanelCycle(Wizard.Row(p, 30), "style", "Style", STYLE_CHOICES)
    Wizard.Note(p, "Torn parchment: torn, burnt paper edges. Outlines (beta): only white lines for cliffs, "
        .. "water and roads (needs the Overlay Map: Outlines download).", 44)
    PanelCycle(Wizard.Row(p, 30, StandardStyle), "edge", "Fade at the edges", EDGE_CHOICES)
    PanelCycle(Wizard.Row(p, 34, StandardStyle), "shape", "Edge shape", SHAPE_CHOICES)
    PanelSlider(Wizard.Row(p, 48, OutlineStyle), "outlineLines", "Line strength", 0.1, 1, 0.05)
    PanelSlider(Wizard.Row(p, 48, OutlineStyle), "outlineBack", "Background darkness", 0, 1, 0.05)

    p = Page("Markers")
    Wizard.Text(p, "Quests, vendors, flight points and other addons' icons on the map.", 30)
    PanelSlider(Wizard.Row(p, 48), "pinOpacity", "Marker opacity", 0.1, 1, 0.05)
    PanelSlider(Wizard.Row(p, 50), "markerSize", "Marker size", 0.5, 2.5, 0.05)
    PanelCheck(Wizard.Row(p, 28), "onlyMe", "Show only my arrow")
    Wizard.Note(p, "Hides every marker except your own arrow.", 24)
    PanelCheck(Wizard.Row(p, 28), "arrowCustom", "Custom arrow size")
    Wizard.Note(p, "Your arrow at a size and opacity of its own, apart from the other markers.", 30)
    PanelSlider(Wizard.Row(p, 48, ArrowOwn), "arrowSize", "My arrow size", 0.5, 3, 0.05)
    PanelSlider(Wizard.Row(p, 48, ArrowOwn), "arrowOpacity", "My arrow opacity", 0.1, 1, 0.05)

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
    PanelSlider(Wizard.Row(p, 50, ZoneOn), "zoneDim", "Rest of map visibility", 0, 0.6, 0.05)
    Keep.PanelMulti(Wizard.Row(p, 30, ZoneOn), "zoneFit", "Auto-zoom to zone", Keep.FIT_ITEMS)
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
    if not ns.compact then
        Open()
        Wizard.openedMap = ns.compact
    end
    Wizard.frame:Show()
    Wizard.Show(1)
    C_Timer.After(0.2, Wizard.ZoomIn)
end

-- The map zoomed in on you (with OpenMap's world; the game's own map shows the zone as it is)
function Wizard.ZoomIn()
    if not ns.compact or not Zone.OpenMapStitched() then return end
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
    if ns.compact then ApplyOpacity() end
    if Wizard.openedMap and ns.compact then Close() end
    Wizard.openedMap = nil
    if ns.mover and ns.mover:IsShown() then ns.mover:Hide() end
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
    return ns.compact and db.buttonMode ~= "hide" and (not ns.settling or (ns.panel and ns.panel:IsShown()))
end

-- Two opacities: one with the mouse on the button or close to it (its own size around it),
-- one otherwise: always ("Always") or only with the mouse over the map ("On hover").
local function MapButtonAlpha()
    local near = db.buttonSize
    if (ns.panel and ns.panel:IsShown()) or ns.mapButton:IsMouseOver(near, -near, -near, near) then
        return db.buttonNearOpacity
    end
    if db.buttonMode == "show" or Canvas():IsMouseOver() then return db.buttonOpacity end
    return 0
end

local function BuildMapButton()
    ns.mapButton = CreateFrame("Button", "OverlayMapButton", UIParent)
    ns.mapButton:SetClampedToScreen(true) -- (never off the screen, wherever the map is)
    ns.mapButton:SetSize(db.buttonSize, db.buttonSize)
    local bg = ns.mapButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local icon = ns.mapButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    ns.mapButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ns.mapButton:SetScript("OnClick", function()
        if not ns.panel then BuildPanel() end
        if ns.panel:IsShown() then
            ns.panel:Hide()
        else
            ns.panel:Show() -- (placed as it shows: PlacePanel)
        end
    end)
    ns.mapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Overlay Map options")
        GameTooltip:Show()
    end)
    ns.mapButton:SetScript("OnLeave", GameTooltip_Hide)
    -- With "On hover", it shows while the mouse is over the map (checked ten times a second,
    -- only while the map is open).
    local acc = 0
    ns.mapButton:SetScript("OnUpdate", function(self, elapsed)
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
-- Where a button goes in a corner of the map: nil while that corner is on screen (anchored to the map), else the
-- spot (UIParent's bottom left) of that corner of the part of the map on screen, with room for a button that size
local function CornerSpot(corner, size)
    local c = Canvas()
    local right, top = corner:find("RIGHT") ~= nil, corner:find("TOP") ~= nil
    local k = c:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local r, t, l, b = c:GetRight(), c:GetTop(), c:GetLeft(), c:GetBottom()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not (r and t) then return end
    r, t, l, b = r * k, t * k, l * k, b * k
    if (right and r > w) or (not right and l < 0) or (top and t > h) or (not top and b < 0) then
        local room = size + 8
        local vl, vr = math.max(l, 0), math.min(r, w)
        local vb, vt = math.max(b, 0), math.min(t, h)
        return right and math.max(vr, vl + room) - 4 or math.min(vl, vr - room) + 4,
            top and math.max(vt, vb + room) - 4 or math.min(vb, vt - room) + 4
    end
end

ns.PlaceMapButton = function()
    local c = Canvas()
    local corner = db.buttonCorner or "TOPRIGHT"
    local right, top = corner:find("RIGHT") ~= nil, corner:find("TOP") ~= nil
    local x, y = CornerSpot(corner, db.buttonSize)
    local want = corner .. (x and (":" .. math.floor(x * 10) .. ":" .. math.floor(y * 10)) or ":map")
    if ns.mapButton.placedAt == want and ns.mapButton:GetNumPoints() > 0 then return end
    ns.mapButton.placedAt = want
    ns.mapButton:ClearAllPoints()
    if x then
        ns.mapButton:SetPoint(corner, UIParent, "BOTTOMLEFT", x, y)
    else
        ns.mapButton:SetPoint(corner, c, corner, right and -4 or 4, top and -4 or 4)
    end
    if ns.panel and ns.panel:IsShown() then PlacePanel() end
    if Keep.closeButton and Keep.closeButton:IsShown() then Keep.PlaceCloseButton() end
end

-- Sticky map's X: a small close button in a corner of the map, the only way the map closes while Sticky map is on.
-- It shows as the panel button does (with the mouse over the map, or always with Always; never hidden for good, it's
-- the way out), a little smaller, and in the panel button's corner it sits beside it.
local function CloseWanted()
    return ns.compact and db.sticky and not Zone.shelved and not ns.settling or false
end
local function CloseSize() return math.max(14, math.floor(db.buttonSize * 0.8 + 0.5)) end
local function CloseAlpha()
    local b, near = Keep.closeButton, CloseSize()
    if b:IsMouseOver(near, -near, -near, near) then return db.buttonNearOpacity end
    if db.buttonMode == "show" or Canvas():IsMouseOver() then return db.buttonOpacity end
    return 0
end
function Keep.PlaceCloseButton()
    local b = Keep.closeButton
    local corner = db.stickyCorner or "TOPLEFT"
    local right, top = corner:find("RIGHT") ~= nil, corner:find("TOP") ~= nil
    local size = CloseSize()
    -- (beside the panel button, toward the middle, when they share a corner)
    local shift = 0
    if corner == (db.buttonCorner or "TOPRIGHT") and ButtonWanted() then shift = db.buttonSize + 4 end
    local dx = right and -(4 + shift) or (4 + shift)
    local x, y = CornerSpot(corner, size + shift)
    local want = corner .. ":" .. shift .. (x and (":" .. math.floor(x * 10) .. ":" .. math.floor(y * 10)) or ":map")
    if b.placedAt == want and b:GetNumPoints() > 0 then return end
    b.placedAt = want
    b:ClearAllPoints()
    if x then
        b:SetPoint(corner, UIParent, "BOTTOMLEFT", x + (right and -shift or shift), y)
    else
        b:SetPoint(corner, Canvas(), corner, dx, top and -4 or 4)
    end
end
local function BuildCloseButton()
    local b = CreateFrame("Button", "OverlayMapCloseButton", UIParent)
    b:SetClampedToScreen(true)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local x = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    x:SetPoint("CENTER", 0, 0)
    x:SetText("x")
    b.x = x
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function() if ns.compact then Close() end end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Close the map")
        GameTooltip:AddLine("Sticky map is on: the key and Escape don't close it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    local acc = 0
    b:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        local a = CloseAlpha()
        if math.abs(self:GetAlpha() - a) > 0.001 then self:SetAlpha(a) end
    end)
    Keep.closeButton = b
end
function Keep.UpdateCloseButton()
    -- (Escape as Sticky map says, it may have just been turned on or off with the map open)
    if ns.compact and not Zone.shelved then Keep.EscapeOn(true) end
    if not CloseWanted() then
        if Keep.closeButton then Keep.closeButton:Hide() end
        return
    end
    if not Keep.closeButton then BuildCloseButton() end
    local b, size = Keep.closeButton, CloseSize()
    b:SetSize(size, size)
    local font = b.x:GetFont()
    if font then b.x:SetFont(font, math.max(10, math.floor(size * 0.75)), "OUTLINE") end
    b.placedAt = nil
    Keep.PlaceCloseButton()
    if not b.recheck then
        b.recheck = true
        C_Timer.After(0, function()
            b.recheck = nil
            if b:IsShown() then b.placedAt = nil Keep.PlaceCloseButton() end
        end)
    end
    b:SetFrameStrata("FULLSCREEN")
    b:SetAlpha(CloseAlpha())
    b:Show()
end

ns.UpdateMapButton = function()
    Keep.UpdateCloseButton()
    if not ButtonWanted() then
        if ns.mapButton then ns.mapButton:Hide() end
        if ns.panel and not ns.compact then ns.panel:Hide() end
        return
    end
    if not ns.mapButton then BuildMapButton() end
    local map = Map()
    ns.mapButton:SetSize(db.buttonSize, db.buttonSize)
    ns.PlaceMapButton()
    -- (once more next frame, when the map's new size and place are laid out)
    if not ns.mapButton.recheck then
        ns.mapButton.recheck = true
        C_Timer.After(0, function()
            ns.mapButton.recheck = nil
            if ns.mapButton:IsShown() then ns.PlaceMapButton() end
        end)
    end
    ns.mapButton:SetFrameStrata("FULLSCREEN")
    ns.mapButton:SetAlpha(MapButtonAlpha())
    ns.mapButton:Show()
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
    ns.ApplyLook()
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
    ns.ApplyLook()
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
        if not ns.compact then Open() end
        -- (its panel once the map has settled; beside the options button, or the map if the button is hidden)
        C_Timer.After(0.3, function()
            if not ns.compact then return end
            if not ns.panel then BuildPanel() end
            ns.UpdateMapButton()
            ns.panel:Show()
            if not (ns.mapButton and ns.mapButton:IsShown()) then
                ns.panel:ClearAllPoints()
                ns.panel:SetPoint("TOPLEFT", Canvas(), "TOPRIGHT", 8, 0)
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
            ns.ApplyLook()
            if Wizard.Changed then Wizard.Changed(key) end
            if ns.mover and ns.mover:IsShown() then ShowMover() end
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
            { "Addons", "Which other map addons show on Overlay Map's map." },
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
        .. "Style, Fade at the edges, Shape, Click through the map and Fade while moving: what you change while it's "
        .. "on stays with Full-screen overlay, and the normal map keeps its own. Size, width and position don't apply "
        .. "while it's on.")

    Header("Map")
    Settings.CreateDropdown(P.cat, Register("mode", "Key"), function()
        local container = Settings.CreateControlTextContainer()
        container:Add("hold", "Hold to show")
        container:Add("press", "Toggle")
        return container:GetData()
    end, "Hold to show: the map shows while you hold the key. Toggle: one press shows it, the next one hides it.")
    local stickyInit = Settings.CreateCheckbox(P.cat, Register("sticky", "Sticky map"), Keep.DESC.sticky)
    Under(stickyInit, Settings.CreateDropdown(P.cat, Register("stickyCorner", "Close button corner"), function()
        local container = Settings.CreateControlTextContainer()
        for _, c in ipairs(Keep.CORNER_CHOICES) do container:Add(c[1], c[2]) end
        return container:GetData()
    end, Keep.DESC.stickyCorner), function() return db.sticky end)
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
        if ns.mover and ns.mover:IsShown() then ShowMover() end
        ns.ApplyLook()
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

    Settings.CreateCheckbox(P.cat, Register("moveFadeMarkers", "Fade markers too"),
        "With Fade while moving: the markers fade with the map as you move. Off: only the map fades, as with Map opacity.")
    Settings.CreateCheckbox(P.cat, Register("arrowNoFade", "My arrow doesn't fade"),
        "With Fade markers too: your arrow (and your party's) stays as it is while the map and the other markers fade as you move.")

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
        Settings.CreateCheckbox(P.cat, Register("fitEnter", "Auto-zoom to zone: entering a zone"),
            "Zooms the map so all of your zone fits each time you enter a new zone (not right after you zoomed it "
            .. "yourself, see \"Auto-zoom pause\", nor during a flight: when you land)."),
        Settings.CreateCheckbox(P.cat, Register("fitOpen", "Auto-zoom to zone: opening the map"),
            "Zooms the map so all of your zone fits every time the map opens, instead of \"Open at last zoom\"."),
        Settings.CreateCheckbox(P.cat, Register("fitLeave", "Auto-zoom to zone: leaving a town or city"),
            "Zooms back out to all of your zone as you leave a town (Auto-zoom towns) or a capital."),
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
    local flightInit = Settings.CreateCheckbox(P.cat, Register("fitFlights", NeedsOM("Auto-zoom flights")),
        "Needs OpenMap. Auto-zoom to zone during flights too: each zone you fly into fits the map, and flying out "
        .. "of a town fits its zone. Off: the map waits until you land.")
    if flightInit and flightInit.AddModifyPredicate then flightInit:AddModifyPredicate(OpenMapLoaded) end
    local townInit = Settings.CreateCheckbox(P.cat, Register("fitTowns", NeedsOM("Auto-zoom towns")),
        "Needs OpenMap. Entering a town (a place with an innkeeper or flight master, not a capital), the map "
        .. "zooms in on it, and back out when you leave.")
    if townInit and townInit.AddModifyPredicate then townInit:AddModifyPredicate(OpenMapLoaded) end
    local arrowInit = Settings.CreateCheckbox(P.cat, Register("fitArrow", NeedsOM("Auto-zoom my arrow")),
        "Needs OpenMap. Every time the map opens, it zooms in on your arrow, over the zoom it had and your zone. A cave "
        .. "or town you're in still zooms in on that.")
    if arrowInit and arrowInit.AddModifyPredicate then arrowInit:AddModifyPredicate(OpenMapLoaded) end
    do
        local options = Settings.CreateSliderOptions(100, 2000, 50)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%d yd", v) end)
        local init = Settings.CreateSlider(P.cat, Register("arrowZoom", "Arrow zoom"), options,
            "How much the map shows around you as it opens, in yards across.")
        Under(arrowInit, init, function() return OpenMapLoaded() and db.fitArrow end)
    end
    Settings.CreateCheckbox(P.cat, Register("liveMinimap", "Minimap as map in dungeons"),
        "Inside dungeons and raids the game doesn't let addons know where you are, so no map can show your "
        .. "arrow there. With this on, the game's own minimap (which can) is shown big in the map's place, "
        .. "with your arrow, your party and the layout around you. It shows the minimap's range around you, "
        .. "not the whole dungeon (Dungeon Journal's or OpenMap's map of it does that).")
    Settings.CreateCheckbox(P.cat, Register("rememberZoom", "Open at last zoom"),
        "Opens at the zoom the map had when you last closed it, apart from the normal map's. With OpenMap, "
        .. "OpenMap's own reopen option still decides where it's centred.")
    Slider("moveFade", "Fade while moving", "How much the map fades while you move. It comes back as you stop, "
        .. "or with the mouse over the map. 0%: it doesn't fade.", 0, 0.9, 0.05)
    Settings.CreateCheckbox(P.cat, Register("combatReady", "Ready in combat (experimental)"),
        "The map opens properly in fights. Costs a short stutter as each fight starts. In a fight the map can't be moved or zoomed, and may show a bit off its place.")
    Settings.CreateCheckbox(P.cat, Register("moveFadeFlight", "Not on flights"),
        "With Fade while moving: the map doesn't fade while you're on a flight.")
    Settings.CreateCheckbox(P.cat, Register("moveFadeCombat", "Also in combat"),
        "With Fade while moving: the map stays faded all through a fight, also while you stand still.")
    Settings.CreateCheckbox(P.cat, Register("moveFadeHover", "Solid under the mouse"),
        "With Fade while moving: the map comes back while the mouse is over it. Off: it stays faded while you move.")
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

    Page("Addons")
    for _, s in ipairs(Keep.AddonSwitchList()) do
        if s.here() then Settings.CreateCheckbox(P.cat, Register(s.key, s.label), Keep.ADDONS_TIP) end
    end

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
-- Addons on the map: one switch per map addon (Addons.lua), greyed out when it isn't here
Keep.ADDONS_TIP = "Which other map addons show on Overlay Map's map. One turned off is kept off it while it's open, "
    .. "so the map opens faster; the normal map keeps it. Opened in a fight, the map shows every addon."
function Keep.AddonSwitchList()
    local list = {}
    for _, s in ipairs(ns.Addons.LIST) do
        local name = type(s.name) == "function" and s.name() or s.name
        local off = name .. " (not installed)"
        if s.key == "showOpenMapIcons" and Zone.OpenMapModule() then off = name .. " (with OpenMap's map on)" end
        list[#list + 1] = { s.key, name, key = s.key, label = name, here = s.here, off = off }
    end
    return list
end
Keep.CORNER_CHOICES = { { "TOPRIGHT", "Top right" }, { "TOPLEFT", "Top left" }, { "BOTTOMRIGHT", "Bottom right" },
    { "BOTTOMLEFT", "Bottom left" } }
Keep.DESC = {
    hideBuffs = "The game's buffs and debuffs, and other addons' own buff and debuff icons (EnhanceQoL's, and most addons that name theirs for buffs or auras), hidden while the map is open and back when it closes.",
    sticky = "The map stays on screen until you close it with its small X: the map key and Escape don't close it. The X shows with the mouse over the map, as the panel button does.",
    stickyCorner = "The corner of the map the X sits in. In the panel button's corner, it sits beside it.",
    mapKey = "The key that shows the map. Click, then press the key (or a Shift, Ctrl or Alt combination). Escape cancels.",
    bugReport = "Opens a window with the link to Overlay Map's CurseForge comments and a short report of your setup (versions, where you are, settings), ready to copy and paste in your comment.",
    fitPlacesList = "Zooms the map in on places as you enter them, and back out as you leave: caves and mines, towns (a place with an innkeeper or flight master), and the zones you fly over on a flight. My arrow: zoomed in on you every time the map opens. Choose any of them.",
    overlay = "One switch for an overlay map: the map fills the whole screen, see-through and click-through, with solid markers and large soft edges. It keeps its own opacities, marker size, style and edges: what you change while it's on stays with it, and the normal map keeps its own.",
    mode = "Hold to show: the map shows while you hold the key. Toggle: one press shows it, the next one hides it.",
    scale = "Size of the map. In full-screen overlay, the map fills the screen instead.",
    width = "Width of the map compared to its usual shape. Lower makes it more square.",
    opacity = "How see-through the map itself is. At 0%, only the markers show, floating over the world.",
    rememberZoom = "Opens at the zoom the map had when you last closed it, apart from the normal map's.",
    moveFade = "How much the map fades while you move. It comes back as you stop (or with the mouse over the map: Solid under the mouse). Off: it doesn't fade. While Overlay Map shows the map, OpenMap's own Fade while moving waits.",
    combatReady = "Experimental. The map opens properly in fights. Costs a short stutter as each fight starts. In a fight the map can't be moved or zoomed, and may show a bit off its place.",
    moveFadeFlight = "With Fade while moving: the map doesn't fade while you're on a flight.",
    moveFadeCombat = "With Fade while moving: the map stays faded all through a fight, also while you stand still. It comes back when combat ends.",
    moveFadeHover = "With Fade while moving: the map comes back while the mouse is over it (in full-screen overlay: over a marker, or with Shift held). Off: it stays faded while you move, wherever the mouse is.",
    pinOpacity = "How see-through the markers are: quests, vendors, flight points, your arrow and other addons' markers.",
    markerSize = "Size of the markers, Questie's and OpenMap's icons too (on top of OpenMap's own Icon size).",
    onlyMe = "Hides every marker on the map except your own arrow. The map's picture stays.",
    caveMouths = "A small marker at the entrance of caves and mines (hover it for the cave's name), for the caves Overlay Map knows the entrance of. Needs OpenMap.",
    arrowCustom = "Your arrow at a size and opacity of its own, apart from the other markers.",
    arrowNoFade = "With Fade markers too: your arrow (and your party's) stays as it is while the map and the other markers fade as you move.",
    moveFadeMarkers = "With Fade while moving: the markers fade with the map as you move. Off: only the map fades, as with Map opacity.",
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
    zoneFit = "Zooms the map so all of your zone fits: each time you enter a new zone, every time the map opens, or as you leave a town or capital (back to the zone around it). Choose any of them.",
    keepZoomTime = "After you zoom the map yourself, how long auto-zoom leaves your zoom alone before it fits a new zone again. Off: auto-zoom always fits the zone you enter.",
    zoneKeep = "With OpenMap: while the middle of the view is over the sea or land that belongs to no zone, the border you had stays. Off: the whole map shows there.",
    zoneWhole = "With OpenMap: zoomed out until your zone fills less than this much of the view, the border goes and the whole map shows. Higher: sooner; lower: the border stays further out.",
    zoneView = "With OpenMap: the border is for the zone in the middle of the view, so moving the map to another zone borders that one. Off: the zone you're in.",
    clickThrough = "The mouse goes through the map to the world, so you can click and turn with it over the map. Markers still show their names. Hold Shift to drag and zoom the map.",
    follow = "Keeps the map centred on you while it's open, like the minimap. It holds still while the mouse is over the map.",
    fitPlaces = "Needs OpenMap. Entering a cave or mine, the map zooms in till the cave fills it, and back out when you leave.",
    liveMinimap = "Inside dungeons the game hides where you are from addons. With this on, the game's own minimap (with your arrow) is shown big in the map's place. It doesn't fade while you move.",
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
    -- Open on the map: the game's own red button with the gold arrow (its map's "bigger" button), the older
    -- client's file if this one hasn't it
    local preview = CreateFrame("Button", nil, canvas)
    preview:SetSize(24, 24)
    preview:SetPoint("TOPLEFT", 16, -47)
    local function Art(tex, atlas, file)
        if not tex then return end
        local hasAtlas = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        if hasAtlas then tex:SetAtlas(atlas) else tex:SetTexture(file) end
    end
    preview:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    preview:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    preview:SetHighlightTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Highlight", "ADD")
    Art(preview:GetNormalTexture(), "RedButton-Expand", "Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    Art(preview:GetPushedTexture(), "RedButton-Expand-Pressed", "Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    Art(preview:GetHighlightTexture(), "RedButton-Highlight", "Interface\\Buttons\\UI-Panel-BiggerButton-Highlight")
    preview:SetScript("OnClick", function() Keep.Preview() end)
    Keep.Tip(preview, nil, "Open on the map: closes this window and opens the map with its small options panel, to "
        .. "change the main options while you see them (the game doesn't let the map and this window be open together).")
    local wizard = TopButton("Setup wizard", 120, function() Wizard.Open() end,
        "The map key and the main options in a few steps, with the map open to see each change.")
    wizard:SetPoint("LEFT", preview, "RIGHT", 6, 0)
    local resetAll = TopButton("Reset everything", 130, function() StaticPopup_Show("OVERLAYMAP_RESET_ALL") end,
        "Puts every Overlay Map option back to its default (asks first; your key stays).")
    resetAll:SetPoint("LEFT", wizard, "RIGHT", 6, 0)
    -- Addons on the map: a drop-down list under the search box, a switch per addon
    local addons = CreateFrame("Button", nil, canvas, "BackdropTemplate")
    addons:SetSize(180, 22)
    addons:SetPoint("TOPRIGHT", -20, -48)
    addons.menuRight = true
    addons:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    addons:SetBackdropColor(1, 0.85, 0.3, 0.07)
    addons:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    addons:GetHighlightTexture():SetAlpha(0.15)
    local atext = addons:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- (gold, as the buttons' text)
    atext:SetPoint("LEFT", 8, 0)
    atext:SetText("Addons on the map")
    local aarrow = addons:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    aarrow:SetPoint("RIGHT", -8, 0)
    aarrow:SetText("v")
    Keep.Tip(addons, nil, Keep.ADDONS_TIP)
    addons:SetScript("OnClick", function(self)
        Keep.OpenMulti(self, Keep.AddonSwitchList(), function() Keep.RefreshAll() end)
    end)
    canvas:HookScript("OnHide", function() if Keep.multi and Keep.multi.owner == addons then Keep.multi:Hide() end end)
    local key -- (the Map key button, first on the General tab)
    function O.Top()
        local k = Wizard.CurrentKey()
        if key then key:SetText("Map key: " .. (k and Wizard.KeyText(k) or "|cffff8040none|r")) end
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
    base:SetColorTexture(0.75, 0.55, 0.15, 0.6) -- (3:1 against the panel: a line that groups things must be seen)
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
    local tab, indent = nil, 0
    local function Row(height, key, label, enabledIf)
        local f = CreateFrame("Frame", nil, content)
        f:SetSize(CONTROL, height)
        f.height, f.tab, f.key, f.enabledIf, f.indent = height, tab, key, enabledIf, indent
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
    -- (options made inside Sub belong to the one above: moved in, with a branch line)
    local function Sub(make) indent = Keep.INDENT make() indent = 0 end
    -- a group's title (hidden while searching: the matches are listed by tab)
    local function Head(title)
        local f = Row(24, nil, nil)
        f.isHead = true
        f.search = ""
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 8, -4)
        t:SetText(title)
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.75, 0.55, 0.15, 0.3)
        line:SetHeight(1)
        line:SetPoint("LEFT", t, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        f.line = line
    end
    local function Check(key, label, enabledIf, offLabel, offTip)
        PanelCheck(Row(30, key, label, enabledIf), key, label, enabledIf, offLabel, offTip)
    end
    local function Slider(key, label, minValue, maxValue, step, enabledIf, reshape, fmt)
        PanelSlider(Row(56, key, label, enabledIf), key, label, minValue, maxValue, step, reshape, fmt)
    end
    local function Cycle(key, label, choices, enabledIf)
        PanelCycle(Row(32, key, label, enabledIf), key, label, choices, enabledIf)
    end
    local function Buttons(list, enabledIf, label, key)
        local f = Row(30, key, label, enabledIf)
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
    Head("Opening")
    key = select(1, Buttons({ { "Map key", function() Keep.CatchKey() end,
        "Click, then press the key (or a Shift, Ctrl or Alt combination) that shows the map. Escape cancels." } },
        nil, "Map key keybinding bind shortcut", "mapKey"):GetChildren())
    Cycle("mode", "Key", Wizard.MODE_CHOICES)
    Check("sticky", "Sticky map")
    Sub(function()
        Cycle("stickyCorner", "Close button corner", Keep.CORNER_CHOICES, function() return db.sticky end)
    end)
    Check("rememberZoom", "Open at last zoom")
    Head("Size and place")
    Check("overlay", "Full-screen overlay")
    Slider("scale", "Size", 0.3, 2.5, 0.05, NotOverlay, true)
    Slider("width", "Width", 0.5, 1.5, 0.05, NotOverlay, true)
    Buttons({ { "Move the map", function() ShowMover() end, "Shows a box the size of the map: drag it, then right-click it when done." },
        { "Reset position", function() db.x, db.y = 0, 0 if ns.mover and ns.mover:IsShown() then ShowMover() end ns.ApplyLook() end,
            "Puts the map back in the middle of the screen." } }, NotOverlay, "Move Reset position")
    Head("Fading")
    Slider("opacity", "Map opacity", 0, 1, 0.05)
    Slider("moveFade", "Fade while moving", 0, 0.9, 0.05, nil, nil,
        function(v) return v < 0.025 and "Off" or string.format("%d%%", v * 100 + 0.5) end)
    Sub(function()
        Check("moveFadeHover", "Solid under the mouse", function() return (db.moveFade or 0) > 0 end)
        Check("moveFadeCombat", "Also in combat", function() return (db.moveFade or 0) > 0 end)
        Check("moveFadeFlight", "Not on flights", function() return (db.moveFade or 0) > 0 end)
    end)
    Head("Help")
    do
        Buttons({ { "Report a bug", function() Keep.BugReport() end,
            "A window with the link to report a bug and a report of your setup, ready to copy." } }, nil,
            "Report a bug help issue problem", "bugReport")
    end
    TabReset()

    tab = "Markers"
    Head("All markers")
    Slider("pinOpacity", "Marker opacity", 0.1, 1, 0.05)
    Slider("markerSize", "Marker size", 0.5, 2.5, 0.05)
    Check("onlyMe", "Show only my arrow")
    Check("moveFadeMarkers", "Fade markers too", function() return (db.moveFade or 0) > 0 end)
    Check("caveMouths", "Cave entrances", OpenMapLoaded, "Cave entrances (needs OpenMap)")
    Head("Your arrow")
    Check("arrowCustom", "Custom arrow size")
    Sub(function()
        Slider("arrowSize", "My arrow size", 0.5, 3, 0.05, ArrowOwn)
        Slider("arrowOpacity", "My arrow opacity", 0.1, 1, 0.05, ArrowOwn)
    end)
    Check("arrowNoFade", "My arrow doesn't fade", function() return (db.moveFade or 0) > 0 and db.moveFadeMarkers end)
    TabReset()

    tab = "Style"
    Cycle("style", "Style", STYLE_CHOICES)
    Sub(function()
        Cycle("edge", "Fade at the edges", EDGE_CHOICES, StandardStyle)
        Cycle("shape", "Edge shape", SHAPE_CHOICES, StandardStyle)
        Slider("outlineLines", "Line strength", 0.1, 1, 0.05, OutlineStyle)
        Slider("outlineBack", "Background darkness", 0, 1, 0.05, OutlineStyle)
    end)
    TabReset()

    tab = "Zone borders"
    Head("Border")
    Check("zoneBorder", "Apply borders to zones", Zone.Installed, "Apply borders to zones (needs download)",
        "Zone borders need the Overlay Map: Zone Borders addon, a separate download (from where you got "
        .. "Overlay Map). Install it next to Overlay Map and restart the game.")
    Sub(function()
        Check("zoneSoft", "Fade at the zone edges", ZoneOn)
        Slider("zoneDim", "Rest of map visibility", 0, 0.6, 0.05, ZoneOn)
        do
            local f = Row(30, "zoneFit", "Auto-zoom to zone entering opening leaving town city", ZoneOn)
            f.keys = { "fitEnter", "fitOpen", "fitLeave" }
            Keep.PanelMulti(f, "zoneFit", "Auto-zoom to zone", Keep.FIT_ITEMS, ZoneOn)
        end
        Slider("keepZoomTime", "Auto-zoom pause", 0, 120, 5, function() return ZoneOn() and Zone.AnyFit() end, nil,
            function(v) return v < 0.5 and "Off" or string.format("%d s", v + 0.5) end)
    end)
    Head("With OpenMap")
    Check("zoneKeep", Keep.NeedsOMName("Keep the border over the sea and between zones"), ZoneOM)
    Slider("zoneWhole", Keep.NeedsOMName("Show the whole map below this zone size"), 0.15, 0.85, 0.05, ZoneOM)
    Check("zoneView", Keep.NeedsOMName("Border the zone in the middle of the view"), ZoneOM)
    TabReset()

    tab = "Behavior"
    Head("Controls")
    Check("clickThrough", "Click through the map")
    Check("follow", "Center on me")
    Head("Places")
    do
        local name = Keep.NeedsOMName("Auto-zoom")
        local f = Row(30, "fitPlacesList", name .. " caves mines towns flights my arrow player", OpenMapLoaded)
        f.keys = { "fitPlaces", "fitTowns", "fitFlights", "fitArrow" }
        Keep.PanelMulti(f, "fitPlacesList", name, Keep.PLACE_ITEMS, OpenMapLoaded)
    end
    Sub(function()
        Slider("townSize", "Town zoom", 200, 1000, 50, function() return OpenMapLoaded() and db.fitTowns end, nil,
            function(v) return string.format("%d yd", v + 0.5) end)
        -- (shown only with towns ticked, not just greyed)
        O.rows[#O.rows].showIf = function() return db.fitTowns end
        Slider("arrowZoom", "Arrow zoom", 100, 2000, 50, function() return OpenMapLoaded() and db.fitArrow end, nil,
            function(v) return string.format("%d yd", v + 0.5) end)
        O.rows[#O.rows].showIf = function() return db.fitArrow end
    end)
    Check("liveMinimap", "Minimap as map in dungeons")
    -- (still being worked on: last in the tab, under its own title, and only here, not in the small panel)
    Head("Experimental")
    Check("combatReady", "Ready in combat")
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
    Cycle("buttonCorner", "Corner", Keep.CORNER_CHOICES)
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
            if q then shown = not f.isReset and not f.isHead and f.search:find(q, 1, true) ~= nil
            else shown = f.tab == db.optionsTab end
            if shown and f.showIf and not f.showIf() then shown = false end
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
                    -- (none after a group's title, nor under it: the title starts the group)
                    f.sep:SetShown(not firstInGroup and not f.isHead)
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
                if f.isHead then
                    y = y - h - 4
                    firstInGroup = true
                else
                    if not f.isReset then y = y - h - 12 end
                    firstInGroup = false
                end
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

-- Options that ask before going on (a cost people should know about), by their popup's name
Keep.ASK_ON = { combatReady = "OVERLAYMAP_COMBAT_READY" }
function Keep.AskOn(key)
    local dialog = StaticPopup_Show(Keep.ASK_ON[key], nil, nil, key)
    -- (over the small panel, which sits above the game's usual popup layer)
    if dialog then
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(9000)
    end
end
function Keep.TurnOn(key)
    db[key] = true
    ns.ApplyLook()
    Keep.RefreshAll()
end
StaticPopupDialogs.OVERLAYMAP_COMBAT_READY = {
    text = "Turn on \"Ready in combat\" (experimental)?\n\nThe map opens properly in fights, but every fight starts with a short "
        .. "stutter.\n\nIn a fight the map can't be moved or zoomed.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, key) Keep.TurnOn(key) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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
        if f.tab == name then
            for _, k in ipairs(f.keys or { f.key }) do
                if DEFAULTS[k] ~= nil then
                    if k == "scale" or k == "width" then shape = true end
                    db[k] = DEFAULTS[k]
                end
            end
        end
    end
    if name == "General" then db.x, db.y = 0, 0 end
    SyncOverlay()
    if shape and ns.compact then Zone.Reshape() else ns.ApplyLook() end
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
ns.BuildOptions = BuildOptions

local function OpenOptions()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        Say("Options: Options > AddOns > Overlay Map.")
    end
end
ns.OpenOptions = OpenOptions
