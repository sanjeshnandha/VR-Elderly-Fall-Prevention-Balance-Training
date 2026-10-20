@tool
class_name RoomRoute
extends Node3D
## The walking route for one room -- Core System I.
##
## Finding a hazard and getting past one are different skills. A participant can
## point at a coffee table, name it correctly, and then walk their shin straight
## into it. This node tests the second half: having seen the room, can you cross
## it without touching anything.
##
## HOW IT WORKS. Its RouteMarker children are the stops, in tree order. Until the
## route starts, none of them is drawn at all: an empty room is what the
## participant should see while they are still hunting for hazards. The route
## begins when the session starts in this room, or when they walk into it
## afterwards. Then ONE ring appears, in amber. Standing on it turns it green for
## a moment, it disappears, and the next one appears -- one place to go to at a
## time, never a trail of five. The stretch between two markers is a LEG, and
## each leg is judged clean or not.
##
## A LEG IS DIRTY IF EITHER HALF OF THE SKILL FAILED:
##
##   1. You touched a hazard on the way.    A SlipZone in this room fired during
##      the leg -- you physically walked into the wet floor, the trailing lead,
##      the footstool. This is the half that catches walking.
##   2. Your route went through one.        The path you actually walked passes
##      through a hazard's footprint. This is the half that catches teleporting:
##      choosing a destination on the far side of the coffee table, straight over
##      it, is a bad route even though your feet never touched anything.
##
##      THE PATH YOU WALKED, not the straight line between the two rings. That
##      line was what this tested at first, and it made the whole exercise
##      unwinnable: every room here is laid out so that the direct line between
##      two rings is blocked -- `tools/check_routes.py` refuses a route where it
##      is not, because a leg you can walk straight down tests nothing -- so the
##      legs that required a detour were marked dirty whether you took the
##      detour or walked through the table. A participant who found every hazard
##      and went round every one of them scored 81 for the room, and could not
##      do better. Walking the room properly now scores 100, and the rule still
##      catches a teleport straight over a footstool, because two consecutive
##      samples either side of it make a segment that crosses it.
##
## Crossing a hazard counts even when you had already flagged it. That differs
## from the near-miss rule in slip_zone.gd, deliberately: the near miss is about
## RECOGNITION, and walking knowingly into something you identified is at least
## honest. This is about NAVIGATION, and the lesson of the task is that noticing
## the obstacle is not the same as going round it. The log records which case it
## was, so the distinction survives into the data.
##
## IT NEVER BLOCKS. Unlike the staircase (Architectural Fix 5.1), nothing here is
## enforced: you can ignore the rings entirely, walk anywhere, and leave. A room
## you never routed scores zero for the route and the rest of the session is
## unaffected. Gating a living room would teach compliance with a video game, not
## confidence in a house.
##
## The staircase deliberately has no RoomRoute: its gated teleport chain already
## is one, with stricter rules.

signal leg_finished(room: String, index: int, clean: bool)
signal route_finished(room: String, clean_legs: int, total_legs: int)

@export var room: String = "unknown"

## Start as soon as the participant walks in. Off makes the route dormant until
## `begin()` is called, which is how you would bolt it to a button instead.
@export var auto_start_on_entry: bool = true

@export_multiline var start_line: String = \
	"Now cross the room. Stand on each ring in turn, and keep clear of anything underfoot."

## Most points tested along ONE SEGMENT of the walked path. Segments are short,
## so this is only reached after a teleport.
@export var samples_per_leg: int = 24

## How often the walked path is sampled, in seconds. At a walking pace this is a
## point every 10-15 cm, which is finer than anything you could thread a foot
## through.
@export var path_sample_seconds: float = 0.12

## A sample is kept only if it is this far from the last one, so standing still
## does not fill the array.
@export var path_sample_distance: float = 0.05

## Height above the floor at which the route is tested, in metres. Ankle height:
## what matters is what your feet would have gone through, not your head.
@export var sample_height: float = 0.12

