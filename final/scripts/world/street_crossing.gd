@tool
class_name StreetCrossing
extends Area3D
## Core System H -- crossing the road, measured.
##
## Falls outdoors are not mostly about the road surface: they are about how the
## crossing is approached. So this node watches the three things that actually
## separate a safe crossing from a risky one, and scores each attempt out of
## 100:
##
##   used the crossing   20   stepped into the road at the marked crossing
##                            rather than straight out between parked cars
##   looked both ways    25   turned the head far enough each way, recently
##                            enough to count, BEFORE stepping off the kerb
##   waited for the man  35   stepped out on a steady green man, having asked
##                            for it with the button
##   left enough time    20   no car was close (or they were already past)
##
## Without a signal on the crossing those weights fall back to the original
## 40 / 40 / 20, so a zebra crossing elsewhere would still score sensibly.
##
## THE SIGNAL TERM IS THE BIGGEST ONE ON PURPOSE. Judging a gap needs distance
## judgement, speed judgement and the nerve to commit, and it is the part that
## degrades first. Press, wait, watch, cross is a sequence instead, and a
## sequence can be learned and is the same at every crossing in the country.
##
## It measures; it never blocks. The participant can walk into the road
## anywhere, because a training tool that makes the mistake impossible cannot
## tell you whether they would have made it. What they get instead is a
## head-locked spoken correction at the moment it matters, and the number in
## their debrief.
##
## Put this Area3D over the ROAD SURFACE. The crossing itself is described by
## `crossing_centre_x` / `crossing_half_width` rather than another node, so
## there is one place to move it.

## Emitted for every step into the road, with the scored attempt.
signal crossing_attempted(result: Dictionary)

@export var zone_id: String = "street_crossing"
@export var room: String = "street"

## Full size of the auto-generated trigger box, in metres: the road surface.
@export var extents: Vector3 = Vector3(28.0, 2.5, 6.0)

## The marked crossing, as a span along X in GLOBAL coordinates.
@export var crossing_centre_x: float = 0.0
@export var crossing_half_width: float = 1.8

## The road runs along this axis. Looking "both ways" means looking along it,
## both ways, before stepping off the kerb.
@export var road_axis: Vector3 = Vector3.RIGHT

## How far off the road axis a glance may be and still count, in degrees.
@export var look_cone_degrees: float = 55.0

## A glance counts for this long. Look, then dawdle, and it no longer counts.
@export var look_window: float = 8.0

## Seconds of clear road needed for the gap to count as safe.
@export var safe_gap_seconds: float = 6.0

## Kept for a single named car; normally left empty, because every `StreetCar`
## puts itself in the "street_car" group and all of them are considered.
@export var car_path: NodePath

## The crossing's signal, if it has one.
@export var signal_path: NodePath

## How often to remind someone standing at the kerb who has not pressed yet.
@export var reminder_interval: float = 14.0

## Optional plain Area3D at the kerb: entering it prompts "stop and look both
## ways", once per session. It is set up from here (layer, mask and shape), so
## it needs no script of its own -- and must NOT have the RoomZone script, or
## leaving it would read as leaving the street.
@export var approach_zone_path: NodePath
@export var approach_extents: Vector3 = Vector3(4.0, 2.2, 1.2)

var _car: StreetCar
var _signal: TrafficSignal
var _approach: Area3D
var _at_kerb: bool = false
var _reminded_at: float = -999.0
var _pressed_this_wait: bool = false
var _camera: XRCamera3D
var _looked_positive: float = -999.0
var _looked_negative: float = -999.0
var _prompted: bool = false
var _inside: bool = false
var _entered_at: float = 0.0


