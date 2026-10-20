@tool
class_name GraphicsQuality
extends Node
## Turns the expensive rendering features on and off as one decision, and picks
## a sensible starting point for the machine it finds itself on.
##
## WHY THIS EXISTS. The realism pass switched on SDFGI, SSIL, screen-space
## reflections, volumetric fog and shadow-casting lights in every room. That set
## is aimed at a desktop with a discrete GPU. On a fanless laptop with integrated
## graphics -- an M-series MacBook Air, say -- it is far too much: SDFGI alone
## can cost more per frame than everything else put together, and five
## shadow-casting omni lights are thirty extra renders of the scene every frame,
## because a point light's shadow is a cube and a cube has six faces.
##
## So the effects are grouped into three levels and chosen at startup from the
## video adapter. Integrated graphics get SMOOTH, which still has real textures,
## real materials, filleted edges, sun shadows and ambient occlusion -- the
## things you actually see -- and drops the ones you mostly do not notice once
## they are gone.
##
## WHAT EACH LEVEL COSTS, roughly, in descending order of expense:
##   SDFGI            real-time bounced light. The single most expensive thing
##                    here. Off below ULTRA; the rooms keep their sky ambient,
##                    so they get flatter rather than dark.
##   volumetric fog   the light shafts through the windows. Pretty, costly.
##   SSIL             screen-space bounced light. Subtle, not cheap.
##   omni shadows     six scene renders each. Off below ULTRA.
##   SSR              screen-space reflections on the glass and worktops.
##   PCSS soft sun    shadows that soften with distance; a real cost for a real
##                    gain, so it survives into BALANCED.
##   SSAO             contact darkening. Comparatively cheap and does more for
##                    "things are sitting on the floor" than anything else, so
##                    it stays on at every level.
##
## Press F8 while running to cycle levels and see the frame rate, which is the
## quickest way to find out what your machine actually minds.

enum Level { SMOOTH, BALANCED, ULTRA }

const LEVEL_NAMES := ["Smooth", "Balanced", "Ultra"]

## The WorldEnvironment whose Environment gets reconfigured.
@export var world_environment_path: NodePath

## Show the level and frame rate for a few seconds after a change.
@export var show_readout: bool = true

