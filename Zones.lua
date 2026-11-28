-- Overlay Map: the zone border and the map's edges, caves, towns, dungeons, Auto-zoom and Center on me.
-- The files share one table, ns, and load in the order of OverlayMap.toc (Core.lua first).

local ADDON_NAME, ns = ...
local Keep, Zone, Outline = ns.Keep, ns.Zone, ns.Outline
local db
ns.dbSetters[#ns.dbSetters + 1] = function(t) db = t end
-- From the files before this one
local iconLayers, Say, Map, Canvas, Stop, OpenMapLoaded = ns.iconLayers, ns.Say, ns.Map, ns.Canvas, ns.Stop, ns.OpenMapLoaded
local Fill, Content, Above, ApplyOpacity, PlayerOnMap, OverMarker = ns.Fill, ns.Content, ns.Above, ns.ApplyOpacity, ns.PlayerOnMap, ns.OverMarker

-- Soft edges. The map and its markers fade out towards the edges of the map area, like the
-- overlay maps of other games. Every picture in the map area gets a mask: a picture that is
-- solid in the middle and fades to nothing at its edges, laid over the map area. Each frame
-- holding pictures gets its own mask; new pictures (markers appearing, map tiles loading as
-- you zoom) are picked up as they come.
local SHAPE_FILES = { rect = "Edge", diamond = "Diamond", oval = "Oval" }
ns.SHAPE_FILES = SHAPE_FILES
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
function Zone.AnyFit() return db.fitEnter or db.fitOpen or db.fitLeave end
function Zone.IsCity(id) return id ~= nil and (Zone.CITY_ZONE[id] or Zone.SAME_PLACE[id]) ~= nil end
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
-- The zone you're in, as the outlines show it (ZoneGrid.lua): the game's zone lines don't follow the painted
-- outline (Dun Algaz is Wetlands to the game, past Wetlands' painted map), so walking out of the outline you
-- were in the hidden part of the map until the game said you'd changed zone. Now: the game's zone while
-- you're inside its outline (or a capital's in it); else the outline you're inside; inside none (a gap, the
-- sea), nil, as the game gives for places with no outline ("Keep the border over the sea and between zones"
-- keeps the one you had). Without the grid or OpenMap's world: the game's zone, as before.
function Zone.PlayerZone()
    local game = Zone.Outlined(C_Map.GetBestMapForUnit("player"))
    local grid = _G.OverlayMapZoneGrid
    Zone.pzOutside = false
    if not (grid and game and Zone.OpenMapStitched and Zone.OpenMapStitched()) or Zone.inCave or (IsIndoors and IsIndoors()) then
        return game
    end
    local u, v = Zone.PlayerWorld()
    if not u then
        -- (where you are hidden for a moment: the outline you were in kept, in the same game zone)
        Zone.whereHidden = GetTime()
        if Zone.pzKey and Zone.pzKey:match("(%-?%d+)$") == tostring(game) then
            Zone.pzOutside = Zone.pzOut
            return Zone.pzZone
        end
        return game
    end
    -- (worked out again only when you've moved a few yards or the game's zone changed)
    local key = string.format("%d %d %d", u * 20000, v * 20000, game)
    if Zone.pzKey == key then Zone.pzOutside = Zone.pzOut return Zone.pzZone end
    local zone = game
    local inGame = Zone.InOutline(game, u, v)
    if inGame == false then
        zone = nil
        for _, id in ipairs(Zone.Partners(game)) do
            if Zone.InOutline(id, u, v) then zone = game break end
        end
        -- (capitals first: a capital's outline lies inside its zone's)
        for pass = 1, 2 do
            if zone then break end
            for id in pairs(grid) do
                if id ~= game and (pass == 2) == not Zone.IsCity(id) and Zone.InOutline(id, u, v) then
                    zone = id
                    break
                end
            end
        end
    end
    -- (on land the game gives a zone, outside every outline: you left the outline, the whole map shows, as
    -- leaving a zone; "Keep the border over the sea and between zones" is for the sea and no-zone land)
    Zone.pzKey, Zone.pzZone, Zone.pzOut = key, zone, zone == nil
    Zone.pzOutside = Zone.pzOut
    return zone
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
    -- (on a flight, or in no outlined zone: just following you, so you don't leave the view; with Auto-zoom
    -- flights, kept to the zone fitted, as on foot)
    if UnitOnTaxi("player") and not db.fitFlights then return u, v end
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
    -- (the map opened in a fight with OpenMap: OpenMap can't put its view right till the fight ends, and the
    -- outline came out a different size and place than the map under it. The whole map meanwhile, cut again
    -- as the fight ends: Zone.AfterCombat)
    if Keep.combatMismatch and not Zone.inFightZone then
        -- (the zone the border would have, worked out all the same: the markers outside it still follow "Rest of the
        -- map visibility", by where they are in the world, Zone.MarkZone)
        Zone.inFightZone = true
        local ok, zone = pcall(Zone.MaskZone)
        Zone.inFightZone = nil
        if (Zone.fightZone or false) ~= ((ok and zone) or false) then Keep.pinsDirty = true end
        Zone.fightZone = ok and zone or nil
        Zone.why = "opened in a fight: the border comes back as it ends"
        return
    end
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
    local id = db.zoneView and here or Zone.PlayerZone()
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
    if not zone and not tried and db.zoneKeep and not (Zone.pzOutside and not db.zoneView) then
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
    local was = Zone.zoneNow
    Zone.zoneNow = (Zone.shown and Zone.level and Zone.level < 100) and Zone.shown or nil
    if was ~= Zone.zoneNow then Keep.pinsDirty = true end
end

-- How much of the outside of the zone shows (the rest of the map's visibility): 1 without a zone border
-- The zone the markers are judged by: the border's, or in a fight without the border, the one it would have
function Zone.MarkZone()
    return Zone.zoneNow or (Keep.combatMismatch and Zone.fightZone) or nil
end

function Zone.OutsideShare()
    if db.zoneBorder and not Zone.zoneNow and Keep.combatMismatch and Zone.fightZone then return db.zoneDim or 0 end
    if not (db.zoneBorder and Zone.zoneNow) then return 1 end
    return math.max(0, math.min(1, (Zone.level or 0) / 100))
end

-- Which layer a marker goes on: the markers' layer, or (with a zone border, a marker whose spot is outside the
-- zone) the outside layer. Its spot: the middle of the marker, on the map shown, into the world, and the zone
-- there (as deep as the game's maps go). Kept per marker until it, the map shown or the zone changes.
Zone.pinWhere = setmetatable({}, { __mode = "k" })
-- A stretch of a Questie path (Questie's own drawing of it, a frame of type "line"), or a frame inside one
function Zone.IsPath(f)
    if f.type == "line" then return true end
    local parent = f:GetParent()
    return parent ~= nil and parent.type == "line"
end

function Zone.PinLayer(pin)
    -- (the game's arrow (your party's dots with it: one marker), with "My arrow doesn't fade": on the arrow's
    -- layer, which isn't faded while you move)
    if db.arrowNoFade and pin.pinTemplate == "GroupMembersPinTemplate" then return Zone.ArrowPinLayer() end
    if not (db.zoneBorder and Zone.MarkZone()) then return ns.layer end
    -- (a path's marker always on the markers' layer, cut by the border there: Zone.pathsOnly. On the outside
    -- layer, all of it would go, the part inside your zone too)
    if pin.icon and pin.icon.type == "line" then return ns.layer end
    if not Zone.outLayer then
        Zone.outLayer = CreateFrame("Frame", "OverlayMapMarkersOutside", UIParent)
        Zone.outLayer:SetClipsChildren(true)
        ns.SyncLayer()
    end
    return Zone.PinOutside(pin) and Zone.outLayer or ns.layer
end

function Zone.PinOutside(pin)
    local content = Content()
    local seen = Zone.pinWhere[pin]
    -- (where it's drawn: Questie's icon, which OpenMap may move off its marker to the right spot for WoW:
    -- Forever, else the marker. A marker on the hidden outside layer has no place on screen: then it keeps
    -- the side it was on, or it went back and forth every second, flickering)
    local spot = (pin.icon and pin.icon.GetCenter) and pin.icon or pin
    -- (opened in a fight: the map under the markers isn't at OpenMap's view, so where one is drawn says nothing.
    -- Questie's keep their spot on the icon: judged by it; others as inside)
    if Keep.combatMismatch and not Zone.zoneNow then
        local icon = pin.icon
        local S = _G.OpenMap and _G.OpenMap.MapStitch
        if icon and icon.UiMapID and type(icon.x) == "number" and type(icon.y) == "number" and S and S.Rect then
            local ok, l, r, t, b = pcall(S.Rect, icon.UiMapID)
            if ok and l then
                return Zone.WorldOutside(l + icon.x / 100 * (r - l), t + icon.y / 100 * (b - t)) and true or false
            end
        end
        return false
    end
    local x, y = spot:GetCenter()
    local cl, ct = content:GetLeft(), content:GetTop()
    local cw, ch = content:GetSize()
    if not (x and cl and cw and cw > 0 and ch > 0) then return seen and seen.out or false end
    local pe, ce = spot:GetEffectiveScale(), content:GetEffectiveScale()
    local nx = (x * pe - cl * ce) / (cw * ce)
    local ny = (ct * ce - y * pe) / (ch * ce)
    local host = Map():GetMapID()
    local key = string.format("%s %.4f %.4f %s", tostring(host), nx, ny, tostring(Zone.zoneNow))
    if seen and seen.key == key then return seen.out end
    local out = false
    local hl, hr, ht, hb = Zone.WorldRect(host)
    if hl then out = Zone.WorldOutside(hl + nx * (hr - hl), ht + ny * (hb - ht)) end
    Zone.pinWhere[pin] = { key = key, out = out }
    return out
end

-- Whether a point of OpenMap's world is inside a zone's outline as it's drawn (ZoneGrid.lua: the outline's
-- picture as a grid). The game's own zone lines don't follow the painted outline: Dun Algaz is Wetlands to
-- the game, past the bottom of Wetlands' painted map, so its markers showed outside the border.
Zone.gridRows = {}
Zone.GRID_VALUE = {}
do
    local al = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #al do Zone.GRID_VALUE[al:byte(i)] = i - 1 end
end
function Zone.InOutline(id, u, v)
    local grid = _G.OverlayMapZoneGrid
    local data = grid and grid[id]
    if not data then return nil end
    local l, r, t, b = Zone.WorldRect(id)
    if not l then return nil end
    local fx, fy = (u - l) / (r - l), (v - t) / (b - t)
    if fx < 0 or fx >= 1 or fy < 0 or fy >= 1 then return false end
    local rows = Zone.gridRows[id]
    if not rows then
        rows = {}
        for row in data:gmatch("[^,]+") do rows[#rows + 1] = row end
        Zone.gridRows[id] = rows
    end
    local row = rows[math.floor(fy * #rows) + 1]
    if not row then return false end
    local col, at, inside = math.floor(fx * 128), 0, false
    for i = 1, #row do
        at = at + (Zone.GRID_VALUE[row:byte(i)] or 0)
        if col < at then return inside end
        inside = not inside
    end
    return false
end

-- The other outlines that count as the same place (a capital and the zone it's in)
Zone.partners = {}
function Zone.Partners(id)
    local list = Zone.partners[id]
    if list then return list end
    list = {}
    for other in pairs(_G.OverlayMapZoneGrid or {}) do
        if other ~= id and Zone.Same(other) == Zone.Same(id) then list[#list + 1] = other end
    end
    Zone.partners[id] = list
    return list
end

-- A point of OpenMap's world outside the zone's border (in a cave: outside its box). Inside: within the
-- zone's outline as drawn (or a capital's in it), or in a cave of the zone's (its quests are there, past the
-- painted outline). Without the grid (an older Overlay Map file list), the game's own zone lines.
function Zone.WorldOutside(u, v)
    local now = Zone.MarkZone()
    if not now then return false end
    if type(now) == "string" then
        local l, r, t, b = Zone.WorldRect(now)
        return l and (u < l or u > r or v < t or v > b) or false
    end
    local inOutline = Zone.InOutline(now, u, v)
    if inOutline ~= nil then
        if inOutline then return false end
        for _, id in ipairs(Zone.Partners(now)) do
            if Zone.InOutline(id, u, v) then return false end
        end
        if not Zone.CaveKeyAt(u, v) then return true end
    end
    local zone = Zone.Outlined(Zone.DeepestAt(u, v))
    return not zone or Zone.Same(zone) ~= Zone.Same(now)
end

-- OpenMap's own icons (its quest "!" and "?", flight masters, dungeons, boats, your pins ...): on its icon layer,
-- not among the map's markers, so the outside layer never had them. Each knows its spot in the world (u, v).
-- Outside the zone's border: at the rest of the map's visibility, and at 0% unseen and out of the mouse's
-- reach. Only with a zone border; anything else (no border, the map closed) puts them back as OpenMap had them.
Zone.omPins = setmetatable({}, { __mode = "k" })  -- every one of OpenMap's icons seen
Zone.omFaded = setmetatable({}, { __mode = "k" }) -- the ones changed here
-- (hidden at 0%, not made to ignore the mouse: click-through already switches their clicks, and the two fought.
-- One OpenMap hides itself, back to its pool, isn't Overlay Map's any more: shown again here, it came back as
-- a stray icon in an old spot)
function Zone.OMPinHidden(pin)
    if Zone.omHiding then return end
    Zone.omFaded[pin], pin.omHidden = nil, nil
    pin:SetAlpha(1)
end

function Zone.OMPinLook(pin, share)
    local out = false
    if Zone.omAllOut then -- (all of them hidden: the map opened in a fight, see ApplyOpacity)
        out, share = true, 0
    elseif share < 1 and type(pin.u) == "number" and type(pin.v) == "number" then
        if pin.omU == pin.u and pin.omV == pin.v and pin.omZone == Zone.MarkZone() and pin.omGen == Zone.omGen then
            out = pin.omOut
        else
            out = Zone.WorldOutside(pin.u, pin.v) and true or false
            pin.omU, pin.omV, pin.omZone, pin.omOut, pin.omGen = pin.u, pin.v, Zone.MarkZone(), out, Zone.omGen
        end
    end
    if out then
        if not Zone.omFaded[pin] then
            if not pin:IsShown() then return end -- (one OpenMap keeps hidden: left so)
            Zone.omFaded[pin] = true
            if not pin.omHooked then pin.omHooked = true hooksecurefunc(pin, "Hide", Zone.OMPinHidden) end
        end
        if math.abs(pin:GetAlpha() - share) > 0.001 then pin:SetAlpha(share) end
        if share <= 0.02 then
            if pin:IsShown() then
                Zone.omHiding = true
                pin:Hide()
                Zone.omHiding = false
                pin.omHidden = true
            end
        elseif pin.omHidden then
            pin.omHidden = nil
            pin:Show()
        end
    elseif Zone.omFaded[pin] then
        Zone.omFaded[pin] = nil
        pin:SetAlpha(1)
        if pin.omHidden then pin.omHidden = nil pin:Show() end
    end
end

-- OpenMap's lines (Questie's paths as OpenMap draws them, flight routes, drawings): the game doesn't cut a line
-- with the zone's border as it does a picture, so each piece is judged by its middle, as the icons are by their
-- spot: outside, at the rest of the map's visibility (unseen at 0%). Its middle is known from where OpenMap drew
-- it (S.AddLine, S.AddPath: in its world). A piece that crosses the border shows or goes whole; a path is
-- many short pieces.
Zone.omLines = setmetatable({}, { __mode = "k" })  -- [line] = true: every line OpenMap drew since the hook
Zone.omLinesFaded = setmetatable({}, { __mode = "k" })
function Zone.OMLineLook(line, share)
    local out = false
    if Zone.omAllOut then
        out, share = true, 0
    elseif share < 1 and line.omMidU then
        if line.omZone == Zone.MarkZone() and line.omGen == Zone.omGen and line.omMidKey == line.omMidU + line.omMidV then
            out = line.omOut
        else
            out = Zone.WorldOutside(line.omMidU, line.omMidV) and true or false
            line.omZone, line.omGen, line.omMidKey, line.omOut = Zone.MarkZone(), Zone.omGen, line.omMidU + line.omMidV, out
        end
    end
    if out then
        Zone.omLinesFaded[line] = true
        if math.abs(line:GetAlpha() - share) > 0.001 then line:SetAlpha(share) end
    elseif Zone.omLinesFaded[line] then
        Zone.omLinesFaded[line] = nil
        line:SetAlpha(1)
    end
end
function Zone.OMLineDrawn(line, u1, v1, u2, v2)
    if not (line and type(u1) == "number" and type(v1) == "number" and type(u2) == "number" and type(v2) == "number") then return end
    Zone.omLines[line] = true
    line.omMidU, line.omMidV = (u1 + u2) / 2, (v1 + v2) / 2
    -- (a line OpenMap takes back from its pool keeps the alpha it was given here: judged again at once)
    if ns.compact and ns.Addons.OpenMapIconsOff() then return end
    if ns.compact or Zone.omLinesFaded[line] then Zone.OMLineLook(line, ns.compact and Zone.OutsideShare() or 1) end
end

-- Every icon again (the zone, the visibility or the icons changed); share 1: all back as they were
function Zone.OMPinsApply(share)
    -- (OpenMap's icons and lines kept off the map, the Addons tab: only Overlay Map's own cave entrances judged;
    -- the ones faded before are put back as the map closes, share 1)
    if share < 1 and ns.Addons.OpenMapIconsOff() then
        local set = Zone.mouthSet
        for _, pin in ipairs(set and set.pins or {}) do
            if Zone.omFaded[pin] or pin:IsShown() then Zone.OMPinLook(pin, share) end
        end
        return
    end
    if share < 1 or next(Zone.omLinesFaded) then
        for line in pairs(Zone.omLines) do Zone.OMLineLook(line, share) end
    end
    if share >= 1 and not next(Zone.omFaded) then return end
    for pin in pairs(Zone.omPins) do
        if Zone.omFaded[pin] or (share < 1 and pin:IsShown()) then Zone.OMPinLook(pin, share) end
    end
end

-- Hooked once: each icon OpenMap adds or moves is judged right away (a reused one too: one faded here and
-- given back to OpenMap's pool comes back faded otherwise). The ones made before: found once on its layer.
function Zone.HookOMPins()
    if Zone.omHooked then return end
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    if not (S and type(S.AddPin) == "function" and type(S.MovePin) == "function") then return end
    Zone.omHooked = true
    local function judge(pin)
        if not pin then return end
        Zone.omPins[pin] = true
        if ns.compact and ns.Addons.OpenMapIconsOff() and not pin.caveName then return end
        if ns.compact and (Zone.omFaded[pin] or Zone.OutsideShare() < 1 or Zone.omAllOut) then Zone.OMPinLook(pin, Zone.OutsideShare()) end
    end
    hooksecurefunc(S, "AddPin", function(set) if type(set) == "table" and set.pins then judge(set.pins[#set.pins]) end end)
    hooksecurefunc(S, "MovePin", function(_, pin) judge(pin) end)
    if type(S.AddLine) == "function" then
        hooksecurefunc(S, "AddLine", function(set, u1, v1, u2, v2)
            if type(set) == "table" and set.lines then Zone.OMLineDrawn(set.lines[#set.lines], u1, v1, u2, v2) end
        end)
    end
    if type(S.AddPath) == "function" then
        -- (one piece between each two points, the last ones added)
        hooksecurefunc(S, "AddPath", function(set, pts)
            if type(set) ~= "table" or not set.lines or type(pts) ~= "table" then return end
            local n = math.floor(#pts / 2) - 1
            local first = #set.lines - n
            for k = 1, n do
                local i = 2 * k - 1
                Zone.OMLineDrawn(set.lines[first + k], pts[i], pts[i + 1], pts[i + 2], pts[i + 3])
            end
        end)
    end
    -- (the paths drawn before the hook: OpenMap asked to draw them again, now through it)
    local mod = Zone.OpenMapModule()
    if mod and type(mod.DrawQuestiePaths) == "function" then pcall(mod.DrawQuestiePaths) end
    Zone.OMWalkLayers()
end

-- One of OpenMap's icons (a button at a world spot), not one of its other frames
function Zone.IsOMPin(f)
    return type(f.u) == "number" and type(f.v) == "number" and f.look ~= nil
end

-- The icons already on an icon layer, found once per layer (one that turns up after the hook too: OpenMap's
-- icon layer can be found a moment after the map opens, its icons placed before)
Zone.omLayers = setmetatable({}, { __mode = "k" })
function Zone.OMWalkLayers()
    if not Zone.omHooked then return end
    local function walk(f, depth)
        for _, child in ipairs({ f:GetChildren() }) do
            if Zone.IsOMPin(child) then
                Zone.omPins[child] = true
            elseif depth > 0 then
                walk(child, depth - 1)
            end
        end
    end
    for f in pairs(iconLayers) do
        if not Zone.omLayers[f] then Zone.omLayers[f] = true walk(f, 3) end
    end
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
    if not ns.compact or Zone.level == nil then self:Hide() return end
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
    if not ns.compact or db.style ~= "outlines" or not Outline.available then Outline.Hide() return end
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
        ns.SyncLayer()
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
ns.maskedTex = maskedTex

-- A marker leaving the map for Overlay Map's layers takes its pictures' zone cut with it (laid while it was
-- still on the map, as the map opened): taken off, so a marker near the border isn't cut there
function Zone.Unzone(f, depth)
    for _, r in ipairs({ f:GetRegions() }) do
        local m = maskedTex.zone[r]
        if m and not Zone.IsPath(f) then pcall(r.RemoveMaskTexture, r, m) maskedTex.zone[r] = nil end
    end
    if depth > 0 then
        for _, child in ipairs({ f:GetChildren() }) do Zone.Unzone(child, depth - 1) end
    end
end

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
    local want = ns.compact and type(Zone.zoneNow) == "string" and Zone.WantShape()
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
        -- (pictures only: the game doesn't cut lines with a mask, OpenMap's are faded instead, Zone.OMLineLook.
        -- On the markers' layer, the zone's border only cuts Questie's path pictures: Zone.pathsOnly)
        if Zone.pathsOnly and not Zone.IsPath(frame) then
            -- (a marker's picture with a zone cut from its time on the map: off, Zone.Unzone)
            if on[r] then pcall(r.RemoveMaskTexture, r, on[r]) on[r] = nil end
        elseif r:GetObjectType() == "Texture" then
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
    -- (OpenMap's icons aren't cut by the zone's border either, as the markers: whole inside it, and outside
    -- it at the rest of the map's visibility, Zone.OMPinLook. Its paths, on the same layer, are still cut)
    if kind == "zone" and Zone.IsOMPin(frame) then
        if Zone.walked.zone[frame] ~= -1 then
            Zone.walked.zone[frame] = -1
            for _, r in ipairs({ frame:GetRegions() }) do
                local m = maskedTex.zone[r]
                if m then pcall(r.RemoveMaskTexture, r, m) maskedTex.zone[r] = nil end
            end
        end
        return
    end
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
ns.UnmaskKind = UnmaskKind

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
        if Zone.opening and ns.compact then ApplyOpacity() end -- (the map can fade in now)
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
    if not ns.compact then
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
ns.ApplyEdges = ApplyEdges
function Zone.ApplyEdgesNow(keepZone)
    if ns.compact and not keepZone then Zone.UpdateZone() end
    if not ns.compact then Zone.Rest() return end
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
            -- (markers: not cut by the zone's border, a marker near it was cut in half; each is shown whole, on
            -- the markers' layer inside the zone, or on the outside layer: Zone.PinLayer. The soft edges still fade them)
            if ns.layer and ns.layer:IsShown() and kind ~= "zone" then MaskTree(ns.layer, 0, kind) end
            -- (but Questie's paths among them are cut by it: a path crosses the border, it has no one spot)
            if ns.layer and ns.layer:IsShown() and kind == "zone" then
                Zone.pathsOnly = true
                MaskTree(ns.layer, 0, kind)
                Zone.pathsOnly = false
            end
            if kind == "shape" and Zone.outLayer and Zone.outLayer:IsShown() then MaskTree(Zone.outLayer, 0, kind) end
            if ns.viewLayer and ns.viewLayer:IsShown() then MaskTree(ns.viewLayer, 0, kind) end
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
-- A while after the map opens, once OpenMap has placed its icons and paths: which side of the zone's border
-- each marker and icon is on, worked out again from scratch, and OpenMap's layer gone through again for the
-- border's cut. Done earlier, some were judged or cut before they were in place, and stayed so until the
-- zone changed (showing outside the border, or its paths uncut, until you looked at another zone and back).
function Zone.FreshLook()
    if not ns.compact or not (db.zoneBorder and Zone.zoneNow) then return end
    wipe(Zone.pinWhere)
    Zone.omGen = (Zone.omGen or 0) + 1
    Zone.omKey = nil
    Keep.pinsDirty = true
    if ns.viewLayer then
        local function forget(f, depth)
            Zone.walked.zone[f], Zone.walked.shape[f] = nil, nil
            if depth >= 5 then return end
            for _, child in ipairs({ f:GetChildren() }) do forget(child, depth + 1) end
        end
        forget(ns.viewLayer, 0)
        if ns.layer then forget(ns.layer, 0) end
        wipe(Zone.kids)
    end
    Zone.OMWalkLayers()
    ApplyOpacity()
    ApplyEdges(true)
end

local function QueueEdges()
    if edgesPending or not ns.compact or (not WantShapeMask() and not db.zoneBorder) then return end
    edgesPending = true
    C_Timer.After(math.max(0, edgesLast + EDGE_GAP - GetTime()), function()
        edgesPending = false
        edgesLast = GetTime()
        if ns.compact then ApplyEdges() end
    end)
end
ns.QueueEdges = QueueEdges

-- OpenMap's view moved: only which zone is outlined is worked out again (ten times a second at most),
-- and the pictures are only gone through when that changes; the outline itself moves with the map.
function Zone.ViewMoved()
    if not ns.compact or not db.zoneBorder or Zone.viewQueued then return end
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
        ns.lastX, ns.lastY = nil, nil
        return
    end
    local api = OpenMapLoaded() and _G.OpenMapAPI
    if api and api.IsStitched and api.IsStitched() then
        local best = C_Map.GetBestMapForUnit("player")
        if not best then return end
        local x, y = PlayerOnMap(best)
        if not x then return end
        if not force and ns.lastX and math.abs(x - ns.lastX) < 1e-4 and math.abs(y - ns.lastY) < 1e-4 then return end
        -- (in combat OpenMap doesn't move its map: Center on me waits for the fight to end, as the fits do)
        if InCombatLockdown() then return end
        ns.lastX, ns.lastY = x, y
        local u, v = api.WorldFromMap(best, x, y)
        -- (while the map zooms to fit a new zone, towards that zoom, not the one it's passing)
        local zoom = Zone.fitUntil and GetTime() < Zone.fitUntil and Zone.fitZoom or nil
        if zoom then
            -- (there already: Center on me back to the zoom it finds, so your own zoom isn't fought)
            local okZ, _, _, cz = pcall(api.GetView)
            if okZ and type(cz) == "number" and math.abs(cz - zoom) <= zoom * 0.01 then Zone.fitUntil = GetTime() + 0.2 end
        end
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
    if not force and ns.lastX and math.abs(x - ns.lastX) < 1e-4 and math.abs(y - ns.lastY) < 1e-4 then return end
    ns.lastX, ns.lastY = x, y
    pcall(c.SetPanTarget, c, x, y)
end
ns.Follow = Follow

-- Entering a new zone (with the zone border): the map zoomed so the zone fits, centred on it. With OpenMap a glide (instant as the map opens); without it, the game's
-- map shows the zone, all of it.
function Zone.Fit(zone, instant)
    if Zone.OpenMapStitched() then
        local fit = Zone.FitZoom(zone)
        local l, r, t, b = Zone.Box(zone)
        local api = _G.OpenMapAPI
        if not fit or not l then return end
        if not api.ShowWorld then return end
        Zone.ViewTo((l + r) / 2, (t + b) / 2, fit * Zone.FIT_MARGIN, instant) -- (after the fight, in combat)
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
        and not (Zone.fitUntil and GetTime() < Zone.fitUntil) and not ns.settling and Canvas():IsMouseOver() then
        Zone.zoomedAt = GetTime()
    end
    Zone.lastZoom = z
end

-- Auto-zoom flights (db.fitFlights): Auto-zoom to zone also during a flight, each zone you fly into fitted to
-- the map (with "Entering a zone"), and the zone fitted as you fly out of a town (with "Leaving a town or
-- city"). Towns aren't zoomed into on the way (you're over them for seconds). Off: nothing until you land.
function Zone.OnFlight() return UnitOnTaxi("player") and true or false end

function Zone.CheckFit(instant)
    -- (on a flight: each zone you fly over with Auto-zoom flights; else the one you land in, once you land)
    if Zone.OnFlight() and not db.fitFlights then return end
    local zone = Zone.PlayerZone()
    if not zone or zone == Zone.fittedFor then return end
    local first = Zone.fittedFor == nil
    -- (out of a capital into another zone: "Leaving a town or city"; anything else: "Entering a zone")
    local leaving = Zone.IsCity(Zone.fittedFor) and not Zone.IsCity(zone)
    Zone.fittedFor = zone
    if first or not (leaving and db.fitLeave or not leaving and db.fitEnter) or not db.zoneBorder or not Zone.Available() then return end
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
        if ns.compact then
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
    if not (ns.compact and ns and ns.IsWorldMapOverlayAttached and toggle and toggle:IsShown()) then return end
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
        if button == "RightButton" and ns.compact then Zone.rightDownAt = GetTime() end
    end)
end

function Zone.HookJournal()
    Zone.WatchRightPress()
    local ns, fdj = _G.ForeverDungeonJournal_NS, _G.ForeverDungeonJournalFrame
    if Zone.journalHooked or not (ns and fdj) then return end
    Zone.journalHooked = true
    if type(ns.RefreshWorldMapOverlay) == "function" then
        hooksecurefunc(ns, "RefreshWorldMapOverlay", function()
            if not ns.compact then return end
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
                if Zone.reclearing or not saved or not ns.compact or (a or 1) <= 0 then return end
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
    return ns.compact and db.liveMinimap and Minimap and Zone.InDungeon() and not Zone.shelved
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
    if ns.compact then
        C_Timer.After(0, function()
            if not ns.compact or Zone.live then return end
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
    -- (a cave map's own cut: Zone Borders' copy of OpenMap's, opened at the cave's entrances, else OpenMap's)
    local own = key and key > 0 and _G.OverlayMap_ZoneBordersCaves and _G.OverlayMap_ZoneBordersCaves["map " .. key]
    if own then return "Interface\\AddOns\\" .. Zone.ADDON .. "\\Cave\\" .. own end
    if key and key > 0 and S and S.CaveMasks then return S.CaveMasks .. key end
    local n = key and key < 0 and Zone.CaveShape(key)
    if n then return "Interface\\AddOns\\" .. Zone.ADDON .. "\\Cave\\" .. n .. (db.zoneSoft and "s" or "") end
    -- (sharp: a plain box of Overlay Map's own, big enough that its cut has no soft rim; the game's small
    -- white square faded over a sixteenth of the box at each edge, a glow round the cave)
    return MEDIA .. (db.zoneSoft and "Edge2" or "Box")
end

-- The cave you're in: its box (left, top, right, bottom) and key; Zone.caveKey keeps the key
-- Cave entrances: a marker at each one Overlay Map knows (cavemouths.py: the caves with a Blizzard cave map,
-- their entrance found on the cave map and checked against the zone's map under it), as OpenMap's own icons,
-- in a set of OpenMap's (so they move, zoom and fade with the others), shown only while Overlay Map shows the
-- map. { cave map, continent, x, y } (world yards)
Zone.CAVE_MOUTHS = {
    { 2, 1, -162.2, -4359.0 }, { 3, 1, -245.1, -5081.4 }, { 5, 1, 1474.1, -4870.2 }, { 6, 1, 808.5, -4751.2 },
    { 8, 1, -2389.8, 302.3 }, { 9, 1, -1901.9, -1102.7 }, { 11, 1, -828.5, -2032.2 }, { 19, 0, 2856.4, -725.9 },
    { 28, 0, -6043.1, 46.4 }, { 28, 0, -6226.8, 121.5 }, { 29, 0, -5623.3, -272.5 }, { 31, 0, -5725.7, -1684.8 },
    { 33, 0, -7387.6, -1148.8 }, { 33, 0, -7731.7, -1082.7 }, { 38, 0, -9844.9, 205.6 }, { 40, 0, -9180.2, -597.5 },
    { 53, 0, -10451.0, 1935.1 }, { 54, 0, -9976.9, 1455.8 }, { 55, 0, -11085.5, 1525.3 }, { 58, 1, 10753.3, 923.5 },
    { 59, 1, 10043.2, 1035.5 }, { 79, 1, -7968.2, -1311.2 }, { 82, 1, -6304.8, 142.4 }, { 426, 0, -8673.2, -117.5 },
    { 428, 0, -6525.5, 482.1 }, { 466, 0, 2047.6, 1819.1 }, { 470, 0, -5542.4, 590.6 },
}
Zone.MOUTH_LOOK = { texture = MEDIA .. "CaveEntrance", size = 18 }
Zone.MOUTH_ZOOM = 2 -- (OpenMap's zoom from which they show: about a zone across, as its dungeon entrances)

function Zone.MouthEnter(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(pin.caveName or "Cave")
    GameTooltip:AddLine("Cave entrance", 1, 1, 1)
    GameTooltip:Show()
end

function Zone.CaveMouthPins()
    local OM = _G.OpenMap
    local S = OM and OM.MapStitch
    if not (S and S.PinSet and S.AddPin and S.FromYards and S.SetPinSetOn) then return end
    local on = ns.compact and db.caveMouths ~= false and Zone.OpenMapStitched()
    local set = Zone.mouthSet
    if not set then
        if not on then return end
        local ok, made = pcall(S.PinSet, "overlaymapCaveMouths", Zone.MOUTH_ZOOM)
        if not (ok and made) then return end
        set = made
        Zone.mouthSet = set
        for _, m in ipairs(Zone.CAVE_MOUTHS) do
            local okY, u, v = pcall(S.FromYards, m[2], m[3], m[4])
            if okY and type(u) == "number" and type(v) == "number" then
                local okP, pin = pcall(S.AddPin, set, u, v, Zone.MOUTH_LOOK)
                if okP and pin then
                    local c = OM.MapCaves and OM.MapCaves[m[1]]
                    pin.caveName = c and c[1] or "Cave"
                    pin:SetScript("OnEnter", Zone.MouthEnter)
                    pin:SetScript("OnLeave", GameTooltip_Hide)
                end
            end
        end
    end
    if set.on ~= on then pcall(S.SetPinSetOn, set, on) end
end

function Zone.CaveHere()
    local was = Zone.caveKey
    Zone.caveKey = nil
    if not (IsIndoors and IsIndoors()) or not Zone.OpenMapStitched() then return end
    local u, v = Zone.PlayerWorld()
    if not u then
        -- (where you are hidden from addons for a moment, as in some fights: still in the cave you were in, not
        -- out of it, which fitted the zone and fitted the cave again once it was back)
        Zone.whereHidden = GetTime()
        local r = was and Zone.CaveRectOf(was)
        if r then
            Zone.caveKey = was
            return r[1], r[2], r[3], r[4], was
        end
        return
    end
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
-- (while the map glides to a zoom of Overlay Map's, Center on me heads for that zoom too: after a second it
-- went back to the zoom passing by, and walking out of a town the glide stopped half-way, zoomed in further
-- than the same fit as the map opens. Until the glide is done, or a few seconds)
Zone.GLIDE_TIME = 4
function Zone.ViewTo(u, v, zoom, instant)
    -- (in combat OpenMap doesn't move its map: it keeps the view asked for till the fight ends, while saying it's
    -- there already, so the border and the lines were laid for a view the map wasn't at. Kept here instead, and
    -- asked for as combat ends: Zone.AfterCombat)
    if InCombatLockdown() then
        Zone.viewLater = { u, v, zoom }
        return
    end
    Zone.viewLater = nil
    Zone.fitZoom, Zone.fitUntil = zoom, GetTime() + Zone.GLIDE_TIME
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
        if ns.compact and type(c.zoomLevels) == "table" and c.zoomLevels[1] and c.InstantPanAndZoom then
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
    if db.zoneBorder and db.fitEnter and zone and Zone.Available() then
        Zone.Fit(zone, instant)
        return
    end
    local u, v = Zone.PlayerWorld()
    if before and u then Zone.ViewTo(u, v, before, instant) end
end

-- force: as the map opens with Fit Zone on each opening, the cave fitted again over the zone
function Zone.CheckPlaces(instant, force)
    if Zone.OnFlight() then
        -- (flying out of a town: back to the zone, with Auto-zoom flights; no town zoomed into on the way)
        if Zone.townFor then
            Zone.townFor, Zone.beforeTown = nil, nil
            local zone = Zone.PlayerZone()
            if db.fitFlights and db.fitLeave and db.zoneBorder and zone and Zone.Available() then
                Zone.fittedFor = zone
                Zone.Fit(zone, instant)
            end
        end
        return
    end
    if not (db.fitPlaces or db.fitTowns) then return end
    local mine = not instant and Zone.zoomedAt and GetTime() - Zone.zoomedAt < Zone.KeepMyZoom()
    if Zone.InDungeon() then
        if not db.fitPlaces then return end
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
    local u0, v0, u1, v1
    if db.fitPlaces then u0, v0, u1, v1 = Zone.CaveHere() end
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
        Zone.townFor = nil -- (a town at the cave's mouth: zoomed in on again)
        return
    end
    if not u0 then Zone.CheckTown(instant, force, mine) end
end

-- Towns (Auto-zoom towns): the game has no list of them, nor of their size. A town here: where an innkeeper
-- (Questie's database of NPCs) or a flight master (OpenMap's flight network) is, not in a capital (which has
-- its own map, fitted as a zone). Entering one (within TOWN_IN yards of one of them), the map zooms in on it,
-- db.townSize yards across, centred on its innkeeper and flight master together; leaving it (past TOWN_OUT), back
-- to your zone (Auto-zoom to zone) or the zoom you had. Not after a zoom of your own (Auto-zoom pause), and not
-- on a flight: once you land.
Zone.TOWN_IN, Zone.TOWN_OUT, Zone.TOWN_SAME = 130, 200, 250 -- yards (TOWN_SAME: one town's NPCs, apart)

-- How much of OpenMap's world a yard is (from where it puts two points 500 yards apart)
function Zone.WorldPerYard()
    if Zone.perYard then return Zone.perYard end
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    local fl = _G.OpenMap and _G.OpenMap.MapFlights
    if not (S and S.FromYards and fl and fl.nodes) then return end
    for _, n in pairs(fl.nodes) do
        local ok, u0, v0 = pcall(S.FromYards, n[2], n[3], n[4])
        local ok2, u1, v1 = pcall(S.FromYards, n[2], n[3] + 500, n[4])
        if ok and ok2 and u0 and u1 then
            local d = math.sqrt((u1 - u0) ^ 2 + (v1 - v0) ^ 2) / 500
            if d > 0 then Zone.perYard = d return d end
        end
    end
end

-- The towns' spots in OpenMap's world, gathered once (Questie's NPCs a few hundred a frame, so nothing stalls)
function Zone.BuildTowns()
    if Zone.towns or Zone.townsBuilding then return end
    local S = _G.OpenMap and _G.OpenMap.MapStitch
    if not (S and S.Rect and S.FromYards) then return end
    Zone.townsBuilding = true
    local spots = {}
    local function Add(u, v, what)
        if not (u and v) then return end
        -- (a capital's: left to Auto-zoom to zone)
        local id = Zone.DeepestAt(u, v)
        if id and (Zone.CITY_ZONE[id] or Zone.SAME_PLACE[id]) then return end
        spots[#spots + 1] = { u, v, what }
    end
    local fl = _G.OpenMap.MapFlights
    for _, n in pairs(fl and fl.nodes or {}) do
        local ok, u, v = pcall(S.FromYards, n[2], n[3], n[4])
        if ok then Add(u, v, "flight") end
    end
    local loader = _G.QuestieLoader
    local okD, QDB = loader and pcall(loader.ImportModule, loader, "QuestieDB")
    local okZ, ZoneDB = loader and pcall(loader.ImportModule, loader, "ZoneDB")
    local flag = okD and type(QDB) == "table" and QDB.npcFlags and QDB.npcFlags.INNKEEPER
    if not (flag and QDB.NPCPointers and QDB.QueryNPCSingle and okZ and type(ZoneDB) == "table" and ZoneDB.GetUiMapIdByAreaId) then
        Zone.towns, Zone.townsBuilding = spots, false
        return
    end
    local ids = {}
    for id in pairs(QDB.NPCPointers) do ids[#ids + 1] = id end
    local i = 0
    local function Step()
        local ok, err = pcall(function()
            for _ = 1, 400 do
                i = i + 1
                local id = ids[i]
                if not id then return end
                local f = QDB.QueryNPCSingle(id, "npcFlags") or 0
                if bit.band(f, flag) ~= 0 then
                    for areaID, coords in pairs(QDB.QueryNPCSingle(id, "spawns") or {}) do
                        local uiMapID = ZoneDB:GetUiMapIdByAreaId(areaID)
                        local l, r, t, b
                        if uiMapID then l, r, t, b = S.Rect(uiMapID) end
                        if l then
                            for _, c in ipairs(coords) do
                                if c[1] and c[1] >= 0 then Add(l + c[1] / 100 * (r - l), t + c[2] / 100 * (b - t), "inn") end
                            end
                        end
                    end
                end
            end
        end)
        if not ok or i >= #ids then
            Zone.towns, Zone.townsBuilding = spots, false
            if not ok then Zone.townsError = tostring(err) end
            return
        end
        C_Timer.After(0, Step)
    end
    Step()
end

-- The town you're in: its middle (its innkeeper and flight master together), or nil
function Zone.TownHere(wasIn)
    local towns, per = Zone.towns, Zone.WorldPerYard()
    if not (towns and per) then return end
    local u, v = Zone.PlayerWorld()
    if not u then return end
    local reach = (wasIn and Zone.TOWN_OUT or Zone.TOWN_IN) * per
    local near, nearD
    for _, t in ipairs(towns) do
        local d = (t[1] - u) ^ 2 + (t[2] - v) ^ 2
        if not nearD or d < nearD then near, nearD = t, d end
    end
    if not near or nearD > reach * reach then return end
    local same, su, sv, n = Zone.TOWN_SAME * per, 0, 0, 0
    for _, t in ipairs(towns) do
        if (t[1] - near[1]) ^ 2 + (t[2] - near[2]) ^ 2 <= same * same then su, sv, n = su + t[1], sv + t[2], n + 1 end
    end
    return su / n, sv / n
end

function Zone.CheckTown(instant, force, mine)
    if not db.fitTowns or not Zone.OpenMapStitched() then
        Zone.townFor = nil
        return
    end
    -- (where you are hidden for a moment: still in the town you were in, or out of one, till it's back)
    if not Zone.PlayerWorld() then Zone.whereHidden = GetTime() return end
    if not Zone.towns then Zone.BuildTowns() return end
    local tu, tv = Zone.TownHere(Zone.townFor ~= nil)
    if tu then
        local key = string.format("%.4f %.4f", tu, tv)
        if key == Zone.townFor and not force then return end
        Zone.townFor = key
        Zone.townNote = { at = GetTime(), mine = mine and true or false }
        if mine then return end
        local okV, _, _, z = pcall(_G.OpenMapAPI.GetView)
        if not Zone.beforeTown and okV and type(z) == "number" then Zone.beforeTown = z end
        local half = (db.townSize or 400) / 2 * Zone.WorldPerYard()
        local fit = Zone.ZoomForBox(tu - half, tu + half, tv - half, tv + half)
        if fit then Zone.ViewTo(tu, tv, fit, instant) end
    elseif Zone.townFor then
        Zone.townFor = nil
        local before = Zone.beforeTown
        Zone.beforeTown = nil
        if mine then return end
        local zone = Zone.PlayerZone()
        if db.zoneBorder and db.fitLeave and zone and Zone.Available() then
            Zone.Fit(zone, instant)
            return
        end
        local u, v = Zone.PlayerWorld()
        if before and u then Zone.ViewTo(u, v, before, instant) end
    end
end
