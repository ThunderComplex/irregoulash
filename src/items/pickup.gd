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
##
## An ability pickup found with both ability slots full is not refused: standing on it offers a swap,
## and pressing a slot's key puts this ability in that slot. The pickup then becomes the ability that was
## dropped, upgrades and cooldown included, so a swap can always be taken back.
##
## A pickup that cannot be taken says so in a prompt over itself, shown while the player stands on it,
## rather than in an announcement: the reason belongs to the thing on the floor, and the message feed is
## kept for what matters.

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
## Upgrade level of an ability pickup (0 for a fresh one). A dropped ability keeps the level it had.
@export_range(0, 3) var ability_level: int = 0:
	set(value):
		ability_level = value
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

## Pickup art, by convention: `pickup_<kind>.png`, `pickup_<weapon id>.png` for weapons, and
## `pickup_upgrade_weapon.png` for a weapon upgrade. A kind with no file is drawn as a plain shape.
const SPRITE_DIRECTORY: String = "res://assets/pickup/"
## The size the art is shown at, in world pixels along its longest side, whatever size it was drawn:
## inside the pickup's ring for most things, a little longer for guns, which are long and thin.
const SPRITE_SIZE: float = 24.0
const WEAPON_SPRITE_SIZE: float = 34.0

static var _sprites: Dictionary = {}

var _t: float = 0.0
var _light: PointLight2D = null
## The art: the pickup's sprite, or the plain shape drawn for a kind without one.
var _marker: Node2D = null
var _marker_scale: float = 1.0
var _collected: bool = false
## Seconds left on a dropped ability's cooldown. It keeps running on the ground, so swapping an ability out
## and back in neither costs nor saves a cooldown.
var _ability_cooldown: float = 0.0
## The holder this pickup is currently offering a swap to, and the prompt that says so.
var _offered_to: AbilityHolder = null
var _prompt: Label = null


func _ready() -> void:
	# Pickup art is drawn larger than it is shown, so it is drawn through its mipmaps; without them a
	# shrunk sprite shimmers as it pulses.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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

	var texture: Texture2D = sprite_texture()
	if texture != null:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		_marker_scale = sprite_scale(texture)
		_marker = sprite
	else:
		_marker = _shape_marker(color)
	# Unshaded: a pickup you cannot see in the dark is a pickup that does not exist.
	_marker.material = FxDirector.unshaded_material()
	_marker.z_index = Layers.Z_PICKUP + 1
	_marker.scale = Vector2.ONE * _marker_scale
	add_child(_marker)

	var ring := Line2D.new()
	ring.points = Shapes.closed_outline(Shapes.circle(15.0, 16))
	ring.width = 2.0
	ring.default_color = color
	ring.material = FxDirector.unshaded_material()
	ring.modulate.a = 0.5
	ring.z_index = Layers.Z_PICKUP
	add_child(ring)


## This pickup's art, or null when its kind has none (see `SPRITE_DIRECTORY`).
func sprite_texture() -> Texture2D:
	var file: String
	match kind:
		"weapon":
			file = "pickup_%s.png" % weapon_id
		"upgrade":
			file = "pickup_upgrade_weapon.png"
		_:
			file = "pickup_%s.png" % kind
	if not _sprites.has(file):
		var path: String = SPRITE_DIRECTORY.path_join(file)
		_sprites[file] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _sprites[file]


## The scale that shows `texture` at `SPRITE_SIZE` (or `WEAPON_SPRITE_SIZE`) along its longest side.
func sprite_scale(texture: Texture2D) -> float:
	var longest: float = maxf(1.0, float(maxi(texture.get_width(), texture.get_height())))
	return (WEAPON_SPRITE_SIZE if kind == "weapon" else SPRITE_SIZE) / longest