## Lights whose shadows are switched off below ULTRA are remembered here, so
## turning the level back up restores exactly what the scene author asked for.
var _designed_shadows: Dictionary = {}
var _readout: Label = null
var _readout_layer: CanvasLayer = null
var _readout_until: float = 0.0
var _level: int = Level.BALANCED


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(true)
	_remember_designed_shadows()
	apply(_auto_level() if Settings.graphics_quality < 0 else Settings.graphics_quality, false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F8:
		cycle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _readout == null:
		return
	if Time.get_ticks_msec() * 0.001 > _readout_until:
		_readout_layer.visible = false
		return
	_readout.text = "%s   %d fps" % [LEVEL_NAMES[_level], Engine.get_frames_per_second()]


## Step to the next level and remember it.
func cycle() -> void:
	apply((_level + 1) % LEVEL_NAMES.size(), true)


func apply(level: int, remember: bool) -> void:
	_level = clampi(level, 0, LEVEL_NAMES.size() - 1)
	var env := _environment()
	if env != null:
		_apply_environment(env)
	_apply_lights()
	_apply_viewport()
	if remember:
		Settings.set_option("graphics_quality", _level)
	print("[GraphicsQuality] %s (%s)" % [LEVEL_NAMES[_level], _adapter()])
	SessionManager.log_event("graphics_quality", {"level": LEVEL_NAMES[_level]})
	if show_readout:
		_show_readout()


func level_name() -> String:
	return LEVEL_NAMES[_level]


# ---------------------------------------------------------------------------
#  Choosing a starting level
# ---------------------------------------------------------------------------

static func _adapter() -> String:
	return RenderingServer.get_video_adapter_name()


## Integrated graphics get SMOOTH, everything else BALANCED. Nothing starts on
## ULTRA: a first run that stutters is worse than one that looks slightly
## flatter, and F8 is one keystroke away.
static func _auto_level() -> int:
	var name := _adapter().to_lower()
	for integrated in ["apple", "intel", "uhd", "iris", "radeon graphics", "vega", "adreno", "mali"]:
		if name.contains(integrated):
			return Level.SMOOTH
	return Level.BALANCED


# ---------------------------------------------------------------------------
#  Applying it
# ---------------------------------------------------------------------------

func _environment() -> Environment:
	var holder := get_node_or_null(world_environment_path) as WorldEnvironment
	if holder == null:
		push_warning("GraphicsQuality: world_environment_path does not point at a WorldEnvironment.")
		return null
	return holder.environment


func _apply_environment(env: Environment) -> void:
	var ultra := _level == Level.ULTRA
	var balanced := _level >= Level.BALANCED

	# The big one. Without it the rooms are lit by the sky ambient and their own
	# lamps, which is flatter but never dark.
	env.sdfgi_enabled = ultra
	env.ssil_enabled = ultra
	env.volumetric_fog_enabled = ultra

	env.ssr_enabled = balanced
	env.ssr_max_steps = 56 if ultra else 24

	# Kept at every level: it is the cheapest way to make an object look like it
	# is standing on the floor rather than hovering over it.
	env.ssao_enabled = true
	env.ssao_intensity = 2.2 if balanced else 1.8
	env.ssao_radius = 1.1 if balanced else 0.7

	env.glow_enabled = true

	# With no bounced light, lift the ambient a little so the far corners of a
	# room do not fall away.
	#
	# Two things want to own the ambient: this, and night mode. They would
	# otherwise take it in turns, and whichever ran last would win -- so pressing
	# the night button could come out fully lit, or changing the graphics level
	# after dark could turn the sun back on. This sets the DAY value and hands it
	# to DayNight, which decides what the ambient actually is.
	var day_ambient := 1.0 if ultra else 1.25
	var day_night := get_tree().get_first_node_in_group("day_night")
	if day_night != null and day_night.has_method("set_day_ambient"):
		day_night.call("set_day_ambient", day_ambient)
	else:
		env.ambient_light_energy = day_ambient


func _remember_designed_shadows() -> void:
	for light in _lights():
		_designed_shadows[light.get_instance_id()] = light.shadow_enabled


func _lights() -> Array[Light3D]:
	var found: Array[Light3D] = []
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var light := node as Light3D
		if light != null:
			found.append(light)
		for child in node.get_children():
			stack.append(child)
	return found


func _apply_lights() -> void:
	var ultra := _level == Level.ULTRA
	var balanced := _level >= Level.BALANCED
	for light in _lights():
		var designed: bool = _designed_shadows.get(light.get_instance_id(), light.shadow_enabled)
		if light is DirectionalLight3D:
			# The sun keeps its shadows at every level -- daylight with no shadow
			# on the floor stops reading as daylight at all. What changes is how
			# it is filtered.
			light.shadow_enabled = designed
			light.light_angular_distance = 0.6 if balanced else 0.0
			light.directional_shadow_mode = (
				DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if balanced
				else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
			light.directional_shadow_max_distance = 60.0 if balanced else 35.0
		elif light is SpotLight3D:
			# One shadow map each, and they are the window shafts, so they are
			# worth keeping down to BALANCED.
			light.shadow_enabled = designed and balanced
		else:
			# An OmniLight's shadow is a cube: six renders of the scene, every
			# frame, per light. This is where the frame rate goes.
			light.shadow_enabled = designed and ultra


func _apply_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	# Rendering 3D below the window resolution and letting FSR scale it back up
	# is the single biggest saving available on a high-DPI display: a "1280x720"
	# window on a Retina screen is really 2560x1440 pixels, which is 3.7 million
	# of them being shaded every frame.
	#
	# FSR 1 rather than FSR 2 on purpose. FSR 2 looks better but is temporal, and
	# temporal upscalers ghost behind moving objects -- not something to inflict
	# on an application whose whole subject is judging where things are.
	#
	# A headset sets its own render scale, so this is left alone in VR.
	var in_vr := vp.use_xr
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = 1.0 if in_vr else [0.75, 0.85, 1.0][_level]
	vp.fsr_sharpness = 0.25
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][_level]
	vp.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA if _level == Level.SMOOTH
		else Viewport.SCREEN_SPACE_AA_DISABLED)


func _show_readout() -> void:
	if _readout == null:
		_readout_layer = CanvasLayer.new()
		_readout_layer.layer = 100
		add_child(_readout_layer)
		_readout = Label.new()
		_readout.position = Vector2(18, 14)
		_readout.add_theme_font_size_override("font_size", 22)
		_readout.add_theme_color_override("font_color", Color(1, 1, 1))
		_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_readout.add_theme_constant_override("outline_size", 6)
		_readout_layer.add_child(_readout)
	_readout_layer.visible = true
	_readout_until = Time.get_ticks_msec() * 0.001 + 4.0
