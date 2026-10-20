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
##
## ADAPTIVE FOCUS
## --------------
## Before the session, SessionManager works out which test (a room, or the
## balance exercise) has the lowest recent score. The director then:
##   * names it on the instruction panel and in the spoken welcome,
##   * lights a beacon at its doorway (FocusBeacon) so the participant starts
##     there,
##   * gives hints drawn from what was missed there last time when they walk
##     in (pointing at WHERE to look, not at the answer),
##   * marks it on the performance board, and tells them at the debrief which
##     test will be the focus next time.
## Nothing is locked or forced: the focus is a suggestion and every room still
## counts.

enum Stage { WELCOME, EXPLORING, BALANCE, DEBRIEF }

@export var instruction_panel_path: NodePath
@export var debrief_panel_path: NodePath
@export var balance_exercise_path: NodePath
@export var focus_beacon_path: NodePath

@export var begin_button_path: NodePath
@export var seated_button_path: NodePath
@export var repeat_button_path: NodePath
@export var skip_button_path: NodePath
@export var balance_button_path: NodePath
@export var again_button_path: NodePath
@export var finish_button_path: NodePath
@export var night_button_path: NodePath
@export var reset_button_path: NodePath

## Start the balance exercise automatically once every hazard has been found.
@export var auto_start_balance: bool = true

## Which way the participant is turned to face at the welcome (Godot yaw,
## 0 = -Z). 90 faces west, towards the instruction panel. In a headset the
## participant's physical facing is arbitrary, so the rig is turned for them.
@export var welcome_yaw_degrees: float = 90.0

var stage: Stage = Stage.WELCOME

var _instruction_holder: ViewportPanel3D
var _debrief_holder: ViewportPanel3D
var _instructions: InstructionPanel
var _debrief: DebriefPanel
var _balance: BalanceExercise
var _beacon: FocusBeacon

var _begin_button: WallButton
var _seated_button: WallButton
var _repeat_button: WallButton
var _skip_button: WallButton
var _balance_button: WallButton
var _again_button: WallButton
var _finish_button: WallButton
var _night_button: WallButton
var _reset_button: WallButton
## Seconds the reset button stays armed after the first press.
var _reset_armed: bool = false
var _reset_token: int = 0

var _focus: Dictionary = {}
var _focus_hint_given: bool = false
## Rooms whose guidance has already been spoken this session.
var _rooms_told: Dictionary = {}
## Set by the SKIP button: stop talking, and do not start the line that was
## about to play. Cleared at every stage change, so the next stage speaks
## normally and nobody is left in silence by one press.
var _skip_speech: bool = false
var _balance_auto_started: bool = false

const WELCOME_BODY := """You are going to walk through a house and look for things that could cause a fall.

When you see one, point at it with your right hand and pull the trigger.

To move, hold the trigger on your left hand, aim the green line at the floor, and let go.

To hold a handrail, put your hand near it and squeeze the grip button.

Your progress board is on the wall to your left. Press the green START button when you are ready."""

## The opening. DELIBERATELY GENERAL.
##
## This used to be the whole briefing: the rings, the stairs, the front door,
## the pavement and the crossing sequence, all of it, read out at the start and
## then left on the panel for the rest of the session. So a participant standing
## in the bathroom was being told about pedestrian signals, and the panel on the
## wall said the same thing in the bathroom as it did on the kerb.
##
## What belongs here is only what is true everywhere. Everything else moved into
## ROOM_GUIDES below, and is shown and spoken when the participant walks into
## the room it is about.
const EXPLORING_BODY := """Look around each room. Point at anything that could cause a fall and pull the trigger.

When you have had a look, green rings appear on the floor, one at a time. Stand on each one in turn. Getting there without touching anything is part of the exercise -- if the direct way is blocked, go round it.

I will tell you what to look for in each room as you come to it.

There is no time limit. Take as long as you like."""

