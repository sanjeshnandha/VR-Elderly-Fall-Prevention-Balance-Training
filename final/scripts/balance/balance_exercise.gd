class_name BalanceExercise
extends Node3D
## Core System C -- the reach-and-touch balance task, with Architectural Fix 5.5.
##
## Modelled loosely on the clinical Functional Reach Test (Duncan et al., 1990):
## the participant stands or sits comfortably, reaches forward and to each side
## for a target at arm's length, and we observe how much their head travels
## while they do it. This is a demonstrable proxy for postural sway. It is NOT
## clinical-grade -- a headset is not a force plate -- and the debrief says so.
##
## ARCHITECTURAL FIX 5.5 -- BASELINE CALIBRATION
## ---------------------------------------------
## The naive implementation scores sway from the absolute XRCamera3D position.
## That is wrong in a way that silently destroys the data: a participant who
## begins the trial slouched and then straightens up scores a huge "sway" for
## doing exactly the right thing, while someone who starts leaning and stays
## leaning scores perfectly. World coordinates also encode where in the room
## they happen to be standing, which is not a balance measurement at all.
##
## So each trial:
##   1. runs a 3-second spoken countdown ("three... two... one...") which both
##      gives the participant time to settle AND tells them when measurement
##      starts, so they are never being scored without knowing it;
##   2. on "Go!", captures `XRCamera3D.global_position` into `_baseline`;
##   3. scores every subsequent frame as a DELTA from that captured Vector3.
##
## Sway is measured horizontally (XZ). Vertical head movement is the reach
## itself -- crouching or leaning down toward a low target is correct technique,
## not instability, and penalising it would teach the wrong thing.
##
## The participant is asked to keep their FEET STILL and reach only as far as
## is comfortable, because a step moves the head horizontally and is scored as
## sway. A reach they cannot make simply times out; timed-out reaches are NOT
## averaged into steadiness (standing still would otherwise score 100) -- they
## lower the balance test score through the completion rate instead.
##
## The target is placed where there is room for it: if a wall or furniture is
## in the way the reach is shortened, and if there is no room at all the
## participant is asked to turn towards open space. After MAX_PLACEMENT_TRIES
## the trial is recorded as "skipped" and does not count either way.

signal trial_started(index: int)
signal trial_finished(result: Dictionary)
signal exercise_finished(results: Array)

## Direction of each trial's target, as a yaw offset in degrees from the way the
## participant is facing at "Go!". Forward, then right, then left: the same
## three-direction sweep used in multi-directional reach testing.
@export var trial_yaw_offsets: Array[float] = [0.0, 45.0, -45.0]

## Horizontal distance from the head to the orb, in metres. 0.55 m is a
## comfortable arm's length that requires a slight lean but not a step.
@export var reach_distance: float = 0.55

## Orb height relative to the captured baseline head position, in metres.
@export var orb_height_offset: float = -0.15

## Countdown length in seconds -- Fix 5.5, step 1.
@export var countdown_seconds: float = 3.0

## Abandon a trial after this long and record it as incomplete.
@export var trial_timeout: float = 25.0

## Horizontal deviation, in metres, treated as "as much sway as we ever expect".
## A participant at or beyond this scores 0 for stability. 0.20 m of head travel
## while reaching is already a substantial loss of postural control.
@export var sway_tolerance: float = 0.20

@export var orb_path: NodePath = ^"BalanceOrb"

## Shortest reach worth measuring, in metres. Below this the trial is retried.
@export var min_reach_distance: float = 0.35

const MAX_PLACEMENT_TRIES := 2
## Space kept between the target and any wall or furniture behind it.
const PLACEMENT_MARGIN := 0.15

enum State { IDLE, COUNTDOWN, ACTIVE, DONE }

var state: State = State.IDLE
var results: Array[Dictionary] = []

var _orb: BalanceOrb
var _player: XRPlayer
var _camera: XRCamera3D
var _trial_index: int = -1
var _timer: float = 0.0
var _last_beep: int = -1

