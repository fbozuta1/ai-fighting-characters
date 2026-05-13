class_name SpellProjectile
extends Area2D

var caster: Player
var textures: Array[Texture2D] = []
var animation_speed: float = 12.0
var flip_h: bool = false
var direction: Vector2 = Vector2.RIGHT
var damage: float = 10.0
var speed: float = 120.0
var max_distance: float = 120.0
var path_mode: String = "arc"
var arc_height: float = 0.0
var wave_amplitude: float = 0.0
var wave_frequency: float = 1.0
var knockback_force: float = 80.0
var target_collision_mask: int = 0

var _base_position: Vector2 = Vector2.ZERO
var _travelled: float = 0.0
var _sprite: AnimatedSprite2D

func _ready() -> void:
	_base_position = global_position
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	collision_layer = 0
	collision_mask = target_collision_mask
	monitoring = true
	monitorable = false

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _build_sprite_frames()
	_sprite.animation = "default"
	_sprite.flip_h = flip_h
	_sprite.play("default")
	add_child(_sprite)

	var shape := CircleShape2D.new()
	shape.radius = _get_collision_radius()

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = shape
	add_child(collision_shape)

	area_entered.connect(_on_area_entered)

func _build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	if not frames.has_animation("default"):
		frames.add_animation("default")
	frames.set_animation_loop("default", true)
	frames.set_animation_speed("default", animation_speed)
	for frame_texture: Texture2D in textures:
		if frame_texture != null:
			frames.add_frame("default", frame_texture)
	return frames

func _get_collision_radius() -> float:
	var radius: float = 8.0
	for frame_texture: Texture2D in textures:
		if frame_texture == null:
			continue
		var frame_size: float = minf(float(frame_texture.get_width()), float(frame_texture.get_height()))
		radius = max(radius, max(6.0, frame_size * 0.25))
	return radius

func _physics_process(delta: float) -> void:
	var step: float = speed * delta
	_travelled += step
	_base_position += direction * step
	var progress: float = clampf(_travelled / maxf(max_distance, 1.0), 0.0, 1.0)
	global_position = _base_position + _get_path_offset(progress)

	if _travelled >= max_distance:
		queue_free()

func _get_path_offset(progress: float) -> Vector2:
	match path_mode.to_lower():
		"straight":
			return Vector2.ZERO
		"wave":
			var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
			return perpendicular * sin(progress * TAU * wave_frequency) * wave_amplitude
		_:
			return Vector2(0.0, -sin(progress * PI) * arc_height)

func _on_area_entered(area: Area2D) -> void:
	var other_node: Node = area.get_parent()
	if caster == null or other_node == caster:
		return
	if other_node is Player:
		var other := other_node as Player
		var knockback: Vector2 = direction
		knockback.y *= 0.25
		other.take_damage(damage, knockback.normalized() * knockback_force)
		queue_free()
