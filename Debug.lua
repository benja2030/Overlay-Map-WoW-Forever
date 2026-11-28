-- Overlay Map: /omap debug and Report a bug.
-- The files share one table, ns, and load in the order of OverlayMap.toc (Core.lua first).

local ADDON_NAME, ns = ...
local Keep, Zone = ns.Keep, ns.Zone
local db
ns.dbSetters[#ns.dbSetters + 1] = function(t) db = t end
-- From the files before this one
local stopped, iconLayers, Say, Map, Canvas, HIDE_GROUPS = ns.stopped, ns.iconLayers, ns.Say, ns.Map, ns.Canvas, ns.HIDE_GROUPS
local GroupFrames, hiddenExtra, faded, shields, mouseOff, mouseLater = ns.GroupFrames, ns.hiddenExtra, ns.faded, ns.shields, ns.mouseOff, ns.mouseLater
local moved, SaveLevels, maskedTex, onlyHidden, IsTownsfolk = ns.moved, ns.SaveLevels, ns.maskedTex, ns.onlyHidden, ns.IsTownsfolk

-- Report a bug (/omap report, the small panel, the main options' General tab): an addon can't open a web page
-- or copy to the clipboard, so a window shows the link to the CurseForge page's comments (where players
-- report; GitHub's issues for those with an account) and a short report, both selected for Ctrl+C. The report
-- says which versions, cave, zone and settings, so a "this cave looks wrong" comes with what's needed to find
-- it; short, as a comment (the whole of /omap debug on request).
Keep.BUG_URL = "https://www.curseforge.com/wow/addons/overlay-map/comments"
Keep.BUG_URL_GH = "https://github.com/benja2030/Overlay-Map-WoW-Forever/issues/new"
-- (the lines of /omap debug a report keeps)
Keep.BUG_LINES = { "debug.", "Saved:", "Where you are:", "Caves and dungeons:", "Zone border:", "Towns:", "Flights:",
    "Ready in combat:", "Last opening:", "Addons on the map:", "Dungeon Journal:", "Map-related addons loaded:" }
function Keep.BugText()
    local lines = {}
    _G.OVERLAYMAP_CAPTURE = lines
    local ok, err = pcall(OverlayMap_Debug)
    _G.OVERLAYMAP_CAPTURE = nil
    if not ok then lines[#lines + 1] = "(debug stopped: " .. tostring(err) .. ")" end
    local function Ver(name)
        local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        local v = get and get(name, "Version")
        return v and (name .. " " .. v) or nil
    end
    local head = { "Overlay Map bug report", date("%Y-%m-%d %H:%M") }
    for _, name in ipairs({ ADDON_NAME, "OverlayMap_ZoneBorders", "OverlayMap_Outlines", "OpenMap", "Questie" }) do
        local v = Ver(name)
        if v then head[#head + 1] = v end
    end
    head = { table.concat(head, ", "), "What happened:", "" }
    for _, l in ipairs(lines) do
        local plain = l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local keep = Keep.bugFull
        if not keep then
            for _, start in ipairs(Keep.BUG_LINES) do
                if plain:find(start, 1, true) == 1 then keep = true break end
            end
        end
        if keep then head[#head + 1] = plain end
    end
    return table.concat(head, "\n")
end
function Keep.BugReport(github)
    local f = Keep.bugFrame
    if not f then
        f = CreateFrame("Frame", "OverlayMapBugReport", UIParent, "BackdropTemplate")
        Keep.bugFrame = f -- (made once: opened again, the same window)
        f:SetSize(520, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(9100)
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.05, 0.045, 0.04, 0.97)
        f:SetBackdropBorderColor(0.75, 0.55, 0.15, 0.9)
        tinsert(UISpecialFrames, "OverlayMapBugReport")
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText("Report a bug")
        -- (the X in the corner, its pictures set here: the template's alone didn't show on this window)
        local close = CreateFrame("Button", nil, f)
        close:SetSize(30, 30)
        close:SetPoint("TOPRIGHT", -3, -3)
        close:SetFrameLevel(f:GetFrameLevel() + 20)
        close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
        close:SetScript("OnClick", function() f:Hide() end)
        local how = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        how:SetPoint("TOPLEFT", 14, -40)
        how:SetPoint("RIGHT", -14, 0)
        how:SetJustifyH("LEFT")
        how:SetText("1. Copy this link (Ctrl+C), open it in your browser and leave a comment there:")
        local link = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        link:SetHeight(22)
        link:SetPoint("TOPLEFT", 20, -60)
        link:SetPoint("RIGHT", -16, 0)
        link:SetAutoFocus(false)
        link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        link:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.url or Keep.BUG_URL) self:HighlightText() end end)
        link:SetScript("OnEscapePressed", function() f:Hide() end)
        f.link = link
        local how2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        how2:SetPoint("TOPLEFT", 14, -92)
        how2:SetPoint("RIGHT", -14, 0)
        how2:SetJustifyH("LEFT")
        how2:SetText("2. Click in the report below, copy it (Ctrl+A, then Ctrl+C) and paste it in your comment, after "
            .. "what happened. A screenshot helps too.")
        local scroll = CreateFrame("ScrollFrame", "OverlayMapBugScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -130)
        scroll:SetPoint("BOTTOMRIGHT", -34, 44)
        -- (the whole of /omap debug, when asked for it)
        local full = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        full:SetSize(22, 22)
        full:SetPoint("BOTTOMLEFT", 12, 12)
        full.text = full:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        full.text:SetPoint("LEFT", full, "RIGHT", 2, 0)
        full.text:SetText("Full report (when asked for it)")
        full:SetScript("OnClick", function(self)
            Keep.bugFull = self:GetChecked() and true or false
            f.box:SetText(Keep.BugText())
            f.box:SetCursorPosition(0)
        end)
        f.full = full
        local gh = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gh:SetPoint("BOTTOMRIGHT", -14, 18)
        gh:SetText("Have a GitHub account? /omap github")
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject("ChatFontNormal")
        box:SetWidth(460)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        scroll:SetScrollChild(box)
        f.box = box
    end
    f.url = github and Keep.BUG_URL_GH or Keep.BUG_URL
    f.link:SetText(f.url)
    Keep.bugFull = false
    f.full:SetChecked(false)
    f.box:SetText(Keep.BugText())
    f.box:SetCursorPosition(0)
    f:Show()
    f.link:SetFocus()
    f.link:HighlightText()
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
    Say("debug. Client " .. tostring((select(4, GetBuildInfo()))) .. ", Overlay Map open: " .. tostring(ns.compact))
    Say("Saved: size " .. f(db.scale) .. ", map " .. f(db.opacity) .. ", markers " .. f(db.pinOpacity)
        .. ", overlay mode " .. tostring(db.overlay and true or false) .. ", style " .. tostring(db.style))
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
        Say(ns.Addons.DebugLine())
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
            ns.layer and ns.layer:IsShown() and (ns.layer:GetFrameStrata() .. " " .. ns.layer:GetFrameLevel()) or "not in use")
            or ("OpenMap's not found" .. (Zone.FindArrow() and " (but it's there)" or "")))
            .. (gp and string.format("; the game's arrow pin: %s %d, on %s", gp:GetFrameStrata(), gp:GetFrameLevel(),
                gp:GetParent() == ns.layer and "the markers' layer" or "the map") or "; no game arrow pin"))
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
        do
            local tu, tv = Zone.TownHere(Zone.townFor ~= nil)
            local per = Zone.WorldPerYard()
            local near
            local pu, pv = Zone.PlayerWorld()
            if Zone.towns and per and pu then
                for _, t in ipairs(Zone.towns) do
                    local d = math.sqrt((t[1] - pu) ^ 2 + (t[2] - pv) ^ 2) / per
                    if not near or d < near then near = d end
                end
            end
            Say(string.format("Towns: %s; %s spots known%s; nearest %s yd; %s%s", db.fitTowns and "on" or "off",
                Zone.towns and tostring(#Zone.towns) or (Zone.townsBuilding and "still gathering" or "none"),
                Zone.townsError and (" (error: " .. Zone.townsError .. ")") or "",
                near and string.format("%d", near) or "?", tu and "in a town" or "not in a town",
                Zone.townNote and (Zone.townNote.mine and ", kept your zoom" or "") or ""))
        end
        Say(string.format("Where you are: the game says %s, the outlines say %s; auto-zoom to zone: %s%s%s",
            tostring(C_Map.GetBestMapForUnit("player")), tostring(Zone.PlayerZone()),
            db.fitEnter and "entering " or "", db.fitOpen and "opening " or "", db.fitLeave and "leaving" or ""))
        Say("Flights: " .. (db.fitFlights and "on" or "off") .. "; on a flight now: " .. tostring(Zone.OnFlight()))
        Say("Ready in combat: " .. (db.combatReady and "on" or "off") .. (Keep.readyNote and ("; last fight: " .. Keep.readyNote) or "")
            .. "; map protected now: " .. tostring(Map() and Map():IsProtected() and true or false)
            .. (Keep.combatMismatch and ("; opened in this fight without it: markers "
                .. "replaced till it ends") or "")
            .. ("; OpenMap's view " .. (function()
                local ok, u, v, z = pcall(function() return _G.OpenMapAPI.GetView() end)
                return ok and type(z) == "number" and string.format("%.3f, %.3f, zoom %.2f", u, v, z) or "?"
            end)()))
        Say("Caves and dungeons: " .. (db.fitPlaces and "on" or "off") .. "; "
            .. (Zone.InDungeon() and ("in a dungeon, map " .. tostring(C_Map.GetBestMapForUnit("player")))
                or u0 and "in a cave" or ("not in a cave" .. ((IsIndoors and IsIndoors()) and " (indoors)" or "")))
            .. (Zone.caveKey and Zone.caveKey > 0 and (", cave map " .. Zone.caveKey
                .. ((_G.OverlayMap_ZoneBordersCaves and _G.OverlayMap_ZoneBordersCaves["map " .. Zone.caveKey])
                    and " (entrance opened)" or "")) or "")
            .. (Zone.caveKey and Zone.caveKey < 0 and (", cave " .. Zone.caveKey .. (Zone.CaveShape(Zone.caveKey)
                and (" (its own shape " .. Zone.CaveShape(Zone.caveKey) .. ")")
                or (_G.OverlayMap_ZoneBordersCaves and " (box: no shape for it)"
                    or " (box: the cave shapes of Zone Borders 1.1.0 aren't loaded)"))) or "")
            .. (Zone.caveFor and ", cave fitted" or "") .. (Zone.dungeonFor and ", dungeon fitted" or "")
            .. (Zone.whereHidden and string.format("; your position last hidden %.0f s ago", GetTime() - Zone.whereHidden) or ""))
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
        local why = not db.liveMinimap and "option off" or not ns.compact and "map closed" or not Zone.InDungeon() and "not in a dungeon"
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
        -- (the markers sorted by the border: on the markers' layer inside it, on the outside layer outside)
        local inside, outside = 0, 0
        for pin in pairs(moved) do
            if pin:GetParent() == Zone.outLayer then outside = outside + 1 elseif pin:GetParent() == ns.layer then inside = inside + 1 end
        end
        Say(string.format("  markers: %d inside the border, %d outside (outside layer %s, alpha %.2f)", inside, outside,
            Zone.outLayer and (Zone.outLayer:IsShown() and "shown" or "hidden") or "not made", Zone.outLayer and Zone.outLayer:GetAlpha() or 0))
        local omAll, omOut, omHid = 0, 0, 0
        for pin in pairs(Zone.omPins) do
            omAll = omAll + 1
            if Zone.omFaded[pin] then omOut = omOut + 1 if pin.omHidden then omHid = omHid + 1 end end
        end
        Say(string.format("  OpenMap icons: %d known, %d outside the border (%d hidden)%s", omAll, omOut, omHid,
            Zone.omHooked and "" or ", not hooked"))
        local lines, cut, shownLines = 0, 0, 0
        local function count(f, depth)
            for _, r in ipairs({ f:GetRegions() }) do
                if r:GetObjectType() == "Line" then
                    lines = lines + 1
                    if r:IsVisible() then shownLines = shownLines + 1 end
                    if maskedTex.zone[r] then cut = cut + 1 end
                end
            end
            if depth < 3 then for _, child in ipairs({ f:GetChildren() }) do count(child, depth + 1) end end
        end
        if ns.viewLayer then count(ns.viewLayer, 0) end
        if ns.layer then count(ns.layer, 0) end
        local stretches, stretchesCut = 0, 0
        if ns.layer then
            for _, pin in ipairs({ ns.layer:GetChildren() }) do
                local icon = pin.icon
                if icon and icon.type == "line" then
                    stretches = stretches + 1
                    for _, r in ipairs({ icon:GetRegions() }) do if maskedTex.zone[r] then stretchesCut = stretchesCut + 1 break end end
                end
            end
        end
        local omLines, omLinesOut = 0, 0
        for line in pairs(Zone.omLines) do
            if line:IsShown() then omLines = omLines + 1 if Zone.omLinesFaded[line] then omLinesOut = omLinesOut + 1 end end
        end
        Say(string.format("  paths: %d lines (%d showing), %d cut by the border; Questie path stretches %d, %d cut; OpenMap's lines %d, %d outside the border",
            lines, shownLines, cut, stretches, stretchesCut, omLines, omLinesOut))
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
            ns.layer and ns.layer:IsShown() and (ns.layer:GetFrameStrata() .. " " .. ns.layer:GetFrameLevel()) or "not in use",
            ns.viewLayer and ns.viewLayer:IsShown() and (ns.viewLayer:GetFrameStrata() .. " " .. ns.viewLayer:GetFrameLevel()) or "not in use",
            n, tostring(low), tostring(high)))
        for f in pairs(iconLayers) do
            local levels = {}
            SaveLevels(f, levels, 5)
            local bottom, top = nil, nil
            for fr, l in pairs(levels) do
                if fr ~= f then bottom, top = math.min(bottom or l, l), math.max(top or l, l) end
            end
            Say(string.format("   icon layer: on %s (%s), level %d, its icons %s to %s",
                f:GetParent() == ns.viewLayer and "Overlay Map's icon layer" or "the map", f:GetFrameStrata(), f:GetFrameLevel(),
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
    -- (an indented line, without the "Overlay Map:" in front; into the bug report while one is put together)
    local function Line(msg)
        local cap = rawget(_G, "OVERLAYMAP_CAPTURE")
        if cap then cap[#cap + 1] = msg return end
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
    for i = 1, math.min(#kinds, 12) do Line("   " .. kinds[i]) end
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
        if fr == ns.layer then what = what .. " [Overlay Map's marker layer]" end
        if fr == ns.viewLayer then what = what .. " [Overlay Map's icon layer]" end
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
            Line("   " .. string.rep("  ", n) .. Describe(fr))
            fr, n = fr:GetParent(), n + 1
        end
    else
        Say("Under the mouse: nothing")
    end
    Say("Map-related addons loaded: " .. (#list > 0 and table.concat(list, ", ") or "none"))
end
