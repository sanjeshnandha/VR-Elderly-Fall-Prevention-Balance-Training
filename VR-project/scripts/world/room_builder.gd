@tool
class_name RoomBuilder
extends Node3D
## Builds a rectangular room -- floor, ceiling and four walls with doorways --
## from a handful of numbers.
##
## SCALE IS THE POINT. 1 unit = 1 metre, always. Getting scale right matters
## more than any amount of visual polish: if the doorway is 2.4 m instead of
## 2.0 m the whole house feels subtly enormous, the participant misjudges every
## distance, and a training application about spatial judgement has taught them
## something false. Defaults here are real UK/US domestic dimensions:
##   ceiling 2.4 m, doorway 0.9 x 2.03 m, stair rise 0.19 m, going 0.25 m.
##
## Openings are given as Vector4(wall_index, centre_offset, width, height):
##   wall_index  0 = +Z, 1 = -Z, 2 = +X, 3 = -X
##   centre_offset  metres from the middle of that wall, along the wall
##   width, height  metres
##
## Runs in the editor (@tool) so the layout is visible while you place hazards.

@export var size: Vector2 = Vector2(4.0, 4.0): set = _set_size
@export var height: float = 2.4: set = _set_height
@export var wall_thickness: float = 0.12

@export var floor_color: Color = Color("#8a7f72")
@export var wall_color: Color = Color("#d9d4cb")
@export var ceiling_color: Color = Color("#efece6")

@export var build_floor: bool = true
@export var build_ceiling: bool = true

## Which of the four walls to build at all. Leave a wall out to open a room
## straight onto the next one.
@export var build_walls: Array[bool] = [true, true, true, true]

@export var openings: Array[Vector4] = []

## Rebuild now. Toggling this in the inspector regenerates the geometry.
@export var rebuild: bool = false: set = _set_rebuild

const GROUP := "room_geometry"


func _ready() -> void:
	build()


func _set_size(value: Vector2) -> void:
	size = value
	if is_inside_tree():
		build()


func _set_height(value: float) -> void:
	height = value
	if is_inside_tree():
		build()


func _set_rebuild(_value: bool) -> void:
	rebuild = false
	if is_inside_tree():
		build()


func build() -> void:
	_clear()

	if build_floor:
		_add_slab("Floor", Vector3(size.x, wall_thickness, size.y),
			Vector3(0.0, -wall_thickness * 0.5, 0.0), floor_color)
	if build_ceiling:
		_add_slab("Ceiling", Vector3(size.x, wall_thickness, size.y),
			Vector3(0.0, height + wall_thickness * 0.5, 0.0), ceiling_color)

	for wall_index in 4:
		if wall_index < build_walls.size() and not build_walls[wall_index]:
			continue
		_build_wall(wall_index)


func _clear() -> void:
	for child in get_children():
		if child.is_in_group(GROUP):
			child.free()


# ---------------------------------------------------------------------------
#  Walls
# ---------------------------------------------------------------------------

## Wall run length, outward normal and centre position for each wall index.
func _wall_axis(wall_index: int) -> Dictionary:
	match wall_index:
		0: return {"length": size.x, "centre": Vector3(0.0, 0.0, size.y * 0.5), "along": Vector3.RIGHT}
		1: return {"length": size.x, "centre": Vector3(0.0, 0.0, -size.y * 0.5), "along": Vector3.RIGHT}
		2: return {"length": size.y, "centre": Vector3(size.x * 0.5, 0.0, 0.0), "along": Vector3.BACK}
		_: return {"length": size.y, "centre": Vector3(-size.x * 0.5, 0.0, 0.0), "along": Vector3.BACK}


func _build_wall(wall_index: int) -> void:
	var axis := _wall_axis(wall_index)
	var length: float = axis["length"]
	var centre: Vector3 = axis["centre"]
	var along: Vector3 = axis["along"]

	# Collect this wall's openings as [start, end] spans along the wall.
	var spans: Array = []
	for opening in openings:
		if int(opening.x) != wall_index:
			continue
		var half_width: float = opening.z * 0.5
		spans.append({
			"start": opening.y - half_width,
			"end": opening.y + half_width,
			"height": opening.w,
		})
	spans.sort_custom(_compare_spans)

	var cursor := -length * 0.5
	var index := 0

	for span: Dictionary in spans:
		var start: float = clampf(span["start"], -length * 0.5, length * 0.5)
		var end: float = clampf(span["end"], -length * 0.5, length * 0.5)

		# Solid segment before the opening.
		if start > cursor:
			_add_wall_segment(wall_index, centre, along, cursor, start, 0.0, height, index)
			index += 1
		# Lintel above the opening.
		var opening_height: float = minf(span["height"], height)
		if opening_height < height:
			_add_wall_segment(wall_index, centre, along, start, end, opening_height, height, index)
			index += 1
		cursor = maxf(cursor, end)

	# Remaining solid segment after the last opening.
	if cursor < length * 0.5:
		_add_wall_segment(wall_index, centre, along, cursor, length * 0.5, 0.0, height, index)


## Left-to-right along the wall, so segments are emitted in order.
static func _compare_spans(a: Dictionary, b: Dictionary) -> bool:
	return float(a["start"]) < float(b["start"])


func _add_wall_segment(
	wall_index: int, centre: Vector3, along: Vector3,
	from: float, to: float, bottom: float, top: float, index: int
) -> void:
	var run := to - from
	var tall := top - bottom
	if run <= 0.001 or tall <= 0.001:
		return

	var mid := (from + to) * 0.5
	var position := centre + along * mid + Vector3(0.0, bottom + tall * 0.5, 0.0)

	var box_size: Vector3
	if wall_index <= 1:
		box_size = Vector3(run, tall, wall_thickness)
	else:
		box_size = Vector3(wall_thickness, tall, run)

	_add_slab("Wall%d_%d" % [wall_index, index], box_size, position, wall_color)


# ---------------------------------------------------------------------------
#  Geometry helper
# ---------------------------------------------------------------------------

## A visible box plus a static collision body on layer 1 ("world"), which is the
## layer the teleport arc tests against for walkable floor.
func _add_slab(slab_name: String, box_size: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = slab_name
	body.position = position
	body.collision_layer = 1 << 0
	body.collision_mask = 0
	body.add_to_group(GROUP)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box_size
	shape.shape = box_shape
	body.add_child(shape)

	body.add_child(AutoShape.make_box_mesh(box_size, color))
	add_child(body)
	if Engine.is_editor_hint() and owner != null:
		body.owner = owner
