@tool
class_name SlipZone
extends Area3D
## The consequence half of a hazard: stepping onto the wet tile / rug edge.
##
## DESIGN NOTE -- WHY THERE IS NO FALL ANIMATION
## ---------------------------------------------
## The obvious implementation is to lurch the camera as if the player slipped.
## Do not do this. Moving a VR camera in a way the user did not initiate is the
## single most reliable way to induce simulator sickness, and this cohort is
## both more susceptible to it and less able to recover from a genuine startle
## while wearing a headset. A real loss of balance in a real living room is the
## outcome we are trying to prevent, not stage.
##
## So a "slip" here is entirely non-vestibular:
##   * a head-locked warning tone and spoken line,
##   * a red edge vignette (peripheral, no motion),
##   * a `near_miss` entry in the session log.
##
## The learning signal is informational, not visceral, and the participant stays
## upright and comfortable throughout.

signal near_miss

@export var zone_id: String = ""
@export var room: String = "unknown"

## Hazard this zone belongs to. If the participant already spotted and flagged
## it, entering is treated as an informed choice and logged separately -- they
## demonstrated recognition, which is what the session is scoring.
@export var linked_hazard_path: NodePath

@export_multiline var warning_line: String = "Careful -- this floor is wet and slippery."

## Do not re-fire more often than this, in seconds.
@export var cooldown: float = 6.0

## Full size of the auto-generated trigger box, in metres. This is the WARNING
## volume and nothing else -- see the note below.
@export var extents: Vector3 = Vector3(1.6, 2.0, 1.6)

## The actual footprint of the thing: the width of the lead, the edge of the
## spill, the ground the footstool stands on. Leave at zero to use `extents`.
##
## TWO VOLUMES, AND WHY THEY MUST NOT BE THE SAME ONE.
##
## `extents` is a WARNING volume. You want it to speak a little BEFORE the
## participant is standing in the wet patch, so it is drawn generously and often
## covers a good share of the room -- the trailing lead's is twenty-five times
## the area of the lead.
##
## Nothing is scored against that volume. A warning is a warning; being warned
## early is the whole point of it, and a penalty for standing a half-metre from
## a coffee table would be telling the participant off for behaving correctly.
## It would also be unlearnable: no amount of care gets you round a room when
## the penalty region is bigger than the gaps between the furniture.
##
## So `route_extents` is the volume that COSTS something. Touching it is a near
## miss, it marks the walking leg dirty, and `RoomRoute` judges a chosen route
## against it. It is the object, not the space around the object.
@export var route_extents: Vector3 = Vector3.ZERO

## How far outside the footprint still counts as standing on the thing. The
## probe tracks the participant's body centre and their feet are wider than
## that, so a few centimetres of allowance is honest; much more and the
## penalty volume starts creeping back out towards the warning volume.
@export var contact_margin: float = 0.10


## The footprint a walking route has to miss, and the one that is scored.
func navigation_extents() -> Vector3:
	if route_extents.x > 0.001 and route_extents.z > 0.001:
		return route_extents
	return extents

var _hazard: Hazard
var _last_warning: float = -999.0
var _last_contact: float = -999.0

# Entering the warning volume only starts watching. What is scored is whether
# the body centre then crosses the footprint itself, which area_entered cannot
# tell you: it fires once, at the outer boundary, metres from the object.
var _probes: Array[Area3D] = []
var _in_contact: bool = false


func _ready() -> void:
	AutoShape.ensure_box(self, extents)
	set_physics_process(false)      # only runs while a probe is in the volume
	if Engine.is_editor_hint():
		return

	if zone_id.is_empty():
		zone_id = "%s_%s" % [room, name.to_snake_case()]
	_hazard = get_node_or_null(linked_hazard_path) as Hazard

	collision_layer = 0
	collision_mask = 1 << 1  # player probe
	monitoring = true
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player_probe"):
		return
	if not _probes.has(area):
		_probes.append(area)
	set_physics_process(true)
	_speak_warning()


func _on_area_exited(area: Area3D) -> void:
	_probes.erase(area)
	if _probes.is_empty():
		set_physics_process(false)
		_in_contact = false


func _physics_process(_delta: float) -> void:
	var touching := false
	for probe in _probes:
		if is_instance_valid(probe) and _inside_footprint(probe.global_position):
			touching = true
			break
	if touching and not _in_contact:
		_in_contact = true
		_register_contact()
	elif not touching:
		_in_contact = false


## X and Z only, like the route test: what matters is what your feet went
## through, and these volumes are two metres tall so height says nothing.
func _inside_footprint(world_point: Vector3) -> bool:
	var half := navigation_extents() * 0.5
	var local := global_transform.affine_inverse() * world_point
	return (absf(local.x) <= half.x + contact_margin
		and absf(local.z) <= half.z + contact_margin)


## Spoken as you come close. Costs nothing: it is the part of the system that
## is trying to help rather than measure.
func _speak_warning() -> void:
	if _hazard != null and _hazard.is_flagged:
		return                      # they spotted it; do not nag
	var now := SessionManager.session_time()
	if now - _last_warning < cooldown:
		return
	_last_warning = now
	AudioCues.speak_text(warning_line)


## You are standing on it. This is the part that costs something.
func _register_contact() -> void:
	var now := SessionManager.session_time()
	if now - _last_contact < cooldown:
		return
	_last_contact = now

	var recognised: bool = _hazard != null and _hazard.is_flagged
	# Counts towards the room score only while a session is running, and only
	# when the hazard had NOT been recognised first (see SessionManager).
	SessionManager.record_near_miss(zone_id, room, recognised)

	AudioCues.play("reminder")
	_flash_vignette()
	near_miss.emit()


## Peripheral-only red flash. Never touches camera transform.
func _flash_vignette() -> void:
	var vignette := get_tree().get_first_node_in_group("comfort_vignette")
	if vignette != null and vignette.has_method("flash"):
		vignette.flash(Color(0.9, 0.15, 0.1), 0.9)
