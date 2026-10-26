class_name LightningBolt
extends AbilityEffect
## A bolt fired from the caster towards the cursor: the DIRECTION-targeting ability.
##
## It spawns the same `Projectile` that bullets use, which is the whole point of the
## targeting split -- the holder never learns that this ability is a projectile while the
## other two are areas.

func begin(caster: Node2D, target: Vector2, slot: AbilitySlot) -> bool:
	var data: AbilityResource = slot.data
	var to_target: Vector2 = target - caster.global_position
	if to_target.length_squared() < 1.0:
		return false
	var direction: Vector2 = to_target.normalized()
	var origin: Vector2 = caster.global_position + direction * 22.0

	var parent: Node = GameDirector.spawn_parent()

	var bullet := Projectile.new()
	bullet.damage = slot.damage()
	bullet.hits_mask = Layers.PLAYER_SHOT_HITS
	bullet.shooter = caster
	bullet.max_distance = data.projectile_range
	bullet.color = data.color
	bullet.knockback = 150.0
	bullet.show_orb = false
	parent.add_child(bullet)
	bullet.launch(origin, direction, data.projectile_speed)

	# A brief, bright streak, so it reads as lightning rather than a slow bullet.
	var bolt := Line2D.new()
	bolt.points = PackedVector2Array([origin, origin + direction * 110.0])
	bolt.width = 3.0
	bolt.default_color = data.color
	bolt.material = FxDirector.unshaded_material()
	bolt.z_index = Layers.Z_FX + 1
	parent.add_child(bolt)
	var tween: Tween = bolt.create_tween()
	tween.tween_property(bolt, "modulate:a", 0.0, 0.12)
	tween.tween_callback(bolt.queue_free)

	FxDirector.flash_light(origin, data.color, 1.3, 160.0, 0.12)
	# The effect itself is done; the projectile outlives it.
	lifetime = 0.05
	return true
