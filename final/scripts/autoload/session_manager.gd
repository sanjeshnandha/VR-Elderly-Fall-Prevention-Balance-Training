extends Node
## Session recorder, scorer, adaptive focus and JSON persistence -- Core System E.
##
## This is the data source for the whole project: everything a caregiver or
## researcher sees comes out of here, and everything the debrief panel and the
## performance board show is read back from the same structures that get
## written to disk.
##
## FILE LAYOUT  (user://session_log.json, schema 2)
## ------------------------------------------------
##   {
##     "schema_version": 3,
##     "participant_id": "P01",
##     "sessions": [ <session>, <session>, ... ]     # oldest first
##   }
##
## The file holds an ARRAY of sessions rather than one session, because the
## stated goal is measuring improvement *across* runs.
##
## PER-TEST SCORES AND ADAPTIVE FOCUS
## ----------------------------------
## Every room (hallway, bathroom, staircase, bedroom) and the balance exercise
## is scored separately, 0-100, as its own "test" (see `test_scores()`):
##
##   room    = 70 % hazards found in that room + 30 % rail use in that room
##             (renormalised if the room has no rail), minus 10 per near miss
##             on a hazard the participant had not yet recognised (max -20)
##   street  = 60 % hazards found outdoors + 40 % the footpath route, same
##             near-miss penalty
##   street_crossing
##           = its own test, not part of the street room: 65 % the quality of
##             the signalled crossing runs (scripts/world/crossing_practice.gd)
##             + 35 % how the kerb was stepped off on each entry into the road
##             (scripts/world/street_crossing.gd), renormalised when only one
##             of the two happened
##   balance = mean steadiness of COMPLETED reaches x fraction completed
##
## `compute_focus()` averages each test over the participant's last
## FOCUS_WINDOW sessions and picks the LOWEST one below FOCUS_THRESHOLD as the
## focus for the next session. The session director then points the
## participant at it, gives hints drawn from what they missed there, and the
## board marks it. When every test is at or above the threshold there is no
## focus and the participant explores freely.
##
## On Windows `user://` resolves to
##   %APPDATA%\Godot\app_userdata\VR Fall-Prevention Trainer\session_log.json
## Use `OS.get_user_data_dir()` (printed at session end) to find it.

const LOG_PATH := "user://session_log.json"
## 3 added the per-room walking route (Core System I). The change is purely
## additive -- every key a version 2 log had is still written, and the history
## reader takes defaults for anything missing -- so old logs still load and still
## feed the adaptive focus.
const SCHEMA_VERSION := 3

## Weightings used for the overall score. Hazard recognition is the primary
## training objective, so it carries the most weight.
const WEIGHT_HAZARD := 0.5
const WEIGHT_HANDRAIL := 0.3
const WEIGHT_BALANCE := 0.2

## Per-room score weightings.
## Core System I added a third component to a room: crossing it safely. Hazard
## recognition stays the largest share, because spotting the thing is still the
## primary skill, but getting past it without contact is now worth almost as
## much as using a handrail -- and in the four rooms that have no rail at all it
## is the only behavioural measure there is.
##
## Any component a room cannot offer is dropped and the rest renormalised, so a
## room with no rail and no route is still scored purely on what it can test.
const ROOM_WEIGHT_HAZARD := 0.5
const ROOM_WEIGHT_RAIL := 0.2
const ROOM_WEIGHT_ROUTE := 0.3

## Outdoors there are two practices rather than one: walking the footpath (the
## ordinary Core System I route, past the leaves, the bin and the lifted slab)
## and the signalled crossing. They are scored as two SEPARATE tests, so a
## participant who reads the lights well but keeps tripping on the path -- or
## the reverse -- can see which of the two needs the work, and the adaptive
## focus can send them back to just that one. The street room therefore covers
## the footpath only.
const STREET_ROOM := "street"
const STREET_WEIGHT_HAZARD := 0.6
const STREET_WEIGHT_ROUTE := 0.4

## Core System J, scored on its own. A completed run carries the larger share
## because crossing the whole road on one green man is the skill being trained;
## stepping off the kerb correctly is the habit underneath it. Either share is
## dropped and the other renormalised when only one of the two happened, so a
## participant who pressed the button and crossed properly is not marked down
## for never having stepped into the road anywhere else.
const CROSSING_TEST := "street_crossing"
const CROSSING_WEIGHT_RUN := 0.65
const CROSSING_WEIGHT_ENTRY := 0.35
const NEAR_MISS_PENALTY := 10.0
const NEAR_MISS_PENALTY_CAP := 20.0

## Tests are shown and tie-broken in this order.
const ROOM_ORDER: Array[String] = [
	"hallway", "living_room", "kitchen", "bathroom", "staircase", "bedroom", "street",
]
const TEST_ORDER: Array[String] = [
	"hallway", "living_room", "kitchen", "bathroom", "staircase", "bedroom", "street",
	"street_crossing", "balance",
]
const TEST_NAMES := {
	"hallway": "Hallway",
	"living_room": "Living room",
	"kitchen": "Kitchen",
	"bathroom": "Bathroom",
	"staircase": "Stairs",
	"bedroom": "Bedroom",
	"street": "Street",
	"street_crossing": "Road crossing",
	"balance": "Balance",
}

## A test is only chosen as the focus while its recent average is below this.
const FOCUS_THRESHOLD := 90.0
## How many recent sessions the focus average looks back over.
const FOCUS_WINDOW := 3

## Gentle hints, keyed by hazard id. They point at *where to look*, not at the
## answer, so the next session still tests recognition.
const HINTS := {
	"bathroom_wet_floor": "Look closely at the floor surface.",
	"bathroom_no_grab_bar": "Think about what you would hold on to when stepping into the bath.",
	"stairs_missing_rail": "Check both sides of the staircase.",
	"stairs_dim_light": "Look up. Can you see every step clearly?",
	"stairs_uneven_step": "Compare the height of each step with the next.",
	"hall_rug_edge": "Look at the edges of anything lying on the floor.",
	"hall_extension_cord": "Look for anything crossing the walkway.",
	"bed_dim_light": "Imagine getting up here at night. Is there enough light?",
	"bed_armless_chair": "Think about how you would stand up from each seat.",
	"bed_floor_clutter": "Follow the path from the bed to the door with your eyes.",
	"living_low_sofa": "Think about how you would stand up from each seat in here.",
	"living_coffee_table": "Look at the floor between the door and the chairs.",
	"living_trailing_flex": "Follow the leads from each appliance with your eyes.",
	"living_footstool": "Look for anything small left where you walk.",
	"kitchen_high_shelf": "Look up. What do you use every day, and how high is it?",
	"kitchen_step_stool": "How would you reach the top shelf, and what would you hold?",
	"kitchen_wet_floor": "Look at the floor in front of the sink.",
	"kitchen_open_door": "Look at the cupboards at knee height.",
	"bathroom_bath_mat": "Look at what is on the floor beside the bath.",
	"street_front_step": "Look down as you go through the front door.",
	"street_uneven_paving": "Watch the joints between the paving slabs.",
	"street_high_kerb": "Look at the height of the kerb before you step off it.",
	"street_wet_leaves": "Wet leaves are as slippery as ice. Look at what is underfoot.",
	"street_bin_blocking": "Notice anything that pushes you off the pavement.",
}