## The plain shape a kind without art is drawn as: distinct silhouettes, so a pickup still reads as what
## it is at a glance in the dark.
func _shape_marker(color: Color) -> Polygon2D:
	var shape := Polygon2D.new()
	if kind == "health":
		shape.polygon = PackedVector2Array([
			Vector2(-8.0, -3.0), Vector2(-3.0, -3.0), Vector2(-3.0, -8.0), Vector2(3.0, -8.0),
			Vector2(3.0, -3.0), Vector2(8.0, -3.0), Vector2(8.0, 3.0), Vector2(3.0, 3.0),
			Vector2(3.0, 8.0), Vector2(-3.0, 8.0), Vector2(-3.0, 3.0), Vector2(-8.0, 3.0),
		])
	elif kind == "key":
		shape.polygon = PackedVector2Array([
			Vector2(-8.0, -4.0), Vector2(-8.0, 4.0), Vector2(-2.0, 4.0), Vector2(-2.0, 1.5),
			Vector2(8.0, 1.5), Vector2(8.0, -1.5), Vector2(-2.0, -1.5), Vector2(-2.0, -4.0),
		])
	elif kind == "ability_upgrade":
		# A diamond: an upgrade to the build rather than to the gun in hand.
		shape.polygon = PackedVector2Array([
			Vector2(0.0, -9.0), Vector2(9.0, 0.0), Vector2(0.0, 9.0), Vector2(-9.0, 0.0),
		])
	else:
		shape.polygon = Shapes.circle(9.0, 6)
	shape.color = color.lightened(0.2)
	return shape


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	var pulse: float = 0.5 + 0.5 * sin(_t * 2.6)
	if _light != null:
		_light.energy = 0.35 + pulse * 0.4
	if _marker != null:
		# Gentler than the old shapes' pulse: art that swells too much reads as wobbling.
		_marker.scale = Vector2.ONE * _marker_scale * (0.95 + pulse * 0.1)

	_ability_cooldown = maxf(0.0, _ability_cooldown - delta)

	# Also poll: a weapon dropped by a dying enemy can land underneath the player.
	var standing: Player = null
	if not _collected:
		for body: Node2D in get_overlapping_bodies():
			var player := body as Player
			if player != null and not player.is_dead():
				standing = player
				break
	if kind == "ability":
		_update_swap_offer(standing)
	elif kind == "ability_upgrade":
		_update_upgrade_prompt(standing)
	elif kind == "upgrade":
		_update_weapon_upgrade_prompt(standing)
	elif kind == "health":
		_update_health_prompt(standing)
	elif kind == "ammo":
		_update_ammo_prompt(standing)
	if standing != null:
		_try_collect(standing)


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
			if holder == null or not _would_refill(holder):
				# Not consumed; the prompt over the pickup says why (`_update_ammo_prompt`).
				return
			holder.add_ammo(amount)
			AudioDirector.play_at(&"pickup", global_position, -4.0)
			_float("+%d AMMO" % amount)
		"health":
			if not _would_heal(player):
				# Not consumed; the prompt over the medkit says why (`_update_health_prompt`).
				return
			player.health.heal(float(amount))
			AudioDirector.play_at(&"upgrade", global_position, -5.0)
			_float("+%d HEALTH" % amount)
		"upgrade":
			if holder == null:
				return
			if not holder.upgrade_current():
				# Not consumed: nothing in hand, or it is at the cap. The prompt over the pickup says which
				# (`_update_weapon_upgrade_prompt`).
				return
			AudioDirector.play_at(&"upgrade", global_position, -3.0)
			var raised: WeaponSlot = holder.slot()
			_float("%s +%d" % [raised.data.display_name.to_upper(), raised.level])
		"ability_upgrade":
			if ability_holder == null:
				return
			if not ability_holder.upgrade_all():
				# Not consumed: either there is nothing to raise, or everything is already at the cap. The
				# prompt over the pickup says which (`_update_upgrade_prompt`).
				return
			AudioDirector.play_at(&"upgrade", global_position, -3.0)
			_float("ABILITIES UPGRADED")
		"weapon":
			if holder == null:
				return
			var is_new: bool = holder.add_weapon(weapon_id, weapon_ammo, true)
			AudioDirector.play_at(&"pickup_weapon", global_position, -3.0)
			var weapon_name: String = WeaponLibrary.by_id(weapon_id).display_name
			_float("PICKED UP %s" % weapon_name if is_new else "+AMMO for %s" % weapon_name)
		"key":
			# Always exactly one key. Deliberately not `amount`: an ammo pickup's default of 24
			# would silently hand out 24 keys the moment someone switched the kind.
			player.add_key(1)
			AudioDirector.play_at(&"pickup_ability", global_position, -4.0)
			_float("+KEY  (%d)" % player.keys)
		"ability":
			if ability_holder == null:
				return
			var ability: AbilityResource = AbilityLibrary.by_id(ability_id)
			if ability_holder.has_ability(String(ability.id)):
				# Left where it is; the prompt over it says why (`_update_swap_offer`).
				return
			if ability_holder.is_full():
				# Not taken automatically: with both slots full it is a choice, made by pressing the key of
				# the slot to give up while standing here. The prompt over the pickup says so.
				return
			ability_holder.replace_slot(ability_holder.slots.size(), _make_slot())
			_float("GAINED ABILITY %s" % ability.display_name)
			AudioDirector.play_at(&"pickup_ability", global_position, -3.0)
	_collect()


