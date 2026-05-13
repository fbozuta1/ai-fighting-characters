class_name SpellState
extends PlayerState

const CAST_DURATION: float = 0.28
const SPEED: float = 25.0

var elapsed: float = 0.0
var spell_cast: bool = false

func enter() -> void:
	elapsed = 0.0
	spell_cast = false
	if player.has_animation("Fight"):
		player.sprite.play("Fight")
		player.sprite.frame = 0
	elif player.has_animation("Idle"):
		player.sprite.play("Idle")

func process_physics(delta: float) -> State:
	if player.is_in_hit_stun():
		super(delta)
		return player.state_machine.idle_state

	elapsed += delta
	var move_x := Input.get_axis(left_key, right_key)
	var move_y := Input.get_axis(up_key, down_key)
	player.velocity.x = move_x * SPEED
	player.velocity.y = move_y * SPEED
	super(delta)

	if move_x != 0:
		player.sprite.flip_h = move_x < 0

	if not spell_cast:
		player.cast_spell()
		spell_cast = true

	if elapsed >= CAST_DURATION:
		if Input.is_action_pressed(movement_key):
			return player.state_machine.walk_state
		return player.state_machine.idle_state

	return null
