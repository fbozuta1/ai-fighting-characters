class_name CameraFollow
extends Camera2D

@export var p1_path: NodePath
@export var p2_path: NodePath
@export var min_zoom: float = 1.4
@export var max_zoom: float = 3.0
@export var zoom_distance_min: float = 80.0
@export var zoom_distance_max: float = 360.0
@export var zoom_lerp_speed: float = 4.0


var _p1: Node2D
var _p2: Node2D

func _ready() -> void:
	if not p1_path.is_empty():
		_p1 = get_node_or_null(p1_path) as Node2D
	if not p2_path.is_empty():
		_p2 = get_node_or_null(p2_path) as Node2D
	position_smoothing_enabled = true
	position_smoothing_speed = 5.0
	if _p1 != null and _p2 != null:
		position = (_p1.global_position + _p2.global_position) * 0.5

func _process(delta: float) -> void:
	if _p1 == null or _p2 == null:
		return
	position = (_p1.global_position + _p2.global_position) * 0.5

	var dist: float = _p1.global_position.distance_to(_p2.global_position)
	var t: float = clampf(inverse_lerp(zoom_distance_min, zoom_distance_max, dist), 0.0, 1.0)
	var target_zoom_value: float = lerpf(max_zoom, min_zoom, t)
	var current: float = zoom.x
	var smoothed: float = lerpf(current, target_zoom_value, clampf(zoom_lerp_speed * delta, 0.0, 1.0))
	zoom = Vector2(smoothed, smoothed)
