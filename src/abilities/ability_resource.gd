class_name AbilityResource
extends Resource
## Data for one ability.
##
## Balance lives here and in `AbilityLibrary`, exactly like weapons: the holder only
## needs to know *how to aim* and *when it may fire*, and the effect knows the rest. That
## split is what keeps every ability from turning into another branch in one function.

## How the cursor position is turned into a target.
enum Targeting {
	## At the cursor, clamped to `max_range`. Used by fire_wall and fire_tempest.
	POINT,
	## Along the aim direction away from the caster. Used by lightning_bolt.
	DIRECTION,
	## On the caster itself. Reserved for a future self-buff.
	SELF,
}

@export var id: StringName = &"ability"
@export var display_name: String = "Ability"
@export var description: String = ""
@export var targeting: Targeting = Targeting.POINT
@export var cooldown: float = 1.0
## The script spawned and run on a successful cast. Keep it to a script rather than a
## scene, matching `Projectile`: the visuals are built in code like every other entity
## here, so a scene would hold nothing but a script reference.
@export var effect: Script
@export var color: Color = Color(1.0, 0.62, 0.25)
@export var sfx: StringName = &"cast_fire"

@export_group("Aiming")
## POINT abilities land at most this far from the caster.
@export var max_range: float = 420.0
## POINT abilities that need room to be placed (a fire wall does; an explosion does not),
## and are refused rather than placed inside geometry.
@export var requires_clear_space: bool = false
## Radius of that clearance check.
@export var placement_radius: float = 56.0

@export_group("Effect")
@export var damage: float = 14.0
## Damage is applied every this many seconds while something is inside the effect.
@export var tick_interval: float = 0.4
@export var duration: float = 5.0
## Rectangular effects (the fire wall) use `area_size`; circular ones (the tempest) use
## `area_radius`.
@export var area_size: Vector2 = Vector2(176.0, 40.0)
@export var area_radius: float = 96.0
@export var projectile_speed: float = 1700.0
@export var projectile_range: float = 700.0
## 0 means silent. Abilities that make no noise would be a free pass in a stealth game,
## so every entry in the library sets this.
@export var noise_radius: float = 900.0
@export var shake: float = 0.2

@export_group("Upgrades")
## Growth per upgrade level, applied by `AbilitySlot`.
@export var damage_per_level: float = 0.25
@export var area_per_level: float = 0.18
@export var cooldown_per_level: float = 0.12