## What to say in each room, said when the participant arrives in it.
##
## Two or three sentences. Enough to point at what the room is about, never a
## list of its hazards -- naming them would answer the question the room is
## asking.
const ROOM_GUIDES := {
	"hallway": {
		"title": "The hallway",
		"body": "Look along the floor as you come in: anything lying on it, and anything crossing it.",
	},
	"living_room": {
		"title": "The living room",
		"body": "Two things in here. How you would get out of each seat, and what is low enough to catch a foot. Anything you can see through is the easiest to miss.",
	},
	"kitchen": {
		"title": "The kitchen",
		"body": "Look at what is stored above shoulder height, and at what you would stand on to reach it. Then look at the floor, and at the cupboard doors.",
	},
	"bathroom": {
		"title": "The bathroom",
		"body": "Wet floor, something solid to hold, and whatever is lying on the tiles. Take your time in here. It is the smallest room and one of the most dangerous.",
	},
	"staircase": {
		"title": "The stairs",
		"body": "Hold the rail all the way up and down. The next step will only light up while you are holding on. Look at each tread as you come to it.",
	},
	"bedroom": {
		"title": "The bedroom",
		"body": "Picture getting up in the night. Is there enough light to see the floor, something firm to push yourself up from, and a clear path to the door?",
	},
	"street": {
		"title": "Outside",
		"body": "Two separate exercises out here, and each one is scored on its own. First walk down the path and along the pavement, ring by ring, keeping clear of what is on it -- and look up as well as down. Then, at the crossing, press the button on the pole and wait for the green man.",
	},
}

## How long the reset button stays armed after its first press.
const RESET_ARM_SECONDS := 6.0

const BALANCE_BODY := """Keep your feet where they are and look straight ahead.

I will count down from three. When I say go, a glowing ball will appear at arm's length.

Reach out and touch it, only as far as is comfortable. If you cannot reach it, that is fine -- just wait."""


func _ready() -> void:
	add_to_group("session_director")
	# Boot banner. If you see this in the Output panel, every script compiled and
	# the scene tree built successfully -- any problem after this point is
	# runtime, not a load failure.
	print("[SessionDirector] Scene loaded. %d hazards registered across the house."
		% SessionManager.hazards_total())

	_resolve_nodes()
	_connect_buttons()

	SessionManager.refresh_history_snapshot()
	_focus = SessionManager.current_focus
	print("[SessionDirector] Focus for this session: %s (%s)."
		% [_focus.get("test", "none"), _focus.get("reason", "")])

	if _instructions != null:
		_instructions.show_step("Welcome", WELCOME_BODY, false)
		_instructions.set_focus_line(_focus_line())
	if _beacon != null:
		_beacon.show_for_focus(_focus)
	_set_stage_buttons()

	_face_the_panel()

	# Give the headset a moment to settle on the participant's head before the
	# first spoken line, or they will miss the beginning of it.
	await get_tree().create_timer(2.0).timeout
	_speak_welcome()


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard twins of the two wall buttons a tester reaches for most.
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F10:
		# Researcher escape hatch (works in VR as well).
		force_debrief()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F9:
		# Same as the "Skip talking" button on the west wall.
		_on_skip()
		get_viewport().set_input_as_handled()


func _resolve_nodes() -> void:
	_instruction_holder = get_node_or_null(instruction_panel_path) as ViewportPanel3D
	_debrief_holder = get_node_or_null(debrief_panel_path) as ViewportPanel3D
	_balance = get_node_or_null(balance_exercise_path) as BalanceExercise
	_beacon = get_node_or_null(focus_beacon_path) as FocusBeacon

	if _instruction_holder != null:
		_instructions = _instruction_holder.content as InstructionPanel
	if _debrief_holder != null:
		_debrief = _debrief_holder.content as DebriefPanel
		_debrief_holder.visible = false

	_begin_button = get_node_or_null(begin_button_path) as WallButton
	_seated_button = get_node_or_null(seated_button_path) as WallButton
	_repeat_button = get_node_or_null(repeat_button_path) as WallButton
	_skip_button = get_node_or_null(skip_button_path) as WallButton
	_balance_button = get_node_or_null(balance_button_path) as WallButton
	_again_button = get_node_or_null(again_button_path) as WallButton
	_finish_button = get_node_or_null(finish_button_path) as WallButton
	_night_button = get_node_or_null(night_button_path) as WallButton
	_reset_button = get_node_or_null(reset_button_path) as WallButton


