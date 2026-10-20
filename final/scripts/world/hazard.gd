@tool
class_name Hazard
extends Area3D
## Core System A -- a single flaggable object.
##
## Attach to an Area3D that surrounds the thing the participant should notice.
## Set `is_hazard = false` on decoy objects (a towel rail, a bedside lamp) so
## the exercise is genuine discrimination and not "point at everything".
##
## The node registers itself with SessionManager on _ready(), so the "found X of
## Y" denominator is always derived from the scene. Add a hazard to a room and
## the score adapts with no other edit.

## Stable identifier used in the JSON log and to look up coaching advice.
## Keep it snake_case and unique, e.g. "bathroom_wet_floor".
@export var hazard_id: String = ""

## Human-readable name shown on the debrief panel and spoken aloud.
@export var hazard_name: String = "Unnamed hazard"

## Which room this belongs to. Used to group the debrief.
@export var room: String = "unknown"

## False for decoys: pointing at it is logged as a false positive, not a find.
@export var is_hazard: bool = true

## One-line explanation shown when the participant flags it correctly.
@export_multiline var explanation: String = ""

## Meshes to tint on hover / flag. If empty, every MeshInstance3D descendant is
## used automatically.
@export var highlight_meshes: Array[NodePath] = []

## Vertical offset of the floating confirmation label, in metres.
@export var label_height: float = 0.45

## Shift the floating name away from the centre of the aim volume. The volume
## has to be generous -- it is what the participant points at -- but on a long
## object (a rug, a trailing lead) the name belongs over the part that is
## actually dangerous, not over the middle.
@export var label_offset: Vector3 = Vector3.ZERO

## Full size of the auto-generated trigger box, in metres. Ignored if the scene
## already provides a CollisionShape3D.
@export var extents: Vector3 = Vector3(0.6, 0.6, 0.6)

## How much of a mesh has to be inside the aim volume before it is treated as
## part of the hazard and lit up with it.
const INSIDE_FRACTION := 0.45

# High-contrast palette. Yellow-on-dark is the most legible combination for
# users with reduced contrast sensitivity, and stays readable through the
# chromatic aberration of cheap VR lenses.
const COLOR_HOVER := Color(1.0, 0.85, 0.1)
const COLOR_FLAGGED := Color(0.15, 0.95, 0.35)

var is_flagged: bool = false
var _hovered: bool = false
var _meshes: Array[MeshInstance3D] = []
var _originals: Array[Material] = []
var _label: Label3D


func _ready() -> void:
	# Generate the trigger volume in the editor too, so the scene shows no
	# "node has no shape" warning and the volume is visible while you place it.
	AutoShape.ensure_box(self, extents)
	if Engine.is_editor_hint():
		return

	if hazard_id.is_empty():
		hazard_id = "%s_%s" % [room, name.to_snake_case()]
		push_warning("Hazard '%s' had no hazard_id; generated '%s'." % [name, hazard_id])

	_collect_meshes()

	# Hazards live on their own physics layer so the pointer ray can be told to
	# hit ONLY hazards and UI -- it never snags on walls or furniture.
	collision_layer = 1 << 2   # layer 3 "hazard"
	collision_mask = 0         # hazards detect nothing themselves
	monitoring = false
	monitorable = true
	input_ray_pickable = true

	if is_hazard:
		SessionManager.register_hazard(hazard_id, hazard_name, room)


func _collect_meshes() -> void:
	_meshes.clear()
	_originals.clear()
	if not highlight_meshes.is_empty():
		for path in highlight_meshes:
			var n := get_node_or_null(path) as MeshInstance3D
			if n != null:
				_meshes.append(n)
	else:
		_gather_meshes_recursive(self)
		if _meshes.is_empty():
			_gather_meshes_in_volume()
	for m in _meshes:
		_originals.append(m.material_overlay)


## Every MeshInstance3D under the hazard itself.
##
## The rare case, kept because it is the one that needs no guessing: when a
## scene DOES parent the prop to its hazard, those meshes are the hazard's own
## geometry and all of them are meant. Nothing here is filtered by the aim
## volume -- being a child already said so. The label spawned at run time is a
## Label3D, not a MeshInstance3D, so it is never picked up.
func _gather_meshes_recursive(node: Node) -> void:
	for child in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			_meshes.append(mesh)
		_gather_meshes_recursive(child)


## The thing a hazard is ABOUT is almost never a child of it.
##
## Every hazard in this house is an Area3D sitting over a prop that is its
## SIBLING -- the lifted slab, the trailing lead, the wet patch, the bin. So the
## recursive search above found nothing, every `_meshes` array was empty, and
## the green glow on a correct find and the amber glow on hover had never once
## appeared anywhere in the project. Flagging still worked -- the tone, the
## spoken name and the floating label all fired -- which is exactly why it went
## unnoticed for so long: the one piece of feedback that says "that object, the
## one you are looking at" was the missing one.
##
## Rather than naming the prop by hand on thirty hazards, take the meshes whose
## bounds OVERLAP the aim volume. That is the same question the volume already
## answers, so the two cannot drift apart, and it survives a long thin object
## like a kerb whose centre is twenty metres away from the bit being pointed at.
##
## Two guards keep it from highlighting the world: anything much larger than the
## volume is the floor, the pavement or the road, and the room shell is skipped
## outright.
func _gather_meshes_in_volume() -> void:
	var room_node := get_parent()
	if room_node == null:
		return
	var half := extents * 0.5
	var inverse := global_transform.affine_inverse()
	var footprint := maxf(extents.x * extents.z, 0.01)
	for sibling in room_node.get_children():
		# The room shell is skipped outright -- a wall or a floor slab that a
		# small volume happens to sit inside is never what was pointed at. A
		# staircase is not skipped: its generated treads are exactly what the
		# uneven-step hazard is about.
		if sibling == self or sibling is RoomBuilder:
			continue
		_gather_if_inside(sibling, inverse, half, footprint)


