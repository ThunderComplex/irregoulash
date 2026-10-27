# TopDown Shooter — WIP Vertical Slice: Task List

**Goal of this WIP:** answer one question — *"Is line-of-sight-based topdown shooting actually fun,
and is this architecture worth extending into a full game?"*

It is not a finished game. It is the smallest thing that contains the **whole loop** end to end:
sneak → get spotted → fight → loot → move to the next level.

Status: **all phases built, mechanically verified, ready for you to play.**

---

## Decisions locked in

| Topic | Decision |
|---|---|
| Scope | Full vertical slice: movement, aim, 3 weapons + pickup/switch/upgrade, LoS fog, layered enemy AI, 2 connected levels, HUD, death/win, debug tools |
| Vision tech | `CanvasModulate` (black ambient) + `PointLight2D` (near-sight ring + aim cone) + `LightOccluder2D` shadows, auto-generated from wall shapes |
| Camera | Smooth follow with level limits; anything outside the player's LoS is pitch black |
| Enemy AI | Patrol → Suspicious → Alert → Search → Return, awareness meters, sight + hearing, ally alerting |
| Art | Geometric placeholder shapes generated in-engine; no asset dependencies |
| Levels | 2 connected levels + a documented template + an ASCII builder that lints what it builds |
| Out of scope | ARPG abilities/talents, inventory, procgen levels, saving, shops, bosses, real audio/art assets, controller support, options menu |

---

## Phase 0 — Project foundation ✅
- [x] `project.godot`: physics layer names, display size, MSAA, autoloads, near-black clear colour
- [x] Autoloads: `Tuning`, `GameInput`, `AudioDirector`, `FxDirector`, `GameDirector`
- [x] `Tuning` = the single source of truth for every gameplay number (live-editable while playing)
- [x] Input actions registered at runtime in code, so a keybind is a one-line change and cannot be
      corrupted by a hand-edited `project.godot`

## Phase 1 — Core vision tech ✅
- [x] Procedural light textures from a `PackedByteArray` (radial falloff + soft-edged cone)
- [x] Vision rig: near-sight ring + aim cone, both shadow-casting
- [x] `Wall`: one `size` property generates collider, occluder, visual and memory copy, live in the editor
- [x] `Lamp`: static lights, wall-blocked, with an unshaded fixture that reads as a beacon in the dark
- [x] Proving-ground dev scene with corners, a doorway, a pillar and a lamp
- [x] Explored-geometry memory (walls stay faintly visible; enemies never do)
- [x] Dev probe harness: scripted scenarios, numeric pixel sampling, screenshots

## Phase 2 — Player ✅
- [x] Screen-relative WASD movement, acceleration/friction, `MOTION_MODE_FLOATING`
- [x] Mouse aim, independent of movement, with a gun pivot that flips when aiming left
- [x] Dash with cooldown, sparks, and a noise event that enemies can hear
- [x] `Health` component: damage, hit flash, invulnerability window, death
- [x] Footsteps with their own noise radius
- [x] Recoil pushback, camera aim-offset lead, smooth follow with level-derived limits

## Phase 3 — Weapons ✅
- [x] `WeaponResource` + `WeaponSlot` (runtime state, upgrade level) + `WeaponLibrary` (3 weapons)
- [x] Pistol (semi, accurate), SMG (full auto, cheap, loud), Shotgun (7 pellets, huge knockback)
- [x] `WeaponHolder`: fire cadence, mag/reserve, reload, spread bloom, knockback, per-shot noise
- [x] `Projectile`: swept raycast (no tunnelling), self-drawn streak, visible orbs for slow rounds
- [x] Muzzle flash light that gives away the shooter's position
- [x] Pickups: weapon, ammo, medkit, weapon upgrade crate — all self-lit so they are findable
- [x] Switching with `1`/`2`/`3` and the mouse wheel; HUD shows mag/reserve/slots/reload
- [x] Weapon loadout persists across levels

## Phase 4 — Enemies ✅
- [x] `EnemyArchetype` + `EnemyLibrary`: guard, scout, heavy
- [x] Perception: FOV + range + real line-of-sight raycasts, on a 0.15 s clock
- [x] Awareness meter: distance-scaled, boosted ×1.8 when the player's own cone is on them
- [x] Hearing: gunshots, footsteps and dashes are radius-based noise events
- [x] FSM: Patrol (routes or wander or stand-and-scan) → Suspicious → Alert → Search → Return
- [x] Alert shouts propagate to friends in earshot; being shot at wakes enemies up
- [x] Burst fire with reaction delay and range-scaled inaccuracy; dodgeable projectiles
- [x] Death: corpse, blood stain, weapon drop, kill counter

