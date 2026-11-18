# Changelog

## 1.1.1 (2026-11-18)

### New

- **Also hide: Character Names**: the names above players', NPCs' and pets' heads are hidden while the map is open, and come back as they were when it closes. (The game doesn't allow changing them in combat: then it waits for combat to end.)

### Fixed

- The soft edges shape did nothing with Soft Edges off. Now a diamond or an oval cuts the map sharp in that shape.
- Without OpenMap, the map could open in a corner of the screen the first time (with the options button out of reach), and away from the game's usual map window it was cut off, and seemed to move when resized. The map is now placed from the middle of the screen, and its invisible window covers the whole screen while Overlay Map shows it, so the map can be anywhere.
- Without OpenMap, zooming all the way out left empty margins around the map, which looked broken with soft edges or Torn Parchment (more so with Follow me). While Overlay Map shows the map, the furthest zoom is now the one where the map fills its area.
- A part of the interface hidden by Overlay Map blinked when another addon tried to show it, like UI Visibility's "On hover" on the quest tracker. It's now kept invisible the moment that happens.

## 1.1.0 (2026-11-18)

### Renamed

- **Quick Map is now Overlay Map.** It installs as a new addon: remove the old `QuickMap` folder and choose your key again in **Options > Keybindings > Overlay Map**. To keep your settings, rename `QuickMap.lua` to `OverlayMap.lua` in your `WTF\Account\(your account)\SavedVariables\` folder (with the game closed). The README explains it step by step.
- The commands are now `/omap` and `/overlaymap`.

### New

- **Soft edges**: the map and its markers fade out towards the edges, like the overlay maps of other games. Off, small, medium, large or very large.
- **Soft edges shape**: rectangle with rounded corners, diamond or oval.
- **Map style: Torn Parchment**: torn, burnt paper edges, like an old map. The burnt rim is drawn over the map and under the markers, and fades with the map. With this style, the soft edges options are greyed out.
- **Overlay mode**: one switch that makes the map big, centred, see-through and click-through, with solid markers and large soft edges. Turning it off puts back what you had.
- **Markers only**: the map's opacity now goes down to 0%, leaving only the markers floating over the world.
- **Remember zoom**: the map opens at the zoom it had when you last closed it, apart from the normal map's. With OpenMap it uses OpenMap's own API, and OpenMap's reopen option still decides where the view is centred.
- **Click through**: clicks go through the map to the world, so you can keep clicking and turning your character with the right button over it. Markers still show their names when hovered, but can't be clicked (a click on one goes to the world too). Hold Shift to use the map normally.
- **Options button**: a second opacity for when the mouse is on the button or close to it, and a size option. Its opacity over the map can now go down to 0%, so it only shows when you get close to it. The button's options are now only in the main options, so the small panel is shorter.
- **Size** now goes up to 250%.
- `/omap debug` shows more: the mouse setup of the map and its markers, what is under the mouse, and how each hidden part of the interface was hidden.

### Changed

- **Hiding other parts of the interface**: they're now hidden completely instead of only made invisible, so nothing can be clicked by mistake. The parts the game protects (action bars, unit frames) can't be hidden by an addon, so they're made invisible and covered by an invisible shield that takes the clicks meant for them. Keybinds still work.
- **Follow me** holds still while the mouse is over the map, so you can look at the markers while you move. It catches up with you when the mouse leaves.

### Fixed

- Hovered markers blinked: the markers' layers were laid out again five times a second even when nothing had changed.
- Markers' tooltips didn't show after closing and reopening the map with click through on, until the map had settled.
- Clicking a marker with click through on left it stuck, showing nothing.
- A Lua error every few frames with click through on ("attempt to call a nil value").
- Action bars and the other hidden parts could still be clicked: the code that hides them ended up repeated in the file, and the oldest copy, which only made them invisible, was the one running.
- The soft edges were laid out again every second.

## 1.0.0 (2026-11-17)

- First version, as Quick Map.
