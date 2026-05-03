class_name Player
extends CharacterBody2D

@onready var state_machine: StateMachine = $"StateMachine"
# Koristimo sprite za animaciju
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var prompt: Control = get_parent().get_node("CanvasLayer/Prompt")
@onready var ResultField: Label =  get_parent().get_node("CanvasLayer/Prompt/Panel/GenerationStatusLabel")

const GENERATION_SCRIPT_PATH: String = "C:\\Users\\fbozu\\Documents\\ai-fighting-characters\\scripts\\python_ai_generation\\pixellab_generation_script.py"
const DEFAULT_RESULT_PATH: String = "res://animation_result.json"
const ANIMATION_NAMES: Dictionary = {
	"idle": "Idle",
	"walk": "Walk",
	"fight": "Fight",
}
const ANIMATION_SPEED: float = 5.0
const GENERATION_PROGRESS_FILE: String = "user://animation_progress.json"
const TARGET_SPRITE_HEIGHT: float = 42.0
const MIN_SPRITE_SCALE: float = 0.12
const MAX_SPRITE_SCALE: float = 1.2

var generation_thread: Thread
var generation_progress_timer: Timer
var generation_progress_file_path: String = ""
var is_generation_running: bool = false

func _ready(): 
	state_machine.init()
	prompt.visible = false
	prompt.submitted.connect(_on_prompt_submitted)
	generation_progress_timer = Timer.new()
	generation_progress_timer.wait_time = 0.25
	generation_progress_timer.timeout.connect(_on_generation_progress_timer_timeout)
	add_child(generation_progress_timer)
	#sprite.flip_h = true
	if CharacterSelectionData.selected_action_folders.is_empty() == false:
		load_animations_from_action_folders(CharacterSelectionData.selected_action_folders)
	elif CharacterSelectionData.selected_result_file.is_empty() == false:
		load_animations_from_result_file(CharacterSelectionData.selected_result_file)
	else:
		load_animations_from_result_file(DEFAULT_RESULT_PATH)

func _process(delta):
	state_machine.process_frame(delta)

func _physics_process(delta):
	state_machine.process_physics(delta)

func _input(event):
	state_machine.process_input(event)

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
		ResultField.text = "Failed to start generation thread"
		if prompt.has_method("finish_generation_progress"):
			prompt.finish_generation_progress(false, ResultField.text)

func _on_back_to_selection_pressed() -> void:
	CharacterSelectionData.clear()
	get_tree().change_scene_to_file("res://scenes/character_selection.tscn")

func _exit_tree() -> void:
	if generation_thread != null and generation_thread.is_started():
		generation_thread.wait_to_finish()

func _run_generation_script(animation_request_file: String, progress_file_path: String) -> void:
	var animation_result: Array[String] = []
	var exit_code := OS.execute("python", [GENERATION_SCRIPT_PATH, animation_request_file, progress_file_path], animation_result, true)
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
	if prompt.has_method("finish_generation_progress"):
		if success:
			prompt.finish_generation_progress(true, "Loaded animations")
		else:
			prompt.finish_generation_progress(false, ResultField.text)

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

	if prompt.has_method("update_generation_progress"):
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
	ResultField.text = ""
	if animation_result.is_empty():
		ResultField.text = "Empty script output"
		return false
	var animation_result_file: String = _get_animation_result_file(animation_result)
	if animation_result_file.is_empty():
		ResultField.text = "Animation result is empty"
		return false
	return load_animations_from_result_file(animation_result_file)

func load_animations_from_result_file(animation_result_file: String) -> bool:
	var resolved_result_file := _resolve_file_path(animation_result_file)
	if resolved_result_file.is_empty():
		ResultField.text = "Animation result file " + animation_result_file + " doesn't exist"
		return false
		
	var result_file = FileAccess.open(resolved_result_file, FileAccess.READ)
	var result_text = result_file.get_as_text()
	result_file.close()

	var result_json = JSON.new()
	var result_parse_status = result_json.parse(result_text)

	if result_parse_status != OK:
		print("JSON parse error:", result_json.get_error_message())
		print("At line:", result_json.get_error_line())
		ResultField.text = "Failed to parse animation result JSON"
		return false
	
	var result_data = result_json.data
	if typeof(result_data) != TYPE_DICTIONARY:
		ResultField.text = "Animation result JSON is not an object"
		return false

	if result_data.has("errors") and result_data["errors"].size() > 0:
		ResultField.text = ",".join(result_data["errors"])
		return false

	if not result_data.has("action_folders"):
		ResultField.text = "Animation result is missing action_folders"
		return false
	if typeof(result_data["action_folders"]) != TYPE_DICTIONARY:
		ResultField.text = "Animation result action_folders is not an object"
		return false

	var load_errors: Array[String] = _load_sprite_frames(result_data["action_folders"], resolved_result_file)
	if not load_errors.is_empty():
		ResultField.text = ",".join(load_errors)
		return false

	ResultField.text = "Loaded animations"
	return true

func load_animations_from_action_folders(action_folders: Dictionary) -> bool:
	var load_errors: Array[String] = _load_sprite_frames(action_folders, "")
	if not load_errors.is_empty():
		ResultField.text = ",".join(load_errors)
		return false
	ResultField.text = "Loaded animations"
	return true

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
