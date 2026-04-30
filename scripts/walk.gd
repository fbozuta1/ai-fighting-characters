class_name PlayerWalkState
extends PlayerState

const SPEED: float = 75

func enter() -> void:
	player.sprite.play("Walk")

func process_physics(delta: float) -> State:
	do_move(get_move_dir())
	super(delta)

	# Ovde se proverava smer u kom je trenutno pretisnut input
	# da bi se proverilo da li je nesto pretisnuto i da li treba
	# da se prekine walk stanje i vrati u idle stanje.
	var dir := Input.get_axis(left_key, right_key)

	#if Input.is_action_pressed(fight_key):
#		player.sprite.play("assault_trooper_fight")
#	else:
#		player.sprite.play("assault_trooper_walk")

	# dir == -1 - Samo levo je pretisnuto
	# dir == 1 - Samo desno je pretisnuto
	# dir == 0 - Oba su pretisnuta ili ni jedno nije pretisnuto
	if Input.is_action_pressed(fight_key):
		return player.state_machine.fight_state

	# (Kad us oba pretisnuta ili ni jedno nije pretisnuto vracamo u idle stanje)
	if dir == 0:
		return player.state_machine.idle_state
	else:
		# Kad je samo levo pritisnuto, onda flip-uj smer kretanja
		player.sprite.flip_h = dir == 1

	return null
	
func get_move_dir() -> float: return Input.get_axis(left_key, right_key)

func do_move(move_dir: float) -> void: player.velocity.x = move_dir * SPEED
