@tool
class_name LeafLitter
extends Node3D
## A drift of wet leaves on the pavement: individual leaves, not a brown box.
##
## WHY THIS IS NOT A BOX
##
## It was: 1.5 x 0.75 m, 20 mm thick, flat brown, 25 % metallic. At that size a
## single colour has nothing in it for the eye to catch, so it read as a stain
## painted on the paving -- and a stain is not a hazard anybody recognises.
## Wet leaves are one of the two or three things that actually put older people
## on the ground, and the whole exercise is spotting them before stepping on
## them, so they have to look like leaves.
##
## What makes a leaf drift read is not detail in any one leaf. It is that there
## are a hundred of them, all slightly different: different lengths, different
## yaw, lying at slightly different angles with their edges curled up, in half a
## dozen browns and ochres, piled deeper in the middle and thinning to singles
## at the edge. All of that is cheap -- it is one mesh, built once.
##
## The node sits ON the paving surface, so local y = 0 is the ground.
##
## MESH. Every leaf is a flat polygon about its own midrib, with the edges
## lifted slightly so they catch the light the way a curled leaf does, merged
## into ONE MeshInstance3D named "Leaves". A dark mulch patch underneath stops
## bright paving showing through the gaps where the drift is thickest.

## Footprint of the drift (metres, x by z).
@export var size: Vector2 = Vector2(1.5, 0.75): set = _set_size

## How many leaves. Ninety is enough to read as a drift at walking pace; the
## cost is one mesh either way.
@export var leaves: int = 110: set = _set_leaves

## Change this for a different drift of the same size.
@export var shape_seed: int = 3: set = _set_seed

## Length of an average leaf, before the per-leaf size variation.
@export var leaf_length: float = 0.105

## Width as a fraction of length.
@export var leaf_width: float = 0.62

## How much the edges of a leaf curl up. Small, but it is what stops a hundred
## flat polygons reading as one flat polygon.
@export var curl: float = 0.012

## How deep the drift piles in the middle.
@export var pile: float = 0.035

## Leaves are not all one colour, and a drift that is loses all its texture.
@export var palette: Array[Color] = [
	Color(0.44, 0.30, 0.15), Color(0.55, 0.38, 0.17), Color(0.36, 0.24, 0.13),
	Color(0.49, 0.33, 0.21), Color(0.33, 0.29, 0.16), Color(0.58, 0.44, 0.22),
	Color(0.28, 0.19, 0.12), Color(0.51, 0.27, 0.14),
]

## Wet leaves are dark and shiny; dry ones are pale and matt. This is the one
## control that turns one into the other.
@export_range(0.0, 1.0) var wetness: float = 0.75

## The mulch patch under the drift: the packed-down layer that has been there
## longest. Set `mulch` false for a fresh fall with paving showing through.
##
## Keep it SMALL and LIGHT. Drawn at full size in the drift's own browns it is
## a dark blob with a hard edge -- which is to say, it is the brown box this
## node replaced, with leaves sprinkled on it. At 0.7 of the drift and a few
## shades off the wet paving it does its one job, which is to stop clean dry
## paving showing through the middle of the pile, and the leaves carry the rest.
@export var mulch: bool = true
@export_range(0.2, 1.0) var mulch_scale: float = 0.70
@export var mulch_color: Color = Color(0.33, 0.28, 0.21, 1.0)

## Rebuild now (editor button).
@export var rebuild: bool = false: set = _set_rebuild

const GROUP := "leaf_visual"
## Samples along one side of a leaf outline. Seven is enough for a leaf shape.
const RIB_SAMPLES := 7


func _ready() -> void:
	build()


func _set_size(value: Vector2) -> void:
	size = value
	if is_inside_tree():
		build()


func _set_leaves(value: int) -> void:
	leaves = maxi(value, 0)
	if is_inside_tree():
		build()


func _set_seed(value: int) -> void:
	shape_seed = value
	if is_inside_tree():
		build()


func _set_rebuild(_value: bool) -> void:
	rebuild = false
	if is_inside_tree():
		build()


# ---------------------------------------------------------------------------
#  Building it
# ---------------------------------------------------------------------------

func build() -> void:
	for child in get_children():
		if child.is_in_group(GROUP):
			child.free()
	if mulch:
		_spawn("Mulch", _mulch_mesh(), _mulch_material())
	_spawn("Leaves", _leaf_mesh(), _leaf_material())


