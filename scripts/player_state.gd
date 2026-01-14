class_name PlayerState
extends State

# prvi video 8:13 je vreme kad ovo uradi pitaj filipa sta
@onready var player: Player = get_tree().get_first_node_in_group("Player")

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", -9.8)

# Animation names
var idle_anim: String = "Idle"
var walk_anim: String = "Walk"

# States
@export_group("States")
@export var idle_state: PlayerState
@export var walk_state: PlayerState

# Input Keys
var movement_key: String = "Movement"
var left_key: String = "Left"
var right_key: String = "Right"

# Base Func
func process_physics(delta: float) -> State:
	player.velocity.y += gravity * delta
	player.move_and_slide()
	return null
	
