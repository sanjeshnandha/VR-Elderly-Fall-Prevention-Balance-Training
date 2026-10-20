class_name HazardPointer
extends Node3D
## Core System A, player side -- the hazard-flagging pointer.
##
## A short, thick, high-contrast beam cast from the controller's *aim* pose.
## The trigger on this hand does one thing and one thing only: flag whatever the
## beam is resting on (Architectural Fix 5.4).
##
## Deliberate accessibility choices:
##  * The ray masks hazards and UI ONLY, so it cannot snag on a wall halfway to
##    the thing the participant is trying to point at.
##  * `dwell_to_confirm` optionally flags after resting on a target for a moment,
##    for participants with a tremor or reduced grip strength who cannot press a
##    trigger without moving the beam off target.
##  * The beam turns yellow the instant it finds a target, so pressing is
##    confirmatory rather than exploratory.

## How far the beam reaches indoors, in metres. Room-scale: a longer beam makes
## precise selection harder, because a small hand tremor is amplified with
## distance, and nothing in the house is more than six metres from anywhere you
## can stand.
@export var beam_length: float = 6.0

## How far it reaches outdoors. The street is fifty-two metres long and the
## things to find are across a seven-metre road, so six metres puts several of
## them -- the postbox opposite, most obviously -- physically out of reach. The
## tremor argument still applies, but the volumes out there are a metre or more
## across, which absorbs it.
@export var beam_length_outdoors: float = 16.0

## The room where the longer reach applies.
@export var outdoor_room: String = "street"

@export var beam_radius: float = 0.008

## Flag automatically after holding the beam on a target this long. Set to 0 to
## require a trigger press. Non-zero is recommended for tremor accessibility.
@export var dwell_to_confirm: float = 0.0

## Name of the boolean OpenXR action used to flag. Must exist in
## res://openxr_action_map.tres.
@export var flag_action: String = "trigger_click"

const COLOR_IDLE := Color(0.55, 0.75, 1.0)
const COLOR_TARGET := Color(1.0, 0.85, 0.1)

var _controller: XRController3D
var _ray: RayCast3D
var _beam: MeshInstance3D
var _dot: MeshInstance3D
## Either a Hazard or an in-world button (anything exposing `press()`).
var _current: Node3D = null
var _dwell: float = 0.0
var _enabled: bool = true


func _ready() -> void:
	_controller = _find_controller()
	_build_beam()

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0.0, 0.0, -_reach())
	# Layer 1 (world) + layer 3 (hazard) + layer 6 (ui).
	# World geometry is included so the beam STOPS at a wall -- you should not
	# be able to flag the bathroom hazards from the hallway. But a world hit
	# never becomes a target below, so the beam never "snags": it just ends
	# there, and only a hazard or a button ever lights up.
	_ray.collision_mask = (1 << 0) | (1 << 2) | (1 << 5)
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	_ray.enabled = true
	add_child(_ray)

	if _controller != null:
		_controller.button_pressed.connect(_on_button_pressed)


func _find_controller() -> XRController3D:
	var node: Node = get_parent()
	while node != null:
		var controller := node as XRController3D
		if controller != null:
			return controller
		node = node.get_parent()
	return null


## Turn the pointer off during the balance exercise / debrief so the beam does
## not clutter the view.
func set_pointer_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	_ray.enabled = value
	if not value and _current != null:
		_set_hover(_current, false)
		_current = null


# ---------------------------------------------------------------------------
#  Frame update
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _enabled:
		return

	var reach := _reach()
	_ray.target_position = Vector3(0.0, 0.0, -reach)
	var hit: Node3D = null
	var distance := reach

	if _ray.is_colliding():
		var collider := _ray.get_collider() as Node3D
		distance = global_position.distance_to(_ray.get_collision_point())
		if collider != null and (collider is Hazard or collider.has_method("press")):
			hit = collider

	_set_target(hit)
	_update_beam(distance, hit != null)

	# Dwell-to-confirm for participants who cannot hold a trigger steady.
	if dwell_to_confirm > 0.0 and hit != null and not _already_done(hit):
		_dwell += delta
		if _dwell >= dwell_to_confirm:
			_dwell = 0.0
			_activate(hit)
	else:
		_dwell = 0.0


## Six metres indoors, sixteen outside.
func _reach() -> float:
	if SessionManager.current_room == outdoor_room:
		return beam_length_outdoors
	return beam_length


func _already_done(target: Node3D) -> bool:
	return target is Hazard and (target as Hazard).is_flagged


func _set_target(hit: Node3D) -> void:
	if hit == _current:
		return
	if _current != null:
		_set_hover(_current, false)
	_current = hit
	if _current != null:
		_set_hover(_current, true)


func _set_hover(target: Node3D, value: bool) -> void:
	if target.has_method("set_hovered"):
		target.call("set_hovered", value)


## Public equivalent of a trigger press. Used by the desktop debug rig.
func trigger() -> void:
	if not _enabled:
		return
	if _current != null:
		_activate(_current)
	else:
		AudioCues.play("page")


func _activate(target: Node3D) -> void:
	if target is Hazard:
		(target as Hazard).flag_hazard()
	elif target.has_method("press"):
		target.call("press")


func _on_button_pressed(action_name: String) -> void:
	# Only ever reacts to the flag action. Even if a stray action were somehow
	# delivered, it is ignored here as well as being absent from the action map.
	if not _enabled or action_name != flag_action:
		return
	if _current != null:
		_activate(_current)
	else:
		# Pressing at nothing is silent-but-acknowledged; a senior user pressing
		# a button and getting no response at all assumes the device is broken.
		AudioCues.play("page")


# ---------------------------------------------------------------------------
#  Beam visuals
# ---------------------------------------------------------------------------

func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = beam_radius
	cyl.bottom_radius = beam_radius
	cyl.height = 1.0
	cyl.radial_segments = 8
	_beam.mesh = cyl
	# Cylinders are built along +Y; rotate to point down -Z like the controller.
	_beam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(_beam)

	_dot = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.02
	sphere.height = 0.04
	sphere.radial_segments = 12
	sphere.rings = 6
	_dot.mesh = sphere
	add_child(_dot)

	_apply_color(COLOR_IDLE)


func _update_beam(distance: float, on_target: bool) -> void:
	_beam.scale = Vector3(1.0, distance, 1.0)
	_beam.position = Vector3(0.0, 0.0, -distance * 0.5)
	_dot.position = Vector3(0.0, 0.0, -distance)
	_dot.visible = on_target
	_apply_color(COLOR_TARGET if on_target else COLOR_IDLE)


func _apply_color(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam.material_override = mat
	_dot.material_override = mat
