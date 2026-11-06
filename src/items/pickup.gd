@tool
class_name Pickup
extends Area2D
## World pickup: weapons, ammo, weapon and ability upgrades, medkits, abilities and keys.
##
## Pickups carry their own light and an unshaded marker, because a pickup you
## cannot see in pitch darkness is a pickup that does not exist. They pulse
## gently so they read as "interactable" and are findable across a dark room.
##
## In the editor each pickup draws a gizmo coloured by kind and labelled with what
## it gives you, so pickups can be read and placed without running the level.

@export_enum("weapon", "ammo", "upgrade", "health", "ability", "ability_upgrade", "key") var kind: String = "weapon":
	set(value):
		kind = value
		if Engine.is_editor_hint():
			queue_redraw()
@export_enum("pistol", "smg", "shotgun") var weapon_id: String = "smg":
	set(value):
		weapon_id = value
		if Engine.is_editor_hint():
			queue_redraw()
@export_enum("fire_wall", "fire_tempest", "lightning_bolt") var ability_id: String = "fire_wall":
	set(value):
		ability_id = value
		if Engine.is_editor_hint():
			queue_redraw()
@export var amount: int = 24:
	set(value):
		amount = value
		if Engine.is_editor_hint():
			queue_redraw()
## Reserve ammo a *weapon* pickup gives; `amount` is not used for weapons. -1 means the weapon's own
## default: a full reserve if the weapon is new, two ammo pickups' worth if it is already carried.
## Enemy drops set this so a dead guard is not a full resupply.
@export var weapon_ammo: int = -1:
	set(value):
		weapon_ammo = value
		if Engine.is_editor_hint():
			queue_redraw()

