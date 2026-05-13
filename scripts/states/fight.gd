class_name FightState
extends PlayerState

const SPEED: float = 35
const HOLD_THRESHOLD: float = 0.2

var hold_time: float = 0.0
var heavy_attack_started: bool = false
var heavy_attack_done: bool = false
var tap_attack_done: bool = false

func enter() -> void:
	hold_time = 0.0
	heavy_attack_started = false
	heavy_attack_done = false
	tap_attack_done = false
	if player.has_animation("Fight"):
		player.sprite.play("Fight")
		player.sprite.frame = 0

func exit() -> void:
	player.set_hitbox_active(false)

func process_input(event: InputEvent) -> State:
	super(event)
	if event.is_action_released(fight_key) and not heavy_attack_started:
		player.perform_tap_attack()
		tap_attack_done = true
		return _next_state_after_attack()
	return null

func process_physics(delta: float) -> State:
	if player.is_in_hit_stun():
		super(delta)
		return player.state_machine.idle_state

	hold_time += delta
	var move_x := Input.get_axis(left_key, right_key)
	var move_y := Input.get_axis(up_key, down_key)
	player.velocity.x = move_x * SPEED
	player.velocity.y = move_y * SPEED
	super(delta)

	if move_x != 0:
		player.sprite.flip_h = move_x < 0

	if tap_attack_done:
		return _next_state_after_attack()

	if Input.is_action_pressed(fight_key) and hold_time >= HOLD_THRESHOLD:
		heavy_attack_started = true

	if heavy_attack_started:
		if _fight_animation_is_on_final_frame():
			if not heavy_attack_done:
				player.perform_heavy_attack()
				heavy_attack_done = true
			return _next_state_after_attack()
		return player.state_machine.fight_state

	if not Input.is_action_pressed(fight_key):
		player.perform_tap_attack()
		tap_attack_done = true
		return _next_state_after_attack()

	return player.state_machine.fight_state

func _fight_animation_is_on_final_frame() -> bool:
	if not player.has_animation("Fight"):
		return true
	var frame_count := player.sprite.sprite_frames.get_frame_count("Fight")
	return frame_count <= 0 or player.sprite.frame >= frame_count - 1

func _next_state_after_attack() -> State:
	if Input.is_action_pressed(movement_key):
		return player.state_machine.walk_state
	return player.state_machine.idle_state
