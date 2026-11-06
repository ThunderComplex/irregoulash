# Open questions

Design questions that are genuinely undecided. Answered ones are kept at the bottom for the record;
the decisions they produced live in `docs/DESIGN_NOTES.md`, and the work they created lives in
`docs/TASKS.md`.

## Still open

- **How much Steam, exactly?** Achievements and cloud saves are cheap and worth doing; leaderboards,
  Workshop or a level editor are a different product. Decide before the store page, because the page
  promises it. See task 7 in `docs/TASKS.md`.
- **What does Continue mean after the campaign is finished?** The checkpoint is cleared on a win, so a
  finished game offers New Game only. A level select (task 6) needs to answer whether replaying a
  level restores the progression you had, or starts that level from a fixed loadout.
- **Upgrade caps.** Task 2 proposes 3 for both weapons and abilities, so a late crate is not wasted and
  damage does not run away. It is a balance number to settle in playtesting, not a design question --
  but it has to exist before upgrade crates are placed.
- **What happens to an ability pickup when both slots are full?** It currently stays on the ground.
  That is fine with three abilities and two slots; it stops being obvious if the roster grows.

## Answered

Kept verbatim so the answers are not lost; the condensed decisions are in `docs/DESIGN_NOTES.md`.

### Campaign shape

> The campaign is a chain, and this will never deviate. I might want the player to unlock a level
> select once he's finished with the game.

→ Task 3 (one ordered table) and task 6 (level select after the ending).

### How long is the game?

> The game should be long enough to warrant a $4/4€ price tag. But since the game is also relatively
> small in terms of mechanics making it too long would be detrimental. I'm thinking somewhere around
> 2-2.5 hours.

→ About a dozen hand-authored levels at ~10 minutes each. The level count is the real constraint; the
hours fall out of it.

### Mid-level saving?

> No, the checkpoint per level is fine. Levels won't be big enough to seriously warrant mid-level
> saving.

→ No work. It also sets a practical ceiling on level length, because dying restarts the level.

### Consumables and the talent tree

> Not necessary and too overkill. Medkit pickups are enough. However, ability upgrade pickups similar
> to weapon upgrade pickups would be a good idea.

→ Task 1 (carry abilities) and task 2 (one crate raises both slots), because abilities are currently
per-level, so upgrades would evaporate at the next exit.

### Keybinds and controller support

> Fully rebindable keys are a must before this game is properly released.

And, in the discussion that followed: the release target is Steam, where the game may be played on
Steam Deck/Machine and with controllers, so gamepad support is in scope too.

→ Task 4 (rebindable input) and task 5 (gamepad, including Deck at 1280x800).
