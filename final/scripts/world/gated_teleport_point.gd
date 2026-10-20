@tool
class_name GatedTeleportPoint
extends Area3D
## Architectural Fix 5.1 -- the teleport loophole, closed.
##
## THE PROBLEM
## -----------
## Free-aim teleport lets the participant stand at the top of the stairs, point
## the beam at the hallway floor below, and arrive there instantly. They never
## traverse the steps, so the handrail zone never fires, and the single most
## important safe-movement habit in the whole application is never practised.
## Worse, the session log records a clean run -- the failure is invisible.
##
## THE FIX
## -------
## Three cooperating pieces:
##
##   1. `GatedRegion` (scripts/world/gated_region.gd) wraps the flight and the
##      landing. While the player is inside it, the teleporter refuses free-aim
##      destinations, and no destination inside it is legal from outside it.
##   2. This node is the ONLY legal destination inside such a region. One sits
##      on each group of treads, plus one entry point at the foot of the stairs
##      (just OUTSIDE the region, so the participant can always walk away).
##   3. A point is only *active* while `required_rail` is actually held, and
##      only if it is the next or previous point in the chain from the one the
##      participant is standing on. So the flight is taken one landing at a
##      time, up AND down, with a hand on the rail. There is no aim that skips
##      it in either direction.
##
## The entry point at the foot uses `rail_required_only_when_gated`: walking up
## to the stairs from the hallway needs no rail, but stepping down onto it from
## the flight does.
##
## godot-xr-tools note: if you have the addon installed, this is the analogue of
## `XRToolsTeleportPoint`, with the gating added.

signal activated
signal deactivated
signal used

## Rail that must be held for this destination to unlock.
@export var required_rail_path: NodePath

## Only require the rail while the player is inside a GatedRegion. Use on the
## entry point at the foot of the stairs: arriving from the hallway is free,
## stepping down onto it from the flight is not.
@export var rail_required_only_when_gated: bool = false

## Previous point in the chain (one step further down). Only the points next to
## the one the participant is standing on are selectable. Leave empty on the
## entry point at the foot of the stairs.
@export var requires_previous_path: NodePath

## Where the participant faces on arrival, in degrees around Y. Godot yaw 0
## looks along -Z. Facing the way they are travelling removes the "where am I?"
## moment that causes a startle.
@export var arrival_yaw_degrees: float = 0.0

@export var room: String = "staircase"

## How close (horizontally, metres) the participant's head must be to a point
## for them to count as standing on it. Covers room-scale drift after arrival.
const STANDING_RADIUS := 0.9

## A locked point only explains itself when the participant is this close.
## Without it, a flight of stairs shows four stacked captions at once and the
## nearest one is unreadable behind the rest.
const LABEL_DISTANCE := 2.2

const COLOR_ACTIVE := Color(0.15, 0.95, 0.35)
const COLOR_LOCKED := Color(0.45, 0.45, 0.48)

## The point the participant most recently arrived at (null = not on the stairs).
static var current: GatedTeleportPoint = null

var used_already: bool = false

var _rail: GrabRail
var _previous: GatedTeleportPoint
var _active: bool = false
var _disc: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	AutoShape.ensure_cylinder(self, 0.35, 0.1)
	if Engine.is_editor_hint():
		# Show the landing disc while authoring the stairwell, but do not poll
		# rail state in the editor -- the rails are not simulating there.
		_build_visuals()
		_apply_visual_state()
		set_process(false)
		return

	# Layer 5 "teleport_target": inside a gated region only this layer yields a
	# legal destination, so the teleporter can never resolve to bare floor.
	collision_layer = 1 << 4
	collision_mask = 0
	monitoring = false
	monitorable = true

	add_to_group("gated_teleport_point")

	_rail = get_node_or_null(required_rail_path) as GrabRail
	_previous = get_node_or_null(requires_previous_path) as GatedTeleportPoint

	_build_visuals()
	_active = is_active()
	_apply_visual_state()

	if _rail != null:
		_rail.grabbed.connect(_on_state_changed.unbind(1))
		_rail.released.connect(_on_state_changed.unbind(1))


func _exit_tree() -> void:
	if current == self:
		current = null


func _on_state_changed() -> void:
	_refresh()


