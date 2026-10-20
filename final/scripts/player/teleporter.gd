class_name Teleporter
extends Node3D
## Core System D -- locomotion. Teleport only, by default and by policy.
##
## Smooth locomotion is the leading cause of simulator sickness, so this app
## does not implement it at all -- there is no setting and no code path for it.
## (A `smooth_locomotion` flag used to exist in Settings with nothing behind it;
## it was removed rather than left to imply an option that was never there.)
##
## Two modes, chosen automatically:
##
##   FREE      -- outside any GatedRegion. Aim an arc at any walkable floor.
##   POINTS    -- inside a GatedRegion (the staircase). The arc snaps only to
##                *active* GatedTeleportPoints, and a point is only active while
##                the participant is holding the handrail. This is
##                Architectural Fix 5.1 and it is what makes the handrail habit
##                enforced rather than merely measured.
##
## Interaction: hold the move-hand trigger to show the arc, release to travel.
## Hold-to-aim, release-to-commit is far more forgiving than press-to-jump for
## someone with a tremor -- a wobble does not cost you a jump to the wrong spot.

## Boolean OpenXR action that shows/commits the teleport arc.
@export var teleport_action: String = "trigger_click"

## Maximum free-teleport distance, in metres.
@export var max_range: float = 5.0

## Steepest floor angle you may land on, in degrees.
@export var max_floor_angle: float = 30.0

## Snap radius for locking onto a GatedTeleportPoint, in metres.
@export var point_snap_radius: float = 1.2

## In free mode, a floor hit this close to an active GatedTeleportPoint lands
## ON the point, so walking up to the foot of the stairs "uses" the entry point
## and the one-step-at-a-time chain can start from it.
@export var free_mode_point_snap: float = 0.5

const COLOR_VALID := Color(0.15, 0.95, 0.35)
const COLOR_INVALID := Color(0.9, 0.2, 0.15)
const ARC_STEPS := 24

var _player: XRPlayer
var _controller: XRController3D
var _aiming: bool = false
var _valid: bool = false
var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = NAN
var _locked_point: GatedTeleportPoint = null

var _arc: MeshInstance3D
var _marker: MeshInstance3D
var _arc_material: StandardMaterial3D
var _enabled: bool = true


## Both hands carry a Teleporter and a HazardPointer; XRPlayer enables exactly
## one of each according to the hand roles, so swapping to left-handed is a
## single setting and never leaves a hand doing two jobs.
func set_teleport_enabled(value: bool) -> void:
	_enabled = value
	if not value and _aiming:
		_aiming = false
		_set_visible(false)


func _ready() -> void:
	_player = _find_player()
	_controller = _find_controller()
	_build_visuals()
	_set_visible(false)

	if _controller != null:
		_controller.button_pressed.connect(_on_button_pressed)
		_controller.button_released.connect(_on_button_released)
	else:
		push_warning("Teleporter: no XRController3D ancestor; desktop rig will drive it.")


func _find_player() -> XRPlayer:
	var node: Node = get_parent()
	while node != null:
		var player := node as XRPlayer
		if player != null:
			return player
		node = node.get_parent()
	return null


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
	if action_name == teleport_action:
		begin_aim()


func _on_button_released(action_name: String) -> void:
	if action_name == teleport_action:
		commit()


func begin_aim() -> void:
	if not _enabled:
		return
	_aiming = true
	_set_visible(true)


## Travel to the aimed destination if it is legal; otherwise refuse audibly.
func commit() -> void:
	if not _aiming:
		return
	_aiming = false
	_set_visible(false)

	if not _valid:
		AudioCues.play("reject")
		if GatedRegion.is_player_gated():
			# Explain *why* it refused. Silent refusal reads as a broken device.
			AudioCues.speak_text("Hold the rail, then point at the next green step.")
		return

	if _locked_point != null:
		var xform := _locked_point.consume()
		_player.teleport_to(xform.origin, _locked_point.arrival_yaw_degrees)
	else:
		GatedTeleportPoint.current = null
		_player.teleport_to(_target_position, _target_yaw)

	AudioCues.play("page")
	# A short "blink": close the comfort vignette briefly so the jump is not a
	# jarring full-field cut (Core System D).
	var vignette := get_tree().get_first_node_in_group("comfort_vignette")
	if vignette != null and vignette.has_method("blink"):
		vignette.call("blink", 0.25)


# ---------------------------------------------------------------------------
#  Aiming
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not _aiming or _player == null:
		return

	var points := _trace_arc()
	_update_arc_mesh(points)
	_marker.visible = _valid
	if _valid:
		_marker.global_position = _target_position + Vector3(0.0, 0.02, 0.0)
	_apply_color(COLOR_VALID if _valid else COLOR_INVALID)


