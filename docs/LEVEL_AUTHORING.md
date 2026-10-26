# Level authoring

Two rules, straight from `AGENTS.md`:

1. **Making a level must be easy.**
2. **It must not be possible to break a level by forgetting a node.**

Both are handled by `src/levels/level.gd`. A level scene contains *only* content —
walls, lamps, enemies, pickups, exits and marker points:

| Thing | If it is missing from the level scene |
|---|---|
| Black fog (`CanvasModulate`) | created at runtime by `Level` |
| Explored-geometry memory | created at runtime by `Level` |
| Effect layer (bullets, blood, sparks) | created at runtime by `Level` |
| HUD | created at runtime by `Level` |
| Player | always spawned by `Level`, at the `PlayerSpawn` marker |
| Camera limits | derived from the walls |
| Spawn marker | falls back to the origin, with a warning |
| Exit | warns loudly at load, does not crash |

So a new level is: **walls + a spawn marker + an exit.**

> **Never put a `CanvasModulate` (the fog) in a level scene.** Godot's 2D editor
> renders the scene you are editing *through* it, so a black fog node turns the
> editing viewport black and makes the level unauthorable. `Level` creates the fog
> at runtime. To see how a level reads in the dark, turn on `editor_lighting_preview`
> (below) or run it and press `F4`.

---

## Drawing walls: the wall brush

Levels are authored in Godot's own 2D editor, using the **Level Tools** plugin
(`addons/level_tools/`, enabled in Project Settings). In the 2D editor's toolbar
you get two buttons:

- **Wall brush** (toggle)
- **Lint level** (button)

With the brush on, left-drag in the viewport:

| Gesture | Result |
|---|---|
| Drag along an axis | a wall band, 64px thick, along that axis |
| Drag diagonally | a rectangle (rooms, blocks, big open-plan shapes) |
| Click without dragging | a 64px block |
| Hold `Ctrl` | force a square |
| Hold `Alt` | ignore grid snapping (32px) |
| Right-click or `Esc` while dragging | cancel |

While the brush is on it takes over left-clicks in the viewport, so **turn it off to
select, move or resize nodes** with the mouse (you can always select from the Scene
dock).

**The brush stays ready.** It pins itself to a container — the `Node2D` you had
selected, otherwise the node called `Walls` — and keeps that container selected after
every wall, so you can draw wall after wall without touching the Scene dock. To send
walls somewhere else, select a different `Node2D` in the Scene dock (never a `Wall`
itself: the brush deliberately refuses to nest walls inside level content).

The wall appears as you drag it: the brush creates a real (but unsaved) `Wall` and
moves it with your drag, so what you see while dragging *is* the geometry you will
get. Release to keep it, right-click or `Esc` to cancel, `Ctrl+Z` to undo.

> Note for anyone touching the brush code: the 2D editor delivers canvas input
> events in **editor window** coordinates, and the 2D viewport does *not* sit at the
> window's origin — the docks and toolbar offset it right and down. Converting a raw
> event position therefore places the wall down-and-right of the mouse by exactly
> that offset. The brush asks `Viewport.get_mouse_position()` instead, which is in the
> viewport's own coordinates — the space `get_canvas_transform()` expects — and it
> prints what the cursor resolved to once, on the first drag.
>
> There used to be an on-canvas preview rectangle drawn through the editor's overlay
> API as well. The overlay draws in *window* space, so it reintroduced exactly this
> offset bug (twice, in opposite directions). It is gone; the in-scene wall is the
> preview.

Walls are created through the editor's undo history (**Ctrl+Z** works), and they
land in:

1. the currently selected `Node2D` — so **select the `Walls` node first** if you
   want them grouped,
2. otherwise a node named `Walls`,
3. otherwise the scene root.

A drawn wall is an ordinary `Wall` node afterwards: select it and change `size` or
`color` in the inspector, drag it around, copy/paste it, whatever you like.

### Why walls are one property

