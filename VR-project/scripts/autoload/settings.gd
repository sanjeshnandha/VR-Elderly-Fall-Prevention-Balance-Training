extends Node
## Persistent, accessibility-focused user settings (autoload singleton "Settings").
##
## Everything here is deliberately coarse-grained: a senior user should never be
## asked to fine-tune a slider. Options are ON/OFF or three-step where possible.
##
## Saved to `user://settings.cfg` so a returning participant keeps their profile.

const CONFIG_PATH := "user://settings.cfg"

## Emitted whenever any setting changes. Listeners re-apply themselves.
signal settings_changed

# --- Comfort ---------------------------------------------------------------

## Seated mode. See scripts/player/seated_mode.gd (Architectural Fix 5.2).
## Change it through `set_option("seated_mode", true)` so listeners are notified.
var seated_mode: bool = false

## The virtual character's standing eye height in metres. When seated mode is
## on, the XROrigin3D is raised so the physically-seated player's eyes land
## here, keeping counters and handrails at a natural reach.
var standing_eye_height: float = 1.60

## Comfort vignette while turning / teleporting. ON by default.
var comfort_vignette: bool = true

## Teleport-only locomotion. Smooth locomotion is OFF by default and there is
## no in-app way to enable it for the participant; it exists only as a
## researcher/debug affordance.
var smooth_locomotion: bool = false

# --- Sensory (Architectural Fix 5.3) ---------------------------------------

## Master volume for spoken/UI cues, in linear 0..1. Defaults high because
## presbycusis (age-related high-frequency hearing loss) is the norm in this
## population.
var cue_volume: float = 1.0

## Multiplier applied to every UI font size. 1.0 == already-large baseline.
var text_scale: float = 1.0

## Speak instructions aloud using the OS text-to-speech engine, in addition to
## showing them on the panel.
var spoken_instructions: bool = true

# --- Session ---------------------------------------------------------------

## Free-text participant identifier written into the session log. Set by the
## researcher, not the participant.
var participant_id: String = "anonymous"


func _ready() -> void:
	# First autoload to run. If this line is absent from the Output panel, the
	# project never got as far as loading autoloads and the problem is in
	# project.godot or the run configuration, not in any scene.
	print("[Settings] Autoloads booting on %s, Godot %s."
		% [OS.get_name(), Engine.get_version_info().get("string", "?")])
	load_settings()


## Change any field by name and notify listeners. Used by the in-world
## settings panel so it does not need a setter per option.
func set_option(option_name: String, value: Variant) -> void:
	if not (option_name in self):
		push_warning("Settings.set_option: unknown option '%s'" % option_name)
		return
	set(option_name, value)
	save_settings()
	settings_changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("comfort", "seated_mode", seated_mode)
	cfg.set_value("comfort", "standing_eye_height", standing_eye_height)
	cfg.set_value("comfort", "comfort_vignette", comfort_vignette)
	cfg.set_value("comfort", "smooth_locomotion", smooth_locomotion)
	cfg.set_value("sensory", "cue_volume", cue_volume)
	cfg.set_value("sensory", "text_scale", text_scale)
	cfg.set_value("sensory", "spoken_instructions", spoken_instructions)
	cfg.set_value("session", "participant_id", participant_id)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("Settings: could not save to %s (error %d)" % [CONFIG_PATH, err])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return  # First run; defaults above are already correct.
	seated_mode = cfg.get_value("comfort", "seated_mode", seated_mode)
	standing_eye_height = cfg.get_value("comfort", "standing_eye_height", standing_eye_height)
	comfort_vignette = cfg.get_value("comfort", "comfort_vignette", comfort_vignette)
	smooth_locomotion = cfg.get_value("comfort", "smooth_locomotion", smooth_locomotion)
	cue_volume = cfg.get_value("sensory", "cue_volume", cue_volume)
	text_scale = cfg.get_value("sensory", "text_scale", text_scale)
	spoken_instructions = cfg.get_value("sensory", "spoken_instructions", spoken_instructions)
	participant_id = cfg.get_value("session", "participant_id", participant_id)
	settings_changed.emit()
