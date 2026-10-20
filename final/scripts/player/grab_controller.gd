class_name GrabController
extends Node3D
## Core System B, player side -- the grip button, and nothing else.
##
## Architectural Fix 5.4: the middle-finger grip is bound to exactly one verb,
## "take hold of this", and it works identically on a handrail, a grab bar and
## the balance orb. There is no context in which grip does something different,
## because a modal control is precisely what a first-time user cannot track.
##
## Grab is *proximity* based rather than ray based. Reaching out and closing
## your hand around a rail is the real-world motion we are rehearsing; making
## the participant aim a laser at the rail first would teach the wrong thing.

signal grabbed(target: Node3D)
signal released(target: Node3D)

## Radius of the grab sphere around the palm, in metres. Generous on purpose:
## proprioception in VR is poor, and a missed grab reads as "the rail is
## broken", not "I missed".
@export var grab_radius: float = 0.14

## Name of the boolean OpenXR action used to grab.
@export var grab_action: String = "grip_click"

## Offset from the controller origin to the palm centre.
@export var palm_offset: Vector3 = Vector3(0.0, -0.02, -0.05)

var held: Node3D = null
var is_gripping: bool = false

var _controller: XRController3D
var _area: Area3D
var _hand_visual: MeshInstance3D


func _ready() -> void:
	_controller = _find_controller()
	position = palm_offset

	_area = Area3D.new()
	_area.name = "GrabArea"
	# Grabbable things live on layer 4; the detector masks only that layer, so
	# grip can never latch onto a wall. The hand itself sits on layer 7 so
	# in-world buttons can notice a physical push without the teleport ray or
	# the hazard pointer ever colliding with the participant's own hand.
	_area.collision_layer = 1 << 6
	_area.collision_mask = 1 << 3
	_area.monitoring = true
	_area.add_to_group("hand_grab_area")

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = grab_radius
	shape.shape = sphere
	_area.add_child(shape)
	add_child(_area)

	_build_hand_visual()

	if _controller != null:
		_controller.button_pressed.connect(_on_button_pressed)
		_controller.button_released.connect(_on_button_released)


func _find_controller() -> XRController3D:
	var node: Node = get_parent()
	while node != null:
		var controller := node as XRController3D
		if controller != null:
			return controller
		node = node.get_parent()
	return null


# ---------------------------------------------------------------------------
#  Input
# ---------------------------------------------------------------------------

func _on_button_pressed(action_name: String) -> void:
	if action_name != grab_action:
		return
	is_gripping = true
	_try_grab()
	_update_hand_visual()


func _on_button_released(action_name: String) -> void:
	if action_name != grab_action:
		return
	is_gripping = false
	_release()
	_update_hand_visual()


## Public equivalent of the grip button. Used by the desktop debug rig.
func set_grip(value: bool) -> void:
	if is_gripping == value:
		return
	is_gripping = value
	if value:
		_try_grab()
	else:
		_release()
	_update_hand_visual()


func _try_grab() -> void:
	if held != null:
		return
	_grab(_nearest_grabbable())


## Take hold of one specific object, without searching for it.
##
## The desktop rig uses this after moving the hand onto a rail: the grab volume
## only learns it has moved when the physics engine next runs, and by then the
## grip has been and gone with nothing held. Telling the hand what it is
## holding removes that race entirely.
func grab_specific(target: Node3D) -> void:
	if held != null:
		return
	is_gripping = true
	_grab(target)
	_update_hand_visual()


func _grab(target: Node3D) -> void:
	if target == null:
		return

	if target is GrabRail:
		if not (target as GrabRail).grab(self):
			return
	elif target.has_method("grab"):
		if not target.call("grab", self):
			return

	held = target
	# A rail auto-releases when the hand drifts out of its reach while the grip
	# is still squeezed. Hear about it, so `held` and the green palm never claim
	# a hold that no longer exists.
	if target is GrabRail:
		var rail := target as GrabRail
		if not rail.released.is_connected(_on_rail_released):
			rail.released.connect(_on_rail_released)
	AudioCues.play("confirm")
	SessionManager.log_event("grab", {"target": target.name})
	grabbed.emit(target)


func _on_rail_released(hand: Node3D) -> void:
	if hand != self or held == null:
		return
	var target := held
	held = null
	(target as GrabRail).released.disconnect(_on_rail_released)
	SessionManager.log_event("release", {"target": target.name, "reason": "out_of_reach"})
	released.emit(target)
	_update_hand_visual()


func _release() -> void:
	if held == null:
		return
	var target := held
	held = null
	if target is GrabRail:
		var rail := target as GrabRail
		if rail.released.is_connected(_on_rail_released):
			rail.released.disconnect(_on_rail_released)
		rail.release(self)
	elif target.has_method("release"):
		target.call("release", self)
	SessionManager.log_event("release", {"target": target.name})
	released.emit(target)


## Closest overlapping grabbable. Nearest-first so two rails side by side behave
## predictably.
func _nearest_grabbable() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	var palm := _area.global_position

	for area in _area.get_overlapping_areas():
		var candidate: Node3D = area
		if not candidate.has_method("grab"):
			# Allow the graspable Area3D to be a child of the real target.
			var parent := candidate.get_parent() as Node3D
			if parent != null and parent.has_method("grab"):
				candidate = parent
			else:
				continue
		if candidate is GrabRail and not (candidate as GrabRail).can_grab(self):
			continue

		var point := palm
		if candidate is GrabRail:
			point = (candidate as GrabRail).closest_hold_point(palm)
		else:
			point = candidate.global_position
		var distance := palm.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = candidate

	return best


# ---------------------------------------------------------------------------
#  Hand visual -- an open palm that closes when gripping
# ---------------------------------------------------------------------------

func _build_hand_visual() -> void:
	_hand_visual = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.03, 0.11)
	_hand_visual.mesh = box
	add_child(_hand_visual)
	_update_hand_visual()


func _update_hand_visual() -> void:
	var mat := StandardMaterial3D.new()
	if held != null:
		mat.albedo_color = Color(0.15, 0.95, 0.35)
	elif is_gripping:
		mat.albedo_color = Color(0.9, 0.9, 0.55)
	else:
		mat.albedo_color = Color(0.85, 0.78, 0.72)
	mat.roughness = 0.7
	_hand_visual.material_override = mat
	# Closing the hand narrows it slightly -- a legible cue at a glance without
	# needing a rigged hand model.
	_hand_visual.scale = Vector3(0.75, 1.0, 0.85) if is_gripping else Vector3.ONE
