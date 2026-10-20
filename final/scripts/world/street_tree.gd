@tool
class_name StreetTree
extends Node3D
## A street tree, and the limb of it that hangs over the pavement.
##
## WHY THIS EXISTS
##
## The low-branch hazard was two boxes floating in mid-air at head height with
## nothing above them: a stick and a green blob, hanging in the sky over the
## pavement. Reported, reasonably, as "what is this? why is it flying?".
##
## A branch is not a prop. It is the lowest limb of something, and without the
## something the participant is not being asked to spot an overhanging branch --
## they are being asked to work out what they are even looking at. So the tree
## is modelled: a trunk out of the grass, limbs off it, a canopy, and ONE low
## limb that reaches out over the walking line at head height. That limb is the
## hazard, and now it is attached to the thing it grew from.
##
## The node sits at the BASE OF THE TRUNK, on the ground, so nothing it builds
## can float: every part is measured up from there.
##
## Named meshes: "Trunk" (trunk and the ordinary limbs), "Canopy", "LowLimb"
## and "LowLimbLeaves" -- the last two being what the hazard lights up.

## Overall height to the top of the canopy.
@export var height: float = 4.6

## Trunk radius at the ground. It tapers to 60 % of this at the crown.
@export var trunk_radius: float = 0.17

## Trees are not plumb.
@export var lean_degrees: float = 4.0

## Ordinary limbs, which exist so the low one does not look like the only one.
@export var limbs: int = 5

## Where the low limb REACHES, relative to this node: the far end of it, which
## is the bit at head height over the pavement. The limb is drawn from the
## trunk to here, so moving this swings the branch rather than detaching it.
@export var low_limb_to: Vector3 = Vector3(0.85, 1.92, 1.75)

## Radius of the low limb at the trunk.
@export var low_limb_radius: float = 0.065

## Radius of the leaf cluster on the end of the low limb.
@export var leaf_cluster: float = 0.42

## The crown.
@export var canopy_blobs: int = 9
@export var canopy_radius: float = 1.45
## Crowns are wider than they are deep.
@export var canopy_flatten: float = 0.72

@export var shape_seed: int = 1

@export var bark_surface: String = "walnut_wood"
@export var bark_color: Color = Color(0.34, 0.27, 0.21, 1.0)
@export var leaf_surface: String = "foliage"
@export var leaf_color: Color = Color(0.31, 0.45, 0.26, 1.0)

## Rebuild now (editor button).
##
## The shape properties above have no setters on purpose. A setter that does
## not assign its own property silently throws the scene's value away -- the
## first draft of this file had one shared setter for all of them, and every
## export would have stayed at its default no matter what the scene said. The
## values are applied before _ready() either way, so the only thing lost is
## live updating in the editor, and this button covers that.
@export var rebuild: bool = false: set = _set_rebuild

const GROUP := "tree_part"
## Sides on a trunk or a limb. Eight is plenty at this distance and keeps the
## whole tree well under a thousand triangles.
const SIDES := 8
const BLOB_RINGS := 6


func _ready() -> void:
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

	var bark := AutoShape.make_material(bark_color, 0.86, 0.0, bark_surface)
	var leaf := AutoShape.make_material(leaf_color, 0.72, 0.0, leaf_surface)

	_spawn("Trunk", _trunk_mesh(), bark)
	_spawn("Canopy", _canopy_mesh(), leaf)
	_spawn("LowLimb", _low_limb_mesh(), bark)
	_spawn("LowLimbLeaves", _low_leaves_mesh(), leaf)


func _spawn(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.add_to_group(GROUP)
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)
	return mi


## Where the trunk is at height `y`, allowing for the lean.
func _trunk_at(y: float) -> Vector3:
	var lean := deg_to_rad(lean_degrees)
	return Vector3(sin(lean) * y, y, 0.0)


func _crown_centre() -> Vector3:
	return _trunk_at(height * 0.70)


func _trunk_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := height * 0.78
	# Four segments up the trunk, each a little narrower than the last: a
	# single cylinder reads as a drainpipe.
	var steps := 4
	for i in steps:
		var y0 := top * float(i) / float(steps)
		var y1 := top * float(i + 1) / float(steps)
		var r0 := trunk_radius * lerpf(1.0, 0.6, float(i) / float(steps))
		var r1 := trunk_radius * lerpf(1.0, 0.6, float(i + 1) / float(steps))
		_limb(st, _trunk_at(y0), _trunk_at(y1), r0, r1)

	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed * 2749 + 5
	var crown := _crown_centre()
	for i in maxi(limbs, 0):
		var a := TAU * float(i) / float(maxi(limbs, 1)) + rng.randf_range(-0.3, 0.3)
		var from := _trunk_at(height * rng.randf_range(0.42, 0.68))
		var reach := canopy_radius * rng.randf_range(0.55, 0.95)
		var to := Vector3(crown.x + cos(a) * reach,
			crown.y + rng.randf_range(-0.25, 0.55),
			crown.z + sin(a) * reach)
		_limb(st, from, to, trunk_radius * 0.42, trunk_radius * 0.22)
	st.index()
	return st.commit()


