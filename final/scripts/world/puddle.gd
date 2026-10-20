@tool
class_name Puddle
extends Node3D
## A spill on a hard floor: the bathroom's wet tile and the kitchen's spill.
##
## WHAT IT REPLACED, AND WHY.
## Both were a flat rounded box 10 mm thick, pale blue, 35% metallic, at 75%
## opacity. Every one of those choices fights what water actually is. Water is a
## dielectric, so metallic belongs at zero. It has almost no colour of its own at
## this depth, so a blue tint reads as plastic. Its edge is never straight, and a
## rectangle is the one shape a spill cannot make. And the thing that tells you a
## floor is wet, before you notice anything else, is not the water at all -- it
## is the dark halo of damp tile around it.
##
## So a puddle here is three things drawn together:
##
##   1. A FILM of water with an irregular outline, thinning to nothing at the
##      rim, almost colourless, almost perfectly smooth, carrying a ripple
##      normal map. Being smooth is what gives it the sharp reflection of the
##      ceiling light, which is the whole read at a glance.
##   2. A DAMP patch under and around it: the floor's own texture darkened, a
##      little rougher than dry tile. It extends past the water, because the
##      wet area always does.
##   3. A few DROPLETS thrown clear of the main body, which is what stops it
##      reading as one deliberate shape.
##
## The outline is generated from a superellipse so it fills most of its
## rectangle. That is not cosmetic: the scored footprint in the matching
## SlipZone is that rectangle, and a round blob inside a square footprint would
## mean being penalised on a corner of floor that looks dry.
##
## It never collides. A puddle is 3 mm of water; the hazard is that you slip on
## it, which SlipZone handles, not that you walk into it.

const TEX := "res://assets/textures/water_"

## Footprint of the water, in metres. The outline fills most of this.
@export var size: Vector2 = Vector2(1.7, 1.3): set = _set_size

## Changes the outline without changing anything else. Different value per
## puddle, or the bathroom and the kitchen have the same spill in them.
@export var shape_seed: int = 1: set = _set_seed

## How far the film stands proud of the floor. Millimetres: any more and the
## rim shows as a wall of water when you look across it.
@export var depth: float = 0.004

## 0 gives a perfectly even outline, 0.35 a very ragged one.
@export var raggedness: float = 0.20: set = _set_ragged

## How far the damp floor reaches beyond the water, in metres. Set to 0 for no
## damp ring at all.
##
## This started at 0.26 with a third of the floor's brightness taken out of it,
## and it swallowed the puddle whole -- the result read as something spilled a
## week ago and never cleaned up. It is a hint that the wet area extends past
## the water, nothing more.
@export var damp_margin: float = 0.10

## How much of the floor's brightness the damp ring takes out, at its darkest.
@export var damp_strength: float = 0.12

## Splashes thrown clear of the main body.
@export var droplets: int = 5

## Tint of the water itself.
##
## Physically a 3 mm film is nearly colourless and makes tile DARKER, and the
## first version of this was built that way. It was wrong for this house. On a
## white bathroom floor a colourless darker film reads as a stain, and the thing
## has to be found and pointed at by someone who may not see well. The pale
## cool tint the old slab used was a stylisation, but it was the right one: it
## says "water" at a glance and from across the room.
##
## Kept pale, but much darker than it was. The albedo TEXTURE is near-white
## (0.94 average), so a tint of 0.73-0.89 on top of it put the film at roughly
## 0.8 albedo -- brighter than the tile it sits on. A patch of floor brighter
## than the floor does not read as water; it reads as a light shining on the
## floor, which is exactly how it looked.
@export var water_tint: Color = Color(0.56, 0.66, 0.72, 1.0)

## Opacity of the film at its deepest. It thins to nothing at the rim whatever
## this is set to.
##
## Lower than it was for the same reason: the single strongest cue that a floor
## is wet is seeing the floor THROUGH the water, grout lines and all.
@export var opacity: float = 0.42

## Strength of the ripple normal map. Low: this is a puddle, not a pond.
##
## Raised, because it is what breaks the ceiling lamp into a few soft streaks
## instead of one hard dot. A single unbroken highlight on a flat film is the
## thing that reads as a lamp rather than as water.
@export var ripple_strength: float = 0.80