signal session_started
signal session_ended(summary: Dictionary)
signal hazard_flagged(hazard_id: String, hazard_name: String)
signal hazard_progress_changed(found: int, total: int)
signal handrail_result(zone_id: String, complied: bool)
signal balance_trial_recorded(trial: Dictionary)
## Any live score changed. The performance board redraws on this.
signal scores_changed
## Every hazard in `room` has now been found.
signal room_completed(room: String)
## The participant moved into a different room ("" = between rooms).
signal room_changed(room: String)

# --- Live session state ----------------------------------------------------

var session_active: bool = false
var session_finished: bool = false
var _session_start_ms: int = 0
var _session_id: String = ""
var _started_utc: String = ""

## hazard_id -> {id, name, room, found, time_to_flag_s}
var _hazards: Dictionary = {}
## zone_id -> {id, room, description, transits: Array[Dictionary]}
var _handrail_zones: Dictionary = {}
## Array of balance trial dictionaries.
var _balance_trials: Array[Dictionary] = []
## Chronological raw event log; the audit trail behind the aggregates.
var _events: Array[Dictionary] = []
## object name -> {object, room, count, first_t}. Safe objects the user flagged.
var _false_positives: Dictionary = {}
## Array of {zone, room, recognised, t}.
var _near_misses: Array[Dictionary] = []
## One entry per step into the road; see scripts/world/street_crossing.gd.
var _crossings: Array[Dictionary] = []

## Walking routes, by room: what RoomRoute registered and how it went.
##   { room: { "legs_total": int, "legs_done": int, "legs_clean": int,
##             "started": bool, "finished": bool, "detail": Array } }
var _routes: Dictionary = {}

## Room occupancy. Rooms touch at doorways, so the probe can briefly be in two;
## the most recently entered one is "current".
var _rooms_occupied: Array[String] = []
var current_room: String = ""
var _room_entered_at: float = 0.0
## room -> seconds spent there this session.
var _room_time: Dictionary = {}

## Focus chosen for THIS session (from previous sessions), and the per-test
## scores of the latest previous session, both captured before it starts.
var current_focus: Dictionary = {}
var baseline_tests: Dictionary = {}
var _last_summary: Dictionary = {}

var _corrupt_log_backed_up: bool = false


func _ready() -> void:
	refresh_history_snapshot()


# ---------------------------------------------------------------------------
#  Registration -- objects call these from their own _ready()
# ---------------------------------------------------------------------------

## Every Hazard node registers itself so `total` is derived from the scene, not
## hard-coded. Adding a hazard to a room automatically updates the denominator.
func register_hazard(hazard_id: String, hazard_name: String, room: String) -> void:
	if _hazards.has(hazard_id):
		push_warning("SessionManager: duplicate hazard id '%s'" % hazard_id)
	_hazards[hazard_id] = {
		"id": hazard_id,
		"name": hazard_name,
		"room": room,
		"found": false,
		"time_to_flag_s": -1.0,
	}
	hazard_progress_changed.emit(hazards_found(), hazards_total())


## Every handrail / grab-bar compliance zone registers itself.
func register_handrail_zone(zone_id: String, room: String, description: String) -> void:
	_handrail_zones[zone_id] = {
		"id": zone_id,
		"room": room,
		"description": description,
		"transits": [],
	}


# ---------------------------------------------------------------------------
#  Session lifecycle
# ---------------------------------------------------------------------------

## Re-read the log and work out the focus and the "last time" scores for the
## board. Called at startup and again when a session starts.
func refresh_history_snapshot() -> void:
	current_focus = compute_focus()
	var previous := get_previous_session()
	baseline_tests = tests_of_session(previous) if not previous.is_empty() else {}


func start_session() -> void:
	refresh_history_snapshot()
	session_active = true
	session_finished = false
	_session_start_ms = Time.get_ticks_msec()
	_started_utc = Time.get_datetime_string_from_system(true)
	_session_id = "%s-%04d" % [
		_started_utc.replace(":", "").replace("-", ""),
		randi() % 10000,
	]
	_balance_trials.clear()
	_events.clear()
	_false_positives.clear()
	_near_misses.clear()
	_crossings.clear()
	for room: String in _routes:
		var route: Dictionary = _routes[room]
		route["legs_done"] = 0
		route["legs_clean"] = 0
		route["started"] = false
		route["finished"] = false
		route["detail"] = []
	_room_time.clear()
	_last_summary = {}
	_room_entered_at = 0.0
	for h: Dictionary in _hazards.values():
		h["found"] = false
		h["time_to_flag_s"] = -1.0
	for z: Dictionary in _handrail_zones.values():
		z["transits"] = []
	log_event("session_started", {
		"participant_id": Settings.participant_id,
		"focus": current_focus.get("test", ""),
	})
	if not current_room.is_empty():
		log_event("room_entered", {"room": current_room})
	session_started.emit()
	scores_changed.emit()


## Forget the current scene's registrations before the house is reloaded for
## another session ("Go again"). The new scene re-registers everything.
func prepare_new_run() -> void:
	session_active = false
	session_finished = false
	_hazards.clear()
	_handrail_zones.clear()
	_rooms_occupied.clear()
	current_room = ""
	_last_summary = {}
	refresh_history_snapshot()


## Seconds since `start_session()`, used as the timestamp on every event.
func session_time() -> float:
	if not session_active:
		return 0.0
	return float(Time.get_ticks_msec() - _session_start_ms) / 1000.0


## Events are only recorded while a session is running; anything the
## participant does before START or after the debrief is not part of the run.
func log_event(type: String, data: Dictionary = {}) -> void:
	if not session_active:
		return
	var event := {"t": snappedf(session_time(), 0.01), "type": type}
	event.merge(data)
	_events.append(event)


# ---------------------------------------------------------------------------
#  Rooms -- driven by RoomZone (scripts/world/room_zone.gd)
# ---------------------------------------------------------------------------

func enter_room(room: String) -> void:
	_rooms_occupied.erase(room)
	_rooms_occupied.append(room)
	_set_current_room(room)


func exit_room(room: String) -> void:
	_rooms_occupied.erase(room)
	if current_room == room:
		_set_current_room(_rooms_occupied.back() if not _rooms_occupied.is_empty() else "")


func _set_current_room(room: String) -> void:
	if room == current_room:
		return
	_accumulate_room_time()
	current_room = room
	if not room.is_empty():
		log_event("room_entered", {"room": room})
	room_changed.emit(room)


