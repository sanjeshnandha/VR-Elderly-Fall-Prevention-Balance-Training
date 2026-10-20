extends Node
## Head-locked (2D) audio cue bus -- Architectural Fix 5.3, audio half.
##
## WHY THIS IS NOT AudioStreamPlayer3D
## -----------------------------------
## Positional audio attenuates with distance and head orientation. That is
## exactly what you want for ambience, and exactly what you must NOT use for
## essential instructions: if the participant is looking away from the hazard
## -- which, by definition, is what happens when they *miss* a hazard -- the
## corrective cue fades out and is never heard. Add presbycusis (age-related
## high-frequency hearing loss, present in ~⅓ of people over 65) and the cue is
## gone entirely.
##
## So: every instruction, confirmation, warning and debrief line plays through a
## plain `AudioStreamPlayer`, which is head-locked, non-attenuating, and full
## volume regardless of where the user is looking.
##
## SPEECH QUEUE
## ------------
## Spoken lines QUEUE by default, so a confirmation never cuts off the end of
## an instruction. Pass `interrupt = true` only for lines that must be heard
## right now (a countdown number, "say that again").
##
## TONES ARE GENERATED, NOT SHIPPED
## --------------------------------
## Cue tones are synthesised at startup into AudioStreamWAV resources so the
## project has zero binary audio dependencies. Drop real recorded voice-over
## into `res://audio/` and call `play_stream()` to override any of them.

## Emitted when a cue finishes; useful for chaining instruction steps.
signal cue_finished(cue_name: String)

const MIX_RATE := 22050

## Named cue -> [frequency_hz, duration_seconds, is_two_tone]
const TONE_TABLE := {
	"confirm":      [880.0, 0.16, false],   # hazard correctly flagged
	"reject":       [220.0, 0.22, false],   # not possible right now (locked, too early)
	"neutral":      [587.33, 0.14, false],  # noted, no judgement (a safe object was flagged)
	"reminder":     [523.25, 0.30, true],   # "try using the rail here"
	"countdown":    [660.0, 0.10, false],   # 3.. 2.. 1..
	"go":           [990.0, 0.28, false],   # balance task start
	"success":      [1174.7, 0.34, true],   # balance target touched
	"page":         [440.0, 0.12, false],   # UI page turn / button press
}

## Spoken lines. Shown on the panel AND (if enabled) read aloud by the OS TTS.
const SPOKEN_LINES := {
	"use_rail": "Try using the rail here. Hold the grip button to take hold of it.",
	"rail_good": "Good. Keep hold of the rail.",
	"balance_intro": "Keep your feet where they are and look straight ahead. A glowing ball will appear. Reach out and touch it, only as far as is comfortable.",
	"balance_go": "Go. Reach for the ball.",
	"balance_done": "Well done. You can lower your arm.",
	"room_complete": "You found everything in this room. Move to the next doorway when you are ready.",
	"session_complete": "That is the end of the session. Your results are on the panel in front of you.",
}

var _player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _tones: Dictionary = {}
var _tts_voice_id: String = ""
var _current_cue: String = ""


func _ready() -> void:
	# Two separate head-locked players so a short confirmation beep can never
	# cut off a spoken instruction mid-sentence.
	_player = AudioStreamPlayer.new()
	_player.name = "CuePlayer"
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_cue_finished)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "VoicePlayer"
	_voice_player.bus = "Master"
	add_child(_voice_player)

	_build_tones()
	_pick_tts_voice()

	Settings.settings_changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	var db := linear_to_db(clampf(Settings.cue_volume, 0.0001, 1.0))
	_player.volume_db = db
	_voice_player.volume_db = db


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

## Play a named tone from TONE_TABLE. Non-positional, always audible.
func play(cue_name: String) -> void:
	if not _tones.has(cue_name):
		push_warning("AudioCues.play: unknown cue '%s'" % cue_name)
		return
	_current_cue = cue_name
	_player.stream = _tones[cue_name]
	_player.play()


## Play a caller-supplied stream (e.g. recorded voice-over) head-locked.
func play_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	_voice_player.stream = stream
	_voice_player.play()


## Speak one of SPOKEN_LINES aloud (if TTS is available and enabled) and return
## the text so the caller can also display it. ALWAYS display the returned text:
## audio alone is not accessible.
func speak(line_key: String, interrupt: bool = false) -> String:
	var text: String = SPOKEN_LINES.get(line_key, line_key)
	speak_text(text, interrupt)
	return text


## Speak arbitrary text aloud. Safe to call when no TTS engine exists.
## Queues behind anything already being spoken unless `interrupt` is true.
func speak_text(text: String, interrupt: bool = false) -> void:
	if not Settings.spoken_instructions:
		return
	if _tts_voice_id.is_empty() or text.strip_edges().is_empty():
		return
	# Rate 0.85: slightly slower than default. Comprehension in older adults
	# improves markedly with a reduced speech rate.
	DisplayServer.tts_speak(text, _tts_voice_id, 100, 1.0, 0.85, 0, interrupt)


## True while the TTS engine is still speaking (or has lines queued).
func is_speaking() -> bool:
	if _tts_voice_id.is_empty() or not Settings.spoken_instructions:
		return false
	return DisplayServer.tts_is_speaking()


## Wait until speech has finished, but never longer than `max_seconds`, so a
## misbehaving TTS engine can never stall the session.
func wait_for_speech(max_seconds: float = 12.0) -> void:
	var waited := 0.0
	while is_speaking() and waited < max_seconds:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1


func stop_speech() -> void:
	if not _tts_voice_id.is_empty():
		DisplayServer.tts_stop()


# ---------------------------------------------------------------------------
#  Internals
# ---------------------------------------------------------------------------

func _on_cue_finished() -> void:
	cue_finished.emit(_current_cue)


func _pick_tts_voice() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
	if voices.size() > 0:
		_tts_voice_id = voices[0]


func _build_tones() -> void:
	for cue_name: String in TONE_TABLE.keys():
		var spec: Array = TONE_TABLE[cue_name]
		_tones[cue_name] = _make_tone(spec[0], spec[1], spec[2])


## Synthesise a mono 16-bit sine tone with a short attack/release envelope so it
## does not click. `two_tone` switches to a perfect fifth above halfway through,
## which reads as "attention" rather than "error" and survives high-frequency
## hearing loss better than a single high beep.
##
## The phase is accumulated sample by sample, so the switch to the second
## pitch is continuous -- recomputing sin(2*pi*f*t) with a new f would jump
## the waveform and produce an audible click mid-cue.
func _make_tone(freq: float, duration: float, two_tone: bool) -> AudioStreamWAV:
	var total := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(total * 2)
	var fade := int(MIX_RATE * 0.008)  # 8 ms click guard
	var phase := 0.0

	for i in total:
		var f := freq
		if two_tone and i > total / 2:
			f = freq * 1.5
		phase = fmod(phase + TAU * f / float(MIX_RATE), TAU)
		var sample := sin(phase)

		# Envelope
		var env := 1.0
		if i < fade:
			env = float(i) / float(fade)
		elif i > total - fade:
			env = float(total - i) / float(fade)
		sample *= env * 0.6

		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
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