func _ready() -> void:
	AutoShape.ensure_box(self, extents)
	if Engine.is_editor_hint():
		return

	collision_layer = 0
	collision_mask = 1 << 1  # player probe
	monitoring = true
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

	_car = get_node_or_null(car_path) as StreetCar
	_signal = get_node_or_null(signal_path) as TrafficSignal
	if _signal == null:
		_signal = get_tree().get_first_node_in_group("traffic_signal") as TrafficSignal
	if _signal != null:
		_signal.demand_registered.connect(_on_demand)
		_signal.phase_changed.connect(_on_signal_phase)
	_approach = get_node_or_null(approach_zone_path) as Area3D
	if _approach != null:
		AutoShape.ensure_box(_approach, approach_extents)
		_approach.collision_layer = 0
		_approach.collision_mask = 1 << 1  # player probe
		_approach.monitoring = true
		_approach.monitorable = false
		_approach.area_entered.connect(_on_approach_entered)
		_approach.area_exited.connect(_on_approach_exited)

	SessionManager.session_started.connect(_on_session_started)


func _on_session_started() -> void:
	_prompted = false
	_looked_positive = -999.0
	_looked_negative = -999.0
	_pressed_this_wait = false
	_reminded_at = -999.0


func _on_demand() -> void:
	_pressed_this_wait = true


## A fresh wait begins each time the traffic gets its green back.
func _on_signal_phase(phase: int) -> void:
	if phase == TrafficSignal.Phase.TRAFFIC_GREEN:
		_pressed_this_wait = false
		_reminded_at = _now()


func _on_approach_entered(area: Area3D) -> void:
	if not area.is_in_group("player_probe") or _inside:
		return
	_at_kerb = true
	_reminded_at = _now()
	if _prompted:
		return
	_prompted = true
	if _signal != null:
		AudioCues.speak_text(
			"You are at the kerb. This is a signalled crossing. Press the button on "
			+ "the pole, wait for the green man, then look both ways and cross."
		)
	else:
		AudioCues.speak_text(
			"You are at the kerb. Stop here, look both ways, and cross at the markings."
		)
	SessionManager.log_event("crossing_prompt", {"zone": zone_id})


func _on_approach_exited(area: Area3D) -> void:
	if area.is_in_group("player_probe"):
		_at_kerb = false


## Somebody standing at the kerb who has not pressed anything is stuck, because
## the signal rests on green until it is asked. Saying so beats cycling the
## lights on a timer, which would teach that the button does not matter.
func _remind_at_kerb() -> void:
	if _signal == null or not _at_kerb or _inside:
		return
	if _signal.is_walk() or _signal.is_clearing() or _signal.is_demanded():
		return
	var now := _now()
	if now - _reminded_at < reminder_interval:
		return
	_reminded_at = now
	AudioCues.speak_text(_signal.advice())


# ---------------------------------------------------------------------------
#  Watching the head, before the road
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	_remind_at_kerb()
	if _inside:
		return  # only glances made BEFORE stepping off the kerb count
	if _camera == null:
		var player := get_tree().get_first_node_in_group("xr_player") as XRPlayer
		if player == null:
			return
		_camera = player.camera
		if _camera == null:
			return

	var facing := -_camera.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return
	var along := facing.normalized().dot(road_axis.normalized())
	var threshold := cos(deg_to_rad(look_cone_degrees))
	var now := _now()
	if along >= threshold:
		_looked_positive = now
	elif along <= -threshold:
		_looked_negative = now


# ---------------------------------------------------------------------------
#  Stepping into the road
# ---------------------------------------------------------------------------

func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player_probe") or _inside:
		return
	_inside = true
	_entered_at = _now()

	var where := area.global_position
	var used_crossing := absf(where.x - crossing_centre_x) <= crossing_half_width
	var looked := _looked_both_ways()
	var gap := _gap_seconds(where)
	var safe_gap := gap >= safe_gap_seconds
	var obeyed := _signal == null or _signal.is_walk()

	var result := {
		"t": snappedf(SessionManager.session_time(), 0.01),
		"used_crossing": used_crossing,
		"looked_both_ways": looked,
		"safe_gap": safe_gap,
		"gap_seconds": snappedf(minf(gap, 99.0), 0.1),
		"entry_x": snappedf(where.x, 0.01),
		"score": _score(used_crossing, looked, obeyed, safe_gap),
	}
	if _signal != null:
		result["obeyed_signal"] = obeyed
		result["pressed_button"] = _pressed_this_wait
		result["signal_phase"] = _signal.phase_name()
	SessionManager.record_crossing(result)
	crossing_attempted.emit(result)
	_coach(used_crossing, looked, obeyed, safe_gap)


