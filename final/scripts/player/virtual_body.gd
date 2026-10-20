class_name VirtualBody
extends Node3D
## A deliberately minimal self-avatar: a slim waist, two legs, and feet that
## step as you move. Nothing above the waist.
##
## WHY A BODY AT ALL
## -----------------
## Without one, a headset user is a floating pair of hands. Judging where the
## floor is, how far away the rug edge is, and whether you have room for the
## next step all get measurably harder, because the usual reference -- seeing
## your own feet -- is missing. For a training application about looking at the
## ground, that is the wrong thing to leave out. The body also casts a shadow,
## which is a second, stronger floor cue.
##
## HOW IT IS DRIVEN
## ----------------
## Nothing here is animated by hand or by an AnimationPlayer. Every frame:
##
##   * the body stands under the headset, on the floor found by a ray cast
##     straight down (so it is correct on stair treads too);
##   * it faces where the head faces, but LAGS behind it and only catches up
##     past a comfortable twist -- looking over your shoulder should not spin
##     your hips;
##   * the feet stay planted until one is more than `step_length` from where it
##     should be, then that one foot swings forward in `step_time` seconds.
##     Standing still means standing still: no idle shuffle;
##   * knees and elbows come from two-bone inverse kinematics, so the legs bend
##     rather than stretch.
##
## NOTHING ABOVE THE WAIST -- ON PURPOSE
## A chest sits about 30 cm below the eyes, so in a first-person view it fills
## the lower half of the screen and hides exactly what this app wants the
## participant looking at: the floor immediately in front of their feet. So
## there is no torso, no shoulders and no arms by default -- just a slim waist
## block the legs hang from. Looking down gives you feet, legs, and an
## uninterrupted view of the ground.
##
## (`show_arms` can be turned on, but with no torso the arms float, so it is
## only useful if you also add a chest back.)
##
## DELIBERATELY NOT DONE
##   * No head or neck: it would clip through the camera's near plane.
##   * No collision: this is a visual, and nothing in the game should ever be
##     pushed around by it.
##   * No "run" or "idle" animation and no head bob. Any motion the participant
##     did not initiate themselves is a simulator-sickness risk.
##
## Seated mode keeps the body STANDING, which is the whole point of
## Architectural Fix 5.2: the real person sits, the virtual body does not, so
## rails and counters stay where a standing person would reach for them.

## Turn the whole body off (e.g. to compare with and without for a study).
@export var enabled: bool = true: set = set_enabled

## Draw arms from the shoulders to the hands. OFF by default: see the note
## above about keeping the view of the floor clear.
@export var show_arms: bool = false

## Proportions, as fractions of the current eye height. Roughly adult average.
@export var hip_ratio: float = 0.53
@export var shoulder_ratio: float = 0.82

## Waist block size in metres. Keep it small: it sits directly below the eyes.
@export var waist_size: Vector3 = Vector3(0.26, 0.11, 0.17)

## Limb thicknesses (radius, metres).
@export var thigh_radius: float = 0.055
@export var shin_radius: float = 0.045

## Half the distance between the feet when standing, in metres.
@export var stance_width: float = 0.10

## How far a foot may be from where it should be before it takes a step.
@export var step_length: float = 0.40

## Seconds one step takes, and how high the foot lifts.
@export var step_time: float = 0.25
@export var step_height: float = 0.07

## Degrees the head may turn away from the hips before the hips follow.
@export var twist_tolerance: float = 45.0
## How quickly the hips catch up once past that, in degrees per second.
@export var turn_speed: float = 220.0

@export var trouser_color: Color = Color("#3d4657")
@export var top_color: Color = Color("#6d7a8c")
@export var shoe_color: Color = Color("#2a2a2e")
@export var skin_color: Color = Color("#c79a78")

var _player: XRPlayer
var _camera: XRCamera3D