## Roughness of the film, used directly rather than multiplied by the water
## roughness map.
##
## The map is 0.02-0.06 everywhere. Multiplied into the old base of 0.04 it
## gave an effective roughness near 0.002 -- a perfect mirror, which with the
## ceiling lamp above it and glow at an HDR threshold of 1.05 (0.72 at night)
## produced a blown white spot. Still water in a lit room is smooth, but not
## mirror-smooth, and the highlight has to be a sheen rather than a point.
@export_range(0.02, 0.6, 0.01) var surface_roughness: float = 0.14

## How much the far edge brightens as you look across it.
##
## Godot's rim term is additive and keyed on the angle between the normal and
## the view. On a flat film seen by someone standing over it, that angle is
## grazing across almost the WHOLE puddle, not just its edge -- so this does
## not light a rim, it lights the lot. At the old value of 0.85 the puddle
## glowed. Low enough now to catch the far edge and nothing else.
@export_range(0.0, 1.0, 0.01) var rim_strength: float = 0.18

## How fast the surface drifts. A spill on a floor is still; this is just
## enough that the highlight is not nailed to one spot.
@export var drift: float = 0.012

const SEGMENTS := 72
const RIM_INSET := 0.80        # where the full-thickness body ends
const UPDATE_HZ := 20.0

var _water: MeshInstance3D
var _damp: MeshInstance3D
var _material: StandardMaterial3D
var _time: float = 0.0
var _accum: float = 0.0


func _ready() -> void:
	_rebuild()
	set_process(not Engine.is_editor_hint() and drift > 0.0)


func _process(delta: float) -> void:
	if _material == null:
		return
	# Updated at 20 Hz rather than every frame: nothing about a 3 mm film of
	# water needs 90 Hz, and this runs in every room the participant is not in.
	_accum += delta
	if _accum < 1.0 / UPDATE_HZ:
		return
	_time += _accum
	_accum = 0.0
	# A lissajous rather than a straight scroll. A constant drift in one
	# direction reads as a conveyor belt; two incommensurate periods read as
	# the surface settling.
	_material.uv1_offset = Vector3(
		sin(_time * 0.41) * drift,
		cos(_time * 0.27) * drift,
		0.0)


# ---------------------------------------------------------------------------
#  Geometry
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	for child in get_children():
		if child.is_in_group("puddle_visual"):
			child.free()
	_water = _spawn("Water", _build_water(), _water_material())
	if damp_margin > 0.001 and damp_strength > 0.001:
		_damp = _spawn("Damp", _build_damp(), _damp_material())


