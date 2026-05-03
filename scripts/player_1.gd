class_name Player
extends CharacterBody2D

signal hp_changed(new_hp: float, max_hp: float)
signal defeated(player_id: int)

@export var player_id: int = 1
@export var max_hp: float = 100.0

@onready var state_machine: StateMachine = $"StateMachine"
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D

const GENERATION_SCRIPT_PATH: String = "res://scripts/python_ai_generation/pixellab_generation_script.py"
const DEFAULT_RESULT_PATH: String = "res://animation_result.json"
const ANIMATION_NAMES: Dictionary = {
	"idle": "Idle",
	"walk": "Walk",
	"fight": "Fight",
}
const ANIMATION_SPEED: float = 10.0
const GENERATION_PROGRESS_FILE: String = "user://animation_progress.json"
const TARGET_SPRITE_HEIGHT: float = 42.0
const MIN_SPRITE_SCALE: float = 0.12
const MAX_SPRITE_SCALE: float = 1.2

const HITBOX_OFFSET_X: float = 28.0
const HITBOX_SIZE: Vector2 = Vector2(44.0, 38.0)
const ATTACK_RANGE_X: float = 54.0
const ATTACK_RANGE_Y: float = 34.0
const FIGHT_DAMAGE: float = 7.0
const ATTACK_HIT_COOLDOWN: float = 0.22
const KNOCKBACK_FORCE: float = 95.0
const MAX_KNOCKBACK_SPEED: float = 130.0
const KNOCKBACK_DECELERATION: float = 560.0
const HIT_STUN_DURATION: float = 0.12
const HURTBOX_LAYER_BY_ID: Dictionary = {1: 2, 2: 4}
const HITBOX_MASK_BY_ID: Dictionary = {1: 4, 2: 2}

var input_config: Dictionary = {}
var hp: float = 0.0
var is_attacking: bool = false
var hit_cooldowns: Dictionary = {}
var hit_stun_time: float = 0.0
var play_area_bounds: Rect2 = Rect2()
var has_play_area_bounds: bool = false

var prompt: Control = null
var ResultField: Label = null

var generation_thread: Thread
var generation_progress_timer: Timer
var generation_progress_file_path: String = ""
var is_generation_running: bool = false

func _ready():
	_init_input_config()
	hp = max_hp
	_init_combat_areas()
	state_machine.init()
	if player_id == 2:
		sprite.flip_h = true

	if player_id == 1:
		var canvas := get_parent().get_node_or_null("CanvasLayer")
		if canvas != null:
			prompt = canvas.get_node_or_null("Prompt")
			if prompt != null:
				ResultField = prompt.get_node_or_null("Panel/GenerationStatusLabel")
				prompt.visible = false
				if prompt.has_signal("submitted"):
					prompt.submitted.connect(_on_prompt_submitted)
		generation_progress_timer = Timer.new()
		generation_progress_timer.wait_time = 0.25
		generation_progress_timer.timeout.connect(_on_generation_progress_timer_timeout)
		add_child(generation_progress_timer)

	_load_initial_character()

func _process(delta):
	state_machine.process_frame(delta)

func _physics_process(delta):
	hit_stun_time = max(0.0, hit_stun_time - delta)
	state_machine.process_physics(delta)
	if hitbox != null:
		hitbox.position.x = (-1.0 if sprite.flip_h else 1.0) * HITBOX_OFFSET_X
	_update_hit_cooldowns(delta)
	_process_active_hits()

func _input(event):
	state_machine.process_input(event)

func _init_input_config() -> void:
	if player_id == 2:
		input_config = {
			"left": "P2_Left",
			"right": "P2_Right",
			"up": "P2_Up",
			"down": "P2_Down",
			"fight": "P2_Fight",
			"movement": "P2_Movement",
		}
	else:
		input_config = {
			"left": "Left",
			"right": "Right",
			"up": "Up",
			"down": "Down",
			"fight": "Fight",
			"movement": "Movement",
		}