func _accumulate_room_time() -> void:
	var now := session_time()
	if session_active and not current_room.is_empty():
		_room_time[current_room] = float(_room_time.get(current_room, 0.0)) + (now - _room_entered_at)
	_room_entered_at = now


func room_visited(room: String) -> bool:
	return _room_time.has(room) or (session_active and current_room == room)


# ---------------------------------------------------------------------------
#  Core System A -- hazard flagging
# ---------------------------------------------------------------------------

## Returns true if this was a new, correct find (caller plays the confirm cue).
func record_hazard_flag(hazard_id: String, hazard_name: String) -> bool:
	if not _hazards.has(hazard_id):
		return false
	var h: Dictionary = _hazards[hazard_id]
	if h["found"]:
		return false  # already flagged; no double credit
	h["found"] = true
	h["time_to_flag_s"] = snappedf(session_time(), 0.01)
	var room: String = h["room"]
	log_event("hazard_flagged", {"id": hazard_id, "name": hazard_name, "room": room})
	hazard_flagged.emit(hazard_id, hazard_name)
	hazard_progress_changed.emit(hazards_found(), hazards_total())
	scores_changed.emit()
	if room_hazards_found(room) == room_hazards_total(room):
		room_completed.emit(room)
	return true


## The user flagged something harmless. Recorded but NOT punished -- over-
## caution is a desirable behaviour in this population, so false positives are
## reported for the researcher rather than deducted from any score. Repeated
## flags of the same object are counted once.
func record_false_positive(object_name: String, room: String) -> void:
	if _false_positives.has(object_name):
		_false_positives[object_name]["count"] += 1
	else:
		_false_positives[object_name] = {
			"object": object_name,
			"room": room,
			"count": 1,
			"first_t": snappedf(session_time(), 0.01),
		}
	log_event("false_positive", {"object": object_name, "room": room})


func hazards_total() -> int:
	return _hazards.size()


func hazards_found() -> int:
	var n := 0
	for h: Dictionary in _hazards.values():
		if h["found"]:
			n += 1
	return n


func room_hazards_total(room: String) -> int:
	var n := 0
	for h: Dictionary in _hazards.values():
		if h["room"] == room:
			n += 1
	return n


func room_hazards_found(room: String) -> int:
	var n := 0
	for h: Dictionary in _hazards.values():
		if h["room"] == room and h["found"]:
			n += 1
	return n


func missed_hazards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Dictionary in _hazards.values():
		if not h["found"]:
			out.append(h)
	return out


# ---------------------------------------------------------------------------
#  Near misses -- SlipZone
# ---------------------------------------------------------------------------

func record_near_miss(zone_id: String, room: String, recognised: bool) -> void:
	if not session_active:
		return
	_near_misses.append({
		"zone": zone_id,
		"room": room,
		"recognised": recognised,
		"t": snappedf(session_time(), 0.01),
	})
	log_event("near_miss", {"zone": zone_id, "room": room, "hazard_already_flagged": recognised})
	scores_changed.emit()


# ---------------------------------------------------------------------------
#  Core System I -- walking a room without touching anything
# ---------------------------------------------------------------------------

## Called by each RoomRoute as it loads, so a room that has a route is scored on
## one even if the participant never walks it. Without this, skipping the route
## entirely would be indistinguishable from the room not having one, and the
## easiest way to score well would be to ignore the task.
func register_route(room: String, legs: int) -> void:
	if legs <= 0:
		return
	if _routes.has(room):
		var existing: Dictionary = _routes[room]
		existing["legs_total"] = legs
		return
	_routes[room] = {
		"legs_total": legs,
		"legs_done": 0,
		"legs_clean": 0,
		"started": false,
		"finished": false,
		"detail": [],
	}


func room_has_route(room: String) -> bool:
	return _routes.has(room)


func route_legs_total(room: String) -> int:
	if not _routes.has(room):
		return 0
	return int((_routes[room] as Dictionary).get("legs_total", 0))


func route_legs_done(room: String) -> int:
	if not _routes.has(room):
		return 0
	return int((_routes[room] as Dictionary).get("legs_done", 0))


func route_legs_clean(room: String) -> int:
	if not _routes.has(room):
		return 0
	return int((_routes[room] as Dictionary).get("legs_clean", 0))


func route_started(room: String) -> bool:
	if not _routes.has(room):
		return false
	return bool((_routes[room] as Dictionary).get("started", false))


## One stretch between two markers, judged. `detail` carries why it failed.
func record_route_leg(room: String, index: int, clean: bool, detail: Dictionary) -> void:
	if not session_active or not _routes.has(room):
		return
	var route: Dictionary = _routes[room]
	route["started"] = true
	route["legs_done"] = int(route["legs_done"]) + 1
	if clean:
		route["legs_clean"] = int(route["legs_clean"]) + 1
	var entry := {"leg": index, "clean": clean, "t": snappedf(session_time(), 0.01)}
	entry.merge(detail)
	(route["detail"] as Array).append(entry)
	log_event("route_leg", {"room": room, "leg": index, "clean": clean,
		"touched": detail.get("touched", false), "crossed": detail.get("crossed", [])})
	scores_changed.emit()


func record_route_complete(room: String, clean_legs: int, total_legs: int) -> void:
	if not _routes.has(room):
		return
	var route: Dictionary = _routes[room]
	route["finished"] = true
	log_event("route_complete", {"room": room, "clean": clean_legs, "legs": total_legs})
	scores_changed.emit()


## 0-100: the share of the room's legs crossed without touching or routing
## through a hazard. Legs never attempted count against it, which is what makes
## walking out half way different from walking it cleanly.
func route_score(room: String) -> float:
	var total := route_legs_total(room)
	if total <= 0:
		return 0.0
	return clampf(100.0 * float(route_legs_clean(room)) / float(total), 0.0, 100.0)


# ---------------------------------------------------------------------------
#  Core System H -- crossing the road
# ---------------------------------------------------------------------------

## One call per step into the road, from StreetCrossing.
func record_crossing(result: Dictionary) -> void:
	if not session_active:
		return
	_crossings.append(result)
	log_event("road_crossing", result)
	scores_changed.emit()


## "entry" records are one step off the kerb, scored by StreetCrossing.
## "run" records are a whole crossing, scored by CrossingPractice. They are
## averaged together into crossing quality, but the debrief has to be able to
## tell them apart -- a run record has no `used_crossing` key, and counting it
## as a missing one would report crossings away from the markings that never
## happened.
func _crossing_kind(record: Dictionary) -> String:
	return String(record.get("kind", "entry"))


func crossing_attempts(kind: String = "") -> int:
	if kind.is_empty():
		return _crossings.size()
	var n := 0
	for c: Dictionary in _crossings:
		if _crossing_kind(c) == kind:
			n += 1
	return n


