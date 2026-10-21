# Design notes, findings and roadmap

## The pitch in one line

You cannot see anything your own light does not touch, the enemies notice when
that light lands on them, and sound travels through walls. Everything else in
this slice exists to make that one idea readable.

## The three pillars

1. **Vision is the mechanic, not a filter.** The fog is not decoration: unseen
   things are genuinely invisible, enemies included. That is what makes sneaking
   and being ambushed both possible.
2. **Awareness is a meter, not a switch.** Enemies fill an awareness value from
   zero, faster when you are closer, when they can see you, and — importantly —
   when your own cone is pointed at them. Looking at something makes it notice
   you. That is the tension the whole design hangs on.
3. **Noise is information for everyone.** Gunshots, dashes and footsteps are
   broadcast events with a radius. They pull patrols towards you, and they are
   how you track enemies you cannot see.

## Design decisions worth knowing about (and how to reverse them)

| Decision | Why | Where to change it |
|---|---|---|
| Enemies see in the dark; the player does not | They are the authority on their own senses, and the player has lamps + wall memory + their own cone as counterweights. Perfect symmetry would remove the tension. | `Tuning.enemy_sight_range`, `enemy_sight_fov` |
| Walls are drawn *above* actors | Top-down readability: geometry reads as solid, actors never straddle it | `Layers.Z_WALL` |
| Combat FX (muzzle flashes, blood, sparks) are unshaded | So a fight in the dark is still legible — you track enemies by muzzle flash, which is also how you find them | `FxDirector._additive_material()` |
| Explored walls stay visible at 30%; enemies do not | The map has to be memorisable without leaking enemy positions | `Tuning.memory_brightness` |
| The vision cone is a light, not a shader | It is GPU-cheap, it respects occluders automatically, and it means levels stay easy to author | `VisionRig.configure()` |
| Weapon/level/enemy data lives in code libraries, not `.tres` files | Balance is one edit, diffs are readable, and a new weapon is one function | `weapon_library.gd`, `enemy_library.gd` |
| The HUD is built in code | It changed constantly while the game was being built; a `.tscn` would have been re-anchored a dozen times | `hud.gd` |
| Audio is synthesised at startup | The slice ships with no assets, and gunfire needed to exist before it could be tuned | `audio_director.gd` |

## Findings from building this (measured, not guessed)

These three cost the most time and are worth writing down:

1. **Godot 4's 2D lighting is multiplicative, and `CanvasModulate` is the
   ambient.** A lit surface keeps its own colour (`base * (ambient + Σ lights)`);
   with a black ambient and a white cone light, the world looks like its
   materials. An early "the lighting looks washed out" diagnosis was wrong — the
   cause was light *strength* and a too-dark floor colour, not blending.
2. **Unshaded canvas items are not affected by `CanvasModulate`.** That is what
   makes the explored-geometry memory possible in the normal canvas layer, with
   no extra `CanvasLayer` (and therefore no camera-alignment work). The memory
   copy must be composited **on top of** the wall body; drawing it underneath
   hides it behind an opaque unlit polygon.
3. **`PointLight2D` textures define the light's shape, and a wedge texture plus
   node rotation is a vision cone.** Both the wedge and the radial falloff are
   generated into a `PackedByteArray` at startup — no PNGs, no import settings,
   and the falloff maths is one function.

Also worth knowing:

- **A code-driven child rotation plus an authored parent rotation is a double
  application.** The level builder gives every enemy a `rotation` to set its
  starting facing. `Enemy` folded that value into `_facing` but left it on the
  node as well — and because `Visual.rotation` is driven from `_facing` in *local*
  space, the drawn nose ended up rotated by the authored angle twice. The vision
  logic was always correct (`aim_err` measured 0.0° whenever an enemy was ALERT);
  only the drawing was wrong, by a constant per-enemy offset of up to 133°. Fixed
  by folding the authored rotation into `_facing`, zeroing the node, and applying
  the facing to the visual immediately. Anything that draws a direction from a
  script (the player's gun pivot and vision rig too) needs the same care.

- **A bullet outlives its shooter, so damage sources must be validated, not
  typed.** `Projectile` holds a reference to whoever fired it; if that enemy dies
  while the round is still in the air, the reference becomes a freed object.
  Handing a freed object to a typed parameter (`source: Node`) or emitting it
  through a typed signal is a runtime error, and it only shows up sporadically —
  exactly when a fight is going well. `Health.take_damage()` therefore takes an
  untyped `source`, validates it with `is_instance_valid()`, and passes a valid
  `Node` or `null` onwards. `GameDirector.valid_player()` exists for the same
  reason: casting a freed node (`GameDirector.player as Player`) errors too.
- **Never touch a node after something that might have freed it.** The HUD used
  to call `get_viewport().set_input_as_handled()` *after* `go_to_title()`, which
  replaces the scene — a node that has left the tree has no viewport. Same
  reason the level loader defers `change_scene_to_file`.
- `LightOccluder2D` shadows work with all-default masks, but **only if the
  occluder exists**, which is exactly why `Wall` generates it.
- Synthetic input cannot reliably fake a "just pressed" across the physics-frame
  boundary, so scripted semi-auto fire drives the weapon directly. Real input is
  unaffected.
- `Area2D.body_entered` does not fire for bodies *placed* inside the area. Exits
  and pickups therefore poll overlaps as well, which also makes them correct for
  a player teleported, respawned or dropped onto them.
- Swapping scenes from inside a physics callback is not allowed; the level loader
  defers `change_scene_to_file`.

## Tuning cheat sheet

Everything lives in `src/autoload/tuning.gd` (live-editable via the editor's
Remote tree while playing), `src/weapons/weapon_library.gd` and
`src/enemies/enemy_library.gd`. The knobs that change the feel the most:

| Want | Change |
|---|---|
| More/less claustrophobic | `sight_far_range`, `sight_far_degrees` |
| Stealth to be more forgiving | `awareness_gain_*`, `awareness_lit_multiplier` |
| Enemies to give up sooner | `alert_lost_sight_grace`, `search_duration` |
| Fights to be survivable | `enemy_library` damage/spread, `player_max_health` |
| The player to find the map more easily | `memory_brightness`, more `Lamp`s |

## Extension roadmap

Roughly in the order that makes sense next:

1. **A real playtest and pass on level layouts.** The two levels are first
   drafts. Cover placement and lamp placement will matter more than any code.
2. **Navigation for enemies.** A baked `NavigationRegion2D` per level would
   remove the "wedged on geometry" failure mode and let enemies flank properly.
   `Enemy._avoid()` is the only thing that would be replaced.
3. **Enemy perception polish**: peripheral vision cones drawn for *awareness*
   only, a "last seen" marker the player can see, an enemy that checks corpses.
4. **ARPG layer** (explicitly out of scope here, but reserved): a `WeaponSlot`
   already carries an upgrade level, `Health` is a component, and pickups are
   data-driven — an `Ability` resource + a cooldown holder would slot in beside
   `WeaponHolder` without touching the player script.
5. **More content**: 3–4 more weapons, 2 more archetypes, a proper level chain
   with branching exits (an exit is already just a scene reference).
6. **Real audio and art**: `AudioDirector` is a drop-in replacement target
   (swap `_build_bank()` for `load()` calls); every entity builds its art in a
   `_build_art()` function that can be replaced with a `Sprite2D` in one place.
7. **Save/load, options, gamepad.** All absent.

## What to judge when you play it

The questions this slice exists to answer:

- Does sweeping a torch-like cone around a dark room feel tense, or does it just
  get in the way?
- Is the explored-wall memory enough to navigate by, or do you get lost?
- Does the awareness meter read as fair when a fight starts, and does breaking
  line of sight feel like an escape?
- Is "noise pulls guards to you" legible in play?
- After ten minutes, do you want another room, or do you want to stop?