func _spawn(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.add_to_group("puddle_visual")
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Radius of the outline at angle `theta`, as a fraction of the half-extents.
##
## A superellipse (exponent 3) rather than a circle, so the shape fills most of
## its rectangle instead of rattling around inside it, modulated by three
## harmonics that are periodic in theta -- which is what keeps the outline
## closed with no seam where it wraps.
func _outline(theta: float, phase: PackedFloat32Array) -> Vector2:
	var c := cos(theta)
	var s := sin(theta)
	# Exponent 2.4: between an ellipse and a rounded rectangle. A true ellipse
	# leaves the corners of the footprint dry, and anything squarer reads as the
	# rounded box this replaced.
	var n := 2.4
	var ex := signf(c) * pow(absf(c), 2.0 / n)
	var ez := signf(s) * pow(absf(s), 2.0 / n)
	var wobble := (0.50 * sin(3.0 * theta + phase[0])
		+ 0.30 * sin(4.0 * theta + phase[1])
		+ 0.20 * sin(6.0 * theta + phase[2]))
	# Scaled so the result is never greater than 1: the outline stays inside the
	# declared footprint, which is also the scored one.
	var r := 1.0 - raggedness + raggedness * (wobble * 0.5 + 0.5)
	return Vector2(ex, ez) * r


## Derived arithmetically rather than drawn from an RNG, so the outline is
## identical in the engine and in the Python that measures it. tools/ needs to
## be able to work out how much of the scored footprint is actually under water,
## and it cannot do that if the shape depends on Godot's generator.
func _phases() -> PackedFloat32Array:
	var s := float(shape_seed)
	return PackedFloat32Array([
		fposmod(s * 0.6180339887 + 0.137, 1.0) * TAU,
		fposmod(s * 0.3819660113 + 0.724, 1.0) * TAU,
		fposmod(s * 0.7548776662 + 0.391, 1.0) * TAU,
	])


## The film: a fan to an inner ring at full thickness and full opacity, then a
## skirt out to the rim where it thins to nothing.
func _build_water() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var phase := _phases()
	_add_blob(st, Vector2.ZERO, half, phase, 0.0, depth)

	var rings := RandomNumberGenerator.new()
	rings.seed = shape_seed * 31 + 7
	for i in droplets:
		var ang := rings.randf() * TAU
		var reach := 1.0 + rings.randf_range(0.10, 0.55)
		var at := Vector2(cos(ang), sin(ang)) * half * reach
		var r := rings.randf_range(0.03, 0.075)
		# Each droplet is the same outline turned to a different angle, so they
		# are a family rather than five copies of one shape.
		_add_blob(st, at, Vector2(r, r * rings.randf_range(0.7, 1.3)), phase,
			rings.randf() * TAU, depth * 0.55)

	st.generate_tangents()
	return st.commit()


func _add_blob(st: SurfaceTool, centre: Vector2, half: Vector2,
		phase: PackedFloat32Array, spin: float, thickness: float) -> void:
	var inner: Array[Vector2] = []
	var outer: Array[Vector2] = []
	for i in SEGMENTS:
		var theta := TAU * float(i) / float(SEGMENTS)
		var unit := _outline(theta + spin, phase)
		outer.append(centre + unit * half)
		inner.append(centre + unit * half * RIM_INSET)

	var mid := Vector3(centre.x, thickness, centre.y)
	for i in SEGMENTS:
		var j := (i + 1) % SEGMENTS
		var a := Vector3(inner[i].x, thickness, inner[i].y)
		var b := Vector3(inner[j].x, thickness, inner[j].y)
		_tri(st, mid, b, a, 1.0, 1.0, 1.0)
		var c := Vector3(outer[i].x, thickness * 0.35, outer[i].y)
		var d := Vector3(outer[j].x, thickness * 0.35, outer[j].y)
		_tri(st, a, b, d, 1.0, 1.0, 0.0)
		_tri(st, a, d, c, 1.0, 0.0, 0.0)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		aa: float, ab: float, ac: float) -> void:
	_vert(st, a, aa)
	_vert(st, b, ab)
	_vert(st, c, ac)


## UVs come straight from the local XZ position, so one tile of the ripple map
## covers a fixed number of metres however big the puddle is.
func _vert(st: SurfaceTool, p: Vector3, alpha: float) -> void:
	st.set_normal(Vector3.UP)
	st.set_color(Color(1.0, 1.0, 1.0, alpha))
	st.set_uv(Vector2(p.x, p.z))
	st.add_vertex(p)


## The damp floor beyond the water: a RING, not a disc.
##
## The first version filled the whole shape and the result was a flat grey
## saucer with a puddle somewhere inside it -- the halo swamped the thing it was
## supposed to frame. Under the water the darkening is the water's own job (the
## film is tinted and partly opaque); what this layer is for is the margin of
## wet tile that always extends past the edge of a spill, and which is usually
## the first thing you actually notice about a wet floor.
##
## So it is transparent where the water is, rises just outside the waterline,
## and fades out at `damp_margin`.
func _build_damp() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water_half := size * 0.5
	var outer_half := water_half + Vector2(damp_margin, damp_margin)
	var peak_half := water_half + Vector2(damp_margin, damp_margin) * 0.30
	var phase := _phases()
	var inside: Array[Vector2] = []
	var peak: Array[Vector2] = []
	var outside: Array[Vector2] = []
	for i in SEGMENTS:
		var theta := TAU * float(i) / float(SEGMENTS)
		var unit := _outline(theta, phase)
		inside.append(unit * water_half * 0.90)
		peak.append(unit * peak_half)
		outside.append(unit * outer_half)

	var y := 0.0005
	for i in SEGMENTS:
		var j := (i + 1) % SEGMENTS
		var a := Vector3(inside[i].x, y, inside[i].y)
		var b := Vector3(inside[j].x, y, inside[j].y)
		var c := Vector3(peak[i].x, y, peak[i].y)
		var d := Vector3(peak[j].x, y, peak[j].y)
		var e := Vector3(outside[i].x, y, outside[i].y)
		var f := Vector3(outside[j].x, y, outside[j].y)
		_tri(st, a, b, d, 0.35, 0.35, 1.0)
		_tri(st, a, d, c, 0.35, 1.0, 1.0)
		_tri(st, c, d, f, 1.0, 1.0, 0.0)
		_tri(st, c, f, e, 1.0, 0.0, 0.0)
	return st.commit()