## The one that matters: out of the trunk, over the wall, to head height above
## the pavement. Drawn in two lengths so it bends on the way, the way a limb
## that has grown out towards the light does.
func _low_limb_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var from := _trunk_at(maxf(low_limb_to.y - 0.55, 0.4))
	var mid := from.lerp(low_limb_to, 0.55) + Vector3(0.0, 0.16, 0.0)
	_limb(st, from, mid, low_limb_radius, low_limb_radius * 0.78)
	_limb(st, mid, low_limb_to, low_limb_radius * 0.78, low_limb_radius * 0.55)
	st.index()
	return st.commit()


func _low_leaves_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed * 6271 + 11
	# Three overlapping clumps along the outer third of the limb, so the thing
	# the participant has to duck is leaves rather than a bare stick.
	for i in 3:
		var t := 0.62 + 0.19 * float(i)
		var from := _trunk_at(maxf(low_limb_to.y - 0.55, 0.4))
		var at := from.lerp(low_limb_to, t)
		_blob(st, at + Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.06, 0.1),
			rng.randf_range(-0.12, 0.12)), leaf_cluster * rng.randf_range(0.7, 1.05))
	st.index()
	return st.commit()


func _canopy_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed * 15485 + 3
	var crown := _crown_centre()
	for i in maxi(canopy_blobs, 1):
		var a := TAU * float(i) / float(maxi(canopy_blobs, 1)) + rng.randf_range(-0.4, 0.4)
		var out := canopy_radius * rng.randf_range(0.0, 0.85)
		var at := crown + Vector3(cos(a) * out,
			rng.randf_range(-0.2, 1.0) * canopy_flatten, sin(a) * out)
		_blob(st, at, canopy_radius * rng.randf_range(0.46, 0.72))
	st.index()
	return st.commit()


# ---------------------------------------------------------------------------
#  Primitives
# ---------------------------------------------------------------------------

## A tapered limb from `from` to `to`. Built by hand rather than from a
## CylinderMesh so that the two ends can have different radii and so that the
## whole tree is one mesh per material.
func _limb(st: SurfaceTool, from: Vector3, to: Vector3, r0: float, r1: float) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 0.001:
		return
	var y := axis / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	for i in SIDES:
		var a0 := TAU * float(i) / float(SIDES)
		var a1 := TAU * float(i + 1) / float(SIDES)
		var d0 := x * cos(a0) + z * sin(a0)
		var d1 := x * cos(a1) + z * sin(a1)
		var p00 := from + d0 * r0
		var p10 := from + d1 * r0
		var p01 := to + d0 * r1
		var p11 := to + d1 * r1
		_tri(st, p00, p01, p11, d0)
		_tri(st, p00, p11, p10, d0)


## A rough sphere, for foliage.
func _blob(st: SurfaceTool, at: Vector3, r: float) -> void:
	for ring in BLOB_RINGS:
		var t0 := PI * float(ring) / float(BLOB_RINGS)
		var t1 := PI * float(ring + 1) / float(BLOB_RINGS)
		for i in SIDES:
			var a0 := TAU * float(i) / float(SIDES)
			var a1 := TAU * float(i + 1) / float(SIDES)
			var p00 := _on_sphere(at, r, t0, a0)
			var p01 := _on_sphere(at, r, t1, a0)
			var p11 := _on_sphere(at, r, t1, a1)
			var p10 := _on_sphere(at, r, t0, a1)
			_tri(st, p00, p01, p11, (p00 - at).normalized())
			_tri(st, p00, p11, p10, (p00 - at).normalized())


func _on_sphere(at: Vector3, r: float, theta: float, phi: float) -> Vector3:
	return at + Vector3(sin(theta) * cos(phi), cos(theta) * canopy_flatten,
		sin(theta) * sin(phi)) * r


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() > 0.000001:
		n = n.normalized()
	else:
		n = normal
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(p.x, p.y))
		st.add_vertex(p)
