class_name SessionDirector
extends Node
## Runs the session from end to end: welcome -> explore the house -> balance
## exercise -> debrief. Everything the participant is asked to do comes from
## here, so the script of the session is readable in one file.
##
## The director never grabs control away from the participant. There is no
## forced transition and no timer that moves them on; every stage advances
## either because they finished it or because they pressed a large physical
## button. Someone who needs ten minutes in the bathroom gets ten minutes.

enum Stage { WELCOME, EXPLORING, BALANCE, DEBRIEF }

@export var instruction_panel_path: NodePath
@export var debrief_panel_path: NodePath
@export var balance_exercise_path: NodePath

@export var begin_button_path: NodePath
@export var seated_button_path: NodePath
@export var repeat_button_path: NodePath
@export var balance_button_path: NodePath
@export var finish_button_path: NodePath

## Start the balance exercise automatically once every hazard has been found.
@export var auto_start_balance: bool = true

var stage: Stage = Stage.WELCOME

var _instruction_holder: ViewportPanel3D
var _debrief_holder: ViewportPanel3D
var _instructions: InstructionPanel
var _debrief: DebriefPanel
var _balance: BalanceExercise

var _begin_button: WallButton
var _seated_button: WallButton
var _repeat_button: WallButton
var _balance_button: WallButton
var _finish_button: WallButton

const WELCOME_BODY := """You are going to walk through a house and look for things that could cause a fall.

When you see one, point at it with your right hand and pull the trigger.

To move, hold the trigger on your left hand, aim the green line at the floor, and let go.

To hold a handrail, put your hand near it and squeeze the grip button.

Press the green START button when you are ready."""

const EXPLORING_BODY := """Look around each room. Point at anything that could cause a fall and pull the trigger.

On the stairs you must hold the rail. The next step will only light up while you are holding on.

There is no time limit. Take as long as you like."""

const BALANCE_BODY := """Stand or sit comfortably and look straight ahead.

I will count down from three. When I say go, a glowing ball will appear at arm's length.

Reach out and touch it. Move your feet if you need to -- do not stretch past your balance."""


func _ready() -> void:
	# Boot banner. If you see this in the Output panel, every script compiled and
	# the scene tree built successfully -- any problem after this point is
	# runtime, not a load failure.
	print("[SessionDirector] Scene loaded. %d hazards registered across the house."
		% SessionManager.hazards_total())

	_resolve_nodes()
	_connect_buttons()

	if _instructions != null:
		_instructions.show_step("Welcome", WELCOME_BODY, false)
	_set_stage_buttons()

	# Give the headset a moment to settle on the participant's head before the
	# first spoken line, or they will miss the beginning of it.
	await get_tree().create_timer(2.0).timeout
	AudioCues.speak_text(WELCOME_BODY)


func _resolve_nodes() -> void:
	_instruction_holder = get_node_or_null(instruction_panel_path) as ViewportPanel3D
	_debrief_holder = get_node_or_null(debrief_panel_path) as ViewportPanel3D
	_balance = get_node_or_null(balance_exercise_path) as BalanceExercise

	if _instruction_holder != null:
		_instructions = _instruction_holder.content as InstructionPanel
	if _debrief_holder != null:
		_debrief = _debrief_holder.content as DebriefPanel
		_debrief_holder.visible = false

	_begin_button = get_node_or_null(begin_button_path) as WallButton
	_seated_button = get_node_or_null(seated_button_path) as WallButton
	_repeat_button = get_node_or_null(repeat_button_path) as WallButton
	_balance_button = get_node_or_null(balance_button_path) as WallButton
	_finish_button = get_node_or_null(finish_button_path) as WallButton


