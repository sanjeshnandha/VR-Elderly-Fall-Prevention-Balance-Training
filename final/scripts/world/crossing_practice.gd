@tool
class_name CrossingPractice
extends Node3D
## Street practice 2 -- crossing on the green man, measured.
##
## The street now has two practices. The first is `RoomRoute`, the ordinary
## walking route along the footpath, which is about getting past what is lying
## on the pavement. This is the second, and it is about the crossing itself.
##
## IT IS A RUN, NOT A SNAPSHOT. `StreetCrossing` scores the MOMENT of stepping
## off the kerb -- was the green man showing, did you look, was the road clear.
## That is a different question from how the crossing then went, and the second
## question is the one that catches the things that actually hurt an older
## pedestrian at a signalled crossing: hesitating on the kerb until the green
## man has nearly gone, drifting out of the marked lane, and still being in the
## road when the traffic gets its green back.
##
## So this node watches the whole run and scores it out of 100:
##
##   set off promptly     25   left the kerb soon after the green man appeared
##   kept to the markings 25   stayed between the edge lines while in the road
##   got across in time   50   reached the far side before the traffic's green
##
## Both of the first two are forfeit if the kerb was never left. Standing still
## technically never leaves the markings, and an earlier weighting handed 30
## points to somebody who pressed the button and did not move -- which is the
## one outcome the practice exists to discourage.
##
## THE BUTTON STARTS IT. Pressing to cross is already the first thing the
## participant must learn, so there is no second control to find: the practice
## arms itself on `TrafficSignal.demand_registered`, the rings appear when the
## green man does, and it ends when they reach the far pavement or when the
## lights change back.
##
## IT STILL NEVER BLOCKS. Walking out on a red man, wandering off the markings
## and dawdling are all possible, the cars still stop, and what happens is that
## the run is scored as what it was and said out loud.

signal run_finished(result: Dictionary)

enum Stage { IDLE, ARMED, CROSSING, DONE }

@export var room: String = "street"
@export var practice_id: String = "street_crossing_run"

@export var signal_path: NodePath
@export var crossing_path: NodePath

## Seconds after the green man appears within which stepping off counts as
## prompt. Generous: this is not a reaction test.
@export var start_grace: float = 3.5

## Setting off later than this scores nothing for promptness.
@export var start_limit: float = 9.0

## Seconds a participant may be off the markings before it starts to cost.
## Enough to absorb a wobble, not enough to absorb a diagonal.
@export var off_allowance: float = 0.7

## Off the markings for this long scores nothing for keeping to them.
@export var off_limit: float = 3.0

## Do not repeat the "you have stepped off" line more often than this.
@export var correction_cooldown: float = 5.0

## What the rings say on the way BACK, in the order they are reached. Leave it
## empty to keep each marker's own label in both directions.
@export var return_labels: Array[String] = []

const POINTS_PROMPT := 25.0
const POINTS_MARKINGS := 25.0
## Half the marks, because getting across before the traffic moves again is the
## thing that actually matters, and it is what the destination rings are for.
const POINTS_INTIME := 50.0
## Finishing on the flashing green man is normal and correct; it is finishing
## after the traffic has its green back that is the failure.
const INTIME_ON_CLEARING := 40.0

var stage: int = Stage.IDLE
## True when this run goes from the far pavement back to the near one.
var _reversed: bool = false
## Each marker's own label, kept so a return crossing can put them back.
var outbound_labels: Array[String] = []

var _signal: TrafficSignal
var _crossing: StreetCrossing
var _markers: Array[RouteMarker] = []
var _index: int = -1
var _probe: Area3D

var _green_at: float = 0.0
var _left_kerb_at: float = -1.0
var _off_seconds: float = 0.0
var _last_correction: float = -999.0
var _in_road: bool = false


func _ready() -> void:
	_collect_markers()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return

	_signal = get_node_or_null(signal_path) as TrafficSignal
	if _signal == null:
		_signal = get_tree().get_first_node_in_group("traffic_signal") as TrafficSignal
	_crossing = get_node_or_null(crossing_path) as StreetCrossing

	for marker in _markers:
		marker.reached.connect(_on_marker_reached)
		marker.dismiss()
	if _markers.size() < 2:
		push_warning("CrossingPractice '%s' has %d marker(s); it needs at least two."
			% [practice_id, _markers.size()])
		return
	if _signal != null:
		_signal.demand_registered.connect(_on_demand)
		_signal.phase_changed.connect(_on_phase_changed)
	for marker in _markers:
		outbound_labels.append(marker.label_text)
	SessionManager.session_started.connect(_reset)
	SessionManager.session_ended.connect(_on_session_ended)


