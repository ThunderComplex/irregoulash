# Character art

Characters are seen from straight above and drawn in three parts. Each part is drawn **once, facing
right**; the game rotates and moves it.

| Part | Faces | Drawn | Moved by |
|---|---|---|---|
| **Body** | the aim | head, shoulders and arms, one image | turns with the aim, sways a little per step |
| **Leg** | the walking direction | one leg, used for both | stretched forward and back from the hip in code |
| **Weapon** | the aim | one image per weapon, shared by everyone | held in the body's hands |

There is no animation to draw. From above, a swinging leg looks like it stretches forward from the hip
(or backward, behind it), so `src/characters/character_rig.gd` draws the stride by stretching and flipping
the one leg image, driven by distance walked so the feet never slide. When you back away from where you
aim, the legs turn round and walk backwards instead of twisting under the body.

## The checklist

1. **256×256 canvas, facing right.** Up the canvas is the character's left.
2. **Drawn at 5× world size.** `art_scale` is 0.2: a 256 px canvas covers 51 world px. The player's
   collision circle is 28 world px across, about 140 px on the canvas.
3. **Body: hips in the middle of the canvas.** The body turns about that point. Off-centre is fine if
   you set `body_pivot`.
4. **Body: arms end at the hands.** Set `hands` to that point (canvas pixels from the top-left); the
   weapon's grip goes there.
5. **Leg: hip end on the left, toe on the right.** By default the hip is the middle of the leg's left
   end, which suits a rounded hip like the player's. Set `leg_hip` otherwise.
6. **Weapons: muzzle on the right, centred vertically.** Saved as `assets/weapons/weapon_<id>.png`
   (`weapon_pistol.png`, `weapon_smg.png`, `weapon_shotgun.png`). The hands hold a weapon 30% of the way
   along it from the back, and shots leave from its right-most tip. Nothing else needs setting.
7. **Facing must read at a glance**, especially on enemies: the body's direction is the player's only cue
   for where an enemy is looking. A weapon held forward does this well.
8. **Transparent everywhere else.** The edges of the drawing are measured from its transparency (the
   weapon's grip and muzzle, the leg's hip), so stray faint pixels move them.

## Getting it into the game

1. Save PNGs in `assets/characters/` and `assets/weapons/`.
2. In Godot's **Import** dock, tick **Mipmaps → Generate** and **Reimport**. The art is shown at a fifth of
   its size and shimmers without mipmaps. (The current art already has this set.)
3. A **CharacterLook** resource ties a body and leg together. Save it in `assets/characters/`, named
   after who wears it:

   | File | Used by |
   |---|---|
   | `player.tres` | the player |
   | `guard.tres`, `scout.tres`, `heavy.tres` | that enemy archetype |
   | `enemy.tres` | every enemy without a file of its own |

   Nothing needs registering: the next run picks it up. A character with no file keeps its placeholder.
   Weapons need no look file at all: an enemy holds the weapon it drops, the player the one selected.

### Look settings

| Setting | What it does |
|---|---|
| `hands` | Where the weapon's grip goes, in body pixels. (-1, -1): no weapon shown. |
| `weapon_scale` | Resizes held weapons relative to the body, without redrawing them. |
| `sway` | How far the body rocks side to side per step, in world px. 0 turns it off. |
| `stance_width` | World px between the two hips. |
| `stride` | World px walked per full stride. Feet look like they **skate**: raise it. They **shuffle**: lower it. |
| `reach` | How far a leg stretches at the front and back of a stride, as a fraction of its drawn length. |
| `rest_reach` | How far the legs reach forward when standing still. |
| `art_scale` | World size over drawn size. Leave at 0.2 unless you draw at a different scale. |
| `backpedal_degrees` | How far apart aim and movement must be before the legs walk backwards. |

## Checking it

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 res://dev/surface_lab.tscn -- --probe=character_rig
```

Close-ups of the player standing, walking towards the aim, backing away and strafing, and an enemy, in
`dev/shots/rig_*.png`. `--probe=rig_backpedal` prints how far each leg reaches through a stride.

The placeholder art follows every rule above, so it doubles as an example: `CharacterLook.placeholder()`.
