extends Node
## Single source of truth for every gameplay number.
##
## This node is an autoload, so during play you can select it in the editor's
## *Remote* scene tree and tweak any value live. Nothing else in the project
## should hard-code a gameplay constant.

#region Player
@export_group("Player")
## Pixels per second. Movement is always screen-relative (W is up).
@export var player_speed: float = 195.0
@export var player_accel: float = 1900.0
@export var player_friction: float = 2200.0
@export var player_radius: float = 14.0
@export var player_max_health: float = 100.0
@export var player_hit_invuln: float = 0.5
@export var player_dash_speed: float = 620.0
@export var player_dash_time: float = 0.16
@export var player_dash_cooldown: float = 1.1
## How close the player has to be to work a door, measured from the door's surface.
@export var player_interact_range: float = 60.0
## Noise radius created by each action. Enemies inside it gain awareness.
@export var noise_footstep: float = 130.0
@export var noise_dash: float = 300.0
@export var noise_gunshot: float = 950.0
#endregion

#region Doors
@export_group("Doors")
## Seconds for the leaf to swing open or shut. Short enough not to feel like waiting.
@export var door_open_time: float = 0.22
## An enemy that opened a door shuts it again once it is this far past it.
@export var door_close_distance: float = 52.0
## Opening or closing a door. Quiet, but not silent: a door tells you someone is moving.
@export var noise_door: float = 420.0
## Dashing an unlocked door off its hinges. This is the loud option.
@export var noise_door_smash: float = 700.0
## Trying a locked door by hand: a rattle, heard only nearby.
@export var noise_door_locked: float = 120.0
## Dashing into a locked door: louder than trying it, quieter than breaking one.
@export var noise_door_smash_locked: float = 380.0
## A door bouncing off whoever is standing in the doorway: barely more than breathing.
@export var noise_door_bump: float = 110.0
#endregion

#region Vision
@export_group("Vision")
## Radius of the "you can feel something right next to you" ring, in pixels.
@export var sight_near_radius: float = 115.0
@export var sight_near_energy: float = 0.7
## The aim cone.
@export var sight_far_range: float = 560.0
@export var sight_far_degrees: float = 78.0
@export var sight_far_energy: float = 1.0
## Darkness colour. Pitch black = enemies outside your light are *really* invisible.
@export var fog_color: Color = Color(0, 0, 0, 1)
## Brightness of explored (already seen) geometry memory. Enemies are never remembered.
@export var memory_brightness: float = 0.30
@export var memory_sample_interval: float = 0.12
#endregion

#region Enemies
@export_group("Enemies")
@export var enemy_sight_range: float = 430.0
@export var enemy_sight_fov: float = 105.0
## Awareness (0..1) gained per second while the player is visible, at point blank.
@export var awareness_gain_close: float = 2.6
## Awareness gained per second at the very edge of sight.
@export var awareness_gain_far: float = 0.55
## Multiplier when the player is standing in the player's own light (you light them up).
@export var awareness_lit_multiplier: float = 1.8
## Awareness lost per second when the player is not visible.
@export var awareness_decay: float = 0.42
@export var awareness_suspicious: float = 0.35
@export var awareness_alert: float = 1.0
## How long an enemy keeps chasing after losing sight before searching.
@export var alert_lost_sight_grace: float = 1.0
@export var search_duration: float = 20.0
## How far a search reaches, as a fraction of how far the player could have run since they were last
## seen. Under 1.0 because the player has to stop, turn and shoot too; raise it to make searches
## wider and meaner.
@export var search_budget_factor: float = 0.6
## Ceiling on a search radius, so a long chase does not turn into a level-wide sweep.
@export var search_budget_max: float = 900.0
@export var suspicious_look_time: float = 1.2
@export var take_damage_guess_distance: float = 300.0
## Radius in which a shouting enemy alerts its friends.
@export var shout_radius: float = 520.0
@export var shout_cooldown: float = 5.0
## Enemy body
@export var enemy_radius: float = 13.0
#endregion

#region Combat
@export_group("Combat")
@export var player_bullet_speed: float = 1500.0
@export var enemy_bullet_speed: float = 780.0
## Enemy reaction delay between seeing you and firing.
@export var enemy_reaction_time: float = 0.42
@export var enemy_burst_pause: float = 0.65
## Extra inaccuracy (degrees) added to enemy shots at max range.
@export var enemy_extra_spread: float = 7.0
## How long the terrain remembers a bullet hole.
@export var decal_lifetime: float = 12.0
#endregion

#region Audio
@export_group("Audio")
@export var sfx_volume_db: float = -6.0
@export var music_volume_db: float = -18.0
#endregion

#region Camera / feel
@export_group("Camera / feel")
@export var camera_smoothing: float = 8.0
## Nudge the camera slightly toward where the player is aiming.
@export var camera_aim_offset: float = 0.18
@export var camera_aim_offset_max: float = 110.0
@export var shake_decay: float = 3.4
@export var shake_max_offset: float = 26.0

@export_group("Resolution independence")
## How much world is visible vertically, in pixels, whatever the window size. The camera
## zooms to keep this constant, so the vision cone covers the same share of the screen at
## any resolution -- which is what stops a 4K window from being mostly black.
## (The old hardcoded pairing was a 720-tall viewport at zoom 0.9, i.e. 800.)
@export var camera_visible_height: float = 800.0
## The height the HUD is laid out for. Every HUD dimension and font size is scaled from
## this, so the interface looks the same at 800x600 and at 4K.
@export var ui_reference_height: float = 720.0
#endregion
#endregion