var _waist: MeshInstance3D
## [left, right] for each pair.
var _thighs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _feet: Array[MeshInstance3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []

var _body_yaw: float = 0.0
var _foot_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_from: Vector3 = Vector3.ZERO
var _step_to: Vector3 = Vector3.ZERO
var _stepping: int = -1
var _step_t: float = 0.0
var _last_body_position: Vector3 = Vector3.ZERO
var _ready_to_walk: bool = false


func _ready() -> void:
	_player = get_parent() as XRPlayer
	if _player == null:
		push_error("VirtualBody must be a child of the XRPlayer (XROrigin3D).")
		set_process(false)
		return
	# Drawn in world space: the rig moves and turns under it, the body should
	# not be dragged around by the origin's own rotation.
	top_level = true
	_build()
	set_enabled(enabled)


func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	set_process(value)
	if not value:
		return
	_ready_to_walk = false  # re-plant the feet next frame


# ---------------------------------------------------------------------------
#  Per frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null:
		return
	if _camera == null:
		_camera = _player.camera
		if _camera == null:
			return

	var head := _camera.global_position
	# The floor the RIG is standing on, not whatever happens to be under the
	# head: leaning out over a stairwell, or walking into a flight of stairs,
	# must not shrink the body and bring its hips up to eye level.
	var floor_y := _player.global_position.y - _player.seated_offset()
	var eye_height := clampf(head.y - floor_y, 0.8, 2.2)
	var body_position := Vector3(head.x, floor_y, head.z)

	_update_yaw(delta)
	var basis := Basis(Vector3.UP, _body_yaw)
	var right := basis.x
	var forward := -basis.z

	# A teleport moves the whole person at once: plant both feet rather than
	# sprinting them across the room.
	if not _ready_to_walk or _last_body_position.distance_to(body_position) > 0.8:
		_plant_feet(body_position, right)
		_ready_to_walk = true
	_last_body_position = body_position

	_update_feet(delta, body_position, right, forward)
	_update_limbs(body_position, eye_height, basis)


## Hips follow the head loosely: free movement within `twist_tolerance`, then
## they turn to keep up. This is what stops the body spinning when you simply
## glance sideways.
func _update_yaw(delta: float) -> void:
	var head_yaw := _camera.global_rotation.y
	if not _ready_to_walk:
		_body_yaw = head_yaw
		return
	var difference := angle_difference(_body_yaw, head_yaw)
	var slack := deg_to_rad(twist_tolerance)
	if absf(difference) <= slack:
		return
	var target := head_yaw - signf(difference) * slack
	_body_yaw = rotate_toward(_body_yaw, target, deg_to_rad(turn_speed) * delta)


func _plant_feet(body_position: Vector3, right: Vector3) -> void:
	_stepping = -1
	_step_t = 0.0
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_foot_pos[i] = _on_floor(body_position + right * side * stance_width)


func _update_feet(delta: float, body_position: Vector3, right: Vector3, forward: Vector3) -> void:
	if _stepping >= 0:
		_step_t += delta / maxf(step_time, 0.01)
		var t := clampf(_step_t, 0.0, 1.0)
		var flat: Vector3 = _step_from.lerp(_step_to, t)
		flat.y += sin(PI * t) * step_height
		_foot_pos[_stepping] = flat
		if t >= 1.0:
			_foot_pos[_stepping] = _step_to
			_stepping = -1
		return

	# Whichever foot is furthest from where it should be goes next, and only if
	# it is far enough to be worth a step.
	var worst := -1
	var worst_distance := step_length
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var want := _on_floor(body_position + right * side * stance_width)
		var distance := Vector2(want.x - _foot_pos[i].x, want.z - _foot_pos[i].z).length()
		if distance > worst_distance:
			worst_distance = distance
			worst = i
	if worst < 0:
		return

	var side_sign := -1.0 if worst == 0 else 1.0
	# Step slightly PAST the target, the way a real stride does, so the feet
	# alternate instead of shuffling into the same spot.
	var target := body_position + right * side_sign * stance_width + forward * step_length * 0.35
	_step_from = _foot_pos[worst]
	_step_to = _on_floor(target)
	_stepping = worst
	_step_t = 0.0


func _update_limbs(body_position: Vector3, eye_height: float, basis: Basis) -> void:
	var right := basis.x
	var forward := -basis.z

	var hip_height := eye_height * hip_ratio
	var shoulder_height := eye_height * shoulder_ratio
	var hip_centre := body_position + Vector3.UP * hip_height
	var shoulder_centre := body_position + Vector3.UP * shoulder_height

	_waist.global_position = hip_centre
	_waist.global_basis = basis

	var leg := maxf(hip_height, 0.3)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hip := hip_centre + right * side * stance_width
		var foot := _foot_pos[i] + Vector3.UP * 0.06  # ankle, not sole
		# Knees bend forwards.
		var knee := _two_bone(hip, foot, leg * 0.5, leg * 0.5, forward)
		_place_segment(_thighs[i], hip, knee)
		_place_segment(_shins[i], knee, foot)
		_feet[i].global_position = _foot_pos[i] + Vector3.UP * 0.03 + forward * 0.04
		_feet[i].global_basis = basis

	if not show_arms or _upper_arms.is_empty():
		return
	var hands := [_player.move_hand, _player.point_hand]
	var arm := (shoulder_height - hip_height) + eye_height * 0.28
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := shoulder_centre + right * side * (stance_width + 0.07)
		var hand_node := hands[i] as Node3D
		var hand := shoulder + forward * 0.25 - Vector3.UP * 0.35
		if hand_node != null and hand_node.is_inside_tree():
			hand = hand_node.global_position
		# Elbows hang down and slightly out, never through the chest.
		var bend := (-Vector3.UP + right * side * 0.4).normalized()
		var elbow := _two_bone(shoulder, hand, arm * 0.5, arm * 0.5, bend)
		_place_segment(_upper_arms[i], shoulder, elbow)
		_place_segment(_forearms[i], elbow, hand)


# ---------------------------------------------------------------------------
#  Geometry helpers
# ---------------------------------------------------------------------------

## Floor height under `point`, from a ray cast down through world geometry
## (layer 1). Falls back to the rig's own floor when nothing is hit. Used for
## the FEET, which do stand on whatever is under them -- one on a tread and one
## on the one below is exactly right on a staircase.
func _floor_under(point: Vector3) -> float:
	var from := point + Vector3.UP * 0.2
	var to := point - Vector3.UP * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 << 0
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _player.global_position.y - _player.seated_offset()
	return float(hit["position"].y)


func _on_floor(point: Vector3) -> Vector3:
	return Vector3(point.x, _floor_under(point), point.z)


## Two-bone IK: where the joint between `a` and `b` sits, bending towards
## `bend`. Keeps the limb bent instead of stretched when the foot or hand is
## closer than the full leg or arm length.
func _two_bone(a: Vector3, b: Vector3, l1: float, l2: float, bend: Vector3) -> Vector3:
	var offset := b - a
	var distance := offset.length()
	if distance < 0.001:
		return a + bend.normalized() * l1
	var direction := offset / distance
	var reach := clampf(distance, 0.001, (l1 + l2) * 0.999)
	var along := (reach * reach + l1 * l1 - l2 * l2) / (2.0 * reach)
	var out := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var side := bend - direction * bend.dot(direction)
	if side.length_squared() < 0.0001:
		side = Vector3.UP - direction * Vector3.UP.dot(direction)
	return a + direction * along + side.normalized() * out


## Stretch a unit-height cylinder between two points.
func _place_segment(segment: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var offset := to - from
	var length := offset.length()
	if length < 0.001:
		segment.visible = false
		return
	segment.visible = true
	var up := offset / length
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_axis := reference.cross(up).normalized()
	var z_axis := x_axis.cross(up)
	segment.global_position = (from + to) * 0.5
	segment.global_basis = Basis(x_axis, up * length, z_axis)


# ---------------------------------------------------------------------------
#  Build (once)
# ---------------------------------------------------------------------------

func _build() -> void:
	_waist = _box(waist_size, trouser_color)
	for i in 2:
		_thighs.append(_limb(thigh_radius, trouser_color))
		_shins.append(_limb(shin_radius, trouser_color))
		_feet.append(_box(Vector3(0.10, 0.05, 0.22), shoe_color))
		if show_arms:
			_upper_arms.append(_limb(0.05, top_color))
			_forearms.append(_limb(0.045, skin_color))


## A unit-height cylinder, scaled between two points every frame.
func _limb(radius: float, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = AutoShape.make_material(color, 0.8)
	mesh_instance.top_level = true
	# The body's shadow on the floor is a strong depth cue in its own right.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)
	return mesh_instance


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := AutoShape.make_box_mesh(size, color, 0.8)
	mesh_instance.top_level = true
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)
	return mesh_instance
