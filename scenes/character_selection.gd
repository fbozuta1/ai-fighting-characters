extends Control

const ANIMATIONS_ROOT: String = "res://assets/animations"
const GENERATION_SCRIPT_PATH: String = "res://scripts/python_ai_generation/pixellab_generation_script.py"
const GENERATION_PROGRESS_FILE: String = "user://animation_progress.json"
const REQUEST_FILE_PATH: String = "user://animation_request.json"

const ACTION_LABELS: Dictionary = {
	"idle": "I",
	"walk": "W",
	"fight": "F",
}
const COLOR_BG: Color = Color(0.035, 0.045, 0.075, 1.0)
const COLOR_PANEL: Color = Color(0.075, 0.085, 0.13, 0.98)
const COLOR_PANEL_ALT: Color = Color(0.105, 0.095, 0.145, 0.98)
const COLOR_BORDER: Color = Color(0.48, 0.88, 0.62, 1.0)
const COLOR_AMBER: Color = Color(1.0, 0.78, 0.27, 1.0)
const COLOR_TEXT: Color = Color(0.92, 0.96, 0.88, 1.0)
const COLOR_MUTED: Color = Color(0.58, 0.68, 0.68, 1.0)
const COLOR_BUTTON: Color = Color(0.13, 0.19, 0.19, 1.0)
const COLOR_BUTTON_HOVER: Color = Color(0.18, 0.28, 0.24, 1.0)

var card_grid: GridContainer
var title_field: LineEdit
var description_field: TextEdit
var reference_image_path_field: LineEdit
var reference_image_dialog: FileDialog
var progress_bar: ProgressBar
var status_label: Label
var generate_button: Button
var header_label: Label
var reference_image_path: String = ""
var preview_timer: Timer
var preview_animations: Array[Dictionary] = []
var generation_thread: Thread
var progress_timer: Timer
var generation_progress_file_path: String = ""

var current_player: int = 1

func _ready() -> void:
	current_player = 1 if not CharacterSelectionData.has_selection(1) else 2
	_build_ui()
	_load_character_cards()
	preview_timer = Timer.new()
	preview_timer.wait_time = 0.14
	preview_timer.timeout.connect(_on_preview_timer_timeout)
	add_child(preview_timer)
	preview_timer.start()
	progress_timer = Timer.new()
	progress_timer.wait_time = 0.25
	progress_timer.timeout.connect(_on_progress_timer_timeout)
	add_child(progress_timer)
	_refresh_header()

func _exit_tree() -> void:
	if generation_thread != null and generation_thread.is_started():
		generation_thread.wait_to_finish()

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = COLOR_BG
	add_child(backdrop)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 14)
	root.offset_left = 30
	root.offset_top = 22
	root.offset_right = -30
	root.offset_bottom = -24
	add_child(root)

	header_label = Label.new()
	header_label.text = "Select Character"
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.add_theme_font_size_override("font_size", 34)
	header_label.add_theme_color_override("font_color", COLOR_AMBER)
	header_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	header_label.add_theme_constant_override("shadow_offset_x", 3)
	header_label.add_theme_constant_override("shadow_offset_y", 3)
	root.add_child(header_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)

	var existing_panel := PanelContainer.new()
	existing_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	existing_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	existing_panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL, COLOR_BORDER))
	body.add_child(existing_panel)

	var existing_margin := MarginContainer.new()
	existing_margin.add_theme_constant_override("margin_left", 12)
	existing_margin.add_theme_constant_override("margin_top", 12)
	existing_margin.add_theme_constant_override("margin_right", 12)
	existing_margin.add_theme_constant_override("margin_bottom", 12)
	existing_panel.add_child(existing_margin)

	var existing_box := VBoxContainer.new()
	existing_box.add_theme_constant_override("separation", 10)
	existing_margin.add_child(existing_box)

	var existing_title := Label.new()
	existing_title.text = "Fighter Roster"
	existing_title.add_theme_font_size_override("font_size", 20)
	existing_title.add_theme_color_override("font_color", COLOR_TEXT)
	existing_box.add_child(existing_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	existing_box.add_child(scroll)

	card_grid = GridContainer.new()
	card_grid.columns = 4
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card_grid)

	_build_generation_panel(body)

