class_name Pickup
extends Area2D
## World pickup: weapons, ammo, weapon upgrades and medkits.
##
## Pickups carry their own light and an unshaded marker, because a pickup you
## cannot see in pitch darkness is a pickup that does not exist. They pulse
## gently so they read as "interactable" and are findable across a dark room.

@export_enum("weapon", "ammo", "upgrade", "health") var kind: String = "weapon"
@export_enum("pistol", "smg", "shotgun") var weapon_id: String = "smg"
@export var amount: int = 24

var _t: float = 0.0
var _light: PointLight2D = null
var _marker: Polygon2D = null
var _collected: bool = false


func _ready() -> void:
	var collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D
	if collision != null and collision.shape == null:
		var shape := CircleShape2D.new()
		shape.radius = 20.0
		collision.shape = shape
	body_entered.connect(_on_body_entered)
	_build_art()


func _build_art() -> void:
	var color: Color = _pickup_color()

	_light = PointLight2D.new()
	_light.texture = VisionTextures.radial()
	_light.texture_scale = 130.0 * 2.0 / float(VisionTextures.SIZE)
	_light.color = color
	_light.energy = 0.55
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.z_index = Layers.Z_ACTOR
	add_child(_light)

	_marker = Polygon2D.new()
	# Medkits are drawn as a cross so they read differently at a glance.
	if kind == "health":
		_marker.polygon = PackedVector2Array([
			Vector2(-8.0, -3.0), Vector2(-3.0, -3.0), Vector2(-3.0, -8.0), Vector2(3.0, -8.0),
			Vector2(3.0, -3.0), Vector2(8.0, -3.0), Vector2(8.0, 3.0), Vector2(3.0, 3.0),
			Vector2(3.0, 8.0), Vector2(-3.0, 8.0), Vector2(-3.0, 3.0), Vector2(-8.0, 3.0),
		])
	else:
		_marker.polygon = Shapes.circle(9.0, 6)
	_marker.color = color.lightened(0.2)
	_marker.material = FxDirector.unshaded_material()
	_marker.z_index = Layers.Z_PICKUP + 1
	add_child(_marker)

	var ring := Line2D.new()
	ring.points = Shapes.closed_outline(Shapes.circle(15.0, 16))
	ring.width = 2.0
	ring.default_color = color
	ring.material = FxDirector.unshaded_material()
	ring.modulate.a = 0.5
	ring.z_index = Layers.Z_PICKUP
	add_child(ring)


func _process(delta: float) -> void:
	_t += delta
	var pulse: float = 0.5 + 0.5 * sin(_t * 2.6)
	if _light != null:
		_light.energy = 0.35 + pulse * 0.4
	if _marker != null:
		_marker.scale = Vector2.ONE * (0.9 + pulse * 0.18)

	# Also poll: a weapon dropped by a dying enemy can land underneath the player.
	if not _collected:
		for body: Node2D in get_overlapping_bodies():
			var player := body as Player
			if player != null and not player.is_dead():
				_try_collect(player)
				return


func _pickup_color() -> Color:
	match kind:
		"ammo":
			return Color(0.65, 0.85, 1.0)
		"upgrade":
			return Color(1.0, 0.7, 0.95)
		"health":
			return Color(0.5, 1.0, 0.6)
		_:
			return WeaponLibrary.by_id(weapon_id).pickup_color


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or player.is_dead():
		return
	_try_collect(player)


func _try_collect(player: Player) -> void:
	if _collected:
		return
	var holder := player.weapons as WeaponHolder

	match kind:
		"ammo":
			if holder == null:
				return
			holder.add_ammo(amount)
			AudioDirector.play_at(&"pickup", global_position, -4.0)
			GameDirector.announce_message("+%d ammo" % amount, _pickup_color())
		"health":
			if player.health.current >= player.health.max_health * 0.98:
				return
			player.health.heal(float(amount))
			AudioDirector.play_at(&"upgrade", global_position, -5.0)
			GameDirector.announce_message("+%d health" % amount, _pickup_color())
		"upgrade":
			if holder == null or not holder.upgrade_current():
				return
			AudioDirector.play_at(&"upgrade", global_position, -3.0)
			GameDirector.announce_message("WEAPON UPGRADED", _pickup_color())
		_:
			if holder == null:
				return
			var is_new: bool = holder.add_weapon(weapon_id, -1, true)
			AudioDirector.play_at(&"pickup_weapon", global_position, -3.0)
			if is_new:
				GameDirector.announce_message(
					"PICKED UP %s" % WeaponLibrary.by_id(weapon_id).display_name, _pickup_color())
			else:
				GameDirector.announce_message("+AMMO for %s" % WeaponLibrary.by_id(weapon_id).display_name,
					_pickup_color())
	_collect()


func _collect() -> void:
	_collected = true
	FxDirector.flash_light(global_position, _pickup_color(), 1.0, 150.0, 0.25)
	FxDirector.spark_burst(global_position, Vector2.UP, 8, _pickup_color(), 150.0, 0.3)
	queue_free()
