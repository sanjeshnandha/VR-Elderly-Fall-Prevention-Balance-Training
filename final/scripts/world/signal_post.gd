@tool
class_name SignalPost
extends Node3D
## One pole at the crossing: either a traffic head or a pedestrian head.
##
## All of them read the same `TrafficSignal`; none of them decides anything.
## Splitting the controller from the posts is what lets the crossing have a
## primary and a secondary head showing the same thing without two timers that
## can drift apart -- the bug that would be invisible in the editor and obvious,
## and alarming, in a headset.
##
## THE FIGURES ARE A TEXTURE, NOT A MESH. `tools/make_textures.py` draws the red
## man and the green man as white-on-black masks, used as both the albedo and
## the emission map so the black is the unlit housing and the figure is what
## glows. A lamp that is off still shows its figure faintly, because a real lens
## does.
##
## The push button is a `WallButton`, the same node the wall panel uses, so it
## can be pressed by pointing and pulling the trigger OR by reaching out and
## touching it -- which is Architectural Fix 5.4 applied to the street.

enum Kind { TRAFFIC, PEDESTRIAN }

@export_enum("Traffic:0", "Pedestrian:1") var kind: int = Kind.TRAFFIC

@export var controller_path: NodePath

## Yaw of the head, in degrees. At 0 the head looks along -Z.
@export var facing_degrees: float = 0.0

## Build a second head looking the other way. Used on the far pole, which has to
## be read both from across the road and by someone standing beside it.
@export var back_to_back: bool = false

## A press-to-cross button on this pole.
@export var has_button: bool = false

@export var pole_height: float = 2.65
@export var head_height: float = 2.15

## Seconds remaining, shown under a pedestrian head.
@export var show_countdown: bool = true

@export var pole_color: Color = Color("#3b3f44")

const RED := Color(0.95, 0.18, 0.14)
const AMBER := Color(1.0, 0.64, 0.08)
const GREEN := Color(0.20, 0.88, 0.32)
const OFF_FACTOR := 0.10
const FIG_STAND := "res://assets/textures/signal_stand.png"
const FIG_WALK := "res://assets/textures/signal_walk.png"

var _controller: TrafficSignal
var _lamps: Array[StandardMaterial3D] = []      # per head, in build order
var _kinds: Array[String] = []                  # "red" / "amber" / "green" / "stand" / "walk"
var _countdowns: Array[Label3D] = []
var _flash_t: float = 0.0
var _flash_on: bool = true


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		set_process(false)
		return
	_controller = get_node_or_null(controller_path) as TrafficSignal
	if _controller == null:
		_controller = get_tree().get_first_node_in_group("traffic_signal") as TrafficSignal
	if _controller != null:
		_controller.phase_changed.connect(_on_phase_changed)
	_apply()


func _process(delta: float) -> void:
	if _controller == null or not is_instance_valid(_controller):
		return
	# The flashing green man, and the countdown, are the only things that change
	# between phases, so nothing else is touched per frame.
	if _controller.is_clearing():
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash_t = 0.5
			_flash_on = not _flash_on
			_apply()
	_update_countdown()


func _on_phase_changed(_phase: int) -> void:
	_flash_t = 0.5
	_flash_on = true
	_apply()


# ---------------------------------------------------------------------------
#  Lighting the right lamp
# ---------------------------------------------------------------------------

func _apply() -> void:
	if _controller == null or not is_instance_valid(_controller):
		return
	var p: int = _controller.phase
	for i in _lamps.size():
		var on := false
		match _kinds[i]:
			"red":
				on = p != TrafficSignal.Phase.TRAFFIC_GREEN and p != TrafficSignal.Phase.TRAFFIC_AMBER
			"amber":
				on = p == TrafficSignal.Phase.TRAFFIC_AMBER
			"green":
				on = p == TrafficSignal.Phase.TRAFFIC_GREEN
			"stand":
				on = not (_controller.is_walk() or _controller.is_clearing())
			"walk":
				on = _controller.is_walk() or (_controller.is_clearing() and _flash_on)
		_light(_lamps[i], _base_colour(_kinds[i]), on)


func _base_colour(lamp_kind: String) -> Color:
	match lamp_kind:
		"amber":
			return AMBER
		"green", "walk":
			return GREEN
		_:
			return RED


func _light(material: StandardMaterial3D, colour: Color, on: bool) -> void:
	if on:
		material.albedo_color = colour
		material.emission = colour
		material.emission_energy_multiplier = 1.8
	else:
		material.albedo_color = colour * OFF_FACTOR
		material.emission = colour * OFF_FACTOR
		material.emission_energy_multiplier = 0.2