## Ballistic arc from the controller. Returns the polyline; sets `_valid`,
## `_target_position`, `_locked_point` as side effects.
func _trace_arc() -> PackedVector3Array:
	var points := PackedVector3Array()
	var space := get_world_3d().direct_space_state

	var origin := global_position
	var direction := -global_transform.basis.z
	var velocity := direction * 6.0
	var gravity := Vector3(0.0, -9.8, 0.0)
	var step := 0.06

	_valid = false
	_locked_point = null
	_target_yaw = NAN

	var gated := GatedRegion.is_player_gated()
	var current := origin
	points.append(current)

	for i in ARC_STEPS:
		var next := current + velocity * step + gravity * step * step * 0.5
		velocity += gravity * step

		var query := PhysicsRayQueryParameters3D.create(current, next)
		# World geometry (layer 1) stops the arc so it looks right, and teleport
		# points (layer 5) can be hit directly. Whether a *floor* hit counts as a
		# destination is decided in _resolve_hit(): inside a gated region it does
		# not, so bare stair treads cannot be warped to.
		query.collision_mask = (1 << 0) | (1 << 4)
		query.collide_with_areas = true
		query.collide_with_bodies = true

		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			points.append(hit["position"])
			_resolve_hit(hit, gated)
			return points

		points.append(next)
		current = next
		if origin.distance_to(current) > max_range * 1.6:
			break

	return points


func _resolve_hit(hit: Dictionary, gated: bool) -> void:
	var collider: Object = hit.get("collider")
	var position: Vector3 = hit["position"]

	# Direct hit on a teleport point.
	var point := _as_teleport_point(collider)
	if point != null:
		if point.is_active():
			_valid = true
			_locked_point = point
			_target_position = point.global_position
			_target_yaw = point.arrival_yaw_degrees
		return

	# Gating applies to the destination as well as to the origin, otherwise the
	# participant could stand in the hallway and land halfway up the stairs.
	if gated or GatedRegion.is_point_gated(position):
		var nearest := _nearest_active_point(position)
		if nearest != null:
			_valid = true
			_locked_point = nearest
			_target_position = nearest.global_position
			_target_yaw = nearest.arrival_yaw_degrees
		return

	# Free mode: only real floor (group "walkable", set by RoomBuilder and
	# Staircase), flat enough to stand on. Furniture tops, bath rims and the top
	# of the wardrobe are not destinations.
	var body := collider as Node
	if body == null or not body.is_in_group("walkable"):
		return
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if rad_to_deg(normal.angle_to(Vector3.UP)) > max_floor_angle:
		return
	var head := _player.head_position()
	head.y = position.y
	if head.distance_to(position) > max_range:
		return

	# Landing right next to an active entry point: land on the point itself.
	var near_point := _nearest_active_point(position, free_mode_point_snap)
	if near_point != null:
		_valid = true
		_locked_point = near_point
		_target_position = near_point.global_position
		_target_yaw = near_point.arrival_yaw_degrees
		return

	_valid = true
	_target_position = position


func _as_teleport_point(collider: Object) -> GatedTeleportPoint:
	var point := collider as GatedTeleportPoint
	if point != null:
		return point
	var node := collider as Node
	if node != null:
		return node.get_parent() as GatedTeleportPoint
	return null


func _nearest_active_point(near: Vector3, radius: float = -1.0) -> GatedTeleportPoint:
	var best: GatedTeleportPoint = null
	var best_distance := point_snap_radius if radius < 0.0 else radius
	for node in get_tree().get_nodes_in_group("gated_teleport_point"):
		var point := node as GatedTeleportPoint
		if point == null or not point.is_active():
			continue
		var distance := point.global_position.distance_to(near)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


# ---------------------------------------------------------------------------
#  Visuals
# ---------------------------------------------------------------------------

func _build_visuals() -> void:
	_arc_material = StandardMaterial3D.new()
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.emission_enabled = true
	_arc_material.emission_energy_multiplier = 2.0
	_arc_material.vertex_color_use_as_albedo = false
	_arc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_arc = MeshInstance3D.new()
	_arc.name = "Arc"
	_arc.top_level = true  # drawn in world space, not relative to the hand
	_arc.material_override = _arc_material
	add_child(_arc)

	_marker = MeshInstance3D.new()
	_marker.name = "Marker"
	_marker.top_level = true
	var torus := TorusMesh.new()
	torus.inner_radius = 0.26
	torus.outer_radius = 0.34
	_marker.mesh = torus
	_marker.material_override = _arc_material
	add_child(_marker)


func _update_arc_mesh(points: PackedVector3Array) -> void:
	var mesh := ImmediateMesh.new()
	if points.size() >= 2:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in points:
			mesh.surface_add_vertex(p)
		mesh.surface_end()
	_arc.mesh = mesh
	_arc.global_transform = Transform3D.IDENTITY


func _apply_color(color: Color) -> void:
	_arc_material.albedo_color = color
	_arc_material.emission = color


func _set_visible(value: bool) -> void:
	_arc.visible = value
	_marker.visible = value and _valid