# --- Per-trial measurement state (all deltas from _baseline) ---------------
var _baseline: Vector3 = Vector3.ZERO
var _baseline_captured: bool = false
var _max_sway: float = 0.0
var _sway_sum: float = 0.0
var _sway_samples: int = 0
var _trial_start: float = 0.0
var _placement_tries: int = 0
var _aborted: bool = false
var _reach_used: float = 0.0


func _ready() -> void:
	_orb = get_node_or_null(orb_path) as BalanceOrb
	if _orb == null:
		push_error("BalanceExercise: no BalanceOrb at '%s'." % orb_path)
		return
	_orb.touched.connect(_on_orb_touched)
	_orb.set_armed(false)
	set_physics_process(false)


func _resolve_player() -> void:
	_player = get_tree().get_first_node_in_group("xr_player") as XRPlayer
	if _player != null:
		_camera = _player.camera


## Run the whole exercise: every entry in `trial_yaw_offsets`, in order.
func begin() -> void:
	if state != State.IDLE:
		return
	_resolve_player()
	if _camera == null:
		push_error("BalanceExercise: no XRCamera3D; cannot run.")
		return
	results.clear()
	_trial_index = -1
	_aborted = false
	state = State.COUNTDOWN  # blocks a second begin() while the intro plays
	AudioCues.speak("balance_intro")
	SessionManager.log_event("balance_exercise_started", {"trials": trial_yaw_offsets.size()})
	# Let the spoken introduction finish before the first countdown starts
	# (the countdown numbers interrupt speech, so starting early would cut it).
	await get_tree().create_timer(2.0).timeout
	await AudioCues.wait_for_speech(12.0)
	if _aborted:
		return
	_next_trial()


## Stop immediately (researcher escape hatch). Pending timers see `_aborted`
## and do nothing, so the exercise can never restart itself after the debrief.
func abort() -> void:
	_aborted = true
	state = State.DONE
	set_physics_process(false)
	if _orb != null:
		_orb.set_armed(false)


func _next_trial() -> void:
	_trial_index += 1
	if _trial_index >= trial_yaw_offsets.size():
		_finish()
		return

	state = State.COUNTDOWN
	_placement_tries = 0
	_start_countdown()
	trial_started.emit(_trial_index)


func _start_countdown() -> void:
	state = State.COUNTDOWN
	_timer = countdown_seconds
	_last_beep = -1
	_baseline_captured = false
	_orb.set_armed(false)
	set_physics_process(true)


func _finish() -> void:
	state = State.DONE
	set_physics_process(false)
	_orb.set_armed(false)
	AudioCues.speak("balance_done")
	SessionManager.log_event("balance_exercise_finished", {"trials": results.size()})
	exercise_finished.emit(results)


# ---------------------------------------------------------------------------
#  Per-frame
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_process_countdown(delta)
		State.ACTIVE:
			_process_active()


func _process_countdown(delta: float) -> void:
	_timer -= delta

	# One beep per remaining whole second: "three... two... one..."
	var remaining := int(ceilf(_timer))
	if remaining != _last_beep and remaining > 0:
		_last_beep = remaining
		AudioCues.play("countdown")
		AudioCues.speak_text(str(remaining), true)

	if _timer > 0.0:
		return

	_start_measurement()


## ARCHITECTURAL FIX 5.5, steps 2 and 3.
## Capture the baseline at the exact moment measurement begins, and place the
## orb relative to that baseline so the reach distance is the same for a tall
## standing participant and a short seated one.
func _start_measurement() -> void:
	_baseline = _camera.global_position
	_baseline_captured = true

	_max_sway = 0.0
	_sway_sum = 0.0
	_sway_samples = 0
	_trial_start = SessionManager.session_time()

	# Facing direction at "Go!", flattened to horizontal.
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var yaw := deg_to_rad(trial_yaw_offsets[_trial_index])
	var direction := forward.rotated(Vector3.UP, yaw)

	# Make sure the target is not inside a wall or a piece of furniture.
	var orb_height := Vector3(0.0, orb_height_offset, 0.0)
	var reach := minf(reach_distance, _clear_distance(_baseline + orb_height, direction) - PLACEMENT_MARGIN)
	if reach < min_reach_distance:
		_handle_blocked_target()
		return
	_reach_used = reach

	_orb.global_position = _baseline + direction * reach + orb_height
	_orb.set_armed(true)

	state = State.ACTIVE
	AudioCues.play("go")
	AudioCues.speak("balance_go")
	SessionManager.log_event("balance_trial_started", {
		"index": _trial_index,
		"yaw_offset_deg": trial_yaw_offsets[_trial_index],
		"baseline": _vec_to_array(_baseline),
	})


