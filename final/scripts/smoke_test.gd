extends Node3D
## Diagnostic scene. Deliberately depends on NOTHING in this project -- no
## autoloads, no custom classes, no XR, no shaders.
##
## Run it with the scene open and F6 ("Run Current Scene").
##
##   * A window opens with a spinning green box and white text
##       -> Godot, macOS and your run settings are fine. Any problem is inside
##          main.tscn, and the Output panel will say what.
##   * Nothing happens at all
##       -> the problem is in the editor's run configuration, not the project.
##          Check Editor Settings > Run > Window Placement > Game Embed Mode is
##          Disabled, and look in Debugger > Errors.

var _box: MeshInstance3D
var _elapsed: float = 0.0


func _ready() -> void:
	print("=========================================")
	print("  SMOKE TEST RUNNING")
	print("  Godot version : %s" % Engine.get_version_info().get("string", "?"))
	print("  Platform      : %s" % OS.get_name())
	print("  Renderer      : %s" % RenderingServer.get_video_adapter_name())
	print("  user:// path  : %s" % OS.get_user_data_dir())
	print("=========================================")

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.0, 3.0)
	camera.current = true
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	add_child(light)

	_box = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_box.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.4)
	_box.material_override = mat
	_box.position = Vector3(0.0, 1.0, 0.0)
	add_child(_box)

	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "SMOKE TEST OK\nGodot %s on %s\n\nIf you can read this, the engine runs fine\nand the problem is inside main.tscn." % [
		Engine.get_version_info().get("string", "?"), OS.get_name()
	]
	label.position = Vector2(24.0, 24.0)
	label.add_theme_font_size_override("font_size", 22)
	layer.add_child(label)


func _process(delta: float) -> void:
	_elapsed += delta
	if _box != null:
		_box.rotation.y += delta
	# One heartbeat per second proves the main loop is actually ticking.
	if int(_elapsed) != int(_elapsed - delta):
		print("[SmokeTest] running, %d s" % int(_elapsed))