func _collect_markers() -> void:
	_markers.clear()
	for child in get_children():
		var marker := child as RouteMarker
		if marker != null:
			if marker.room != room:
				marker.room = room
			_markers.append(marker)


func _reset() -> void:
	stage = Stage.IDLE
	_index = -1
	_left_kerb_at = -1.0
	_off_seconds = 0.0
	_in_road = false
	for marker in _markers:
		marker.reset()
		marker.dismiss()


func _on_session_ended(_summary: Dictionary) -> void:
	for marker in _markers:
		marker.dismiss()
	stage = Stage.DONE


# ---------------------------------------------------------------------------
#  Running it
# ---------------------------------------------------------------------------

func _on_demand() -> void:
	if stage == Stage.CROSSING:
		return
	stage = Stage.ARMED
	_index = -1
	_left_kerb_at = -1.0
	_off_seconds = 0.0
	_in_road = false
	for marker in _markers:
		marker.reset()
		marker.dismiss()
	AudioCues.speak_text(
		"Crossing practice. Wait here. When the green man shows, follow the rings "
		+ "straight across and keep between the white lines.")
	# The labels go back to the ones the scene set; _begin() swaps them again if
	# this turns out to be a return crossing.
	for i in _markers.size():
		if i < outbound_labels.size():
			_markers[i].label_text = outbound_labels[i]
	SessionManager.log_event("crossing_practice_armed", {"room": room})


func _on_phase_changed(phase: int) -> void:
	if phase == TrafficSignal.Phase.WALK and stage == Stage.ARMED:
		_begin()
	elif phase == TrafficSignal.Phase.TRAFFIC_GREEN and stage == Stage.CROSSING:
		# The traffic has its green back and they are not across.
		_finish(false)


## Which way is this crossing going?
##
## The rings are one list, laid near kerb to far kerb. Taken in that order they
## are right once and wrong ever after: having crossed, the participant presses
## the button on the far pole -- which works, and re-arms this -- and the first
## ring lights up seven metres away on the side they just came from, with the
## rest walking them backwards. They cross, and then they are stranded, or they
## follow the rings the wrong way across a road.
##
## So the list is walked forwards or backwards depending on which end they are
## standing at when the green man shows.
func _choose_direction() -> void:
	_reversed = false
	var probe := _player_probe()
	if probe == null or _markers.size() < 2:
		return
	var here := probe.global_position
	var first: float = here.distance_to(_markers[0].global_position)
	var last: float = here.distance_to(_markers[_markers.size() - 1].global_position)
	_reversed = last < first


## The marker that is step `index` of this run.
func _at(index: int) -> RouteMarker:
	var i := _markers.size() - 1 - index if _reversed else index
	return _markers[i]


func _begin() -> void:
	stage = Stage.CROSSING
	_green_at = _now()
	_choose_direction()
	_index = 0
	for marker in _markers:
		marker.reset()
		marker.set_shown(true)
	if _reversed and return_labels.size() == _markers.size():
		for i in _markers.size():
			_at(i).label_text = return_labels[i]
	_at(0).set_state(RouteMarker.State.NEXT)
	SessionManager.log_event("crossing_practice_started",
		{"room": room, "markers": _markers.size(), "returning": _reversed})


func _on_marker_reached(marker: RouteMarker) -> void:
	if stage != Stage.CROSSING or _index < 0 or marker != _at(_index):
		return
	marker.set_state(RouteMarker.State.DONE)
	AudioCues.play("confirm")
	_index += 1
	if _index >= _markers.size():
		_finish(true)
		return
	_at(_index).set_state(RouteMarker.State.NEXT)


func _physics_process(delta: float) -> void:
	if stage != Stage.CROSSING:
		return
	var probe := _player_probe()
	if probe == null:
		return
	var where := probe.global_position
	var on_road := _is_on_road(where)
	if on_road and not _in_road:
		_in_road = true
		if _left_kerb_at < 0.0:
			_left_kerb_at = _now()
	elif not on_road:
		_in_road = false
	if not on_road:
		return
	if _within_markings(where):
		return
	_off_seconds += delta
	if _off_seconds > off_allowance:
		_correct_off_markings()


