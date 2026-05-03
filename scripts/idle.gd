class_name PlayerIdleState
extends PlayerState


func enter() -> void:
	if player.has_animation("Idle"):
		player.sprite.play("Idle")

func process_input(event: InputEvent) -> State:
	super(event)
	if event.is_action_pressed(movement_key): 
		return player.state_machine.walk_state
	if event.is_action_pressed(fight_key) and player.has_animation("Fight"):
		return player.state_machine.fight_state
	return null


func process_physics(delta: float) -> State:
	super(delta)
	return null