func _connect_buttons() -> void:
	if _begin_button != null:
		_begin_button.pressed.connect(_on_begin)
	if _seated_button != null:
		_seated_button.pressed.connect(_on_toggle_seated)
		_refresh_seated_button()
	if _repeat_button != null:
		_repeat_button.pressed.connect(_on_repeat)
	if _skip_button != null:
		_skip_button.pressed.connect(_on_skip)
	if _balance_button != null:
		_balance_button.pressed.connect(_on_start_balance)
	if _again_button != null:
		_again_button.pressed.connect(_on_again)
	if _finish_button != null:
		_finish_button.pressed.connect(_on_finish)
	if _night_button != null:
		_night_button.pressed.connect(_on_toggle_night)
		_refresh_night_button()
	if _reset_button != null:
		_reset_button.pressed.connect(_on_reset_scores)
		_disarm_reset()

	SessionManager.hazard_progress_changed.connect(_on_hazard_progress)
	SessionManager.room_changed.connect(_on_room_changed)
	SessionManager.room_completed.connect(_on_room_completed)
	if _balance != null:
		_balance.exercise_finished.connect(_on_balance_finished)


func _face_the_panel() -> void:
	var player := get_tree().get_first_node_in_group("xr_player") as XRPlayer
	if player == null:
		return
	# Wait for the headset to report a real pose before turning the rig.
	await get_tree().process_frame
	await get_tree().process_frame
	player.face_yaw(welcome_yaw_degrees)


# ---------------------------------------------------------------------------
#  Focus text
# ---------------------------------------------------------------------------

func _focus_test() -> String:
	return str(_focus.get("test", ""))


## "the bathroom", "the stairs", "the balance exercise"
func _focus_spoken_name() -> String:
	var test := _focus_test()
	if test == "balance":
		return "the balance exercise"
	return "the " + SessionManager.test_display_name(test).to_lower()


func _focus_line() -> String:
	match str(_focus.get("reason", "")):
		"lowest_average":
			return "Today's focus: %s (your lowest recent score, %d out of 100)" % [
				_focus.get("name", ""), int(round(float(_focus.get("average", 0.0))))]
		"all_above_threshold":
			return "No focus today -- you scored well everywhere. Explore freely."
	return ""


func _focus_sentence() -> String:
	match str(_focus.get("reason", "")):
		"lowest_average":
			if _focus_test() == "balance":
				return "Today's focus is the balance exercise. When you have looked around the house, press the purple Balance button at the far end of the hallway, and take your time with it."
			if _focus_test() == SessionManager.CROSSING_TEST:
				return "Today's focus is crossing the road, where your score was lowest last time. Follow the yellow light to the front door, walk down to the crossing, and press the button on the pole."
			return "Today's focus is %s, where your score was lowest last time. Follow the yellow light and start there." % _focus_spoken_name()
		"all_above_threshold":
			return "You scored well in every room last time. Explore the whole house freely."
	return ""


func _speak_welcome() -> void:
	if _skip_speech:
		return
	var text := WELCOME_BODY
	var focus := _focus_sentence()
	if not focus.is_empty():
		text += "\n\n" + focus
	AudioCues.speak_text(text, true)


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
	if _skip_button != null:
		# Always available: someone who has heard it all before should never
		# have to sit through it again, at any point in the session.
		_skip_button.set_enabled(true)
	if _balance_button != null:
		_balance_button.set_enabled(stage == Stage.EXPLORING)
	if _again_button != null:
		_again_button.set_enabled(stage == Stage.DEBRIEF)
	if _finish_button != null:
		_finish_button.set_enabled(stage == Stage.DEBRIEF)


func _on_begin() -> void:
	if stage != Stage.WELCOME:
		return
	stage = Stage.EXPLORING
	_skip_speech = false  # a new stage gets to introduce itself
	SessionManager.start_session()
	_focus = SessionManager.current_focus
	_focus_hint_given = false
	_rooms_told.clear()
	if _instructions != null:
		_instructions.set_focus_line(_focus_line())
		_instructions.show_step("Look for hazards", EXPLORING_BODY, false)
	var text := EXPLORING_BODY
	var focus := _focus_sentence()
	if not focus.is_empty():
		text = focus + "\n\n" + text
	# The room the session starts in has to be introduced here: room_changed only
	# fires when the room CHANGES, and the participant is already standing in the
	# hallway when they press Begin. Its line goes on the end of the opening
	# rather than replacing the panel, so the general brief stays readable until
	# they walk somewhere.
	var here := SessionManager.current_room
	if not here.is_empty():
		_rooms_told[here] = true
		var opening := str((ROOM_GUIDES.get(here, {}) as Dictionary).get("body", ""))
		if not opening.is_empty():
			text += "\n\n" + opening
	AudioCues.speak_text(text, true)
	_set_stage_buttons()
	# Already standing in the focus room (e.g. focus = hallway)?
	_on_room_changed(here, false)


