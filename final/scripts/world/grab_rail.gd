@tool
class_name GrabRail
extends Area3D
## A handrail or grab bar the participant can take hold of.
##
## Implemented as a self-contained Area3D so the project runs with no addons.
## If `godot-xr-tools` is installed you can instead make the rail an
## `XRToolsPickable` and let the bridge forward its signals -- see
## `scripts/util/xr_tools_bridge.gd`. Either way the rest of the game only
## cares about `is_held`, `grabbed` and `released`.
##
## The rail is a *static* hold: the hand snaps to the nearest point along the
## rail's local X axis and slides, rather than the rail moving to the hand.
## Ripping a handrail off the wall would be both physically wrong and, for a
## nervous first-time user, alarming.

signal grabbed(hand: Node3D)
signal released(hand: Node3D)

## Identifier written to the session log, e.g. "stair_rail_main".
@export var rail_id: String = ""

## Half-length of the graspable span along local X, in metres. The hand snaps
## to the closest point within +/- this distance of the rail origin.
@export var span: float = 1.0

## Rails glow softly when a hand is close enough to grab them. A senior user
## should never have to guess whether they are in range.
@export var show_proximity_glow: bool = true

## Rail tube radius, in metres. 0.02 m (40 mm diameter) is the domestic
## handrail size most people can close a hand right around.
@export var radius: float = 0.02

## Build the tube mesh automatically. Turn off if you supply your own model.
@export var auto_mesh: bool = true

@export var rail_color: Color = Color("#c8a26a")
## A named surface from Surfaces.SPECS, which overrides `rail_color`. A grab rail
## is one of the few things in the house a user will look at closely and put
## their hand on, so it is worth real brushed steel rather than a flat colour.
@export var rail_surface: String = "brushed_metal"
@export var bracket_surface: String = "steel_dark"

const COLOR_READY := Color(0.35, 0.75, 1.0)
const COLOR_HELD := Color(0.15, 0.95, 0.35)

var is_held: bool = false
var held_by: Node3D = null

var _meshes: Array[MeshInstance3D] = []
var _hands_in_range: Array[Node3D] = []


func _ready() -> void:
	if rail_id.is_empty():
		rail_id = name.to_snake_case()

	if auto_mesh:
		_build_tube()
	AutoShape.ensure_x_capsule(self, radius * 2.5, span * 2.0)
	if Engine.is_editor_hint():
		return

	# Layer 4 "grabbable": the grab controller's detector masks only this layer,
	# so grip never accidentally latches onto scenery.
	# Mask layer 7 "hand" so the rail also sees the hand arrive, which is what
	# drives the proximity glow and the auto-release when a hand moves away.
	collision_layer = 1 << 3
	collision_mask = 1 << 6
	monitoring = true
	monitorable = true
	# So the desktop rig can find something to reach for (see flat_debug_rig.gd).
	add_to_group("grabbable")

	_gather_meshes(self)
	_update_glow()

	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


## A horizontal tube along local X, plus two short brackets back to the wall.
## The capsule collision volume is deliberately 2.5x the visual radius: a
## generous grab volume around a realistically thin rail.
func _build_tube() -> void:
	var tube := MeshInstance3D.new()
	tube.name = "RailTube"
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = span * 2.0
	cyl.radial_segments = 12
	tube.mesh = cyl
	tube.rotation_degrees = Vector3(0.0, 0.0, 90.0)  # Y-aligned cylinder onto X
	tube.material_override = AutoShape.make_material(rail_color, 0.4, 0.3, rail_surface)
	add_child(tube)

	for side in [-1.0, 1.0]:
		var bracket := MeshInstance3D.new()
		bracket.name = "Bracket%s" % ("L" if side < 0.0 else "R")
		var box := BoxMesh.new()
		box.size = Vector3(0.03, 0.03, 0.07)
		bracket.mesh = box
		bracket.position = Vector3(side * (span - 0.06), 0.0, 0.045)
		bracket.material_override = AutoShape.make_material(
			Color("#8d8d92"), 0.5, 0.4, bracket_surface)
		add_child(bracket)


func _gather_meshes(node: Node) -> void:
	for child in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			_meshes.append(mesh)
		_gather_meshes(child)


func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("hand_grab_area"):
		var hand := area.get_parent() as Node3D
		if hand != null and not _hands_in_range.has(hand):
			_hands_in_range.append(hand)
			_update_glow()


func _on_area_exited(area: Area3D) -> void:
	if area.is_in_group("hand_grab_area"):
		var hand := area.get_parent() as Node3D
		_hands_in_range.erase(hand)
		if held_by == hand:
			release(hand)
		_update_glow()


# ---------------------------------------------------------------------------
#  Grab API -- called by scripts/player/grab_controller.gd
# ---------------------------------------------------------------------------

func can_grab(hand: Node3D) -> bool:
	return not is_held or held_by == hand


func grab(hand: Node3D) -> bool:
	if not can_grab(hand):
		return false
	is_held = true
	held_by = hand
	_update_glow()
	grabbed.emit(hand)
	return true


func release(hand: Node3D) -> void:
	if held_by != hand:
		return
	is_held = false
	held_by = null
	_update_glow()
	released.emit(hand)


## Nearest graspable world position to `world_point`, clamped to the rail span.
## The hand visual is snapped here so the hold looks anchored.
func closest_hold_point(world_point: Vector3) -> Vector3:
	var local := to_local(world_point)
	local.x = clampf(local.x, -span, span)
	local.y = 0.0
	local.z = 0.0
	return to_global(local)


func _update_glow() -> void:
	if not show_proximity_glow:
		return
	var color := Color(0, 0, 0, 0)
	var enabled := false
	if is_held:
		color = COLOR_HELD
		enabled = true
	elif not _hands_in_range.is_empty():
		color = COLOR_READY
		enabled = true

	for mesh in _meshes:
		if not enabled:
			mesh.material_overlay = null
			continue
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.r, color.g, color.b, 0.4)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.6
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_overlay = mat
