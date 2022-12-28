extends Control

var PORT = 6000
export var max_packet_size = 10000
export var output_index = 0

var _server : WebSocketServer = WebSocketServer.new()
var project : MMGraphEdit
var _remote : MMGenRemote
var remote_params_gens_dict = {}
var local_params_gens_dict = {}
var responses : Array = []
var error_message : String = ""
var resolution : int = 256

enum { ERROR, LOAD, INIT_PARAMETERS, SET_LOCAL_PARAMETER_VALUE, INIT_REMOTE_PARAMETERS, SET_REMOTE_PARAMETER_VALUE, PING }
enum resolutions { _256,_512, _1024, _2048 }

var command_key_requirements : Dictionary = {
	"ping" : [],
	"load_ptex" : ["filepath"]
}

func _ready():
	print("_ready()")
	_server.connect("client_connected", self, "_connected")
	_server.connect("client_disconnected", self, "_disconnected")
	_server.connect("client_close_request", self, "_close_request")
	_server.connect("data_received", self, "_on_data")
	_server.listen(PORT)
	
	$VBoxContainer/CloseButton.connect("pressed", self, "close")
	var resOptionButton :  OptionButton = $VBoxContainer/ResolutionHBoxContainer/ResolutionOptions
	for res in resolutions.values():
		resOptionButton.add_item(str(pow(2, 8+res)))
	return
	
func _connected(id, proto):
	inform("Client %d connected with protocol: %s" % [id, proto])
	
func _close_request(id, code, reason):
	inform("Client %d disconnecting with code: %d, reason: %s" % [id, code, reason])
	
func _disconnected(id, was_clean = false):
	inform("Client %d disconnected, clean: %s" % [id, str(was_clean)])
	
func _on_data(id):
	### TODO: Authentication 
	print("Packet received.")
	var pkt : PoolByteArray = _server.get_peer(id).get_packet()
	var pkt_string : String = pkt.get_string_from_ascii()
	inform("Got data from client %d: %s, ... echoing" % [id, pkt_string.substr(0, 140)])
	
	print("pkt_string: ", pkt_string)
	var data = parse_json(pkt_string)
	print("Data: ",str(data).substr(0,140))
	var command : String = data["command"]
	match command:
		
		"ping":
			var data_dict = { "command" : "pong" }
			send_json_data(id, data_dict)
			
		"load_ptex":
			var filepath : String = data["filepath"]
			var loaded_data = load_ptex(filepath)

			var response = PoolByteArray()
			while loaded_data is GDScriptFunctionState:
				print(loaded_data.is_valid())
				loaded_data = yield(loaded_data, "completed")
			inform_and_send(id, "Finished loading ptex file.")
			response.append_array(loaded_data)
			send_image_data(id, data["image_name"], loaded_data)

			var remote_parameters = find_parameters_in_remote(_remote)			
			
			var local_parameters = find_local_parameters()
			
			if data["reset_parameters"]:
				var set_remote_parameters_command = { "command":"init_parameters", "image_name":data["image_name"], "parameters_type":"remote", "parameters":remote_parameters}		
				send_json_data(id, set_remote_parameters_command)
				var set_local_parameters_command = { "command":"init_parameters", "image_name":data["image_name"], "parameters_type":"local", "parameters":local_parameters}
				send_json_data(id, set_local_parameters_command)
				var parameters_loaded_notify_command = { "command":"parameters_loaded"}
				send_json_data(id, parameters_loaded_notify_command)
			else:
				var request_parameters_command = { "command":"request_parameters", "image_name":data["image_name"]}
				send_json_data(id, request_parameters_command)
				
		"parameter_change":
			var node_name = data["parameter_label"].split("/")[0]
			var parameter_label = data["parameter_label"].split("/")[1]
			var render_result
			print("parameter_change")
			if data["parameter_type"] == "remote":
				render_result = change_parameter_and_render(node_name, parameter_label, data["parameter_value"], true)
			elif data["parameter_type"] == "local":
				render_result = change_parameter_and_render(node_name, parameter_label, data["parameter_value"], false)
			else:
				inform_and_send(id, "ERROR: Unable to determine parameter type.")

			while render_result is GDScriptFunctionState:
				render_result = yield(render_result, "completed")
			send_image_data(id, data["image_name"], render_result)
			inform_and_send(id, "Parameter changed, render finished and transfered.")
			
		"set_multiple_parameters":
			print(data)
			for parameter_string in data["parameters"]:
				var parameter = parse_json(parameter_string)
				#print("parameter: ", parameter)
				#print(typeof(parameter))
				#print(typeof(["a"]))
				#print(typeof( { "a":"b"} ))
				var node_name = parameter["parameter_label"].split("/")[0]
				var parameter_label = parameter["parameter_label"].split("/")[1]
				var parameter_value = parameter["parameter_value"]
				var is_remote = parameter["parameter_type"] == "remote"
				set_parameter_value(node_name, parameter_label, parameter_value, is_remote)
				
		_:
			inform_and_send(id, "Unable  to read message command.")
			
		

	
func send_json_data(id : int, data : Dictionary) -> void:
	var response = PoolByteArray()
	response.append_array("json|".to_utf8())
	var json_data = to_json(data)
	#print("json_data: ", json_data)
	response.append_array(json_data.to_utf8())
	_server.get_peer(id).put_packet(response)
	