func _on_toggle_seated() -> void:
	var now := not Settings.seated_mode
	Settings.set_option("seated_mode", now)
	_refresh_seated_button()
	# SeatedMode listens to Settings and runs its own measured calibration.


## Day or night. Available at every stage on purpose: the participant may want
## to see the room they just walked through with the lights off, and a teacher
## demonstrating wants to flip it mid-sentence.
func _on_toggle_night() -> void:
	var now := not Settings.night_mode
	Settings.set_option("night_mode", now)
	_refresh_night_button()
	SessionManager.log_event("night_mode", {"on": now, "stage": stage})
	if not _skip_speech:
		if now:
			AudioCues.speak_text(
				"Night. The lamps are on, and some of them are not enough. "
				+ "Look at the floor before you step.")
		else:
			AudioCues.speak_text("Daylight again.")


func _refresh_night_button() -> void:
	if _night_button == null:
		return
	_night_button.set_label("Night mode")
	_night_button.set_sub_label("Currently: %s" % ("NIGHT" if Settings.night_mode else "DAY"))


## Erase the saved scores. TWO presses, because there is no undo.
##
## The first press arms it and says so, on the button and out loud; the second
## within the window does it. A dialog would be the obvious alternative and is
## the wrong one here: reading a modal through a headset, at this age, with the
## text scaled, is harder than touching a wall twice.
func _on_reset_scores() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_token += 1
		var token := _reset_token
		if _reset_button != null:
			_reset_button.set_label("Press again to erase")
			_reset_button.set_sub_label("%d saved session(s)" % SessionManager.session_count())
		if not _skip_speech:
			AudioCues.speak_text(
				"This erases every score saved for this participant, and it cannot "
				+ "be undone. Press it again to go ahead, or leave it alone.", true)
		SessionManager.log_event("reset_armed", {"stage": stage})
		# Disarms itself. The token means a later press cannot be cancelled by an
		# earlier press's timer.
		await get_tree().create_timer(RESET_ARM_SECONDS).timeout
		if _reset_armed and token == _reset_token:
			_disarm_reset()
		return

	var removed := SessionManager.clear_history()
	_disarm_reset()
	_focus = SessionManager.current_focus
	if _instructions != null:
		_instructions.set_focus_line(_focus_line())
	if not _skip_speech:
		if removed > 0:
			AudioCues.speak_text(
				"Done. %d session%s erased. The board is empty and the next session "
				% [removed, "" if removed == 1 else "s"]
				+ "will be a first one.", true)
		else:
			AudioCues.speak_text("There was nothing saved to erase.", true)


func _disarm_reset() -> void:
	_reset_armed = false
	if _reset_button == null:
		return
	_reset_button.set_label("Reset scores")
	var saved := SessionManager.session_count()
	_reset_button.set_sub_label(
		"Erase %d saved session(s)" % saved if saved > 0 else "Nothing saved yet")


func _refresh_seated_button() -> void:
	if _seated_button == null:
		return
	_seated_button.set_label("Seated mode")
	_seated_button.set_sub_label("Currently: %s" % ("ON" if Settings.seated_mode else "OFF"))


## Stop talking now. Pairs with "Say that again", which brings it all back.
func _on_skip() -> void:
	_skip_speech = true
	AudioCues.stop_speech()
	SessionManager.log_event("instructions_skipped", {"stage": stage})
	if _instructions != null:
		_instructions.set_focus_line(_focus_line())


func _on_repeat() -> void:
	_skip_speech = false
	match stage:
		Stage.WELCOME:
			_speak_welcome()
		Stage.EXPLORING:
			# "Say that again" repeats what applies HERE: the general brief, then
			# the guidance for the room the participant is standing in.
			var text := EXPLORING_BODY
			var focus := _focus_sentence()
			if not focus.is_empty():
				text = focus + "\n\n" + text
			var guide := str((ROOM_GUIDES.get(SessionManager.current_room, {}) as Dictionary)
				.get("body", ""))
			if not guide.is_empty():
				text += "\n\n" + guide
			AudioCues.speak_text(text, true)
		Stage.BALANCE:
			AudioCues.speak_text(BALANCE_BODY, true)
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
	if auto_start_balance and total > 0 and found >= total and not _balance_auto_started:
		_balance_auto_started = true
		if not _skip_speech:
			AudioCues.speak_text("You have found every hazard. Well done. Now for a short balance exercise.")
		await AudioCues.wait_for_speech(8.0)
		_on_start_balance()


