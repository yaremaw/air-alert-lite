# Godot 4.7.2 web export template for Strike Alert, cut down to what the game
# uses: 2D drawing, GDScript, fonts (with OpenType features), WebP and PNG
# images, WAV sound, FastNoiseLite and the browser bridge. Everything else is
# left out so the engine downloads and starts faster.
#
# Used by tools/web_engine/build.sh (scons profile=<this file>).

platform = "web"
# (target=template_release and optimize=size are given on build.sh's command
# line: the web platform's defaults would override them here.)
threads = "no"  # matches the Web export preset (thread support off)
lto = "full"
deprecated = "no"

disable_3d = "yes"
disable_advanced_gui = "yes"  # RichTextLabel, TextEdit, Tree, OptionButton, dialogs...
disable_physics_2d = "yes"
disable_physics_3d = "yes"
disable_navigation_2d = "yes"
disable_navigation_3d = "yes"
disable_xr = "yes"
minizip = "no"
brotli = "no"

modules_enabled_by_default = "no"
module_gdscript_enabled = "yes"
module_text_server_adv_enabled = "yes"
module_freetype_enabled = "yes"
module_svg_enabled = "yes"  # the default theme's icons are SVG
module_webp_enabled = "yes"  # the home screen picture
module_noise_enabled = "yes"  # FastNoiseLite, for generating maps
graphite = "no"