func _init_combat_areas() -> void:
	if hurtbox != null:
		hurtbox.collision_layer = HURTBOX_LAYER_BY_ID.get(player_id, 2)
		hurtbox.collision_mask = 0
	if hitbox != null:
		hitbox.collision_layer = 0
		hitbox.collision_mask = HITBOX_MASK_BY_ID.get(player_id, 4)
		hitbox.monitoring = true
		hitbox.monitorable = false
	if hitbox_shape != null and hitbox_shape.shape is RectangleShape2D:
		var shape := hitbox_shape.shape as RectangleShape2D
		shape.size = HITBOX_SIZE

func _load_initial_character() -> void:
	var folders: Dictionary = CharacterSelectionData.get_action_folders(player_id)
	var result_file: String = CharacterSelectionData.get_result_file(player_id)
	if not folders.is_empty():
		load_animations_from_action_folders(folders)
	elif not result_file.is_empty():
		load_animations_from_result_file(result_file)
	elif player_id == 1:
		load_animations_from_result_file(DEFAULT_RESULT_PATH)

func set_hitbox_active(active: bool) -> void:
	if active and not is_attacking:
		hit_cooldowns.clear()
	is_attacking = active

func take_damage(amount: float, knockback: Vector2) -> void:
	if hp <= 0.0:
		return
	hp = max(0.0, hp - amount)
	velocity += knockback
	velocity = velocity.limit_length(MAX_KNOCKBACK_SPEED)
	hit_stun_time = HIT_STUN_DURATION
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		defeated.emit(player_id)

func is_in_hit_stun() -> bool:
	return hit_stun_time > 0.0

func set_play_area_bounds(bounds: Rect2) -> void:
	play_area_bounds = bounds
	has_play_area_bounds = bounds.size.x > 0.0 and bounds.size.y > 0.0
	_apply_play_area_bounds()

func decelerate_knockback(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECELERATION * delta)

func apply_post_move_constraints() -> void:
	_apply_play_area_bounds()

func _apply_play_area_bounds() -> void:
	if not has_play_area_bounds:
		return

	var clamped_position := global_position.clamp(play_area_bounds.position, play_area_bounds.position + play_area_bounds.size)
	if clamped_position.x != global_position.x:
		velocity.x = 0.0
	if clamped_position.y != global_position.y:
		velocity.y = 0.0
	global_position = clamped_position

func _update_hit_cooldowns(delta: float) -> void:
	var expired: Array[int] = []
	for instance_id in hit_cooldowns:
		var remaining := float(hit_cooldowns[instance_id]) - delta
		if remaining <= 0.0:
			expired.append(instance_id)
		else:
			hit_cooldowns[instance_id] = remaining
	for instance_id in expired:
		hit_cooldowns.erase(instance_id)

