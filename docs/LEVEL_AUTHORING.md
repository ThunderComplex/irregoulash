# Level authoring

Two rules, straight from `AGENTS.md`:

1. **Making a level must be easy.**
2. **It must not be possible to break a level by forgetting a node.**

Both are handled by `src/levels/level.gd`. A level scene contains *only*
content — walls, lamps, enemies, pickups, exits and marker points. Everything the
game needs in order to function is created by the base script if it is missing:

| Thing | If it is missing from the level scene |
|---|---|
| Black fog (`CanvasModulate`) | created by `Level` |
| Explored-geometry memory | created by `Level` |
| Effect layer (bullets, blood, sparks) | created by `Level` |
| HUD | created by `Level` |
| Player | always spawned by `Level`, at the `PlayerSpawn` marker |
| Camera limits | derived from the walls |
| Spawn marker | falls back to the origin, with a warning |
| Exit | warns loudly at load, does not crash |

So a new level is: **walls + a spawn marker + an exit.** Everything else is
optional.

---

## Fastest way: the ASCII builder

`dev/build_levels.gd` turns a text map into a real, editable scene. Edit the maps
at the top of that file, run:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://dev/build_levels.gd
```

and it writes `src/levels/level_XX.tscn`. Open that scene in the editor and tweak
it by hand afterwards if you like — from that point on it is an ordinary scene.

### Legend

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

One cell is 64 px. Corridors should be at least 2 cells wide, doorways at least
2 cells — the player is a 28 px circle and enemies are up to 34 px.

### The builder lints what it builds

- reports rows whose lengths disagree (it pads them and seals the border, so a
  typo becomes extra floor rather than a hole in the map)
- reports any entity inside a wall
- flood-fills from the spawn and reports **anything the player cannot reach** —
  an unreachable exit or pickup is a hard failure, it will be printed
- reports a missing exit or spawn

A level that lints clean is guaranteed completable.

### Routes

Route markers `1`/`2`/`3` become `Routes/RouteN` nodes with `Marker2D` children.
Every *uppercase* enemy is wired to route 1. Assigning an enemy to route 2 or 3
is a one-field edit afterwards (`patrol_route` on the enemy, e.g.
`NodePath("../../Routes/Route2")`).

---

## Authoring by hand

Start from `src/levels/level_template.tscn`, or just make a new 2D scene and drop
the pieces in from the FileSystem dock.

### `Wall` — `src/levels/wall.tscn`

The single authoring primitive for solid geometry. You set **one** property:
`size`. The script generates the collider, the light occluder, the visual and the
explored-geometry memory copy from it, and updates them live in the editor. The
occluder is what makes walls block light, and because it is generated you cannot
forget it.

- `color` — wall colour (it is only ever seen lit, or at ~30% as "memory")
- `occludes_light` — turn off for railings or glass

### `Lamp` — `src/levels/lamp.tscn`

A static level light. Lamps are your main level-design lever:

- they create **lit pockets**, where enemies are visible to you even outside your
  cone (and where you are easier for them to notice),
- they are **blocked by walls**, so they never leak through geometry,
- the fixture itself is drawn unshaded, so distant lamps read as faint gold
  beacons in the dark and give the player something to navigate by.

`radius`, `energy`, `color`, `shadows`, `flicker`.

### `Enemy` — `src/enemies/enemy.tscn`

- `archetype_id` — `guard`, `scout` or `heavy`
- `patrol_route` — a `NodePath` to a container whose `Marker2D` children are the
  route (routes live in the level, not under the enemy, so they stay put)
- `wander_radius` — used when there is no route
- `returns_to_post` — set false for a guard who should hold a position
- `rotation` — the starting facing; rotate the enemy in the editor to choose
  which way it is looking when the level starts

No route and no wander radius means the enemy stands still and sweeps its view,
which is a perfectly good "guard at a door" setup.

### `Pickup` — `src/items/pickup.tscn`

- `kind` — `weapon`, `ammo`, `upgrade` or `health`
- `weapon_id` — `pistol`, `smg`, `shotgun` (only for `kind = weapon`)
- `amount` — ammo rounds or health restored

Pickups light themselves, so they are findable in the dark. That is not optional
polish: **a pickup the player cannot see does not exist.**

### `ExitZone` — `src/levels/exit_zone.tscn`

- `next_level` — a `PackedScene` to load when the player walks in
- `is_final` — wins the run instead

Exits carry a beacon light and an unshaded marker ("ESCAPE" / "WAY OUT"), and
they poll for overlapping bodies as well as listening to `body_entered`, so an
exit still works if the player is teleported or respawned into it.

### `Level` — the scene root

```
level_title       shown as a banner on entry
objective         the line in the top-right of the HUD
next_level        the scene its (non-final) exits lead to
start_weapons     weapons the player starts with, if they are not carrying any
auto_bounds       derive camera limits from the walls (leave on)
bounds_rect       manual camera limits, used when auto_bounds is off
bounds_margin     how far past the walls the camera may travel
min_bound_size    stops the camera clamping awkwardly in small levels
fog_color         black by default; anything else stops seeing being the point
reveal_color      ambient used by the F4 debug reveal
```

Weapons **persist between levels** (`GameDirector.carried_loadout`), so
`start_weapons` is only used on a fresh run or if a level is launched directly.

---

## Checklist for a new level

1. Copy `level_template.tscn` (or add an ASCII map to `dev/build_levels.gd`).
2. Lay out walls. Keep sightlines interesting: long corridors are dangerous,
   corners are where the mechanic shines.
3. Add a `PlayerSpawn` marker.
4. Add at least one `ExitZone`, set `next_level`, and set `next_level` on the
   Level root too.
5. Add lamps so there is something to navigate by.
6. Add enemies: mix archetypes, give some a route and some a post.
7. Add 1–2 medkits and ammo — the player has no regeneration.
8. Set `level_title` and `objective`.
9. Run the game. Turn on `F4` to check the layout and `F3` to watch the AI.
