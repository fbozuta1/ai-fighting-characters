extends Node

const LEVEL_SCENE_PATH: String = "res://scenes/level.tscn"
const SELECTION_SCENE_PATH: String = "res://scenes/character_selection.tscn"

var p1_action_folders: Dictionary = {}
var p1_result_file: String = ""
var p2_action_folders: Dictionary = {}
var p2_result_file: String = ""

func select_action_folders(player_id: int, action_folders: Dictionary) -> void:
	if player_id == 1:
		p1_action_folders = action_folders.duplicate(true)
		p1_result_file = ""
	else:
		p2_action_folders = action_folders.duplicate(true)
		p2_result_file = ""

func select_result_file(player_id: int, result_file: String) -> void:
	if player_id == 1:
		p1_result_file = result_file
		p1_action_folders = {}
	else:
		p2_result_file = result_file
		p2_action_folders = {}

func get_action_folders(player_id: int) -> Dictionary:
	return p1_action_folders if player_id == 1 else p2_action_folders

func get_result_file(player_id: int) -> String:
	return p1_result_file if player_id == 1 else p2_result_file

func has_selection(player_id: int) -> bool:
	return not get_result_file(player_id).is_empty() or not get_action_folders(player_id).is_empty()

func has_full_selection() -> bool:
	return has_selection(1) and has_selection(2)

func clear() -> void:
	p1_action_folders = {}
	p1_result_file = ""
	p2_action_folders = {}
	p2_result_file = ""