func _process_active_hits() -> void:
	if not is_attacking or hitbox == null:
		return
	for other in _get_attack_targets():
		var other_id := other.get_instance_id()
		if hit_cooldowns.has(other_id):
			continue
		var dir: Vector2 = (other.global_position - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(-1.0 if sprite.flip_h else 1.0, 0.0)
		dir.y *= 0.35
		dir = dir.normalized()
		other.take_damage(FIGHT_DAMAGE, dir * KNOCKBACK_FORCE)
		hit_cooldowns[other_id] = ATTACK_HIT_COOLDOWN

func _get_attack_targets() -> Array[Player]:
	var targets: Array[Player] = []
	for area in hitbox.get_overlapping_areas():
		var other_node: Node = area.get_parent()
		if other_node is Player and other_node != self:
			var other := other_node as Player
			if not targets.has(other):
				targets.append(other)

	var parent := get_parent()
	if parent == null:
		return targets
	for child in parent.get_children():
		if child is Player and child != self:
			var other := child as Player
			if not targets.has(other) and _is_player_in_attack_range(other):
				targets.append(other)
	return targets

func _is_player_in_attack_range(other: Player) -> bool:
	var offset := other.global_position - global_position
	var facing := -1.0 if sprite.flip_h else 1.0
	var in_front: bool = abs(offset.x) <= 2.0 or signf(offset.x) == signf(facing)
	return in_front and abs(offset.x) <= ATTACK_RANGE_X and abs(offset.y) <= ATTACK_RANGE_Y

func _on_prompt_submitted(title: String, description: String, reference_image_path: String):
	if is_generation_running:
		return

	var animation_request_file: String = _save_animation_request_json(title, description, reference_image_path)
	generation_progress_file_path = ProjectSettings.globalize_path(GENERATION_PROGRESS_FILE)
	_write_initial_generation_progress()
	is_generation_running = true
	generation_progress_timer.start()
	generation_thread = Thread.new()
	var thread_start_error := generation_thread.start(Callable(self, "_run_generation_script").bind(animation_request_file, generation_progress_file_path))
	if thread_start_error != OK:
		generation_progress_timer.stop()
		is_generation_running = false
		if ResultField != null:
			ResultField.text = "Failed to start generation thread"
		if prompt != null and prompt.has_method("finish_generation_progress"):
			prompt.finish_generation_progress(false, "Failed to start generation thread")

func _on_back_to_selection_pressed() -> void:
	CharacterSelectionData.clear()
	get_tree().change_scene_to_file("res://scenes/character_selection.tscn")

func _exit_tree() -> void:
	if generation_thread != null and generation_thread.is_started():
		generation_thread.wait_to_finish()

func _run_generation_script(animation_request_file: String, progress_file_path: String) -> void:
	var animation_result: Array[String] = []
	var script_path: String = ProjectSettings.globalize_path(GENERATION_SCRIPT_PATH)
	var exit_code := OS.execute("python", [script_path, animation_request_file, progress_file_path], animation_result, true)
	if exit_code != OK and animation_result.is_empty():
		animation_result.append("Generation script failed with exit code " + str(exit_code))
	call_deferred("_on_generation_finished", animation_result)

func _on_generation_finished(animation_result: Array[String]) -> void:
	generation_progress_timer.stop()
	if generation_thread != null:
		generation_thread.wait_to_finish()
		generation_thread = null
	is_generation_running = false

	var success := print_result(animation_result)
	if prompt != null and prompt.has_method("finish_generation_progress"):
		if success:
			prompt.finish_generation_progress(true, "Loaded animations")
		else:
			prompt.finish_generation_progress(false, ResultField.text if ResultField != null else "Generation failed")

func _write_initial_generation_progress() -> void:
	var data := {
		"status": "starting",
		"message": "Starting generation...",
		"action": "",
		"action_index": 0,
		"total_actions": ANIMATION_NAMES.size(),
	}
	var file := FileAccess.open(GENERATION_PROGRESS_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _on_generation_progress_timer_timeout() -> void:
	var file := FileAccess.open(GENERATION_PROGRESS_FILE, FileAccess.READ)
	if file == null:
		return

	var progress_text := file.get_as_text()
	file.close()

	var progress_json := JSON.new()
	if progress_json.parse(progress_text) != OK:
		return
	if typeof(progress_json.data) != TYPE_DICTIONARY:
		return

	var progress_data: Dictionary = progress_json.data
	var status := str(progress_data.get("status", "starting"))
	var message := str(progress_data.get("message", "Starting generation..."))
	var action_index := int(progress_data.get("action_index", 0))
	var total_actions := int(progress_data.get("total_actions", ANIMATION_NAMES.size()))
	var progress_value := _get_generation_progress_value(status, action_index, total_actions)

	if prompt != null and prompt.has_method("update_generation_progress"):
		prompt.update_generation_progress(progress_value, message)

func _get_generation_progress_value(status: String, action_index: int, total_actions: int) -> float:
	if status == "completed":
		return 100.0
	if status == "generating_reference_image":
		return 5.0
	if status == "generating_action_descriptions":
		return 15.0
	if status == "generating_action" and total_actions > 0:
		return clamp(15.0 + (float(action_index) / float(total_actions)) * 80.0, 15.0, 95.0)
	return 0.0

func print_result(animation_result: Array[String]) -> bool:
	if ResultField != null:
		ResultField.text = ""
	if animation_result.is_empty():
		if ResultField != null:
			ResultField.text = "Empty script output"
		return false
	var animation_result_file: String = _get_animation_result_file(animation_result)
	if animation_result_file.is_empty():
		if ResultField != null:
			ResultField.text = "Animation result is empty"
		return false
	return load_animations_from_result_file(animation_result_file)

func load_animations_from_result_file(animation_result_file: String) -> bool:
	var resolved_result_file := _resolve_file_path(animation_result_file)
	if resolved_result_file.is_empty():
		_set_status("Animation result file " + animation_result_file + " doesn't exist")
		return false

	var result_file = FileAccess.open(resolved_result_file, FileAccess.READ)
	var result_text = result_file.get_as_text()
	result_file.close()

	var result_json = JSON.new()
	var result_parse_status = result_json.parse(result_text)

	if result_parse_status != OK:
		print("JSON parse error:", result_json.get_error_message())
		print("At line:", result_json.get_error_line())
		_set_status("Failed to parse animation result JSON")
		return false

	var result_data = result_json.data
	if typeof(result_data) != TYPE_DICTIONARY:
		_set_status("Animation result JSON is not an object")
		return false

	if result_data.has("errors") and result_data["errors"].size() > 0:
		_set_status(",".join(result_data["errors"]))
		return false

	if not result_data.has("action_folders"):
		_set_status("Animation result is missing action_folders")
		return false
	if typeof(result_data["action_folders"]) != TYPE_DICTIONARY:
		_set_status("Animation result action_folders is not an object")
		return false

	var load_errors: Array[String] = _load_sprite_frames(result_data["action_folders"], resolved_result_file)
	if not load_errors.is_empty():
		_set_status(",".join(load_errors))
		return false

	_set_status("Loaded animations")
	return true

func load_animations_from_action_folders(action_folders: Dictionary) -> bool:
	var load_errors: Array[String] = _load_sprite_frames(action_folders, "")
	if not load_errors.is_empty():
		_set_status(",".join(load_errors))
		return false
	_set_status("Loaded animations")
	return true

func _set_status(text: String) -> void:
	if ResultField != null:
		ResultField.text = text

func _get_animation_result_file(animation_result: Array[String]) -> String:
	var output_lines: Array[String] = []
	for output_chunk in animation_result:
		for line in output_chunk.split("\n", false):
			var clean_line := line.strip_edges()
			if not clean_line.is_empty():
				output_lines.append(clean_line)

	if output_lines.is_empty():
		return ""

	return output_lines[output_lines.size() - 1]

func _load_sprite_frames(action_folders: Dictionary, result_file_path: String) -> Array[String]:
	var sprite_frames := SpriteFrames.new()
	var errors: Array[String] = []
	var loaded_actions: Array[String] = []

	for action_name in ANIMATION_NAMES.keys():
		if not action_folders.has(action_name):
			continue

		var animation_name: String = ANIMATION_NAMES[action_name]
		var folder_path: String = _resolve_folder_path(str(action_folders[action_name]), result_file_path)
		if folder_path.is_empty():
			errors.append("Animation folder for " + action_name + " doesn't exist: " + str(action_folders[action_name]))
			continue

		var frame_paths: Array[String] = _get_png_frames(folder_path)
		if frame_paths.is_empty():
			errors.append("No PNG frames found for " + action_name + " in " + folder_path)
			continue

		sprite_frames.add_animation(animation_name)
		sprite_frames.set_animation_loop(animation_name, true)
		sprite_frames.set_animation_speed(animation_name, ANIMATION_SPEED)

		for frame_path in frame_paths:
			var texture := _load_png_texture(frame_path)
			if texture == null:
				errors.append("Failed to load frame: " + frame_path)
				continue
			sprite_frames.add_frame(animation_name, texture)

		if sprite_frames.get_frame_count(animation_name) == 0:
			errors.append("No loadable frames for " + action_name)
		else:
			loaded_actions.append(action_name)

	if not loaded_actions.has("idle"):
		errors.append("Missing idle animation")

	if not errors.is_empty():
		return errors

	sprite.sprite_frames = sprite_frames
	_normalize_sprite_size()
	sprite.animation = "Idle"
	sprite.play("Idle")
	return []

func has_animation(animation_name: String) -> bool:
	return sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation_name)

func _normalize_sprite_size() -> void:
	var idle_texture := _get_first_animation_texture("Idle")
	if idle_texture == null:
		return
	var texture_height := float(idle_texture.get_height())
	if texture_height <= 0.0:
		return
	var normalized_scale: float = clamp(TARGET_SPRITE_HEIGHT / texture_height, MIN_SPRITE_SCALE, MAX_SPRITE_SCALE)
	sprite.scale = Vector2(normalized_scale, normalized_scale)

func _get_first_animation_texture(animation_name: String) -> Texture2D:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation_name):
		return null
	if sprite.sprite_frames.get_frame_count(animation_name) <= 0:
		return null
	return sprite.sprite_frames.get_frame_texture(animation_name, 0)