## What this pickup just gave you, said where it happened: a short line rising from the pickup rather than
## an entry in the message feed.
func _float(text: String) -> void:
	FxDirector.float_text(global_position + Vector2(0.0, -26.0), text, _pickup_color())


func _collect() -> void:
	_collected = true
	_withdraw_offer()
	FxDirector.flash_light(global_position, _pickup_color(), 1.0, 150.0, 0.25)
	FxDirector.spark_burst(global_position, Vector2.UP, 8, _pickup_color(), 150.0, 0.3)
	queue_free()


#region prompts and ability swap

## Whether standing here and pressing a slot key should swap this ability in.
func can_swap_into(holder: AbilityHolder) -> bool:
	return (kind == "ability" and not _collected and holder != null and holder.is_full()
		and not holder.has_ability(ability_id))


## Puts this ability in slot `index` and leaves the one it replaces lying here instead.
func swap_into(holder: AbilityHolder, index: int) -> void:
	if not can_swap_into(holder):
		return
	var gained: AbilityResource = AbilityLibrary.by_id(ability_id)
	var old: AbilitySlot = holder.replace_slot(index, _make_slot())
	AudioDirector.play_at(&"pickup_ability", global_position, -3.0)
	FxDirector.flash_light(global_position, _pickup_color(), 1.0, 150.0, 0.25)
	_float("GAINED ABILITY %s" % gained.display_name)
	if old == null or old.data == null:
		_collect()
		return
	# What was given up needs no message: it is lying right here, with a prompt offering it back.
	ability_id = String(old.data.id)
	ability_level = old.level
	_ability_cooldown = old.cooldown_left
	# The prompt now offers the dropped ability back.
	_update_swap_offer(holder.get_parent() as Player)


func _make_slot() -> AbilitySlot:
	var slot := AbilitySlot.new(AbilityLibrary.by_id(ability_id))
	slot.level = clampi(ability_level, 0, AbilitySlot.MAX_LEVEL)
	slot.cooldown_left = _ability_cooldown
	return slot


## Offers the swap to whoever is standing here, or withdraws it when they step off. Standing on an
## ability already carried gets a prompt saying so instead.
func _update_swap_offer(standing: Player) -> void:
	var holder: AbilityHolder = standing.abilities as AbilityHolder if standing != null else null
	if holder != null and can_swap_into(holder):
		if _offered_to != null and _offered_to != holder:
			_withdraw_offer()
		_offered_to = holder
		holder.swap_offer = self
		_show_swap_prompt(holder)
		return
	_withdraw_offer()
	if holder != null and holder.has_ability(ability_id):
		_show_prompt("%s\nalready carried" % _ability_title())


## Ammo goes to the weapon in hand, so it is left on the ground when that weapon's reserve is full (or
## there is no weapon), and says so while the player stands on it. Switching weapons can make it useful.
func _update_ammo_prompt(standing: Player) -> void:
	var holder: WeaponHolder = standing.weapons as WeaponHolder if standing != null else null
	var held: WeaponSlot = holder.slot() if holder != null else null
	if holder == null or _collected or _would_refill(holder):
		_hide_prompt()
	elif held == null or held.data == null:
		_show_prompt("No weapon to load")
	else:
		_show_prompt("%s already full" % held.data.display_name)


## Whether ammo would go anywhere: a weapon in hand with room in its reserve.
func _would_refill(holder: WeaponHolder) -> bool:
	var held: WeaponSlot = holder.slot()
	return held != null and held.data != null and held.reserve < held.data.reserve_max


## A medkit is left on the ground for a player at full health, and says so while they stand on it.
func _update_health_prompt(standing: Player) -> void:
	if standing == null or _collected or _would_heal(standing):
		_hide_prompt()
	else:
		_show_prompt("Already at full health")