## Phase 5 — Level flow & content ✅
- [x] `Level` base: auto-creates fog, memory, FX layer, HUD; spawns the player; derives camera limits
- [x] `ExitZone`: beacon light, unshaded marker, overlap polling, final-exit flag
- [x] Title screen with the control list generated from `GameInput` (cannot drift out of date)
- [x] Death / victory / pause overlays, run stats, restart-in-place, back to title
- [x] ASCII → `.tscn` builder with a level linter (unreachable entities, entities in walls, missing exit)
- [x] Level 01 "The Yard" (5 enemies) and Level 02 "The Depot" (7 enemies, 6 rooms off a corridor)
- [x] `level_template.tscn` + `docs/LEVEL_AUTHORING.md`
- [x] HUD: health, ammo, weapon slots, reload bar, threat indicator, objective, banner, message feed

## Phase 6 — Audio & juice ✅
- [x] `AudioDirector`: 24 sounds synthesised from noise bursts and sine sweeps at startup
- [x] Pooled 1D and 2D players, per-play pitch variation, a dedicated SFX bus
- [x] Gunshots per weapon, reload, dry fire, impacts, hurt, death, pickups, footsteps, alert stingers
- [x] Muzzle flashes, impact sparks, blood with fading stains, tracers, screen shake
- [x] Edge-only damage vignette (shader), hit flashes, level banner

## Phase 7 — Verification, tuning, docs ✅
- [x] Headless load tests for every scene; a clean console apart from the fixed bugs below
- [x] Probe scenarios: `vision`, `memory`, `map`, `combat`, `death`, `flow`, `title`, `debug`
- [x] Balance pass: enemy damage/spread/reaction, player invulnerability, light strength and falloff
- [x] `README.md`, `docs/LEVEL_AUTHORING.md`, `docs/DESIGN_NOTES.md`, this file
- [x] Debug tools: god mode, noclip, debug readout, reveal, spawn enemy, alert all, give all weapons

## Phase 9 — Level authoring tools (added after the first playtest)

The first authoring pass was disliked for concrete reasons, and they were fair: it
was text instead of drawing, it was grid-locked, enemies and routes were invisible
in the editor, and **the level scenes contained a black `CanvasModulate`, which made
Godot's own 2D editor render them black**. That last one was my bug, not a limitation
of Godot — and it was most of the reason a separate editor app looked necessary.

Authoring now happens in the Godot editor, not in a separate application:

- [x] Removed the fog from level scenes (created at runtime instead) — this is what
	  made the 2D editor usable again
- [x] `PatrolRoute`: waypoints as `Marker2D` children, drawn in the editor as a
	  dashed path with direction arrows and numbered points, plus a link line from
	  every enemy that patrols it
- [x] Editor gizmos for every entity: enemies (facing wedge, vision cone, archetype
	  name, broken-route warnings), pickups (symbol + label), exits (ring +
	  destination), the spawn point with the player's vision reach, camera bounds
- [x] Lamps render real lights and shadows in the editor (a hand-authored
      `GradientTexture2D` in `lamp.tscn`) instead of only a radius arc
- [x] Opt-in `editor_lighting_preview` on `Level`, so the *lighting* can be authored
      and not just the geometry
- [x] **Wall brush** (`addons/level_tools/`): drag to draw walls, with undo/redo,
      axis bands vs rectangles, `Ctrl` for squares, `Alt` to ignore snapping, and a
      live size readout while dragging
- [x] **`LevelLint`**: no spawn / no exit / an exit that goes nowhere / content buried
      in walls / broken patrol routes / content the player cannot reach, with a
      walkability map printed when reachability fails. Runs from the editor button or
      headlessly via `--probe=lint`
- [x] Verified: three levels lint clean; the editor loads every scene and the plugin
      with no errors; runtime behaviour is unchanged (fog, occluders, AI, and the
      enemy-facing check all still pass)
- [x] `dev/check_scene_hygiene.gd` proves that (a) saving a level cannot bake
      generated colliders or occluders into it, and (b) editor-only helper nodes are
      never serialised, which is what makes the lighting preview safe