`Wall` is authored as **one** property, `size`. From it the script generates the
collider, the light occluder, the visual and the explored-geometry memory copy.
Because the occluder is generated, a level cannot be "almost right" — there is no
way to place a wall that blocks movement but not light, or to forget the occluder
entirely.

---

## What you can see while editing

The second half of authoring well is being able to *read* a level without running
it. Everything below is drawn in the editor by `@tool` code:

| What | What it draws |
|---|---|
| `Enemy` | body, a **facing wedge** (this is exactly the direction its vision cone follows), a faint outline of that cone, its archetype name, and either `wanders here` or a warning if its `patrol_route` is broken |
| `PatrolRoute` | the path as a dashed line, **arrows for direction of travel**, numbered waypoints, and a link line from every enemy that patrols it |
| `Pickup` | a symbol coloured by kind plus a label (`SMG`, `AMMO 40`, `MEDKIT 35`, `WEAPON UPGRADE`) |
| `ExitZone` | a ring plus its destination (`TO: LEVEL_02`, or `FINAL EXIT: WINS THE RUN`) |
| `Lamp` | the fixture, its radius, and (thanks to a `GradientTexture2D` baked into `lamp.tscn`) a real light with real shadows |
| `Level` | the **camera bounds** (how far the camera may follow), the spawn point, **the player's vision reach and cone** at the spawn, and a warning if there is no `ExitZone` |

### Lighting preview

`Level` has an **Editor → Editor Lighting Preview** toggle. Turn it on and the
editing viewport is dimmed to `editor_preview_ambient` (default 0.34) so lamp
pools, wall shadows and dark corners read while you are laying things out — you
can author the lighting, not just the geometry.

It is off by default, because Godot's 2D editor already renders lights and
shadows: with no fog in the scene you see everything at full material colour and
the lamps on top of that. The preview node is added as an *unowned* child, and
Godot does not serialise children that are not owned by the scene root, so it can
never end up saved into a level file. (That rule is tested by
`dev/check_scene_hygiene.gd`.)

---

## Placing enemies and their routes

The **Place enemy** tool does the whole job in one gesture, with the archetype chosen
in the dropdown beside it:

1. Pick `Guard`, `Scout` or `Heavy` from the dropdown.
2. Switch **Place enemy** on and left-click in the viewport to place it there.
3. Keep left-clicking to add patrol waypoints. Each enemy gets **its own**
   `PatrolRoute`, created on the first waypoint and named after the enemy
   (`Guard3Route`), so two enemies never accidentally share a route.
4. Right-click (or `Esc`) to finish. **Finishing switches the tool off** — press the
   button again for the next enemy. That way the next stray click in the viewport
   selects a node instead of placing an enemy.

Alt while clicking places without grid snapping (`32px` otherwise).

| Waypoints placed | What the enemy does |
|---|---|
| none | wanders around where it stands (`wander_radius`) |
| one | stands on the spot and scans — a guard post |
| two or more | patrols them, in the order you clicked |

Undo walks back through what you built in order — one waypoint at a time, then the
route, then the enemy — so `Ctrl+Z` unwinds a mistake without throwing away the whole
enemy. The enemy and its route are committed to the scene as you go, so you can also
just select the enemy afterwards and rotate it to set the direction it starts facing.

The wall brush and the enemy tool both want the left mouse button, so switching one on
switches the other off.

---

## Patrol routes

`PatrolRoute` is a `Node2D` whose `Marker2D` children are the waypoints, in tree
order. The **Place enemy** tool creates one per enemy for you; this is how to build or
edit one by hand.

1. Add a `PatrolRoute` (e.g. under a `Routes` node).
2. Add `Marker2D` children and drag them where you want the patrol to go — the path,
   arrows and numbered points update as you drag. One marker makes a guard post, and
   two or more make a patrol.
3. On each enemy, set **`patrol_route`** to that node (drag the node from the Scene
   dock into the property, or use the node picker).

