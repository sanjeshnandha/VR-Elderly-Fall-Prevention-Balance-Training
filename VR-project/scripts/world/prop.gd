@tool
class_name Prop
extends Node3D
## A single piece of primitive furniture: a box or a cylinder, with optional
## collision. Kenney-style blockout, not photoreal -- the training value is in
## correct scale and correct affordances, not in texture detail.
##
## Everything in the house is built from these so that a room is a dozen
## readable lines in a .tscn rather than a hundred, and so that adjusting the
## height of a chair seat is one number in the inspector.

enum Kind { BOX, CYLINDER, SPHERE }

@export var kind: Kind = Kind.BOX: set = _set_kind
## Full size in metres (BOX), or (diameter, height, diameter) for CYLINDER.
@export var box_size: Vector3 = Vector3(0.5, 0.5, 0.5): set = _set_box_size
@export var color: Color = Color("#9c8f80"): set = _set_color
@export var roughness: float = 0.8
@export var metallic: float = 0.0

## Solid furniture blocks the teleport arc; a rug or a cord does not.
@export var collide: bool = true

## Slightly emissive, for things that are meant to catch the eye (a lamp).
@export var emissive: bool = false

const GROUP := "prop_geometry"


func _ready() -> void:
	build()


func _set_kind(value: Kind) -> void:
	kind = value
	if is_inside_tree():
		build()


func _set_box_size(value: Vector3) -> void:
	box_size = value
	if is_inside_tree():
		build()


func _set_color(value: Color) -> void:
	color = value
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

	var mat := AutoShape.make_material(color, roughness, metallic)
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.2
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	if collide:
		var body := StaticBody3D.new()
		body.name = "PropBody"
		body.add_to_group(GROUP)
		body.collision_layer = 1 << 0
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = _make_shape()
		body.add_child(shape)
		add_child(body)

	if Engine.is_editor_hint() and owner != null:
		for child in get_children():
			if child.is_in_group(GROUP):
				child.owner = owner


func _make_mesh() -> Mesh:
	match kind:
		Kind.CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = box_size.x * 0.5
			cyl.bottom_radius = box_size.z * 0.5
			cyl.height = box_size.y
			cyl.radial_segments = 16
			return cyl
		Kind.SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = box_size.x * 0.5
			sphere.height = box_size.y
			return sphere
		_:
			var box := BoxMesh.new()
			box.size = box_size
			return box


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