var _markers: Array[RouteMarker] = []
var _zones: Array[SlipZone] = []
var _index: int = -1
var _started: bool = false
var _finished: bool = false
var _leg_from: Vector3 = Vector3.ZERO
var _leg_touched: bool = false
var _leg_touch_recognised: bool = false
## Where the participant actually went during this leg.
var _leg_path: PackedVector3Array = PackedVector3Array()
var _sample_due: float = 0.0
var _probe: Node3D = null


func _ready() -> void:
	_collect_markers()
	if Engine.is_editor_hint():
		return

	_collect_zones()
	for zone in _zones:
		zone.near_miss.connect(_on_zone_near_miss.bind(zone))
	for marker in _markers:
		marker.reached.connect(_on_marker_reached)
		marker.set_state(RouteMarker.State.PENDING)

	if _markers.size() < 2:
		push_warning("RoomRoute '%s' has %d marker(s); a route needs at least two."
			% [room, _markers.size()])
		return

	SessionManager.register_route(room, _markers.size() - 1)
	if auto_start_on_entry:
		SessionManager.room_changed.connect(_on_room_changed)
		# room_changed only fires when the room actually CHANGES. The participant
		# presses Begin while standing in the hallway, which is already the
		# current room, so that signal never arrives and the route would sit
		# there dormant. Starting the session is the other way in.
		SessionManager.session_started.connect(_on_session_started)
	SessionManager.session_ended.connect(_on_session_ended)


func _on_session_started() -> void:
	if SessionManager.current_room == room:
		begin()


func _on_session_ended(_summary: Dictionary) -> void:
	for marker in _markers:
		marker.dismiss()


func _collect_markers() -> void:
	_markers.clear()
	for child in get_children():
		var marker := child as RouteMarker
		if marker != null:
			if marker.room != room:
				marker.room = room
			_markers.append(marker)


## Every SlipZone anywhere in the tree that belongs to this room. They are the
## hazard footprints: there is no second set of volumes to keep in step with
## them, which is the whole reason this reuses them rather than defining its own.
func _collect_zones() -> void:
	_zones.clear()
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var zone := node as SlipZone
		if zone != null and zone.room == room:
			_zones.append(zone)
		for child in node.get_children():
			stack.append(child)


# ---------------------------------------------------------------------------
#  Running the route
# ---------------------------------------------------------------------------

func _on_room_changed(entered: String) -> void:
	var here := entered == room
	# One room's rings at a time. A route left half-finished keeps its place, but
	# stops glowing at the participant from the next room through a doorway.
	if _started and not _finished:
		for marker in _markers:
			marker.set_shown(here)
		return
	if not here or _finished or not SessionManager.session_active:
		return
	begin()


## Light the first ring. Safe to call twice.
func begin() -> void:
	if _started or _markers.size() < 2:
		return
	_started = true
	_index = 0
	for marker in _markers:
		marker.reset()
	_markers[0].set_state(RouteMarker.State.NEXT)
	SessionManager.log_event("route_started", {"room": room, "legs": _markers.size() - 1})
	if not start_line.is_empty():
		AudioCues.speak_text(start_line)


func _on_marker_reached(marker: RouteMarker) -> void:
	if _finished or _index < 0 or marker != _markers[_index]:
		return

	marker.set_state(RouteMarker.State.DONE)
	AudioCues.play("confirm")

	if _index > 0:
		_finish_leg(marker)

	_index += 1
	if _index >= _markers.size():
		_complete()
		return

	_markers[_index].set_state(RouteMarker.State.NEXT)
	_begin_leg(marker.global_position)


func _begin_leg(from: Vector3) -> void:
	_leg_from = from
	_leg_touched = false
	_leg_touch_recognised = false
	_leg_path = PackedVector3Array([from])
	_sample_due = 0.0