func _resolve_folder_path(folder_path: String, result_file_path: String) -> String:
	var normalized_folder := folder_path.replace("\\", "/")
	var result_dir := result_file_path.get_base_dir() if not result_file_path.is_empty() else ""
	var candidates: Array[String] = []

	candidates.append(normalized_folder)
	candidates.append(ProjectSettings.globalize_path(normalized_folder))
	candidates.append(ProjectSettings.globalize_path("res://" + _strip_current_dir_prefix(normalized_folder)))
	if not result_dir.is_empty():
		candidates.append(result_dir.path_join(normalized_folder))
	candidates.append(ProjectSettings.globalize_path("res://").path_join(normalized_folder))
	candidates.append(ProjectSettings.globalize_path("res://scripts/python_ai_generation").path_join(normalized_folder))

	var trimmed := normalized_folder
	while trimmed.begins_with("../"):
		trimmed = _strip_parent_dir_prefix(trimmed)
		candidates.append(ProjectSettings.globalize_path("res://").path_join(trimmed))

	for candidate in candidates:
		var normalized_candidate := candidate.simplify_path()
		if DirAccess.dir_exists_absolute(normalized_candidate):
			return normalized_candidate

	return ""

func _resolve_file_path(file_path: String) -> String:
	var normalized_file := file_path.replace("\\", "/")
	var candidates: Array[String] = []

	candidates.append(normalized_file)
	candidates.append(ProjectSettings.globalize_path(normalized_file))
	candidates.append(ProjectSettings.globalize_path("res://" + _strip_current_dir_prefix(normalized_file)))
	candidates.append(ProjectSettings.globalize_path("res://").path_join(normalized_file))
	candidates.append(ProjectSettings.globalize_path("res://scripts/python_ai_generation").path_join(normalized_file))

	for candidate in candidates:
		var normalized_candidate := candidate.simplify_path()
		if FileAccess.file_exists(normalized_candidate):
			return normalized_candidate

	return ""