## The point the participant is standing on right now, or null.
##
## Worked out from WHERE THEY ARE, not from which point they last teleported
## to: someone who walks up a step in room-scale, or with the desktop keys,
## is just as much standing on it. (Tracking only teleports meant that walking
## up one step locked every disc on the flight, because nothing was adjacent
## to a chain position the participant had left.)
static func standing_point(tree: SceneTree) -> GatedTeleportPoint:
	var player := tree.get_first_node_in_group("xr_player") as XRPlayer
	if player == null:
		return current if is_instance_valid(current) else null
	var head := player.head_position()
	var best: GatedTeleportPoint = null
	var best_distance := STANDING_RADIUS
	for node in tree.get_nodes_in_group("gated_teleport_point"):
		var point := node as GatedTeleportPoint
		if point == null:
			continue
		var offset := head - point.global_position
		# Ignore points on a different level: on a stair the discs are close
		# together horizontally but well apart vertically.
		if absf(offset.y) > 2.2:
			continue
		offset.y = 0.0
		var distance := offset.length()
		if distance < best_distance:
			best_distance = distance
			best = point
	current = best
	return best


## True when this destination may currently be selected.
func is_active() -> bool:
	if not _is_next_to_standing_point():
		return false
	if _rail != null and not _rail.is_held:
		if not rail_required_only_when_gated or GatedRegion.is_player_gated():
			return false
	return true


## One step at a time: selectable only from the point directly below or above.
## The entry point (no previous) is also selectable from anywhere off the
## stairs.
func _is_next_to_standing_point() -> bool:
	var here := standing_point(get_tree())
	if here == self:
		return false
	if _previous == null:
		return here == null or here._previous == self
	if here == null:
		return false
	return here == _previous or here._previous == self


func _refresh() -> void:
	var now := is_active()
	if now == _active:
		return
	_active = now
	_apply_visual_state()
	if _active:
		activated.emit()
	else:
		deactivated.emit()


func _process(_delta: float) -> void:
	# The rail emits signals, but the chain depends on where the participant is
	# standing, so poll once per frame as well.
	_refresh()
	_update_label()


## Global transform the player origin should be moved to. Called by the
## teleporter; also marks this as the point the participant is standing on.
func consume() -> Transform3D:
	used_already = true
	current = self
	used.emit()
	SessionManager.log_event("teleport_point_used", {"point": name, "room": room})
	_apply_visual_state()
	var basis := Basis(Vector3.UP, deg_to_rad(arrival_yaw_degrees))
	return Transform3D(basis, global_position)


# ---------------------------------------------------------------------------
#  Visuals -- a floor disc plus a plain-language reason when locked
# ---------------------------------------------------------------------------

## True when the participant's head is close enough to be talked to.
func _near_player() -> bool:
	var player := get_tree().get_first_node_in_group("xr_player") as XRPlayer
	if player == null:
		return true
	return player.head_position().distance_to(global_position) <= LABEL_DISTANCE


func _build_visuals() -> void:
	_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 0.02
	cyl.radial_segments = 24
	_disc.mesh = cyl
	_disc.position = Vector3(0.0, 0.011, 0.0)
	add_child(_disc)

	_label = Label3D.new()
	_label.pixel_size = 0.0012
	_label.font_size = 72
	_label.outline_size = 22
	_label.outline_modulate = Color(0.05, 0.05, 0.05)
	# Full billboard, single sided: these labels lie on the floor and are often
	# read from directly above, where a Y-axis billboard can present its BACK --
	# which draws the text mirrored.
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.double_sided = false
	_label.no_depth_test = true
	_label.position = Vector3(0.0, 0.42, 0.0)
	add_child(_label)


func _apply_visual_state() -> void:
	var color := COLOR_ACTIVE if _active else COLOR_LOCKED
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.75 if _active else 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8 if _active else 0.3
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc.material_override = mat
	_update_label()


func _update_label() -> void:
	_label.modulate = COLOR_ACTIVE if _active else COLOR_LOCKED
	if _active:
		# Where you may go next is always worth saying.
		_label.text = "Step here"
		return
	if Engine.is_editor_hint():
		_label.text = "Hold the rail\nto unlock"
		return
	if current == self or not _near_player():
		_label.text = ""
	elif not _is_next_to_standing_point():
		_label.text = "One step at a time"
	else:
		_label.text = "Hold the rail\nto unlock"
