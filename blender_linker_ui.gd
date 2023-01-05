extends WindowDialog

export var server_node : NodePath
onready var info_node = $VBoxContainer/InfoLabel

func _ready():
	popup_centered()
	#connect("informing", self, "_on_informing")


func _on_CloseButton_pressed():
	visible = false

func _on_informing(message):
	print("_on_informing")
	info_node.text = message