The route draws a link line from every enemy that uses it, and an enemy with a route
that does not resolve says so on itself. An enemy with no route uses `wander_radius`
instead.

Routes live in the level rather than under the enemy on purpose: they must not move
when the enemy does. They *can* be shared, but the tool gives every enemy its own, so
that editing one patrol never surprises another enemy.

---

## Enemy navigation: the "Bake navmesh" button

Enemies path around geometry with Godot's navigation server, and the mesh is generated
from your walls with one click:

**Bake navmesh** in the toolbar. It creates and positions the navigation polygon itself
(`Nav` node, `NavigationPolygon`) — you never draw navigation polygons by hand. The
walls are read from the `wall` group that every `Wall` puts itself in, and the baker
subtracts them from one outline around the level, so the walkable area falls out of the
geometry.

- **Re-bake after moving walls.** The bake stores a fingerprint of the wall layout on
  the `Nav` node, and **Lint level** reports when the mesh no longer matches the level.
  A stale mesh is worse than none: enemies will path through where a wall used to be.
- **Without a navmesh, nothing breaks.** Enemies fall back to steering with obstacle
  probes — they come around corners less reliably, but the level stays playable. That
  fallback is also what keeps the dev test scenes (which have no `Nav`) working.
- Paths are baked with an agent radius of 18px (a little wider than the player and the
  enemies), so they keep clearance from walls instead of hugging them.
- The baked mesh is a normal `NavigationRegion2D`, so **Godot draws it in the editor**
  (select `Nav` to see the walkable area highlighted over your floor) — the quickest way
  to see whether a corridor is wide enough for the enemies you placed.

Verify that it works for real with the probe, which bakes at runtime and then raycasts
every path the mesh hands out against the geometry:

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 \
	res://src/levels/level_01.tscn -- --probe=navmesh
```

It reports the polygon count, how many enemies picked the mesh up, and how many of the
sampled paths cross a wall (which should be zero).

## Linting a level

**Lint level** in the toolbar (or the command below) reports the mistakes that
make a level unplayable:

- no `PlayerSpawn` marker (`Level` falls back to the origin and warns)
- no `ExitZone`
- an exit that is neither final nor has a `next_level`
- an enemy whose `patrol_route` does not resolve, or is not a `PatrolRoute`
- a patrol route with fewer than two waypoints
- any enemy, pickup, exit or spawn point sitting inside a wall
- **content the player cannot actually walk to** (flood fill from the spawn)

When it finds a reachability problem it also prints a small map — `#` wall, `.`
walkable, ` ` sealed off — because that is the fastest way to see which room is
cut off.

From a terminal (works headlessly, exits non-zero if anything is wrong, so it can
be a pre-commit hook):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . \
	res://src/ui/title_screen.tscn -- --probe=lint
```

It is approximate: reachability is rasterised onto a 32px grid, so a gap narrower
than about 32px reads as sealed even though the player (a 28px circle) might
technically squeeze through.

---

## The ASCII builder (optional, for roughing out a layout)

`dev/build_levels.gd` turns a text map into a real, editable scene:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://dev/build_levels.gd
```

It is a *sketching* tool, not the workflow — it is grid-locked to 64px and cannot
express what the editor can. It is handy for blocking out a layout quickly, and it
writes ordinary `.tscn` files that you then open and finish by hand. It also lints
what it builds: uneven rows, entities inside walls, unreachable entities, and a
missing exit or spawn.

Legend:

```
#  wall                      .  / space  floor
P  player spawn              1 2 3      patrol route marker (routes 1..3)
G  guard, patrols route 1    g  guard, wanders near spawn
S  scout, patrols route 1    s  scout, wanders
H  heavy, patrols route 1    h  heavy, wanders
L  lamp
-  pistol pickup   =  smg pickup   +  shotgun pickup
A  ammo pickup     %  medkit       U  weapon upgrade crate
X  exit to the next level     Z  final exit (wins the run)
```