func _spawn(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.add_to_group(GROUP)
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## How thick the drift is at a point, 0 at the edge and 1 in the middle. Also
## used as the probability of a leaf being accepted there, which is what makes
## the drift thin out instead of stopping at a hard line.
func _density(u: float, v: float) -> float:
	var r := sqrt(u * u + v * v)
	return clampf(1.0 - r * r, 0.0, 1.0)


func _leaf_mesh() -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed * 7919 + 13
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var placed := 0
	var tries := 0
	while placed < leaves and tries < leaves * 40:
		tries += 1
		var u := rng.randf_range(-1.0, 1.0)
		var v := rng.randf_range(-1.0, 1.0)
		var d := _density(u, v)
		if d <= 0.0 or rng.randf() > 0.25 + 0.75 * d:
			continue
		placed += 1
		_add_leaf(st, rng, u, v, d)

	st.generate_normals()
	st.index()
	return st.commit()


## One leaf, lying where it fell.
func _add_leaf(st: SurfaceTool, rng: RandomNumberGenerator, u: float, v: float,
		d: float) -> void:
	var centre := Vector3(u * size.x * 0.5, 0.0, v * size.y * 0.5)
	# Deeper in the middle, and each leaf sits a little proud of the last so
	# they overlap rather than z-fight.
	centre.y = 0.001 + pile * d * rng.randf_range(0.25, 1.0)

	var length := leaf_length * rng.randf_range(0.72, 1.28)
	var width := length * leaf_width * rng.randf_range(0.85, 1.15)
	var yaw := rng.randf_range(0.0, TAU)
	# A leaf on a pile lies on whatever is under it, never flat.
	var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.22, 0.22)) \
		* Basis(Vector3.BACK, rng.randf_range(-0.22, 0.22))
	var spin := Basis(Vector3.UP, yaw)
	var colour: Color = palette[rng.randi_range(0, palette.size() - 1)]
	# The ones lower in the pile are wetter, darker and have had longer to rot.
	colour = colour.darkened(clampf(0.35 * (1.0 - rng.randf()) * wetness, 0.0, 0.4))

	# Outline: half-widths along the midrib, widest at about 45 % of the way up,
	# with a drawn-out tip. A leaf, rather than an oval.
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in RIB_SAMPLES:
		var t := float(i) / float(RIB_SAMPLES - 1)
		var half := width * 0.5 * pow(sin(PI * pow(t, 0.78)), 0.85)
		var lift := curl * (1.0 - cos(TAU * t)) * 0.5
		var along := (t - 0.42) * length
		left.append(Vector3(-half, lift + curl * half / maxf(width, 0.001), along))
		right.append(Vector3(half, lift + curl * half / maxf(width, 0.001), along))

	var basis := spin * tilt

	# Two strips, midrib to each edge. The midrib stays low so the leaf dishes.
	for i in RIB_SAMPLES - 1:
		var t0 := float(i) / float(RIB_SAMPLES - 1)
		var t1 := float(i + 1) / float(RIB_SAMPLES - 1)
		var rib0 := centre + basis * Vector3(0.0, 0.0, (t0 - 0.42) * length)
		var rib1 := centre + basis * Vector3(0.0, 0.0, (t1 - 0.42) * length)
		var l0 := centre + basis * left[i]
		var l1 := centre + basis * left[i + 1]
		var r0 := centre + basis * right[i]
		var r1 := centre + basis * right[i + 1]
		_tri(st, colour, rib0, l0, l1)
		_tri(st, colour, rib0, l1, rib1)
		_tri(st, colour, rib0, r1, r0)
		_tri(st, colour, rib0, rib1, r1)


func _tri(st: SurfaceTool, colour: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	for p in [a, b, c]:
		st.set_color(colour)
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)


## The packed layer underneath: an irregular dark patch, so the gaps between
## leaves are mulch rather than clean paving.
func _mulch_mesh() -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed * 104729 + 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 40
	var radii: Array[float] = []
	for i in segments:
		radii.append(rng.randf_range(0.78, 1.0))
	var centre := Vector3(0.0, 0.0005, 0.0)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var r0: float = radii[i]
		var r1: float = radii[(i + 1) % segments]
		var half := size * 0.5 * mulch_scale
		var p0 := Vector3(cos(a0) * r0 * half.x, 0.0005, sin(a0) * r0 * half.y)
		var p1 := Vector3(cos(a1) * r1 * half.x, 0.0005, sin(a1) * r1 * half.y)
		_tri(st, mulch_color, centre, p1, p0)
	st.generate_normals()
	st.index()
	return st.commit()


func _leaf_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	# Wet leaves are dark and shiny. Dry ones are pale and matt.
	mat.roughness = lerpf(0.85, 0.22, wetness)
	mat.metallic = 0.0
	mat.metallic_specular = lerpf(0.4, 0.85, wetness)
	# Leaves lie at every angle, so some of them show their backs.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _mulch_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = lerpf(0.9, 0.35, wetness)
	mat.metallic_specular = lerpf(0.35, 0.7, wetness)
	return mat