## Free horizontal distance from `from` along `direction`, up to reach + margin.
func _clear_distance(from: Vector3, direction: Vector3) -> float:
	var limit := reach_distance + PLACEMENT_MARGIN
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * limit)
	query.collision_mask = 1 << 0  # world geometry and solid furniture
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return limit
	return from.distance_to(hit["position"])


func _handle_blocked_target() -> void:
	_placement_tries += 1
	set_physics_process(false)
	state = State.IDLE
	SessionManager.log_event("balance_target_blocked", {
		"index": _trial_index, "attempt": _placement_tries,
	})
	if _placement_tries > MAX_PLACEMENT_TRIES:
		# No room here even after asking. Record it as skipped: it does not
		# count towards completion or steadiness.
		var result := _result_dict(false)
		result["skipped"] = true
		results.append(result)
		SessionManager.record_balance_trial(result)
		trial_finished.emit(result)
		AudioCues.speak_text("There is not enough room for that one. Let us move on.", true)
		await get_tree().create_timer(2.5).timeout
		if not _aborted:
			_next_trial()
		return
	AudioCues.speak_text("There is something in the way. Please turn to face an open space.", true)
	await get_tree().create_timer(3.5).timeout
	if not _aborted:
		_start_countdown()


func _process_active() -> void:
	# Deviation from the CAPTURED baseline, never from world coordinates.
	var delta_vector := _camera.global_position - _baseline
	# Horizontal only: reaching down is technique, not instability.
	var sway := Vector2(delta_vector.x, delta_vector.z).length()

	_max_sway = maxf(_max_sway, sway)
	_sway_sum += sway
	_sway_samples += 1

	if SessionManager.session_time() - _trial_start > trial_timeout:
		_record_trial(false)


func _on_orb_touched() -> void:
	if state != State.ACTIVE:
		return
	_record_trial(true)


func _record_trial(completed: bool) -> void:
	state = State.IDLE
	set_physics_process(false)
	# A touched orb stays visible (green) until the next countdown, so the
	# participant sees that it counted. A timed-out one disappears now.
	if not completed:
		_orb.set_armed(false)

	var result := _result_dict(completed)
	results.append(result)
	SessionManager.record_balance_trial(result)
	trial_finished.emit(result)

	if not completed:
		AudioCues.speak_text("That is fine, let us move on.")

	await get_tree().create_timer(2.0).timeout
	if not _aborted:
		_next_trial()


func _result_dict(completed: bool) -> Dictionary:
	var mean_sway := _sway_sum / maxf(float(_sway_samples), 1.0)
	var elapsed := SessionManager.session_time() - _trial_start
	return {
		"index": _trial_index,
		"yaw_offset_deg": trial_yaw_offsets[_trial_index],
		"completed": completed,
		"skipped": false,
		"reach_m": snappedf(_reach_used, 0.01),
		"completion_time_s": snappedf(elapsed, 0.01),
		"max_sway_cm": snappedf(_max_sway * 100.0, 0.1),
		"mean_sway_cm": snappedf(mean_sway * 100.0, 0.1),
		"stability_score": snappedf(_stability_score(mean_sway, _max_sway), 0.1),
		"baseline": _vec_to_array(_baseline),
		"seated_mode": Settings.seated_mode,
	}


## 100 = no measurable head travel, 0 = at or beyond `sway_tolerance`.
## Mean sway is weighted more heavily than peak sway: one momentary wobble
## matters less than being unsteady throughout the reach.
func _stability_score(mean_sway: float, max_sway: float) -> float:
	var weighted := mean_sway * 0.65 + max_sway * 0.35
	var normalised := clampf(weighted / maxf(sway_tolerance, 0.001), 0.0, 1.0)
	return 100.0 * (1.0 - normalised)


func _vec_to_array(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
