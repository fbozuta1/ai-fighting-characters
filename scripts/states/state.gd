class_name State 
extends Node2D


# vrvtno kad udje u state
func enter() -> void:
	pass 
	
func exit() -> void:
	pass 


# Called every frame. 'delta' is the elapsed time since the previous frame.
func process_frame(delta: float) -> State:
	return null

# nisam siguran trenutno sta radi
func process_input(event: InputEvent) -> State:
	return null

#nisam siguran trenutno sta radi
func process_physics(delta: float) -> State:
	return null