## Phase 10 — Post-playtest fixes and decisions (current state)

Everything below came out of actually *using* the thing, which is where the real bugs
were. Each one was diagnosed from evidence (probe output, pixel samples, walkability
maps, the editor's own error log) rather than guessed at.

**Authoring**

- [x] Wall brush: the drawn wall landed down-and-right of the mouse. Canvas input
	  arrives in *editor window* coordinates and the 2D viewport is offset by the
	  docks; it now asks `Viewport.get_mouse_position()`, which is in the space
	  `get_canvas_transform()` expects
- [x] Wall brush: the on-canvas preview was removed. It drew in window space and
	  reintroduced the very same offset from the other direction — the in-scene wall
	  is the preview now, and it is exact by construction
- [x] Wall brush: no longer stops working after each wall. It used to re-derive its
	  parent from a selection it had just changed; the container is now pinned and
	  kept selected, which also means one click per wall instead of two
- [x] **Enemy tool**: pick an archetype, click to place, click out a patrol route,
	  right-click to finish. One dedicated `PatrolRoute` per enemy, committed as you
	  go so `Ctrl+Z` walks the route back rather than discarding the enemy
- [x] `Level.next_level` was exported *and documented* but read by nothing. It is now
	  the fallback target for exits without one, and both the linter and the exits'
      editor labels understand the fallback
- [x] Linter: one waypoint is a valid guard post rather than a problem, and its
      reachability test no longer seals doorways whose free space misses the grid
      (tests cell centres instead of cell overlap)

**Gameplay**

- [x] Bullets outlive their shooters, so a freed reference reached a typed parameter
      and killed `take_hit` at the worst possible moment. Damage sources are validated
      rather than typed
- [x] Enemy facing: the authored rotation was applied twice, so the nose — the only
	  cue for which way an enemy's vision cone points — was permanently off by up to
	  133°. Measured, then fixed, then measured again (`nose_err` is 0.0° in all states)
- [x] Pickup and exit lights now cast shadows; they were leaking light through walls
- [x] Enemy navigation is a navigation mesh baked from the level's walls by one click in
      the plugin ("Bake navmesh"), with direct steering as the fallback for levels that
      have none. Verified by baking at runtime and raycasting every sampled path against
      the geometry: 24 paths, 0 wall crossings
- [x] Lamps are gated on line of sight: a lamp the player can neither see nor stand
	  inside no longer lights the world for them, so sealed rooms stay dark

**Known and deliberately deferred**

- Per-pixel visibility from the player (a screen-space shadow pass) would remove the
  last case where a lit room reveals what is inside it, including things behind its own
  furniture. Too expensive for a WIP; see the decision table in `DESIGN_NOTES.md`.
- Enemy navigation is a baked mesh now, but agents do not avoid *each other*: a group
  converging on the player will overlap. (`NavigationAgent2D.avoidance_enabled` is the
  switch; it needs tuning for jitter.)
- Quitting with a sound playing prints a spurious "leaked ObjectDB instances" warning
  (engine-side, documented in the README).
- The levels are still first drafts: cover and lamp placement will matter more than
  any code change from here.

## Phase 13 — Resolution independence and settings

The game no longer assumes 1280x720 anywhere: every window size and aspect ratio works.

- [x] Native rendering (`window/stretch/mode="disabled"`) instead of stretching a 720p canvas,
      so text and edges stay sharp on a large or high-DPI display
- [x] `Tuning.camera_visible_height`: the camera zooms so **800px of world is visible
      vertically at every window size** — verified 800 at 1280x720, 1920x1080, 1024x768,
      1280x800, 1600x600, 2560x1440 and 800x600. At 1280x720 that is zoom 0.9, exactly the old
      hardcoded value, so the existing feel is unchanged
- [x] HUD scaled from `Tuning.ui_reference_height` and rebuilt on resize (measured 0.833 to
      2.000 across those sizes), so it reads the same relative size on any display
- [x] Title screen and settings menu laid out in a scaled 1280x720 reference frame and rebuilt
      on resize, so neither assumes the old resolution
- [x] `Settings` autoload: window mode (windowed / borderless / exclusive), resolution, vsync,
      master and SFX volume — applied immediately and persisted to `user://settings.cfg`
- [x] Settings menu reachable from the title screen (`O`) and from the pause overlay (`O`),
      with the live window size in its footer
- [x] `Settings` now owns the SFX bus volume; `AudioDirector` stopped setting it, so the two
      cannot fight over the same slider
- [x] Fixed a latent bug found on the way: the HUD's death/victory overlay was zero-sized, so
      its text was drawn in the top-left corner (see DESIGN_NOTES)
- [x] Verified: settings open from a paused game, and a save/load round-trip reads back the
      written values (the probe restores the player's settings file afterwards)

Still open: no in-game keybind rebinding, no mouse sensitivity, and no command-line display
overrides. A very wide window sees more world sideways, which is documented in
LEVEL_AUTHORING.

## Phase 12 — Abilities

Three abilities on their own slots, sharing exactly one cast path.

- [x] `AbilityResource` as a full data sheet (targeting mode, range, placement rules, area,
      tick, duration, projectile speed, noise, shake, upgrade growth) with all balance in
      `AbilityLibrary`, in the same shape as weapons
- [x] Targeting split: `POINT` (clamped to range, optionally requiring a clear spot),
      `DIRECTION`, and `SELF` reserved
- [x] `AbilityHolder`: cooldowns **per slot**, one cast path, effects spawned through
      `GameDirector.spawn_parent()`, sfx + noise + shake driven by the data, and refusals
      that cost the player nothing
- [x] `DamageField`: the shared area-damage component (a rectangle for the wall, a circle
      for the blast), ticking through the same `take_hit()` interface bullets use, and
      optionally solid and shadow-casting
- [x] `FireWall` (solid and occluding), `FireTempest` (circular blast), `LightningBolt`
      (reuses `Projectile`)
- [x] HUD line per slot; ability pickups are left on the ground when the slots are full or
      already carrying that ability
- [x] Fixed four bugs found on the way: a `match` default written as the string `"_"`
      instead of the wildcard, the ability pickup defaulting to `"smg"`, `add_ability`
      reporting success with nowhere to put the ability, and cooldowns scaling *up* with
      upgrades
- [x] Verified: the bolt removes exactly its 18 damage, the tempest kills a 55hp guard, a
      wall inside geometry is refused *without* spending its cooldown, a wall in the open
      reports `solid=true occludes=true`, and an immediate re-cast is refused while cooling

Still open: no aiming telegraph before casting, no ability upgrade pickups, and abilities
can only target points and directions, not entities.

## Phase 11 — Playtest verdict (yours to make)

Things I verified mechanically (screenshots + numeric probes, see `dev/shots/`):

- Lighting is multiplicative and lit surfaces keep their material colour
- Behind a wall with a clear sightline blocked, sampled pixels are `rgb(0,0,0)` — genuinely invisible
- Explored walls sample at exactly 30 % of their colour; unexplored floor samples at 0
- 12 pistol rounds killed 2 guards; noise pulled a third into SUSPICIOUS and then ALERT
- Awareness rises from the player's own cone landing on an enemy (`aw=0.37` while patrolling)
- Enemies finished a full cycle: PATROL → SUSPICIOUS → ALERT → SEARCH → PATROL
- Exits chain levels, weapon loadout survives the transition, the final exit shows the win screen
- Dying shows the death overlay with run stats
- The audio bank builds 24 valid streams (longest 2.22 s) and a pooled player actually plays
- A dedicated stress scenario (10 enemies, 48 shots, 5 kills, player under fire) runs with an
  entirely clean console after fixing the stale-damage-source bug described in `DESIGN_NOTES.md`
- The `facing` scenario measures the drawn nose against the real vision direction for every
  enemy: `nose_err` is 0.0° in all states, and ALERT enemies show `aim_err` 0.0° (nose on you)

What I cannot judge from here, and what to look at when you play:

1. **Does the cone feel tense or annoying?** If it is annoying, `sight_far_range` and
   `sight_far_degrees` are the two numbers to move first.
2. **Is the explored-wall memory enough to navigate by?** If you get lost, raise
   `Tuning.memory_brightness` and/or add lamps to the levels.
3. **Is the awareness meter fair?** If fights feel untelegraphed, lower
   `awareness_lit_multiplier`; if sneaking feels trivial, raise it.
4. **Is "noise pulls guards to you" legible?** The feedback is the alert stinger plus the
   threat meter; if it reads as random, the fix is a noise indicator, not more tuning.
5. **Do the level layouts work?** They are first drafts. Cover and lamp placement will
   matter more than any code change — this is the most likely first edit.
