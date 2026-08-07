class_name XRPlayer
extends XROrigin3D
## The player rig. Owns XR start-up, hand-role assignment, the player probe that
## world triggers detect, and the single entry point for moving the player.
##
## HAND ROLES (Architectural Fix 5.4)
## ----------------------------------
##   Move hand   : trigger = show teleport beam, release = go.
##   Point hand  : trigger = flag the hazard under the pointer.
##   Both hands  : grip    = take hold of a rail or the balance orb.
##
## Two buttons, and each hand does exactly one thing with its trigger. Nothing
## is modal, nothing is a double-press, and there is no menu button to hit by
## accident. Left-handed participants are handled by `Settings` swapping which
## physical controller drives which role -- the instructions never change.
##
## If OpenXR fails to start (no headset plugged in), the rig silently falls back
## to a keyboard/mouse debug camera so the project still runs on a desk.

signal xr_started
signal xr_failed

@export var camera_path: NodePath = ^"XRCamera3D"
@export var probe_path: NodePath = ^"PlayerProbe"
@export var left_controller_path: NodePath = ^"LeftHand"
@export var right_controller_path: NodePath = ^"RightHand"
@export var flat_rig_path: NodePath = ^"FlatDebugRig"

## Swap which physical controller moves and which points. Left-handers usually
## prefer to point with the left.
@export var left_handed: bool = false

var camera: XRCamera3D
var probe: Area3D
var move_hand: XRController3D
var point_hand: XRController3D
var xr_active: bool = false

var _left: XRController3D
var _right: XRController3D
var _flat_rig: Node3D
var _interface: XRInterface


func _ready() -> void:
	camera = get_node_or_null(camera_path) as XRCamera3D
	probe = get_node_or_null(probe_path) as Area3D
	_left = get_node_or_null(left_controller_path) as XRController3D
	_right = get_node_or_null(right_controller_path) as XRController3D
	_flat_rig = get_node_or_null(flat_rig_path) as Node3D

	add_to_group("xr_player")
	_assign_hand_roles()
	_start_xr()


# ---------------------------------------------------------------------------
#  XR start-up
# ---------------------------------------------------------------------------

func _start_xr() -> void:
	print("[XRPlayer] Booting on %s. Looking for an OpenXR runtime..." % OS.get_name())

	# macOS note: Godot has no usable OpenXR runtime on macOS, so this always
	# takes the fallback branch there and the desktop rig engages. The VR build
	# has to be tested on Windows or Linux with SteamVR running.
	_interface = XRServer.find_interface("OpenXR")
	if _interface != null and _interface.is_initialized():
		_enable_xr()
		return
	if _interface != null and _interface.initialize():
		_enable_xr()
		return

	print("[XRPlayer] No OpenXR runtime. Desktop debug rig active (WASD + mouse).")
	xr_active = false
	if _flat_rig != null:
		_flat_rig.set("enabled", true)
	xr_failed.emit()


func _enable_xr() -> void:
	xr_active = true
	print("[XRPlayer] OpenXR initialised. Headset active.")
	# Let the compositor drive presentation; vsync must be off or the headset
	# and the monitor fight over frame pacing.
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _flat_rig != null:
		_flat_rig.set("enabled", false)
	xr_started.emit()


# ---------------------------------------------------------------------------
#  Hand roles
# ---------------------------------------------------------------------------

func _assign_hand_roles() -> void:
	if _left == null or _right == null:
		push_error("XRPlayer: controller nodes not found.")
		return
	if left_handed:
		move_hand = _right
		point_hand = _left
	else:
		move_hand = _left
		point_hand = _right

	# Children read their role from the parent controller's meta rather than
	# being wired up per-hand in the editor, so swapping is a one-line change.
	move_hand.set_meta("role", "move")
	point_hand.set_meta("role", "point")

	# Both hands carry both tools; exactly one is live on each hand.
	_set_role_tools(move_hand, true, false)
	_set_role_tools(point_hand, false, true)


func _set_role_tools(hand: XRController3D, teleport: bool, point: bool) -> void:
	for node in _descendants(hand):
		if node is Teleporter:
			(node as Teleporter).set_teleport_enabled(teleport)
		elif node is HazardPointer:
			(node as HazardPointer).set_pointer_enabled(point)


func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			out.append(child)
			stack.append(child)
	return out


# ---------------------------------------------------------------------------
#  Probe -- the body that world Area3Ds actually detect
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if camera == null or probe == null:
		return
	# Keep the probe under the headset horizontally, at origin height. Handrail
	# zones, slip zones and gated regions all test against this, so they respond
	# to where the participant physically walked -- not where the rig sits.
	var local := camera.transform.origin
	probe.position = Vector3(local.x, probe.position.y, local.z)


# ---------------------------------------------------------------------------
#  Movement -- the ONLY way anything relocates the player
# ---------------------------------------------------------------------------

## Move so the participant's *feet* land on `target_position`, optionally facing
## `yaw_degrees`. Works in both standing and seated mode because it compensates
## for wherever the headset currently is inside the play space.
func teleport_to(target_position: Vector3, yaw_degrees: float = NAN) -> void:
	if camera == null:
		global_position = target_position
		return

	if not is_nan(yaw_degrees):
		# Rotate the origin so the camera ends up facing the requested yaw,
		# pivoting about the camera rather than the origin -- otherwise the
		# participant gets swung sideways through the room.
		var camera_yaw := camera.global_rotation.y
		var delta_yaw := deg_to_rad(yaw_degrees) - camera_yaw
		var pivot := camera.global_position
		var offset := global_position - pivot
		offset = offset.rotated(Vector3.UP, delta_yaw)
		global_position = pivot + offset
		rotate_y(delta_yaw)

	# Horizontal offset between the origin and where the head actually is.
	var head_offset := camera.global_position - global_position
	head_offset.y = 0.0
	global_position = target_position - head_offset

	SessionManager.log_event("teleport", {
		"to": [snappedf(target_position.x, 0.01), snappedf(target_position.y, 0.01), snappedf(target_position.z, 0.01)],
	})


## Head position in world space, or the origin if XR has not started.
func head_position() -> Vector3:
	return camera.global_position if camera != null else global_position


func head_basis() -> Basis:
	return camera.global_transform.basis if camera != null else global_transform.basis
