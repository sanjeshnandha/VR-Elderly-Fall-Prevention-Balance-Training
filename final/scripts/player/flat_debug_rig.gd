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
##   W / A / S / D   walk. Follows the ground: up stair treads, down the kerb,
##                   out of the front door. Still ignores WALLS and the stair
##                   gating -- a debug aid only; use the right-click teleport to
##                   exercise Fix 5.1 properly
##   Mouse           look (Escape releases the cursor)
##   Left click      flag / press whatever is under the crosshair
##   Space (hold)    grip: take hold of a handrail or the balance orb. The
##                   hand REACHES for whatever is within `desktop_reach` --
##                   a rail beside you, an orb in front of you -- because a
##                   desktop player cannot move a hand sideways the way someone
##                   in a headset just does. Without it you have to walk off
##                   the step you are standing on to touch the rail.
##   Right click     hold to aim the teleport arc, release to travel
##   Q / E           lower / raise the simulated head height
##   F10             researcher: end the session now (handled by SessionDirector,
##                   so it works from the PC keyboard in VR too)
##
## It is a development aid only. Nothing here runs when XR is active, and the
## session log records `settings.xr_active` so desk-tested runs can be
## filtered out.

@export var enabled: bool = false: set = set_enabled

@export var move_speed: float = 2.0
@export var mouse_sensitivity: float = 0.0022
@export var eye_height: float = 1.60

## How far the hand will reach for a rail or the balance orb when Space is
## held, in metres. Roughly a seated adult's arm plus a lean.
@export var desktop_reach: float = 1.3

## Tallest thing walking can step up, in metres. A 190 mm stair tread yes, a
## wall no.
@export var step_height: float = 0.45

## Walk INTO things instead of through them.
##
## This rig used to add the movement straight on to the rig's position, so WASD
## went through walls, through the sofa, out of the house and across the road.
## It is a swept capsule now: it slides along what it hits, steps over anything
## shorter than `step_clearance`, and stops at everything else.
##
## A headset participant teleports and never meets this, but the desktop rig is
## how the project is demonstrated and tested, and a walkthrough that goes
## through the wall of the bathroom is not a walkthrough of a house.
@export var collide_with_world: bool = true

## Half-width of the body, in metres. 0.22 is a shoulder's half-width plus a
## little; the doorways are 0.90, so there is 0.23 m of clearance each side.
@export var body_radius: float = 0.22

## Anything shorter than this is stepped over rather than walked into: the
## 130 mm kerb, a 190 mm stair tread, a threshold strip, a rug. Anything taller
## stops you.
@export var step_clearance: float = 0.26

## Height of the collision capsule. Shoulder height is what has to clear a
## doorway, not the top of the head.
@export var body_height: float = 1.70

## Held to walk through walls anyway: the old behaviour, kept deliberately. A
## researcher setting a scene up needs it, and if anything ever does trap the
## participant it is the way out.
@export var ghost_key: Key = KEY_SHIFT

## How quickly the eyes follow the ground up and down, in metres per second.
## Instant would be a jolt; this is a step, not a jump.
@export var ground_follow_speed: float = 6.0

var _player: XRPlayer
var _camera: XRCamera3D
var _pitch: float = 0.0
var _yaw: float = 0.0
var _mouse_captured: bool = false
var _reaching: bool = false
var _reach_target: Node3D = null
var _crosshair: CanvasLayer
var _body_shape: CapsuleShape3D
## Slide passes per frame. Two gets you along a wall and into a corner; a third
## is for the corner itself.
const SLIDE_PASSES := 3


func _ready() -> void:
	_player = get_parent() as XRPlayer
	if _player != null:
		_camera = _player.camera
	_body_shape = CapsuleShape3D.new()
	_body_shape.radius = body_radius
	_body_shape.height = maxf(body_height - step_clearance, body_radius * 2.0 + 0.01)
	set_enabled(enabled)


