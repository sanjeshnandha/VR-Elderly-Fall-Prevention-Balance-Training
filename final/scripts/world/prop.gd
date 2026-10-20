@tool
class_name Prop
extends Node3D
## A single piece of furniture: a filleted box, a cylinder or a sphere, with a
## real material and optional collision.
##
## Everything in the house is built from these, so that a room is a few dozen
## readable lines in a .tscn rather than a thousand, and so that raising the
## height of a chair seat stays one number in the inspector.
##
## TWO THINGS MAKE THESE READ AS FURNITURE RATHER THAN BLOCKOUT.
##
## 1. Filleted edges. `corner_radius` runs the box through MeshKit, which puts a
##    genuine 18 mm round on every arris while keeping the faces dead flat and
##    the outer dimensions exact. Nothing in a real room has a sharp arris, and
##    the eye picks that up long before it notices a texture.
## 2. A named `surface` from the Surfaces library, which brings albedo, normal
##    and roughness maps with world-space triplanar UVs -- so the grain of a
##    table runs the right way and the tiles line up across a join.
##
## COLLISION IS UNAFFECTED by either. The shape stays a plain box of exactly
## `box_size`, so the fillet cannot change where the teleport arc stops or what
## the hand can reach. Visual polish must never move a physics boundary in a
## training application about spatial judgement.

enum Kind { BOX, CYLINDER, SPHERE }

@export var kind: Kind = Kind.BOX: set = _set_kind
## Full size in metres (BOX), or (diameter, height, diameter) for CYLINDER.
@export var box_size: Vector3 = Vector3(0.5, 0.5, 0.5): set = _set_box_size

@export_group("Look")
## A name from Surfaces.SPECS: "oak_wood", "upholstery", "ceramic", "glass" ...
## Leave it empty to fall back to `color`, which is what every prop written
## before the texture pass does.
@export var surface: String = "": set = _set_surface
## Used when `surface` is empty, and as the emission colour when `emissive` is
## on. A named surface ignores it: the maps already carry the colour.
@export var color: Color = Color("#9c8f80"): set = _set_color
## Multiplies a named surface, for one sofa in a different fabric from another
## without a second set of maps. Leave white to use the texture as baked.
@export var tint: Color = Color(1, 1, 1, 1): set = _set_tint
## Only used when `surface` is empty.
@export var roughness: float = 0.8
@export var metallic: float = 0.0
## Fillet radius in metres. 0.015 to 0.025 suits furniture; 0 restores Godot's
## own BoxMesh, which is the escape hatch if MeshKit ever misbehaves.
@export var corner_radius: float = 0.018: set = _set_corner_radius
## Slightly emissive, for things meant to catch the eye: a lamp, a lit window.
@export var emissive: bool = false: set = _set_emissive
@export var emission_energy: float = 1.2
## Texture coordinates come from the world, so a pattern runs continuously
## across separate props and slabs. Turn it OFF for anything that moves, or the
## texture stands still while the object slides through it.
@export var world_texture: bool = true

@export_group("Physics")
## Solid furniture blocks the teleport arc; a rug or a cord does not.
@export var collide: bool = true
## Ground you are allowed to teleport onto: paths, pavements, the road. Grass,
## walls and the tops of furniture are not (see teleporter.gd). Needs `collide`.
@export var walkable: bool = false

const GROUP := "prop_geometry"


func _ready() -> void:
	build()


func _set_kind(value: Kind) -> void:
	kind = value
	_rebuild()


func _set_box_size(value: Vector3) -> void:
	box_size = value
	_rebuild()


func _set_color(value: Color) -> void:
	color = value
	_rebuild()


func _set_surface(value: String) -> void:
	surface = value
	_rebuild()


func _set_tint(value: Color) -> void:
	tint = value
	_rebuild()


func _set_corner_radius(value: float) -> void:
	corner_radius = value
	_rebuild()


func _set_emissive(value: bool) -> void:
	emissive = value
	_rebuild()


func _rebuild() -> void:
	if is_inside_tree():
		build()


func build() -> void:
	for child in get_children():
		if child.is_in_group(GROUP):
			child.free()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PropMesh"
	mesh_instance.add_to_group(GROUP)
	mesh_instance.mesh = _make_mesh()
	mesh_instance.material_override = _make_material()
	add_child(mesh_instance)

	if collide:
		var body := StaticBody3D.new()
		body.name = "PropBody"
		body.add_to_group(GROUP)
		body.collision_layer = 1 << 0
		body.collision_mask = 0
		if walkable:
			body.add_to_group("walkable")
		var shape := CollisionShape3D.new()
		shape.shape = _make_shape()
		body.add_child(shape)
		add_child(body)

	# Generated children are not owned, even in the editor: they are rebuilt on
	# every load, and owning them would save duplicates into the .tscn.


## A shared library material where possible, a private copy only when this prop
## needs its own tint or emission. Sharing matters: it is the difference between
## one material for every oak surface in the house and two hundred.
func _make_material() -> StandardMaterial3D:
	var base := Surfaces.get_material(surface, world_texture)
	var needs_own_copy := emissive or tint != Color(1, 1, 1, 1)

	if base == null:
		# No surface named, or the name was not recognised.
		var plain := AutoShape.make_material(color, roughness, metallic)
		if emissive:
			_apply_emission(plain, color)
		return plain

	if not needs_own_copy:
		return base

	var mat := base.duplicate() as StandardMaterial3D
	mat.albedo_color = mat.albedo_color * tint
	if emissive:
		_apply_emission(mat, color)
	return mat


func _apply_emission(mat: StandardMaterial3D, emission_color: Color) -> void:
	mat.emission_enabled = true
	mat.emission = Color(emission_color.r, emission_color.g, emission_color.b)
	mat.emission_energy_multiplier = emission_energy


func _make_mesh() -> Mesh:
	match kind:
		Kind.CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = box_size.x * 0.5
			cyl.bottom_radius = box_size.z * 0.5
			cyl.height = box_size.y
			cyl.radial_segments = 24
			return cyl
		Kind.SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = box_size.x * 0.5
			sphere.height = box_size.y
			sphere.radial_segments = 32
			sphere.rings = 16
			return sphere
		_:
			return MeshKit.rounded_box(box_size, corner_radius)


## Always the full box: the fillet is cosmetic and must not shrink the volume
## the teleport arc and the reach test see.
func _make_shape() -> Shape3D:
	match kind:
		Kind.CYLINDER:
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(box_size.x, box_size.z) * 0.5
			cyl.height = box_size.y
			return cyl
		Kind.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = box_size.x * 0.5
			return sphere
		_:
			var box := BoxShape3D.new()
			box.size = box_size
			return box
