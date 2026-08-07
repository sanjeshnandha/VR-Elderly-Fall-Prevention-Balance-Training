class_name SeatedMode
extends Node
## Architectural Fix 5.2 -- seated-mode camera height calibration.
##
## THE PROBLEM
## -----------
## Seated mode is not a rendering option, it is a *geometry* option. The moment
## the participant sits down, the headset drops roughly 0.4-0.6 m (more if they
## move from standing to a low armchair). The virtual world does not move with
## them, so the kitchen counter, the bath rim and -- critically -- the stair
## handrail are all suddenly at chin height. Reaching up and out is the exact
## shoulder posture that causes impingement pain in older adults, and it makes
## the handrail task physically unpleasant for the users who most need to sit
## down for it.
##
## THE FIX
## -------
## Raise the XROrigin3D by the difference between the participant's *standing*
## virtual eye height and their *measured seated* head height. The virtual body
## keeps standing; only the real person sits. Counters and rails stay exactly
## where a standing user would find them.
##
## Calibration is measured, not assumed: we sample the actual headset height
## over a second while the participant sits still, because "seated head height"
## varies by 25 cm across a realistic cohort (wheelchair vs. dining chair vs.
## high stool).
##
## godot-xr-tools: if `XRToolsPlayerBody` is present as a sibling, its
## `player_calibrate_height` property is driven with the same offset so the
## addon's collision capsule and step logic stay consistent with the visuals.
## Detection is by duck-typing, so this file has no hard dependency on the addon.

signal calibration_started
signal calibration_finished(offset: float)

## Seconds of "sit still and look ahead" before sampling begins.
@export var settle_seconds: float = 3.0

## Seconds of headset height averaged to get the seated head height.
@export var sample_seconds: float = 1.0

## Guard rails on the computed offset. A participant leaning forward to tie a
## shoe during calibration must not launch the virtual body two metres up.
@export var max_offset: float = 1.20
@export var min_offset: float = 0.0

var current_offset: float = 0.0

var _player: XRPlayer
var _camera: XRCamera3D
var _base_y: float = 0.0
var _samples: Array[float] = []
var _calibrating: bool = false
var _phase_timer: float = 0.0
var _sampling: bool = false
var _xr_tools_body: Node = null


func _ready() -> void:
	_player = get_parent() as XRPlayer
	if _player == null:
		push_error("SeatedMode must be a child of the XRPlayer (XROrigin3D).")
		set_process(false)
		return
	_camera = _player.camera
	_base_y = _player.position.y
	_xr_tools_body = _find_xr_tools_player_body()

	Settings.settings_changed.connect(_on_settings_changed)
	# Apply whatever was saved from a previous session, without re-measuring.
	if Settings.seated_mode:
		_apply_offset(current_offset)
	set_process(false)


func _on_settings_changed() -> void:
	if Settings.seated_mode and current_offset == 0.0:
		start_calibration()
	elif not Settings.seated_mode:
		reset_to_standing()


# ---------------------------------------------------------------------------
#  Calibration
# ---------------------------------------------------------------------------

## Begin the sit-still-and-measure routine. Safe to call again at any time --
## a participant who shifts to a different chair mid-session should re-run it.
func start_calibration() -> void:
	if _camera == null:
		_camera = _player.camera
	if _camera == null:
		push_warning("SeatedMode: no camera; cannot calibrate.")
		return

	_calibrating = true
	_sampling = false
	_phase_timer = 0.0
	_samples.clear()
	set_process(true)

	AudioCues.play("countdown")
	AudioCues.speak_text(
		"Sit back comfortably and look straight ahead. Hold still while I set your height."
	)
	SessionManager.log_event("seated_calibration_started", {})
	calibration_started.emit()


func _process(delta: float) -> void:
	if not _calibrating:
		return
	_phase_timer += delta

	if not _sampling:
		if _phase_timer >= settle_seconds:
			_sampling = true
			_phase_timer = 0.0
			AudioCues.play("go")
		return

	# Camera transform is local to the origin, so this is the raw physical
	# headset height above the play-space floor -- unaffected by any offset we
	# have already applied.
	_samples.append(_camera.transform.origin.y)

	if _phase_timer >= sample_seconds:
		_finish_calibration()


func _finish_calibration() -> void:
	_calibrating = false
	_sampling = false
	set_process(false)

	if _samples.is_empty():
		push_warning("SeatedMode: no height samples captured.")
		return

	# Median, not mean: one frame of tracking loss (which reports y = 0) would
	# drag a mean down by tens of centimetres.
	_samples.sort()
	var seated_head_height: float = _samples[_samples.size() / 2]

	var offset := clampf(
		Settings.standing_eye_height - seated_head_height, min_offset, max_offset
	)
	_apply_offset(offset)

	SessionManager.log_event("seated_calibration_finished", {
		"seated_head_height_m": snappedf(seated_head_height, 0.001),
		"standing_eye_height_m": Settings.standing_eye_height,
		"applied_offset_m": snappedf(offset, 0.001),
	})
	AudioCues.play("success")
	AudioCues.speak_text("Height set. Everything is now within easy reach.")
	calibration_finished.emit(offset)


func _apply_offset(offset: float) -> void:
	current_offset = offset
	_player.position.y = _base_y + offset
	_push_to_xr_tools(offset)


## Return the rig to true standing geometry.
func reset_to_standing() -> void:
	_calibrating = false
	set_process(false)
	current_offset = 0.0
	_player.position.y = _base_y
	_push_to_xr_tools(0.0)
	SessionManager.log_event("seated_mode_off", {})


# ---------------------------------------------------------------------------
#  godot-xr-tools bridge (optional)
# ---------------------------------------------------------------------------

func _find_xr_tools_player_body() -> Node:
	for child in _player.get_children():
		# XRToolsPlayerBody exposes `player_calibrate_height`. Checking for the
		# property rather than the class name keeps this working across addon
		# versions and avoids a parse error when the addon is absent.
		if "player_calibrate_height" in child:
			return child
	return null


func _push_to_xr_tools(offset: float) -> void:
	if _xr_tools_body == null:
		return
	# XRToolsPlayerBody uses this to keep its collision capsule and step-up
	# logic aligned with the visual eye height.
	_xr_tools_body.set("player_calibrate_height", offset)
	if _xr_tools_body.has_method("calibrate_player_height"):
		_xr_tools_body.call("calibrate_player_height")