func set_enabled(value: bool) -> void:
	enabled = value
	set_process(value)
	set_process_input(value)
	set_process_unhandled_input(value)
	if _crosshair != null:
		_crosshair.visible = value
	if not value:
		if _mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_mouse_captured = false
		return
	if _crosshair == null and is_inside_tree():
		_build_crosshair()

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
	elif event.is_action_pressed("debug_grip"):
		# Space is the grip: the one verb that means "take hold of this".
		_reaching = true
		_reach_target = _nearest_grabbable()
		_grip_when_hand_arrives()
	elif event.is_action_released("debug_grip"):
		_reaching = false
		_reach_target = null
		for grabber in _find_all_grabbers():
			grabber.set_grip(false)
	elif event.is_action_pressed("debug_teleport"):
		for teleporter in _find_all_teleporters():
			teleporter.begin_aim()
	elif event.is_action_released("debug_teleport"):
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
		# Walk relative to where the CAMERA is looking in the world, not to
		# `_yaw`, which is only the camera's yaw within the rig. The rig itself
		# is rotated (the participant starts facing the instruction panel, and
		# every teleport can turn it again), so using `_yaw` alone made W/S and
		# A/D come out turned by whatever the rig's own rotation was.
		var facing := Basis(Vector3.UP, _camera.global_rotation.y)
		var motion := facing * Vector3(input.x, 0.0, input.y).normalized() \
			* move_speed * delta
		if collide_with_world and not Input.is_key_pressed(ghost_key):
			_player.global_position = _slide(_player.global_position, motion)
		else:
			_player.global_position += motion

	# Sample the ground AFTER moving, so a step is climbed the moment you reach
	# it rather than one frame later.
	_follow_ground(delta)

	# Park the hands just in front of the face so the pointer and grab volumes
	# land somewhere sensible on a desktop. Holding Space reaches them out to
	# arm's length (the balance orb sits 0.55 m from the head).
	var reach := -0.52 if _reaching else -0.30
	_pose_hand(_player.point_hand, Vector3(0.18, -0.16, reach))
	_pose_hand(_player.move_hand, Vector3(-0.18, -0.16, reach))
	# Put the grabbing hand ON the rail while Space is held, THEN aim the
	# pointer hand, so what you click is still what is under the crosshair even
	# when that hand is the one doing the holding.
	_apply_reach()
	_aim_at_crosshair(_player.point_hand)


## Move `from` by `motion`, sliding along whatever is in the way.
##
## A swept capsule rather than a ray: a ray from the eyes would walk the body
## through a table while the head passed over it. The capsule stands from
## `step_clearance` to `body_height`, so what it hits is what a person's shins
## and shoulders would hit, and anything below it is left to `_follow_ground()`
## to step up.
func _slide(from: Vector3, motion: Vector3) -> Vector3:
	var space := _player.get_world_3d().direct_space_state
	if space == null:
		return from + motion

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body_shape
	query.collision_mask = 1 << 0        # world geometry only
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var at := from
	var left := motion
	# If the capsule is already inside something -- spawned there, or pushed in
	# by the ground following a step -- push out first, or every cast below
	# returns zero and the rig is welded in place.
	at = _unstick(space, query, at)

	for _pass in SLIDE_PASSES:
		if left.length_squared() < 0.000001:
			break
		query.transform = Transform3D(Basis(), at + _capsule_offset())
		query.motion = left
		var result := space.cast_motion(query)
		var safe: float = result[0] if result.size() > 0 else 1.0
		at += left * safe
		if safe >= 0.999:
			return at
		# What did it hit? Slide the rest of the movement along that face. The
		# normal is flattened: a sloped surface should not launch the eyes.
		query.transform = Transform3D(Basis(), at + _capsule_offset())
		query.motion = Vector3.ZERO
		var rest := space.get_rest_info(query)
		if rest.is_empty():
			return at
		var normal: Vector3 = rest.get("normal", Vector3.ZERO)
		normal.y = 0.0
		if normal.length_squared() < 0.000001:
			return at
		left = (left * (1.0 - safe)).slide(normal.normalized())
	return at


## Push the body out of anything it is already standing inside.
func _unstick(space: PhysicsDirectSpaceState3D,
		query: PhysicsShapeQueryParameters3D, at: Vector3) -> Vector3:
	query.transform = Transform3D(Basis(), at + _capsule_offset())
	query.motion = Vector3.ZERO
	var rest := space.get_rest_info(query)
	if rest.is_empty():
		return at
	var normal: Vector3 = rest.get("normal", Vector3.ZERO)
	normal.y = 0.0
	if normal.length_squared() < 0.000001:
		return at
	# A small, steady nudge rather than a jump: being inside a wall should feel
	# like being eased out of it, not like being fired out of it.
	return at + normal.normalized() * 0.02


## The capsule stands between `step_clearance` and `body_height` above the feet.
func _capsule_offset() -> Vector3:
	return Vector3.UP * ((step_clearance + body_height) * 0.5)


