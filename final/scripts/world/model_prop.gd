@tool
class_name ModelProp
extends Node3D
## A piece of real furniture: a model file (Kenney Furniture Kit, CC0) placed
## in the world, with the same collision behaviour as `prop.gd` so nothing else
## in the project has to change.
##
## WHY NOT JUST DROP THE MODEL IN
## ------------------------------
##   * The game measures behaviour against SHAPES: the teleport arc needs to
##     know what is floor, the pointer needs something to stop at, and hazard
##     volumes are sized in metres. A model's own geometry is the wrong thing
##     for all three -- too detailed, often concave, and different in every
##     pack. So the collision stays a plain box, exactly as it was, and the
##     model is dressing hung on it.
##   * Every pack authors at its own scale and facing. `align_to_box` measures
##     the model and fits it to `box_size`, so a scene file keeps saying "this
##     sofa is 2.0 x 0.8 x 0.85 m" and the model obeys, rather than the other
##     way round. Real dimensions are the point of this project.
##   * The asset pack is not in the repository. If the model is missing this
##     falls back to the coloured box, so the project still opens, runs and
##     scores correctly in a clean checkout.
##
## The node's origin is the CENTRE of `box_size`, like `prop.gd`, and the model
## is sat on the bottom of that box.

## Path to a .glb/.gltf/.obj/.tscn under res://assets/. Empty = plain box.
@export_file("*.glb", "*.gltf", "*.obj", "*.tscn") var model_path: String = "": set = _set_model_path

## Full size in metres. Collision, the fallback box, and -- with
## `align_to_box` -- what the model is scaled to fit.
@export var box_size: Vector3 = Vector3(0.5, 0.5, 0.5): set = _set_box_size

## Scale the model to fill `box_size` and sit it on the floor of that box.
## Turn off to place a model at its authored size with `model_scale`.
@export var align_to_box: bool = true

## Extra scale applied after alignment (or instead of it).
@export var model_scale: float = 1.0

## Turn the model about Y, in degrees. Packs disagree about which way "front" is.
@export var model_yaw_degrees: float = 0.0

## Nudge the model within its box, in metres.
@export var model_offset: Vector3 = Vector3.ZERO

## Colour of the fallback box, and of the model when `tint_model` is on.
@export var color: Color = Color("#9c8f80")
@export var tint_model: bool = false

@export var roughness: float = 0.8
@export var metallic: float = 0.0

## Solid furniture blocks the teleport arc and the pointer beam; a rug does not.
@export var collide: bool = true

## Ground you may teleport onto (see teleporter.gd). Needs `collide`.
@export var walkable: bool = false

const GROUP := "prop_geometry"


func _ready() -> void:
	build()


func _set_model_path(value: String) -> void:
	model_path = value
	if is_inside_tree():
		build()


func _set_box_size(value: Vector3) -> void:
	box_size = value
	if is_inside_tree():
		build()


func build() -> void:
	for child in get_children():
		if child.is_in_group(GROUP):
			child.free()

	var model := _instantiate_model()
	if model != null:
		model.add_to_group(GROUP)
		add_child(model)
		_fit(model)
		if tint_model:
			_tint(model)
	else:
		# No pack installed: the blockout box, exactly as before.
		var mesh_instance := AutoShape.make_box_mesh(box_size, color, roughness)
		mesh_instance.add_to_group(GROUP)
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
		var box := BoxShape3D.new()
		box.size = box_size
		shape.shape = box
		body.add_child(shape)
		add_child(body)


func _instantiate_model() -> Node3D:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return null
	var packed := load(model_path)
	if packed is PackedScene:
		return (packed as PackedScene).instantiate() as Node3D
	if packed is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = packed
		return mesh_instance
	return null


## Scale the model to `box_size` and stand it on the bottom of the box.
func _fit(model: Node3D) -> void:
	model.rotation_degrees = Vector3(0.0, model_yaw_degrees, 0.0)
	var bounds := _model_bounds(model)
	var factor := model_scale
	if align_to_box and bounds.size.x > 0.001 and bounds.size.z > 0.001:
		# Fit the footprint; height follows, so proportions are never squashed.
		factor *= minf(box_size.x / bounds.size.x, box_size.z / bounds.size.z)
	model.scale = Vector3.ONE * factor
	# Centre horizontally on the box, and sit the model on the box's floor.
	var centre := bounds.get_center() * factor
	model.position = Vector3(-centre.x, -box_size.y * 0.5 - bounds.position.y * factor, -centre.z) + model_offset


## Combined AABB of every mesh in the model, in the model's own space.
func _model_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.mesh.get_aabb()
		# Into the model's space, not the mesh's own.
		var relative := model.global_transform.affine_inverse() * mesh_instance.global_transform
		box = relative * box
		if first:
			bounds = box
			first = false
		else:
			bounds = bounds.merge(box)
	return bounds


func _tint(model: Node3D) -> void:
	var material := AutoShape.make_material(color, roughness, metallic)
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = material
