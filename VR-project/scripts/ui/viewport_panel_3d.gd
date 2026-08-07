class_name ViewportPanel3D
extends Node3D
## Architectural Fix 5.3, UI half -- a 2D Control rendered onto a quad in 3D.
##
## This is a dependency-free stand-in for `XRToolsViewport2Din3D`. If you have
## godot-xr-tools installed you can swap in that node instead; the debrief
## Control is a plain `Control` scene and does not care which one renders it.
##
## WHY A WORLD-SPACE PANEL AND NOT A HUD
## -------------------------------------
## A screen-space overlay in VR sits at infinity and cannot be focused on. VR
## lenses are ground for a fixed focal distance of roughly 1.5-2.0 m; text
## nearer than that forces an accommodation the eye cannot make, and for a
## presbyopic user -- effectively everyone over about 50 -- it is simply
## unreadable. So the panel is a real object placed in that focal band.
##
## The defaults below are the accessibility contract for every panel in this
## project:
##   * 1.75 m from the user (inside the 1.5-2.0 m comfort band)
##   * placed slightly BELOW eye level: sustained upward gaze is uncomfortable
##     and, for users with bifocals, the wrong part of the lens
##   * dark grey background, yellow/white text, no pure black or pure white
##   * a large viewport downscaled onto a large quad, so text is supersampled
##     and stays crisp through the lens

## Metres from the participant's eyes. Keep inside 1.5-2.0.
@export_range(1.0, 3.0, 0.05) var view_distance: float = 1.75

## Physical size of the panel in metres. 1.2 x 0.9 m at 1.75 m subtends roughly
## 38 degrees -- comfortably inside the sweet spot of the lens.
@export var panel_size: Vector2 = Vector2(1.2, 0.9)

## Viewport resolution. High relative to the panel size so text is supersampled.
@export var viewport_size: Vector2i = Vector2i(1600, 1200)

## The Control scene to render. Must have `anchors_preset = Full Rect`.
@export var content_scene: PackedScene

## Follow the participant: keep the panel at `view_distance`, facing them.
@export var follow_player: bool = false

## Degrees below eye level to sit when following.
@export var follow_pitch_down: float = 8.0

var content: Control
var viewport: SubViewport

var _quad: MeshInstance3D
var _player: XRPlayer


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = viewport_size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# 2D UI in a 3D world: disable 3D rendering in the subviewport entirely.
	viewport.disable_3d = true
	viewport.gui_embed_subwindows = true
	add_child(viewport)

	if content_scene != null:
		content = content_scene.instantiate() as Control
		if content != null:
			viewport.add_child(content)
			content.set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_quad()

	if follow_player:
		_player = get_tree().get_first_node_in_group("xr_player") as XRPlayer
		set_process(true)
	else:
		set_process(false)


func _build_quad() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "PanelQuad"
	var quad := QuadMesh.new()
	quad.size = panel_size
	_quad.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = viewport.get_texture()
	# Unshaded: room lighting must never dim the debrief text.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Linear filtering + mipmaps; nearest filtering shimmers badly under the
	# constant micro-motion of a head-mounted display.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_quad.material_override = mat

	add_child(_quad)


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("xr_player") as XRPlayer
		return

	var head := _player.head_position()
	var forward := -_player.head_basis().z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()

	var drop := tan(deg_to_rad(follow_pitch_down)) * view_distance
	global_position = head + forward * view_distance - Vector3(0.0, drop, 0.0)
	look_at(head, Vector3.UP)
	# QuadMesh faces +Z; look_at points -Z at the target, so spin 180 degrees.
	rotate_object_local(Vector3.UP, PI)


## Place the panel once, in front of wherever the participant is now, then stop
## following. Used for the debrief so the panel stays put and can be examined.
func place_in_front_of_player() -> void:
	_player = get_tree().get_first_node_in_group("xr_player") as XRPlayer
	if _player == null:
		return
	set_process(true)
	await get_tree().process_frame
	_process(0.0)
	set_process(false)
