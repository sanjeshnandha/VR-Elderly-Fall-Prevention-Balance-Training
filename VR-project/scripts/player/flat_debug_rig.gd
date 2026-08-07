class_name FlatDebugRig
extends Node3D
## Desktop testing rig -- lets the whole application be driven with a keyboard
## and mouse when no headset is attached.
##
## This exists because iterating on room layout, hazard placement and the
## session script inside a headset is slow and, over a long session, genuinely
## unpleasant. `Cafezinhu/godot-vr-simulator` does the same job with more
## fidelity; this is the zero-dependency version and it activates automatically
## whenever OpenXR fails to initialise (see xr_player.gd).
##
##   W / A / S / D   walk
##   Mouse           look (Escape releases the cursor)
##   Left click      flag the hazard under the pointer
##   Right click     hold to grip -- also aims and fires the teleport arc
##   Q / E           lower / raise the simulated head height
##
## It is a development aid only. Nothing here runs when XR is active, and the
## session log records `xr_active` so desk-tested runs can be filtered out.

@export var enabled: bool = false: set = set_enabled

@export var move_speed: float = 2.0
@export var mouse_sensitivity: float = 0.0022
@export var eye_height: float = 1.60

var _player: XRPlayer
var _camera: XRCamera3D
var _pitch: float = 0.0
var _yaw: float = 0.0
var _mouse_captured: bool = false


func _ready() -> void:
	_player = get_parent() as XRPlayer
	if _player != null:
		_camera = _player.camera
	set_enabled(enabled)


func set_enabled(value: bool) -> void:
	enabled = value
	set_process(value)
	set_process_input(value)
	set_process_unhandled_input(value)
	if not value:
		if _mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_mouse_captured = false
		return

	if _camera == null and _player != null:
		_camera = _player.camera
	if _camera != null:
		_camera.position = Vector3(0.0, eye_height, 0.0)
		# XRCamera3D only becomes the active camera when XR is running, so make
		# it current explicitly for the flat view.
		_camera.current = true

	# Deliberately NOT capturing the mouse here. Grabbing the cursor during
	# start-up is unreliable on macOS and leaves you with a window you cannot
	# click out of. The first click inside the window captures it instead.
	_capture_mouse(false)
	print("[FlatDebugRig] Desktop controls active.")
	print("  Click the window to capture the mouse for looking around.")
	print("  WASD walk | left click flag | right click grab+teleport | Q/E height | Esc release")


func _capture_mouse(value: bool) -> void:
	_mouse_captured = value
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event.is_action_pressed("debug_toggle_mouse"):
		_capture_mouse(not _mouse_captured)
		get_viewport().set_input_as_handled()
		return

	# First click anywhere in the window takes the mouse; it does not also count
	# as a flag press, so you cannot accidentally flag a hazard on the click
	# that gives the window focus.
	if not _mouse_captured and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_capture_mouse(true)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _mouse_captured:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.4, 1.4)
		return

	if event.is_action_pressed("debug_flag"):
		for pointer in _find_all_pointers():
			pointer.trigger()
	elif event.is_action_pressed("debug_grab"):
		for grabber in _find_all_grabbers():
			grabber.set_grip(true)
		for teleporter in _find_all_teleporters():
			teleporter.begin_aim()
	elif event.is_action_released("debug_grab"):
		for grabber in _find_all_grabbers():
			grabber.set_grip(false)
		for teleporter in _find_all_teleporters():
			teleporter.commit()


func _process(delta: float) -> void:
	if _player == null or _camera == null:
		return

	# Drive the XRCamera3D directly. With XR off nothing else writes to it, so
	# the rest of the game -- probe tracking, sway measurement, teleport -- runs
	# through exactly the same code paths as it does in a headset.
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position.y = eye_height

	if Input.is_key_pressed(KEY_Q):
		eye_height = maxf(0.6, eye_height - delta * 0.6)
	if Input.is_key_pressed(KEY_E):
		eye_height = minf(2.0, eye_height + delta * 0.6)

	var input := Vector2(
		Input.get_action_strength("debug_move_right") - Input.get_action_strength("debug_move_left"),
		Input.get_action_strength("debug_move_back") - Input.get_action_strength("debug_move_forward")
	)
	if input.length_squared() > 0.0:
		var basis := Basis(Vector3.UP, _yaw)
		var motion := basis * Vector3(input.x, 0.0, input.y).normalized()
		_player.global_position += motion * move_speed * delta

	# Park the hands just in front of the face so the pointer and grab volumes
	# land somewhere sensible on a desktop.
	_pose_hand(_player.point_hand, Vector3(0.22, -0.18, -0.30))
	_pose_hand(_player.move_hand, Vector3(-0.22, -0.18, -0.30))


func _pose_hand(hand: XRController3D, offset: Vector3) -> void:
	if hand == null or _camera == null:
		return
	hand.transform = _camera.transform * Transform3D(Basis.IDENTITY, offset)


# ---------------------------------------------------------------------------
#  Helpers -- collect the interaction tools hanging off the rig
# ---------------------------------------------------------------------------

func _find_all_pointers() -> Array[HazardPointer]:
	var out: Array[HazardPointer] = []
	for node in _descendants(_player):
		var pointer := node as HazardPointer
		if pointer != null:
			out.append(pointer)
	return out


func _find_all_grabbers() -> Array[GrabController]:
	var out: Array[GrabController] = []
	for node in _descendants(_player):
		var grabber := node as GrabController
		if grabber != null:
			out.append(grabber)
	return out


func _find_all_teleporters() -> Array[Teleporter]:
	var out: Array[Teleporter] = []
	for node in _descendants(_player):
		var teleporter := node as Teleporter
		if teleporter != null:
			out.append(teleporter)
	return out


func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	if root == null:
		return out
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			out.append(child)
			stack.append(child)
	return out
