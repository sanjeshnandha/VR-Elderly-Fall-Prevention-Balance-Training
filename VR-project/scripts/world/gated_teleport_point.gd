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
##   1. `GatedRegion` (scripts/world/gated_region.gd) wraps the staircase. While
##      the player is inside it, the teleporter refuses free-aim destinations.
##   2. This node is the ONLY legal destination inside such a region. One sits
##      on each stair landing / tread group.
##   3. A point is only *active* while `required_rail` is actually held. Let go
##      of the rail and the next landing greys out and cannot be selected.
##
## The result is that the habit is enforced by the locomotion system rather than
## merely logged after the fact: you physically cannot ascend without holding on.
##
## `requires_previous` additionally chains the points so the participant must
## take the flight one landing at a time instead of jumping to the top.
##
## godot-xr-tools note: if you have the addon installed, this is the analogue of
## `XRToolsTeleportPoint`, with the gating added. The bridge in
## scripts/util/xr_tools_bridge.gd lets an `XRToolsFunctionTeleport` restrict
## itself to these nodes.

signal activated
signal deactivated
signal used

## Rail that must be held for this destination to unlock. Leave empty for an
## ungated landing (typically the first one, at the bottom of the stairs).
@export var required_rail_path: NodePath

## Optional predecessor. This point stays locked until that one has been used,
## which forces the flight to be taken in order.
@export var requires_previous_path: NodePath

## Where the participant faces on arrival, in degrees around Y. Facing them up
## the stairs on arrival removes the "where am I?" moment that causes a startle.
@export var arrival_yaw_degrees: float = 0.0

@export var room: String = "staircase"

const COLOR_ACTIVE := Color(0.15, 0.95, 0.35)
const COLOR_LOCKED := Color(0.45, 0.45, 0.48)

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
		_rail.grabbed.connect(_on_rail_state_changed.unbind(1))
		_rail.released.connect(_on_rail_state_changed.unbind(1))
	if _previous != null:
		_previous.used.connect(_on_rail_state_changed)

	_refresh()


func _on_rail_state_changed() -> void:
	_refresh()


## True when this destination may currently be selected.
func is_active() -> bool:
	if _previous != null and not _previous.used_already:
		return false
	if _rail != null and not _rail.is_held:
		return false
	return true


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
	# The rail emits signals, but polling once per frame also covers the
	# `requires_previous` chain and any rail released by an addon path that does
	# not emit through GrabRail.
	_refresh()


## Global transform the player origin should be moved to. Called by the
## teleporter; also marks the point as used so the next one in the chain opens.
func consume() -> Transform3D:
	used_already = true
	used.emit()
	SessionManager.log_event("teleport_point_used", {"point": name, "room": room})
	_apply_visual_state()
	var basis := Basis(Vector3.UP, deg_to_rad(arrival_yaw_degrees))
	return Transform3D(basis, global_position)


# ---------------------------------------------------------------------------
#  Visuals -- a floor disc plus a plain-language reason when locked
# ---------------------------------------------------------------------------

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
	_label.pixel_size = 0.0016
	_label.font_size = 84
	_label.outline_size = 22
	_label.outline_modulate = Color(0.05, 0.05, 0.05)
	# Y-axis billboard: the label spins to face you horizontally but stays
	# upright, so it does not tilt when you look up or down a flight of stairs.
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.no_depth_test = true
	_label.position = Vector3(0.0, 0.5, 0.0)
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

	_label.modulate = color
	if _active:
		_label.text = "Step here"
	elif _previous != null and not _previous.used_already:
		_label.text = "Use the step below first"
	else:
		_label.text = "Hold the rail\nto unlock"
