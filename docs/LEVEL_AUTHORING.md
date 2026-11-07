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
| `ExitZone` | a ring plus its destination (`TO: THE DEPOT`, or `FINAL EXIT: WINS THE RUN`) |
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

## Doors and keys

A door is the level's way of hiding something. Shut, it blocks movement, bullets **and light**, so
you cannot see into the room behind it and whatever is inside cannot see you. Open the doorway and
the room becomes visible — and so do you.

**The leaf is a real object, open or shut.** Its collider and light occluder are children of the
leaf, so they swing with it: open, the leaf stands in the room and still stops **sight, bullets and
you**, while the *doorway* beside it is clear to walk, shoot and see through. That is what makes an
open door cover — you can stand behind it and be hidden, and so can an enemy.

**Enemies pass an open leaf but cannot see through it.** They walk through the space it occupies,
because the navmesh does not include doors and steering around a leaf the path runs straight through
was making them grind to a halt. If you want a real barrier, shut the door or lock it — an open door
is cover, not a wall.

**Placing one:** turn on **Place door**, click where the doorway should be, and drag along the wall
to set which way the leaf lies; release to place it. A plain click places it horizontally. Tick
**Locked** first to place a door that needs a key. Doors go into a `Doors` container, which the tool
creates if the level does not have one yet — one undo removes the door and the container together.

**Leave a gap for it.** The tool places the door; it does not cut the wall. Draw the wall with a
door-sized opening, then put the door in the opening. The linter reports a door that overlaps a
wall, because that door is sealed and can never be used.

**Re-bake the navmesh after adding or moving a doorway.** Doors are deliberately excluded from the
navmesh, so a doorway should always be connected in the mesh — but a mesh baked *before* the doorway
existed still has solid wall there, and then you can open the door and walk through while enemies
never do. The linter reports this as a problem ("the navmesh has no route through door ..."), so it
cannot be shipped by accident. It is the same fix as any other mesh change: press **Bake navmesh**.

**Doors are not walls.** They are excluded from the navmesh bake on purpose: a doorway has to be
passable in the baked mesh, or enemies could never path through one. So the AI walks up to a shut
door and opens it, and shuts it again after passing — that is deliberate behaviour, not a bug. A
*locked* door is the exception: enemies cannot open it, so they stop and give up on that route.

**Locked doors and keys.** Any key opens any locked door, and opening one consumes a single key.
Keys are a `Pickup` with `kind = key`, and the player can carry as many as they find; the count
survives level changes and is saved with the checkpoint. Put a key somewhere the player has to
work for, and a locked door somewhere that makes them want it.

**Smashing.** The player's dash destroys an unlocked door permanently, with the loudest noise in
the level: the door bursts into splinters and is **removed from the level**, so the doorway is
simply open from then on. Dashing into a *locked* door does not open it: it only rattles, louder
than trying the handle but quieter than a smash. So a locked door can never be bypassed by force —
if you want a door that is a real barrier, lock it.

**Standing in the doorway** and trying to shut it does not close the door: the leaf swings most of
the way, meets you, and comes back open. No message is shown, because the animation is the
explanation. Nothing is consumed and the door's state does not change.

**A moving door never pushes anyone.** If a leaf swings into you (or into an enemy) it passes over
you and you keep your footing; if it comes to rest on top of you, you can walk out. A settled leaf
still blocks like a wall. This matters for enemies too: a guard shoved into a corner by a door it
opened itself cannot get out of it.

## Surfaces: what walls and floors look like

Two dropdowns on the **Level** node, and nothing per wall:

| Property | Meaning |
|---|---|
| `wall_surface_id` | the look of every wall in the level |
| `floor_surface_id` | the look of the floor; `plain` draws no floor at all, which is how levels looked before surfaces |

Each style is a `SurfaceStyle` resource in `src/levels/surfaces/`, and its file name is its id. The
dropdowns are filled from that folder, so a new file shows up in them with nothing to register.
`plain` is built in and has no file.

**Authoring a style** happens in the **Surfaces** dock (part of the level tools plugin):

1. Open a level (or `dev/surface_lab.tscn`), and select the texture in the FileSystem dock.
2. Type a name into the Surfaces dock and press **New wall** or **New floor**. The style is saved,
   opened in the inspector, and put on the open level.
3. Tune it in the inspector. The level in the 2D viewport restyles as you drag each slider, so there
   is no more edit–run–check loop. Turn on the level's `editor_lighting_preview` to judge it in the dark.
4. Save the scene (or press **Save** in the dock) to write the style file.

Clicking a style in the dock edits it; double-clicking (or **Use in level**) applies it to the open
level, undoably. **Duplicate** copies the selected style so you can try a variation and keep the
original. Styles are plain `.tres` files, so renaming or deleting one in the FileSystem dock works too.
A level asking for a style that no longer exists draws it as `plain`.

