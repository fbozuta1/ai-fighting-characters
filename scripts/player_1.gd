class_name Player
extends CharacterBody2D

@onready var state_machine: StateMachine = $"StateMachine"
# Koristimo sprite za animaciju
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var prompt: Control = get_parent().get_node("CanvasLayer/Prompt")
@onready var ResultField: TextEdit =  get_parent().get_node("CanvasLayer/Prompt/Panel/CharacterDescription")

const GENERATION_SCRIPT_PATH: String = "C:\\Users\\fbozu\\Documents\\ai-fighting-characters\\scripts\\python_ai_generation\\pixellab_generation_script.py"
const DEFAULT_RESULT_PATH: String = "res://animation_result.json"
const ANIMATION_NAMES: Dictionary = {
	"idle": "Idle",
	"walk": "Walk",
	"fight": "Fight",
}
const ANIMATION_SPEED: float = 5.0

func _ready(): 
	state_machine.init()
	#prompt.visible = false
	prompt.submitted.connect(_on_prompt_submitted)
	#sprite.flip_h = true
	load_animations_from_result_file(DEFAULT_RESULT_PATH)

func _process(delta):
	state_machine.process_frame(delta)

func _physics_process(delta):
	state_machine.process_physics(delta)

func _input(event):
	state_machine.process_input(event)

func _on_prompt_submitted(title: String, description: String, reference_image_path: String):
	var animation_request_file: String = _save_animation_request_json(title, description, reference_image_path)
	var animation_result: Array[String] = []
	OS.execute("python", [GENERATION_SCRIPT_PATH, animation_request_file], animation_result, true)
	print_result(animation_result)

func print_result(animation_result: Array[String]):
	ResultField.text = ""
	if animation_result.is_empty():
		ResultField.text = "Empty script output"
		return
	var animation_result_file: String = _get_animation_result_file(animation_result)
	if animation_result_file.is_empty():
		ResultField.text = "Animation result is empty"
		return
	load_animations_from_result_file(animation_result_file)

func load_animations_from_result_file(animation_result_file: String) -> void:
	var resolved_result_file := _resolve_file_path(animation_result_file)
	if resolved_result_file.is_empty():
		ResultField.text = "Animation result file " + animation_result_file + " doesn't exist"
		return
		
	var result_file = FileAccess.open(resolved_result_file, FileAccess.READ)
	var result_text = result_file.get_as_text()
	result_file.close()

	var result_json = JSON.new()
	var result_parse_status = result_json.parse(result_text)

	if result_parse_status != OK:
		print("JSON parse error:", result_json.get_error_message())
		print("At line:", result_json.get_error_line())
		ResultField.text = "Failed to parse animation result JSON"
		return
	
	var result_data = result_json.data
	if typeof(result_data) != TYPE_DICTIONARY:
		ResultField.text = "Animation result JSON is not an object"
		return

	if result_data.has("errors") and result_data["errors"].size() > 0:
		ResultField.text = ",".join(result_data["errors"])
		return

	if not result_data.has("action_folders"):
		ResultField.text = "Animation result is missing action_folders"
		return
	if typeof(result_data["action_folders"]) != TYPE_DICTIONARY:
		ResultField.text = "Animation result action_folders is not an object"
		return

	var load_errors: Array[String] = _load_sprite_frames(result_data["action_folders"], resolved_result_file)
	if not load_errors.is_empty():
		ResultField.text = ",".join(load_errors)
		return

	ResultField.text = "Loaded animations"

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

	for action_name in ANIMATION_NAMES.keys():
		if not action_folders.has(action_name):
			errors.append("Missing " + action_name + " animation folder")
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

	if not errors.is_empty():
		return errors

	sprite.sprite_frames = sprite_frames
	sprite.animation = "Idle"
	sprite.play("Idle")
	return []

func _resolve_folder_path(folder_path: String, result_file_path: String) -> String:
	var normalized_folder := folder_path.replace("\\", "/")
	var result_dir := result_file_path.get_base_dir()
	var candidates: Array[String] = []

	candidates.append(normalized_folder)
	candidates.append(ProjectSettings.globalize_path(normalized_folder))
	candidates.append(ProjectSettings.globalize_path("res://" + _strip_current_dir_prefix(normalized_folder)))
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
