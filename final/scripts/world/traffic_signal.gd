@tool
class_name TrafficSignal
extends Node3D
## Core System J -- a signalled pedestrian crossing, and the practice of using it.
##
## WHY A SIGNALLED CROSSING AND NOT JUST A ZEBRA.
## Judging a gap in traffic is the hardest part of crossing a road, and it is the
## part that degrades first: it needs distance judgement, speed judgement and the
## confidence to commit. A signalled crossing replaces all of that with a
## sequence -- press, wait, watch, cross -- which is learnable, repeatable and
## the same at every crossing in the country. That sequence is the thing worth
## practising, so this node owns it and `StreetCrossing` scores it.
##
## THE CYCLE. It rests on green for the traffic and only changes when somebody
## asks for it, which is what makes the button matter:
##
##   TRAFFIC_GREEN   traffic goes, red man. Rests here until the button is
##                   pressed, then runs out `minimum_green` first -- a press
##                   does not stop the traffic instantly, and learning that is
##                   part of the point.
##   TRAFFIC_AMBER   traffic stopping.
##   ALL_RED         everything stopped, before anyone is invited out.
##   WALK            green man, and the bleeper. Cross NOW.
##   WALK_CLEARING   the green man flashes. If you are already crossing, carry
##                   on; if you are still on the kerb, do not start.
##   then back to TRAFFIC_GREEN.
##
## IT NEVER BLOCKS, like everything else here. You can walk out on a red man and
## the cars will still stop for you (see street_car.gd) -- what happens is that
## the attempt is scored as not having waited, and you are told so. A crossing
## that physically cannot be got wrong teaches nothing about the crossing
## outside the front door.

signal phase_changed(phase: int)
signal demand_registered

enum Phase { TRAFFIC_GREEN, TRAFFIC_AMBER, ALL_RED, WALK, WALK_CLEARING }

## Seconds of green the traffic always gets before a press can take effect.
@export var minimum_green: float = 6.0
@export var amber_seconds: float = 3.0
@export var all_red_seconds: float = 2.0

## The green man. Generous: the road is 7 m and an unhurried older walker is
## nearer 0.7 m/s than the 1.2 m/s most signal timings assume.
@export var walk_seconds: float = 10.0

## The flashing green man. Long enough to finish a crossing begun at the very
## end of `walk_seconds`.
@export var clearing_seconds: float = 6.0

## Rest on green until somebody presses, rather than cycling on its own. On is
## what makes the button a lesson rather than scenery.
@export var rest_in_green: bool = true

## The bleeper that sounds while the green man is lit. Positional, so it is
## audible at the crossing and not through the house.
@export var bleeper: bool = true
@export var bleep_interval: float = 0.6
@export var bleep_hz: float = 2000.0
@export var bleeper_distance: float = 18.0

const MIX_RATE := 22050

var phase: int = Phase.TRAFFIC_GREEN
var _elapsed: float = 0.0
var _demanded: bool = false
var _bleep_t: float = 0.0
var _player: AudioStreamPlayer3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("traffic_signal")
	_build_bleeper()
	SessionManager.session_started.connect(_on_session_started)


func _on_session_started() -> void:
	phase = Phase.TRAFFIC_GREEN
	_elapsed = 0.0
	_demanded = false
	phase_changed.emit(phase)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_elapsed += delta
	match phase:
		Phase.TRAFFIC_GREEN:
			if _elapsed >= minimum_green and (_demanded or not rest_in_green):
				_advance(Phase.TRAFFIC_AMBER)
		Phase.TRAFFIC_AMBER:
			if _elapsed >= amber_seconds:
				_advance(Phase.ALL_RED)
		Phase.ALL_RED:
			if _elapsed >= all_red_seconds:
				_demanded = false
				_advance(Phase.WALK)
		Phase.WALK:
			_bleep(delta)
			if _elapsed >= walk_seconds:
				_advance(Phase.WALK_CLEARING)
		Phase.WALK_CLEARING:
			if _elapsed >= clearing_seconds:
				_advance(Phase.TRAFFIC_GREEN)


func _advance(next: int) -> void:
	phase = next
	_elapsed = 0.0
	_bleep_t = 0.0
	if next == Phase.WALK:
		AudioCues.speak_text("The green man is showing. You can cross now.")
	elif next == Phase.WALK_CLEARING:
		AudioCues.speak_text("The green man is flashing. Finish crossing, but do not start.")
	phase_changed.emit(phase)
	SessionManager.log_event("signal_phase", {"phase": phase_name()})