## Mean quality of the crossings made, 0-100.
func crossing_quality_pct() -> float:
	if _crossings.is_empty():
		return 0.0
	var sum := 0.0
	for c: Dictionary in _crossings:
		sum += float(c.get("score", 0.0))
	return sum / float(_crossings.size())


func crossings_counted(key: String, kind: String = "") -> int:
	var n := 0
	for c: Dictionary in _crossings:
		if not kind.is_empty() and _crossing_kind(c) != kind:
			continue
		if c.get(key, false):
			n += 1
	return n


## Mean score of the completed crossing RUNS only, 0-100, or -1 if there are
## none. Reported separately in the debrief because it is a different skill
## from how the kerb was stepped off.
func crossing_run_pct() -> float:
	var runs := 0
	var sum := 0.0
	for c: Dictionary in _crossings:
		if _crossing_kind(c) != "run":
			continue
		runs += 1
		sum += float(c.get("score", 0.0))
	return -1.0 if runs == 0 else sum / float(runs)


## Mean score of the kerb ENTRIES only, 0-100, or -1 if there are none.
func crossing_entry_pct() -> float:
	var entries := 0
	var sum := 0.0
	for c: Dictionary in _crossings:
		if _crossing_kind(c) != "entry":
			continue
		entries += 1
		sum += float(c.get("score", 0.0))
	return -1.0 if entries == 0 else sum / float(entries)


## True once the crossing has been attempted at all, in either sense. Below
## this the test reports "not done this session" rather than nought, exactly as
## the balance exercise does when it is skipped.
func crossing_ran() -> bool:
	return not _crossings.is_empty()


## 0-100 for the road-crossing test. See the header comment for the formula.
func crossing_score() -> float:
	var acc := 0.0
	var weight := 0.0
	var runs := crossing_run_pct()
	if runs >= 0.0:
		acc += runs * CROSSING_WEIGHT_RUN
		weight += CROSSING_WEIGHT_RUN
	var entries := crossing_entry_pct()
	if entries >= 0.0:
		acc += entries * CROSSING_WEIGHT_ENTRY
		weight += CROSSING_WEIGHT_ENTRY
	if weight == 0.0:
		return 0.0
	return clampf(acc / weight, 0.0, 100.0)


## False for the tests that are not rooms, and so have no room to have been
## visited before they can show a score.
func is_room_test(test: String) -> bool:
	return test != "balance" and test != CROSSING_TEST


# ---------------------------------------------------------------------------
#  Core System B -- handrail / grab-bar compliance
# ---------------------------------------------------------------------------

## One call per crossing. Every crossing is kept (not just the last one), so
## "held on for X of Y crossings" really counts crossings.
func record_handrail_result(zone_id: String, complied: bool, grip_time_s: float, transit_time_s: float) -> void:
	if not session_active:
		return
	if not _handrail_zones.has(zone_id):
		push_warning("SessionManager: unknown handrail zone '%s'" % zone_id)
		return
	var z: Dictionary = _handrail_zones[zone_id]
	var transit := {
		"t": snappedf(session_time(), 0.01),
		"complied": complied,
		"grip_time_s": snappedf(grip_time_s, 0.01),
		"transit_time_s": snappedf(transit_time_s, 0.01),
	}
	(z["transits"] as Array).append(transit)
	log_event("handrail_transit", {
		"zone": zone_id, "room": z["room"], "complied": complied,
		"grip_time_s": transit["grip_time_s"], "transit_time_s": transit["transit_time_s"],
	})
	handrail_result.emit(zone_id, complied)
	scores_changed.emit()


## Number of crossings, optionally only those in `room`.
func handrail_opportunities(room: String = "") -> int:
	var n := 0
	for z: Dictionary in _handrail_zones.values():
		if room.is_empty() or z["room"] == room:
			n += (z["transits"] as Array).size()
	return n


func handrail_complied(room: String = "") -> int:
	var n := 0
	for z: Dictionary in _handrail_zones.values():
		if not room.is_empty() and z["room"] != room:
			continue
		for t: Dictionary in z["transits"]:
			if t["complied"]:
				n += 1
	return n


func handrail_compliance_pct(room: String = "") -> float:
	var opp := handrail_opportunities(room)
	if opp == 0:
		return 0.0
	return 100.0 * float(handrail_complied(room)) / float(opp)


# ---------------------------------------------------------------------------
#  Core System C -- balance exercise
# ---------------------------------------------------------------------------

## `trial` is produced by scripts/balance/balance_exercise.gd and contains at
## least: completed(bool), skipped(bool), completion_time_s,
## stability_score(0-100), max_sway_cm, mean_sway_cm, baseline(Array).
func record_balance_trial(trial: Dictionary) -> void:
	if not session_active:
		return
	_balance_trials.append(trial)
	log_event("balance_trial", trial)
	balance_trial_recorded.emit(trial)
	scores_changed.emit()


## Trials that count: everything except those skipped because there was no
## room to place the target.
func _balance_counted_trials() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in _balance_trials:
		if not t.get("skipped", false):
			out.append(t)
	return out


func _balance_completed_trials() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in _balance_counted_trials():
		if t.get("completed", false):
			out.append(t)
	return out


func balance_ran() -> bool:
	return not _balance_counted_trials().is_empty()


func balance_mean_time() -> float:
	var done := _balance_completed_trials()
	if done.is_empty():
		return 0.0
	var sum := 0.0
	for t: Dictionary in done:
		sum += float(t.get("completion_time_s", 0.0))
	return sum / float(done.size())


## Mean steadiness over COMPLETED reaches only. A trial that timed out
## (standing still, or a target that could not be reached) has near-zero head
## movement by construction; averaging it in would reward not reaching.
func balance_mean_stability() -> float:
	var done := _balance_completed_trials()
	if done.is_empty():
		return 0.0
	var sum := 0.0
	for t: Dictionary in done:
		sum += float(t.get("stability_score", 0.0))
	return sum / float(done.size())


func balance_completion_rate() -> float:
	var counted := _balance_counted_trials()
	if counted.is_empty():
		return 0.0
	return float(_balance_completed_trials().size()) / float(counted.size())


func balance_max_sway_cm() -> float:
	var worst := 0.0
	for t: Dictionary in _balance_completed_trials():
		worst = maxf(worst, float(t.get("max_sway_cm", 0.0)))
	return worst


# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

func hazard_score() -> float:
	if hazards_total() == 0:
		return 0.0
	return 100.0 * float(hazards_found()) / float(hazards_total())


## Balance test score: steadiness of the reaches you completed, scaled by the
## fraction you completed. Three steady reaches = high; one steady reach and
## two timeouts = one third of that.
func balance_score() -> float:
	return balance_mean_stability() * balance_completion_rate()


