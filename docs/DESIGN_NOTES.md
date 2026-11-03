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
| A lamp the player can neither see nor stand inside does not light the world for them | The renderer's rule is "lit = visible", and shadows are cast from each light, so a lamp in a sealed room used to reveal whatever was in its pool straight through the wall. Line of sight is tested from the player to the *lamp*, which removes the case that reads as a bug; a lit room you can already see into still shows you what is inside it | `Lamp.require_line_of_sight`, `Lamp.visibility_fade` |
| Path finding is a baked navigation mesh, generated from the walls by one click, with direct steering as the fallback | Hand-drawn navigation polygons would be another thing to keep in sync with the geometry. Baking from the `wall` group means the mesh is derived from the same data the vision, collision and linter all use, and a level without one still works | `NavmeshBaker`, the plugin's "Bake navmesh" button, `Enemy._move_toward` |
| Abilities are one cast path plus a per-ability effect script, not a branch per ability | Weapons share a pipeline (aim -> bullets -> damage), so their uniformity is free. Abilities do not share one, and a `match` in the holder would grow with every ability added. The resource says how it aims and what it costs; the effect script does the rest | `AbilityResource.targeting`, `AbilityResource.effect`, `AbilityHolder.use_ability` |
| The fire wall blocks movement *and* light | It is the one ability that changes the level, and in a game about line of sight a temporary occluder is worth more than the damage. Free to build: `Wall` already generates occluders from a rectangle, and `DamageField` can be solid | `FireWall`, `DamageField.blocks_light` |
| Render at the window's real resolution and derive the scale, rather than stretching a fixed 1280x720 canvas | Stretching a 720p canvas up to 4K softens text and edges, and this game is flat vector art with a text-heavy HUD, so softness is obvious. Rendering natively and deriving the camera zoom and HUD scale costs a few lines either way and is sharp at every size | `project.godot` (`stretch/mode="disabled"`), `Player._update_camera_zoom`, `HUD._compute_scale` |
| The camera keeps a constant *height* of world visible (800px) at any window size | Something has to be held constant for the game to play the same at every size, and for a top-down game that is the vertical field of view: the vision cone, lamp radii and enemy sight then cover the same share of the screen everywhere. The accepted tradeoff is horizontal -- an ultrawide window sees further sideways, which is better than letterboxing it | `Tuning.camera_visible_height`, `Player._update_camera_zoom` |
| The vision cone is a light, not a shader | It is GPU-cheap, it respects occluders automatically, and it means levels stay easy to author | `VisionRig.configure()` |
| Weapon/level/enemy data lives in code libraries, not `.tres` files | Balance is one edit, diffs are readable, and a new weapon is one function | `weapon_library.gd`, `enemy_library.gd` |
| The HUD is built in code | It changed constantly while the game was being built; a `.tscn` would have been re-anchored a dozen times | `hud.gd` |
| Audio is synthesised at startup | The slice ships with no assets, and gunfire needed to exist before it could be tuned | `audio_director.gd` |
| "Continue" resumes a level and a loadout, not a position | A real save system (position, enemy state, items already taken) is a large feature and fragile against levels being re-edited. A checkpoint storing the level path and the loadout is a few lines, reuses `WeaponHolder.serialize()` exactly as the level chain already does, and covers what a player actually minds losing -- their guns | `Progress`, `GameDirector.continue_run` |
| A door is an occluder *and* an obstacle, not just a state flag | In a game where sight is the mechanic, a door that only blocks movement would be decoration. One `StaticBody2D` on the WORLD layer blocks movement, bullets, enemy sight rays and lamp visibility at once, so shutting a door genuinely takes a room off the board | `Door`, `Layers.WORLD` |
| A moving door never shoves anyone | A `StaticBody2D` can block or not block, but it cannot block *without* pushing, so a swinging leaf takes your position out of your hands — which reads as the game fighting you. While the leaf moves, or while it sits on top of an actor, that actor gets a collision exception against it (`add_collision_exception_with`); the exception is dropped as soon as the leaf settles clear, so a settled door blocks normally. This applies to enemies too: a door they opened themselves used to shunt them into corners they could not leave | `Door._physics_process`, `Door._leaf_covers` |
| A search's size comes from *time*, not a constant radius | The player keeps moving after they are lost, so the uncertainty grows every second. A fixed 260px circle while the player may be 900px away meant the enemy searched the right place at the wrong time — it looked like amnesia, not like a search | `Enemy.search_budget`, `Tuning.search_budget_factor` |
| Search targets must be walkable, and are ordered by the player's last heading | A random point behind a wall cannot be reached, and watching an enemy grind toward one is what "wandering off" actually looked like. Asking the navmesh for a path skips those, and rooting the sweep in the direction the player was last moving makes the first place it looks usually the right one | `Enemy._pick_search_target`, `Enemy._can_walk_to` |
| A search goes *to* the trail end first, and doors are checked on the mesh | The place the player was last seen is where the trail ends, and it is what takes a searcher to the door you shut. Reachability is a navmesh path, not a ray, because a ray to a point beyond a shut door is blocked — but a shut door is exactly where a guard should go and open it | `Enemy._enter_search`, `Enemy._can_walk_to` |
| A locked door does not end a search | Being unable to get through a door is not the same as giving up: the enemy rattles it once so you can hear someone trying, marks it as a dead end, and keeps sweeping on its own side. Removing the old freeze also removed the "standing still against a door" look | `Enemy._handle_doors`, `Door.rattle` |
| The *open* leaf is on its own physics layer: it stops sight, bullets and the player, but not enemy movement | The leaf is an object in the room, not a hole that changed state, so its collider and occluder are children of the leaf and swing with it. But doorways are deliberately not navmesh geometry, so an enemy's path runs straight through the leaf -- and a velocity aimed dead into a collider gives `move_and_slide` nothing to slide along, so enemies ground to a halt on open doors. `Layers.DOOR` keeps everything the leaf is for (cover from sight, stopping bullets, stopping the player) and lets the AI's feet through, which is the one property that has to differ per actor | `Layers.DOOR`, `Door._update_solid_layer`, `Door._rebuild_geometry` |
| The navmesh is baked *without* doors in it | If doors were bake geometry, a shut door would make its doorway permanently impassable to path finding, and an open one would be a hole the mesh was cut around. Leaving them out means doorways always connect, and a shut door becomes something the AI handles at the door (`open_for_enemy`) rather than something it plans around | `Door` not being a `Wall`, `Enemy._handle_doors` |
| A blocked door close bounces instead of showing a message | Standing in a doorway and pressing interact is a legible situation: the obstruction is right there on screen. A text message interrupts a fight to explain something the animation can show in a fifth of a second. Nothing is spent, nothing is announced, the leaf just tries and gives up |
| A smashed door is deleted, not left as wreckage | The doorway is the point. Leaving a ghost leaf means every smashed door is a permanent visual object that also has to be explained (can I walk through it, is it still a door). Deleting the node and playing a short splinter burst leaves a clean opening -- and removes a whole class of "is this still interactive" questions | `Door.smash` |
| Locked doors need a key, any key, and can never be smashed | One key type keeps the player from juggling colours, and consuming a key makes the door a real cost. Making locks immune to dashing is what stops the dash from trivialising every door in the game: force opens the cheap doors, keys open the real ones | `Door.interact`, `Door.smash` |
| The pause state is a real menu, not text with key hints | A text overlay can only advertise one binding per action, cannot be clicked, and is unreadable to anyone who has not memorised the hints. `MenuList` is one widget for both menus, and the settings menu hangs off it | `MenuList`, `HUD._show_overlay` |

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

