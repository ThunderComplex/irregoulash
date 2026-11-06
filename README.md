# TopDown Shooter

A top-down 2D shooter where **line of sight is the whole game**. You can only see
what your own light reaches, and so can the enemies.

It is in active development towards a finished game, but it is playable end to end
today: **sneak → get noticed → fight → loot → escape to the next level.** Art and
audio are still placeholders, generated in code.

---

## Run it

Godot 4.7 (built and tested against 4.7.2):

```
Godot_v4.7.2-stable_win64_console.exe --path .
```

(Or open the project in the editor — `H:\dev\Godot\Engine\4.7\` — and press `F5`.)

Levels are authored in Godot's own 2D editor — see **`docs/LEVEL_AUTHORING.md`**.
The short version: enable the **Level Tools** plugin's **Wall brush**, drag to draw
walls, drag the markers and pickups around, then press **Lint level** to check for
the mistakes that make a level unplayable.

The game opens on the title screen. Enter or left click starts a run on
**Level 01 — The Yard**; its exit leads to **Level 02 — The Depot**, whose exit
wins the run.

## Controls

| Input | Action |
|---|---|
| `WASD` | Move (always screen-relative — `W` is up, never "toward the mouse") |
| Mouse | Aim; your vision cone follows the cursor |
| Left mouse | Fire |
| `R` | Reload |
| `F` | Open / close a door (locked ones need a key) |
| `Shift` | Dash: fast, loud, and it smashes unlocked doors off their hinges |
| `1` `2` `3` / wheel | Switch weapon |
| Q / E | Use ability 1 / 2 |
| `Esc` | Pause (opens the pause menu) |

All of these can be rebound in Settings → Controls; this table is the default.

### Controller

| Input | Action |
|---|---|
| Left stick | Move |
| Right stick | Aim (last direction is kept when the stick is released) |
| RT | Fire |
| X | Reload |
| Y | Interact |
| B | Dash |
| LB / RB | Ability 1 / 2 |
| D-pad ← / → | Previous / next weapon |
| Start | Pause |
| D-pad + A / B | Menu navigation, confirm / back |

Prompts follow whichever device you last used, and pad buttons are rebindable in the same
Settings → Controls list. The default window list includes 1280×800 for the Steam Deck.

Walk over weapons, ammo and medkits to pick them up.

### Debug keys

| Key | Effect |
|---|---|
| `F1` | God mode |
| `F2` | Noclip |
| `F3` | Debug readout (enemy states, awareness, HP, distances) plus each searching enemy's area, target and searched ground |
| `F4` | Lift the fog (see the whole level) |
| `F5` | Spawn an enemy in front of you |
| `F6` | Alert every enemy |
| `F7` | Give every weapon |
| `F9` | Slow motion (0.25x) |

---

## What is actually implemented

- **Line-of-sight vision.** A near-sight ring plus an aim cone, both casting real
  shadows against level geometry; the rest of the canvas is pitch black, so
  anything outside your light is *invisible* rather than merely dark.
- **Explored-geometry memory.** Walls you have already seen stay faintly visible,
  which is what keeps a pitch-black map navigable. Enemies are never remembered.
- **Searches that look like searches.** Losing an enemy does not make it forget you: it goes to where
  it last saw you, sweeps outward in rings while favouring the direction you were heading, only picks
  places it can actually reach, widens the area the longer you have been gone, opens the doors you
  shut behind you, and rattles the ones it cannot open. `F3` draws all of it.
- **Enemies with layered alertness.** Patrol → Suspicious → Alert → Search →
  Return, driven by an awareness meter rather than a boolean, fed by sight (FOV,
  range, real line of sight), **hearing** (gunshots, footsteps, dashes), and the
  fact that *you are shining your own light on them*. Alert enemies shout for
  nearby friends.
- **Three weapons** (pistol, SMG, shotgun), each with its own feel, ammo, spread
  bloom, reload, knockback and noise radius, plus **weapon upgrades** and pickups
  for weapons/ammo/medkits.
- **Two playable levels** connected by exits, with carried weapons persisting
  between them, plus death/victory/pause screens and run stats.
- **Procedurally synthesised audio** — the project ships with zero audio assets;
  every sound is generated from code at startup.
- **Placeholder geometric art** generated in code, so there are no art assets to
  install and every entity is a clean silhouette.
- **Three abilities** (fire wall, fire tempest, lightning bolt) on their own slots (Q/E),
  each with its own cooldown, upgrade level and pickup. One cast path serves all of them:
  the resource says how it aims, the effect script does the rest, so the fire wall can be
  a solid, shadow-casting barrier while the bolt is just a projectile and neither of them
  needs a branch in the holder.
- **Doors, and keys.** A shut door blocks movement, bullets and light, so it hides a room as well as
  blocking a path; opening one reveals the room *and* you. An open leaf still stops sight, bullets and you, so an
  open door is a clear doorway *and* a slab of cover to hide behind — enemies can walk past it,
  but they cannot see through it. Doors can be opened and
  shut by hand or smashed with a dash, locked ones need a key (any key opens any door, and you can
  carry as many as you find), and enemies open doors in their way and shut them again behind
  themselves. The navmesh deliberately ignores doors, so a doorway is never a dead end to the AI.
- **Menus, and one checkpoint.** The title screen offers New Game, Continue, Level Select, Settings
  and Quit; the pause menu offers Settings, Continue and Quit to Menu. Continue resumes the level you
  were on with what you were carrying, from a single `user://progress.cfg` written on level entry and
  refreshed whenever you pause. It is a level checkpoint, not a save system: no position, no enemy
  state, no items already taken.
- **Level select after finishing.** Reaching the final exit sets a `finished` flag in
  `user://progress.cfg` that survives new games, and unlocks a picker on the title screen. A level
  picked there is a practice run: every weapon fully upgraded and stocked, no abilities, the
  checkpoint untouched, and its exit brings you back to the picker.
- **Surfaces.** Walls and floors take a tiled texture chosen per level from two dropdowns on the `Level`
  node, with the rim, inner shadow and bottom band computed from each rectangle's own
  size. Tiling is in world space, so grain stays the same size on a 96px wall and a 900px one. Floors are
  lit by lamps and your cone; wall tops are unshaded, because a wall cannot be lit by the light it casts
  shadows for (see `docs/DESIGN_NOTES.md`). Styles are `.tres` files in `src/levels/surfaces/`, made and tuned live
  from the editor's Surfaces dock; `dev/surface_lab.tscn` is the scratch scene for judging a look.
- **Any resolution and aspect ratio**, with a settings menu (window mode, resolution,
  vsync, master and effects volume) persisted to `user://settings.cfg`. The game renders
  natively rather than stretching a fixed canvas, so text stays crisp at 4K, and the camera
  zooms itself so the same amount of world is visible at every size -- the vision cone
  covers the same share of the screen whether the window is 800x600 or 2560x1440.
- **In-editor authoring tools** (`addons/level_tools/`): a wall brush (drag to draw
  walls, with undo), an enemy tool (pick an archetype, click to place, click again to
  lay out its patrol route, right-click to finish — one route per enemy), a one-click
  **Bake navmesh** that generates enemy path finding from the walls, editor gizmos for
  everything (enemies with facing wedges and vision cones, patrol routes with direction
  arrows, labelled pickups and exits, camera bounds, the spawn point's vision reach), an
  opt-in lighting preview, and a level linter. See `docs/LEVEL_AUTHORING.md`.

## Not built yet

A talent tree, a real inventory, consumables, procgen levels, mid-level saving,
shops, boss fights, and real art/audio assets. Controller support and keybind
remapping are *in* scope for release and are queued in `docs/TASKS.md`, alongside
the rest of the work that is planned but not built. `docs/OPEN_QUESTIONS.md` lists
the design questions that are still open; `docs/DESIGN_NOTES.md` records how the
existing systems were built and why.

---

## Project layout

```
project.godot            autoloads, physics layer names, display settings
addons/level_tools/      editor plugin: wall brush + level linter
src/autoload/            Tuning, GameInput, AudioDirector, FxDirector, GameDirector
src/common/              Layers, Shapes, Health, VisionTextures
src/player/              player.gd/.tscn, vision_rig.gd
src/weapons/             weapon_resource/slot/library, weapon_holder, projectile
src/abilities/           ability_resource/slot/library/holder, casting, effects, damage_field
src/campaign/            campaign_library.gd (the level chain, in order)
src/items/               pickup.gd/.tscn (weapons, ammo, upgrades, medkits, keys, abilities)
src/enemies/             enemy.gd/.tscn, enemy_archetype, enemy_library
src/levels/              level.gd (level base), wall, door, lamp, exit_zone, patrol_route,
                         vision_memory, level_lint, navmesh_baker
src/ui/                  hud, menu_list, title_screen, settings_menu
dev/                     probe.gd, build_levels.gd, check_scene_hygiene.gd (dev tools)
docs/                    LEVEL_AUTHORING.md, DESIGN_NOTES.md, OPEN_QUESTIONS.md, TASKS.md
```

### Two things worth knowing before reading the code

1. **All balance lives in `src/autoload/tuning.gd`** and in the two "library"
   files (`weapon_library.gd`, `enemy_library.gd`). Nothing hard-codes a
   gameplay number. `Tuning` is an autoload, so you can also tweak it live while
   playing via the editor's *Remote* scene tree.
2. **A level cannot be broken by omission.** `Level` builds the fog, the memory
   system, the effect layer, the HUD, the player and the camera limits itself, so
   a level scene only contains content. See `docs/LEVEL_AUTHORING.md`.

---

## Verifying changes without a human at the keyboard

`dev/probe.gd` runs scripted scenarios, prints numeric diagnostics and saves
screenshots to `dev/shots/`. It is attached automatically when `--probe=` is
passed, and does nothing otherwise.

```
# whole-level layout check (zooms out and lifts the fog)
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 \
    res://src/levels/level_01.tscn -- --probe=map

# walk, shoot, kill, report
... res://src/levels/level_01.tscn -- --probe=combat

# fire/shadow casting with sampled pixel colours
... res://dev/vision_test.tscn -- --probe=vision

# level chaining and the win screen
... res://src/levels/level_01.tscn -- --probe=flow

# stand in the open and get killed
... res://src/levels/level_02.tscn -- --probe=death

# title screen, debug readout
... res://src/ui/title_screen.tscn -- --probe=title
... res://src/levels/level_02.tscn -- --probe=debug
```

Levels are generated from ASCII maps by a dev tool that also lints what it
builds (unreachable pickups, entities inside walls, missing exits):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://dev/build_levels.gd
```

Lint every level — the same checks the editor's "Lint level" button runs, from a
terminal, exiting non-zero if anything is wrong:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . \
    res://src/ui/title_screen.tscn -- --probe=lint
```

Check level-file hygiene (that saving a level cannot bake generated colliders into
it, and that editor-only helper nodes cannot be serialised into it):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://dev/check_scene_hygiene.gd
```

After adding or removing `class_name` scripts, refresh the editor's class cache
before running the game headlessly:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```

---

## Known limitations

- **Enemies see in the dark; you do not.** This is intentional (they are the
  authority on their own senses, and lamps plus wall memory are your
  counterweight), but it does mean an unaware enemy can spot you before you can
  see them. Tuning it is one number: `Tuning.enemy_sight_range`.
- **Enemy navigation is baked per level.** Enemies path with a navigation mesh
  generated from the walls by the plugin's **Bake navmesh** button; a level without one
  falls back to direct steering, which is worse around corners. Re-bake after moving
  walls — the linter reports when the mesh no longer matches the level.
- **Levels are hand-laid-out ASCII, and the layouts are first drafts.** They are
  completable and linted, not tuned. Expect to want to move cover around.
- **The HUD is built in code**, not as a scene, so it cannot be nudged around in
  the editor. That was a deliberate trade while the layout was still changing.
- **No save/load.** Settings (window, resolution, vsync, volumes) persist in
  `user://settings.cfg`. Gameplay actions are rebindable in the settings menu, and the choices
  persist in `user://bindings.cfg`; `GameInput.DEFAULT_SPECS` is the shipped default, so an
  unrebound action keeps tracking that table. Gamepad bindings live in the same file and the same
  table.
- Quitting a level prints `2 ObjectDB instances were leaked at exit` (an
  `AudioStreamWAV` and its playback). It is a shutdown-ordering artefact in Godot's
  audio mixer, not a gameplay leak — `AudioDirector._exit_tree()` stops every pooled
  player and drops the bank — but it does make real leaks harder to spot in logs.
- **The linter's reachability check is approximate**: it rasterises onto a 32px grid,
  so a gap narrower than that reads as sealed even if the player could squeeze
  through.
