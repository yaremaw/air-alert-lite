extends Node
## Starts the Funplay MCP runtime bridge (play-mode control for the editor's
## MCP server) in desktop debug runs only. The web build leaves the addon out.

func _ready() -> void:
	if OS.is_debug_build() and not OS.has_feature("web"):
		var path: String = "res://addons/funplay_mcp/runtime/funplay_mcp_runtime_bridge.gd"
		if ResourceLoader.exists(path):
			add_child((load(path) as GDScript).new())
