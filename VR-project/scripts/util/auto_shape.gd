@tool
class_name AutoShape
extends RefCounted
## Small helpers that give a trigger volume a collision shape at runtime if the
## scene did not provide one.
##
## Why: hand-authoring a CollisionShape3D plus a SubResource for every one of
## the ~30 hazards, zones, rails and landings in the house triples the size of
## the .tscn files and makes them tedious to review or extend. Every trigger in
## this project therefore exports a plain `extents` vector and builds its own
## box at load time. Drop a Hazard into a room, set two numbers, done.
##
## If a CollisionShape3D *is* present in the scene it is always respected and
## nothing is generated -- so an irregular hazard can still have a hand-fitted
## shape where that matters.


## True if `owner_node` already has a CollisionShape3D child.
static func has_shape(owner_node: Node) -> bool:
	for child in owner_node.get_children():
		if child is CollisionShape3D:
			return true
	return false


## Give `owner_node` a box collision shape of the given full size, if it has none.
static func ensure_box(owner_node: CollisionObject3D, size: Vector3) -> void:
	if has_shape(owner_node):
		return
	var s := size.abs()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(s.x, 0.01), maxf(s.y, 0.01), maxf(s.z, 0.01))
	var node := CollisionShape3D.new()
	node.name = "AutoShape"
	node.shape = shape
	owner_node.add_child(node)
	# Clears the editor's "this node has no shape" configuration warning as soon
	# as the generated shape exists.
	owner_node.update_configuration_warnings()


## Give `owner_node` an upright cylinder collision shape, if it has none.
static func ensure_cylinder(owner_node: CollisionObject3D, radius: float, height: float) -> void:
	if has_shape(owner_node):
		return
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.01)
	shape.height = maxf(height, 0.01)
	var node := CollisionShape3D.new()
	node.name = "AutoShape"
	node.shape = shape
	owner_node.add_child(node)
	# Clears the editor's "this node has no shape" configuration warning as soon
	# as the generated shape exists.
	owner_node.update_configuration_warnings()


## Give `owner_node` a capsule aligned along its local X axis (the shape of a
## horizontal handrail), if it has none.
static func ensure_x_capsule(owner_node: CollisionObject3D, radius: float, length: float) -> void:
	if has_shape(owner_node):
		return
	var shape := CapsuleShape3D.new()
	shape.radius = maxf(radius, 0.005)
	shape.height = maxf(length, radius * 2.0 + 0.01)
	var node := CollisionShape3D.new()
	node.name = "AutoShape"
	node.shape = shape
	# CapsuleShape3D runs along Y; rotate it onto X.
	node.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	owner_node.add_child(node)
	# Clears the editor's "this node has no shape" configuration warning as soon
	# as the generated shape exists.
	owner_node.update_configuration_warnings()


## Build a simple unshaded-ish box mesh child. Used by prop.gd and grab_rail.gd.
static func make_box_mesh(size: Vector3, color: Color, roughness: float = 0.75) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = make_material(color, roughness)
	return mesh_instance


static func make_material(color: Color, roughness: float = 0.75, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
