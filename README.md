# Quick Map

*(Instrucciones en español más abajo.)*

Shows the map of your zone with a key, in **WoW: Forever**, without the borders, buttons and quest log around it. Hold the key for a quick look, or press it to leave the map open. Its size, shape, opacity and place on screen are yours to choose.

It uses the game's own map, so everything on it shows too: quests, vendors, flight points, your arrow, and other addons' markers like Questie's.

## What it does

- **Hold or press**: the map shows while you hold the key, or one press shows it and the next hides it.
- **Size and width**: make the map bigger or smaller, and narrower (more square) or wider.
- **Two opacities**: one for the map itself and one for the markers on it, so the map can fade into the background while quests and vendors stay clear. Hovering a marker shows its name, as on the normal map.
- **Keep opacity while moving**: the game fades its map while you move; Quick Map keeps the opacity you chose (or fades to half, if you prefer).
- **Follow me**: keeps the map centred on you while it's open, like the minimap.
- **Hide the minimap** while the map is open (SexyMap's minimap too).
- **Also hide** other parts of the interface while the map is open: action bars, player and target frames, chat, quest tracker, buffs, menu and bags, experience bar. Each one is its own option.
- **Move it** anywhere on screen.
- **Options button** in the corner of the map, which opens a small panel to change all of this while you look at the map. It can show always, only with the mouse over the map, or never, at the opacity you choose.

When the map closes, everything goes back exactly as it was: the normal map (M) is not changed at all.

## Installation

1. Put the `QuickMap` folder inside `World of Warcraft\_forever_\Interface\AddOns\` (the game folder's name may vary; it must be the WoW: Forever installation).
2. It must end up like this: `...\Interface\AddOns\QuickMap\QuickMap.toc`. Make sure there is no extra folder in between, like `QuickMap\QuickMap\`.
3. In the game, choose a key in **Options > Keybindings > Quick Map > Show the map**.

## Options and commands

All the options are in **Options > AddOns > Quick Map**. Most of them are also in the small panel that the arrow button on the map opens. In that panel, size and width change when you press **Apply Size & Width**.

| Command | What it does |
|---|---|
| `/qmap` | Opens the options |
| `/qmap move` | Shows a box the size of the map: drag it, right-click it when done |
| `/qmap reset` | Puts the map back in the middle of the screen |
| `/qmap debug` | Shows what the map looks like from the inside (useful when reporting a problem) |

`/quickmap` works too.

## Other addons

- **OpenMap**: works with it. OpenMap keeps the map window where it saved it, so Quick Map moves only the map inside it. Leave OpenMap's own "fade while moving" at 0 and use Quick Map's instead, or the two will fight while you walk. With OpenMap, changing the width shows more or less of the world at the sides instead of zooming.
- **Questie**: its markers show on the map and take the objectives' opacity.
- **SexyMap**: its minimap (with its clock, zone name and buttons) is hidden with the rest.

## Good to know

- Opening the map works like the game's own map: your character does the map-reading animation, and an open window like the character panel closes.
- Inside dungeons and raids the game hides your position, so **Follow me** doesn't move the map there.
- In combat the game doesn't let addons hide action bars or unit frames, so those are made invisible instead.
- Without OpenMap, **Follow me** only moves the map when it's zoomed in (mouse wheel): zoomed all the way out, the whole zone already fits.

## If the addon stops loading

After a WoW: Forever update, the addon may stop loading. At character select, open the AddOns list and find Quick Map:

- **"Out of date"**: check **Load out of date AddOns** at the top of the list. That's all.
- **"Incompatible"**: in the game, type `/dump select(4, GetBuildInfo())` in chat. It prints a number, for example 16001. Open `QuickMap.toc` with Notepad, replace the number in the first line (`## Interface: 16001`) with that one, save, and restart the game. Never put an invented number there: the game marks it Incompatible and it won't load at all.

## License

MIT. See `LICENSE`.

---

# Quick Map (español)

Muestra el mapa de tu zona con una tecla, en **WoW: Forever**, sin los bordes, botones ni el registro de misiones a su alrededor. Mantén la tecla para echar un vistazo rápido, o presiónala para dejar el mapa abierto. El tamaño, la forma, la opacidad y su lugar en pantalla los eliges tú.

Usa el mapa del propio juego, así que todo lo que hay en él también se ve: misiones, vendedores, puntos de vuelo, tu flecha y los indicadores de otros addons, como los de Questie.

## Qué hace

- **Mantener o presionar**: el mapa se ve mientras mantienes la tecla, o una pulsación lo abre y la siguiente lo cierra.
- **Tamaño y ancho**: el mapa más grande o más chico, y más angosto (más cuadrado) o más ancho.
- **Dos opacidades**: una para el mapa y otra para los indicadores, así el mapa puede quedar de fondo mientras las misiones y vendedores se ven claros. Al pasar el mouse sobre un indicador se ve su nombre, como en el mapa normal.
- **Mantener la opacidad al moverse**: el juego desvanece su mapa mientras caminas; Quick Map mantiene la opacidad que elegiste (o la baja a la mitad, si lo prefieres).
- **Seguirme**: mantiene el mapa centrado en ti mientras está abierto, como el minimapa.
- **Ocultar el minimapa** mientras el mapa está abierto (también el de SexyMap).
- **Ocultar también** otras partes de la interfaz mientras el mapa está abierto: barras de acción, marcos del jugador y del objetivo, chat, seguimiento de misiones, beneficios, menú y bolsas, barra de experiencia. Cada una es una opción aparte.
- **Moverlo** a cualquier parte de la pantalla.
- **Botón de opciones** en la esquina del mapa, que abre un panel pequeño para cambiar todo esto mientras miras el mapa. Puede verse siempre, solo con el mouse sobre el mapa, o nunca, con la opacidad que elijas.

Al cerrar el mapa todo vuelve a quedar exactamente como estaba: el mapa normal (M) no cambia en nada.

## Instalación

1. Pon la carpeta `QuickMap` dentro de `World of Warcraft\_forever_\Interface\AddOns\` (el nombre de la carpeta del juego puede variar; tiene que ser la instalación de WoW: Forever).
2. Tiene que quedar así: `...\Interface\AddOns\QuickMap\QuickMap.toc`. Revisa que no quede una carpeta de más en medio, como `QuickMap\QuickMap\`.
3. En el juego, elige una tecla en **Opciones > Keybindings > Quick Map > Show the map**.

## Opciones y comandos

Todas las opciones están en **Opciones > AddOns > Quick Map**. La mayoría también están en el panel pequeño que abre el botón con la flecha en el mapa. En ese panel, el tamaño y el ancho cambian al presionar **Apply Size & Width**.

| Comando | Qué hace |
|---|---|
| `/qmap` | Abre las opciones |
| `/qmap move` | Muestra un recuadro del tamaño del mapa: arrástralo y haz clic derecho al terminar |
| `/qmap reset` | Devuelve el mapa al centro de la pantalla |
| `/qmap debug` | Muestra cómo está el mapa por dentro (útil para reportar un problema) |

`/quickmap` también funciona.

## Otros addons

- **OpenMap**: funciona con él. OpenMap mantiene la ventana del mapa donde la guardó, así que Quick Map mueve solo el mapa que está dentro. Deja el "desvanecer al moverse" de OpenMap en 0 y usa el de Quick Map, o los dos pelearán mientras caminas. Con OpenMap, cambiar el ancho muestra más o menos mundo a los lados en vez de hacer zoom.
- **Questie**: sus indicadores se ven en el mapa y usan la opacidad de los objetivos.
- **SexyMap**: su minimapa (con su reloj, nombre de zona y botones) se oculta junto con lo demás.

## Bueno saber

- Abrir el mapa funciona como el mapa del juego: tu personaje hace la animación de leer el mapa, y si tienes abierta una ventana como la del personaje, se cierra.
- Dentro de dungeons y raids el juego oculta tu posición, así que ahí **Seguirme** no mueve el mapa.
- En combate el juego no deja que los addons oculten las barras de acción ni los marcos de unidad, así que esos se vuelven invisibles en vez de ocultarse.
- Sin OpenMap, **Seguirme** solo mueve el mapa cuando tiene zoom (rueda del mouse): alejado al máximo, la zona entera ya cabe.

## Si el addon deja de cargar

Después de una actualización de WoW: Forever, el addon podría dejar de cargar. En la selección de personaje, abre la lista de AddOns y busca Quick Map:

- **"Out of date"**: marca **Load out of date AddOns** arriba de la lista. Con eso basta.
- **"Incompatible"**: en el juego, escribe `/dump select(4, GetBuildInfo())` en el chat. Te mostrará un número, por ejemplo 16001. Abre `QuickMap.toc` con el Bloc de notas, reemplaza el número de la primera línea (`## Interface: 16001`) por ese, guarda y reinicia el juego. Nunca pongas un número inventado: el juego lo marca como Incompatible y no cargará.

## Licencia

MIT. Ver `LICENSE`.
