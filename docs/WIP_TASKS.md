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

## Phase 8 — Playtest verdict (yours to make)

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
