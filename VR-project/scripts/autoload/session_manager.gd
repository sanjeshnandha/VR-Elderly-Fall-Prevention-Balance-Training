extends Node
## Session recorder, scorer and JSON persistence -- Core System E.
##
## This is the data source for the whole project: everything a caregiver or
## researcher sees comes out of here, and everything the debrief panel shows is
## read back from the same structure that gets written to disk.
##
## FILE LAYOUT  (user://session_log.json)
## --------------------------------------
##   {
##     "schema_version": 1,
##     "participant_id": "P01",
##     "sessions": [ <session>, <session>, ... ]     # oldest first
##   }
##
## The file holds an ARRAY of sessions rather than one session, because the
## stated goal is measuring improvement *across* runs. `get_delta_vs_previous()`
## does the comparison and the debrief panel renders it.
##
## On Windows `user://` resolves to
##   %APPDATA%\Godot\app_userdata\VR Fall-Prevention Trainer\session_log.json
## Use `OS.get_user_data_dir()` (printed at session end) to find it.

const LOG_PATH := "user://session_log.json"
const SCHEMA_VERSION := 1

## Weightings used for the overall score. Hazard recognition is the primary
## training objective, so it carries the most weight.
const WEIGHT_HAZARD := 0.5
const WEIGHT_HANDRAIL := 0.3
const WEIGHT_BALANCE := 0.2

signal session_started
signal session_ended(summary: Dictionary)
signal hazard_flagged(hazard_id: String, hazard_name: String)
signal hazard_progress_changed(found: int, total: int)
signal handrail_result(zone_id: String, complied: bool)
signal balance_trial_recorded(trial: Dictionary)

# --- Live session state ----------------------------------------------------

var session_active: bool = false
var _session_start_ms: int = 0
var _session_id: String = ""

## hazard_id -> {id, name, room, is_hazard, found, time_to_flag_s}
var _hazards: Dictionary = {}
## zone_id -> {id, room, complied, grip_time_s, transit_time_s, attempted}
var _handrail_zones: Dictionary = {}
## Array of balance trial dictionaries.
var _balance_trials: Array[Dictionary] = []
## Chronological raw event log; the audit trail behind the aggregates.
var _events: Array[Dictionary] = []
## Objects the user flagged that were not hazards.
var _false_positives: Array[Dictionary] = []


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
		"attempted": false,
		"complied": false,
		"grip_time_s": 0.0,
		"transit_time_s": 0.0,
	}


# ---------------------------------------------------------------------------
#  Session lifecycle
# ---------------------------------------------------------------------------

func start_session() -> void:
	session_active = true
	_session_start_ms = Time.get_ticks_msec()
	_session_id = "%s-%04d" % [
		Time.get_datetime_string_from_system(true).replace(":", "").replace("-", ""),
		randi() % 10000,
	]
	_balance_trials.clear()
	_events.clear()
	_false_positives.clear()
	for h: Dictionary in _hazards.values():
		h["found"] = false
		h["time_to_flag_s"] = -1.0
	for z: Dictionary in _handrail_zones.values():
		z["attempted"] = false
		z["complied"] = false
		z["grip_time_s"] = 0.0
		z["transit_time_s"] = 0.0
	log_event("session_started", {"participant_id": Settings.participant_id})
	session_started.emit()


## Seconds since `start_session()`, used as the timestamp on every event.
func session_time() -> float:
	if not session_active:
		return 0.0
	return float(Time.get_ticks_msec() - _session_start_ms) / 1000.0


func log_event(type: String, data: Dictionary = {}) -> void:
	var event := {"t": snappedf(session_time(), 0.01), "type": type}
	event.merge(data)
	_events.append(event)


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
	log_event("hazard_flagged", {"id": hazard_id, "name": hazard_name, "room": h["room"]})
	hazard_flagged.emit(hazard_id, hazard_name)
	hazard_progress_changed.emit(hazards_found(), hazards_total())
	return true


## The user flagged something harmless. Recorded but NOT punished harshly --
## over-caution is a desirable behaviour in this population, so false positives
## are reported for the researcher rather than deducted from the score.
func record_false_positive(object_name: String, room: String) -> void:
	_false_positives.append({
		"object": object_name,
		"room": room,
		"t": snappedf(session_time(), 0.01),
	})
	log_event("false_positive", {"object": object_name, "room": room})


func hazards_total() -> int:
	return _hazards.size()


func hazards_found() -> int:
	var n := 0
	for h: Dictionary in _hazards.values():
		if h["found"]:
			n += 1
	return n