func _build_generation_panel(parent: Control) -> void:
	var generation_panel := PanelContainer.new()
	generation_panel.custom_minimum_size = Vector2(360, 0)
	generation_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	generation_panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL_ALT, COLOR_AMBER))
	parent.add_child(generation_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	generation_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Create Fighter"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_AMBER)
	box.add_child(title)

	var name_label := Label.new()
	name_label.text = "Name"
	_style_form_label(name_label)
	box.add_child(name_label)

	title_field = LineEdit.new()
	title_field.placeholder_text = "Example: iron duelist"
	_style_line_edit(title_field)
	box.add_child(title_field)

	var description_label := Label.new()
	description_label.text = "Description"
	_style_form_label(description_label)
	box.add_child(description_label)

	description_field = TextEdit.new()
	description_field.custom_minimum_size = Vector2(0, 130)
	description_field.placeholder_text = "Appearance, outfit, weapon, fighting style..."
	description_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_style_text_edit(description_field)
	box.add_child(description_field)

	var reference_label := Label.new()
	reference_label.text = "Reference image"
	_style_form_label(reference_label)
	box.add_child(reference_label)

	var reference_row := HBoxContainer.new()
	reference_row.add_theme_constant_override("separation", 8)
	box.add_child(reference_row)

	var reference_button := Button.new()
	reference_button.text = "Choose"
	_style_button(reference_button, false)
	reference_button.pressed.connect(_on_reference_image_button_pressed)
	reference_row.add_child(reference_button)

	reference_image_path_field = LineEdit.new()
	reference_image_path_field.editable = false
	reference_image_path_field.placeholder_text = "Optional"
	reference_image_path_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_line_edit(reference_image_path_field)
	reference_row.add_child(reference_image_path_field)

	generate_button = Button.new()
	generate_button.text = "Generate and Play"
	_style_button(generate_button, true)
	generate_button.pressed.connect(_on_generate_pressed)
	box.add_child(generate_button)

	progress_bar = ProgressBar.new()
	progress_bar.visible = false
	progress_bar.show_percentage = false
	_style_progress_bar(progress_bar)
	box.add_child(progress_bar)

	status_label = Label.new()
	status_label.visible = false
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(status_label)

	reference_image_dialog = FileDialog.new()
	reference_image_dialog.title = "Select Reference Image"
	reference_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	reference_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	reference_image_dialog.filters = PackedStringArray(["*.png ; PNG Images", "*.jpg, *.jpeg ; JPEG Images", "*.webp ; WebP Images"])
	reference_image_dialog.use_native_dialog = true
	reference_image_dialog.file_selected.connect(_on_reference_image_selected)
	add_child(reference_image_dialog)

func _load_character_cards() -> void:
	preview_animations.clear()
	for child in card_grid.get_children():
		child.queue_free()

	var characters := _discover_characters()
	if characters.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No characters with idle animations found."
		card_grid.add_child(empty_label)
		return

	for character in characters:
		card_grid.add_child(_create_character_card(character))

func _discover_characters() -> Array[Dictionary]:
	var characters: Array[Dictionary] = []
	var dir := DirAccess.open(ANIMATIONS_ROOT)
	if dir == null:
		return characters

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while not folder_name.is_empty():
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var character_root := ANIMATIONS_ROOT.path_join(folder_name)
			var action_folders := _find_action_folders(character_root)
			if action_folders.has("idle"):
				characters.append({
					"name": folder_name,
					"root": character_root,
					"actions": action_folders,
					"preview": _first_png_in_folder(action_folders["idle"]),
					"idle_frames": _png_frames_in_folder(action_folders["idle"]),
				})
		folder_name = dir.get_next()
	dir.list_dir_end()

	characters.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["name"]).naturalnocasecmp_to(str(right["name"])) < 0
	)
	return characters