## Record where the participant is, while a leg is in progress.
func _physics_process(delta: float) -> void:
	if not _started or _finished or _index <= 0:
		return
	_sample_due -= delta
	if _sample_due > 0.0:
		return
	_sample_due = maxf(path_sample_seconds, 0.02)
	var probe := _player_probe()
	if probe == null:
		return
	var point := probe.global_position
	# A long jump between two samples is a teleport, and it is kept exactly as
	# it is: the segment across the gap is what rule 2 is about.
	if _leg_path.size() > 0 and \
			point.distance_to(_leg_path[_leg_path.size() - 1]) < path_sample_distance:
		return
	if _leg_path.size() < 2048:
		_leg_path.append(point)


func _player_probe() -> Node3D:
	if _probe == null or not is_instance_valid(_probe):
		var player := get_tree().get_first_node_in_group("xr_player")
		if player != null:
			_probe = player.get("probe") as Node3D
	return _probe if is_instance_valid(_probe) else null


func _finish_leg(marker: RouteMarker) -> void:
	_leg_path.append(marker.global_position)
	var crossed := _path_crosses_hazard(_leg_path)
	var clean := not _leg_touched and crossed.is_empty()
	var index := _index    # the leg that has just ended arrives AT this marker

	SessionManager.record_route_leg(room, index, clean, {
		"to": marker.marker_id,
		"touched": _leg_touched,
		"touched_recognised": _leg_touch_recognised,
		"crossed": crossed,
	})
	if not clean:
		AudioCues.play("reminder")
	leg_finished.emit(room, index, clean)


func _complete() -> void:
	_finished = true
	var total: int = _markers.size() - 1
	var clean: int = SessionManager.route_legs_clean(room)
	SessionManager.record_route_complete(room, clean, total)
	# The route is over: the last green ring goes with it, so the room is left
	# as the participant found it.
	for marker in _markers:
		marker.dismiss()
	if clean >= total:
		AudioCues.speak_text("Nicely done. You crossed the room without touching a thing.")
	else:
		AudioCues.speak_text(
			"That is the room crossed. %d of the %d stretches were clear."
			% [clean, total])
	route_finished.emit(room, clean, total)


func _on_zone_near_miss(zone: SlipZone) -> void:
	if not _started or _finished or _index <= 0:
		return
	_leg_touched = true
	var hazard := zone.get_node_or_null(zone.linked_hazard_path) as Hazard
	if hazard != null and hazard.is_flagged:
		_leg_touch_recognised = true


# ---------------------------------------------------------------------------
#  Did the route go through something?
# ---------------------------------------------------------------------------

## Zone ids whose footprint the straight line from `from` to `to` passes through.
##
## Tested analytically against each zone's `extents` rather than with a physics
## query, because a SlipZone sits on collision layer 0 -- it only ever monitors,
## and occupies no layer for anything else to find it with. Transforming the
## sample into the zone's own space and comparing against half-extents is exact,
## costs nothing, and does not require giving those volumes a layer they would
## then show up on in every other query in the house.
func _path_crosses_hazard(path: PackedVector3Array) -> Array:
	var hit: Array = []
	if _zones.is_empty() or path.size() < 2:
		return hit
	for i in path.size() - 1:
		for zone_id in _segment_crosses_hazard(path[i], path[i + 1]):
			if not hit.has(zone_id):
				hit.append(zone_id)
	return hit


func _segment_crosses_hazard(from: Vector3, to: Vector3) -> Array:
	var hit: Array = []
	if _zones.is_empty():
		return hit
	# One sample per 80 mm along the segment. Walked segments are short and need
	# two or three; the long one after a teleport is where this matters.
	var steps := clampi(ceili(from.distance_to(to) / 0.08), 2, maxi(samples_per_leg, 2))
	for zone in _zones:
		var inverse := zone.global_transform.affine_inverse()
		var half := zone.navigation_extents() * 0.5
		for i in steps + 1:
			var point := from.lerp(to, float(i) / float(steps))
			point.y = from.y + sample_height
			var local := inverse * point
			# X and Z only: a tripping hazard's footprint is what the route has
			# to miss, and the zones are two metres tall so height tells you
			# nothing useful here.
			if absf(local.x) <= half.x and absf(local.z) <= half.z:
				hit.append(zone.zone_id)
				break
	return hit
