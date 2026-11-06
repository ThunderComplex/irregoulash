# Task list

The work that is queued, written as steps rather than intentions. Each task says what changes, which
files it touches, how it is verified, and when it counts as finished.

Design reasoning lives in `docs/DESIGN_NOTES.md`; genuinely undecided questions live in
`docs/OPEN_QUESTIONS.md`. This file is only the queue.

## Order and dependencies

| # | Task | Depends on | Size | Status |
|---|------|------------|------|--------|
| 1 | Carry abilities between levels | -- | small | done |
| 2 | Ability upgrade pickups (both slots +1) | 1 | small | done |
| 3 | Campaign as one ordered table | -- | medium | done |
| 4 | Rebindable input (keyboard and mouse) | -- | medium | done |
| 5 | Gamepad support, including Steam Deck | 4 | large | done |
| 6 | Level select after finishing | 3 | medium | done |
| 7 | Steam release plumbing | 3, 4, 5, 6 | medium | queued |

Why this order:

- 1 unlocks 2, and both are progression fixes: an upgrade that evaporates at the next door is worse
  than no upgrade at all.
- 3 is independent, and doing it early makes every level added after it cheaper. 6 depends on it.
- 4 and 5 are the only "before release" blockers. 5 depends on 4's binding store being built from
  `InputEvent`s rather than from key codes, so 4 is not throwaway work.
- 7 is packaging rather than game, so it goes last.

Every task ends with the probe scenario named under **Verify** passing and the docs it touches
updated. Code that compiles is not a finished task.

---

## 1. Carry abilities between levels

**Status: done.** `--probe=carry` passes (and fails with the restore removed). `AbilityHolder.serialize/deserialize`,
`GameDirector.carried_abilities` / `snapshot_carried()`, `Level._spawn_player()`, and the `progress.cfg`
`abilities` field are in place. The probe now finds the next level through `CampaignLibrary` (task 3),
not through an exit's export.

**Goal.** An ability picked up in a level is still carried in the next one, and through Continue,
including its upgrade level.

**Why.** `Level._spawn_player()` restores the weapon loadout and the key count; abilities are not part
of that, and each level instantiates a fresh `Player`. So an ability is currently a one-level buff --
invisible until the player notices it is missing two rooms later, and fatal to task 2.

**Steps.**

1. `src/abilities/ability_holder.gd`: add `serialize() -> Array` mirroring
   `WeaponHolder.serialize()`: one entry per slot, `{ "id": String(slot.data.id), "level": slot.level }`.
   Cooldowns are deliberately not carried -- a level starts with both abilities ready, exactly as a
   level transition already drops a reload timer.
2. Same file: add `deserialize(data: Array) -> void`. Clear `slots`, then rebuild each one directly
   (`AbilitySlot.new(data)`, `slot.level = maxi(0, int(...))`). Do **not** route through
   `add_ability()`: it refuses when the slots are full or the ability is already carried, which is
   precisely the state being restored. Skip ids that no longer resolve with a `push_warning`, so a
   renamed ability cannot brick a save that carries it.
3. `src/autoload/game_director.gd`: add `var carried_abilities: Array = []` beside
   `carried_loadout`; reset it in `start_run()`; copy it in `continue_run()` from `Progress.abilities`;
   snapshot it in `snapshot_loadout()` and rename that function to `snapshot_carried()`, because it
   no longer carries only a loadout. Update its callers (`notify_level_cleared`, `Progress.record`).
4. `src/levels/level.gd`: in `_spawn_player()`, after the weapon block, restore abilities when there
   is anything to restore:
   `(player.abilities as AbilityHolder).deserialize(GameDirector.carried_abilities)`.
   A fresh run still starts empty and takes its first ability from a level pickup.
5. `src/autoload/progress.gd`: add `abilities: Array`, save it under `[progress] abilities`, snapshot
   it in `record()`, clear it in `clear()`, and read it with a `[]` default so checkpoints written
   before this change still load.
6. `docs/DESIGN_NOTES.md`: extend the "Continue resumes a level and a loadout, not a position" row to
   say it restores weapons, keys and abilities.