func overall_score() -> float:
	# Only include components that actually ran, then renormalise, so a session
	# that skipped the balance task is not scored as if it failed it.
	var total_weight := 0.0
	var acc := 0.0
	if hazards_total() > 0:
		acc += hazard_score() * WEIGHT_HAZARD
		total_weight += WEIGHT_HAZARD
	if handrail_opportunities() > 0:
		acc += handrail_compliance_pct() * WEIGHT_HANDRAIL
		total_weight += WEIGHT_HANDRAIL
	if balance_ran():
		acc += balance_score() * WEIGHT_BALANCE
		total_weight += WEIGHT_BALANCE
	if total_weight == 0.0:
		return 0.0
	return acc / total_weight


## Every room that has anything scorable, in display order (known rooms first,
## then any custom room a hazard was placed in).
func scored_rooms() -> Array[String]:
	var rooms: Array[String] = []
	for r in ROOM_ORDER:
		rooms.append(r)
	for h: Dictionary in _hazards.values():
		var room: String = h["room"]
		if not rooms.has(room):
			rooms.append(room)
	for z: Dictionary in _handrail_zones.values():
		var room: String = z["room"]
		if not rooms.has(room):
			rooms.append(room)
	var out: Array[String] = []
	for r in rooms:
		if room_hazards_total(r) > 0 or _room_has_zone(r) or r == STREET_ROOM:
			out.append(r)
	return out


func _room_has_zone(room: String) -> bool:
	for z: Dictionary in _handrail_zones.values():
		if z["room"] == room:
			return true
	return false


## Full breakdown for one room (the numbers behind its score).
func room_breakdown(room: String) -> Dictionary:
	var unrecognised := 0
	var total_near := 0
	for n: Dictionary in _near_misses:
		if n["room"] == room:
			total_near += 1
			if not n["recognised"]:
				unrecognised += 1
	var missed: Array = []
	for h: Dictionary in _hazards.values():
		if h["room"] == room and not h["found"]:
			missed.append(h["id"])
	var time_s := float(_room_time.get(room, 0.0))
	if session_active and current_room == room:
		time_s += session_time() - _room_entered_at
	return {
		"hazards_found": room_hazards_found(room),
		"hazards_total": room_hazards_total(room),
		"missed": missed,
		"rail_crossings": handrail_opportunities(room),
		"rail_complied": handrail_complied(room),
		"near_misses": total_near,
		"near_misses_unrecognised": unrecognised,
		"route_legs": route_legs_total(room),
		"route_legs_done": route_legs_done(room),
		"route_legs_clean": route_legs_clean(room),
		"route_score": snappedf(route_score(room), 0.1) if room_has_route(room) else 0.0,
		"crossings": crossing_attempts() if room == STREET_ROOM else 0,
		"crossing_quality_pct": snappedf(crossing_quality_pct(), 0.1) if room == STREET_ROOM else 0.0,
		"visited": room_visited(room),
		"time_s": snappedf(time_s, 0.1),
		"score": room_score(room),
	}


## 0-100 for one room. See the header comment for the formula.
func room_score(room: String) -> float:
	var acc := 0.0
	var weight := 0.0
	var hazard_weight := STREET_WEIGHT_HAZARD if room == STREET_ROOM else ROOM_WEIGHT_HAZARD
	var behaviour_weight := ROOM_WEIGHT_RAIL
	var total := room_hazards_total(room)
	if total > 0:
		acc += 100.0 * float(room_hazards_found(room)) / float(total) * hazard_weight
		weight += hazard_weight
	# The signalled crossing is deliberately NOT part of this score -- it is its
	# own test, see crossing_score(). Outdoors there is no rail either, so the
	# street room is hazards plus the footpath route and nothing else.
	if room != STREET_ROOM:
		if handrail_opportunities(room) > 0:
			acc += handrail_compliance_pct(room) * behaviour_weight
			weight += behaviour_weight
		elif _room_has_zone(room) and room_visited(room):
			# Visited a room with a rail but never crossed it (e.g. never climbed
			# the stairs): the rail habit was not shown, so that part scores 0.
			weight += behaviour_weight

	# Core System I: crossing the room without touching anything. A registered
	# route always carries its weight once the room has been visited, whether or
	# not it was walked -- see register_route().
	if room_has_route(room):
		var route_weight := STREET_WEIGHT_ROUTE if room == STREET_ROOM else ROOM_WEIGHT_ROUTE
		if route_legs_done(room) > 0:
			acc += route_score(room) * route_weight
			weight += route_weight
		elif room_visited(room):
			weight += route_weight

	if weight == 0.0:
		return 0.0
	var penalty := 0.0
	for n: Dictionary in _near_misses:
		if n["room"] == room and not n["recognised"]:
			penalty += NEAR_MISS_PENALTY
	penalty = minf(penalty, NEAR_MISS_PENALTY_CAP)
	return clampf(acc / weight - penalty, 0.0, 100.0)


## Test name -> 0-100 score, or null if that test did not run this session.
func test_scores() -> Dictionary:
	var out := {}
	for room in scored_rooms():
		out[room] = snappedf(room_score(room), 0.1)
	out[CROSSING_TEST] = snappedf(crossing_score(), 0.1) if crossing_ran() else null
	out["balance"] = snappedf(balance_score(), 0.1) if balance_ran() else null
	return out


func test_display_name(test: String) -> String:
	return str(TEST_NAMES.get(test, test.capitalize()))