func _strip_current_dir_prefix(path: String) -> String:
	if path.begins_with("./"):
		return path.substr(2)
	return path

func _strip_parent_dir_prefix(path: String) -> String:
	if path.begins_with("../"):
		return path.substr(3)
	return path

func _get_png_frames(folder_path: String) -> Array[String]:
	var frames: Array[String] = []
	var dir := DirAccess.open(folder_path)
	if dir == null:
		return frames

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "png":
			frames.append(folder_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	frames.sort_custom(Callable(self, "_compare_frame_paths"))
	return frames

func _compare_frame_paths(left: String, right: String) -> bool:
	return left.naturalnocasecmp_to(right) < 0

func _load_png_texture(frame_path: String) -> Texture2D:
	var image := Image.new()
	if image.load(frame_path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _save_animation_request_json(title: String, description: String, reference_image_path: String) -> String:
	var request_reference_image_path = null
	if not reference_image_path.strip_edges().is_empty():
		request_reference_image_path = reference_image_path.strip_edges()

	var data = {
		"char_data": {
			"title": title,
			"description": description,
			"ref_image_path": request_reference_image_path,
		},
		"actions": ["idle", "walk", "fight"],
		"base_folder": "./assets/animations"
	}

	var json_string = JSON.stringify(data, "\t")

	const REQUEST_FILE_PATH: String = "user://animation_request.json"
	var file = FileAccess.open(REQUEST_FILE_PATH, FileAccess.WRITE)
	file.store_string(json_string)
	file.close()
	return ProjectSettings.globalize_path(REQUEST_FILE_PATH)