func missed_hazards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Dictionary in _hazards.values():
		if not h["found"]:
			out.append(h)
	return out


# ---------------------------------------------------------------------------
#  Core System B -- handrail / grab-bar compliance
# ---------------------------------------------------------------------------

func record_handrail_result(zone_id: String, complied: bool, grip_time_s: float, transit_time_s: float) -> void:
	if not _handrail_zones.has(zone_id):
		push_warning("SessionManager: unknown handrail zone '%s'" % zone_id)
		return
	var z: Dictionary = _handrail_zones[zone_id]
	z["attempted"] = true
	z["complied"] = complied
	z["grip_time_s"] = snappedf(grip_time_s, 0.01)
	z["transit_time_s"] = snappedf(transit_time_s, 0.01)
	log_event("handrail_transit", {
		"zone": zone_id, "room": z["room"], "complied": complied,
		"grip_time_s": z["grip_time_s"], "transit_time_s": z["transit_time_s"],
	})
	handrail_result.emit(zone_id, complied)


func handrail_opportunities() -> int:
	var n := 0
	for z: Dictionary in _handrail_zones.values():
		if z["attempted"]:
			n += 1
	return n


func handrail_complied() -> int:
	var n := 0
	for z: Dictionary in _handrail_zones.values():
		if z["attempted"] and z["complied"]:
			n += 1
	return n


func handrail_compliance_pct() -> float:
	var opp := handrail_opportunities()
	if opp == 0:
		return 0.0
	return 100.0 * float(handrail_complied()) / float(opp)


# ---------------------------------------------------------------------------
#  Core System C -- balance exercise
# ---------------------------------------------------------------------------

## `trial` is produced by scripts/balance/balance_exercise.gd and contains at
## least: completed(bool), completion_time_s, stability_score(0-100),
## max_sway_cm, mean_sway_cm, baseline(Vector3 as Array).
func record_balance_trial(trial: Dictionary) -> void:
	_balance_trials.append(trial)
	log_event("balance_trial", trial)
	balance_trial_recorded.emit(trial)


func balance_mean_time() -> float:
	var times: Array[float] = []
	for t: Dictionary in _balance_trials:
		if t.get("completed", false):
			times.append(float(t.get("completion_time_s", 0.0)))
	if times.is_empty():
		return 0.0
	var sum := 0.0
	for v in times:
		sum += v
	return sum / float(times.size())


func balance_mean_stability() -> float:
	if _balance_trials.is_empty():
		return 0.0
	var sum := 0.0
	for t: Dictionary in _balance_trials:
		sum += float(t.get("stability_score", 0.0))
	return sum / float(_balance_trials.size())


func balance_max_sway_cm() -> float:
	var worst := 0.0
	for t: Dictionary in _balance_trials:
		worst = maxf(worst, float(t.get("max_sway_cm", 0.0)))
	return worst


# ---------------------------------------------------------------------------
#  Scoring + tips
# ---------------------------------------------------------------------------

func hazard_score() -> float:
	if hazards_total() == 0:
		return 0.0
	return 100.0 * float(hazards_found()) / float(hazards_total())


func balance_score() -> float:
	return balance_mean_stability()


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
	if not _balance_trials.is_empty():
		acc += balance_score() * WEIGHT_BALANCE
		total_weight += WEIGHT_BALANCE
	if total_weight == 0.0:
		return 0.0
	return acc / total_weight


## Plain-language, actionable coaching lines. Deliberately short, second person,
## and tied to what the participant actually did -- never generic praise.
func build_tips() -> Array[String]:
	var tips: Array[String] = []

	for h: Dictionary in missed_hazards():
		var room: String = str(h["room"]).capitalize()
		tips.append("%s: you missed the %s. %s" % [
			room, str(h["name"]).to_lower(), _advice_for(str(h["id"]))
		])

	var pct := handrail_compliance_pct()
	if handrail_opportunities() > 0 and pct < 100.0:
		tips.append("You went up or down the stairs %d time(s) without holding the rail. Take the rail every time, even for one step." % (handrail_opportunities() - handrail_complied()))

	if not _balance_trials.is_empty():
		var stab := balance_mean_stability()
		if stab < 60.0:
			tips.append("You leaned a long way to reach the target. Move your feet instead of stretching -- reaching past your balance point is a common cause of falls.")
		elif stab < 80.0:
			tips.append("Your balance was steady overall. Try to keep your weight over your feet as you reach.")

	if _false_positives.size() > 3:
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
	}
	return str(advice.get(hazard_id, "Check this area again next time."))


# ---------------------------------------------------------------------------
#  Summary + persistence
# ---------------------------------------------------------------------------

