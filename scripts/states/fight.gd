class_name FightState
extends PlayerState

const SPEED: float = 35

func enter() -> void:
	if player.has_animation("Fight"):
		player.sprite.play("Fight")
	player.set_hitbox_active(true)

func exit() -> void:
	player.set_hitbox_active(false)

func process_physics(delta: float) -> State:
	if player.is_in_hit_stun():
		super(delta)
		return player.state_machine.idle_state

	var move_x := Input.get_axis(left_key, right_key)
	var move_y := Input.get_axis(up_key, down_key)
	player.velocity.x = move_x * SPEED
	player.velocity.y = move_y * SPEED
	super(delta)

	if move_x != 0:
		player.sprite.flip_h = move_x < 0

	if Input.is_action_pressed(fight_key) and player.has_animation("Fight"):
		return player.state_machine.fight_state
	if Input.is_action_pressed(movement_key):
		return player.state_machine.walk_state
	return player.state_machine.idle_state
