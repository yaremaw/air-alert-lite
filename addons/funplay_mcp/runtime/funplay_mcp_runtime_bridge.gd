extends Node

const STATE_PATH = "user://funplay_mcp_runtime_bridge.json"
const COMMAND_PATH = "user://funplay_mcp_runtime_command.json"
const RESPONSE_PATH = "user://funplay_mcp_runtime_response.json"
const SCREENSHOT_DIR = "user://funplay_mcp_runtime_screenshots"
const WRITE_INTERVAL_SEC = 0.5
const MAX_TREE_DEPTH = 6
const MAX_TREE_NODES = 200
const MAX_RUNTIME_EVENTS = 100
const KEY_NAME_MAP = {
	"enter": KEY_ENTER,
	"escape": KEY_ESCAPE,
	"esc": KEY_ESCAPE,
	"space": KEY_SPACE,
	"tab": KEY_TAB,
	"backspace": KEY_BACKSPACE,
	"up": KEY_UP,
	"down": KEY_DOWN,
	"left": KEY_LEFT,
	"right": KEY_RIGHT,
	"shift": KEY_SHIFT,
	"ctrl": KEY_CTRL,
	"control": KEY_CTRL,
	"alt": KEY_ALT,
}
const MOUSE_BUTTON_MAP = {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP,
	"wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
}

var _elapsed: float = 0.0
var _last_command_id: String = ""
var _runtime_events: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clear_session_command_files()
	_add_runtime_event("ready", "Runtime bridge ready.")
	_write_state("ready")


func _process(delta: float) -> void:
	_poll_command()
	_elapsed += delta
	if _elapsed < WRITE_INTERVAL_SEC:
		return
	_elapsed = 0.0
	_write_state("running")


func _exit_tree() -> void:
	_add_runtime_event("exit", "Runtime bridge exiting.")
	_write_state("exit")


func _write_state(status: String) -> void:
	var tree: SceneTree = get_tree()
	var viewport: Viewport = get_viewport()
	var current_scene: Node = tree.current_scene if tree != null else null
	var tree_budget: Dictionary = {
		"remaining": MAX_TREE_NODES,
		"truncated": false,
	}
	var state: Dictionary = {
		"status": status,
		"timestamp": Time.get_datetime_string_from_system(true, true),
		"fps": Engine.get_frames_per_second(),
		"time_scale": Engine.time_scale,
		"paused": tree.paused if tree != null else false,
		"current_scene": _node_summary(current_scene),
		"node_count": _count_nodes(current_scene),
		"root_child_count": tree.root.get_child_count() if tree != null and tree.root != null else 0,
		"viewport_size": _vector2_to_dict(viewport.get_visible_rect().size) if viewport != null else null,
		"scene_tree": _serialize_node_tree(current_scene, 0, tree_budget),
		"scene_tree_truncated": bool(tree_budget.get("truncated", false)),
		"scene_tree_max_depth": MAX_TREE_DEPTH,
		"scene_tree_max_nodes": MAX_TREE_NODES,
		"runtime_events": _runtime_events.duplicate(true),
		"last_command_id": _last_command_id,
		"command_path": COMMAND_PATH,
		"response_path": RESPONSE_PATH,
	}

	var file: FileAccess = FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state, "\t") + "\n")
		file = null


func _clear_session_command_files() -> void:
	_remove_user_file(COMMAND_PATH)
	_remove_user_file(RESPONSE_PATH)