func send_image_data(id : int, image_name, image_data : PoolByteArray) -> void: # Unfortunately there's apparently a limit to the size of elements in Godot's dictionaries, this is a workaround
	var response = PoolByteArray()
	var prefix_size = 11 + len(image_name)
	var prefix_size_string = str(prefix_size).pad_zeros(3)
	response.append_array("image|{}|{}|".format([prefix_size_string, image_name], "{}").to_utf8())
	response.append_array(image_data)
	_server.get_peer(id).put_packet(response)
	
func load_ptex(filepath : String):
	var material_loaded = mm_globals.main_window.do_load_material(filepath, true, false)
	project = mm_globals.main_window.get_current_project()
	var material_node = project.get_material_node()
	var result = material_node.render(material_node, output_index, resolution)
	print("e")
	while result is GDScriptFunctionState:
		print(result.is_valid())
		result = yield(result, "completed")
	var response = result.texture.get_data().get_data()
	
	_remote = get_remote()
	find_local_parameters()
	result.release(material_node)
	return response

func render():
	# Too similar to load_ptex()
	var material_node = project.get_material_node()
	var result = material_node.render(material_node, output_index, resolution)
	while result is GDScriptFunctionState:
		result = yield(result, "completed")
	var output = result.texture.get_data().get_data()
	result.release(material_node)
	return output
		
func get_remote() -> MMGenRemote:
	for child in project.top_generator.get_children():
		if child.get_type() == "remote":
			return child
	inform("Warning: Remote node not found.")
	return null

func find_parameters_in_remote(remote_gen : MMGenRemote) -> Array:
	remote_params_gens_dict.clear()
	var output = []
	for widget in remote_gen.widgets:
		for lw in widget.linked_widgets:
			var top_gen = project.top_generator.get_node(lw.node)
			var param = top_gen.get_parameter(lw.widget)
			print("param: ", param)
			output.push_back( { 'node' : lw.node, 'param_label' : lw.widget, 'param_value' : param } )
			print("node: ", lw.node)
			print("adding ", "{}/{}".format([lw.node, lw.widget], "{}"))
			remote_params_gens_dict["{}/{}".format([lw.node, lw.widget], "{}")] = top_gen
	return output
	
func find_local_parameters() -> Array:
	var output = []
	for child in project.top_generator.get_children():
		if child.get_type() == "remote":
			continue
#		if child.get_type() ==  "material_export":
#		#	print("material_export node found!")
#			continue
		print("child.parameters: ", child.parameters)
		for param in child.parameters:
			local_params_gens_dict["{}/{}".format([child.get_hier_name(), param], "{}")] = child
			output.push_back( { 'node' : child.get_hier_name(), 'param_label' : param, 'param_value' : child.get_parameter(param), 'param_type':child.get_parameter_def(param) } )
	print("local_params_gens_dict: ", local_params_gens_dict)
	return output

func get_parameter_value(node_name : String, label : String): # No longer in use
	var gen = remote_params_gens_dict["{}/{}".format([node_name, label], "{}")]
	var parameter = gen.get_parameter(label)
	return parameter
	
func set_parameter_value(node_name : String, label : String, value : String, is_remote : bool):
	var dict = remote_params_gens_dict if is_remote else local_params_gens_dict
	var gen = dict["{}/{}".format([node_name, label], "{}")]
	print("Parameter {}/{} about to be set to {}".format([node_name, label, value], "{}"))
	print("gen.get_parameter_def(label).yoe: ", gen.get_parameter_def(label).type)
	var type = gen.get_parameter_def(label).type
	var typed_value = null
	if  type == "enum" or type == "boolean":
		typed_value = int(value)
	elif type == "float":
		typed_value = float(value)
	elif type == "vector":
		print(inform("Vector parameter values not implemented yet."))
		return
		#typed_value = vector4(value)
	gen.set_parameter(label, typed_value)
	
func close(id) -> void:
	print("Close()")
	_server.stop()
	get_parent().queue_free()
	
func inform(message : String) -> void:
	print(message)
	$VBoxContainer/InfoLabel.text = message
	
func inform_and_send(id : int, message : String) -> void:
	inform(message)
	var data = { "command":"inform", "info":message }
	send_json_data(id, data)
	
func change_parameter_and_render(node_name : String, parameter_label : String, parameter_value : String, is_remote : bool) -> void:
	set_parameter_value(node_name, parameter_label, parameter_value, is_remote)
	var result = render()
	while result is GDScriptFunctionState:
		result = yield(result, "completed")
	#response.append_array(result)
	return result

func process_parameter_set_data(command_argument : String, command_image : String,  is_remote : bool):
	var parameters_value_pair =  command_argument.split(":")
	var new_value = parameters_value_pair[1]
	var node_label_pair = parameters_value_pair[0].split("/")
	set_parameter_value(node_label_pair[0], node_label_pair[1], new_value, is_remote)
	
	var response = PoolByteArray()
	response.push_back(0)
	response.push_back(1)
	response.append_array(("|{}|".format([command_image], "{}")).to_utf8())
	var result = render()
	while result is GDScriptFunctionState:
		result = yield(result, "completed")
	response.append_array(result)
	return response

var i = 0
func _process(delta):
	if i % 120 == 0:
		print("Connection status: ", _server.get_connection_status())
	i += 1
	_server.poll()
