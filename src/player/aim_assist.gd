class_name AimAssist
extends RefCounted
## Bends right-stick aim towards an enemy the player is already pointing at. A stick is far less precise
## than a mouse, and the game's enemies are small.
##
## The stick stays in charge. Only an enemy within a narrow cone of the stick pulls the aim, and the pull
## fades to nothing at the cone's edge, so pushing the stick away always breaks free. With the stick on
## the enemy itself, the aim settles on its centre.
##
## It only helps with a shot the player could already take: the enemy has to be visible to them, and the
## path from the barrel has to be clear. Enemies in the dark, behind a wall or behind a fire wall pull
## nothing, so the assist cannot be used to find them.

## The pull is offset from the stick's angle, and eased, so aim glides on and off a target instead of
## snapping when one comes into range or dies.
var _offset: float = 0.0


## Where to aim, given the stick's direction this frame.
func aim(player: Player, stick: Vector2, delta: float) -> Vector2:
	var stick_angle: float = stick.angle()
	var wanted: float = _wanted_offset(player, stick_angle)
	_offset = lerpf(_offset, wanted, 1.0 - exp(-Tuning.gamepad_assist_rate * delta))
	return Vector2.from_angle(stick_angle + _offset)


## Forget the pull, for when the stick is let go.
func reset() -> void:
	_offset = 0.0


## The turn from the stick's angle to the best target's, scaled by how close the stick is to it.
func _wanted_offset(player: Player, stick_angle: float) -> float:
	var cone: float = deg_to_rad(Tuning.gamepad_assist_cone_degrees)
	var candidates: Array[Dictionary] = []
	for node: Node in player.get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var distance: float = player.global_position.distance_to(enemy.global_position)
		if distance > Tuning.sight_far_range:
			continue
		var barrel_angle: float = player.barrel_aim(enemy.global_position).angle()
		var turn: float = angle_difference(stick_angle, barrel_angle)
		# How wide the enemy looks from here. Inside that the stick is on target and the pull is full.
		var body: float = atan2(enemy.archetype.radius, maxf(distance, 1.0))
		if absf(turn) <= body + cone:
			candidates.append({"enemy": enemy, "angle": barrel_angle, "turn": turn, "body": body})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(a["turn"]) < absf(b["turn"]))
	for candidate: Dictionary in candidates:
		if _can_hit(player, candidate["enemy"], candidate["angle"]):
			var body: float = candidate["body"]
			var turn: float = candidate["turn"]
			return turn * (1.0 - smoothstep(body, body + cone, absf(turn)))
	return 0.0


func _can_hit(player: Player, enemy: Enemy, barrel_angle: float) -> bool:
	if not GameDirector.player_sees(enemy.global_position):
		return false
	var ray := PhysicsRayQueryParameters2D.create(player.muzzle_position_at(barrel_angle),
		enemy.global_position, Layers.PLAYER_SHOT_HITS, [player.get_rid()])
	# Point blank the muzzle can be inside the enemy, which still counts as a hit.
	ray.hit_from_inside = true
	var hit: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit["collider"] == enemy
