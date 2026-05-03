class_name FightState
extends PlayerState

const SPEED: float = 35


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func enter() -> void:
	if player.has_animation("Fight"):
		player.sprite.play("Fight")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func process_physics(delta: float) -> State:
	do_move(get_move_dir())
	super(delta)
	
	if Input.is_action_pressed(fight_key) and player.has_animation("Fight"):
		return player.state_machine.fight_state
	if Input.is_action_pressed(movement_key):
		return player.state_machine.walk_state
	return player.state_machine.idle_state

func get_move_dir() -> float: return Input.get_axis(left_key, right_key)

func do_move(move_dir: float) -> void: player.velocity.x = move_dir * SPEED
#func process_input(event: InputEvent) -> State:
#	super(event)
#	if not event.is_action_pressed(fight_key):
#		return player.state_machine.idle_state
#	return null
