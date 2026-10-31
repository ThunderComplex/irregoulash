class_name WeaponResource
extends Resource
## Data for one weapon. All balance lives here, so a new weapon is one entry in
## `WeaponLibrary` and nothing else.

@export var id: StringName = &"pistol"
@export var display_name: String = "Pistol"
## Used for the HUD grouping and pickup labelling.
@export var category: String = "pistol"
@export var damage: float = 12.0
## Shots per second.
@export var fire_rate: float = 5.0
@export var automatic: bool = false
## Bullets per trigger pull.
@export var pellets: int = 1
## Base inaccuracy cone in degrees.
@export var spread_deg: float = 1.5
## How much the crosshair blooms per shot.
@export var recoil_kick: float = 0.5
## Bullet travel distance in pixels.
@export var max_range: float = 720.0
@export var projectile_speed: float = 1500.0
@export var mag_size: int = 12
@export var reload_time: float = 1.1
@export var reserve_max: int = 150
## Screen shake per shot (0..1 trauma).
@export var shake: float = 0.16
## Push applied to whatever is hit.
@export var knockback: float = 50.0
@export var color: Color = Color(1.0, 0.92, 0.6)
@export var sfx: StringName = &"shot_pistol"
## 0 = use Tuning.noise_gunshot. Bigger guns are louder and give you away further.
@export var noise_radius: float = 0.0
## Ammo granted by an ammo pickup for this weapon.
@export var ammo_pickup: int = 24
## Placeholder silhouette size, drawn in the player's hands.
@export var silhouette: Vector2 = Vector2(22.0, 6.0)
@export var pickup_color: Color = Color(0.75, 0.8, 0.9)


func cooldown() -> float:
	return 1.0 / maxf(0.05, fire_rate)


func noise() -> float:
	if noise_radius > 0.0:
		return noise_radius
	return Tuning.noise_gunshot