## Say the right thing for the room the participant is actually standing in.
##
## The panel and the voice used to carry one block of text for the whole
## session, so the bathroom was told about pedestrian crossings. Now every room
## gets its own two sentences, shown on arrival and spoken the FIRST time only:
## walking back through the hallway four times should not mean hearing the
## hallway four times.
##
## The focus hints go on top of that, when this is the room the participant was
## sent here to practise. The road crossing is a focus without a room of its
## own, so it is cued on reaching the street, and its wording changes with it --
## "this is your focus room" is wrong for an exercise, and so is counting
## hazards missed in it.
func _on_room_changed(room: String, show_panel: bool = true) -> void:
	if stage != Stage.EXPLORING or room.is_empty():
		return

	var guide: Dictionary = ROOM_GUIDES.get(room, {})
	var title := str(guide.get("title", SessionManager.test_display_name(room)))
	var body := str(guide.get("body", ""))
	var spoken := body

	var crossing_focus := _focus_test() == SessionManager.CROSSING_TEST
	var is_focus := room == _focus_test() \
		or (crossing_focus and room == SessionManager.STREET_ROOM)

	if is_focus and not _focus_hint_given:
		_focus_hint_given = true
		var hints: Array = _focus.get("hints", [])
		var missed: Array = _focus.get("missed", [])
		var line := "This is your focus room."
		if crossing_focus:
			line = "Crossing the road is today's focus. The button is on the pole at the end of the pavement."
			missed = []
		if missed.size() > 0:
			line += " Last time you missed %d thing%s here." % [
				missed.size(), "" if missed.size() == 1 else "s"]
		for i in mini(hints.size(), 2):
			line += " " + str(hints[i])
		spoken = line + ("\n\n" + spoken if not spoken.is_empty() else "")
		title += "  --  today's focus"
		var listed := ""
		for i in mini(hints.size(), 3):
			listed += "\n• %s" % str(hints[i])
		body = ("Focus: %s%s" % [_focus.get("name", ""), listed]).strip_edges() \
			+ ("\n\n" + body if not body.is_empty() else "")
		SessionManager.log_event("focus_hint_given", {"room": room})

	if show_panel and _instructions != null and not body.is_empty():
		_instructions.show_step(title, body.strip_edges(), false)
	# First arrival only. Re-entering a room re-shows the panel, silently.
	if not _rooms_told.has(room):
		_rooms_told[room] = true
		if not _skip_speech and not spoken.is_empty():
			AudioCues.speak_text(spoken)


func _on_room_completed(room: String) -> void:
	if stage != Stage.EXPLORING:
		return
	# The whole-house message takes precedence when this was the last room.
	if SessionManager.hazards_found() >= SessionManager.hazards_total():
		return
	var line: String = AudioCues.SPOKEN_LINES["room_complete"]
	if room == _focus_test():
		line = "Well done. You found everything in your focus room. " + line
	AudioCues.speak_text(line)


func _on_start_balance() -> void:
	if stage != Stage.EXPLORING or _balance == null:
		return
	stage = Stage.BALANCE
	_skip_speech = false
	_set_stage_buttons()
	if _beacon != null:
		_beacon.hide_beacon()
	if _instructions != null:
		_instructions.show_step("Balance exercise", BALANCE_BODY, false)
	_balance.begin()


func _on_balance_finished(_results: Array) -> void:
	if stage == Stage.BALANCE:
		_show_debrief()


func _show_debrief() -> void:
	stage = Stage.DEBRIEF
	_skip_speech = false
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
		_instructions.set_focus_line("")
		_instructions.show_step("Finished", "Your results are on the panel in front of you and on the progress board.", false)


## Start a fresh session straight away (reloads the house). Today's results
## are already saved, so the new session's focus includes them.
func _on_again() -> void:
	if stage != Stage.DEBRIEF:
		return
	AudioCues.stop_speech()
	SessionManager.prepare_new_run()
	get_tree().reload_current_scene()


func _on_finish() -> void:
	AudioCues.speak("session_complete", true)
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


## Escape hatch for a researcher: end the session early (F10 on the keyboard).
func force_debrief() -> void:
	if stage == Stage.DEBRIEF or stage == Stage.WELCOME:
		return
	if stage == Stage.BALANCE and _balance != null:
		_balance.abort()
	SessionManager.log_event("session_ended_early", {})
	_show_debrief()
