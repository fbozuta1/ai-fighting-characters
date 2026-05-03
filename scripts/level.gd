extends Node2D

@onready var p1: Player = $Player
@onready var p2: Player = $Player2
@onready var p1_hp_bar: ProgressBar = $CanvasLayer/HUD/P1HPBar
@onready var p2_hp_bar: ProgressBar = $CanvasLayer/HUD/P2HPBar
@onready var p1_label: Label = $CanvasLayer/HUD/P1Label
@onready var p2_label: Label = $CanvasLayer/HUD/P2Label
@onready var back_to_selection_button: Button = $CanvasLayer/BackToSelection
@onready var win_panel: Control = $CanvasLayer/WinPanel
@onready var win_label: Label = $CanvasLayer/WinPanel/Label
@onready var restart_button: Button = $CanvasLayer/WinPanel/RestartButton

const HP_GREEN: Color = Color(0.24, 0.92, 0.34, 1.0)
const HP_RED: Color = Color(1.0, 0.12, 0.08, 1.0)
const HUD_DARK: Color = Color(0.035, 0.045, 0.06, 0.96)
const HUD_BORDER: Color = Color(0.95, 0.74, 0.24, 1.0)
const HUD_TEXT: Color = Color(0.92, 0.96, 0.88, 1.0)

var p1_hp_fill_style: StyleBoxFlat
var p2_hp_fill_style: StyleBoxFlat
var p1_hit_tween: Tween
var p2_hit_tween: Tween

func _ready() -> void:
	_style_hud()
	_init_bar(p1_hp_bar, p1.max_hp)
	_init_bar(p2_hp_bar, p2.max_hp)
	p1.hp_changed.connect(_on_p1_hp_changed)
	p2.hp_changed.connect(_on_p2_hp_changed)
	p1.defeated.connect(_on_player_defeated)
	p2.defeated.connect(_on_player_defeated)
	win_panel.visible = false
	restart_button.pressed.connect(_on_restart_pressed)

func _init_bar(bar: ProgressBar, max_value: float) -> void:
	bar.min_value = 0.0
	bar.max_value = max_value
	bar.value = max_value
	bar.show_percentage = false

func _on_p1_hp_changed(new_hp: float, _max_hp: float) -> void:
	p1_hp_bar.value = new_hp
	_flash_hp_bar(1)

func _on_p2_hp_changed(new_hp: float, _max_hp: float) -> void:
	p2_hp_bar.value = new_hp
	_flash_hp_bar(2)

func _on_player_defeated(player_id: int) -> void:
	var winner := 2 if player_id == 1 else 1
	win_label.text = "Player %d Wins" % winner
	win_panel.visible = true
	get_tree().paused = true
	win_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	restart_button.process_mode = Node.PROCESS_MODE_ALWAYS

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _style_hud() -> void:
	_style_hp_label(p1_label)
	_style_hp_label(p2_label)
	p1_hp_fill_style = _style_hp_bar(p1_hp_bar)
	p2_hp_fill_style = _style_hp_bar(p2_hp_bar)
	_style_button(back_to_selection_button, "CHARACTER SELECT")
	_style_button(restart_button, "REMATCH")
	win_label.add_theme_color_override("font_color", HUD_BORDER)
	win_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	win_label.add_theme_constant_override("shadow_offset_x", 3)
	win_label.add_theme_constant_override("shadow_offset_y", 3)

func _style_hp_label(label: Label) -> void:
	label.add_theme_color_override("font_color", HUD_TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_font_size_override("font_size", 18)

func _style_hp_bar(bar: ProgressBar) -> StyleBoxFlat:
	bar.custom_minimum_size.y = 26
	var background := _make_box(HUD_DARK, Color(0.18, 0.24, 0.26, 1.0), 3)
	var fill := _make_box(HP_GREEN, Color(0.75, 1.0, 0.67, 1.0), 3)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return fill

func _style_button(button: Button, label_text: String) -> void:
	button.text = label_text
	button.add_theme_stylebox_override("normal", _make_box(Color(0.08, 0.11, 0.13, 0.98), HUD_BORDER, 3))
	button.add_theme_stylebox_override("hover", _make_box(Color(0.13, 0.18, 0.17, 0.98), Color(0.36, 0.95, 0.45, 1.0), 3))
	button.add_theme_stylebox_override("pressed", _make_box(Color(0.04, 0.06, 0.07, 1.0), HP_RED, 3))
	button.add_theme_color_override("font_color", HUD_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 13)

func _make_box(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _flash_hp_bar(player_id: int) -> void:
	var fill_style := p1_hp_fill_style if player_id == 1 else p2_hp_fill_style
	if fill_style == null:
		return
	if player_id == 1 and p1_hit_tween != null:
		p1_hit_tween.kill()
	if player_id == 2 and p2_hit_tween != null:
		p2_hit_tween.kill()

	fill_style.bg_color = HP_RED
	var tween := create_tween()
	tween.tween_property(fill_style, "bg_color", HP_GREEN, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if player_id == 1:
		p1_hit_tween = tween
	else:
		p2_hit_tween = tween