- **A `CanvasModulate` in an authored scene makes Godot's own editor render that
  scene black.** The dark fog is a runtime concern, so it must not live in the
  level file: `Level` creates it. This one line made hand-authoring levels
  impossible until it was removed.
- **Unowned nodes are not serialised, and that is a feature.** Godot's scene saver
  only writes nodes owned by the scene root, which is verified by
  `dev/check_scene_hygiene.gd`. It is what makes editor-only helpers safe: the
  lighting preview and the wall brush's drag preview can be added from `@tool` code
  without any risk of them being written into a level file on save.
- **A rasterised reachability check needs cell centres, not overlap.** Marking a cell
  blocked whenever a wall rectangle overlaps it seals every doorway whose free space
  does not line up with the grid — which is what made a good 64px doorway read as an
  unreachable room until the test moved to the cell centre.
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
- **A physics layer can express "blocks you but not them", and steering cannot.** Two attempts at making
  enemies *steer* around an open door leaf failed for the same reason: the navmesh does not contain
  doors, so the path keeps pointing through the leaf, and any local detour fights it. Worse, a
  `NavigationAgent2D` that is wedged reports itself *arrived*, handing back no direction at all, which
  brakes the enemy to a standstill exactly where it is stuck. The fix was not better steering but a
  property: enemies mask only `WORLD`, so moving an open leaf to `Layers.DOOR` (still in
  `SIGHT_BLOCKERS` and both bullet masks, still in the player's mask) gives the AI a clear route while
  every other property of the leaf is unchanged. When two actors need different answers to "is this
  solid", the answer belongs in the layer table, not in the movement code.
- **A fragment-stage `VERTEX` is not a safe source of local position on a very large quad.** The surface
  shader read `VERTEX` in the fragment stage to work out distance-to-edge, and the floor -- one quad the
  size of the level -- showed a hard-edged rectangular patch of wrong shading in a corner of the screen,
  while walls (small quads near their own origin) looked fine. Both positions are now computed in the
  *vertex* stage and passed as varyings, which is correct by construction for any polygon size. The same
  change dropped an unassigned `breakup` sampler whose default mask turned out not to be trustworthy, and
  stopped applying a rim to floors.
- **A wall cannot be lit by the light it casts shadows for.** Wall tops were textured and rendered almost
  black, and the cause was not the shader: a `LightOccluder2D` puts the rectangle's own interior in
  shadow, because a convex shape is always behind one of its own edges from a light outside it. What the
  game has *always* shown for a wall is its unshaded "memory" silhouette at 30% alpha -- the lit body
  underneath contributed nothing. Measured on the lab: floor (57,39,17) beside wall (18,15,11), and the
  wall's value did not move at all when its tint was raised by 1.77x, which proved the body was invisible.
  Wall surfaces are therefore unshaded (`surface_unshaded.gdshader`), taking the place the silhouette
  had: the wall shows its material once explored, and does not brighten near a lamp. Floors keep the lit
  shader, because light reaches them.
- **"How lit is this wall" is read from the lighting *beside* it, on the side the player is on.** The
  lighting plate is a photograph of the level, and a wall is an occluder, so the mask *on* a wall is the
  wall's own shadow: sampling there can only ever answer "how shadowed am I". `WallDecor` therefore merges
  the walls into one silhouette and, for each vertex, steps ~10px outside the nearest piece of it and reads
  the mask there. Three things this rule has had to get right, each found by playtesting:
  1. **The nearest *point* on a segment**, not the segment's midpoint. With midpoints a long wall had four
     sample positions, so most of it inherited an edge centre's lighting (a large wrongly-lit radius).
  2. **The nearest piece of the whole silhouette**, not of the wall the vertex belongs to. Per-wall queries
     seam at joins, because the two walls either side of a join sample different edges.
  3. **The nearest edge *facing the player*, and always stepped outward.** Without the facing rule a
     64px-thick wall is lit only for the ~20px nearest its lit edge and black for the rest, because the
     vertices in its middle are nearest the far edge and sample the space behind it.
- **A nearest-neighbour search may not stop at the first ring that finds anything.** `WallDecor` buckets
  outline segments into a 96px grid and expanded ring by ring, returning the first ring with a candidate.
  A segment one cell over can be flush against the query point while the point's own cell holds the far
  side of the wall — which is exactly what a wall whose edge sits on a cell boundary gets. Every wall in
  one level sampled its own shadow (`min=0.000 max=0.000`) and rendered black, while the same code looked
  correct in the lab. The search now stops only when the best candidate is closer than the edge of the
  squares already searched, which is exact.
- **Sample each grid corner once.** `WallFill` emitted triangles per cell and sampled all four corners of
  each, so an interior corner was sampled four times; on a 13-wall level that was 2.4x the rebuild cost.
  The fill now shares one vertex grid across the cells (5.7ms instead of 13.9ms per rebuild, measured on
  the camera-heavy test level).
- **"Close enough to the path" is not "standing on the mesh".** Search targets were validated by
  asking whether a path *ended within 40px* of the candidate. A point 30px inside a wall satisfies
  that, so the enemy walked into the wall and ground against it. The check is now
  `map_get_closest_point` against a 4px tolerance, with the path test only for reachability; the
  sweep's exhaustion fallback also used to pick a blind point with no check at all. The probe fuzzes
  400 picks (0 inside walls, 0 off the mesh) and counts how many wall points the *old* rule would
  have accepted (9 in the same geometry), so the pass is a fix rather than a test that cannot fail.
- **"Enemies will not path through this door" was a stale navmesh, not a door bug.** Doors are not
  bake geometry, so the door's lock state cannot affect pathing at all; what had gone stale was the
  mesh itself, baked before the doorway existed. The symptom pointed at the newest feature, which is
  why the fix is a lint *problem* rather than a door change: the linter now checks that every
  doorway's centre is covered by the baked polygons (`LevelLint.disconnected_doorways`), verified
  against the mesh geometry rather than a path query so it works in the editor too. On the level that
  prompted it, the old mesh reported Door2 unconnected and a fresh bake of the same walls connected
  every doorway.
- **A raycast ignores the whole shape its origin is inside.** The muzzle sits 20px ahead of a 14px-wide
  player, so standing flush against a wall put the muzzle *inside* that wall — and a round spawned
  there never saw it, flying out the far side and killing people behind cover. Two fixes, because one
  was not enough: `Projectile.launch` now clamps the spawn to the first surface between the shooter's
  centre and the muzzle, and the flight raycast uses `hit_from_inside = true` so any round that ever
  finds itself inside geometry detonates instead of ignoring it. The clamp alone would leave the next
  spawn path free to reintroduce it; the backstop alone would still spawn rounds past the wall.
- **A debug drawing on the enemy's own canvas is invisible in the dark.** The search overlay lived in
  `Enemy._draw` at first, and produced nothing but two faint arcs on screen: an enemy's canvas item is
  darkened by the fog (that is how enemies stay invisible until your light reaches them), and a search
  is usually happening outside your light. It moved to an unshaded child (`SearchDebugOverlay`).
  Any debug geometry that matters is world-space *and* unshaded.
- **A rotated child pivots on its parent's origin, not on the panel's corner.** The first door leaf
  was a panel offset by half the door's width inside a leaf node sitting at the door's centre, so
  opening it spun the whole panel about the middle like a turnstile. Moving the *leaf node* to the
  edge and drawing the panel from 0 to `size.x` in its space gives a hinge. The rule generalises:
  put the pivot on the node that rotates, not on its child. The probe reports the hinge position
  and the free edge every time it reports a door, so this cannot regress unnoticed.
- **A physics query also lags behind a body that *moved* this frame.** The door's close guard used
  only `intersect_shape`, so a player who entered the doorway and pressed interact in the same frame
  was invisible to it and the door shut on them -- the probe caught it as "door closed and pushed
  the player to exactly the resting distance". Anything that must never happen to the player is now
  also checked against their position directly (`Door.contains_point`), which is exact and instant;
  the shape query still covers enemies.
- **A physics query cannot see a body created in the same frame.** The door test's first version
  spawned a door and immediately asked `intersect_point` whether an enemy was at it; the door did
  not exist to the physics server yet, so the answer was always "nothing there" and the test read
  as a broken AI. The probe now waits two physics frames after spawning before querying. Worth
  remembering for any gameplay code that spawns a body and looks for it immediately.
- **Interaction range has to be measured to a surface, not a centre.** A 96-pixel-wide door's
  centre is 48px from its edge, and the player's own radius puts them ~62px away when standing
  against it, so a 58px centre-to-centre range made wide doors unusable while narrow ones worked.
  `Door.surface_distance` measures to the rectangle, which behaves the way a player expects.
- **A class with both a scene and a script can be built two ways, and only one of them is
  complete.** `Pickup.new()` produces a bare `Area2D` with no collision shape and the default
  layers, while `pickup.tscn` carries both -- so enemy loot rendered perfectly and could never
  be collected. Either always instance the scene, or have the script guarantee what it needs in
  `_ready`; `Pickup` now does the latter so neither path can be wrong. A linter-style check in
  the probe (shape + layer + mask per pickup) is what makes this visible.
- `set_anchors_preset(PRESET_FULL_RECT, false)` does **not** make a `Control` fill its
  parent. It sets the anchors and then recomputes the offsets to keep the control's
  *current* size, which for a freshly created control is zero -- so a full-screen overlay
  became a zero-sized rect at the origin. Its children still drew (`clip_contents` is off by
  default), so the symptom was a settings panel centred on the top-left corner of the
  screen rather than anything that looked like a sizing bug. `set_anchors_and_offsets_preset`
  is the call that fills the parent. The HUD's overlay had the same latent bug, which is
  why the death and victory text used to sit in the corner; a `CanvasLayer` child happens
  not to need it, which is why the rest of the HUD looked correct for so long.

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
2. **Enemy navigation** — *done*: enemies path with a navigation mesh baked from the
   walls by one click in the plugin, and fall back to direct steering when a level has
   none. What is still missing is *avoidance*: agents happily pass through each other,
   so a group hunting you can overlap. `NavigationAgent2D.avoidance_enabled` (RVO) is
   the switch, but it needs tuning to avoid jitter.
3. **Enemy perception polish**: peripheral vision cones drawn for *awareness*
   only, a "last seen" marker the player can see, an enemy that checks corpses.
4. **ARPG layer** — *partly done.* Abilities exist: slots, per-slot cooldowns, upgrade
   levels, pickups, and one cast path with a per-ability effect script, so a fourth
   ability is a library entry plus a small script. Still missing: ability upgrade pickups,
   a targeting telegraph at the cursor (a cast clamps to range and reports refusals, but
   nothing shows the reach *before* you commit), abilities that target entities rather
   than points, and consumables.
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