**Files.** `src/abilities/ability_holder.gd`, `src/autoload/game_director.gd`,
`src/levels/level.gd`, `src/autoload/progress.gd`, `docs/DESIGN_NOTES.md`.

**Verify.** New `--probe=carry` scenario, run against `level_01` (it has an exit and short geometry):

1. Grant `fire_wall` and `lightning_bolt`, set their levels to 2 and 0. Print both.
2. `GameDirector.notify_level_cleared()` (which snapshots), then `GameDirector.load_level(next)`.
3. In the new level, assert the slots and levels match and the cooldowns are ready.
4. `Progress.record()`, drop the player, `GameDirector.continue_run()`, assert again.

Expected output is a single PASS line; before the change it prints `0 abilities` after the transition.

**Done when.** An ability taken in one level is still in the slots in the next, with its level, both
across a normal exit and across Continue.

**Watch out.** `AbilityHolder.MAX_SLOTS` is 2; `deserialize` should restore whatever it is given and
let the slot cap be an authoring concern, or clamp with a warning -- do not silently drop slots 3+.

---

## 2. Ability upgrade pickups

**Status: done.** New `kind = "ability_upgrade"`; `AbilityHolder.upgrade_all()` raises both slots and
returns false at the cap so the crate stays on the ground; both slot types cap at level 3; the HUD
shows `+` marks for abilities as it already did for weapons. `--probe=ability_upgrade` checks the
raise, the cap, the empty case and the HUD label. Crates placed in `level_campaign_02` and
`level_campaign_04` (next to existing pickups) — move them if the rooms want them elsewhere.

**Decision.** One crate upgrades **both** ability slots by one level. The player has two slots and no
"current" one, so "which ability does it upgrade" has no good answer; upgrading both is explicit,
wastes nothing, and keeps the reward legible.

**Goal.** A pickup that raises both abilities one level, shown on the HUD, and left on the ground when
it cannot do anything.

**Steps.**

1. `src/items/pickup.gd`: add `"ability_upgrade"` to the `@export_enum` on `kind` (after `"ability"`).
   Keeping it separate from `"upgrade"` (which raises the weapon in hand) is deliberate: the two
   rewards differ and the inspector list is where that is decided.
2. `src/abilities/ability_holder.gd`: add `upgrade_all() -> bool` -- return `false` when `slots` is
   empty or every slot is already at the cap, otherwise `upgrade()` each slot and return `true`.
3. Decide and add a level cap. Weapons are currently uncapped (`WeaponSlot.upgrade()` increments
   forever); abilities scale damage linearly and cooldown down to a 0.4s floor. A cap of **3** is a
   reasonable first number for both, and `upgrade_all()` returning `false` at the cap is what keeps a
   late crate on the floor instead of being consumed for nothing. Put the constant next to
   `AbilitySlot.upgrade()` so it is one place per system.
4. `src/items/pickup.gd`: handle the new kind in `_try_collect()` -- `if not ability_holder.upgrade_all(): return`
   (not consumed, same rule as a full-slot ability pickup), then `AudioDirector.play_at(&"upgrade", ...)`
   and `GameDirector.announce_message("ABILITIES UPGRADED", ...)`. Add it to `_pickup_color()`, the
   `_draw()` icon branch, and `editor_label()` ("ABILITY UPGRADE").
5. `src/ui/hud.gd`: in `_update_abilities()`, append `"+" .repeat(slot.level)` to the label the way
   `_update_weapons()` already does, so the upgrade is visible in play.
6. Authoring: place two or three crates across the campaign (not every level), and update the pickup
   table in `docs/LEVEL_AUTHORING.md` with the new kind and the "both slots" rule.

**Files.** `src/items/pickup.gd`, `src/abilities/ability_holder.gd`, `src/abilities/ability_slot.gd`,
`src/ui/hud.gd`, `docs/LEVEL_AUTHORING.md`.

**Verify.** Extend `--probe=loot` (it already spawns and collects pickups) with: an `ability_upgrade`
crate while carrying two abilities asserts both levels rise by exactly one; the same crate while
unarmed stays collectable (`_collected == false`); at the cap it also stays collectable; and the HUD
label contains a `+`.

**Done when.** The crate raises both slots, is not consumed when it cannot help, and the HUD shows the
level.

