@tool
class_name Staircase
extends Node3D
## Builds a straight flight of stairs ascending along local +Z, plus a landing.
##
## Real domestic dimensions by default: 190 mm rise, 250 mm going, 900 mm width.
## These are not arbitrary -- they are what the participant's own staircase very
## likely measures, and the whole point of the exercise is that the movement
## rehearsed here transfers to their actual home.
##
## `uneven_step_index` raises one tread by a few millimetres. An unexpectedly
## tall step is one of the most common trip causes on domestic stairs precisely
## because it is nearly invisible; finding it is a genuine perceptual task.

@export var step_count: int = 8: set = _set_step_count
@export var rise: float = 0.19
@export var going: float = 0.25
@export var width: float = 0.90

## 1-based index of the uneven tread. 0 disables it.
@export var uneven_step_index: int = 5

## Extra height on the uneven tread, in metres. 25 mm is enough to catch a toe
## and small enough to be genuinely hard to see.
@export var uneven_extra_rise: float = 0.025

@export var landing_depth: float = 1.6
@export var step_color: Color = Color("#7a6a58")
@export var landing_color: Color = Color("#6f6152")

## Named surfaces from Surfaces.SPECS, which override the colours above. Stair
## treads are looked at more closely than any other floor in the house -- the
## participant is watching their feet the whole way up -- so they get real oak
## with the grain running across the tread.
@export var step_surface: String = "oak_wood"
@export var landing_surface: String = "oak_floor"

@export var rebuild: bool = false: set = _set_rebuild

const GROUP := "stair_geometry"


func _ready() -> void:
	build()


func _set_step_count(value: int) -> void:
	step_count = maxi(value, 1)
	if is_inside_tree():
		build()


func _set_rebuild(_value: bool) -> void:
	rebuild = false
	if is_inside_tree():
		build()


func build() -> void:
	for child in get_children():
		if child.is_in_group(GROUP):
			child.free()

	for i in range(1, step_count + 1):
		var top := step_top_height(i)
		# Each tread is modelled as a solid block from the floor up, which is
		# both how a closed-string domestic stair is actually built and the
		# easiest thing for a physics ray to land on cleanly.
		var box_size := Vector3(width, top, going)
		var position := Vector3(0.0, top * 0.5, (i - 0.5) * going)
		# The uneven tread is the same colour as the others on purpose. Making it
		# obvious would defeat the exercise; the Hazard trigger is what teaches it.
		_add_block("Step%d" % i, box_size, position, step_color, step_surface)

	var landing_height := step_top_height(step_count)
	_add_block(
		"Landing",
		Vector3(width, landing_height, landing_depth),
		Vector3(0.0, landing_height * 0.5, step_count * going + landing_depth * 0.5),
		landing_color,
		landing_surface
	)


## Height of the top surface of tread `index` (1-based), including any unevenness.
func step_top_height(index: int) -> float:
	var top := float(index) * rise
	if uneven_step_index > 0 and index >= uneven_step_index:
		top += uneven_extra_rise
	return top


## World position to stand on tread `index` (1-based). Used to place the gated
## teleport points so they always sit exactly on the tread surface.
func step_stand_position(index: int) -> Vector3:
	return to_global(Vector3(0.0, step_top_height(index), (float(index) - 0.5) * going))


func landing_stand_position() -> Vector3:
	return to_global(Vector3(
		0.0,
		step_top_height(step_count),
		float(step_count) * going + landing_depth * 0.5
	))


func _add_block(block_name: String, box_size: Vector3, position: Vector3,
		color: Color, surface: String = "") -> void:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = position
	body.collision_layer = 1 << 0
	body.collision_mask = 0
	body.add_to_group(GROUP)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	# A 4 mm arris on each tread: enough to catch the light along the nosing,
	# which is exactly the edge a person on stairs is trying to judge.
	body.add_child(AutoShape.make_box_mesh(box_size, color, 0.6, surface, 0.004))
	# Treads and the landing are floor. Inside the stairwell the teleporter only
	# accepts GatedTeleportPoints anyway; this matters for anything aiming from
	# outside the gated region.
	body.add_to_group("walkable")

	# Not owned, even in the editor: see room_builder.gd `_add_slab`.
	add_child(body)
