class_name Layers
extends RefCounted
## Physics layer bits and draw depths in one place, so nothing in the project
## compares a raw integer against a magic number.

# Physics layers (must match the names in project.godot -> [layer_names]).
const WORLD: int = 1 << 0 # walls, level geometry
const PLAYER: int = 1 << 1
const ENEMY: int = 1 << 2
const PLAYER_SHOT: int = 1 << 3
const ENEMY_SHOT: int = 1 << 4
const PICKUP: int = 1 << 5
## An *open* door leaf. Solid to the player, sight and bullets, but not to enemy movement.
##
## A shut door is on WORLD like a wall, because it must stop everything until someone opens it. An open
## leaf is different: it is a physical panel standing in the room, and enemies have no way to steer
## around one -- the navmesh does not include doors, so their paths ran straight through it and they
## ground to a halt. Putting the open leaf on its own layer keeps every property that matters (cover,
## bullets, sight, the player's feet) and gives enemies a clear route past it.
const DOOR: int = 1 << 6
## Blocks sight and nothing else: no movement, no bullets. A fire wall is on it, so it hides both
## sides from each other while anyone can walk (and burn) through it or shoot blind across it.
const SIGHT_ONLY: int = 1 << 7

## Everything solid that blocks *movement*. Walls, and shut doors.
const SOLID: int = WORLD
## What blocks sight: walls, a door leaf whether it is open or shut, and sight-only blockers.
const SIGHT_BLOCKERS: int = WORLD | DOOR | SIGHT_ONLY
## What a bullet fired by the player can hit.
const PLAYER_SHOT_HITS: int = WORLD | DOOR | ENEMY
## What a bullet fired by an enemy can hit.
const ENEMY_SHOT_HITS: int = WORLD | DOOR | PLAYER

# Draw order. Walls sit above actors (top-down readability), memory of explored
# geometry sits below everything that is actually there.
const Z_FLOOR: int = -20
const Z_MEMORY: int = -10
const Z_DECAL: int = -5
const Z_PICKUP: int = 0
const Z_ACTOR: int = 10
const Z_WALL: int = 20
const Z_WALL_EDGE: int = 30
const Z_FX: int = 70
