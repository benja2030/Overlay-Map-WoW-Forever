# Overlay Map

*(Instrucciones en español más abajo.)*

Shows the map of your zone with a key, in **WoW: Forever**, without the borders, buttons and quest log around it. Hold the key for a quick look, or press it to leave the map open. Its size, shape, opacity and place on screen are yours to choose.

It uses the game's own map, so everything on it shows too: quests, vendors, flight points, your arrow, and other addons' markers like Questie's.

## What it does

- **Hold to show or toggle**: the map shows while you hold the key, or one press shows it and the next hides it.
- **Size and width**: make the map bigger or smaller, and narrower (more square) or wider.
- **Two opacities**: one for the map itself and one for the markers on it, so the map can fade into the background while quests and vendors stay clear. Hovering a marker shows its name, as on the normal map.
- **Full-screen overlay**: one switch that makes the map fill the whole screen, see-through and click-through, with solid markers and large soft edges. The options panel then opens inside the map. It keeps its own look (opacities, marker size, style, fade at the edges, shape, click through the map), apart from the normal map's: change it while it's on, and the next time it's the same.
- **Click through the map**: the mouse goes through the map to the world, so you can still click and turn your character with the right button over it. Markers still show their names; hold Shift to drag and zoom the map. Full-screen overlay turns it on.
- **Custom arrow size**: your arrow can have its own size and opacity, apart from the other markers.
- **Markers only**: set the map's opacity to 0% and only the markers float over the world.
- **Open at last zoom**: opens at the zoom it had when you last closed it, apart from the normal map's.
- **Show only my arrow**: hides every marker except your own arrow.
- **Marker size**: bigger or smaller markers, from 50% to 250%.
- **Fade at the edges**: the map fades out towards its edges, like the overlay maps of other games, in the shape of a rounded rectangle, a diamond or an oval (off, small, medium, large or very large).
- **Apply borders to zones**: your zone stands out with its own outline (with OpenMap, the zone you're in), and the rest of the map fades behind it or hides. It goes on top of the map's shape and style, Torn parchment included. **Auto-zoom to zone** fits the map to each new zone, and **Center on me** keeps the view inside your zone. Inside caves (with OpenMap), the cave's own shape. Needs the separate **Overlay Map: Zone Borders** download.
- **Torn parchment style**: torn, burnt paper edges, like an old map, instead of the fade at the edges.
- **Don't fade while moving**: the game fades its map while you move; Overlay Map keeps the opacity you chose (or fades to half, if you prefer).
- **Center on me**: keeps the map centred on you while it's open, like the minimap.
- **Hide the minimap** while the map is open (SexyMap's minimap too).
- **Also hide** other parts of the interface while the map is open: action bars, player and target frames, chat, quest tracker, buffs, menu and bags, experience bar, and the names above characters' heads. Each one is its own option.
- **Move it** anywhere on screen.
- **Panel button** in the corner of the map you choose, which opens a small panel to change all of this while you look at the map. It can show always, only with the mouse over the map, or never, at the opacity you choose.

When the map closes, everything goes back exactly as it was: the normal map (M) is not changed at all.

## Installation

1. Put the `OverlayMap` folder inside `World of Warcraft\_forever_\Interface\AddOns\` (the game folder's name may vary; it must be the WoW: Forever installation).
2. It must end up like this: `...\Interface\AddOns\OverlayMap\OverlayMap.toc`. Make sure there is no extra folder in between, like `OverlayMap\OverlayMap\`.
3. In the game, choose a key in **Options > Keybindings > Overlay Map > Show the map**.

## Coming from Quick Map

Overlay Map was called Quick Map before. It's installed as a new addon, so:

1. Remove the old `QuickMap` folder from `Interface\AddOns\`.
2. Choose your key again in **Options > Keybindings > Overlay Map**.
3. To keep your settings: with the game closed, go to `World of Warcraft\_forever_\WTF\Account\(your account)\SavedVariables\` and rename `QuickMap.lua` to `OverlayMap.lua`. Overlay Map takes them over the next time you log in.

The commands are now `/omap` and `/overlaymap`.

## Options and commands

All the options are in **Options > AddOns > Overlay Map**, on tabs, with a search box that finds any option. At the top: the setup wizard, **Open on the Map** (the map with its small panel, to see your changes as you make them), the map key and **Reset Everything**; each tab has its own reset button. Most options are also in the small panel that the arrow button on the map opens, on four tabs (Map, Look, Zone, Behavior); hover an option to see what it does. Size and width change when you let go of their slider.

| Command | What it does |
|---|---|
| `/omap` | Opens the options |
| `/omap move` | Shows a box the size of the map: drag it, right-click it when done |
| `/omap reset` | Puts the map back in the middle of the screen |
| `/omap setup` | Opens the setup wizard: the map key and the main options, step by step |
| `/omap names` | Puts the names above heads back, if they were left off |
| `/omap debug` | Shows what the map looks like from the inside (useful when reporting a problem) |

`/overlaymap` works too.

## Other addons

- **OpenMap**: works with it. OpenMap keeps the map window where it saved it, so Overlay Map moves only the map inside it. Leave OpenMap's own "fade while moving" at 0 and use Overlay Map's instead, or the two will fight while you walk. With OpenMap, changing the width shows more or less of the world at the sides instead of zooming.
- **Questie**: its markers show on the map and take the markers' opacity.
- **Choosing which addons show**: the Addons tab has a switch for Questie, TomTom and RXPGuides, OpenMap's map, OpenMap's icons and Dungeon Journal's dungeon maps. One turned off is kept off Overlay Map's map while it's open, so the map opens faster; the normal map keeps it. Opened in a fight, the map shows every addon.
- **SexyMap**: its minimap (with its clock, zone name and buttons) is hidden with the rest.
- **Mirror Bars**: its copies of the action bars are hidden along with the action bars.

## Good to know

- Opening the map works like the game's own map: your character does the map-reading animation, and an open window like the character panel closes.
- Inside dungeons and raids the game hides your position, so **Follow me** doesn't move the map there.
- In combat the game doesn't let addons hide action bars or unit frames, so those are made invisible instead.
- In combat the game doesn't let addons open the map (only its own M key can), so the key can't open it during a fight. If the map is already open when the fight starts, closing it makes it invisible until the fight ends, and the key shows it again meanwhile.
- Without OpenMap, **Follow me** only moves the map when it's zoomed in (mouse wheel): zoomed all the way out, the whole zone already fits.

## If the addon stops loading

After a WoW: Forever update, the addon may stop loading. At character select, open the AddOns list and find Overlay Map:

- **"Out of date"**: check **Load out of date AddOns** at the top of the list. That's all.
- **"Incompatible"**: in the game, type `/dump select(4, GetBuildInfo())` in chat. It prints a number, for example 16001. Open `OverlayMap.toc` with Notepad, replace the number in the first line (`## Interface: 16001`) with that one, save, and restart the game. Never put an invented number there: the game marks it Incompatible and it won't load at all.

## License

MIT. See `LICENSE`. The zone outlines are a separate download, **Overlay Map: Zone Borders** (the `OverlayMap_ZoneBorders` folder), with their credits and licences.

---

# Overlay Map (español)

Muestra el mapa de tu zona con una tecla, en **WoW: Forever**, sin los bordes, botones ni el registro de misiones a su alrededor. Mantén la tecla para echar un vistazo rápido, o presiónala para dejar el mapa abierto. El tamaño, la forma, la opacidad y su lugar en pantalla los eliges tú.

Usa el mapa del propio juego, así que todo lo que hay en él también se ve: misiones, vendedores, puntos de vuelo, tu flecha y los indicadores de otros addons, como los de Questie.

## Qué hace

- **Mantener o presionar**: el mapa se ve mientras mantienes la tecla, o una pulsación lo abre y la siguiente lo cierra.
- **Tamaño y ancho**: el mapa más grande o más chico, y más angosto (más cuadrado) o más ancho.
- **Dos opacidades**: una para el mapa y otra para los indicadores, así el mapa puede quedar de fondo mientras las misiones y vendedores se ven claros. Al pasar el mouse sobre un indicador se ve su nombre, como en el mapa normal.
- **Modo superpuesto**: un interruptor que hace que el mapa llene toda la pantalla, transparente y con clic a través, con los indicadores sólidos y bordes suaves grandes. El panel de opciones se abre entonces dentro del mapa. Guarda su propio aspecto (opacidades, tamaño de los indicadores, estilo, bordes suaves, forma, clic a través), aparte del mapa normal: lo que cambies mientras está activo se mantiene para la próxima vez. Al apagarlo vuelve lo que tenías.
- **Clic a través**: el mouse atraviesa el mapa hacia el mundo, así puedes seguir haciendo clic y girar a tu personaje con el botón derecho sobre él. Los indicadores siguen mostrando sus nombres; mantén Shift para arrastrar el mapa y hacer zoom. El modo superpuesto lo activa.
- **Mi flecha**: tu flecha puede tener su propio tamaño y opacidad, aparte de los demás indicadores.
- **Solo indicadores**: con la opacidad del mapa en 0%, solo los indicadores flotan sobre el mundo.
- **Recordar el zoom**: abre con el zoom que tenía la última vez que lo cerraste, aparte del mapa normal.
- **Solo mi flecha**: oculta todos los indicadores menos tu propia flecha.
- **Tamaño de los indicadores**: más grandes o más pequeños, de 50% a 250%.
- **Bordes suaves**: el mapa se desvanece hacia sus bordes, como los mapas superpuestos de otros juegos, con forma de rectángulo redondeado, rombo u óvalo (apagado, pequeño, mediano, grande o muy grande).
- **Borde de la zona**: tu zona destaca con su propia forma (con OpenMap, la zona en que estás), y el resto del mapa se atenúa detrás o se oculta. Va encima de la forma y el estilo del mapa, Pergamino rasgado incluido. El mapa puede acercarse para que quepa cada zona nueva, y Seguirme mantiene la vista dentro de tu zona. Necesita la descarga aparte **Overlay Map: Zone Borders**.
- **Estilo pergamino rasgado (Torn Parchment)**: bordes de papel rasgado y quemado, como un mapa antiguo, en vez de los bordes suaves.
- **Mantener la opacidad al moverse**: el juego desvanece su mapa mientras caminas; Overlay Map mantiene la opacidad que elegiste (o la baja a la mitad, si lo prefieres).
- **Seguirme**: mantiene el mapa centrado en ti mientras está abierto, como el minimapa.
- **Ocultar el minimapa** mientras el mapa está abierto (también el de SexyMap).
- **Ocultar también** otras partes de la interfaz mientras el mapa está abierto: barras de acción, marcos del jugador y del objetivo, chat, seguimiento de misiones, beneficios, menú y bolsas, barra de experiencia, y los nombres sobre las cabezas de los personajes. Cada una es una opción aparte.
- **Moverlo** a cualquier parte de la pantalla.
- **Botón de opciones** en la esquina del mapa que elijas, que abre un panel pequeño para cambiar todo esto mientras miras el mapa. Puede verse siempre, solo con el mouse sobre el mapa, o nunca, con la opacidad que elijas.

Al cerrar el mapa todo vuelve a quedar exactamente como estaba: el mapa normal (M) no cambia en nada.

## Instalación

1. Pon la carpeta `OverlayMap` dentro de `World of Warcraft\_forever_\Interface\AddOns\` (el nombre de la carpeta del juego puede variar; tiene que ser la instalación de WoW: Forever).
2. Tiene que quedar así: `...\Interface\AddOns\OverlayMap\OverlayMap.toc`. Revisa que no quede una carpeta de más en medio, como `OverlayMap\OverlayMap\`.
3. En el juego, elige una tecla en **Opciones > Keybindings > Overlay Map > Show the map**.

## Si usabas Quick Map

Overlay Map antes se llamaba Quick Map. Se instala como un addon nuevo, así que:

1. Borra la carpeta antigua `QuickMap` de `Interface\AddOns\`.
2. Vuelve a elegir tu tecla en **Opciones > Keybindings > Overlay Map**.
3. Para conservar tu configuración: con el juego cerrado, ve a `World of Warcraft\_forever_\WTF\Account\(tu cuenta)\SavedVariables\` y cambia el nombre de `QuickMap.lua` a `OverlayMap.lua`. Overlay Map la toma la próxima vez que entres.

Los comandos ahora son `/omap` y `/overlaymap`.

## Opciones y comandos

Todas las opciones están en **Opciones > AddOns > Overlay Map**, en pestañas, con un buscador que encuentra cualquier opción. Arriba: el asistente de configuración, **Open on the Map** (el mapa con su panel pequeño, para ver tus cambios mientras los haces), la tecla del mapa y **Reset Everything**; cada pestaña tiene su propio botón para volver a los valores por defecto. La mayoría de las opciones también están en el panel pequeño que abre el botón con la flecha en el mapa, en cuatro pestañas (Map, Look, Zone, Behavior); pasa el mouse sobre una opción para ver qué hace. El tamaño y el ancho cambian al soltar su barra.

| Comando | Qué hace |
|---|---|
| `/omap` | Abre las opciones |
| `/omap move` | Muestra un recuadro del tamaño del mapa: arrástralo y haz clic derecho al terminar |
| `/omap reset` | Devuelve el mapa al centro de la pantalla |
| `/omap setup` | Abre el asistente de configuración: la tecla del mapa y las opciones principales, paso a paso |
| `/omap names` | Devuelve los nombres sobre las cabezas, si quedaron ocultos |
| `/omap debug` | Muestra cómo está el mapa por dentro (útil para reportar un problema) |

`/overlaymap` también funciona.

## Otros addons

- **OpenMap**: funciona con él. OpenMap mantiene la ventana del mapa donde la guardó, así que Overlay Map mueve solo el mapa que está dentro. Deja el "desvanecer al moverse" de OpenMap en 0 y usa el de Overlay Map, o los dos pelearán mientras caminas. Con OpenMap, cambiar el ancho muestra más o menos mundo a los lados en vez de hacer zoom.
- **Questie**: sus indicadores se ven en el mapa y usan la opacidad de los objetivos.
- **Elegir qué addons se ven**: la pestaña Addons tiene un interruptor para Questie, TomTom y RXPGuides, el mapa de OpenMap, los íconos de OpenMap y los mapas de mazmorra de Dungeon Journal. Uno apagado no aparece en el mapa de Overlay Map mientras está abierto, así que el mapa abre más rápido; el mapa normal lo mantiene. Abierto en un combate, el mapa muestra todos los addons.
- **SexyMap**: su minimapa (con su reloj, nombre de zona y botones) se oculta junto con lo demás.
- **Mirror Bars**: sus copias de las barras de acción se ocultan junto con las barras de acción.

## Bueno saber

- Abrir el mapa funciona como el mapa del juego: tu personaje hace la animación de leer el mapa, y si tienes abierta una ventana como la del personaje, se cierra.
- Dentro de dungeons y raids el juego oculta tu posición, así que ahí **Seguirme** no mueve el mapa.
- En combate el juego no deja que los addons oculten las barras de acción ni los marcos de unidad, así que esos se vuelven invisibles en vez de ocultarse.
- En combate el juego no deja que los addons abran el mapa (solo su propia tecla M puede), así que la tecla no lo abre durante una pelea. Si el mapa ya estaba abierto cuando empieza la pelea, cerrarlo lo deja invisible hasta que termine, y la tecla lo vuelve a mostrar mientras tanto.
- Sin OpenMap, **Seguirme** solo mueve el mapa cuando tiene zoom (rueda del mouse): alejado al máximo, la zona entera ya cabe.

## Si el addon deja de cargar

Después de una actualización de WoW: Forever, el addon podría dejar de cargar. En la selección de personaje, abre la lista de AddOns y busca Overlay Map:

- **"Out of date"**: marca **Load out of date AddOns** arriba de la lista. Con eso basta.
- **"Incompatible"**: en el juego, escribe `/dump select(4, GetBuildInfo())` en el chat. Te mostrará un número, por ejemplo 16001. Abre `OverlayMap.toc` con el Bloc de notas, reemplaza el número de la primera línea (`## Interface: 16001`) por ese, guarda y reinicia el juego. Nunca pongas un número inventado: el juego lo marca como Incompatible y no cargará.

## Licencia

MIT. Ver `LICENSE`. Las formas de las zonas son una descarga aparte, **Overlay Map: Zone Borders** (la carpeta `OverlayMap_ZoneBorders`), con sus créditos y licencias.