func _gather_if_inside(node: Node, inverse: Transform3D, half: Vector3,
		footprint: float) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null and _mostly_inside(mesh, inverse, half):
		_meshes.append(mesh)
	for child in node.get_children():
		_gather_if_inside(child, inverse, half, footprint)


## Is most of this mesh inside the aim volume?
##
## Overlapping is not enough. A living-room rug overlaps the coffee table's
## volume, the sofa's and the television lead's, so "overlaps" lit the same rug
## for three different hazards. Requiring most of the OBJECT to be inside says
## what is actually meant: this is the thing the volume is drawn around, not
## the thing it happens to be standing on.
##
## Every axis is given a 20 mm floor first, or a rug 14 mm thick has no volume
## to take a fraction of.
func _mostly_inside(mesh: MeshInstance3D, inverse: Transform3D, half: Vector3) -> bool:
	var aabb := mesh.get_aabb()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in 8:
		var corner := inverse * (mesh.global_transform * aabb.get_endpoint(i))
		lo = lo.min(corner)
		hi = hi.max(corner)
	var whole := 1.0
	var shared := 1.0
	for axis in 3:
		var size := maxf(hi[axis] - lo[axis], 0.02)
		var overlap := minf(hi[axis], half[axis]) - maxf(lo[axis], -half[axis])
		if overlap <= 0.0:
			return false
		whole *= size
		shared *= maxf(overlap, 0.02)
	return shared / whole >= INSIDE_FRACTION


# ---------------------------------------------------------------------------
#  Pointer interaction
# ---------------------------------------------------------------------------

## Called every frame by the hazard pointer while the ray rests on this object.
func set_hovered(value: bool) -> void:
	if _hovered == value or is_flagged:
		return
	_hovered = value
	_apply_overlay(COLOR_HOVER if value else Color(0, 0, 0, 0), value)


## The participant pressed the trigger while pointing at this object.
## Returns true if it counted as a new, correct find.
func flag_hazard() -> bool:
	if not SessionManager.session_active:
		# Pointing around before pressing START, or after the debrief, must not
		# consume the hazard -- otherwise it would still read as flagged once
		# the session actually begins and could never be scored.
		AudioCues.play("reject")
		return false

	if is_flagged:
		AudioCues.play("reject")
		return false

	if not is_hazard:
		# A decoy. Logged for the researcher, acknowledged with a NEUTRAL tone --
		# the low "reject" buzz would read as "wrong", and over-caution is a
		# habit we want to keep, not punish.
		SessionManager.record_false_positive(hazard_name, room)
		AudioCues.play("neutral")
		return false

	is_flagged = true
	_hovered = false
	_apply_overlay(COLOR_FLAGGED, true)
	_spawn_label()

	var counted := SessionManager.record_hazard_flag(hazard_id, hazard_name)
	if counted:
		AudioCues.play("confirm")
		# Head-locked speech, never 3D positional -- Architectural Fix 5.3.
		var line := hazard_name
		if not explanation.is_empty():
			line += ". " + explanation
		AudioCues.speak_text(line)
	return counted


func _apply_overlay(color: Color, enabled: bool) -> void:
	# Look again if there is nothing to light up.
	#
	# Two hazards sit over geometry that does not exist until its own node has
	# run: the puddle builds its water surface in _ready(), and the staircase
	# builds its treads there. Sibling _ready() order is not something a scene
	# should have to guarantee, and a named NodePath into a run-time child
	# resolves to null just as easily as an overlap test finds nothing. By the
	# time a glow is actually wanted the room is fully built, so collecting then
	# always succeeds -- and it costs one walk of the room, once, on the first
	# hover of the only hazards that need it.
	if enabled and _meshes.is_empty():
		_collect_meshes()
	for i in _meshes.size():
		var mesh := _meshes[i]
		if not is_instance_valid(mesh):
			continue
		if not enabled:
			mesh.material_overlay = _originals[i]
			continue
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.4
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mesh.material_overlay = mat


func _spawn_label() -> void:
	if _label != null:
		return
	_label = Label3D.new()
	_label.text = hazard_name
	_label.font_size = 96          # rendered small in world space; see pixel_size
	_label.pixel_size = 0.0015
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.double_sided = false    # never show the back of the text, mirrored
	_label.no_depth_test = true    # stays readable even behind furniture
	_label.modulate = COLOR_FLAGGED
	_label.outline_size = 24
	_label.outline_modulate = Color(0.05, 0.05, 0.05, 1.0)
	_label.position = label_offset + Vector3(0.0, label_height, 0.0)
	add_child(_label)