var _t: float = 0.0
var _light: PointLight2D = null
var _marker: Polygon2D = null
var _collected: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		# Editor: gizmo only. The art nodes are built at runtime, and generating
		# them here risks them being written into the level file.
		return
	# Everything a pickup needs to actually be collectable is guaranteed here rather than trusted
	# to whoever spawned it. Loot dropped by an enemy used to be a bare `Pickup.new()`, which had
	# no Collision node and Area2D's default layers (both "world"), so it rendered and glowed
	# exactly like a real pickup while being impossible to walk over. Anything that creates a
	# pickup in code now gets a working one.
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	var collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "Collision"
		add_child(collision)
	if collision.shape == null:
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
	# Cast shadows like every other light. Godot's default is to *not*, which made a
	# pickup's glow leak through walls into neighbouring rooms.
	_light.shadow_enabled = true
	_light.z_index = Layers.Z_ACTOR
	add_child(_light)

	_marker = Polygon2D.new()
	# Distinct silhouettes, so a pickup reads as what it is at a glance in the dark: a cross for
	# medkits, a key shape for keys, a dot for everything else.
	if kind == "health":
		_marker.polygon = PackedVector2Array([
			Vector2(-8.0, -3.0), Vector2(-3.0, -3.0), Vector2(-3.0, -8.0), Vector2(3.0, -8.0),
			Vector2(3.0, -3.0), Vector2(8.0, -3.0), Vector2(8.0, 3.0), Vector2(3.0, 3.0),
			Vector2(3.0, 8.0), Vector2(-3.0, 8.0), Vector2(-3.0, 3.0), Vector2(-8.0, 3.0),
		])
	elif kind == "key":
		_marker.polygon = PackedVector2Array([
			Vector2(-8.0, -4.0), Vector2(-8.0, 4.0), Vector2(-2.0, 4.0), Vector2(-2.0, 1.5),
			Vector2(8.0, 1.5), Vector2(8.0, -1.5), Vector2(-2.0, -1.5), Vector2(-2.0, -4.0),
		])
	elif kind == "ability_upgrade":
		# A diamond: an upgrade to the build rather than to the gun in hand.
		_marker.polygon = PackedVector2Array([
			Vector2(0.0, -9.0), Vector2(9.0, 0.0), Vector2(0.0, 9.0), Vector2(-9.0, 0.0),
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
	if Engine.is_editor_hint():
		return
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
		"ability":
			return Color(0.86, 0.35, 0.03)
		"ability_upgrade":
			# Between the ability's own orange and the weapon crate's pink: a crate you can read as
			# "abilities" at a glance without mistaking it for a weapon upgrade.
			return Color(1.0, 0.62, 0.18)
		"key":
			return Color(1.0, 0.82, 0.32)
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
	var ability_holder := player.abilities as AbilityHolder

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
			if holder == null:
				return
			if not holder.upgrade_current():
				var held: WeaponSlot = holder.slot()
				GameDirector.announce_message("%s: MAXED" % (
					held.data.display_name.to_upper() if held != null else "WEAPON"),
					_pickup_color())
				return
			AudioDirector.play_at(&"upgrade", global_position, -3.0)
			GameDirector.announce_message("WEAPON UPGRADED", _pickup_color())
		"ability_upgrade":
			if ability_holder == null:
				return
			if not ability_holder.upgrade_all():
				# Not consumed: either there is nothing to raise, or everything is already at the cap.
				GameDirector.announce_message("ABILITIES: %s" % (
					"NONE CARRIED" if ability_holder.slots.is_empty() else "MAXED"),
					_pickup_color())
				return
			AudioDirector.play_at(&"upgrade", global_position, -3.0)
			GameDirector.announce_message("ABILITIES UPGRADED", _pickup_color())
		"weapon":
			if holder == null:
				return
			var is_new: bool = holder.add_weapon(weapon_id, weapon_ammo, true)
			AudioDirector.play_at(&"pickup_weapon", global_position, -3.0)
			if is_new:
				GameDirector.announce_message(
					"PICKED UP %s" % WeaponLibrary.by_id(weapon_id).display_name, _pickup_color())
			else:
				GameDirector.announce_message("+AMMO for %s" % WeaponLibrary.by_id(weapon_id).display_name,
					_pickup_color())
		"key":
			# Always exactly one key. Deliberately not `amount`: an ammo pickup's default of 24
			# would silently hand out 24 keys the moment someone switched the kind.
			player.add_key(1)
			AudioDirector.play_at(&"pickup_ability", global_position, -4.0)
			GameDirector.announce_message("+KEY  (%d)" % player.keys, _pickup_color())
		"ability":
			if ability_holder == null:
				return
			var ability: AbilityResource = AbilityLibrary.by_id(ability_id)
			if not ability_holder.add_ability(ability_id):
				# Not consumed: either it is already in the slots or they are full, and
				# leaving it on the ground keeps the choice the player's.
				GameDirector.announce_message("%s: %s" % [ability.display_name.to_upper(),
					"already carried" if ability_holder.has_ability(String(ability.id))
					else "ability slots full"], _pickup_color())
				return
			GameDirector.announce_message("GAINED ABILITY %s" % ability.display_name, _pickup_color())
			AudioDirector.play_at(&"pickup_ability", global_position, -3.0)
	_collect()


func _collect() -> void:
	_collected = true
	FxDirector.flash_light(global_position, _pickup_color(), 1.0, 150.0, 0.25)
	FxDirector.spark_burst(global_position, Vector2.UP, 8, _pickup_color(), 150.0, 0.3)
	queue_free()


#region editor gizmo

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var tint: Color = _pickup_color()
	var font: Font = ThemeDB.fallback_font

	draw_circle(Vector2.ZERO, 11.0, Color(tint, 0.30))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 20, Color(tint, 0.95), 2.0)

	if kind == "health":
		var arm: float = 7.0
		var thick: float = 3.0
		draw_rect(Rect2(-arm, -thick, arm * 2.0, thick * 2.0), Color(tint, 0.9))
		draw_rect(Rect2(-thick, -arm, thick * 2.0, arm * 2.0), Color(tint, 0.9))
	elif kind == "upgrade":
		draw_rect(Rect2(-6.0, -6.0, 12.0, 12.0), Color(tint.lightened(0.2), 0.9))
	elif kind == "ability_upgrade":
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, -8.0), Vector2(8.0, 0.0), Vector2(0.0, 8.0), Vector2(-8.0, 0.0),
		]), Color(tint.lightened(0.2), 0.9))
	elif kind == "key":
		draw_rect(Rect2(-8.0, -2.0, 16.0, 4.0), Color(tint.lightened(0.2), 0.95))
		draw_circle(Vector2(-7.0, 0.0), 3.0, Color(tint.lightened(0.2), 0.95))
	else:
		draw_circle(Vector2.ZERO, 6.0, Color(tint.lightened(0.2), 0.95))

	draw_string(font, Vector2(-20.0, 34.0), editor_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(tint.lightened(0.35), 0.95))


## What this pickup gives you, for the editor label.
func editor_label() -> String:
	match kind:
		"ammo":
			return "AMMO %d" % amount
		"health":
			return "MEDKIT %d" % amount
		"upgrade":
			return "WEAPON UPGRADE"
		"ability_upgrade":
			return "ABILITY UPGRADE"
		"weapon":
			return WeaponLibrary.by_id(weapon_id).display_name
		"ability":
			return AbilityLibrary.by_id(ability_id).display_name
		"key":
			return "KEY"
		_:
			return ""

#endregion
