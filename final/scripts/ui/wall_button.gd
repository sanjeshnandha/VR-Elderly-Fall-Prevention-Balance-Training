@tool
class_name WallButton
extends Area3D
## Architectural Fix 5.4 -- menus are physical objects, not controller shortcuts.
##
## Every menu action in this project (start, seated mode, repeat instructions,
## finish) is a large button mounted on a wall or a stand at chest height. There
## is no "press menu to open settings", because a controller shortcut is a piece
## of hidden state a first-time user has no way to discover and every way to
## trigger by accident.
##
## Two ways to press it, and they are equivalent:
##   * reach out and touch it with your hand, or
##   * point at it and pull the trigger.
##
## 20 cm across. Fitts's law is unforgiving in VR, and a target this size is
## reachable with a tremor.

signal pressed

@export var label_text: String = "Start"
@export_multiline var sub_label_text: String = ""

## Face size in metres. Do not go below 0.15.
@export var button_size: Vector2 = Vector2(0.22, 0.14)

@export var base_color: Color = Color("#2e7d32")
@export var hover_color: Color = Color("#43a047")
@export var press_color: Color = Color("#a5d6a7")

## Minimum seconds between presses; stops a resting hand re-triggering.
@export var debounce: float = 0.8

## Label sizes. 40 px at 0.9 mm per pixel is 36 mm of cap height, which is
## comfortably readable across a hallway and leaves room for two wrapped lines
## inside a 0.18 m plate.
const LABEL_FONT := 40
const SUB_FONT := 30
const PIXEL_SIZE := 0.0009
## How far the labels stand off the plate. The plate is 0.05 thick, so this
## leaves 35 mm of clearance for a billboard that has turned to face somebody
## standing off to one side.
const LABEL_STANDOFF := 0.06

## Set false to grey the button out (e.g. "Finish" before the session ends).
@export var enabled: bool = true: set = set_enabled

var _face: MeshInstance3D
var _label: Label3D
var _sub_label: Label3D
var _last_press: float = -999.0
var _hovered: bool = false


func _ready() -> void:
	# Layer 6 "ui" so the hazard pointer ray finds it; masks layer 7 "hand" so a
	# physical touch also works.
	collision_layer = 1 << 5
	collision_mask = 1 << 6
	monitoring = true
	monitorable = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(button_size.x, button_size.y, 0.06)
	shape.shape = box
	add_child(shape)
	update_configuration_warnings()

	_face = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(button_size.x, button_size.y, 0.05)
	_face.mesh = mesh
	add_child(_face)

	# Both labels BILLBOARD, which is how every other label in this project that
	# works is built -- route_marker.gd and hazard.gd both do exactly this.
	#
	# A flat Label3D on a wall has to be oriented by hand, and getting that
	# wrong has now failed twice in opposite directions: first the text was
	# mirrored (the button faced into the wall, and a double-sided label shows
	# its back quite happily), then, with the buttons turned round and the
	# labels made single-sided, it vanished altogether. A billboarded label
	# cannot be wrong. It turns to the reader, from any approach, at any angle,
	# which is also simply better for somebody who walks up to a wall of
	# controls and needs to read them without squaring up to each one.
	#
	# Y-axis billboard, not full: wall signage should stay upright.
	#
	# `no_depth_test` is on, as it is on the hazard and route-marker labels, for
	# the same reason they have it. A billboard that has turned forty degrees to
	# face somebody standing off to one side sweeps its far corner back through
	# the plate it is mounted on, and the word disappears into the wall. Drawing
	# the text over everything costs a button label faintly visible through a
	# wall from the next room, which is a far smaller problem than a control
	# nobody can read.
	#
	# They are also WRAPPED to the plate. The text used to be laid out as one
	# unbroken line at 58 mm per character-height, so "Press again to erase"
	# came out about 0.6 m wide on a 0.30 m plate, running off both sides and
	# across its neighbours.
	_label = Label3D.new()
	_label.text = label_text
	_label.font_size = LABEL_FONT
	_label.pixel_size = PIXEL_SIZE
	_label.width = button_size.x / PIXEL_SIZE * 0.92
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.double_sided = false
	_label.no_depth_test = true
	_label.modulate = Color("#ffffff")
	_label.outline_size = 14
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.position = Vector3(0.0, 0.0, LABEL_STANDOFF)
	add_child(_label)

	if not sub_label_text.is_empty():
		_sub_label = Label3D.new()
		_sub_label.text = sub_label_text
		_sub_label.font_size = SUB_FONT
		_sub_label.pixel_size = PIXEL_SIZE
		# A little wider than the plate: the sub-label hangs below it, where
		# there is nothing to overlap.
		_sub_label.width = button_size.x / PIXEL_SIZE * 1.25
		_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sub_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_sub_label.double_sided = false
		_sub_label.no_depth_test = true
		_sub_label.modulate = Color("#e8e8e8")
		_sub_label.outline_size = 11
		_sub_label.outline_modulate = Color(0, 0, 0, 0.9)
		_sub_label.position = Vector3(0.0, -button_size.y * 0.5 - 0.055, LABEL_STANDOFF)
		add_child(_sub_label)

	_apply_color(base_color)
	if Engine.is_editor_hint():
		return
	area_entered.connect(_on_area_entered)


func set_enabled(value: bool) -> void:
	enabled = value
	if _face != null:
		_hovered = _hovered and value
		_apply_color(base_color if value else Color("#4a4a4f"))
		# Deferred: a stage change is often triggered by a hand touching THIS
		# button, i.e. from inside its own area_entered signal, where Godot
		# blocks direct changes to `monitoring`.
		set_deferred("monitoring", value)
		input_ray_pickable = value


func set_label(text: String) -> void:
	label_text = text
	if _label != null:
		_label.text = text


func set_sub_label(text: String) -> void:
	sub_label_text = text
	if _sub_label != null:
		_sub_label.text = text


## Pointer hover feedback.
func set_hovered(value: bool) -> void:
	if not enabled or _hovered == value:
		return
	_hovered = value
	_apply_color(hover_color if value else base_color)


func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("hand_grab_area"):
		press()


## Activate. Called by the hazard pointer, by a physical hand touch, or directly.
func press() -> void:
	if not enabled:
		AudioCues.play("reject")
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_press < debounce:
		return
	_last_press = now

	_apply_color(press_color)
	AudioCues.play("page")
	SessionManager.log_event("button_pressed", {"button": name, "label": label_text})
	pressed.emit()

	await get_tree().create_timer(0.18).timeout
	if is_instance_valid(self):
		_apply_color(hover_color if _hovered else base_color)


func _apply_color(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	mat.roughness = 0.5
	_face.material_override = mat
