class_name StateMachine 
extends Node

var current_state: State
# prvo definisemo starting sate
@onready var starting_state: State = $Idle
# States
@export_group("States")
@export var idle_state: PlayerState
@export var walk_state: PlayerState
@export var fight_state: PlayerState

func init() -> void: 
	change_state(starting_state)
	# Ovde moraju da se inicijalizuju stanja
	# To nismo bili uradili pa nije htelo da nam ih menja
	# (oba stanja su bila null i program nije ni znao kako da predje u odgovarajuce stanje)
	idle_state = get_node("Idle")
	walk_state = get_node("Walk")
	fight_state = get_node("Fight")


func process_frame(delta: float) -> void:
	var new_state: State = current_state.process_frame(delta)
	if new_state: change_state(new_state)

# nisam siguran trenutno sta radi
func process_input(event: InputEvent) -> void:
	var new_state: State = current_state.process_input(event)
	if new_state: change_state(new_state)

#nisam siguran trenutno sta radi
func process_physics(delta: float) -> void:
	var new_state: State = current_state.process_physics(delta)
	if new_state: change_state(new_state)

func change_state(new_state: State) -> void:
	if current_state: current_state.exit()
	current_state = new_state
	current_state.enter()
