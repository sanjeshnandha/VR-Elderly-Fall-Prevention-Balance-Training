class_name FocusBeacon
extends Node3D
## Adaptive focus, in the world: a soft pulsing column of light with a label,
## standing at the doorway of the room the participant most needs to practise
## (the lowest recent score, chosen by SessionManager.compute_focus()).
##
## Placement comes from marker children named after the tests
## ("hallway", "bathroom", "staircase", "bedroom", "balance"). The beacon moves
## to the matching marker when a session starts and hides itself once the
## participant walks into that room (or starts the balance exercise), so it
## guides without nagging.
##
## Never moves or rotates the player, never blocks anything: it is a
## suggestion, not a gate.

@export var markers_path: NodePath = ^"."
@export var column_height: float = 2.0
@export var color: Color = Color(1.0, 0.83, 0.1)

var _column: MeshInstance3D
var _ring: MeshInstance3D
var _label: Label3D
var _focus_test: String = ""
var _pulse: float = 0.0


func _ready() -> void:
	_build()
	visible = false
	set_process(false)
	SessionManager.session_started.connect(_on_session_started)
	SessionManager.session_ended.connect(_on_session_ended)
	SessionManager.room_changed.connect(_on_room_changed)


## Show the beacon at the focus marker. Called by the director at the welcome
## stage too, so the participant can see where they are heading before START.
func show_for_focus(focus: Dictionary) -> void:
	_focus_test = str(focus.get("test", ""))
	var marker := _marker_for(_focus_test)
	if _focus_test.is_empty() or marker == null:
		visible = false
		set_process(false)
		return
	global_position = marker.global_position
	_label.text = "Today's focus\n%s" % str(focus.get("name", _focus_test.capitalize()))
	visible = true
	set_process(true)


func hide_beacon() -> void:
	visible = false
	set_process(false)


## The room that counts as having reached the focus. Every test is its own room
## except the road crossing, which is a test inside the street.
func _focus_room() -> String:
	return "street" if _focus_test == SessionManager.CROSSING_TEST else _focus_test


func _on_session_started() -> void:
	show_for_focus(SessionManager.current_focus)
	if SessionManager.current_room == _focus_room():
		hide_beacon()


func _on_session_ended(_summary: Dictionary) -> void:
	hide_beacon()


func _on_room_changed(room: String) -> void:
	if visible and room == _focus_room() and SessionManager.session_active:
		hide_beacon()


func _marker_for(test: String) -> Node3D:
	if test.is_empty():
		return null
	var root := get_node_or_null(markers_path)
	if root == null:
		return null
	return root.get_node_or_null(test) as Node3D


func _process(delta: float) -> void:
	_pulse += delta * 2.0
	var s := 1.0 + sin(_pulse) * 0.08
	_ring.scale = Vector3(s, 1.0, s)
	var mat := _column.material_override as StandardMaterial3D
	mat.albedo_color.a = 0.18 + 0.08 * (0.5 + 0.5 * sin(_pulse))


func _build() -> void:
	_column = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.34
	cyl.height = column_height
	cyl.radial_segments = 24
	cyl.cap_top = false
	cyl.cap_bottom = false
	_column.mesh = cyl
	_column.position = Vector3(0.0, column_height * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_column.material_override = mat
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_column)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.42
	_ring.mesh = torus
	_ring.position = Vector3(0.0, 0.02, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = color
	ring_mat.emission_enabled = true
	ring_mat.emission = color
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = ring_mat
	add_child(_ring)

	_label = Label3D.new()
	_label.font_size = 96
	_label.pixel_size = 0.0016
	_label.outline_size = 24
	_label.outline_modulate = Color(0.05, 0.05, 0.05)
	_label.modulate = color
	# Y-axis billboard: always readable, never tilts. Single sided so the back
	# of the text is never shown mirrored.
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.double_sided = false
	_label.no_depth_test = true
	_label.position = Vector3(0.0, column_height + 0.25, 0.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
