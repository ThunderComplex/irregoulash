# Character art

Characters are drawn as two top-down layers, straight down from above:

| Layer | Turns to | Contents |
|---|---|---|
| **Legs** | where the character is walking | a walk cycle |
| **Torso** | where the character is aiming | head, shoulders, arms and the weapon |

The game rotates each layer, so every layer is drawn **once, facing one way**. Code in
`src/characters/character_rig.gd` does the rest: it plays the walk cycle in step with movement, turns the
legs round and plays the cycle backwards when you back away from where you aim, and sways the torso a
little with each step.

## The checklist

1. **Face right.** Everything points along +X, to the right of the canvas. Up the screen is the
   character's left.
2. **Draw at 4× world size.** A character with a 14 px collision radius is 28 world px across, so it is
   about 112 px across on the canvas. Smooth art downscaled this way stays clean when rotated.
3. **Hips at the pivot.** Both layers turn about the hips: the centre of the collision circle. By default
   that is the **middle of the canvas** (or of each frame); if you crop a canvas off-centre, tell the
   look file where the hips are (`legs_pivot`, `torso_pivot`, in canvas pixels from the top-left).
4. **Legs: one horizontal strip, equal frames.** 8 frames is a good default (any number works, set
   `legs_frames`). Frame 0 doubles as **standing still**, so draw it with the feet together under the
   hips. The cycle loops, so the last frame should lead back into the first.
5. **Torso: one image.** Head, shoulders, arms and weapon together. Optionally one per weapon (see below).
6. **Facing must read at a glance**, especially on enemies: the torso's direction is the player's only
   cue for where an enemy is looking. A weapon held forward does this well.
7. **Leave the rest transparent.** No baked shadow under the feet for now; the lighting does the work.

### Sizes

The collision radius is the character's footprint. Shoulders can spill a little past it; the weapon can
reach well past it.

| Character | Radius (world px) | Across, at 4× | Suggested canvas |
|---|---|---|---|
| Player | 14 | ~112 px | legs 128×128 per frame, torso 192×192 |
| Guard | 13 | ~104 px | legs 128×128, torso 192×192 |
| Scout | 11 | ~88 px | legs 96×96, torso 160×160 |
| Heavy | 17 | ~136 px | legs 160×160, torso 224×224 |

The torso canvas is larger only so the weapon fits in front with the hips still in the middle. A tighter
canvas is fine with `torso_pivot` set.

## Getting it into the game

1. Export PNGs into `assets/characters/` (or anywhere under `assets/`).
2. In Godot's **Import** dock, tick **Mipmaps → Generate** for each, and **Reimport**. The art is shown at a
   quarter of its size, and without mipmaps it shimmers as characters move.
3. Create a **CharacterLook** resource (FileSystem dock → right-click → New Resource → CharacterLook) and
   save it in `assets/characters/`, named after who wears it:

   | File | Used by |
   |---|---|
   | `player.tres` | the player |
   | `guard.tres`, `scout.tres`, `heavy.tres` | that enemy archetype |
   | `enemy.tres` | every enemy without a file of its own |

   Nothing needs registering: the next run picks it up. A character with no file keeps its placeholder,
   so art can arrive one character at a time.
4. Fill in the look in the inspector: `legs_sheet` and `legs_frames`, `torso`, and anything below that
   differs from the defaults.

### Look settings

| Setting | What it does |
|---|---|
| `stride` | World px walked per full cycle. The cycle is driven by distance, not time, so feet don't slide at any speed. Feet look like they **skate**: raise it. Feet **shuffle**: lower it. |
| `torso_by_weapon` | A torso per weapon id (`pistol`, `smg`, `shotgun`). Weapons without one use `torso`. |
| `sway` | How far the torso rocks side to side per step, in world px. 0 turns it off. |
| `art_scale` | Canvas size over world size. 0.25 for 4×; change it only if you draw at a different scale. |
| `backpedal_degrees` | How far apart aim and movement must be before the legs walk backwards. |

## Checking it

`dev/probe.gd` has a scenario that photographs the player up close (standing, walking towards the aim,
backing away, strafing) and an enemy:

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 res://dev/surface_lab.tscn -- --probe=character_rig
```

The screenshots land in `dev/shots/rig_*.png`. The placeholder art follows every rule above, so it doubles
as an example: it is generated in `CharacterLook.placeholder()`.
