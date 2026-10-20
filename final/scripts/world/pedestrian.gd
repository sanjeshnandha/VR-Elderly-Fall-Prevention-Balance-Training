@tool
class_name Pedestrian
extends Node3D
## Somebody else on the pavement.
##
## An empty street is a strange place, and it also teaches the wrong thing: a
## participant who only ever sees an empty crossing never sees what people
## normally do at one. So there are a few of these walking about, and one of them
## waits at the kerb for the green man and crosses on it. Watching somebody else
## do it correctly is worth more than another spoken instruction.
##
## They are deliberately NOT solid. A moving obstacle that can corner a person
## against a wall is the one thing worse for this cohort than an empty street,
## and the participant's own collision (flat_debug_rig.gd) cannot push anything
## out of the way. Instead, a pedestrian who finds the participant in front of
## them simply stops and waits, which is also what a person would do.
##
## Walks a polyline and loops. Everything is driven from `path_points`, so a new
## one is a node with four numbers in it.

## Where they walk, in this node's parent's space. Two points is a there-and-back.
@export var path_points: Array[Vector3] = []: set = _set_path

## Metres per second. 1.1 is an unhurried older adult; 1.4 is brisk.
@export var speed: float = 1.1

## Seconds spent standing at each end before turning round.
@export var pause_seconds: float = 2.0

## Seconds before they set off at all, so a row of them is not in lockstep.
@export var start_delay: float = 0.0

## The signal to obey, and the point indices they wait for the green man BEFORE
## walking to. Two of them for a round trip: stepping off the near kerb and
## stepping off the far one. Empty for somebody who never crosses the road.
##
## Both directions matter. With only the outward leg listed they would cross
## properly, reach the far pavement, turn round and walk straight back across on
## a red man -- which is worse than not modelling the behaviour at all, because
## the participant is being shown it.
@export var signal_path: NodePath
@export var wait_for_walk_at: Array[int] = []

## Stops when the participant is this close in front of them.
@export var yield_distance: float = 1.2

@export_group("Build")
## No setters on these, deliberately: a setter that does not assign its own
## property throws the scene's value away silently, and one shared setter for
## four properties of three different types cannot assign them all. The values
## are applied before _ready() either way; `rebuild` covers editing.
@export var height: float = 1.70
@export var coat_color: Color = Color(0.28, 0.33, 0.42)
@export var trouser_color: Color = Color(0.2, 0.21, 0.24)
@export var skin_color: Color = Color(0.78, 0.63, 0.52)
@export var rebuild: bool = false: set = _set_rebuild

const GROUP := "pedestrian_part"
## Degrees the legs and arms swing through at full stride.
const SWING := 28.0

var _index: int = 0
var _target: int = 1
var _wait: float = 0.0
var _stride: float = 0.0
var _signal: TrafficSignal
var _probe: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("pedestrian")
	_wait = start_delay
	_signal = get_node_or_null(signal_path) as TrafficSignal
	if _signal == null:
		_signal = get_tree().get_first_node_in_group("traffic_signal") as TrafficSignal
	if path_points.size() >= 1:
		position = path_points[0]


func _set_path(value: Array[Vector3]) -> void:
	path_points = value
	_index = 0
	_target = 1
	if is_inside_tree() and path_points.size() >= 1:
		position = path_points[0]


func _set_rebuild(_value: bool) -> void:
	rebuild = false
	if is_inside_tree():
		_build()


# ---------------------------------------------------------------------------
#  Walking
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or path_points.size() < 2:
		return

	if _wait > 0.0:
		_wait -= delta
		_settle(delta)
		return

	# Waiting at the kerb for the green man, like everybody else.
	if wait_for_walk_at.has(_target) and _signal != null and not _signal.is_walk():
		_settle(delta)
		return

	var goal: Vector3 = path_points[_target]
	var to_goal := goal - position
	to_goal.y = 0.0
	var distance := to_goal.length()
	if distance < 0.08:
		_arrive()
		return

	var direction := to_goal / distance
	rotation.y = atan2(direction.x, direction.z)

	# Somebody standing in the way is waited for, not walked through.
	if _participant_in_front(direction):
		_settle(delta)
		return

	var step := minf(speed * delta, distance)
	position += direction * step
	_stride += step
	_swing(sin(_stride * 3.6) * SWING)


func _arrive() -> void:
	_index = _target
	_target = (_target + 1) % path_points.size()
	_wait = pause_seconds


## Bring the legs back together while standing still.
func _settle(delta: float) -> void:
	_stride = move_toward(_stride, 0.0, delta * 4.0)
	_swing(sin(_stride * 3.6) * SWING)


func _swing(degrees: float) -> void:
	for i in _legs.size():
		var limb := _legs[i]
		if is_instance_valid(limb):
			limb.rotation_degrees.x = degrees if i == 0 else -degrees
	for i in _arms.size():
		var limb := _arms[i]
		if is_instance_valid(limb):
			limb.rotation_degrees.x = -degrees * 0.6 if i == 0 else degrees * 0.6


func _participant_in_front(direction: Vector3) -> bool:
	if _probe == null or not is_instance_valid(_probe):
		var player := get_tree().get_first_node_in_group("xr_player")
		if player != null:
			_probe = player.get("probe") as Node3D
	if _probe == null or not is_instance_valid(_probe):
		return false
	var to_them := _probe.global_position - global_position
	to_them.y = 0.0
	if to_them.length() > yield_distance:
		return false
	return to_them.normalized().dot(direction) > 0.2


# ---------------------------------------------------------------------------
#  Building one
# ---------------------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		if child.is_in_group(GROUP):
			child.free()
	_legs.clear()
	_arms.clear()

	var leg_length := height * 0.47
	var torso_height := height * 0.33
	var head_radius := height * 0.072

	for side in [-1.0, 1.0]:
		var hip := _pivot(Vector3(side * height * 0.055, leg_length, 0.0))
		_block(hip, Vector3(height * 0.085, leg_length, height * 0.09),
			Vector3(0.0, -leg_length * 0.5, 0.0), trouser_color)
		_legs.append(hip)

	_block(self, Vector3(height * 0.24, torso_height, height * 0.15),
		Vector3(0.0, leg_length + torso_height * 0.5, 0.0), coat_color)

	for side in [-1.0, 1.0]:
		var shoulder := _pivot(Vector3(side * height * 0.145,
			leg_length + torso_height * 0.92, 0.0))
		_block(shoulder, Vector3(height * 0.055, torso_height * 0.95, height * 0.07),
			Vector3(0.0, -torso_height * 0.48, 0.0), coat_color)
		_arms.append(shoulder)

	_block(self, Vector3(head_radius * 2.0, head_radius * 2.2, head_radius * 1.9),
		Vector3(0.0, leg_length + torso_height + head_radius * 1.05, 0.0), skin_color)


func _pivot(at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.add_to_group(GROUP)
	node.position = at
	add_child(node)
	return node


func _block(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var mesh := AutoShape.make_box_mesh(size, colour, 0.75, "", minf(size.x, size.z) * 0.3)
	mesh.add_to_group(GROUP)
	mesh.position = at
	parent.add_child(mesh)