---

## 3. Campaign as one ordered table

**Status: done.** `CampaignLibrary.LEVELS` is the chain; `ExitZone` no longer exports `next_level`
or `is_final`, and `--probe=lint` prints the campaign in order and checks every level in it (plus the
ones on disk that are not). Verified with `--probe=flow` from `level_campaign_03`: two exits, then the
victory screen.

**Goal.** One list, in one file, is the authority on level order, the next level, and which level is
last. Exits stop carrying targets, and adding a level is one line.

**Why.** Today the chain exists only as `next_level` links between scene files, starting from
`GameDirector.FIRST_LEVEL`. Nothing knows a level's position, the docs describe a `Level.next_level`
fallback that does not exist, and `LevelLint` reads that same nonexistent property (so its "or the
level" branch is dead code). A table fixes all three and is the prerequisite for a level select.

**Steps.**

1. New `src/campaign/campaign_library.gd`, following the code-library pattern of `WeaponLibrary` and
   `EnemyLibrary`:

   ```gdscript
   class_name CampaignLibrary
   extends RefCounted

   ## Every level, in play order. The only place the chain exists.
   const LEVELS: Array[String] = [
       "res://src/levels/level_campaign_01.tscn",
       # ...
   ]
   ```

   with `paths()`, `count()`, `first()`, `index_of(path)`, `next_after(path)` (empty on the last),
   `is_final(path)`, `position_text(path) -> "3 / 12"`, and a cached `title_of(path)` that reads the
   scene's `level_title` once.
2. `src/autoload/game_director.gd`: `FIRST_LEVEL` becomes `CampaignLibrary.first()`; keep the constant
   as a one-line alias during migration if that makes the diff smaller, then delete it.
3. `src/levels/exit_zone.gd`: delete the `next_level` and `is_final` exports. `_enter()` asks the
   campaign what comes next, through a level helper rather than `owner`/`current_scene`: add to
   `Level` a `campaign_next() -> String` and `is_final_level() -> bool`, and walk up from the exit the
   way `Wall.surface_style()` walks up for its style. `accent_color()`, `_label` and `editor_label()`
   read the same helpers, so the editor ring already says `TO: <title>` with no wiring.
4. `src/levels/level_lint.gd`: replace the dead `root.get("next_level")` exit check with
   "this level is in `CampaignLibrary`" plus the campaign-wide checks in step 6.
5. Migration: strip `next_level` / `is_final` lines and their now-unused `ext_resource` entries from
   `level_campaign_01..04` and `level_01..03`, and from `dev/build_levels.gd` (the optional ASCII
   builder writes both). Run `--import` afterwards; a removed `ext_resource` that is still referenced
   fails loudly, which is the check.
6. `LevelLint`: add `static func campaign() -> Array[String]` -- every path exists, no duplicates, at
   least two levels, the last level's exits are final by construction, and (a note, not a problem) the
   open scene's position, e.g. `campaign position 3 / 12`. Wire it into `run()` for notes and into the
   plugin's "Lint level" output.
7. Authoring ergonomics, which is half the point: the `LEVEL_AUTHORING.md` checklist loses "wire the
   exit", the stale `Level.next_level` rows are deleted, and adding a level becomes "save the scene,
   add its path to `LEVELS`". Have the lint name the file when an open level is not registered.
8. `docs/DESIGN_NOTES.md`: record the decision (one table, exits derive the chain) with the reason.

**Files.** `src/campaign/campaign_library.gd` (new), `src/autoload/game_director.gd`,
`src/levels/exit_zone.gd`, `src/levels/level.gd`, `src/levels/level_lint.gd`,
`src/levels/level_*.tscn`, `dev/build_levels.gd`, `docs/LEVEL_AUTHORING.md`, `docs/DESIGN_NOTES.md`.

**Verify.** Extend `--probe=lint` so it walks the whole table: instantiate each level under a hidden
holder, run `LevelLint.run()`, free it, and print one PASS/FAIL line per level. Also assert
`next_after(last).is_empty()` and that every `next_after()` path exists. Then play
`level_campaign_01 → 04` end to end with `--probe=flow`.

**Done when.** The four campaign levels chain with no per-exit wiring, the linter covers every level
in the table, and adding a level is one line plus one scene.

**Watch out.** Removing `PackedScene` exports changes the `.tscn` files; do it with the editor open or
by hand and re-run `--import`, because a stale `uid://` reference is a load-time error rather than a
warning.

---

## 4. Rebindable input (keyboard and mouse)

**Status: done.** Defaults are data (`GameInput.DEFAULT_SPECS`) and an override is written per action to
`user://bindings.cfg`; `register_all()` builds the map from both. The settings menu has a **Controls**
panel (grouped, scrollable, one button per action, Esc backs out one level), conflicts are refused by
name, and **Reset all controls** restores the shipped defaults. The title screen builds its table from
the live map, so a rebind shows up there. `--probe=rebind` covers the whole path including a capture
applied through the panel. Gamepad bindings are task 5's job and slot into the same store.

**Goal.** Every gameplay action can be rebound in the settings menu, conflicts are impossible, the
title screen shows the current bindings, and defaults can be restored.

**Why.** Release blocker, agreed. The current design fights it: `GameInput.KEY_BINDINGS` is a `const`
and `register_all()` rebuilds the `InputMap` from it on every boot, so bindings are code. The title
screen's `CONTROLS_TEXT` is a hand-written string, so any rebind makes it lie.

**Steps.**

1. `src/autoload/game_input.gd`: split the constants into `DEFAULT_EVENTS` (action → `Array[InputEvent]`,
   built in a function because `const` cannot hold objects) and `META` (action → display label and
   group: Movement / Combat / Interaction / System). Keep debug actions in their own group so they can
   be hidden or rebound separately.
2. Persistence: `user://bindings.cfg`, following the shape `Progress` and `Settings` already use. One
   entry per action holding an array of serialised events
   (`{type="key", physical_keycode=87}`, `{type="mouse", button=1}`). Absence of an entry means "use
   the default", so a new action in a later version still works for an old save.
3. Same file: `register_all()` builds `InputMap` from defaults and then applies overrides; add
   `rebind(action, events)`, `reset_action(action)`, `reset_all()`, `save_bindings()`,
   `load_bindings()`, a `bindings_changed` signal, and `describe(event) -> String` for UI ("W", "LMB")
   and for the title screen.
4. Keep `physical_keycode` (already the case): bindings must survive a layout change, and the reason is
   worth a comment so it is not "simplified" later.
5. `src/ui/settings_menu.gd`: add a Controls section listing actions by group, each row a button that
   captures the next event (`_input`, filtered to key/mouse), Esc cancels, and a "Reset all" button.
   On capture, scan the other actions with `InputEvent.is_match()` and refuse or swap on conflict
   rather than allowing two actions on one key. The settings menu is built in code like the HUD, so
   this is a panel, not a scene.
6. `src/ui/title_screen.gd` / `GameInput.CONTROLS_TEXT`: generate the controls block from the live
   bindings (first event per action) instead of the hard-coded string.
7. `docs/DESIGN_NOTES.md`: a row for "bindings are data, defaults are code" with the reverse path.

**Files.** `src/autoload/game_input.gd`, `src/ui/settings_menu.gd`, `src/ui/title_screen.gd`,
`docs/DESIGN_NOTES.md`.

**Verify.** Extend `--probe=input` (it already registers and simulates presses): rebind `reload` to
`K`, simulate it, assert `Input.is_action_pressed(&"reload")`; attempt a conflicting bind and assert
it is refused; save, reload `GameInput` from disk, and assert the override survived; `reset_all()` and
assert the default is back. Also assert the generated controls text contains the new key.

**Done when.** A rebind survives a restart, conflicts are refused, the title screen matches the live
map, and defaults restore in one click.

**Watch out.** Do not reimplement menu navigation: `ui_*` actions stay on the engine defaults, and
`MenuList` already relies on `Control` focus. Rebinding gameplay actions must not touch them.

---

## 5. Gamepad support, including Steam Deck

**Status: done.** Aim is four actions (`aim_up/down/left/right`, right stick by default), so it lives in
the same rebindable map as everything else; the player keeps the last aim when the stick is released.
Pad buttons and stick axes are in `DEFAULT_SPECS` side by side with keys, and the Controls panel
captures `InputEventJoypadButton` and `InputEventJoypadMotion` into the same `bindings.cfg`. The player
and HUD follow the last device used (`GameInput.using_gamepad()`), and the built-in `ui_*` actions get
pad events added without disturbing their keyboard defaults, so menus are navigable with A/B and the
D-pad. `1280x800` is in the resolution list. `--probe=gamepad` injects real joypad events through the
input loop and checks movement, aim + deadzone + persistence, trigger fire, Start pause, UI navigation,
device-aware prompts, and a pad-button rebind.

**Goal.** The game is playable start to finish with only a controller, at 1280x800, with prompts that
match the device in hand, and with pad buttons rebindable through task 4's UI.

**Why.** Steam release, and Steam Deck/Machine is a controller-first platform. The risky part is not
the buttons: it is aiming a vision cone with a stick, which is a feel problem the keyboard/mouse
design never had to solve.

**Steps.** Do 1 first as a spike; if aiming does not feel right, the rest of the task is not worth
building.

1. **Aim source.** `src/player/player.gd` currently derives `aim_direction` from
   `get_global_mouse_position()`, and `_update_camera_offset()` uses mouse *distance* for look-ahead.
   Add an aim source:
   - `GameInput.aim_vector(deadzone) -> Vector2` returns the right stick vector when it clears the
     deadzone, otherwise `Vector2.ZERO`.
   - `Player` uses the stick when it is non-zero and otherwise keeps the last direction, so releasing
     the stick does not snap the cone to the right.
   - Keep it **screen-relative**, like movement: push right = aim right, never "aim relative to where
     the character faces".
   - Camera look-ahead uses the stick magnitude (or a fixed offset toward the aim) instead of mouse
     distance. Both constants already exist (`Tuning.camera_aim_offset*`).
   - Add `Tuning` values for deadzone and an aim response exponent; tune them on a pad, not by number.
2. **Bindings.** `src/autoload/game_input.gd`: add `JOY_BUTTONS` (action → `Array[JoyButton]`) and a
   stick table for `move_*` / aim. Register `InputEventJoypadButton` and `InputEventJoypadMotion`
   (axis + direction, threshold) so `Input.is_action_pressed` and `Input.get_vector` work unchanged.
   Default mapping worth starting from: left stick move, right stick aim, RT fire, X reload, Y
   interact, LB dash, RB switch, LB/RB + face buttons or the D-pad for abilities, Start pause.
3. **Device switching.** `GameInput` records the last device that produced input
   (`_input()` switching on `InputEventKey`/`MouseButton` vs `Joypad*`), exposed as
   `active_device()`. Use it for every prompt. Steam Deck starts on pad because a pad produced the
   input; plugging a keyboard flips it.
4. **Prompts.** `HUD` ability/weapon labels and the title screen's controls block read
   `GameInput.describe(event)`, which gains pad names ("A", "RT", "LB"). A text first pass is fine;
   glyph sprites can come later without touching the plumbing.
5. **Menus.** Verify title, settings and pause are fully navigable on a pad: `MenuList` already uses
   `Control` focus and Godot's default `ui_*` actions include joypad accept/cancel, so this should be
   verification rather than work. Fix anything that requires the mouse (hover-only affordances,
   the new rebinding UI included).
6. **Rebinding.** Extend task 4's capture to accept `InputEventJoypadButton` and
   `InputEventJoypadMotion` (axis plus sign) and persist them with the already event-based format.
7. **Steam Deck specifics.**
   - Add `1280x800` to `Settings.COMMON_SIZES`; it is the Deck's native panel and is currently missing.
   - Run the `presentation` probe at 1280x800 and check HUD legibility and that nothing clips; the
     project has no stretch mode by design, so this is a real check.
   - Verify fullscreen start-up and that the pause menu is reachable with Start (not only Esc).
   - Decide explicitly: native `InputEventJoypad*` (recommended, simple, no dependency) versus Steam
     Input action sets (better remapping, more moving parts, Steam-only). Record the choice in
     `DESIGN_NOTES.md`.
8. **Testing without a pad.** Godot can inject pad events: build `InputEventJoypadButton` /
   `InputEventJoypadMotion` and send them with `Input.parse_input_event()`, the same way the existing
   probes fake keys.

**Files.** `src/player/player.gd`, `src/autoload/game_input.gd`, `src/ui/hud.gd`,
`src/ui/title_screen.gd`, `src/ui/settings_menu.gd`, `src/autoload/settings.gd`,
`src/autoload/tuning.gd`, `docs/DESIGN_NOTES.md`.

**Verify.** New `--probe=gamepad`: inject left-stick motion and assert the player moved along the
expected axis; inject right-stick motion and assert `aim_direction` follows it and *stays* after the
stick returns to zero; inject fire/reload/interact and assert they fire; inject a deadzone-sized
right-stick move and assert the aim did not change; navigate the title menu with the D-pad and
activate an item with the accept button; rebind a pad button and assert it persists. Then play one
campaign level start to finish with only a pad.

**Done when.** A controller-only playthrough of the first level works at 1280x800, prompts match the
device, and the sticks are tunable from `Tuning`.

**Watch out.** Aiming must not become "twin-stick shooter" aiming: the cone is the game, so the stick
should be a direction with a deliberate deadzone and a gentle response, not a free cursor. Tune with
the cone visible, at the default zoom.

---

## 6. Level select after finishing

**Status: done.** Reaching the final exit sets `Progress.finished`, persisted in
`user://progress.cfg` and kept across new games. The title screen's LEVEL SELECT item is greyed until
then, and opens a picker built from `CampaignLibrary`. Choosing a level calls
`GameDirector.start_selected_level()`: a practice run with every weapon at max level and full reserve,
no abilities, `Progress.record()` suppressed so the campaign checkpoint is never touched, and the level's
exit routed to the picker (`open_level_select_pending`). `--probe=level_select` covers the unlock flag on
disk, the picker, the practice loadout, an untouched checkpoint, and the return to the picker.

**Goal.** After the final exit, the title screen offers a level select; levels are replayable
individually.

**Why.** Players who finish a 2-hour game will want to revisit a favourite level or hunt a missed
upgrade, and the campaign table (task 3) makes it cheap. Low priority: it is worth nothing until the
last level exists.

**Steps.**

1. `Progress`: a `finished` flag, persisted in `progress.cfg`, set on the campaign's final exit and kept
   separately from the checkpoint (`clear_checkpoint()` in a new game must not clear it; `reset()`
   wipes everything).
2. `GameDirector`: `start_at(path)` that begins a run on a chosen level with an empty loadout, or
   restores a per-level snapshot if the design wants replay with progression (decide then).
3. Title screen: if `progress.completed` covers the campaign, add a "Level select" item that opens a
   menu built from `CampaignLibrary` -- one button per level with its position and title, locked unless
   completed.
4. Probe: `--probe=menus` extension for the select list and a completed-set round trip.

**Done when.** Finishing the campaign unlocks a list of every level, each launches correctly, and New
Game still starts from the first.

---

## 7. Steam release plumbing

**Goal.** A shipping build and the Steam features that are cheap to add and expensive to retrofit.

**Steps.** These depend on tasks 3-6 and none of them change the game:

1. Export presets (Windows first), a version string in the title screen, and a clean `user://` layout
   (`progress.cfg`, `settings.cfg`, `bindings.cfg`) -- Steam Auto-Cloud syncs that folder.
2. Achievements: the counters already exist (`kills`, `levels_cleared`, `progress.completed`), so this
   is a mapping plus the Steamworks calls; keep it out of gameplay code behind one interface.
3. Store page assets, a launch trailer, and a short "how long is it" answer taken from a real
   playthrough rather than the design target.
4. Controller glyph pass for Steam Deck (physical vs virtual button names) once task 5 settles which
   input API is used.

---

## Later, not scheduled

- Retire `level_01..03` ("THE YARD", "THE DEPOT", "TEMPLATE"): they are not in the chain any more, and
  leaving them is how someone later edits the wrong `level_01`.
- Decide what an ability pickup does when both slots are already full (it currently stays on the
  ground, which is fine until there are more abilities than slots).
- A settings "restore all defaults" that covers video, audio and bindings in one action.