# ---------------------------------------------------------------------------
#  Materials
# ---------------------------------------------------------------------------

func _water_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Both meshes are flat films seen from above, so there is nothing to gain
	# from back-face culling and a winding mistake would make them invisible
	# rather than merely wrong. Normals are set explicitly, so lighting is
	# unaffected either way.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Both layers are transparent and nearly coplanar, so distance sorting is
	# unreliable between them. Priority decides it outright.
	m.render_priority = 1
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(water_tint.r, water_tint.g, water_tint.b, opacity)
	# Dielectric. The old slab was 35% metallic, which is why it read as a sheet
	# of painted plastic rather than as water.
	m.metallic = 0.0
	m.roughness = surface_roughness
	# metallic_specular, not specular: the Godot 3 name is silently remapped and
	# then dropped, which the engine log reports and nothing else does.
	#
	# 0.5 is the dielectric default (F0 = 0.04), which is what water is. The old
	# 0.55 pushed the highlight above the glow threshold on its own.
	m.metallic_specular = 0.5
	# A rim term stands in for Fresnel: water goes brighter at a grazing angle,
	# and this is what makes the far edge of a puddle catch the light. See
	# `rim_strength` for why it has to stay small on a horizontal surface.
	m.rim_enabled = rim_strength > 0.001
	m.rim = rim_strength
	# Tinted towards the surface colour rather than towards white: a white rim
	# on a pale film is a glare, a tinted one is a reflection.
	m.rim_tint = 0.6
	# One tile of the ripple map per `metres`, read from the manifest.
	var metres: float = Surfaces.metres("water")
	m.uv1_scale = Vector3(1.0 / metres, 1.0 / metres, 1.0)

	var albedo := _tex("albedo")
	if albedo != null:
		m.albedo_texture = albedo
	# The roughness map is deliberately NOT used. Godot multiplies it into
	# `roughness`, and this one is 0.02-0.06 everywhere, so any base value is
	# driven to a mirror. The ripple normal map supplies the variation instead.
	var normal := _tex("normal")
	if normal != null:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = ripple_strength
	_material = m
	return m


func _damp_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.vertex_color_use_as_albedo = true
	# Near-black at low opacity: it DARKENS the floor's own texture rather than
	# covering it, which is what damp tile looks like. A grey decal would hide
	# the grout lines and read as a sticker.
	m.albedo_color = Color(0.10, 0.11, 0.12, clampf(damp_strength, 0.0, 1.0))
	m.metallic = 0.0
	m.roughness = 0.22
	m.metallic_specular = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 0
	return m


func _tex(suffix: String) -> Texture2D:
	var path := "%s%s.png" % [TEX, suffix]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# ---------------------------------------------------------------------------
#  Editor setters
# ---------------------------------------------------------------------------

func _set_size(value: Vector2) -> void:
	size = value
	if is_inside_tree():
		_rebuild()


func _set_seed(value: int) -> void:
	shape_seed = value
	if is_inside_tree():
		_rebuild()


func _set_ragged(value: float) -> void:
	raggedness = clampf(value, 0.0, 0.45)
	if is_inside_tree():
		_rebuild()