## Plain-language, actionable coaching lines. Deliberately short, second person,
## and tied to what the participant actually did -- never generic praise.
func build_tips() -> Array[String]:
	var tips: Array[String] = []

	for h: Dictionary in missed_hazards():
		var room := test_display_name(str(h["room"]))
		tips.append("%s: you missed the %s. %s" % [
			room, str(h["name"]).to_lower(), _advice_for(str(h["id"]))
		])

	for room in scored_rooms():
		var crossings := handrail_opportunities(room)
		var missed_rail := crossings - handrail_complied(room)
		if crossings > 0 and missed_rail > 0:
			if room == "staircase":
				tips.append("Stairs: you crossed %d of %d time(s) without holding the rail. Take the rail every time, even for one step." % [missed_rail, crossings])
			else:
				tips.append("%s: you let go of the grab bar on %d of %d crossing(s). Keep hold until you are steady." % [test_display_name(room), missed_rail, crossings])

	if crossing_attempts() > 0:
		# Entries only: a run record has none of these keys, and counting it as a
		# missing one would report mistakes that never happened.
		var crossings := crossing_attempts("entry")
		if crossings_counted("used_crossing", "entry") < crossings:
			tips.append("Road crossing: you stepped into the road away from the crossing %d time(s). The marked crossing is where drivers expect you." % (crossings - crossings_counted("used_crossing", "entry")))
		if crossings_counted("looked_both_ways", "entry") < crossings:
			tips.append("Road crossing: look right, then left, then right again before you step off the kerb -- every single time.")
		if crossings_counted("safe_gap", "entry") < crossings:
			tips.append("Road crossing: you began crossing with a car close by. Let it pass; there is no hurry worth a fall.")
		if crossings_counted("obeyed_signal", "entry") < crossings:
			tips.append("Road crossing: wait for the steady green man. A red man, or a flashing one, means do not start.")

		var runs := crossing_attempts("run")
		if runs > 0:
			if crossings_counted("completed", "run") < runs:
				tips.append("Road crossing: the lights changed back before you were across %d time(s). Set off as soon as the green man shows -- it is shorter than it looks." % (runs - crossings_counted("completed", "run")))
			var wandered := 0
			for c: Dictionary in _crossings:
				if _crossing_kind(c) == "run" and float(c.get("off_markings_s", 0.0)) > 0.7:
					wandered += 1
			if wandered > 0:
				tips.append("Road crossing: you drifted off the crossing markings. Drivers look for people between the lines, so stay inside them the whole way over.")

	var unrecognised := 0
	for n: Dictionary in _near_misses:
		if not n["recognised"]:
			unrecognised += 1
	if unrecognised > 0:
		tips.append("You stepped onto %d hazard(s) before noticing them. Scan the floor ahead before you move." % unrecognised)

	if balance_ran():
		var stab := balance_mean_stability()
		if balance_completion_rate() < 1.0:
			tips.append("Some targets were out of comfortable reach. That is fine -- only reach as far as feels safe.")
		if _balance_completed_trials().size() > 0:
			if stab < 60.0:
				tips.append("Your head moved a long way while reaching. Keep your feet still and reach only as far as is comfortable -- reaching past your balance point is a common cause of falls.")
			elif stab < 80.0:
				tips.append("Your balance was steady overall. Try to keep your weight over your feet as you reach.")

	if _false_positives.size() >= 2:
		tips.append("You flagged several safe objects. That is not a problem -- checking carefully is a good habit.")

	if tips.is_empty():
		tips.append("You found every hazard and used the rails throughout. Excellent session.")

	return tips


func _advice_for(hazard_id: String) -> String:
	# Room-specific coaching keyed off the hazard id defined in the room scenes.
	var advice := {
		"bathroom_wet_floor": "Dry the floor or wait before stepping on wet tile.",
		"bathroom_no_grab_bar": "A grab bar beside the tub gives you something solid to hold.",
		"stairs_missing_rail": "Report a broken rail before using the stairs.",
		"stairs_dim_light": "Turn the light on before you use the stairs.",
		"stairs_uneven_step": "Look at each step; an uneven one is easy to catch a toe on.",
		"hall_rug_edge": "Tape down or remove rugs with curling edges.",
		"hall_extension_cord": "Route cords along the wall, never across a walkway.",
		"bed_dim_light": "Keep a lamp within reach of the bed.",
		"bed_armless_chair": "Choose a chair with armrests so you can push up safely.",
		"bed_floor_clutter": "Keep the path from bed to door completely clear.",
		"living_low_sofa": "Raise a low seat on firm blocks, or use a chair with arms.",
		"living_coffee_table": "Move low furniture out of the route you walk most.",
		"living_trailing_flex": "Run leads around the skirting, never across the floor.",
		"living_footstool": "Put the footstool back beside the chair after using it.",
		"kitchen_high_shelf": "Keep everyday things between hip and shoulder height.",
		"kitchen_step_stool": "Use a steady step with a handle, and never a chair.",
		"kitchen_wet_floor": "Wipe up spills the moment they happen.",
		"kitchen_open_door": "Close each cupboard door as you finish with it.",
		"bathroom_bath_mat": "Use a bath mat with a rubber backing, or fix it down.",
	}
	return str(advice.get(hazard_id, "Check this area again next time."))


# ---------------------------------------------------------------------------
#  Adaptive focus
# ---------------------------------------------------------------------------

## Per-test scores of a stored session. Schema-1 sessions (before per-room
## scoring existed) are converted from their hazard detail and balance block
## so older history still counts.
func tests_of_session(session: Dictionary) -> Dictionary:
	if session.has("tests"):
		return session["tests"]
	var out := {}
	var per_room := {}
	for h: Dictionary in session.get("hazards", {}).get("detail", []):
		var room := str(h.get("room", ""))
		if room.is_empty():
			continue
		if not per_room.has(room):
			per_room[room] = [0, 0]
		per_room[room][1] += 1
		if h.get("found", false):
			per_room[room][0] += 1
	for room: String in per_room.keys():
		var pair: Array = per_room[room]
		out[room] = snappedf(100.0 * float(pair[0]) / float(maxi(int(pair[1]), 1)), 0.1)
	var balance: Dictionary = session.get("balance", {})
	out["balance"] = balance.get("mean_stability", null) if int(balance.get("trials", 0)) > 0 else null
	return out


## Sessions in the log that belong to `participant`, oldest first.
func sessions_for(participant: String, doc: Dictionary = {}) -> Array:
	if doc.is_empty():
		doc = load_log()
	var out: Array = []
	for s: Dictionary in doc.get("sessions", []):
		if str(s.get("participant_id", "")) == participant:
			out.append(s)
	return out


