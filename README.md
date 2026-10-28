# Minecart Lift

Minetest-Mod zur vertikalen Beförderung von Loren.

Entwickelt von marghl und OpenAI Codex.

## Abhängigkeiten

- `minecart`

## Enthaltene Schienen

- `minecart_lift:lift_bottom` – Elevator Bottom
- `minecart_lift:lift_top` – Elevator Top
- `minecart_lift:rope` – automatisch erzeugtes, kletterbares Seil
- `minecart_lift:rope_knot` – unterstes Seilsegment mit Knoten

`Elevator Top` benötigt zwei freie Blöcke direkt unter sich. Die Seilwinde
ist als große industrielle Stahl-Seilbox unter einer Deckenplatte gestaltet.
Sie erzeugt zwei Blöcke tiefer eine als Seil dargestellte funktionale Schiene, senkt ein
kletterbares Seil bis zum nächsten festen Boden ab und setzt dort automatisch
`Elevator Bottom`. Das unterste Seilsegment trägt einen sichtbaren Knoten.
Schienen können horizontal an die funktionale obere Schiene angeschlossen
werden. Beide Enden speichern den bidirektionalen Pfad dauerhaft in ihren
Node-Metadaten, entsprechend der Wegpunkt-Infrastruktur von `minecart`.
Der Abstand ist auf 256 Blöcke begrenzt. Mit
`minecart.get_lift_path(pos)` kann das jeweils andere Schienenende abgefragt
werden. Digiline und Mesecon sind noch nicht implementiert.

Vor dem Aufbau lädt der Mod die vollständige Schachtspalte. Status-, Erfolgs-
und Fehlermeldungen werden im Mehrspielermodus ausschließlich dem Spieler
angezeigt, der `Elevator Top` platziert hat.

Beim Klettern verwenden alle Seilsegmente die CC0-lizenzierten Knarrgeräusche
aus dem Ropes-Mod.

## Crafting

`Elevator Top` wird aus sieben Stahlbarren, einem Kupferbarren und einer
normalen Schiene hergestellt:

```text
Steel Ingot | Steel Ingot  | Steel Ingot
Steel Ingot | Copper Ingot | Steel Ingot
Steel Ingot | Rail         | Steel Ingot
```

`Elevator Bottom` und das Seil werden automatisch erzeugt und erscheinen
nicht im Crafting Guide oder im Kreativinventar.

## Protection

Alle Lift-Bauteile sind bei `minecart` als geschützte Nodes registriert und
werden daher durch `minecart:landmark` geschützt. Ein Lift kann außerdem nicht
durch den acht Nodes weit reichenden Schutzbereich eines fremden Meilensteins
gebaut werden. Eigene Meilensteine und das `minecart`-Privileg erlauben den
Zugriff entsprechend der ursprünglichen Minecart-Regeln.

## Chest Cart

The Chest Cart combines Minecart routing with the fixed 32-slot inventory of a
standard Minetest Game chest. Its cargo is serialized with the moving entity and
Minecart monitoring; it is never represented by loose item entities during
normal cart conversion or elevator travel. A standing Chest Cart can be loaded
and unloaded by the Minecart Hopper.

The recipe places one `default:chest` above one `minecart:cart`.

When `technic_chests` is installed, the Minecart Hopper can transfer items to
and from every Technic chest variant. Locked chests require the hopper and
chest to have the same owner. Protected chests allow direct automated transfer,
while their placement, manual access, and removal remain area-protected.

The wooden `protector:chest` is supported separately through Minecart's direct
inventory connection. Protector continues to control placement, manual access,
and removal while the installed hopper may transfer items automatically.

## Configuration

Moving minecarts travel vertically between connected lift rails at 3 nodes per
second by default. The speed can be changed in `minetest.conf`:

At the destination, a cart continues only if a rail is connected in its
direction of travel. Otherwise it stops at the lift station.

Minecart entities are integrated with the `minecart` monitoring data. Vertical
checkpoints are included while recording routes, the current lift position is
persisted, and an interrupted trip is restored after a server restart. During
travel, only the current and destination mapblocks are transiently forceloaded.

```text
minecart_lift_speed = 3
```

## Installation

1. Den Ordner `minecart_lift` in das lokale Verzeichnis `mods` kopieren.
2. Den Mod für die gewünschte Welt aktivieren.
3. Minetest starten.

Der Mod lädt eine öffentliche Lua-Tabelle namens `minecart_lift`.

## Lizenz

Der Quellcode steht unter der MIT-Lizenz. Siehe `LICENSE.txt`.

Die aktive Stahlwinden-Textur ist ein eigenes Projekt-Asset. Die verwendete
Seilgrafik und eine ungenutzte Quellgrafik aus dem Ropes-Mod haben eine
ungeklärte Lizenz; die offene Lizenzfrage wird im Ropes-Projekt in Issue #25
verfolgt. Die Chest-Cart-Grafiken verwenden Material aus Minetest Game und
stehen entsprechend unter CC BY-SA 3.0. Cart-Quellgrafiken und Seilgeräusche
stehen unter CC0. Vollständige Quellen-, Urheber- und Lizenzangaben stehen in
`THIRD_PARTY_ASSETS.md`.
