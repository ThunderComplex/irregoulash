class_name EnemyArchetype
extends Resource
## Data for one kind of enemy. Like weapons, these live in code in
## `EnemyLibrary` so tuning is one edit and levels reference them by name.

@export var id: StringName = &"guard"
@export var display_name: String = "Guard"

@export_group("Body")
@export var max_health: float = 55.0
@export var radius: float = 13.0
@export var speed_patrol: float = 62.0
@export var speed_alert: float = 132.0
@export var body_color: Color = Color(0.85, 0.4, 0.34)

@export_group("Perception")
@export var sight_range: float = 430.0
@export var sight_fov: float = 105.0
## Scales how fast awareness builds. A scout notices you sooner.
@export var detect_multiplier: float = 1.0
## Alerts nearby friends when it finds you.
@export var shouts: bool = true

@export_group("Combat")
@export var damage: float = 9.0
@export var pellets: int = 1
## Seconds between shots inside a burst.
@export var fire_interval: float = 0.22
## Shots per burst, then a pause.
@export var burst: int = 3
@export var burst_pause: float = 0.75
@export var spread_deg: float = 5.0
@export var fire_range: float = 520.0
@export var reaction_time: float = 0.42
## Enemy closes to roughly this distance while hunting.
@export var preferred_range: float = 260.0
## Drops this weapon when killed ("" for nothing).
@export var drop_weapon: String = ""
@export var footstep_audible_range: float = 260.0
