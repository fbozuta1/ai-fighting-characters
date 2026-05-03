extends Node2D

@onready var p1: Player = $Player
@onready var p2: Player = $Player2
@onready var p1_hp_bar: ProgressBar = $CanvasLayer/HUD/P1HPBar
@onready var p2_hp_bar: ProgressBar = $CanvasLayer/HUD/P2HPBar
@onready var win_panel: Control = $CanvasLayer/WinPanel
@onready var win_label: Label = $CanvasLayer/WinPanel/Label
@onready var restart_button: Button = $CanvasLayer/WinPanel/RestartButton

func _ready() -> void:
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

func _on_p1_hp_changed(new_hp: float, _max_hp: float) -> void:
	p1_hp_bar.value = new_hp

func _on_p2_hp_changed(new_hp: float, _max_hp: float) -> void:
	p2_hp_bar.value = new_hp

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
