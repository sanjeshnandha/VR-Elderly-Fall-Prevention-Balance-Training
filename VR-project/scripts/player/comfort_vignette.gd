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

## Radius of the clear centre, 0..1 of the quad. Smaller = stronger tunnelling.
@export var open_radius: float = 1.0
@export var closed_radius: float = 0.42

## How quickly the vignette closes and reopens, in radius units per second.
@export var close_speed: float = 6.0
@export var open_speed: float = 2.5

## Yaw rate, in degrees per second, above which the vignette starts to close.
@export var turn_threshold: float = 45.0

var _material: ShaderMaterial
var _radius: float = 1.0
var _flash_color: Color = Color(0, 0, 0, 0)
var _flash_time: float = 0.0
var _flash_duration: float = 0.0
var _forced: bool = false
var _last_yaw: float = 0.0

const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float radius : hint_range(0.0, 1.5) = 1.0;
uniform float feather : hint_range(0.01, 0.6) = 0.25;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_tint : source_color = vec4(0.9, 0.15, 0.1, 1.0);

void fragment() {
	// Distance from the centre of the quad, 0 at the middle, ~1 at the edge.
	float d = length(UV - vec2(0.5)) * 2.0;
	float vignette = smoothstep(radius - feather, radius + feather, d);
	vec4 color = mix(tint, flash_tint, flash_strength);
	// The flash also lights the periphery even when the vignette is fully open.
	float edge = smoothstep(0.55, 1.0, d) * flash_strength;
	ALBEDO = color.rgb;
	ALPHA = clamp(max(vignette, edge), 0.0, 1.0) * color.a;
}
"""


func _ready() -> void:
	add_to_group("comfort_vignette")

	var quad := QuadMesh.new()
	# Sized and placed to overfill the field of view at 6 cm from the eyes.
	quad.size = Vector2(2.4, 2.0)
	mesh = quad
	position = Vector3(0.0, 0.0, -0.06)
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

	if camera != null and Settings.comfort_vignette:
		var yaw := camera.global_rotation.y
		var rate := absf(rad_to_deg(angle_difference(_last_yaw, yaw))) / maxf(delta, 0.0001)
		_last_yaw = yaw
		if rate > turn_threshold:
			want_closed = true

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
		visible = Settings.comfort_vignette


## Hold the vignette closed, e.g. while a teleport arc is being aimed.
func set_forced(value: bool) -> void:
	_forced = value


## Peripheral colour flash. Purely visual -- never moves the camera, because an
## uncommanded camera movement is the fastest route to simulator sickness in
## exactly the cohort this application is for.
func flash(color: Color, duration: float) -> void:
	_flash_color = color
	_flash_duration = duration
	_flash_time = duration
	visible = true