func _connect_buttons() -> void:
	if _begin_button != null:
		_begin_button.pressed.connect(_on_begin)
	if _seated_button != null:
		_seated_button.pressed.connect(_on_toggle_seated)
		_refresh_seated_button()
	if _repeat_button != null:
		_repeat_button.pressed.connect(_on_repeat)
	if _balance_button != null:
		_balance_button.pressed.connect(_on_start_balance)
	if _finish_button != null:
		_finish_button.pressed.connect(_on_finish)

	SessionManager.hazard_progress_changed.connect(_on_hazard_progress)
	if _balance != null:
		_balance.exercise_finished.connect(_on_balance_finished)


# ---------------------------------------------------------------------------
#  Stage transitions
# ---------------------------------------------------------------------------

func _set_stage_buttons() -> void:
	if _begin_button != null:
		_begin_button.set_enabled(stage == Stage.WELCOME)
	if _seated_button != null:
		# Seated mode can be changed at any time except mid-balance-trial, where
		# re-calibrating would invalidate the captured baseline (Fix 5.5).
		_seated_button.set_enabled(stage != Stage.BALANCE)
	if _repeat_button != null:
		_repeat_button.set_enabled(stage != Stage.DEBRIEF)
	if _balance_button != null:
		_balance_button.set_enabled(stage == Stage.EXPLORING)
	if _finish_button != null:
		_finish_button.set_enabled(stage == Stage.DEBRIEF)


func _on_begin() -> void:
	if stage != Stage.WELCOME:
		return
	stage = Stage.EXPLORING
	SessionManager.start_session()
	if _instructions != null:
		_instructions.show_step("Look for hazards", EXPLORING_BODY)
	_set_stage_buttons()


func _on_toggle_seated() -> void:
	var now := not Settings.seated_mode
	Settings.set_option("seated_mode", now)
	_refresh_seated_button()
	# SeatedMode listens to Settings and runs its own measured calibration.


func _refresh_seated_button() -> void:
	if _seated_button == null:
		return
	_seated_button.set_label("Seated mode")
	_seated_button.set_sub_label("Currently: %s" % ("ON" if Settings.seated_mode else "OFF"))


func _on_repeat() -> void:
	match stage:
		Stage.WELCOME:
			AudioCues.speak_text(WELCOME_BODY)
		Stage.EXPLORING:
			AudioCues.speak_text(EXPLORING_BODY)
		Stage.BALANCE:
			AudioCues.speak_text(BALANCE_BODY)
		Stage.DEBRIEF:
			pass


func _on_hazard_progress(found: int, total: int) -> void:
	if stage != Stage.EXPLORING or _instructions == null:
		return
	_instructions.show_step(
		"Hazards found: %d of %d" % [found, total],
		EXPLORING_BODY,
		false
	)
	if auto_start_balance and total > 0 and found >= total:
		AudioCues.speak_text("You have found every hazard. Well done. Now for a short balance exercise.")
		await get_tree().create_timer(4.0).timeout
		_on_start_balance()


func _on_start_balance() -> void:
	if stage != Stage.EXPLORING or _balance == null:
		return
	stage = Stage.BALANCE
	_set_stage_buttons()
	if _instructions != null:
		_instructions.show_step("Balance exercise", BALANCE_BODY, false)
	_balance.begin()


func _on_balance_finished(_results: Array) -> void:
	_show_debrief()


func _show_debrief() -> void:
	stage = Stage.DEBRIEF
	_set_stage_buttons()

	var summary := SessionManager.end_session()
	if _debrief != null:
		_debrief.show_summary(summary)
	if _debrief_holder != null:
		_debrief_holder.visible = true
		# Put the panel wherever the participant happens to be standing, at the
		# lens focal distance, rather than making them walk to find it.
		_debrief_holder.place_in_front_of_player()
	if _instructions != null:
		_instructions.show_step("Finished", "Your results are on the panel in front of you.", false)


func _on_finish() -> void:
	AudioCues.speak("session_complete")
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


## Escape hatch for a researcher: end the session early from the debug keyboard.
func force_debrief() -> void:
	if stage == Stage.DEBRIEF:
		return
	if stage == Stage.BALANCE and _balance != null:
		_balance.set_physics_process(false)
	_show_debrief()
