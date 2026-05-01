extends Control

signal submitted(title: String, description: String, reference_image_path: String)


@onready var ok_button: Button = $Panel/Button
@onready var blocker: ColorRect = $Blocker
@onready var panel: Panel = $Panel
@onready var DescriptionField: TextEdit = $Panel/CharacterDescription
@onready var TitleField: LineEdit = $Panel/Title
@onready var ReferenceImagePathField: LineEdit = $Panel/ReferenceImagePath
@onready var ReferenceImageButton: Button = $Panel/ReferenceImageButton
@onready var ReferenceImageDialog: FileDialog = $Panel/ReferenceImageDialog
@onready var GenerationProgressBar: ProgressBar = $Panel/GenerationProgressBar
@onready var GenerationStatusLabel: Label = $Panel/GenerationStatusLabel

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
	start_generation_progress()
	emit_signal("submitted", TitleField.text, DescriptionField.text, reference_image_path)

func _on_reference_image_button_pressed() -> void:
	ReferenceImageDialog.popup_centered_ratio(0.8)

func _on_reference_image_dialog_file_selected(path: String) -> void:
	reference_image_path = path
	ReferenceImagePathField.text = path

func start_generation_progress() -> void:
	panel.visible = true
	blocker.visible = true
	ok_button.disabled = true
	ReferenceImageButton.disabled = true
	TitleField.editable = false
	DescriptionField.editable = false
	GenerationProgressBar.value = 0
	GenerationProgressBar.visible = true
	GenerationStatusLabel.text = "Starting generation..."
	GenerationStatusLabel.visible = true

func update_generation_progress(value: float, status_text: String) -> void:
	GenerationProgressBar.value = clamp(value, 0.0, 100.0)
	GenerationStatusLabel.text = status_text

func finish_generation_progress(success: bool, status_text: String) -> void:
	GenerationProgressBar.value = 100 if success else GenerationProgressBar.value
	GenerationStatusLabel.text = status_text
	ok_button.disabled = false
	ReferenceImageButton.disabled = false
	TitleField.editable = true
	DescriptionField.editable = true
	if success:
		panel.visible = false
		blocker.visible = false
