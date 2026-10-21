# TopDown Shooter — WIP vertical slice

A top-down 2D shooter where **line of sight is the whole game**. You can only see
what your own light reaches, and so can the enemies. This build is a small,
playable slice built to answer one question: *is this actually fun, and is it
worth extending into a full game?*

It is not a finished game. It is the smallest thing that contains the whole loop
end to end: **sneak → get noticed → fight → loot → escape to the next level.**

---

## Run it

Godot 4.7 (built and tested against 4.7.2):

```
Godot_v4.7.2-stable_win64_console.exe --path .
```

The game opens on the title screen. Enter or left click starts a run on
**Level 01 — The Yard**; its exit leads to **Level 02 — The Depot**, whose exit
wins the run.

## Controls

| Input | Action |
|---|---|
| `WASD` / arrows | Move (always screen-relative — `W` is up, never "toward the mouse") |
| Mouse | Aim; your vision cone follows the cursor |
| Left mouse | Fire |
| `R` | Reload |
| `Shift` / `Space` | Dash (fast, and loud enough to be heard) |
| `1` `2` `3` / wheel | Switch weapon |
| `Esc` | Pause |

Walk over weapons, ammo and medkits to pick them up.

### Debug keys

| Key | Effect |
|---|---|
| `F1` | God mode |
| `F2` | Noclip |
| `F3` | Debug readout (enemy states, awareness, HP, distances) |
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

## What is deliberately *not* in this WIP

ARPG abilities and a talent tree, a real inventory, consumables, procgen levels,
saving, shops, boss fights, controller support, an options menu, real audio
assets, and enemy navigation meshes. See `docs/DESIGN_NOTES.md` for how each of
those was kept possible.

---

## Project layout

```
project.godot            autoloads, physics layer names, display settings
src/autoload/            Tuning, GameInput, AudioDirector, FxDirector, GameDirector
src/common/              Layers, Shapes, Health, VisionTextures
src/player/              player.gd/.tscn, vision_rig.gd
src/weapons/             weapon_resource/slot/library, weapon_holder, projectile
src/items/               pickup.gd/.tscn (weapons, ammo, upgrades, medkits)
src/enemies/             enemy.gd/.tscn, enemy_archetype, enemy_library
src/levels/              level.gd (level base), wall, lamp, exit_zone, vision_memory
src/ui/                  hud, title_screen
dev/                     probe.gd + build_levels.gd (dev tools, not shipped)
docs/                    WIP_TASKS.md, LEVEL_AUTHORING.md, DESIGN_NOTES.md
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
- **Enemies use steering with whisker raycasts, not a navigation mesh.** They
  navigate rooms and doorways fine and will come around corners, but they can
  wedge themselves on awkward geometry. A `NavigationRegion2D` bake is the
  obvious upgrade.
- **Levels are hand-laid-out ASCII, and the layouts are first drafts.** They are
  completable and linted, not tuned. Expect to want to move cover around.
- **The HUD is built in code**, not as a scene, so it cannot be nudged around in
  the editor. That was a deliberate trade while the layout was still changing.
- **No save/load, no options, no gamepad.**