func _find_action_folders(character_root: String) -> Dictionary:
	var action_folders := {}
	var dir := DirAccess.open(character_root)
	if dir == null:
		return action_folders

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while not folder_name.is_empty():
		if dir.current_is_dir():
			var action_name := folder_name.to_lower()
			if ACTION_LABELS.has(action_name):
				var folder_path := character_root.path_join(folder_name)
				if not _first_png_in_folder(folder_path).is_empty():
					action_folders[action_name] = folder_path
		folder_name = dir.get_next()
	dir.list_dir_end()
	return action_folders

func _first_png_in_folder(folder_path: String) -> String:
	var frames := _png_frames_in_folder(folder_path)
	return frames[0] if not frames.is_empty() else ""

func _png_frames_in_folder(folder_path: String) -> Array[String]:
	var dir := DirAccess.open(folder_path)
	if dir == null:
		return []
	var frames: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "png":
			frames.append(folder_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	frames.sort_custom(func(left: String, right: String) -> bool:
		return left.naturalnocasecmp_to(right) < 0
	)
	return frames

func _create_character_card(character: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(160, 190)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_character_card(card)
	card.pressed.connect(_on_character_selected.bind(character))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_top = 8
	box.offset_right = -8
	box.offset_bottom = -8
	card.add_child(box)

	var top_strip := ColorRect.new()
	top_strip.custom_minimum_size = Vector2(0, 5)
	top_strip.color = COLOR_AMBER
	top_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top_strip)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(128, 118)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", _make_preview_style())
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(preview_panel)

	var preview_margin := MarginContainer.new()
	preview_margin.add_theme_constant_override("margin_left", 8)
	preview_margin.add_theme_constant_override("margin_top", 8)
	preview_margin.add_theme_constant_override("margin_right", 8)
	preview_margin.add_theme_constant_override("margin_bottom", 8)
	preview_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(preview_margin)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(112, 98)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_margin.add_child(preview)

	var idle_frames: Array[String] = []
	for frame_path in character.get("idle_frames", []):
		idle_frames.append(str(frame_path))
	var idle_textures := _load_preview_textures(idle_frames)
	if not idle_textures.is_empty():
		preview.texture = idle_textures[0]
		preview_animations.append({
			"target": preview,
			"frames": idle_textures,
			"frame": 0,
		})

	var name_label := Label.new()
	name_label.text = str(character["name"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var badges := HBoxContainer.new()
	badges.alignment = BoxContainer.ALIGNMENT_CENTER
	badges.add_theme_constant_override("separation", 5)
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(badges)

	var actions: Dictionary = character["actions"]
	for action in ["idle", "walk", "fight"]:
		var badge := Label.new()
		badge.text = ACTION_LABELS[action]
		badge.add_theme_color_override("font_color", COLOR_AMBER if actions.has(action) else Color(0.28, 0.32, 0.34, 1.0))
		badge.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
		badge.add_theme_constant_override("shadow_offset_x", 1)
		badge.add_theme_constant_override("shadow_offset_y", 1)
		badge.add_theme_font_size_override("font_size", 13)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badges.add_child(badge)

	return card

func _on_preview_timer_timeout() -> void:
	for preview_data in preview_animations:
		var target := preview_data.get("target") as TextureRect
		var frames: Array = preview_data.get("frames", [])
		if target == null or frames.is_empty():
			continue
		var frame := (int(preview_data.get("frame", 0)) + 1) % frames.size()
		preview_data["frame"] = frame
		target.texture = frames[frame] as Texture2D

func _load_preview_textures(frame_paths: Array[String]) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for frame_path in frame_paths:
		var texture := _load_png_texture(frame_path)
		if texture != null:
			textures.append(texture)
	return textures

func _make_panel_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style

func _make_button_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := _make_panel_style(bg_color, border_color)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.shadow_size = 0
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _make_preview_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.022, 0.032, 1.0)
	style.border_color = Color(0.34, 0.96, 0.58, 1.0)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 5
	return style

func _style_button(button: Button, primary: bool) -> void:
	var border := COLOR_AMBER if primary else COLOR_BORDER
	button.add_theme_stylebox_override("normal", _make_button_style(COLOR_BUTTON, border))
	button.add_theme_stylebox_override("hover", _make_button_style(COLOR_BUTTON_HOVER, border))
	button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.08, 0.12, 0.13, 1.0), border))
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 14)

