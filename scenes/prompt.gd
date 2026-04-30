extends Control

signal submitted(title: String, description: String, reference_image_path: String)


@onready var ok_button: Button = $Panel/Button
@onready var blocker: ColorRect = $Blocker
@onready var panel: Panel = $Panel
@onready var DescriptionField: TextEdit = $Panel/CharacterDescription
@onready var TitleField: LineEdit = $Panel/Title
@onready var ReferenceImagePathField: LineEdit = $Panel/ReferenceImagePath
@onready var ReferenceImageDialog: FileDialog = $Panel/ReferenceImageDialog

var reference_image_path: String = ""

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#get_tree().paused = true
	pass # Replace with function body.
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

#func run_python_generation_script():
#	OS.execute(PYTHON_PATH, )
	
func _on_button_pressed() -> void:
	panel.visible = false
	blocker.visible = false
	
	emit_signal("submitted", TitleField.text, DescriptionField.text, reference_image_path)
	pass # Replace with function body.

func _on_reference_image_button_pressed() -> void:
	ReferenceImageDialog.popup_centered_ratio(0.8)

func _on_reference_image_dialog_file_selected(path: String) -> void:
	reference_image_path = path
	ReferenceImagePathField.text = path
