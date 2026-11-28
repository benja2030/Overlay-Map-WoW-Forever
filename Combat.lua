-- Overlay Map: fights: Ready in combat, the map kept unseen when closed in a fight, and what comes back as a fight ends.
-- The files share one table, ns, and load in the order of OverlayMap.toc (Core.lua first).

local ADDON_NAME, ns = ...
local Keep, Zone, Wizard, Outline = ns.Keep, ns.Zone, ns.Wizard, ns.Outline
local db
ns.dbSetters[#ns.dbSetters + 1] = function(t) db = t end
-- From the files before this one
local Map, Canvas, OpenMapLoaded, ShowExtras, ShowMinimap, ApplyOpacity = ns.Map, ns.Canvas, ns.OpenMapLoaded, ns.ShowExtras, ns.ShowMinimap, ns.ApplyOpacity
local ApplyEdges, Open, OpenMapDrives = ns.ApplyEdges, ns.Open, ns.OpenMapDrives

-- Your arrow while the map is open in a fight without Ready in combat (Keep.combatMismatch): the game's own
-- is out of place then (it follows the game's view, which OpenMap can't set up in a fight), OpenMap's icons
-- aren't. So one of OpenMap's icons stands in for it, moved to where you are and turned as you face.
Zone.FIGHT_ARROW = { texture = "Interface\\Minimap\\MinimapArrow", size = 28 }
function Zone.FightArrow(on)
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    if not (S and S.PinSet and S.AddPin and S.MovePin and S.SetPinSetOn) then return end
    local f = Zone.fightArrow
    if not on then
        if f then f:Hide() if f.set then pcall(S.SetPinSetOn, f.set, false) end end
        return
    end
    if not f then
        f = CreateFrame("Frame")
        Zone.fightArrow = f
        local ok, set = pcall(S.PinSet, "overlaymapFightArrow", 0, 20)
        if not ok or not set then return end
        f.set = set
        f:SetScript("OnUpdate", function(self, elapsed)
            self.acc = (self.acc or 0) + elapsed
            if self.acc < 0.05 then return end
            self.acc = 0
            local u, v = Zone.PlayerWorld()
            if not u then if self.pin then self.pin:Hide() end return end
            if not self.pin then
                local okP, pin = pcall(S.AddPin, self.set, u, v, Zone.FIGHT_ARROW)
                if not okP or not pin then return end
                pin:EnableMouse(false)
                self.pin = pin
            else
                pcall(S.MovePin, self.set, self.pin, u, v)
                self.pin:Show()
            end
            local facing = GetPlayerFacing and GetPlayerFacing()
            if type(facing) == "number" and not (issecretvalue and issecretvalue(facing)) then self.pin.Icon:SetRotation(facing) end
            self.pin:SetAlpha(db.pinOpacity or 1)
        end)
    end
    if f.set then pcall(S.SetPinSetOn, f.set, true) end
    f:Show()
end

function Zone.AfterCombat()
    local w = Zone.viewLater
    Zone.viewLater = nil
    local mismatch = Keep.combatMismatch
    Keep.combatMismatch = false
    if Zone.fightZone then Zone.fightZone = nil Keep.pinsDirty = true end
    Keep.CaveWheel()
    if not ns.compact or Zone.shelved then return end
    -- (the game's markers, your arrow among them, laid out again on the view as it is: after a fight with the map
    -- open, your arrow stayed away till the view moved, which Center on me doesn't with the mouse over the map)
    local om, api = Zone.OpenMapModule(), _G.OpenMapAPI
    if om and om.ShowNow and api and api.GetView then
        local ok, u, v, z = pcall(api.GetView)
        if ok and type(u) == "number" and type(z) == "number" then pcall(om.ShowNow, u, v, z) end
    end
    Keep.ApplyOnlyMe() -- (the game's quest markers back)
    if mismatch then ApplyOpacity() end
    if w then Zone.ViewTo(w[1], w[2], w[3]) end
    if db.zoneBorder then ApplyEdges() end -- (the border, left off while the map was open in the fight)
    if db.style == "outlines" then Outline.Place() end
end

-- In combat the game doesn't let an addon hide the map while it holds a protected marker (your group's):
-- closing it then left it open, and Overlay Map handed it back to the game, so the normal map with its
-- border showed up. Now it's kept open but invisible, without the mouse, and closed as combat ends; the
-- key shows it again meanwhile.
function Zone.Shelve()
    if Zone.shelved then return end
    Zone.shelved = true
    Keep.EscapeOn(false)
    local c = Canvas()
    -- (its clicks and hover apart, as Click through sets them apart: one "mouse on or off" for both turned
    -- hover off for good when Click through had the clicks off as it was kept away, and the map couldn't be
    -- moved any more, till a reload)
    if c.IsMouseClickEnabled and c.IsMouseMotionEnabled then
        Zone.shelfMouse = { c:IsMouseClickEnabled(), c.IsMouseWheelEnabled and c:IsMouseWheelEnabled() or false,
            c:IsMouseMotionEnabled() }
    else
        Zone.shelfMouse = { c:IsMouseEnabled(), c.IsMouseWheelEnabled and c:IsMouseWheelEnabled() or false }
    end
    pcall(c.EnableMouse, c, false)
    pcall(c.EnableMouseWheel, c, false)
    Zone.MinimapBack()
    ApplyOpacity()
    if ns.mapButton then ns.mapButton:Hide() end
    if Keep.closeButton then Keep.closeButton:Hide() end
    if ns.panel then ns.panel:Hide() end
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
        if m[3] ~= nil and c.SetMouseClickEnabled then
            pcall(c.SetMouseClickEnabled, c, m[1] and true or false)
            pcall(c.SetMouseMotionEnabled, c, m[3] and true or false)
        else
            pcall(c.EnableMouse, c, m[1] and true or false)
        end
        pcall(c.EnableMouseWheel, c, m[2] and true or false)
    end
    if show and ns.compact then ns.ApplyLook() Keep.EscapeOn(true) Keep.CaveWheel() end
end

-- In a fight the game, not OpenMap, may move the map (in a cave, or once it's been set up for the fight), and its
-- zoom changes the map underneath, which the border and the markers can't follow till the fight ends: the wheel
-- off meanwhile (dragging stays)
function Keep.CaveWheel()
    local c = Canvas()
    if not c or not c.EnableMouseWheel or (ns.compact and Zone.shelved) then return end -- (kept unseen: its mouse is off anyway)
    local off = ns.compact and InCombatLockdown() and OpenMapDrives() and true or false
    -- (checked against the map as it is, not only what was set last: the click through puts the map's mouse back
    -- as you hold Shift, the wheel with it)
    if off then
        if c:IsMouseWheelEnabled() then pcall(c.EnableMouseWheel, c, false) end
        Keep.wheelOff = true
    elseif Keep.wheelOff then
        Keep.wheelOff = nil
        pcall(c.EnableMouseWheel, c, true)
    end
end

-- In a fight with OpenMap, its own quest icons instead of the game's: always with Ready in combat, and when the map
-- was opened in the fight without it (Otherwise hide markers in fights), where the game's would be out of place
function Keep.FightQuests()
    if not (ns.compact and InCombatLockdown() and OpenMapDrives()) then return false end
    -- (not with Ready in combat: the game's are placed right then, and OpenMap leaves the quests of the map under its
    -- picture to the game's markers, so hiding them left that zone without any)
    return Keep.combatMismatch and true or false
end

-- Ready in combat (db.combatReady, off by default): in a group the game protects the map in combat (your
-- party's markers on it), and an addon can't open it then. With this on, as combat starts (the last moment
-- the game still allows it) the map is opened unseen, as if closed in combat (Zone.Shelve): the key shows it
-- during the fight, and it closes for real as combat ends. Opening it costs a short stutter, so only when it
-- would be blocked (solo the map opens in combat anyway) and only when chosen.
function Keep.ReadyForCombat()
    Keep.readyNote = nil
    if not db or not db.combatReady or ns.compact then return end
    local map = Map()
    if not map or map:IsShown() then return end
    -- (solo the map opens in a fight anyway, but with OpenMap its view can't be set up then: the markers and the
    -- border came out of place, Keep.combatMismatch. Readied as the fight starts, it's set up)
    if not map:IsProtected() and not OpenMapLoaded() then Keep.readyNote = "not needed (the map isn't protected)" return end
    if Wizard.frame and Wizard.frame:IsShown() then return end
    if InCombatLockdown() then Keep.readyNote = "too late: combat had already locked the map" return end
    Open()
    if ns.compact then
        pcall(Keep.OpeningView) -- (now, while the map can still be moved: see Keep.OpeningView)
        Keep.readyViewAt = GetTime()
        Zone.Shelve()
        Keep.readyNote = "opened unseen as combat began"
    else
        Keep.readyNote = "couldn't open as combat began"
    end
end
