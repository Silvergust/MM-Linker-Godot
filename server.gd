extends Control

var PORT = 6000
export var max_packet_size = 10000

var _server : WebSocketServer = WebSocketServer.new()
var project : MMGraphEdit
var _remote : MMGenRemote
var remote_params_gens_dict = {}
var local_params_gens_dict = {}
var responses : Array = []
var error_message : String = ""

enum { ERROR, LOAD, INIT_PARAMETERS, SET_LOCAL_PARAMETER_VALUE, INIT_REMOTE_PARAMETERS, SET_REMOTE_PARAMETER_VALUE }

func _ready():
	print("_ready()")
	_server.connect("client_connected", self, "_connected")
	_server.connect("client_disconnected", self, "_disconnected")
	_server.connect("client_close_request", self, "_close_request")
	_server.connect("data_received", self, "_on_data")
	_server.listen(PORT)
	return
	
func _connected(id, proto):
	print("Client %d connected with protocol: %s" % [id, proto])
	
func _close_request(id, code, reason):
	print("Client %d disconnecting with code: %d, reason: %s" % [id, code, reason])
	
func _disconnected(id, was_clean = false):
	print("Client %d disconnected, clean: %s" % [id, str(was_clean)])
	
func _on_data(id):
	### TODO: Authentication 
	print("Packet received.")
	var pkt : PoolByteArray = _server.get_peer(id).get_packet()
	var pkt_string : String = pkt.get_string_from_utf8()
	print("Got data from client %d: %s, ... echoing" % [id, pkt_string.substr(0, 140)])
	
	var pkt_strings : PoolStringArray = pkt_string.split("|")
	if pkt_strings.size() != 3:
		send_error(id, "Incorrect prefix|argument split.")
		return
	var command_prefix : String = pkt_strings[0]
	var command_image : String = pkt_strings[1]
	var command_argument : String = pkt_strings[2]
	print("command_prefix: ", command_prefix, ", arguments: ", command_argument)
	var response = PoolByteArray();
	match int(command_prefix):
		LOAD:
			response.push_back(0)
			response.push_back(1)
			response.append_array(("|{}|".format([command_image], "{}").to_utf8()))
			var loaded_ptex_data = load_ptex(command_argument)
			while loaded_ptex_data is GDScriptFunctionState:
				loaded_ptex_data = yield(loaded_ptex_data, "completed")
			response.append_array(loaded_ptex_data)
			
			_server.get_peer(id).put_packet(response)
			
			var remote_values_response = PoolByteArray()
			remote_values_response.push_back(0)
			remote_values_response.push_back(4)
			remote_values_response.append_array(("|{}|".format([command_image], "{}").to_utf8()))
			var remote_values = find_parameters_in_remote(_remote)			
			var remote_values_json = to_json(remote_values)
			remote_values_response.append_array(remote_values_json.to_utf8())
			_server.get_peer(id).put_packet(remote_values_response)
			
			var local_values_response = PoolByteArray()
			local_values_response.push_back(0)
			local_values_response.push_back(2)
			local_values_response.append_array(("|{}|".format([command_image], "{}").to_utf8()))
			var local_values = find_parameters()
			var local_values_json = to_json(local_values)
			print("local_values_json: ", local_values_json)
			local_values_response.append_array(local_values_json.to_utf8())
			print("local_values_response: ", local_values_response)
			_server.get_peer(id).put_packet(local_values_response)
		INIT_PARAMETERS:
			pass
		SET_LOCAL_PARAMETER_VALUE:
			var resp = process_parameter_set_data(command_argument, command_image, false)
			while resp is GDScriptFunctionState:
							resp = yield(resp, "completed")#			
			var parameters_value_pair =  command_argument.split(":")
			print("resp: ", resp.get_string_from_utf8().substr(0, 140))
			_server.get_peer(id).put_packet(resp)
		INIT_REMOTE_PARAMETERS:
			pass
		SET_REMOTE_PARAMETER_VALUE:
			var resp = process_parameter_set_data(command_argument, command_image, true)
			while resp is GDScriptFunctionState:
				resp = yield(resp, "completed")
			print("resp: ", resp.get_string_from_utf8().substr(0, 140))
			_server.get_peer(id).put_packet(resp.t)
		ERROR:
			print("Error packet received.")
		_:
			print("Unable  to read packet prefix")
	print("Finished _on_data")

func send_error(id : int, message : String) -> void:
	printerr("Error: ", message)
	var response = PoolByteArray()
	response.push_back(0)
	response.push_back(0)
	response.append_array("|".to_utf8())
	response.append_array(message.to_utf8())
	_server.get_peer(id).put_packet(response)
	
	
func load_ptex(filepath : String):
	var material_loaded = mm_globals.main_window.do_load_material(filepath, true, false)
	project = mm_globals.main_window.get_current_project()
	var material_node = project.get_material_node()
	var result = material_node.render(material_node, 0, 512)
	print("e")
	while result is GDScriptFunctionState:
		result = yield(result, "completed")
	var response = result.texture.get_data().get_data()
	
	_remote = get_remote()
	find_parameters()
	result.release(material_node)
	print("Finished loading ptex file.")
	return response

func render():
	# Too similar to load_ptex()
	var material_node = project.get_material_node()
	var result = material_node.render(material_node, 0, 512)
	while result is GDScriptFunctionState:
		result = yield(result, "completed")
	var output = result.texture.get_data().get_data()
	result.release(material_node)
	return output
		
func get_remote() -> MMGenRemote:
	for child in project.top_generator.get_children():
		if child.get_type() == "remote":
			return child
	print("Warning: Remote node not found.")
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
	
func find_parameters() -> Array:
	var output = []
	for child in project.top_generator.get_children():
		if child.get_type() == "remote":
			continue
		for param in child.parameters:
			local_params_gens_dict["{}/{}".format([child.get_hier_name(), param], "{}")] = child
			output.push_back( { 'node' : child.get_hier_name(), 'param_label' : param, 'param_value' : child.get_parameter(param) } )
	print("local_params_gens_dict: ", local_params_gens_dict)
	return output

func get_parameter_value(node_name : String, label : String):
	print("remote_params_gens_dict: ", remote_params_gens_dict)
	print("node_name: ", node_name)
	print("label: ", label)
	var gen = remote_params_gens_dict["{}/{}".format([node_name, label], "{}")]
	print("gen: ", gen)
	var parameter = gen.get_parameter(label)
	print("parameter: ", parameter)
	return parameter
	
func set_parameter_value(node_name : String, label : String, value : String, is_remote : bool):
	var dict = remote_params_gens_dict if is_remote else local_params_gens_dict
	var gen = dict["{}/{}".format([node_name, label], "{}")]
	gen.set_parameter(label, value)
	

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
	if i % 30 == 0:
		print("Connection status: ", _server.get_connection_status())
	i += 1
	_server.poll()
