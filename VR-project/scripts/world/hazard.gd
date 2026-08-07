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

## Full size of the auto-generated trigger box, in metres. Ignored if the scene
## already provides a CollisionShape3D.
@export var extents: Vector3 = Vector3(0.6, 0.6, 0.6)

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
	if highlight_meshes.is_empty():
		_gather_meshes_recursive(self)
	else:
		for path in highlight_meshes:
			var n := get_node_or_null(path) as MeshInstance3D
			if n != null:
				_meshes.append(n)
	for m in _meshes:
		_originals.append(m.material_overlay)


func _gather_meshes_recursive(node: Node) -> void:
	for child in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			_meshes.append(mesh)
		_gather_meshes_recursive(child)


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
		# A decoy. Logged for the researcher, gently acknowledged for the user.
		SessionManager.record_false_positive(hazard_name, room)
		AudioCues.play("reject")
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
	for i in _meshes.size():
		var mesh := _meshes[i]
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
	_label.no_depth_test = true    # stays readable even behind furniture
	_label.modulate = COLOR_FLAGGED
	_label.outline_size = 24
	_label.outline_modulate = Color(0.05, 0.05, 0.05, 1.0)
	_label.position = Vector3(0.0, label_height, 0.0)
	add_child(_label)