## Whether a medkit would do anything for `player`. Nearly full counts as full, so a scratch does not use
## up a whole medkit.
func _would_heal(player: Player) -> bool:
	return player.health.current < player.health.max_health * 0.98


## A weapon upgrade that would do nothing explains why while the player stands on it. It upgrades the
## weapon in hand, so switching to another one is the way to use it.
func _update_weapon_upgrade_prompt(standing: Player) -> void:
	var holder: WeaponHolder = standing.weapons as WeaponHolder if standing != null else null
	var held: WeaponSlot = holder.slot() if holder != null else null
	if holder == null or _collected:
		_hide_prompt()
	elif held == null or held.data == null:
		_show_prompt("No weapon to upgrade")
	elif held.level >= WeaponSlot.MAX_LEVEL:
		_show_prompt("%s at max level" % held.data.display_name)
	else:
		_hide_prompt()


## An ability upgrade that would do nothing explains why while the player stands on it.
func _update_upgrade_prompt(standing: Player) -> void:
	var holder: AbilityHolder = standing.abilities as AbilityHolder if standing != null else null
	if holder == null or _collected:
		_hide_prompt()
	elif holder.slots.is_empty():
		_show_prompt("No abilities to upgrade")
	elif not holder.can_upgrade_any():
		_show_prompt("Abilities at max level")
	else:
		_hide_prompt()


func _withdraw_offer() -> void:
	if _offered_to != null and is_instance_valid(_offered_to) and _offered_to.swap_offer == self:
		_offered_to.swap_offer = null
	_offered_to = null
	_hide_prompt()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_withdraw_offer()


## The swap prompt: what is on offer, and which key gives up which slot. It follows the device and any
## rebinding, like the HUD does.
func _show_swap_prompt(holder: AbilityHolder) -> void:
	var choices: Array[String] = []
	for index: int in AbilityHolder.MAX_SLOTS:
		var slot: AbilitySlot = holder.slot_at(index)
		if slot != null and slot.data != null:
			choices.append("[%s] drop %s" % [GameInput.describe_for_device("ability_%d" % (index + 1)),
				slot.data.display_name])
	_show_prompt("%s\n%s" % [_ability_title(), "    ".join(choices)])


func _ability_title() -> String:
	var title: String = AbilityLibrary.by_id(ability_id).display_name.to_upper()
	if ability_level > 0:
		title += "  " + "+".repeat(ability_level)
	return title


## A line or two over the pickup, readable in the dark: what it is, and why it was or was not taken.
func _show_prompt(text: String) -> void:
	if _prompt == null:
		_prompt = Label.new()
		_prompt.name = "SwapPrompt"
		_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_prompt.size = Vector2(360.0, 48.0)
		_prompt.position = Vector2(-180.0, -78.0)
		_prompt.add_theme_font_size_override("font_size", 13)
		_prompt.add_theme_constant_override("outline_size", 5)
		_prompt.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		_prompt.add_theme_color_override("font_color", _pickup_color().lightened(0.35))
		# Readable in the dark, and above walls and actors.
		_prompt.material = FxDirector.unshaded_material()
		_prompt.z_as_relative = false
		_prompt.z_index = Layers.Z_FX + 5
		_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_prompt)
	if _prompt.text != text:
		_prompt.text = text
	_prompt.visible = true


func _hide_prompt() -> void:
	if _prompt != null:
		_prompt.visible = false

#endregion


#region editor gizmo

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var tint: Color = _pickup_color()
	var font: Font = ThemeDB.fallback_font

	draw_circle(Vector2.ZERO, 11.0, Color(tint, 0.30))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 20, Color(tint, 0.95), 2.0)

	# The art, when the kind has some, at the size it is shown in game.
	var texture: Texture2D = sprite_texture()
	if texture != null:
		var shown: Vector2 = Vector2(texture.get_size()) * sprite_scale(texture)
		draw_texture_rect(texture, Rect2(-shown * 0.5, shown), false)
	elif kind == "health":
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
			var name_text: String = AbilityLibrary.by_id(ability_id).display_name
			return name_text + (" " + "+".repeat(ability_level) if ability_level > 0 else "")
		"key":
			return "KEY"
		_:
			return ""

#endregion