func _style_character_card(card: Button) -> void:
	card.add_theme_stylebox_override("normal", _make_card_style(Color(0.075, 0.085, 0.12, 1.0), Color(0.23, 0.40, 0.40, 1.0)))
	card.add_theme_stylebox_override("hover", _make_card_style(Color(0.10, 0.14, 0.15, 1.0), COLOR_BORDER))
	card.add_theme_stylebox_override("pressed", _make_card_style(Color(0.055, 0.07, 0.09, 1.0), COLOR_AMBER))
	card.add_theme_color_override("font_color", COLOR_TEXT)

func _make_card_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := _make_button_style(bg_color, border_color)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 7
	return style

func _style_form_label(label: Label) -> void:
	label.add_theme_color_override("font_color", COLOR_MUTED)
	label.add_theme_font_size_override("font_size", 13)

func _style_line_edit(field: LineEdit) -> void:
	field.add_theme_stylebox_override("normal", _make_button_style(Color(0.035, 0.045, 0.06, 1.0), Color(0.26, 0.38, 0.38, 1.0)))
	field.add_theme_stylebox_override("focus", _make_button_style(Color(0.045, 0.06, 0.07, 1.0), COLOR_BORDER))
	field.add_theme_color_override("font_color", COLOR_TEXT)
	field.add_theme_color_override("font_placeholder_color", Color(0.44, 0.52, 0.52, 1.0))

func _style_text_edit(field: TextEdit) -> void:
	field.add_theme_stylebox_override("normal", _make_button_style(Color(0.035, 0.045, 0.06, 1.0), Color(0.26, 0.38, 0.38, 1.0)))
	field.add_theme_stylebox_override("focus", _make_button_style(Color(0.045, 0.06, 0.07, 1.0), COLOR_BORDER))
	field.add_theme_color_override("font_color", COLOR_TEXT)
	field.add_theme_color_override("font_placeholder_color", Color(0.44, 0.52, 0.52, 1.0))

func _style_progress_bar(bar: ProgressBar) -> void:
	bar.custom_minimum_size.y = 18
	bar.add_theme_stylebox_override("background", _make_button_style(Color(0.03, 0.04, 0.05, 1.0), Color(0.25, 0.34, 0.34, 1.0)))
	bar.add_theme_stylebox_override("fill", _make_button_style(Color(0.36, 0.95, 0.45, 1.0), Color(0.71, 1.0, 0.64, 1.0)))

func _on_character_selected(character: Dictionary) -> void:
	CharacterSelectionData.select_action_folders(current_player, character["actions"])
	_advance_player_or_start()

func _advance_player_or_start() -> void:
	if current_player == 1:
		current_player = 2
		_refresh_header()
		return
	get_tree().change_scene_to_file(CharacterSelectionData.LEVEL_SCENE_PATH)

func _refresh_header() -> void:
	if header_label == null:
		return
	header_label.text = "Select Player %d's character" % current_player

func _on_reference_image_button_pressed() -> void:
	reference_image_dialog.popup_centered_ratio(0.8)

func _on_reference_image_selected(path: String) -> void:
	reference_image_path = path
	reference_image_path_field.text = path

