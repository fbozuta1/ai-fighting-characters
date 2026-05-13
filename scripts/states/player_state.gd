class_name PlayerState
extends State

@onready var player: Player = $"../.."

var idle_anim: String = "Idle"
var walk_anim: String = "Walk"

var left_key: String:
	get: return _key("left", "Left")
var right_key: String:
	get: return _key("right", "Right")
var up_key: String:
	get: return _key("up", "Up")
var down_key: String:
	get: return _key("down", "Down")
var fight_key: String:
	get: return _key("fight", "Fight")
var spell_key: String:
	get: return _key("spell", "Spell")
var movement_key: String:
	get: return _key("movement", "Movement")

func _key(name: String, fallback: String) -> String:
	if player == null or player.input_config.is_empty():
		return fallback
	return player.input_config.get(name, fallback)

func process_physics(delta: float) -> State:
	player.move_and_slide()
	player.apply_post_move_constraints()
	player.decelerate_knockback(delta)
	return null
