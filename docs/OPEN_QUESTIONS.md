# Open questions

Design decisions that are not made yet. Not a task list: each line is a question with the
constraint that will shape the answer, and they are ordered by how much they would change.

## Campaign shape

- **Chain, tree, or hub?** Exits already support per-exit `next_level`, so branching is nearly free
  mechanically, but it decides how much level budget goes into routes a player may never see, and
  what "Continue" should mean if a player can miss a branch.
- **How long is the game?** Everything about pacing and difficulty tuning depends on the answer.

## Systems

- **Mid-level saving?** The checkpoint stores the level and the loadout, and Continue restarts the
  level. A real save means serialising position, enemy states and loot taken — and keeping it valid
  every time a level is re-edited.
- **Consumables and the talent tree.** `Health` is a component and abilities have upgrade levels, so
  the plumbing exists, but nothing has decided what the player spends or chooses.
- **Keybinds and controller support.** Both are publisher-facing rather than fun-facing. Keybinds
  are currently a table in `GameInput`; gamepad support needs stick aiming that feels right with a
  vision cone.

## Presentation

- **Real art and audio.** Swapping the code-drawn placeholders for sprites and animations touches
  the player, enemies, walls, doors, pickups, exits and effects, and needs an animation state per
  entity. Worth budgeting as a distinct chunk of work, not a gradual swap.
- **Per-pixel player visibility.** The vision cone is a light with soft edges; the last approximation
  in the vision tech. Only worth doing if the softness actually reads badly in real content.
- **Enemy-vs-enemy avoidance.** Guards converging currently occupy the same pixel. Small, cosmetic.