## In the carriageway, judged from the crossing's own trigger box so there is
## one definition of "in the road" rather than two that can disagree.
func _is_on_road(where: Vector3) -> bool:
	if _crossing == null or not is_instance_valid(_crossing):
		return false
	var half := _crossing.extents * 0.5
	var local := _crossing.global_transform.affine_inverse() * where
	return absf(local.x) <= half.x and absf(local.z) <= half.z


func _within_markings(where: Vector3) -> bool:
	if _crossing == null or not is_instance_valid(_crossing):
		return true
	return absf(where.x - _crossing.crossing_centre_x) <= _crossing.crossing_half_width


func _correct_off_markings() -> void:
	var now := _now()
	if now - _last_correction < correction_cooldown:
		return
	_last_correction = now
	AudioCues.play("reminder")
	AudioCues.speak_text("You have stepped off the crossing. Keep between the white lines.")


func _player_probe() -> Area3D:
	if _probe == null or not is_instance_valid(_probe):
		var player := get_tree().get_first_node_in_group("xr_player") as XRPlayer
		_probe = player.probe if player != null else null
	return _probe


# ---------------------------------------------------------------------------
#  Scoring the run
# ---------------------------------------------------------------------------

func _finish(completed: bool) -> void:
	if stage != Stage.CROSSING:
		return
	stage = Stage.DONE
	for marker in _markers:
		marker.dismiss()

	var set_off := -1.0 if _left_kerb_at < 0.0 else _left_kerb_at - _green_at
	var prompt_points := 0.0
	var markings_points := 0.0
	if set_off >= 0.0:
		prompt_points = POINTS_PROMPT * clampf(
			1.0 - (set_off - start_grace) / maxf(start_limit - start_grace, 0.1), 0.0, 1.0)
		# Only once they are actually out there: never leaving the kerb is not
		# a perfect record of keeping to the markings.
		markings_points = POINTS_MARKINGS * clampf(
			1.0 - (_off_seconds - off_allowance) / maxf(off_limit - off_allowance, 0.1),
			0.0, 1.0)
	var intime_points := 0.0
	if completed:
		intime_points = INTIME_ON_CLEARING if _signal != null and _signal.is_clearing() \
			else POINTS_INTIME

	var result := {
		"kind": "run",
		"t": snappedf(SessionManager.session_time(), 0.01),
		"completed": completed,
		"set_off_after": snappedf(maxf(set_off, 0.0), 0.1) if set_off >= 0.0 else -1.0,
		"off_markings_s": snappedf(_off_seconds, 0.1),
		"markers_reached": maxi(_index, 0),
		"markers_total": _markers.size(),
		"score": snappedf(prompt_points + markings_points + intime_points, 0.1),
	}
	SessionManager.record_crossing(result)
	run_finished.emit(result)
	_coach(completed, set_off, intime_points)


## One thing, the one that cost the most.
func _coach(completed: bool, set_off: float, intime_points: float) -> void:
	if not completed:
		AudioCues.play("reminder")
		if set_off < 0.0:
			AudioCues.speak_text(
				"The green man has gone and you did not set off. Press the button "
				+ "again and start as soon as it shows.", true)
		else:
			AudioCues.speak_text(
				"The lights have changed and you are still in the road. Get to the "
				+ "pavement. Next time, start as soon as the green man shows.", true)
			_flash()
		return
	if _off_seconds > off_allowance:
		AudioCues.play("reminder")
		AudioCues.speak_text(
			"Across safely, but you wandered off the markings. Drivers look for "
			+ "people between the lines.")
		return
	if set_off > start_grace:
		AudioCues.play("neutral")
		AudioCues.speak_text(
			"Across safely, but you waited on the kerb. The green man is short -- "
			+ "set off as soon as it shows.")
		return
	if intime_points < POINTS_INTIME:
		AudioCues.play("confirm")
		AudioCues.speak_text("Across, and on the markings. You finished on the flashing man.")
		return
	AudioCues.play("success")
	AudioCues.speak_text("Well crossed. Straight off the kerb, on the markings, and across in time.")


func _flash() -> void:
	var vignette := get_tree().get_first_node_in_group("comfort_vignette")
	if vignette != null and vignette.has_method("flash"):
		vignette.call("flash", Color(0.9, 0.15, 0.1), 0.9)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