func build_summary() -> Dictionary:
	var hazard_detail: Array = []
	for h: Dictionary in _hazards.values():
		hazard_detail.append(h.duplicate())
	var rail_detail: Array = []
	for z: Dictionary in _handrail_zones.values():
		rail_detail.append(z.duplicate())

	return {
		"session_id": _session_id,
		"participant_id": Settings.participant_id,
		"started_utc": Time.get_datetime_string_from_system(true),
		"duration_seconds": snappedf(session_time(), 0.01),
		"settings": {
			"seated_mode": Settings.seated_mode,
			"standing_eye_height": Settings.standing_eye_height,
			"comfort_vignette": Settings.comfort_vignette,
			"smooth_locomotion": Settings.smooth_locomotion,
			"spoken_instructions": Settings.spoken_instructions,
			"text_scale": Settings.text_scale,
		},
		"hazards": {
			"total": hazards_total(),
			"found": hazards_found(),
			"accuracy_pct": snappedf(hazard_score(), 0.1),
			"false_positives": _false_positives.size(),
			"detail": hazard_detail,
		},
		"handrail": {
			"opportunities": handrail_opportunities(),
			"complied": handrail_complied(),
			"compliance_pct": snappedf(handrail_compliance_pct(), 0.1),
			"detail": rail_detail,
		},
		"balance": {
			"trials": _balance_trials.size(),
			"mean_completion_s": snappedf(balance_mean_time(), 0.01),
			"mean_stability": snappedf(balance_mean_stability(), 0.1),
			"max_sway_cm": snappedf(balance_max_sway_cm(), 0.1),
			"detail": _balance_trials.duplicate(),
		},
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
## summary (with a `delta` block comparing against the previous run).
func end_session() -> Dictionary:
	if not session_active:
		return {}
	log_event("session_ended", {})
	var summary := build_summary()
	var previous := get_previous_session()
	summary["delta"] = _compute_delta(summary, previous)
	session_active = false

	_append_to_log(summary)
	print("[SessionManager] Session written to %s (%s)" % [LOG_PATH, OS.get_user_data_dir()])
	session_ended.emit(summary)
	return summary


func _append_to_log(summary: Dictionary) -> void:
	var doc := load_log()
	var sessions: Array = doc.get("sessions", [])
	sessions.append(summary)
	doc["schema_version"] = SCHEMA_VERSION
	doc["participant_id"] = Settings.participant_id
	doc["sessions"] = sessions

	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SessionManager: cannot write %s (error %d)" % [LOG_PATH, FileAccess.get_open_error()])
		return
	# `\t` indent keeps the file human-readable for a researcher opening it in a
	# text editor; it is still valid JSON for pandas / R.
	file.store_string(JSON.stringify(doc, "\t"))
	file.close()


## Read the whole log. Returns an empty document on first run or parse failure
## (a corrupt log must never crash a session that is already in progress).
func load_log() -> Dictionary:
	if not FileAccess.file_exists(LOG_PATH):
		return {"schema_version": SCHEMA_VERSION, "sessions": []}
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return {"schema_version": SCHEMA_VERSION, "sessions": []}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SessionManager: session_log.json unreadable; starting a fresh log.")
		return {"schema_version": SCHEMA_VERSION, "sessions": []}
	var doc: Dictionary = parsed
	if not doc.has("sessions"):
		doc["sessions"] = []
	return doc


## The most recently completed session, or {} if this is the first ever run.
func get_previous_session() -> Dictionary:
	var sessions: Array = load_log().get("sessions", [])
	if sessions.is_empty():
		return {}
	return sessions[sessions.size() - 1]


func session_count() -> int:
	return (load_log().get("sessions", []) as Array).size()


func _compute_delta(current: Dictionary, previous: Dictionary) -> Dictionary:
	if previous.is_empty():
		return {"has_previous": false}
	var cs: Dictionary = current.get("score", {})
	var ps: Dictionary = previous.get("score", {})
	return {
		"has_previous": true,
		"previous_session_id": previous.get("session_id", ""),
		"hazard": snappedf(float(cs.get("hazard", 0.0)) - float(ps.get("hazard", 0.0)), 0.1),
		"handrail": snappedf(float(cs.get("handrail", 0.0)) - float(ps.get("handrail", 0.0)), 0.1),
		"balance": snappedf(float(cs.get("balance", 0.0)) - float(ps.get("balance", 0.0)), 0.1),
		"overall": snappedf(float(cs.get("overall", 0.0)) - float(ps.get("overall", 0.0)), 0.1),
	}
