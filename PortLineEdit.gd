extends LineEdit


var previous_string : String = "6001"
signal valid_port_entered

func _ready():
	pass # Replace with function body.


func _on_LineEdit_text_entered(string):
	print("e")
	if string == previous_string:
		print("a")
		return
	print("fas")
	if string.is_valid_integer():
		print("b")
		var int_value = int(string)
		if not 1080 < int_value and int_value < 65536:
			print("c")
			text = previous_string
			return
		print("d")
		emit_signal("valid_port_entered", int_value)