func _update_countdown() -> void:
	if _countdowns.is_empty() or _controller == null:
		return
	var text := ""
	if _controller.is_walk() or _controller.is_clearing():
		text = str(int(ceil(_controller.remaining())))
	var colour := GREEN if _controller.is_walk() else AMBER
	for label in _countdowns:
		# Only when it actually changes: assigning Label3D.text re-renders its
		# texture, and this runs every frame on every post.
		if label.text != text:
			label.text = text
			label.modulate = colour


# ---------------------------------------------------------------------------
#  Building it
# ---------------------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		child.free()
	_lamps.clear()
	_kinds.clear()
	_countdowns.clear()

	_box(self, Vector3(0.24, 0.09, 0.24), Vector3(0.0, 0.045, 0.0), Color("#2b2e32"))
	_box(self, Vector3(0.085, pole_height, 0.085),
		Vector3(0.0, pole_height * 0.5 + 0.08, 0.0), pole_color)

	_head(facing_degrees)
	if back_to_back:
		_head(facing_degrees + 180.0)

	if has_button:
		var button := WallButton.new()
		button.name = "DemandButton"
		button.label_text = "PRESS"
		button.sub_label_text = "wait for the green man"
		button.button_size = Vector2(0.2, 0.13)
		button.base_color = Color("#43484e")
		button.hover_color = Color("#6c737b")
		button.press_color = Color("#f2c14b")
		# The head looks along -Z; a WallButton's face looks along +Z, so it is
		# turned to look the same way as the head.
		button.rotation_degrees = Vector3(0.0, facing_degrees + 180.0, 0.0)
		button.position = Vector3(0.0, 1.08, 0.0).rotated(Vector3.UP, deg_to_rad(facing_degrees))
		button.position += Vector3(0.0, 0.0, -0.075).rotated(Vector3.UP, deg_to_rad(facing_degrees))
		add_child(button)
		if not Engine.is_editor_hint():
			button.pressed.connect(_on_button)


func _on_button() -> void:
	if _controller != null:
		_controller.request_walk()


func _head(yaw: float) -> void:
	var head := Node3D.new()
	head.rotation_degrees = Vector3(0.0, yaw, 0.0)
	add_child(head)

	if kind == Kind.TRAFFIC:
		_box(head, Vector3(0.28, 0.84, 0.22), Vector3(0.0, head_height + 0.18, 0.0),
			Color("#1c1f22"))
		_lamp(head, Vector3(0.0, head_height + 0.46, -0.12), 0.17, "red", "")
		_lamp(head, Vector3(0.0, head_height + 0.18, -0.12), 0.17, "amber", "")
		_lamp(head, Vector3(0.0, head_height - 0.10, -0.12), 0.17, "green", "")
		# A peaked hood over each lamp, which is what stops low sun washing a
		# real signal out -- and what makes this read as a traffic light from a
		# distance rather than as three dots on a box.
		for dy in [0.46, 0.18, -0.10]:
			_box(head, Vector3(0.26, 0.02, 0.09),
				Vector3(0.0, head_height + dy + 0.105, -0.155), Color("#15181a"))
	else:
		_box(head, Vector3(0.34, 0.66, 0.2), Vector3(0.0, head_height + 0.1, 0.0),
			Color("#1c1f22"))
		_lamp(head, Vector3(0.0, head_height + 0.25, -0.11), 0.24, "stand", FIG_STAND)
		_lamp(head, Vector3(0.0, head_height - 0.05, -0.11), 0.24, "walk", FIG_WALK)
		if show_countdown:
			var label := Label3D.new()
			label.font_size = 72
			label.pixel_size = 0.0016
			label.outline_size = 20
			label.outline_modulate = Color(0.02, 0.02, 0.02)
			label.no_depth_test = true
			# Single-sided. A Label3D is double-sided by default, so the
			# countdown read as mirrored digits to anyone standing behind the
			# post -- which, on a back-to-back pedestrian head, is the person
			# waiting on the other kerb.
			label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			label.double_sided = false
			label.position = Vector3(0.0, head_height - 0.33, -0.12)
			label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
			head.add_child(label)
			_countdowns.append(label)


func _lamp(parent: Node3D, offset: Vector3, size: float, lamp_kind: String,
		figure_path: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mesh_instance.mesh = quad
	# A QuadMesh faces +Z; the head looks along -Z.
	mesh_instance.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	mesh_instance.position = offset

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	if not figure_path.is_empty() and ResourceLoader.exists(figure_path):
		var figure: Texture2D = load(figure_path)
		material.albedo_texture = figure
		material.emission_texture = figure
	_light(material, _base_colour(lamp_kind), false)
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	_lamps.append(material)
	_kinds.append(lamp_kind)


func _box(parent: Node3D, size: Vector3, offset: Vector3, colour: Color) -> void:
	var mesh_instance := AutoShape.make_box_mesh(size, colour, 0.5)
	mesh_instance.position = offset
	parent.add_child(mesh_instance)