A wall style can also carry **door art** (`door` on the style): every door in a level with that wall
style shows it. Draw it lying horizontally with the hinge on the left; it is stretched to each door's
size, and 384×128 matches the walls' detail for the standard 96×32 door. A style without door art
keeps plain doors. Locked doors show the same art with a reddish tint and the lock plate.

`dev/surface_lab.tscn` (run it, and use `--probe=surface_lab`
for screenshots) shows one of each shape: a long wall, a medium one, a thin stub, a thick block, a
corner, and a lamp pool on the floor.

**What to expect from the look, because it follows from the lighting model:**

- **Floors are lit.** They take light from lamps and your cone, so a light pool on the ground is the
  main thing that sells the room.
- **Wall tops are *remembered*, not lit.** A wall casts the shadows the vision system depends on, and a
  rectangle's interior is always behind one of its own edges, so a wall can never be lit by the light it
  occludes. Wall tops are therefore drawn unshaded: a wall appears once you have seen it, in its own
  material, and does not get brighter when a lamp is next to it.
- **Tiling is in world space**: one tile is always `tile_world` pixels of the world (64 by default), so a
  96px wall and a 900px wall show the same size grain. Never scale a style per wall to "fit" it.
- The rim, inner shadow and bottom band are computed from each rectangle's own size, so they look right
  on a stub and on a long wall alike.

Authoring advice for the art: keep tiles low-contrast and free of landmarks, and keep them seamless —
repetition is only visible when there is something to recognise. Slight repetition is handled by
blending a much larger sample of the same texture through the `breakup` mask.

## How enemies search

Losing line of sight starts a **search**, and the shape of that search is worth knowing when you
place walls, doors and routes:

- The enemy first walks to the place it last saw you, so it arrives at the door you just shut.
- It then sweeps outward in rings from that point, looking first in the direction you were moving
  when it lost you. It only picks places it can actually walk to.
- **How wide the sweep gets depends on how long you have been gone**: an enemy that lost you eight
  seconds ago searches much further than one that lost you two seconds ago (`search_budget_factor`
  and `search_budget_max` in `Tuning`).
- **Closed doors are opened.** A searcher that reaches a shut door opens it and comes through, so
  shutting a door behind you delays a search rather than ending it.
- **Locked doors are not.** The enemy rattles the handle once, marks that doorway as a dead end for
  this search, and keeps sweeping on its own side. That is the only reliable way to fence a search
  out of somewhere — and it is why a locked door is worth a key.

Press `F3` while playing to see it: each searching enemy draws the area it believes you could be in,
the point it is heading for, and a cross on every place it has already looked.

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
- the open level is not in `CampaignLibrary` (a note, not a problem: its exits then end
  the run, which is how a level being authored behaves)
- an enemy whose `patrol_route` does not resolve, or is not a `PatrolRoute`
- a patrol route with fewer than two waypoints
- any enemy, pickup, exit or spawn point sitting inside a wall
- **content the player cannot actually walk to** (flood fill from the spawn)

The whole campaign is checked too: every path in `CampaignLibrary` has to exist, appear
once, and load as a `Level`. The command below also names any `level_*.tscn` on disk that
is not in the campaign, so a retired level cannot pretend to be part of it.

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
X  exit (the campaign decides where it leads; Z is accepted and means the same)
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

### `Door` — `src/levels/door.tscn`
| Property | Meaning |
|---|---|
| `size` | the closed footprint; the leaf's long axis is local X, so a gap in a north-south wall needs the door rotated 90° |
| `starts_locked` | needs a key, and cannot be smashed |
| `starts_open` | the doorway starts used/open |

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
| `automatic_color` | on by default: a small colour variation worked out from the level and the enemy's name, the same every run. Turn it off to set the colour yourself |
| `hue_shift`, `saturation`, `brightness` | the colour by hand, when `automatic_color` is off |

Only the enemy's **body** is recoloured — never its legs or its weapon, which stay recognisable. The
automatic variation is deliberately small: the enemy types sit close together on the colour wheel
(guard and heavy at about 20°, scout at about 40°), and it never lets a guard drift into a scout. The
editor gizmo is drawn in the colour the enemy will have, level shift included.

### `Pickup` — `src/items/pickup.tscn`
| Property | Meaning |
|---|---|
| `kind` | `weapon`, `ammo`, `upgrade`, `health`, `ability`, `ability_upgrade` or `key` |
| `ability_id` | `fire_wall`, `fire_tempest`, `lightning_bolt` (for `kind = ability`) |
| `ability_level` | upgrade level an ability pickup comes with (0–3; for `kind = ability`) |
| (`key` pickups) | always give exactly one key; there is nothing to configure |
| `weapon_id` | `pistol`, `smg`, `shotgun` (for `kind = weapon`). Picking up a weapon you already carry gives it ammo instead, and leaves the weapon in hand alone; only a weapon picked up for the first time takes the hand |
| `amount` | ammo rounds, or health restored |