## With a signal the weights are 20 / 25 / 35 / 20; without one they fall back
## to the original 40 / 40 / 20, so the same node still scores a zebra.
func _score(used_crossing: bool, looked: bool, obeyed: bool, safe_gap: bool) -> float:
	if _signal == null:
		return ((40.0 if used_crossing else 0.0) + (40.0 if looked else 0.0)
			+ (20.0 if safe_gap else 0.0))
	return ((20.0 if used_crossing else 0.0) + (25.0 if looked else 0.0)
		+ (35.0 if obeyed else 0.0) + (20.0 if safe_gap else 0.0))


func _on_area_exited(area: Area3D) -> void:
	if not area.is_in_group("player_probe") or not _inside:
		return
	_inside = false
	# Fresh glances are needed for the next crossing.
	_looked_positive = -999.0
	_looked_negative = -999.0
	SessionManager.log_event("crossing_finished", {
		"zone": zone_id,
		"seconds_in_road": snappedf(_now() - _entered_at, 0.1),
	})


## Say the single most useful thing, not all four at once. Ordered by what
## would actually have hurt: a car first, then the signal, then the markings,
## then the glance.
func _coach(used_crossing: bool, looked: bool, obeyed: bool, safe_gap: bool) -> void:
	if not safe_gap:
		AudioCues.play("reminder")
		AudioCues.speak_text("A car is coming. Step back and wait for it to pass.", true)
		_flash()
		SessionManager.record_near_miss(zone_id, room, false)
		return
	if not obeyed:
		AudioCues.play("reminder")
		if _signal != null and _signal.is_clearing():
			AudioCues.speak_text(
				"The green man was flashing. That is for finishing, not for starting.")
		elif _signal != null and _signal.is_demanded():
			AudioCues.speak_text(
				"You asked for the crossing but stepped out before the green man. "
				+ "Wait for it; the traffic has not been stopped yet.")
		else:
			AudioCues.speak_text(
				"The red man was showing. Press the button on the pole and wait for "
				+ "the green man.")
		return
	if not used_crossing:
		AudioCues.play("reminder")
		AudioCues.speak_text("Cross at the markings. It is worth the few extra steps.")
		return
	if not looked:
		AudioCues.play("reminder")
		AudioCues.speak_text(
			"Remember to look both ways before you step into the road, even on a "
			+ "green man.")
		return
	AudioCues.play("confirm")
	AudioCues.speak_text("Good. You waited for the green man and looked both ways.")


func _looked_both_ways() -> bool:
	var now := _now()
	return (now - _looked_positive) <= look_window and (now - _looked_negative) <= look_window


## Seconds before the car reaches the point being crossed at. A car that has
## already gone past, or that is waiting off-screen, is not a reason to stand
## on the kerb.
## Every car on the street is considered, not one named one: with two lanes the
## nearest threat is often the one coming the other way.
func _gap_seconds(where: Vector3) -> float:
	var soonest := 99.0
	var cars := get_tree().get_nodes_in_group("street_car")
	if cars.is_empty() and _car != null and is_instance_valid(_car):
		cars = [_car]
	for node in cars:
		var car := node as StreetCar
		if car == null or not is_instance_valid(car):
			continue
		if not car.is_approaching(where.x):
			continue
		soonest = minf(soonest, car.time_to_reach(where.x))
	return soonest


## Peripheral-only red flash, exactly as SlipZone does it: never any camera
## movement, in this cohort, ever.
func _flash() -> void:
	var vignette := get_tree().get_first_node_in_group("comfort_vignette")
	if vignette != null and vignette.has_method("flash"):
		vignette.call("flash", Color(0.9, 0.15, 0.1), 0.9)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