## Pick the test the participant most needs to practise.
##   extra_session -- a session not yet written to disk (used at session end so
##                    the "next time" focus includes the session just played).
## Returns {} fields:
##   test        "" when there is nothing to focus on
##   reason      "first_session" | "all_above_threshold" | "lowest_average"
##   name, average, averages{test: avg}, sessions_considered,
##   missed[] (hazard names missed there last time), hints[]
func compute_focus(extra_session: Dictionary = {}) -> Dictionary:
	var sessions := sessions_for(Settings.participant_id)
	if not extra_session.is_empty():
		sessions.append(extra_session)
	if sessions.is_empty():
		return {"test": "", "reason": "first_session", "averages": {}}

	var recent: Array = sessions.slice(maxi(0, sessions.size() - FOCUS_WINDOW))
	var averages := {}
	var focus := ""
	var lowest := INF
	for test in _all_tests_in(recent):
		var sum := 0.0
		var count := 0
		for s: Dictionary in recent:
			var v: Variant = tests_of_session(s).get(test, null)
			if v != null:
				sum += float(v)
				count += 1
		if count == 0:
			continue
		var avg := sum / float(count)
		averages[test] = snappedf(avg, 0.1)
		if avg < lowest:
			lowest = avg
			focus = test

	var result := {
		"test": "",
		"averages": averages,
		"sessions_considered": recent.size(),
	}
	if focus.is_empty():
		result["reason"] = "first_session"
		return result
	if lowest >= FOCUS_THRESHOLD:
		result["reason"] = "all_above_threshold"
		return result

	result["test"] = focus
	result["reason"] = "lowest_average"
	result["name"] = test_display_name(focus)
	result["average"] = snappedf(lowest, 0.1)

	# What went wrong there most recently, to turn into hints.
	var latest: Dictionary = recent[recent.size() - 1]
	var missed_names: Array = []
	var hints: Array = []
	if focus == "balance":
		hints.append("Keep your feet still and reach only as far as is comfortable.")
		hints.append("Take your time. Steady matters more than fast.")
	elif focus == CROSSING_TEST:
		var crossing: Dictionary = latest.get("street", {})
		if int(crossing.get("runs", 0)) > int(crossing.get("runs_completed", 0)):
			hints.append("Press the button, wait for the steady green man, then walk straight across without stopping.")
		if int(crossing.get("entries", 0)) > int(crossing.get("obeyed_signal", 0)):
			hints.append("A red man, or a flashing one, means do not start. Wait for the next green.")
		if int(crossing.get("entries", 0)) > int(crossing.get("used_crossing", 0)):
			hints.append("Cross at the markings, even if it means a few extra steps.")
		if hints.is_empty():
			hints.append("Stay between the white lines all the way to the far kerb.")
	elif focus == STREET_ROOM:
		hints.append("Take the footpath slowly and look at the ground a few steps ahead of you.")
		for h: Dictionary in latest.get("hazards", {}).get("detail", []):
			if str(h.get("room", "")) == focus and not h.get("found", false):
				missed_names.append(str(h.get("name", h.get("id", ""))))
				var street_hint := str(HINTS.get(str(h.get("id", "")), ""))
				if not street_hint.is_empty():
					hints.append(street_hint)
	else:
		for h: Dictionary in latest.get("hazards", {}).get("detail", []):
			if str(h.get("room", "")) == focus and not h.get("found", false):
				missed_names.append(str(h.get("name", h.get("id", ""))))
				var hint := str(HINTS.get(str(h.get("id", "")), ""))
				if not hint.is_empty():
					hints.append(hint)
		var room_detail: Dictionary = latest.get("rooms", {}).get(focus, {})
		if int(room_detail.get("rail_crossings", 0)) > int(room_detail.get("rail_complied", 0)) \
				or (focus == "staircase" and int(room_detail.get("rail_crossings", 0)) == 0):
			hints.append("Hold the rail for every step, up and down.")
		if int(room_detail.get("near_misses_unrecognised", 0)) > 0:
			hints.append("Stop at the doorway and look before you step in.")
	result["missed"] = missed_names
	result["hints"] = hints
	return result


func _all_tests_in(sessions: Array) -> Array[String]:
	var tests: Array[String] = []
	for t in TEST_ORDER:
		tests.append(t)
	for s: Dictionary in sessions:
		for t: String in tests_of_session(s).keys():
			if not tests.has(t):
				tests.append(t)
	return tests


## Rows for the performance board, one per test, in display order.
##   {test, name, last (float|null), today (float|null), change (float|null),
##    average (float|null), is_focus}
func board_rows() -> Array[Dictionary]:
	var today := test_scores() if (session_active or session_finished) else {}
	var tests: Array[String] = []
	for t in TEST_ORDER:
		tests.append(t)
	for t: String in today.keys():
		if not tests.has(t):
			tests.append(t)
	var averages: Dictionary = current_focus.get("averages", {})
	var rows: Array[Dictionary] = []
	for test in tests:
		var last: Variant = baseline_tests.get(test, null)
		var now: Variant = today.get(test, null)
		# Rooms show a live score from the moment the participant walks in.
		if now != null and is_room_test(test) and not room_visited(test) and not session_finished:
			now = null
		var change: Variant = null
		if last != null and now != null:
			change = snappedf(float(now) - float(last), 0.1)
		rows.append({
			"test": test,
			"name": test_display_name(test),
			"last": last,
			"today": now,
			"change": change,
			"average": averages.get(test, null),
			"is_focus": current_focus.get("test", "") == test,
		})
	return rows


# ---------------------------------------------------------------------------
#  Summary + persistence
# ---------------------------------------------------------------------------

## The summary of the session that just ended ({} before the first one ends).
func get_last_summary() -> Dictionary:
	return _last_summary


func build_summary() -> Dictionary:
	_accumulate_room_time()
	var hazard_detail: Array = []
	for h: Dictionary in _hazards.values():
		hazard_detail.append(h.duplicate())
	var rail_detail: Array = []
	for z: Dictionary in _handrail_zones.values():
		var d: Dictionary = z.duplicate(true)
		d["attempted"] = (z["transits"] as Array).size() > 0
		rail_detail.append(d)
	var rooms := {}
	for room in scored_rooms():
		rooms[room] = room_breakdown(room)

	var player := get_tree().get_first_node_in_group("xr_player")
	var xr_active: bool = player != null and bool(player.get("xr_active"))

	return {
		"session_id": _session_id,
		"participant_id": Settings.participant_id,
		"started_utc": _started_utc,
		"duration_seconds": snappedf(session_time(), 0.01),
		"settings": {
			"xr_active": xr_active,
			"seated_mode": Settings.seated_mode,
			"standing_eye_height": Settings.standing_eye_height,
			"comfort_vignette": Settings.comfort_vignette,
			"night_mode": Settings.night_mode,
			"spoken_instructions": Settings.spoken_instructions,
			"text_scale": Settings.text_scale,
		},
		"focus": {
			"test": current_focus.get("test", ""),
			"reason": current_focus.get("reason", ""),
		},
		"hazards": {
			"total": hazards_total(),
			"found": hazards_found(),
			"accuracy_pct": snappedf(hazard_score(), 0.1),
			"false_positives": _false_positives.size(),
			"false_positive_detail": _false_positives.values(),
			"detail": hazard_detail,
		},
		"handrail": {
			"opportunities": handrail_opportunities(),
			"complied": handrail_complied(),
			"compliance_pct": snappedf(handrail_compliance_pct(), 0.1),
			"detail": rail_detail,
		},
		"near_misses": _near_misses.duplicate(),
		"routes": _routes.duplicate(true),
		"street": {
			"crossings": crossing_attempts(),
			"entries": crossing_attempts("entry"),
			"used_crossing": crossings_counted("used_crossing", "entry"),
			"looked_both_ways": crossings_counted("looked_both_ways", "entry"),
			"safe_gap": crossings_counted("safe_gap", "entry"),
			"obeyed_signal": crossings_counted("obeyed_signal", "entry"),
			"runs": crossing_attempts("run"),
			"runs_completed": crossings_counted("completed", "run"),
			"run_quality_pct": snappedf(crossing_run_pct(), 0.1),
			"quality_pct": snappedf(crossing_quality_pct(), 0.1),
			"detail": _crossings.duplicate(),
		},
		"balance": {
			"trials": _balance_counted_trials().size(),
			"completed": _balance_completed_trials().size(),
			"skipped": _balance_trials.size() - _balance_counted_trials().size(),
			"mean_completion_s": snappedf(balance_mean_time(), 0.01),
			"mean_stability": snappedf(balance_mean_stability(), 0.1),
			"max_sway_cm": snappedf(balance_max_sway_cm(), 0.1),
			"detail": _balance_trials.duplicate(),
		},
		"rooms": rooms,
		"tests": test_scores(),
		"score": {
			"hazard": snappedf(hazard_score(), 0.1),
			"handrail": snappedf(handrail_compliance_pct(), 0.1),
			"balance": snappedf(balance_score(), 0.1),
			"overall": snappedf(overall_score(), 0.1),
		},
		"tips": build_tips(),
		"events": _events.duplicate(),
	}


