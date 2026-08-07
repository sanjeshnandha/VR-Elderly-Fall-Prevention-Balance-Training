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

## Full size of the auto-generated trigger box, in metres.
@export var extents: Vector3 = Vector3(1.6, 2.0, 1.6)

var _hazard: Hazard
var _last_fire: float = -999.0


func _ready() -> void:
	AutoShape.ensure_box(self, extents)
	if Engine.is_editor_hint():
		return

	if zone_id.is_empty():
		zone_id = "%s_%s" % [room, name.to_snake_case()]
	_hazard = get_node_or_null(linked_hazard_path) as Hazard

	collision_layer = 0
	collision_mask = 1 << 1  # player probe
	monitoring = true
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player_probe"):
		return
	var now := SessionManager.session_time()
	if now - _last_fire < cooldown:
		return
	_last_fire = now

	var recognised: bool = _hazard != null and _hazard.is_flagged
	SessionManager.log_event("near_miss", {
		"zone": zone_id,
		"room": room,
		"hazard_already_flagged": recognised,
	})

	AudioCues.play("reminder")
	if not recognised:
		AudioCues.speak_text(warning_line)

	_flash_vignette()
	near_miss.emit()


## Peripheral-only red flash. Never touches camera transform.
func _flash_vignette() -> void:
	var vignette := get_tree().get_first_node_in_group("comfort_vignette")
	if vignette != null and vignette.has_method("flash"):
		vignette.flash(Color(0.9, 0.15, 0.1), 0.9)
