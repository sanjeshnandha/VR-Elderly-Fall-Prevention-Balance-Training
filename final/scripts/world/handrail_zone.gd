@tool
class_name HandrailZone
extends Area3D
## Core System B -- handrail / grab-bar compliance check.
##
## Place this Area3D over a stretch the participant should not cross without
## holding on: the flight of stairs, the step into the bath, the length of the
## tub. Point `rail_path` at the GrabRail they are supposed to use.
##
## The zone measures *how much of the transit* was spent gripping, not merely
## whether the rail was touched once. `min_grip_fraction` is the pass mark.
##
## It records; it does not block. Blocking happens one level up, in
## `gated_teleport_point.gd` (Architectural Fix 5.1), which refuses to let the
## user warp past the stairs in the first place. This zone is what catches the
## case where they *can* walk it physically but let go halfway.

signal transit_started
signal transit_finished(complied: bool)

@export var zone_id: String = ""
@export var room: String = "unknown"
@export_multiline var description: String = "Hold the rail while crossing."

## The rail that must be held. Required.
@export var rail_path: NodePath

## Fraction of time-in-zone that must be spent gripping to pass. 0.6 is a
## deliberately forgiving pass mark: letting go for a moment to open a door is
## normal, letting go for the whole flight is the behaviour we are training out.
@export_range(0.0, 1.0, 0.05) var min_grip_fraction: float = 0.6

## Seconds inside the zone with no grip before the gentle spoken reminder fires.
@export var remind_after_seconds: float = 2.5

## Ignore transits shorter than this. Stops a participant brushing the edge of
## the zone from generating a spurious "missed safe habit" event.
@export var min_transit_seconds: float = 1.0

## Full size of the auto-generated trigger box. Cover the whole flight of stairs
## or the whole length of the tub.
@export var extents: Vector3 = Vector3(2.0, 2.5, 3.0)

var _rail: GrabRail
var _inside: bool = false
var _transit_start: float = 0.0
var _grip_time: float = 0.0
var _time_since_grip: float = 0.0
var _reminded: bool = false


func _ready() -> void:
	AutoShape.ensure_box(self, extents)
	if Engine.is_editor_hint():
		return

	if zone_id.is_empty():
		zone_id = "%s_%s" % [room, name.to_snake_case()]

	_rail = get_node_or_null(rail_path) as GrabRail
	if _rail == null:
		push_error("HandrailZone '%s': rail_path does not point at a GrabRail." % zone_id)

	# Detect the player probe only (layer 2 "player").
	collision_layer = 0
	collision_mask = 1 << 1
	monitoring = true

	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	set_physics_process(false)

	SessionManager.register_handrail_zone(zone_id, room, description)


func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player_probe") or _inside:
		return
	_inside = true
	_transit_start = SessionManager.session_time()
	_grip_time = 0.0
	_time_since_grip = 0.0
	_reminded = false
	set_physics_process(true)
	SessionManager.log_event("handrail_zone_entered", {"zone": zone_id, "room": room})
	transit_started.emit()


func _on_area_exited(area: Area3D) -> void:
	if not area.is_in_group("player_probe") or not _inside:
		return
	_inside = false
	set_physics_process(false)

	var transit := SessionManager.session_time() - _transit_start
	if transit < min_transit_seconds:
		# Grazed the edge of the zone; not a real transit, do not score it.
		SessionManager.log_event("handrail_zone_grazed", {"zone": zone_id})
		return

	var fraction := _grip_time / maxf(transit, 0.001)
	var complied := fraction >= min_grip_fraction
	SessionManager.record_handrail_result(zone_id, complied, _grip_time, transit)

	if not complied:
		AudioCues.play("reminder")
		AudioCues.speak("use_rail")

	transit_finished.emit(complied)


func _physics_process(delta: float) -> void:
	if _rail == null:
		return

	if _rail.is_held:
		_grip_time += delta
		_time_since_grip = 0.0
		if _reminded:
			_reminded = false
			AudioCues.speak("rail_good")
		return

	_time_since_grip += delta
	if not _reminded and _time_since_grip >= remind_after_seconds:
		_reminded = true
		# Head-locked cue: audible no matter which way they are facing.
		AudioCues.play("reminder")
		AudioCues.speak("use_rail")
		SessionManager.log_event("handrail_reminder", {"zone": zone_id})
