extends WindowDialog

export var server_node : NodePath

func _ready():
	popup_centered()


func _on_CloseButton_pressed():
	visible = false
