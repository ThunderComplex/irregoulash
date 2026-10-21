class_name Layers
extends RefCounted
## Physics layer bits and draw depths in one place, so nothing in the project
## compares a raw integer against a magic number.

# Physics layers (must match the names in project.godot -> [layer_names]).
const WORLD: int = 1 << 0          # walls, level geometry
const PLAYER: int = 1 << 1
const ENEMY: int = 1 << 2
const PLAYER_SHOT: int = 1 << 3
const ENEMY_SHOT: int = 1 << 4
const PICKUP: int = 1 << 5

## Everything solid that blocks movement.
const SOLID: int = WORLD
## What a bullet fired by the player can hit.
const PLAYER_SHOT_HITS: int = WORLD | ENEMY
## What a bullet fired by an enemy can hit.
const ENEMY_SHOT_HITS: int = WORLD | PLAYER

# Draw order. Walls sit above actors (top-down readability), memory of explored
# geometry sits below everything that is actually there.
const Z_FLOOR: int = -20
const Z_MEMORY: int = -10
const Z_DECAL: int = -5
const Z_PICKUP: int = 0
const Z_ACTOR: int = 3
const Z_WALL: int = 6
const Z_WALL_EDGE: int = 7
const Z_FX: int = 60