# ---------------------------------------------------------------------------
#  What the rest of the street asks it
# ---------------------------------------------------------------------------

## Somebody pressed the button. Safe to call repeatedly.
func request_walk() -> void:
	if phase != Phase.TRAFFIC_GREEN:
		AudioCues.play("neutral")      # already asked for; not a rejection
		return
	if _demanded:
		AudioCues.play("neutral")
		return
	_demanded = true
	AudioCues.play("confirm")
	AudioCues.speak_text("Thank you. Wait here until the green man shows.")
	SessionManager.log_event("crossing_requested", {"wait": snappedf(remaining(), 0.1)})
	demand_registered.emit()


## True once the button has been pressed and the change is on its way.
func is_demanded() -> bool:
	return _demanded


## The green man is lit and steady: this, and only this, is when to step out.
func is_walk() -> bool:
	return phase == Phase.WALK


## The green man is flashing: finish if you are out there, do not start.
func is_clearing() -> bool:
	return phase == Phase.WALK_CLEARING


## Traffic must be stopped at the line.
func traffic_must_stop() -> bool:
	return phase == Phase.ALL_RED or phase == Phase.WALK or phase == Phase.WALK_CLEARING


## Traffic is on amber and should stop if it can do so safely.
func traffic_stopping() -> bool:
	return phase == Phase.TRAFFIC_AMBER


## Seconds left in the current phase.
func remaining() -> float:
	var total := minimum_green
	match phase:
		Phase.TRAFFIC_AMBER:
			total = amber_seconds
		Phase.ALL_RED:
			total = all_red_seconds
		Phase.WALK:
			total = walk_seconds
		Phase.WALK_CLEARING:
			total = clearing_seconds
	return maxf(total - _elapsed, 0.0)


func phase_name() -> String:
	match phase:
		Phase.TRAFFIC_AMBER:
			return "traffic_amber"
		Phase.ALL_RED:
			return "all_red"
		Phase.WALK:
			return "walk"
		Phase.WALK_CLEARING:
			return "walk_clearing"
		_:
			return "traffic_green"


## What a participant standing at the kerb should be told right now.
func advice() -> String:
	match phase:
		Phase.WALK:
			return "Cross now."
		Phase.WALK_CLEARING:
			return "Do not start crossing. Wait for the next green man."
		_:
			if _demanded:
				return "Wait. The green man is coming."
			return "Press the button on the pole, then wait for the green man."


# ---------------------------------------------------------------------------
#  The bleeper
# ---------------------------------------------------------------------------

func _bleep(delta: float) -> void:
	if not bleeper or _player == null:
		return
	_bleep_t -= delta
	if _bleep_t > 0.0:
		return
	_bleep_t = bleep_interval
	# Floored well above zero: linear_to_db(0.0) is -INF, and an infinite gain
	# going into the audio server is the kind of thing that takes the whole
	# process down rather than producing a quiet sound.
	var level := maxf(clampf(Settings.cue_volume, 0.0, 1.0) * 0.55, 0.0005)
	_player.volume_db = linear_to_db(level)
	if Settings.cue_volume > 0.001:
		_player.play()


## A short pip as an AudioStreamPlayer3D rather than through AudioCues, because
## AudioCues is head-locked by design -- correct for a spoken warning, wrong for
## a crossing you are supposed to locate by ear from thirty metres away.
func _build_bleeper() -> void:
	_player = AudioStreamPlayer3D.new()
	_player.stream = _pip(bleep_hz, 0.12)
	_player.unit_size = 6.0
	_player.max_distance = bleeper_distance
	_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_player)


func _pip(freq: float, duration: float) -> AudioStreamWAV:
	var total := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(total * 2)
	var fade := int(MIX_RATE * 0.006)
	var phase_acc := 0.0
	for i in total:
		phase_acc = fmod(phase_acc + TAU * freq / float(MIX_RATE), TAU)
		var env := 1.0
		if i < fade:
			env = float(i) / float(fade)
		elif i > total - fade:
			env = float(total - i) / float(fade)
		var value := int(clampf(sin(phase_acc) * env * 0.6, -1.0, 1.0) * 32767.0)
		if value < 0:
			value += 65536
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
