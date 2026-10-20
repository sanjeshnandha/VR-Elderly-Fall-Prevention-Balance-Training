@tool
class_name MeshKit
extends RefCounted
## Procedural meshes with filleted edges.
##
## A sharp-cornered box is the clearest signal that a scene is a blockout:
## nothing in a real room has a perfectly sharp arris. Every prop in the house
## therefore gets a small fillet -- 15 to 25 mm, the same as real furniture --
## which costs a few hundred triangles and does more for realism than any
## amount of texture detail.
##
## The fillet is exact, not eyeballed. For a point p on the surface of the outer
## box, with e = half_size - radius:
##
##     q   = clamp(p, -e, e)      the nearest point on the inner box
##     n   = normalize(p - q)     the true surface normal
##     out = q + n * radius
##
## On a face p - q is axis-aligned, so the face stays perfectly FLAT -- a table
## top is still a table top. Along an edge the same expression sweeps a quarter
## cylinder; at a corner, an octant of a sphere. Sampling the outer box at
## e + radius * tan(theta) places the samples at equal angles around those arcs,
## so two segments per 45 degrees already reads as round.
##
## Neighbouring faces evaluate the same projection for the vertices they share,
## so the patches meet exactly: same position, same normal, no crack.
##
## The UVs are per-face planar, which is all that is needed: the materials in
## Surfaces use world-space triplanar mapping and take their texture coordinates
## from the world position, not from these. What the UVs ARE used for is
## generating the tangent frame the normal maps need -- see the note at the end
## of rounded_box().
##
## WINDING. Godot treats CLOCKWISE triangles as front-facing. If every filleted
## prop in the house turns out inside-out on the first run -- you can see
## through the near side of a table and the far side is lit wrongly -- then this
## assumption is the culprit and flipping WINDING_CW below fixes all of them at
## once. Setting Prop.corner_radius to 0 falls back to Godot's own BoxMesh and
## sidesteps this file entirely.

## Godot's front faces are clockwise. See the note above.
const WINDING_CW := true

## Quads per 45 degrees of fillet. Two is enough at furniture scale.
const DEFAULT_SEGMENTS := 2

## Below this the fillet is not worth the triangles.
const MIN_RADIUS := 0.0005


## A box of `size` with every edge filleted by `radius` metres.
static func rounded_box(size: Vector3, radius: float = 0.018,
		segments: int = DEFAULT_SEGMENTS) -> Mesh:
	var full := size.abs()
	var half := full * 0.5
	var smallest := minf(half.x, minf(half.y, half.z))
	var r := clampf(radius, 0.0, smallest * 0.95)

	if r <= MIN_RADIUS or smallest <= 0.002:
		var box := BoxMesh.new()
		box.size = full
		return box

	var seg := clampi(segments, 1, 6)
	var e := Vector3(
		maxf(half.x - r, 0.0),
		maxf(half.y - r, 0.0),
		maxf(half.z - r, 0.0))

	# Deliberately an UNTYPED array with the element type asserted where it is
	# read, rather than `var samples: Array[PackedFloat32Array] = [...]`. A typed
	# array declared from a literal of function calls is the same trap that broke
	# the architrave in room_builder.gd: it compiles and then fails at runtime.
	var samples := [
		_axis_samples(half.x, e.x, r, seg),
		_axis_samples(half.y, e.y, r, seg),
		_axis_samples(half.z, e.z, r, seg),
	]

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	for axis in 3:
		# In-plane axes, chosen so that unit(a) x unit(b) == unit(axis).
		var a := (axis + 1) % 3
		var b := (axis + 2) % 3
		var sa: PackedFloat32Array = samples[a]
		var sb: PackedFloat32Array = samples[b]
		var na := sa.size()
		var nb := sb.size()
		var span_a := maxf(_component(full, a), 0.001)
		var span_b := maxf(_component(full, b), 0.001)
		var half_a := _component(half, a)
		var half_b := _component(half, b)

		for side_index in 2:
			var side := 1.0 if side_index == 0 else -1.0
			var base := verts.size()

			for i in na:
				for j in nb:
					var p := _point(axis, _component(half, axis) * side, sa[i], sb[j])
					var q := Vector3(
						clampf(p.x, -e.x, e.x),
						clampf(p.y, -e.y, e.y),
						clampf(p.z, -e.z, e.z))
					var d := p - q
					var n := _unit(axis) * side
					if d.length_squared() > 1e-12:
						n = d.normalized()
					verts.append(q + n * r)
					norms.append(n)
					uvs.append(Vector2(
						(sa[i] + half_a) / span_a,
						(sb[j] + half_b) / span_b))

			for i in na - 1:
				for j in nb - 1:
					var v00 := base + i * nb + j
					var v01 := v00 + 1            # +b
					var v10 := v00 + nb           # +a
					var v11 := v10 + 1            # +a +b
					var outward_is_positive := side > 0.0
					if not WINDING_CW:
						outward_is_positive = not outward_is_positive
					if outward_is_positive:
						idx.append_array([v00, v11, v10, v00, v01, v11])
					else:
						idx.append_array([v00, v10, v11, v00, v11, v01])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# TANGENTS ARE NOT OPTIONAL. A normal map needs a full tangent frame, and
	# Godot's own words on it are: "The mesh must have both normals and tangents
	# defined in its vertex data. Otherwise, the normal map won't render
	# correctly and will only appear to darken the whole surface." Godot's
	# built-in BoxMesh supplies them; an ArrayMesh built by hand does not, so
	# without this every filleted prop in the house would come out muddy rather
	# than textured. SurfaceTool generates them from the normals and UVs above,
	# which keeps the handedness convention Godot's own importer uses instead of
	# a sign I would have had to guess at.
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_tangents()
	return st.commit()


## Sample positions along one axis of the outer box, clustered into the two
## fillet bands so that the arcs come out evenly divided.
static func _axis_samples(half: float, e: float, r: float, seg: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if e <= 0.0001 or r <= 0.0:
		# The fillet swallows the whole axis; fall back to even sampling.
		var steps := seg * 2
		for i in steps + 1:
			out.append(lerpf(-half, half, float(i) / float(steps)))
		return out

	var quarter := PI * 0.25
	for i in range(seg, -1, -1):
		out.append(-(e + r * tan(quarter * float(i) / float(seg))))
	for i in seg + 1:
		out.append(e + r * tan(quarter * float(i) / float(seg)))
	return out


## Build a Vector3 from a value on `axis` and values on the two in-plane axes,
## consistent with a = (axis + 1) % 3 and b = (axis + 2) % 3.
static func _point(axis: int, on_axis: float, on_a: float, on_b: float) -> Vector3:
	match axis:
		0: return Vector3(on_axis, on_a, on_b)
		1: return Vector3(on_b, on_axis, on_a)
		_: return Vector3(on_a, on_b, on_axis)


static func _unit(axis: int) -> Vector3:
	match axis:
		0: return Vector3.RIGHT
		1: return Vector3.UP
		_: return Vector3.BACK


static func _component(v: Vector3, axis: int) -> float:
	match axis:
		0: return v.x
		1: return v.y
		_: return v.z
