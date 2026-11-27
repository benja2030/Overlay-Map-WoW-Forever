-- Overlay Map: the markers: their own layers over the map, their size and opacity, your arrow, Click through and Show only my arrow.
-- The files share one table, ns, and load in the order of OverlayMap.toc (Core.lua first).

local ADDON_NAME, ns = ...
local Keep, Zone, Wizard, Outline, Arrow = ns.Keep, ns.Zone, ns.Wizard, ns.Outline, ns.Arrow
local db
ns.dbSetters[#ns.dbSetters + 1] = function(t) db = t end
-- From the files before this one
local iconLayers, Map, Canvas, OpenMapLoaded = ns.iconLayers, ns.Map, ns.Canvas, ns.OpenMapLoaded

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
ns.layer = nil         -- Overlay Map's layer for the markers
local moved = {}    -- marker -> true while it is on that layer
ns.moved = moved
local hookedPins = setmetatable({}, { __mode = "k" })
local reparenting = false

local function Content() return Canvas().Child end
ns.Content = Content

-- Keeps the layer over the map area, at the zoom the map has right now.
-- The same for icon frames that don't zoom with the map (they sit on the map area itself).
ns.viewLayer = nil
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
ns.Above = Above

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

ns.SyncLayer = function()
    if Outline.layer and Outline.layer:IsShown() then
        Sync(Outline.layer, Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale(), 0)
        Outline.Place()
    end
    if ns.viewLayer then Sync(ns.viewLayer, Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale(), 1) end
    if ns.layer then Sync(ns.layer, Content():GetEffectiveScale() / UIParent:GetEffectiveScale(), 2) end
    if Zone.outLayer then Sync(Zone.outLayer, Content():GetEffectiveScale() / UIParent:GetEffectiveScale(), 2) end
    if Zone.arrowLayer then Sync(Zone.arrowLayer, Canvas():GetEffectiveScale() / UIParent:GetEffectiveScale(), 3) end
    if Zone.arrowPinLayer then Sync(Zone.arrowPinLayer, Content():GetEffectiveScale() / UIParent:GetEffectiveScale(), 3) end
end
Keep.AfterPlace = function() ns.SyncLayer() end -- (Keep.CheckPlace, further up)

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

-- The game's arrow (a marker, placed on the map's zoomed content, not on OpenMap's icon layer) with "My arrow
-- doesn't fade": a layer of its own like the markers' (the content's scale: on the icons' arrow layer, at the
-- canvas's scale, it was drawn in the wrong place), over them, not faded while you move
function Zone.ArrowPinLayer()
    if not Zone.arrowPinLayer then
        Zone.arrowPinLayer = CreateFrame("Frame", "OverlayMapArrowMarker", UIParent)
        Zone.arrowPinLayer:SetClipsChildren(true)
        Sync(Zone.arrowPinLayer, Content():GetEffectiveScale() / UIParent:GetEffectiveScale(), 3)
    end
    return Zone.arrowPinLayer
end

function Zone.RaiseArrow(alpha)
    local P = Zone.arrowPinLayer
    if P then
        if P:GetNumChildren() > 0 and ns.compact then
            Sync(P, Content():GetEffectiveScale() / UIParent:GetEffectiveScale(), 3)
            if math.abs(P:GetAlpha() - alpha) > 0.001 then P:SetAlpha(alpha) end
            P:Show()
        else
            P:Hide()
        end
    end
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
    if Zone.arrowPinLayer then Zone.arrowPinLayer:Hide() end
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
ns.SaveLevels = SaveLevels

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
            if reparenting or not ns.compact or not moved[self] then return end
            local want = Zone.PinLayer(self)
            if parent == want then return end
            reparenting = true
            Reparent(self, want, 2)
            reparenting = false
        end)
    end
    local want = Zone.PinLayer(pin)
    if pin:GetParent() ~= want then
        -- A new parent resets a frame's level, which would put the marker under the map
        -- (out of reach of the mouse, so no tooltip); it keeps the level the map gave it.
        moved[pin] = true
        reparenting = true
        Reparent(pin, want, 2)
        reparenting = false
        Zone.Unzone(pin, 2)
    end
end

local function ReturnPins()
    local content = Content()
    reparenting = true
    for pin in pairs(moved) do Reparent(pin, content, 2) end
    reparenting = false
    wipe(moved)
    if ns.layer then ns.layer:Hide() end
    if Zone.outLayer then Zone.outLayer:Hide() end
    Zone.OMPinsApply(1)
    Zone.omKey = nil
    local c = Canvas()
    for f in pairs(viewMoved) do
        Reparent(f, c, 5)
    end
    wipe(viewMoved)
    if ns.viewLayer then ns.viewLayer:Hide() end
    Zone.LowerArrow()
end

-- A quick fade of the whole map (and its markers) while it's laid out again, instead of it going
-- off and on at once: 1 shown, 0 hidden (FadeTo, further down).
ns.transition = 1
ns.FadeTo = nil -- (below)

local function ApplyOpacity()
    local map = Map()
    -- The game fades the map while you move; Overlay Map does it itself ("Fade while moving",
    -- Keep.MoveFade), so it works with these opacities.
    local fade = Keep.moveFaded or 1
    if ns.settling or Zone.shelved then fade = 0 end
    -- (opening: hidden until the edges are laid, so the map isn't seen uncut for a moment, then a
    -- quick fade in; a second at most)
    if Zone.opening then
        -- (inside a dungeon with OpenMap: also until its dungeon map is up and tidied, a moment after)
        local hold = Zone.holdFor and GetTime() < Zone.holdFor
        if (ns.settling or Zone.walking or hold) and GetTime() - Zone.opening < 1 then
            fade = 0
        else
            Zone.opening = nil
            ns.transition = 0
            ns.FadeTo(1, 0.15)
        end
    end
    fade = fade * ns.transition
    -- (the setup wizard's key step: the map faint until you press the key you chose)
    if Wizard.dimNow then fade = fade * Wizard.dimNow end
    -- (the markers: without the fade while moving, unless "Fade markers too", as Map opacity leaves them)
    local markFade = fade
    if not db.moveFadeMarkers and (Keep.moveFaded or 1) > 0.01 then markFade = fade / (Keep.moveFaded or 1) end
    local mapAlpha = db.opacity * fade
    -- (Outlines: the map's painting hidden, the lines drawn on their own layer, the markers on theirs)
    if db.style == "outlines" then mapAlpha = 0 end
    -- (the live minimap in a dungeon: shown instead of the map, at its opacity)
    if Zone.live then
        mapAlpha = 0
        -- (not faded while you move: in a dungeon it's the only thing that shows where you are, and the game lost
        -- its drawing as its opacity changed under it at every step, so it disappeared as you walked. The other
        -- fades (opening, kept unseen in a fight, the setup wizard) still apply)
        local liveFade = fade
        if (Keep.moveFaded or 1) > 0.01 then liveFade = fade / (Keep.moveFaded or 1) end
        if Minimap and math.abs(Minimap:GetAlpha() - db.opacity * liveFade) > 0.001 then Minimap:SetAlpha(db.opacity * liveFade) end
        -- (redrawn once it actually shows: while the map was still invisible as it opened, the minimap's redraw
        -- was lost, and it showed black or blank from the second opening on)
        if not Zone.live.drawn and db.opacity * liveFade > 0.05 then
            Zone.live.drawn = true
            C_Timer.After(0.05, function() if Zone.live then Zone.MinimapRedraw(0) end end)
        end
    end
    if math.abs(map:GetAlpha() - mapAlpha) > 0.001 then map:SetAlpha(mapAlpha) end
    Outline.Apply(db.opacity * fade)

    -- (the same opacity: the markers stay on the map. Not with an addon's icon layer, like OpenMap's:
    -- on the map it's over the markers, so its icons covered your arrow, which is the game's marker
    -- when OpenMap doesn't draw its own; on Overlay Map's layers your arrow goes over them)
    if math.abs(db.pinOpacity - db.opacity) < 0.001 and db.style ~= "outlines" and not next(iconLayers) and not Keep.combatMismatch
        and not (db.zoneBorder and Zone.MarkZone()) and not ((db.moveFade or 0) > 0 and not db.moveFadeMarkers) then
        if next(moved) then ReturnPins() end
        if next(Zone.omFaded) or next(Zone.omLinesFaded) then Zone.OMPinsApply(1) Zone.omKey = nil end
        return
    end
    if not ns.layer then
        ns.layer = CreateFrame("Frame", "OverlayMapMarkers", UIParent)
        ns.layer:SetClipsChildren(true) -- markers outside the map area are cut off, like on the map
    end
    if not ns.viewLayer then
        ns.viewLayer = CreateFrame("Frame", "OverlayMapIcons", UIParent)
        ns.viewLayer:SetClipsChildren(true)
    end
    ns.SyncLayer()
    -- (over OpenMap's dungeon map: the world's markers underneath kept off it)
    -- (also while inside a dungeon its map is only away in the journal's window for a moment)
    local pinFade = (Zone.live or Zone.DungeonViewShown() or (Zone.underAlpha ~= nil and Zone.InDungeon())) and 0 or 1
    -- (opened in a fight with OpenMap: the game's own markers out of place till it ends, Keep.combatMismatch.
    -- Those hidden, one by one (ApplyOnlyMe), and your arrow; OpenMap's icons and Questie's are placed right)
    local hideMarks = Keep.combatMismatch
    local viewFade = pinFade
    if math.abs(ns.layer:GetAlpha() - db.pinOpacity * markFade * pinFade) > 0.001 then ns.layer:SetAlpha(db.pinOpacity * markFade * pinFade) end
    ns.layer:Show()
    -- (markers outside the zone's border: at the rest of the map's visibility; hidden at 0%, so they don't
    -- show their names under the mouse either)
    if Zone.outLayer then
        local out = db.pinOpacity * markFade * pinFade * Zone.OutsideShare()
        if math.abs(Zone.outLayer:GetAlpha() - out) > 0.001 then Zone.outLayer:SetAlpha(out) end
        Zone.outLayer:SetShown(out > 0.02)
    end
    -- (OpenMap's own icons outside the border: the same, Zone.OMPinLook; again when the zone or the visibility
    -- changes, else with the markers below)
    Zone.HookOMPins()
    local share = Zone.OutsideShare()
    local omKey = tostring(Zone.MarkZone()) .. " " .. share
    if Zone.omKey ~= omKey then Zone.omKey = omKey Zone.OMPinsApply(share) end
    if math.abs(ns.viewLayer:GetAlpha() - db.pinOpacity * markFade * viewFade) > 0.001 then ns.viewLayer:SetAlpha(db.pinOpacity * markFade * viewFade) end
    ns.viewLayer:Show()
    -- Going through every marker (with Questie, hundreds) is the costly part: only when there are new ones
    -- (Keep.pinsDirty: the map acquired a marker, an option changed, the map opened) and once a second as a
    -- safety net, not on every opacity change (a fade sets it every frame) nor on every upkeep. A marker the map
    -- puts back on itself goes straight back to the layer anyway (MovePin's hook).
    local now = GetTime()
    if Keep.pinsDirty or now - (Keep.pinsAt or 0) >= 1 then
        Keep.pinsDirty, Keep.pinsAt = false, now
        for f in pairs(iconLayers) do
            if f:GetParent() ~= ns.viewLayer then
                viewMoved[f] = true
                Reparent(f, ns.viewLayer, 5)
            end
        end
        for template, pool in pairs(map.pinPools or {}) do
            if not MAP_ART[template] and pool.EnumerateActive then
                for pin in pool:EnumerateActive() do MovePin(pin) end
            end
        end
        Zone.OMWalkLayers()
        Zone.OMPinsApply(share)
    end
    -- ("My arrow doesn't fade": without the fade while moving, the other fades kept)
    local arrowFade = markFade
    if db.arrowNoFade and (Keep.moveFaded or 1) > 0.01 then arrowFade = fade / (Keep.moveFaded or 1) end
    if hideMarks then arrowFade = 0 end -- (the game's arrow: out of place too; one of OpenMap's instead)
    if hideMarks or Zone.fightArrow then Zone.FightArrow(hideMarks and ns.compact and not Zone.shelved) end
    Zone.RaiseArrow(db.pinOpacity * arrowFade * pinFade)
end
ns.ApplyOpacity = ApplyOpacity

local function RestoreOpacity()
    ReturnPins()
    Outline.Hide()
end
ns.RestoreOpacity = RestoreOpacity

local fader = CreateFrame("Frame")
ns.fader = fader
fader:Hide()
fader:SetScript("OnUpdate", function(self)
    local k = math.min(1, (GetTime() - self.t0) / self.time)
    ns.transition = self.from + (self.to - self.from) * k
    if ns.compact then ApplyOpacity() end
    if k >= 1 then
        self:Hide()
        local done = self.done
        self.done = nil
        if done then done() end
    end
end)

ns.FadeTo = function(target, time, done)
    fader.from, fader.to, fader.t0, fader.time, fader.done = ns.transition, target, GetTime(), time, done
    fader:Show()
end

local function StopFade()
    fader:Hide()
    fader.done = nil
    ns.transition = 1
    ns.reshaping = false
    ns.shapeGen = ns.shapeGen + 1
end
ns.StopFade = StopFade

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
        -- (a marker hidden at the moment, its mouse off meanwhile: the mouse it had before, or putting this back
        -- on close left it without tooltips, as after a map open through the end of a fight)
        local hid = Keep.onlyHidden and Keep.onlyHidden[f]
        local click, motion = f:IsMouseClickEnabled(), f:IsMouseMotionEnabled()
        local wheel = f.IsMouseWheelEnabled and f:IsMouseWheelEnabled()
        if hid and hid.motion ~= nil then motion = hid.motion end
        -- (the map area: the mouse it had as the map opened, before Overlay Map changed it (kept unseen for a fight,
        -- its mouse off; or the click through itself, laid again). Noted as it was then, putting it back on close
        -- left the map unable to be moved, till a reload)
        local o = f == Canvas() and Keep.canvasMouse
        if o then click, motion, wheel = o[1], o[2], o[3] end
        passSaved[f] = { click, motion, wheel }
    else
        local on, wheel = f:IsMouseEnabled(), f.IsMouseWheelEnabled and f:IsMouseWheelEnabled()
        local o = f == Canvas() and Keep.canvasMouse
        if o then on, wheel = o[1], o[3] end
        passSaved[f] = { on, nil, wheel }
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

ns.ApplyClickThrough = function(force)
    local on = ns.compact and db.clickThrough and not IsShiftKeyDown()
    if not on then markersOff = false end
    -- force: start over (everything back as it was, then click-through again), the same as
    -- turning the option off and on; used once the map has finished opening.
    if force and on and next(passSaved) then
        ns.compact = false
        ns.ApplyClickThrough()
        ns.compact = true
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
ns.onlyHidden = onlyHidden
Keep.onlyHidden = onlyHidden -- (for the click through's Save, further up)
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
ns.ShowMarkers = ShowMarkers

-- OpenMap draws its own icons for townsfolk (vendors, trainers, mailboxes) from Questie's
-- database, and Questie draws its own for the same NPCs. On its map OpenMap keeps Questie's
-- under its own, so only one shows; over the world, with the markers on their own layers, both
-- showed. While Overlay Map shows OpenMap's map, Questie's townsfolk icons are hidden (Questie's
-- quest icons stay).
local function IsTownsfolk(f) return f.isManualIcon == true end
ns.IsTownsfolk = IsTownsfolk

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

-- The game's own quest markers (a quest ready to turn in, its objective) where Questie draws one of its own
-- on the same spot: Questie's hidden, the game's kept. Exactly under each other, only one showed, but with
-- the markers see-through both did. The game's is the one kept: shift-click on it follows the quest (Questie's
-- can't), and hiding it lost that.
Keep.questTwin = setmetatable({}, { __mode = "k" })
function Keep.HideQuestTwins()
    local twins = setmetatable({}, { __mode = "k" })
    Keep.questTwin = twins
    local pools = Map().pinPools or {}
    local quests = pools.QuestPinTemplate
    if not (quests and quests.EnumerateActive) then return false end
    local spots = {}
    for pin in quests:EnumerateActive() do
        if pin:IsShown() then
            local x, y = pin:GetCenter()
            if x then
                local k = pin:GetEffectiveScale()
                spots[#spots + 1] = { x * k, y * k, pin:GetWidth() * k }
            end
        end
    end
    if #spots == 0 then return false end
    local any = false
    for template, pool in pairs(pools) do
        if type(template) == "string" and template:find("HereBeDragons", 1, true) and pool.EnumerateActive then
            for pin in pool:EnumerateActive() do
                local icon = pin.icon
                if icon and icon:IsShown() and not icon.isManualIcon then
                    local x, y = icon:GetCenter()
                    if x then
                        local k = icon:GetEffectiveScale()
                        x, y = x * k, y * k
                        for _, sp in ipairs(spots) do
                            local reach = math.max(4, sp[3] * 0.5)
                            if math.abs(sp[1] - x) <= reach and math.abs(sp[2] - y) <= reach then
                                twins[icon] = true
                                HideMarker(icon)
                                any = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    return any
end

ns.ApplyOnlyMe = function()
    if not ns.compact then
        ShowMarkers()
        return
    end
    -- (opened in a fight with OpenMap: the game's own markers out of place till it ends, hidden; Questie's, placed
    -- by OpenMap with its picture, stay. Keep.combatMismatch)
    if Keep.FightQuests() and not db.onlyMe then
        for template, pool in pairs(Map().pinPools or {}) do
            -- (not your arrow's marker: hidden through its opacity, ApplyOpacity, so it comes back with it)
            if not MAP_ART[template] and not template:find("HereBeDragons") and template ~= "GroupMembersPinTemplate"
                and pool.EnumerateActive then
                for pin in pool:EnumerateActive() do HideMarkerTree(pin, 2) end
            end
        end
        return
    end
    if not db.onlyMe then
        local folk = HideTownsfolkTwins()
        local quest = Keep.HideQuestTwins()
        if folk or quest then
            ShowMarkers(function(f) return (folk and IsTownsfolk(f)) or Keep.questTwin[f] end)
        else
            ShowMarkers()
        end
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
Keep.ApplyOnlyMe = function() ns.ApplyOnlyMe() end

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
    if not ns.compact or (db.markerSize or 1) == 1 then return end
    -- (a marker that doesn't work out a size of its own was left as it was: nothing to add to)
    if not (pin.startScale and pin.endScale) and pin.IsIgnoringGlobalPinScale and pin:IsIgnoringGlobalPinScale() then
        return
    end
    pin:SetScale(pin:GetScale() * db.markerSize)
    if pin.ApplyCurrentPosition then pin:ApplyCurrentPosition() end
end

ns.ApplyMarkerSize = function()
    local k = ns.compact and db.markerSize or 1
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

-- (Arrow: at the top of the file)
-- My arrow: its own size and opacity, when chosen (My Arrow's Own Size). With OpenMap's map it's
-- OpenMap's own arrow (a picture on its icon layer); otherwise the game's, drawn by the group
-- members' marker, whose size for the player is set on it (its opacity is the whole marker's, so
-- the party's dots take it too). Put back as it was on close.
Arrow.arrowBase = setmetatable({}, { __mode = "k" })    -- arrow picture or marker -> its own size
Arrow.arrowHooked = setmetatable({}, { __mode = "k" })
Arrow.arrowApplied = setmetatable({}, { __mode = "k" })   -- marker -> the size factor last set on it
Arrow.arrowSetting = false

function Arrow.ArrowWant()
    if ns.compact and db.arrowCustom then return db.arrowSize or 1, db.arrowOpacity or 1 end
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

ns.ApplyArrow = function()
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