Pickup art lives in `assets/pickup/`: `pickup_<kind>.png` (`pickup_ammo.png`, `pickup_health.png`, …),
`pickup_<weapon>.png` for a weapon, and `pickup_upgrade_weapon.png` for a weapon upgrade. Each is
shown at a fixed size along its longest side however large it was drawn (24 world px, 34 for weapons),
so draw them at any size. A kind with no file falls back to a plain shape. The editor shows the art too.

The player has **two ability slots**, always. An ability pickup found with both full is not refused:
standing on it shows a prompt, and pressing a slot's key swaps that slot for it. The ability given up
is left lying where the pickup was, with its upgrades and its cooldown (which keeps running), so a swap
can always be taken back — and a level can offer abilities the player has to choose between.

`kind = upgrade` raises **the weapon in hand**; `kind = ability_upgrade` raises **both ability
slots**. Both stop at level 3, and both are left on the ground when they cannot help, so an
upgrade crate is never spent for nothing. The HUD shows levels as `+` marks next to the name.

### `ExitZone` — `src/levels/exit_zone.tscn`
| Property | Meaning |
|---|---|
| `radius` | how big the trigger is |
| `beacon_range` | how far its landmark light reaches |

Where an exit leads is **not a property**. Exits ask their level, the level asks
`CampaignLibrary` (`src/campaign/campaign_library.gd`), and the campaign is the only
place the chain exists. The last level's exit ends the run. A level that is not in the
campaign behaves as if it were the last one, which is what makes trying a level on its
own safe.

### `Level` — the scene root
| Property | Meaning |
|---|---|
| `level_title`, `objective` | the banner and the line in the top-right |
| `start_weapons` | loadout for a fresh run (weapons carried between levels persist) |
| `auto_bounds`, `bounds_rect`, `bounds_margin`, `min_bound_size` | camera limits |
| `fog_color`, `reveal_color` | the runtime fog, and its `F4` debug reveal |
| `editor_lighting_preview`, `editor_preview_ambient` | the editor-only darkness preview |
| `enemy_hue_shift`, `enemy_saturation`, `enemy_brightness` | recolour every enemy body in the level, for a level with its own look. Every type turns by the same amount, so they stay as far apart as they were drawn. Big changes are fine here |

---

## Putting a level into the campaign

The chain is one list, `CampaignLibrary.LEVELS` in `src/campaign/campaign_library.gd`:

```gdscript
const LEVELS: Array[String] = [
	"res://src/levels/level_campaign_01.tscn",
	"res://src/levels/level_campaign_02.tscn",
	# add the new scene path here, in play order
]
```

Adding a level is that one line plus the scene. Exits need no wiring, and the linter
reports an open level that is not listed.

---

## Checklist for a new level

1. Duplicate `src/levels/level_template.tscn`.
2. Turn on the **wall brush**, select a `Walls` node, and draw the layout. Drag
   along an axis for corridors and walls, diagonally for rooms.
3. Put a `PlayerSpawn` marker where the player starts.
4. Add an `ExitZone`. That is the whole job: where it leads comes from the campaign.
5. Add lamps — they are the player's only landmarks, and they define where enemies
   are visible.
6. Add enemies with the **Place enemy** tool: pick an archetype, click to place it,
   click out its patrol waypoints, then right-click to finish. Rotate one afterwards
   to set the direction it starts facing.
7. Add a medkit and some ammo. The player has no regeneration.
8. Optional: leave a gap in a wall, turn on **Place door** and drag along the wall to fill it.
   For a locked door, tick **Locked** and put a **key** pickup somewhere worth the trip.
9. Set `level_title` and `objective`. `level_title` is what the title screen's Continue button
   shows ("CONTINUE   THE YARD"), so keep it short — a level left on the template's `TEMPLATE`
   will say so on the main menu.
10. Press **Bake navmesh**, and again any time you move walls (the linter says when the
   mesh is stale).
11. Press **Lint level**.
12. Play it. `F3` shows what the AI is thinking, `F4` lifts the fog so you can
	check the layout, `F2` lets you fly through walls.

## Resolution

Nothing in a level needs to know the game's resolution. Walls, markers and patrol routes are
authored in world coordinates, and the camera zooms itself so a constant *height* of world is
visible at every window size (the reasoning is in DESIGN_NOTES). Two consequences are worth
knowing while you lay a level out:

- A **wider** window (ultrawide, or a wide borderless window) shows more world to the
  *sides*, so keep a ring of walls or void around the playable area.
- The camera is clamped to the level's bounds and `Level.min_bound_size` is a *minimum*: the
  real bounds grow to the geometry. A level with a generous margin therefore still behaves
  sensibly at an unusual aspect ratio. A very narrow window sees *less* world, so do not
  rely on the player being able to see something at the far edge of the screen.
