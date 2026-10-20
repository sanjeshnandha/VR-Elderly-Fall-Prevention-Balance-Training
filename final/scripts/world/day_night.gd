@tool
class_name DayNight
extends Node
## The same house after dark -- Core System K.
##
## WHY NIGHT IS THE CASE THAT MATTERS. Most falls at home happen on the way to
## the bathroom in the middle of the night: half asleep, no slippers, no glasses,
## and whatever light there is. A simulator that only ever runs at noon trains
## the easy half of the problem. Two of the hazards in this house -- the bedroom
## light that is too dim to see the floor by, and the unlit stairwell -- barely
## read at all in daylight, because in daylight they are not hazards.
##
## WHAT IT DOES. One switch, applied to three things:
##
##   the sun		  becomes a moon: a fortieth of the energy, cold instead of
##					warm, and the sky, the ambient light and the fog go with
##					it;
##   the room lights  come up. Every lamp in the house is in the `room_light`
##					group and keeps its OWN authored energy, multiplied by one
##					gain -- so the lamps that were deliberately feeble stay
##					deliberately feeble, and the hazard survives the switch;
##   the daylight	 goes off. Window beams and sunbeams are in the `daylight`
##					group; the street lamps, the porch light and the light over
##					the crossing are in `street_light` and do the opposite.
##
## Nothing here is animated. A slow fade would be prettier and would also mean
## the participant pressing the button sees nothing happen for two seconds, then
## a room that changed while they were looking away. The switch is immediate and
## the spoken line says which way it went.
##
## The authored energies are read ONCE, at startup, before anything is changed.
## Everything after that is a multiple of those, so pressing the button fifty
## times leaves the house exactly as it found it.

@export var sun_path: NodePath = ^"../SunThroughWindows"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"

@export_group("Night")
## Moonlight, as a fraction of the sun's authored energy.
@export var moon_energy_scale: float = 0.055
@export var moon_color: Color = Color(0.62, 0.70, 0.92)
## Lamps are lit for a room that also has daylight in it, so they need a lift to
## carry it alone. The dim ones are lifted by the same factor and stay dim.
@export var lamp_night_gain: float = 1.9
@export var street_night_gain: float = 1.0
@export var ambient_night_color: Color = Color(0.10, 0.12, 0.20)
@export var ambient_night_energy: float = 0.22
@export var sky_night_top: Color = Color(0.015, 0.02, 0.05)
@export var sky_night_horizon: Color = Color(0.06, 0.07, 0.12)
@export var sky_night_ground: Color = Color(0.03, 0.03, 0.04)
## Fog carries the lamp pools outdoors. Too much and the street is soup.
@export var fog_night_density: float = 0.013
## Lamps should bloom a little after dark; in daylight that reads as a smear.
@export var glow_night_threshold: float = 0.72

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
## Authored values, read before anything is touched.
var _authored: Dictionary = {}
var _day: Dictionary = {}
var _applied: bool = false


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var holder := get_node_or_null(world_environment_path) as WorldEnvironment
	_env = holder.environment if holder != null else null
	if _env != null and _env.sky != null:
		_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_remember()
	if Engine.is_editor_hint():
		return
	add_to_group("day_night")
	Settings.settings_changed.connect(_on_settings_changed)
	# Deferred: the room scenes' lights have to be in the tree before they can
	# be found by group.
	apply.call_deferred(Settings.night_mode)


## Read the scene's own values, once, so that day is "put it back" rather than
## "a second set of numbers that has to be kept in step with the first".
func _remember() -> void:
	if _sun != null:
		_day["sun_energy"] = _sun.light_energy
		_day["sun_color"] = _sun.light_color
	if _env != null:
		_day["ambient_color"] = _env.ambient_light_color
		_day["ambient_energy"] = _env.ambient_light_energy
		_day["fog"] = _env.volumetric_fog_density
		_day["glow"] = _env.glow_hdr_threshold
	if _sky != null:
		_day["sky_top"] = _sky.sky_top_color
		_day["sky_horizon"] = _sky.sky_horizon_color
		_day["sky_ground"] = _sky.ground_bottom_color
		_day["sky_horizon_ground"] = _sky.ground_horizon_color


func _lights(group: String) -> Array[Light3D]:
	var out: Array[Light3D] = []
	for node in get_tree().get_nodes_in_group(group):
		var light := node as Light3D
		if light == null:
			continue
		if not _authored.has(light):
			_authored[light] = light.light_energy
		out.append(light)
	return out


func _on_settings_changed() -> void:
	apply(Settings.night_mode)


## Switch the whole world. Safe to call repeatedly.
func apply(night: bool) -> void:
	if _env == null:
		return

	for light in _lights("room_light"):
		light.light_energy = float(_authored[light]) * (lamp_night_gain if night else 1.0)
		light.visible = true
	for light in _lights("daylight"):
		light.visible = not night
	for light in _lights("street_light"):
		light.light_energy = float(_authored[light]) * street_night_gain
		light.visible = night

	# Lit windows on the far terrace: emissive panels rather than lights,
	# because forty more omnis would cost a great deal and light nothing the
	# participant can reach. A glowing window at noon looks like a mistake, so
	# they are simply hidden in daylight.
	for node in get_tree().get_nodes_in_group("lit_window"):
		var panel := node as Node3D
		if panel != null:
			panel.visible = night

	if _sun != null:
		_sun.light_energy = float(_day["sun_energy"]) * (moon_energy_scale if night else 1.0)
		_sun.light_color = moon_color if night else _day["sun_color"]

	_env.ambient_light_color = ambient_night_color if night else _day["ambient_color"]
	_env.ambient_light_energy = ambient_night_energy if night else _day["ambient_energy"]
	_env.volumetric_fog_density = fog_night_density if night else _day["fog"]
	_env.glow_hdr_threshold = glow_night_threshold if night else _day["glow"]

	if _sky != null:
		_sky.sky_top_color = sky_night_top if night else _day["sky_top"]
		_sky.sky_horizon_color = sky_night_horizon if night else _day["sky_horizon"]
		_sky.ground_bottom_color = sky_night_ground if night else _day["sky_ground"]
		_sky.ground_horizon_color = sky_night_horizon if night else _day["sky_horizon_ground"]

	_applied = night
	if not Engine.is_editor_hint():
		SessionManager.log_event("lighting_changed", {"night": night})


## What the ambient should be in DAYLIGHT. Called by GraphicsQuality, which
## raises it when there is no bounced light to fill the corners -- see the note
## there for why this is a handover rather than two scripts writing the same
## property.
func set_day_ambient(value: float) -> void:
	_day["ambient_energy"] = value
	apply(Settings.night_mode)


func is_night() -> bool:
	return _applied
