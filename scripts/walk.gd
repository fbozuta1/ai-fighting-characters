class_name PlayerWalkState
extends PlayerState

const SPEED: float = 75

func enter() -> void:
	player.animation.play(walk_anim, -1, 2)

func process_physics(delta: float) -> State:
	do_move(get_move_dir())
	super(delta)
	return null
	
func get_move_dir() -> float: return Input.get_axis(left_key, right_key)

func do_move(move_dir: float) -> void: player.velocity.x = move_dir * SPEED