Every uppercase enemy is wired to route 1; assigning one to route 2 or 3 is a
one-field edit in the editor afterwards.

---

## Property reference

### `Wall` — `src/levels/wall.tscn`
| Property | Meaning |
|---|---|
| `size` | the whole story: collider, occluder, visual and memory are generated from it |
| `color` | wall colour (seen lit, or at ~30% as "memory") |
| `occludes_light` | turn off for railings or glass |

### `Lamp` — `src/levels/lamp.tscn`
| Property | Meaning |
|---|---|
| `radius`, `energy`, `color` | the light |
| `shadows` | light respects walls (recommended) |
| `beacon` | keep the fixture itself visible when unlit |
| `flicker`, `flicker_amount` | candle-style variation |
| `require_line_of_sight` | a lamp you can neither see nor stand inside stops lighting the world for you, so sealed rooms stay dark (the fixture's own dot stays visible as a landmark) |
| `visibility_fade` | how quickly it fades in and out, so lamps never pop |

### `Enemy` — `src/enemies/enemy.tscn`
| Property | Meaning |
|---|---|
| `archetype_id` | `guard`, `scout` or `heavy` |
| `patrol_route` | path to a `PatrolRoute`; empty means wander instead. The Place enemy tool fills this in |
| `wander_radius` | how far it roams around its spawn point |
| `patrol_dwell` | seconds spent standing at each waypoint |
| `returns_to_post` | false for a guard that should hold a position |
| `rotation` | its starting facing — rotate it in the editor to choose which way it watches |

### `Pickup` — `src/items/pickup.tscn`
| Property | Meaning |
|---|---|
| `kind` | `weapon`, `ammo`, `upgrade`, `health` or `ability` |
| `ability_id` | `fire_wall`, `fire_tempest`, `lightning_bolt` (for `kind = ability`) |
| `weapon_id` | `pistol`, `smg`, `shotgun` (for `kind = weapon`) |
| `amount` | ammo rounds, or health restored |

### `ExitZone` — `src/levels/exit_zone.tscn`
| Property | Meaning |
|---|---|
| `next_level` | scene to load when the player walks in. Leave empty to use the **level's** `next_level` instead, so several exits can share one target |
| `is_final` | wins the run instead |
| `radius` | how big the trigger is |

### `Level` — the scene root
| Property | Meaning |
|---|---|
| `level_title`, `objective` | the banner and the line in the top-right |
| `next_level` | what its non-final exits lead to |
| `start_weapons` | loadout for a fresh run (weapons carried between levels persist) |
| `auto_bounds`, `bounds_rect`, `bounds_margin`, `min_bound_size` | camera limits |
| `fog_color`, `reveal_color` | the runtime fog, and its `F4` debug reveal |
| `editor_lighting_preview`, `editor_preview_ambient` | the editor-only darkness preview |

---

## Checklist for a new level

1. Duplicate `src/levels/level_template.tscn`.
2. Turn on the **wall brush**, select a `Walls` node, and draw the layout. Drag
   along an axis for corridors and walls, diagonally for rooms.
3. Put a `PlayerSpawn` marker where the player starts.
4. Add an `ExitZone`. Set its own `next_level`, or set `next_level` once on the
   level root and let every non-final exit fall back to it. Leave `is_final` off
   unless it is the last level.
5. Add lamps — they are the player's only landmarks, and they define where enemies
   are visible.
6. Add enemies with the **Place enemy** tool: pick an archetype, click to place it,
   click out its patrol waypoints, then right-click to finish. Rotate one afterwards
   to set the direction it starts facing.
7. Add a medkit and some ammo. The player has no regeneration.
8. Set `level_title` and `objective`.
9. Press **Bake navmesh**, and again any time you move walls (the linter says when the
   mesh is stale).
10. Press **Lint level**.
11. Play it. `F3` shows what the AI is thinking, `F4` lifts the fog so you can
	check the layout, `F2` lets you fly through walls.