## Close the session, append it to user://session_log.json, and return the
## summary (with a `delta` block comparing against the previous run and the
## `next_focus` the next session will use).
func end_session() -> Dictionary:
	if not session_active:
		return _last_summary
	log_event("session_ended", {})
	var summary := build_summary()
	var previous := get_previous_session()
	summary["delta"] = _compute_delta(summary, previous)
	summary["next_focus"] = compute_focus(summary)
	session_active = false
	session_finished = true
	_last_summary = summary

	_append_to_log(summary)
	print("[SessionManager] Session written to %s (%s)" % [LOG_PATH, OS.get_user_data_dir()])
	session_ended.emit(summary)
	scores_changed.emit()
	return summary


func _append_to_log(summary: Dictionary) -> void:
	var doc := load_log()
	var sessions: Array = doc.get("sessions", [])
	sessions.append(summary)
	doc["schema_version"] = SCHEMA_VERSION
	doc["participant_id"] = Settings.participant_id
	doc["sessions"] = sessions
	_write_log_atomically(doc)


## Write to a temporary file first and then rename it over the real log, so a
## crash or power cut mid-write can never leave a half-written (and therefore
## unreadable) session history behind.
func _write_log_atomically(doc: Dictionary) -> void:
	var tmp_path := LOG_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SessionManager: cannot write %s (error %d)" % [tmp_path, FileAccess.get_open_error()])
		return
	# `\t` indent keeps the file human-readable for a researcher opening it in a
	# text editor; it is still valid JSON for pandas / R.
	file.store_string(JSON.stringify(doc, "\t"))
	file.close()

	var abs_tmp := ProjectSettings.globalize_path(tmp_path)
	var abs_log := ProjectSettings.globalize_path(LOG_PATH)
	var err := DirAccess.rename_absolute(abs_tmp, abs_log)
	if err != OK:
		# Some platforms refuse to rename over an existing file.
		DirAccess.remove_absolute(abs_log)
		err = DirAccess.rename_absolute(abs_tmp, abs_log)
	if err != OK:
		push_error("SessionManager: could not move %s into place (error %d). The session is kept in %s." % [tmp_path, err, tmp_path])


## Read the whole log. Returns an empty document on first run or parse failure
## (a corrupt log must never crash a session that is already in progress).
## A corrupt file is COPIED ASIDE before anything overwrites it, so a damaged
## history can still be recovered by hand.
func load_log() -> Dictionary:
	var empty := {"schema_version": SCHEMA_VERSION, "sessions": []}
	if not FileAccess.file_exists(LOG_PATH):
		return empty
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return empty
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_back_up_corrupt_log()
		return empty
	var doc: Dictionary = parsed
	if not doc.has("sessions") or typeof(doc["sessions"]) != TYPE_ARRAY:
		doc["sessions"] = []
	return doc


func _back_up_corrupt_log() -> void:
	if _corrupt_log_backed_up:
		return
	_corrupt_log_backed_up = true
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	var backup := "user://session_log.corrupt-%s.json" % stamp
	var err := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(LOG_PATH), ProjectSettings.globalize_path(backup)
	)
	push_warning("SessionManager: session_log.json unreadable. Copied it to %s (error %d) and starting a fresh log." % [backup, err])


## The most recent completed session of the CURRENT participant, or {}.
func get_previous_session() -> Dictionary:
	var sessions := sessions_for(Settings.participant_id)
	if sessions.is_empty():
		return {}
	return sessions[sessions.size() - 1]


func session_count() -> int:
	return sessions_for(Settings.participant_id).size()


## Erase this participant's saved sessions. Returns how many went.
##
## Everything the performance board shows -- "last time", the change column, the
## averages -- and everything the adaptive focus reads comes from these, so this
## is what "reset the scores" means. The session in progress, if there is one,
## is left alone: it has not been written yet, and stopping it is the Finish
## button's job, not this one's.
##
## PARTICIPANT-SCOPED, deliberately. A researcher's other participants are not
## the thing being reset, and there is no undo to fall back on here. The file is
## rewritten rather than deleted so a half-written log can never be left behind,
## and it goes through the same atomic write as a finished session.
func clear_history() -> int:
	var doc := load_log()
	var kept: Array = []
	var removed := 0
	for entry: Dictionary in doc.get("sessions", []):
		if str(entry.get("participant_id", "")) == Settings.participant_id:
			removed += 1
		else:
			kept.append(entry)
	if removed == 0:
		return 0
	doc["schema_version"] = SCHEMA_VERSION
	doc["sessions"] = kept
	_write_log_atomically(doc)
	# The board and the focus are both computed from the log, so they have to be
	# recomputed from the empty one rather than left showing what was there.
	_last_summary = {}
	refresh_history_snapshot()
	log_event("history_cleared", {"participant": Settings.participant_id,
		"sessions_removed": removed})
	scores_changed.emit()
	return removed


## Compare only components that ran in BOTH sessions; a component that was
## skipped last time is reported as "new" (null) rather than as a huge gain.
func _compute_delta(current: Dictionary, previous: Dictionary) -> Dictionary:
	if previous.is_empty():
		return {"has_previous": false}
	var cs: Dictionary = current.get("score", {})
	var ps: Dictionary = previous.get("score", {})
	var delta := {
		"has_previous": true,
		"previous_session_id": previous.get("session_id", ""),
		"hazard": _diff(cs, ps, "hazard", true, true),
		"handrail": _diff(cs, ps, "handrail",
			int(current.get("handrail", {}).get("opportunities", 0)) > 0,
			int(previous.get("handrail", {}).get("opportunities", 0)) > 0),
		"balance": _diff(cs, ps, "balance",
			int(current.get("balance", {}).get("trials", 0)) > 0,
			int(previous.get("balance", {}).get("trials", 0)) > 0),
		"overall": _diff(cs, ps, "overall", true, true),
	}
	var tests := {}
	var ct: Dictionary = current.get("tests", {})
	var pt := tests_of_session(previous)
	for t: String in ct.keys():
		if ct[t] != null and pt.get(t, null) != null:
			tests[t] = snappedf(float(ct[t]) - float(pt[t]), 0.1)
	delta["tests"] = tests
	return delta


func _diff(cs: Dictionary, ps: Dictionary, key: String, ran_now: bool, ran_before: bool) -> Variant:
	if not ran_now or not ran_before:
		return null
	return snappedf(float(cs.get(key, 0.0)) - float(ps.get(key, 0.0)), 0.1)