func _on_generate_pressed() -> void:
	if generation_thread != null and generation_thread.is_started():
		return
	var title := title_field.text.strip_edges()
	var description := description_field.text.strip_edges()
	if title.is_empty() or description.is_empty():
		status_label.visible = true
		status_label.text = "Name and description are required."
		return

	var request_file := _save_animation_request_json(title, description, reference_image_path)
	generation_progress_file_path = ProjectSettings.globalize_path(GENERATION_PROGRESS_FILE)
	_write_initial_generation_progress()
	progress_bar.value = 0
	progress_bar.visible = true
	status_label.visible = true
	status_label.text = "Starting generation..."
	generate_button.disabled = true
	progress_timer.start()
	generation_thread = Thread.new()
	var error := generation_thread.start(Callable(self, "_run_generation_script").bind(request_file, generation_progress_file_path))
	if error != OK:
		progress_timer.stop()
		generate_button.disabled = false
		status_label.text = "Failed to start generation."

func _run_generation_script(animation_request_file: String, progress_file_path: String) -> void:
	var output: Array[String] = []
	var script_path: String = ProjectSettings.globalize_path(GENERATION_SCRIPT_PATH)
	var exit_code := OS.execute("python", [script_path, animation_request_file, progress_file_path], output, true)
	if exit_code != OK and output.is_empty():
		output.append("Generation script failed with exit code " + str(exit_code))
	call_deferred("_on_generation_finished", output)

func _on_generation_finished(output: Array[String]) -> void:
	progress_timer.stop()
	if generation_thread != null:
		generation_thread.wait_to_finish()
		generation_thread = null
	generate_button.disabled = false

	var result_file := _get_animation_result_file(output)
	if result_file.is_empty():
		status_label.text = "Generation did not return a result file."
		return
	var result_error := _get_result_file_error(result_file)
	if not result_error.is_empty():
		status_label.text = result_error
		return
	CharacterSelectionData.select_result_file(current_player, result_file)
	_advance_player_or_start()

func _write_initial_generation_progress() -> void:
	var data := {
		"status": "starting",
		"message": "Starting generation...",
		"action": "",
		"action_index": 0,
		"total_actions": 3,
	}
	var file := FileAccess.open(GENERATION_PROGRESS_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _on_progress_timer_timeout() -> void:
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
	var total_actions := int(progress_data.get("total_actions", 3))
	progress_bar.value = _get_generation_progress_value(status, action_index, total_actions)
	status_label.text = message

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

func _get_animation_result_file(output: Array[String]) -> String:
	var output_lines: Array[String] = []
	for output_chunk in output:
		for line in output_chunk.split("\n", false):
			var clean_line := line.strip_edges()
			if not clean_line.is_empty():
				output_lines.append(clean_line)
	return "" if output_lines.is_empty() else output_lines[output_lines.size() - 1]

func _get_result_file_error(result_file_path: String) -> String:
	var resolved_file := _resolve_file_path(result_file_path)
	if resolved_file.is_empty():
		return "Generation result file does not exist."
	var file := FileAccess.open(resolved_file, FileAccess.READ)
	if file == null:
		return "Unable to open generation result file."
	var result_text := file.get_as_text()
	file.close()

	var result_json := JSON.new()
	if result_json.parse(result_text) != OK:
		return "Unable to parse generation result file."
	if typeof(result_json.data) != TYPE_DICTIONARY:
		return "Generation result file is not valid."
	var result_data: Dictionary = result_json.data
	if result_data.has("errors") and result_data["errors"].size() > 0:
		return ",".join(result_data["errors"])
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

func _load_png_texture(frame_path: String) -> Texture2D:
	var image := Image.new()
	if image.load(frame_path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _save_animation_request_json(title: String, description: String, selected_reference_image_path: String) -> String:
	var request_reference_image_path = null
	if not selected_reference_image_path.strip_edges().is_empty():
		request_reference_image_path = selected_reference_image_path.strip_edges()

	var data := {
		"char_data": {
			"title": title,
			"description": description,
			"ref_image_path": request_reference_image_path,
		},
		"actions": ["idle", "walk", "fight"],
		"base_folder": "./assets/animations"
	}

	var file := FileAccess.open(REQUEST_FILE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return ProjectSettings.globalize_path(REQUEST_FILE_PATH)