func _remove_user_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _poll_command() -> void:
	if not FileAccess.file_exists(COMMAND_PATH):
		return
	var command_text: String = FileAccess.get_file_as_string(COMMAND_PATH).strip_edges()
	if command_text == "":
		return
	var json := JSON.new()
	if json.parse(command_text) != OK:
		return
	var parsed = json.data
	if not (parsed is Dictionary):
		return
	var command_id: String = str(parsed.get("id", "")).strip_edges()
	if command_id == "" or command_id == _last_command_id:
		return

	_last_command_id = command_id
	var command_name: String = str(parsed.get("command", "")).strip_edges()
	var arguments = parsed.get("arguments", {})
	if not (arguments is Dictionary):
		arguments = {}

	var started_usec: int = Time.get_ticks_usec()
	var response: Dictionary = {
		"id": command_id,
		"command": command_name,
		"success": true,
		"timestamp": Time.get_datetime_string_from_system(true, true),
	}

	match command_name:
		"query_node":
			response["result"] = _command_query_node(arguments)
		"capture_view":
			response["result"] = _command_capture_view(arguments)
		"send_input":
			response["result"] = _command_send_input(arguments)
		"get_events":
			response["result"] = {
				"events": _runtime_events.duplicate(true),
				"event_count": _runtime_events.size(),
			}
		_:
			response["success"] = false
			response["error"] = "Unknown runtime bridge command '%s'." % command_name

	if bool(response.get("success", false)) and response.has("result"):
		var result_success: bool = _runtime_result_success(response.get("result", {}))
		response["success"] = result_success
		if not result_success:
			var result = response.get("result", {})
			if result is Dictionary:
				response["error"] = str(result.get("error", "Runtime bridge command returned an unsuccessful result."))
			else:
				response["error"] = "Runtime bridge command returned an unsuccessful result."

	response["elapsed_msec"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_write_response(response)
	_add_runtime_event("command", "%s: %s" % [command_name, "success" if bool(response.get("success", false)) else "error"], {
		"id": command_id,
		"elapsed_msec": response["elapsed_msec"],
	})
	_write_state("command")


func _write_response(response: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(RESPONSE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(response, "\t") + "\n")
		file = null


func _command_query_node(arguments: Dictionary) -> Dictionary:
	var node_path: String = str(arguments.get("node_path", "current_scene")).strip_edges()
	var node: Node = _resolve_runtime_node(node_path)
	if node == null:
		return {
			"found": false,
			"node_path": node_path,
			"error": "Runtime node not found.",
		}

	var result: Dictionary = _node_summary(node)
	result["found"] = true
	result["properties"] = _runtime_properties(node)

	var requested_properties = arguments.get("properties", [])
	if requested_properties is Array and requested_properties.size() > 0:
		var values: Dictionary = {}
		for property_name in requested_properties:
			var name: String = str(property_name).strip_edges()
			if name == "":
				continue
			values[name] = _safe_variant(node.get(name)) if _has_property(node, name) else null
		result["requested_properties"] = values

	if bool(arguments.get("include_children", false)):
		var budget: Dictionary = {
			"remaining": clamp(int(arguments.get("max_nodes", 80)), 1, 500),
			"truncated": false,
		}
		var max_depth: int = clamp(int(arguments.get("max_depth", 2)), 0, 8)
		result["tree"] = _serialize_node_tree_limited(node, 0, max_depth, budget)
		result["tree_truncated"] = bool(budget.get("truncated", false))

	return result


func _command_capture_view(arguments: Dictionary) -> Dictionary:
	if DisplayServer.get_name().to_lower() == "headless":
		return {
			"captured": false,
			"error": "Runtime viewport capture is unavailable in headless mode.",
		}

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return {
			"captured": false,
			"error": "Runtime viewport is not available.",
		}

	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		return {
			"captured": false,
			"error": "Runtime viewport has no texture.",
		}

	var image: Image = texture.get_image()
	if image == null:
		return {
			"captured": false,
			"error": "Failed to capture runtime viewport image.",
		}

	var save_path: String = str(arguments.get("save_path", "")).strip_edges()
	if save_path == "":
		save_path = "%s/runtime_%d.png" % [SCREENSHOT_DIR, Time.get_ticks_usec()]
	save_path = _normalize_runtime_path(save_path)
	if save_path == "":
		return {
			"captured": false,
			"error": "Runtime screenshot path must stay under user:// or res:// without parent-directory traversal.",
		}
	var ensure_err: int = _ensure_parent_dir(save_path)
	if ensure_err != OK:
		return {
			"captured": false,
			"error": "Failed to create runtime screenshot directory.",
			"save_path": save_path,
			"error_code": ensure_err,
		}
	var save_err: int = image.save_png(save_path)
	if save_err != OK:
		return {
			"captured": false,
			"error": "Failed to save runtime screenshot.",
			"save_path": save_path,
			"error_code": save_err,
		}

	var result: Dictionary = {
		"captured": true,
		"save_path": save_path,
		"size": _vector2_to_dict(Vector2(image.get_size())),
	}
	if bool(arguments.get("return_data_uri", false)):
		result["data_uri"] = "data:image/png;base64,%s" % Marshalls.raw_to_base64(image.save_png_to_buffer())
	return result


func _command_send_input(arguments: Dictionary) -> Dictionary:
	var events = arguments.get("events", [])
	if not (events is Array):
		events = []
	if events.is_empty():
		events = [arguments]

	var results: Array = []
	for item in events:
		if not (item is Dictionary):
			results.append({
				"success": false,
				"error": "Input event must be an object.",
			})
			continue
		results.append(_send_runtime_input_event(item))
	return {
		"event_count": results.size(),
		"results": results,
	}


func _send_runtime_input_event(event: Dictionary) -> Dictionary:
	var event_type: String = str(event.get("type", "action")).strip_edges().to_lower()
	match event_type:
		"action":
			return _runtime_action_event(event)
		"key":
			return _runtime_key_event(event)
		"mouse_button":
			return _runtime_mouse_button_event(event)
		"mouse_drag":
			return _runtime_mouse_drag_event(event)
		_:
			return {
				"success": false,
				"type": event_type,
				"error": "Unsupported runtime input event type.",
			}


func _runtime_action_event(arguments: Dictionary) -> Dictionary:
	var action_name: String = str(arguments.get("action", "")).strip_edges()
	if action_name == "":
		return {"success": false, "type": "action", "error": "'action' is required."}

	var mode: String = str(arguments.get("mode", "tap")).strip_edges().to_lower()
	if not _is_input_mode(mode):
		return {"success": false, "type": "action", "error": "'mode' must be press, release, or tap."}
	var strength: float = float(arguments.get("strength", 1.0))
	if mode == "press" or mode == "tap":
		var press_event := InputEventAction.new()
		press_event.action = action_name
		press_event.pressed = true
		press_event.strength = strength
		Input.parse_input_event(press_event)
	if mode == "release" or mode == "tap":
		var release_event := InputEventAction.new()
		release_event.action = action_name
		release_event.pressed = false
		release_event.strength = 0.0
		Input.parse_input_event(release_event)
	return {
		"success": true,
		"type": "action",
		"action": action_name,
		"mode": mode,
		"strength": strength,
	}


func _runtime_key_event(arguments: Dictionary) -> Dictionary:
	var keycode: int = _to_keycode(arguments.get("key"))
	var physical_keycode: int = _to_keycode(arguments.get("physical_key"))
	if keycode == 0 and physical_keycode == 0:
		return {"success": false, "type": "key", "error": "'key' or 'physical_key' is required."}

	var mode: String = str(arguments.get("mode", "tap")).strip_edges().to_lower()
	if not _is_input_mode(mode):
		return {"success": false, "type": "key", "error": "'mode' must be press, release, or tap."}
	if mode == "press" or mode == "tap":
		var press_event := InputEventKey.new()
		press_event.pressed = true
		if keycode != 0:
			press_event.keycode = keycode
		if physical_keycode != 0:
			press_event.physical_keycode = physical_keycode
		Input.parse_input_event(press_event)
	if mode == "release" or mode == "tap":
		var release_event := InputEventKey.new()
		release_event.pressed = false
		if keycode != 0:
			release_event.keycode = keycode
		if physical_keycode != 0:
			release_event.physical_keycode = physical_keycode
		Input.parse_input_event(release_event)
	return {
		"success": true,
		"type": "key",
		"mode": mode,
		"keycode": keycode,
		"physical_keycode": physical_keycode,
	}


func _runtime_mouse_button_event(arguments: Dictionary) -> Dictionary:
	var mode: String = str(arguments.get("mode", "tap")).strip_edges().to_lower()
	if not _is_input_mode(mode):
		return {"success": false, "type": "mouse_button", "error": "'mode' must be press, release, or tap."}
	var button_index: int = _to_mouse_button(arguments.get("button", "left"))
	var position: Vector2 = _to_vector2(arguments.get("position", Vector2.ZERO))

	if mode == "press" or mode == "tap":
		var press_event := InputEventMouseButton.new()
		press_event.button_index = button_index
		press_event.position = position
		press_event.global_position = position
		press_event.pressed = true
		Input.parse_input_event(press_event)
	if mode == "release" or mode == "tap":
		var release_event := InputEventMouseButton.new()
		release_event.button_index = button_index
		release_event.position = position
		release_event.global_position = position
		release_event.pressed = false
		Input.parse_input_event(release_event)
	return {
		"success": true,
		"type": "mouse_button",
		"mode": mode,
		"button_index": button_index,
		"position": _vector2_to_dict(position),
	}


func _runtime_mouse_drag_event(arguments: Dictionary) -> Dictionary:
	var from_position: Vector2 = _to_vector2(arguments.get("from_position", Vector2.ZERO))
	var to_position: Vector2 = _to_vector2(arguments.get("to_position", Vector2.ZERO))
	var steps: int = clamp(int(arguments.get("steps", 8)), 1, 240)
	var button_index: int = _to_mouse_button(arguments.get("button", "left"))

	var press_event := InputEventMouseButton.new()
	press_event.button_index = button_index
	press_event.position = from_position
	press_event.global_position = from_position
	press_event.pressed = true
	Input.parse_input_event(press_event)

	var previous: Vector2 = from_position
	for step_index in range(1, steps + 1):
		var weight: float = float(step_index) / float(steps)
		var current: Vector2 = from_position.lerp(to_position, weight)
		var motion_event := InputEventMouseMotion.new()
		motion_event.position = current
		motion_event.global_position = current
		motion_event.relative = current - previous
		motion_event.screen_relative = current - previous
		motion_event.button_mask = 1 << (button_index - 1)
		Input.parse_input_event(motion_event)
		previous = current

	var release_event := InputEventMouseButton.new()
	release_event.button_index = button_index
	release_event.position = to_position
	release_event.global_position = to_position
	release_event.pressed = false
	Input.parse_input_event(release_event)
	return {
		"success": true,
		"type": "mouse_drag",
		"button_index": button_index,
		"from_position": _vector2_to_dict(from_position),
		"to_position": _vector2_to_dict(to_position),
		"steps": steps,
	}


func _resolve_runtime_node(node_path: String) -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var current_scene: Node = tree.current_scene
	var path: String = node_path.strip_edges()
	if path == "" or path == "." or path == "current_scene":
		return current_scene
	if path == "/root":
		return tree.root
	if path.begins_with("/"):
		return get_node_or_null(NodePath(path))
	if current_scene != null:
		var relative_node: Node = current_scene.get_node_or_null(NodePath(path))
		if relative_node != null:
			return relative_node
	return tree.root.get_node_or_null(NodePath(path))


func _serialize_node_tree_limited(node: Node, depth: int, max_depth: int, budget: Dictionary):
	if node == null:
		return null
	if int(budget.get("remaining", 0)) <= 0:
		budget["truncated"] = true
		return null
	budget["remaining"] = int(budget.get("remaining", 0)) - 1

	var summary: Dictionary = _node_summary(node)
	summary["properties"] = _runtime_properties(node)
	summary["children"] = []
	if depth >= max_depth:
		summary["children_truncated"] = node.get_child_count() > 0
		if node.get_child_count() > 0:
			budget["truncated"] = true
		return summary

	for child in node.get_children():
		if not (child is Node):
			continue
		if int(budget.get("remaining", 0)) <= 0:
			budget["truncated"] = true
			break
		var child_summary = _serialize_node_tree_limited(child, depth + 1, max_depth, budget)
		if child_summary != null:
			summary["children"].append(child_summary)
	return summary


func _add_runtime_event(kind: String, message: String, details: Dictionary = {}) -> void:
	_runtime_events.append({
		"kind": kind,
		"message": message,
		"details": details,
		"timestamp": Time.get_datetime_string_from_system(true, true),
	})
	while _runtime_events.size() > MAX_RUNTIME_EVENTS:
		_runtime_events.pop_front()


func _runtime_result_success(result) -> bool:
	if result is Dictionary:
		for flag_name in ["success", "found", "captured"]:
			if result.has(flag_name) and not bool(result.get(flag_name, false)):
				return false
		var nested_results = result.get("results", [])
		if nested_results is Array:
			for item in nested_results:
				if item is Dictionary and item.has("success") and not bool(item.get("success", false)):
					return false
	return true


func _count_nodes(node: Node) -> int:
	if node == null:
		return 0
	var total: int = 1
	for child in node.get_children():
		if child is Node:
			total += _count_nodes(child)
	return total


func _node_summary(node: Node):
	if node == null:
		return null
	var summary: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"scene_file_path": node.scene_file_path,
	}
	var script = node.get_script()
	if script is Resource:
		summary["script_path"] = script.resource_path
	var groups: Array = []
	for group_name in node.get_groups():
		groups.append(str(group_name))
	if groups.size() > 0:
		summary["groups"] = groups
	return summary


func _serialize_node_tree(node: Node, depth: int, budget: Dictionary):
	if node == null:
		return null
	if int(budget.get("remaining", 0)) <= 0:
		budget["truncated"] = true
		return null
	budget["remaining"] = int(budget.get("remaining", 0)) - 1

	var summary: Dictionary = _node_summary(node)
	summary["properties"] = _runtime_properties(node)
	summary["children"] = []
	if depth >= MAX_TREE_DEPTH:
		summary["children_truncated"] = node.get_child_count() > 0
		if node.get_child_count() > 0:
			budget["truncated"] = true
		return summary

	for child in node.get_children():
		if not (child is Node):
			continue
		if int(budget.get("remaining", 0)) <= 0:
			budget["truncated"] = true
			break
		var child_summary = _serialize_node_tree(child, depth + 1, budget)
		if child_summary != null:
			summary["children"].append(child_summary)
	return summary


func _runtime_properties(node: Node) -> Dictionary:
	var properties: Dictionary = {
		"process_mode": node.process_mode,
	}
	if node is CanvasItem:
		properties["visible"] = node.visible
	if node is Node2D:
		properties["position"] = _vector2_to_dict(node.position)
		properties["rotation_degrees"] = node.rotation_degrees
		properties["scale"] = _vector2_to_dict(node.scale)
	if node is Control:
		properties["size"] = _vector2_to_dict(node.size)
		properties["global_position"] = _vector2_to_dict(node.global_position)
		if node is Label:
			properties["text"] = node.text
		elif node is Button:
			properties["text"] = node.text
	if node is Node3D:
		properties["position"] = _vector3_to_dict(node.position)
		properties["rotation_degrees"] = _vector3_to_dict(node.rotation_degrees)
		properties["scale"] = _vector3_to_dict(node.scale)
	return properties


func _has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _to_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	if value is String:
		var parts = value.split(",")
		if parts.size() >= 2:
			return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO


func _to_keycode(value) -> int:
	if value == null:
		return 0
	if typeof(value) == TYPE_INT:
		return int(value)
	var text: String = str(value).strip_edges()
	if text == "":
		return 0
	var normalized: String = text.to_lower()
	if KEY_NAME_MAP.has(normalized):
		return int(KEY_NAME_MAP[normalized])
	if text.length() == 1:
		return text.to_upper().unicode_at(0)
	return 0


func _to_mouse_button(value) -> int:
	if value == null:
		return MOUSE_BUTTON_LEFT
	if typeof(value) == TYPE_INT:
		return int(value)
	var normalized: String = str(value).strip_edges().to_lower()
	if MOUSE_BUTTON_MAP.has(normalized):
		return int(MOUSE_BUTTON_MAP[normalized])
	return MOUSE_BUTTON_LEFT


func _is_input_mode(mode: String) -> bool:
	return mode == "press" or mode == "release" or mode == "tap"


func _normalize_runtime_path(path: String) -> String:
	var trimmed: String = path.strip_edges().replace("\\", "/")
	if trimmed == "":
		return ""
	if not (trimmed.begins_with("user://") or trimmed.begins_with("res://")):
		return ""
	if _virtual_path_escapes_root(trimmed):
		return ""
	return trimmed.simplify_path()


func _virtual_path_escapes_root(path: String) -> bool:
	var root_index: int = path.find("://")
	if root_index == -1:
		return true
	var relative_path: String = path.substr(root_index + 3)
	var depth: int = 0
	for part in relative_path.split("/", false):
		var segment: String = str(part).strip_edges()
		if segment == "" or segment == ".":
			continue
		if segment == "..":
			depth -= 1
			if depth < 0:
				return true
		else:
			depth += 1
	return false


func _ensure_parent_dir(path: String) -> int:
	var parent_dir: String = path.get_base_dir()
	if parent_dir == "" or parent_dir == "res://" or parent_dir == "user://":
		return OK
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent_dir))


func _safe_variant(value):
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			return _vector2_to_dict(value)
		TYPE_VECTOR2I:
			return _vector2_to_dict(Vector2(value))
		TYPE_VECTOR3:
			return _vector3_to_dict(value)
		TYPE_VECTOR3I:
			return _vector3_to_dict(Vector3(value))
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_ARRAY:
			var arr: Array = []
			for item in value:
				arr.append(_safe_variant(item))
			return arr
		TYPE_DICTIONARY:
			var dict: Dictionary = {}
			for key in value.keys():
				dict[str(key)] = _safe_variant(value[key])
			return dict
		TYPE_OBJECT:
			if value is Node:
				return _node_summary(value)
			if value is Resource:
				return {
					"type": value.get_class(),
					"resource_path": value.resource_path,
				}
			if value is Object:
				return {
					"type": value.get_class(),
					"string": str(value),
				}
			return str(value)
		_:
			return str(value)


func _vector2_to_dict(value) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _vector3_to_dict(value) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}
