class_name ComfortVignette
extends MeshInstance3D
## Core System D -- comfort vignette (tunnelling) plus the non-vestibular
## warning flash used by SlipZone.
##
## A quad parented to the XRCamera3D, drawn a few centimetres in front of the
## eyes with a radial alpha gradient. Narrowing the visible field during
## rotation and teleport suppresses the peripheral optic flow that drives
## simulator sickness. Because it is a child of the camera it is head-locked by
## construction and costs one transparent quad per frame.
##
## ON by default. Research participants are not asked to opt in to comfort.
##
## GEOMETRY -- WHY THE QUAD IS SMALL
## ---------------------------------
## The quad sits 6 cm from the eye, so its size is really an ANGLE. At
## 0.20 x 0.18 m, the quad edge (shader distance d = 1) is ~59 deg off-axis
## horizontally and ~56 deg vertically: just past the edge of a typical
## headset's field of view, so a closed vignette covers everything outside
## the clear centre. (A 2.4 m quad at 6 cm would put even the "closed"
## vignette at ~80 deg -- outside the lens entirely, i.e. invisible.)
##   d = 0.25  ->  ~23 deg      d = 0.55  ->  ~43 deg      d = 1.0  ->  ~59 deg

const QUAD_SIZE := Vector2(0.20, 0.18)
const QUAD_DISTANCE := 0.06

## Radius of the clear centre, in shader units (d, see above). Smaller =
## stronger tunnelling. Open is beyond the quad corners, i.e. no vignette.
@export var open_radius: float = 1.8
@export var closed_radius: float = 0.40

## How quickly the vignette closes and reopens, in radius units per second.
@export var close_speed: float = 6.0
@export var open_speed: float = 2.5

## Close the vignette on a fast turn at all.
##
## It used to do this at 45 deg/s, which is where "why is the screen blinking?"
## came from. The desktop rig turns the camera with the mouse at 0.0022 rad per
## pixel, so ten pixels in a frame is 76 deg/s and a hundred is 756: ANY mouse
## movement crossed it. The vignette then took 0.23 s to close and 0.56 s to
## reopen, so looking around a room was a continuous flicker.
##
## It is also the wrong trigger in a headset. Simulator sickness comes from the
## eyes and the inner ear DISAGREEING -- which is what artificial locomotion
## does, and what turning your own head does not. This project moves the
## participant by teleport only, and every teleport already blinks. So the turn
## rule guards one real case: a whip of the head fast enough to smear the
## picture. 180 deg/s is a quick glance over the shoulder.
@export var vignette_on_turn: bool = true
@export var turn_threshold: float = 180.0

var _player: Node
var _material: ShaderMaterial
var _radius: float = 1.0
var _flash_color: Color = Color(0, 0, 0, 0)
var _flash_time: float = 0.0
var _flash_duration: float = 0.0
var _forced: bool = false
var _blink_time: float = 0.0
var _last_yaw: float = 0.0
var _has_last_yaw: bool = false

const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float radius : hint_range(0.0, 2.0) = 1.8;
uniform float feather : hint_range(0.01, 0.6) = 0.15;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_tint : source_color = vec4(0.9, 0.15, 0.1, 1.0);

void fragment() {
	// Distance from the centre of the quad, 0 at the middle, ~1 at the edge.
	float d = length(UV - vec2(0.5)) * 2.0;
	float vignette = smoothstep(radius - feather, radius + feather, d);
	vec4 color = mix(tint, flash_tint, flash_strength);
	// The flash also lights the periphery (from ~43 deg outward) even when the
	// vignette is fully open.
	float edge = smoothstep(0.55, 1.0, d) * flash_strength;
	ALBEDO = color.rgb;
	ALPHA = clamp(max(vignette, edge), 0.0, 1.0) * color.a;
}
"""


func _ready() -> void:
	add_to_group("comfort_vignette")

	var quad := QuadMesh.new()
	# Sized as an angle, not a distance -- see the header comment.
	quad.size = QUAD_SIZE
	mesh = quad
	position = Vector3(0.0, 0.0, -QUAD_DISTANCE)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Render after everything else so it always tints the final image.
	sorting_offset = 100.0

	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	material_override = _material

	Settings.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()


func _on_settings_changed() -> void:
	visible = Settings.comfort_vignette or _flash_time > 0.0


func _process(delta: float) -> void:
	var camera := get_parent() as Node3D
	var want_closed := _forced
	if _blink_time > 0.0:
		_blink_time -= delta
		want_closed = true

	# Only in a headset. On the desktop rig the camera is turned by the mouse,
	# which is not locomotion and has no vestibular mismatch to suppress.
	if camera != null and Settings.comfort_vignette and vignette_on_turn and _in_headset():
		var yaw := camera.global_rotation.y
		if _has_last_yaw:
			var rate := absf(rad_to_deg(angle_difference(_last_yaw, yaw))) / maxf(delta, 0.0001)
			if rate > turn_threshold:
				want_closed = true
		_last_yaw = yaw
		_has_last_yaw = true

	var goal := closed_radius if want_closed else open_radius
	var speed := close_speed if want_closed else open_speed
	_radius = move_toward(_radius, goal, speed * delta)
	_material.set_shader_parameter("radius", _radius)

	if _flash_time > 0.0:
		_flash_time -= delta
		var strength := clampf(_flash_time / maxf(_flash_duration, 0.0001), 0.0, 1.0)
		_material.set_shader_parameter("flash_strength", strength * 0.85)
		_material.set_shader_parameter("flash_tint", _flash_color)
		visible = true
	else:
		_material.set_shader_parameter("flash_strength", 0.0)
		visible = Settings.comfort_vignette or _forced
	# Turning the comfort vignette off turns off COMFORT. A forced close is not
	# comfort: it is the boundary warning that says the head is inside a wall
	# (see XRPlayer._check_head_inside), and that has to show whatever the
	# preference says -- the same way a guardian boundary does.
	if not Settings.comfort_vignette and not _forced:
		_radius = open_radius


## True only while a headset is actually driving the camera.
func _in_headset() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("xr_player") as Node
	if _player == null:
		return false
	return bool(_player.get("xr_active"))


## Hold the vignette closed until released.
func set_forced(value: bool) -> void:
	_forced = value


## Close the vignette briefly and let it reopen: used on every teleport so the
## jump is a soft "blink" rather than a full-field cut.
func blink(duration: float) -> void:
	if not Settings.comfort_vignette:
		return
	_blink_time = maxf(_blink_time, duration)
	_radius = minf(_radius, closed_radius + 0.2)


## Peripheral colour flash. Purely visual -- never moves the camera, because an
## uncommanded camera movement is the fastest route to simulator sickness in
## exactly the cohort this application is for.
func flash(color: Color, duration: float) -> void:
	_flash_color = color
	_flash_duration = duration
	_flash_time = duration
	visible = true