## Keep the rig standing ON whatever is under it.
##
## Without this, walking is purely horizontal: you walk INTO the staircase and
## end up with your eyes at ground-floor height while your body stands on the
## tread above, which looks exactly as wrong as it sounds. In a headset the
## participant teleports and this never arises, but the desktop rig has to walk.
func _follow_ground(delta: float) -> void:
	if _player == null or not _player.is_inside_tree():
		return
	var origin := _player.global_position
	var query := PhysicsRayQueryParameters3D.create(
		origin + Vector3.UP * step_height, origin - Vector3.UP * 3.0
	)
	query.collision_mask = 1 << 0  # world geometry: floors, treads, pavements
	query.collide_with_areas = false
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	# Seated mode lifts the rig above the floor it is standing on; keep that.
	var target := float(hit["position"].y) + _player.seated_offset()
	_player.global_position.y = move_toward(origin.y, target, ground_follow_speed * delta)


func _pose_hand(hand: XRController3D, offset: Vector3) -> void:
	if hand == null or _camera == null:
		return
	hand.transform = _camera.transform * Transform3D(Basis.IDENTITY, offset)


## Nearest rail or orb the participant could plausibly take hold of.
func _nearest_grabbable() -> Node3D:
	if _camera == null:
		return null
	var head := _camera.global_position
	var best: Node3D = null
	var best_distance := desktop_reach
	for node in get_tree().get_nodes_in_group("grabbable"):
		var candidate := node as Node3D
		if candidate == null:
			continue
		var distance := head.distance_to(_hold_point(candidate, head))
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Where on that object the hand should land: the closest point along a rail,
## or the middle of anything else.
func _hold_point(target: Node3D, from: Vector3) -> Vector3:
	if target.has_method("closest_hold_point"):
		return target.call("closest_hold_point", from)
	return target.global_position


## Move the hand onto the hold point, then grip on the next physics frame --
## the grab volume's overlaps are only up to date once physics has run.
func _grip_when_hand_arrives() -> void:
	_apply_reach()
	var hand := _reach_hand() if _reach_target != null else null
	for grabber in _find_all_grabbers():
		if hand != null and hand.is_ancestor_of(grabber):
			# This is the hand that reached: hand it the target directly rather
			# than waiting for physics to report the new overlap.
			grabber.grab_specific(_reach_target)
		else:
			grabber.set_grip(true)


## Whichever hand is nearer the thing being reached for -- crossing the body to
## take a rail on your right with your left hand looks wrong and feels worse.
func _reach_hand() -> XRController3D:
	if _reach_target == null or _camera == null:
		return _player.move_hand
	var point := _hold_point(_reach_target, _camera.global_position)
	var move := _player.move_hand
	var pointer := _player.point_hand
	if move == null:
		return pointer
	if pointer == null:
		return move
	if pointer.global_position.distance_to(point) < move.global_position.distance_to(point):
		return pointer
	return move


## Keep the grabbing hand on the rail while Space is held, and let go if the
## participant walks away from it.
func _apply_reach() -> void:
	if not _reaching or _reach_target == null or _camera == null:
		return
	if not is_instance_valid(_reach_target):
		_reach_target = null
		return
	var hand := _reach_hand()
	if hand == null:
		return
	var head := _camera.global_position
	var point := _hold_point(_reach_target, head)
	if head.distance_to(point) > desktop_reach * 1.4:
		# Walked out of reach: release rather than stretch an arm across a room.
		_reaching = false
		_reach_target = null
		for grabber in _find_all_grabbers():
			grabber.set_grip(false)
		return
	hand.global_position = point


func _aim_at_crosshair(hand: XRController3D) -> void:
	if hand == null or _camera == null or not _camera.is_inside_tree():
		return
	var from := _camera.global_position
	var to := from - _camera.global_transform.basis.z * 6.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Same layers the hazard pointer uses: world, hazard, ui.
	query.collision_mask = (1 << 0) | (1 << 2) | (1 << 5)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit["position"] if not hit.is_empty() else to
	var hand_pos := hand.global_position
	if hand_pos.distance_to(target) > 0.05:
		hand.look_at(target, Vector3.UP)


func _build_crosshair() -> void:
	_crosshair = CanvasLayer.new()
	_crosshair.name = "Crosshair"
	var dot := Label.new()
	dot.text = "+"
	dot.add_theme_font_size_override("font_size", 28)
	dot.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	dot.add_theme_constant_override("outline_size", 6)
	dot.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dot.grow_vertical = Control.GROW_DIRECTION_BOTH
	_crosshair.add_child(dot)
	add_child(_crosshair)


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
