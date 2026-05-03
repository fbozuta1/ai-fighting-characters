class_name PlayerWalkState
extends PlayerState

const SPEED: float = 75

func enter() -> void:
	player.sprite.play("Walk")

func process_physics(delta: float) -> State:
	var move_x := Input.get_axis(left_key, right_key)
	var move_y := Input.get_axis(up_key, down_key)
	player.velocity.x = move_x * SPEED
	player.velocity.y = move_y * SPEED
	super(delta)

	if Input.is_action_pressed(fight_key):
		return player.state_machine.fight_state

	if move_x == 0 and move_y == 0:
		return player.state_machine.idle_state

	if move_x != 0:
		player.sprite.flip_h = move_x < 0

	return null
