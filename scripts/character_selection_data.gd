extends Node

const LEVEL_SCENE_PATH: String = "res://scenes/level.tscn"

var selected_action_folders: Dictionary = {}
var selected_result_file: String = ""

func select_action_folders(action_folders: Dictionary) -> void:
	selected_action_folders = action_folders.duplicate(true)
	selected_result_file = ""

func select_result_file(result_file: String) -> void:
	selected_result_file = result_file
	selected_action_folders = {}

func has_selection() -> bool:
	return not selected_result_file.is_empty() or not selected_action_folders.is_empty()

func clear() -> void:
	selected_action_folders = {}
	selected_result_file = ""
