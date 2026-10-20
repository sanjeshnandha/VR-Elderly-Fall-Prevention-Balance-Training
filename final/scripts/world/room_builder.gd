@tool
class_name RoomBuilder
extends Node3D
## Builds a rectangular room -- floor, ceiling, four walls with doorways and
## glazed windows, and the joinery that makes it look like a room -- from a
## handful of numbers.
##
## SCALE IS THE POINT. 1 unit = 1 metre, always. Getting scale right matters
## more than any amount of visual polish: if the doorway is 2.4 m instead of
## 2.0 m the whole house feels subtly enormous, the participant misjudges every
## distance, and a training application about spatial judgement has taught them
## something false. Defaults here are real UK/US domestic dimensions:
##   ceiling 2.4 m, doorway 0.9 x 2.03 m, stair rise 0.19 m, going 0.25 m,
##   skirting 100 mm, architrave 70 mm, window sill 850 mm.
##
## HOLES IN WALLS come in two kinds, because they behave differently:
##
##   openings         Vector4(wall, centre_offset, width, height)
##                    Doorways. They start at the floor, so the wall below them
##                    is gone and the skirting has to stop either side.
##   window_openings  Vector4(wall, centre_offset, width, height)
##                    Windows. They start at `window_sill_height`, so the wall
##                    below stays solid and the skirting runs straight past. Each
##                    one is given a lining, a projecting sill, glazing bars and
##                    an actual pane of glass that stops the teleport arc.
##
##   wall_index  0 = +Z, 1 = -Z, 2 = +X, 3 = -X
##
## Real windows are worth the extra code: daylight arriving through a hole in a
## wall, at an angle, landing on the floor, is most of what makes an interior
## read as a place rather than a diagram -- and with SDFGI on it also lights the
## room for free.
##
## JOINERY. A room made of six untrimmed boxes reads as a box, whatever is
## painted on it, because the one thing every real room has and no blockout does
## is the line where two surfaces meet: skirting at the floor, coving at the
## ceiling, architrave and a lining around each doorway, a threshold underfoot.
## All of it is generated from the same numbers that made the walls, so a room
## costs no extra lines in the .tscn to look finished.
##
## Every trim piece is a MeshInstance3D with NO collision body. That is
## deliberate: trim must not be able to stop a teleport arc, block a pointer ray
## or change what the hand can reach. The one exception is window glass, which
## is meant to be solid -- it is a proper StaticBody3D on the world layer, like
## any other pane of glass you cannot walk through.
##
## Runs in the editor (@tool) so the layout is visible while you place hazards.

@export var size: Vector2 = Vector2(4.0, 4.0): set = _set_size
@export var height: float = 2.4: set = _set_height
@export var wall_thickness: float = 0.12

@export_group("Surfaces")
## Names from Surfaces.SPECS. A named surface brings real albedo, normal and
## roughness maps and IGNORES the matching colour below; clear it to go back to
## flat colour.
@export var floor_surface: String = "oak_floor": set = _set_floor_surface
@export var wall_surface: String = "plaster_wall": set = _set_wall_surface
@export var ceiling_surface: String = "ceiling_plaster": set = _set_ceiling_surface
@export var trim_surface: String = "paint_satin"

@export var floor_color: Color = Color("#8a7f72")
@export var wall_color: Color = Color("#d9d4cb")
@export var ceiling_color: Color = Color("#efece6")

@export_group("Structure")
@export var build_floor: bool = true
@export var build_ceiling: bool = true

## Which of the four walls to build at all. Leave a wall out to open a room
## straight onto the next one.
@export var build_walls: Array[bool] = [true, true, true, true]

## Doorways: Vector4(wall_index, centre_offset, width, height), from the floor up.
@export var openings: Array[Vector4] = []: set = _set_openings

## Windows: Vector4(wall_index, centre_offset, width, height), standing on the
## sill. Each gets a lining, a sill, glazing bars and a solid pane.
@export var window_openings: Array[Vector4] = []: set = _set_window_openings
@export var window_sill_height: float = 0.85

@export_group("Joinery")
@export var skirting: bool = true: set = _set_skirting
@export var skirting_height: float = 0.10
@export var skirting_depth: float = 0.016
@export var cornice: bool = true
@export var architrave: bool = true
@export var architrave_width: float = 0.07
@export var architrave_depth: float = 0.02
## Doorways in a dividing wall are seen from both rooms. The wall belongs to
## whichever RoomBuilder declared the opening, so that one has to trim both
## faces -- switch this on for the hallway.
@export var architrave_both_sides: bool = false
## A hardwood strip under each doorway, where the two floors meet.
@export var thresholds: bool = true
## Glazed panes in the windows. Off leaves the holes empty, which is useful when
## you want to see into a room while placing hazards.
@export var glazing: bool = true
## The pane's surface. "glass_frosted" for a bathroom, where a clear pane onto
## nothing would look wrong and obscured glass is what is actually fitted.
@export var glazing_surface: String = "glass"

## Rebuild now. Toggling this in the inspector regenerates the geometry.
@export var rebuild: bool = false: set = _set_rebuild

const GROUP := "room_geometry"

## Serial number for generated trim, reset at the start of every build. A wall
## with three doorways has four separate runs of skirting, and without this they
## would all be called "Skirt_0" and Godot would quietly rename them -- harmless,
## but it makes the tree unreadable when you are trying to find one piece.
var _trim_serial: int = 0

## A hole whose top is within this of the ceiling has no lintel, so the coving
## cannot run across it.
const FULL_HEIGHT_MARGIN := 0.02

## Thickness of a door or window lining board.
const LINING := 0.018


func _ready() -> void:
	build()


func _set_size(value: Vector2) -> void:
	size = value
	_rebuild_if_ready()


func _set_height(value: float) -> void:
	height = value
	_rebuild_if_ready()


func _set_floor_surface(value: String) -> void:
	floor_surface = value
	_rebuild_if_ready()


func _set_wall_surface(value: String) -> void:
	wall_surface = value
	_rebuild_if_ready()


func _set_ceiling_surface(value: String) -> void:
	ceiling_surface = value
	_rebuild_if_ready()


func _set_openings(value: Array[Vector4]) -> void:
	openings = value
	_rebuild_if_ready()


func _set_window_openings(value: Array[Vector4]) -> void:
	window_openings = value
	_rebuild_if_ready()


func _set_skirting(value: bool) -> void:
	skirting = value
	_rebuild_if_ready()


func _set_rebuild(_value: bool) -> void:
	rebuild = false
	_rebuild_if_ready()


func _rebuild_if_ready() -> void:
	if is_inside_tree():
		build()


func build() -> void:
	_clear()
	_trim_serial = 0

	if build_floor:
		var floor_body := _add_slab("Floor", Vector3(size.x, wall_thickness, size.y),
			Vector3(0.0, -wall_thickness * 0.5, 0.0), floor_color, floor_surface)
		# Only floors are legal free-teleport destinations (see teleporter.gd);
		# furniture tops, bath rims and wardrobe tops are not.
		floor_body.add_to_group("walkable")
	if build_ceiling:
		_add_slab("Ceiling", Vector3(size.x, wall_thickness, size.y),
			Vector3(0.0, height + wall_thickness * 0.5, 0.0), ceiling_color, ceiling_surface)

	for wall_index in 4:
		if wall_index < build_walls.size() and not build_walls[wall_index]:
			continue
		_build_wall(wall_index)
		_build_joinery(wall_index)


func _clear() -> void:
	for child in get_children():
		if child.is_in_group(GROUP):
			child.free()


# ---------------------------------------------------------------------------
#  Walls
# ---------------------------------------------------------------------------

## Wall run length, centre position, direction along the wall, and the direction
## from the wall towards the middle of the room -- which is the side every piece
## of trim has to sit on.
func _wall_axis(wall_index: int) -> Dictionary:
	match wall_index:
		0: return {"length": size.x, "centre": Vector3(0.0, 0.0, size.y * 0.5),
			"along": Vector3.RIGHT, "inward": Vector3.FORWARD}
		1: return {"length": size.x, "centre": Vector3(0.0, 0.0, -size.y * 0.5),
			"along": Vector3.RIGHT, "inward": Vector3.BACK}
		2: return {"length": size.y, "centre": Vector3(size.x * 0.5, 0.0, 0.0),
			"along": Vector3.BACK, "inward": Vector3.LEFT}
		_: return {"length": size.y, "centre": Vector3(-size.x * 0.5, 0.0, 0.0),
			"along": Vector3.BACK, "inward": Vector3.RIGHT}


## Every hole in this wall -- doorways and windows together -- left to right.
func _wall_holes(wall_index: int) -> Array[Dictionary]:
	var holes: Array[Dictionary] = []
	for opening in openings:
		if int(opening.x) == wall_index:
			holes.append(_hole(opening, 0.0, false))
	for window in window_openings:
		if int(window.x) == wall_index:
			holes.append(_hole(window, window_sill_height, true))
	holes.sort_custom(_compare_holes)
	return holes


func _hole(v: Vector4, bottom: float, is_window: bool) -> Dictionary:
	var half_width := v.z * 0.5
	return {
		"start": v.y - half_width,
		"end": v.y + half_width,
		"centre": v.y,
		"width": v.z,
		"bottom": maxf(bottom, 0.0),
		"top": minf(bottom + v.w, height),
		"is_window": is_window,
	}


## Left-to-right along the wall, so segments are emitted in order.
static func _compare_holes(a: Dictionary, b: Dictionary) -> bool:
	return float(a["start"]) < float(b["start"])


func _build_wall(wall_index: int) -> void:
	var axis := _wall_axis(wall_index)
	var length: float = axis["length"]
	var centre: Vector3 = axis["centre"]
	var along: Vector3 = axis["along"]

	var cursor := -length * 0.5
	var index := 0

	for hole in _wall_holes(wall_index):
		var start: float = clampf(hole["start"], -length * 0.5, length * 0.5)
		var end: float = clampf(hole["end"], -length * 0.5, length * 0.5)
		var bottom: float = hole["bottom"]
		var top: float = hole["top"]

		# Solid full-height segment before the hole.
		if start > cursor:
			_add_wall_segment(wall_index, centre, along, cursor, start, 0.0, height, index)
			index += 1
		# Under a window the wall stays; under a doorway there is nothing.
		if bottom > 0.001:
			_add_wall_segment(wall_index, centre, along, start, end, 0.0, bottom, index)
			index += 1
		# Lintel above.
		if top < height - 0.001:
			_add_wall_segment(wall_index, centre, along, start, end, top, height, index)
			index += 1
		cursor = maxf(cursor, end)

	# Remaining solid segment after the last hole.
	if cursor < length * 0.5:
		_add_wall_segment(wall_index, centre, along, cursor, length * 0.5, 0.0, height, index)


func _add_wall_segment(
	wall_index: int, centre: Vector3, along: Vector3,
	from: float, to: float, bottom: float, top: float, index: int
) -> void:
	var run := to - from
	var tall := top - bottom
	if run <= 0.001 or tall <= 0.001:
		return

	var mid := (from + to) * 0.5
	var at := centre + along * mid + Vector3(0.0, bottom + tall * 0.5, 0.0)

	var box_size: Vector3
	if wall_index <= 1:
		box_size = Vector3(run, tall, wall_thickness)
	else:
		box_size = Vector3(wall_thickness, tall, run)

	_add_slab("Wall%d_%d" % [wall_index, index], box_size, at, wall_color, wall_surface)


# ---------------------------------------------------------------------------
#  Joinery
# ---------------------------------------------------------------------------

func _build_joinery(wall_index: int) -> void:
	var axis := _wall_axis(wall_index)
	var length: float = axis["length"]
	var holes := _wall_holes(wall_index)

	if skirting:
		# Skirting stops at a doorway and runs straight past a window.
		for run in _solid_runs(length, holes, true):
			_add_skirting(wall_index, run.x, run.y)
	if cornice:
		# Coving carries over a lintel, but not across a hole that reaches the
		# ceiling.
		for run in _solid_runs(length, holes, false):
			_add_cornice(wall_index, run.x, run.y)

	for i in holes.size():
		var hole: Dictionary = holes[i]
		if bool(hole["is_window"]):
			_add_window_trim(wall_index, hole, i)
			if glazing:
				_add_glazing(wall_index, hole, i)
		else:
			if architrave:
				_add_doorway_trim(wall_index, hole, i)
			if thresholds:
				_add_threshold(wall_index, hole, i)


## The stretches of this wall with something solid at the relevant height, as
## [from, to] pairs along the wall.
func _solid_runs(length: float, holes: Array[Dictionary], at_floor: bool) -> Array[Vector2]:
	var runs: Array[Vector2] = []
	var cursor := -length * 0.5
	for hole in holes:
		var blocks: bool
		if at_floor:
			blocks = float(hole["bottom"]) <= 0.01
		else:
			blocks = float(hole["top"]) >= height - FULL_HEIGHT_MARGIN
		if not blocks:
			continue
		var start: float = clampf(hole["start"], -length * 0.5, length * 0.5)
		var end: float = clampf(hole["end"], -length * 0.5, length * 0.5)
		if start > cursor:
			runs.append(Vector2(cursor, start))
		cursor = maxf(cursor, end)
	if cursor < length * 0.5:
		runs.append(Vector2(cursor, length * 0.5))
	return runs


## Skirting board: a plain run with a small moulded cap, which is what catches
## the light and tells the eye where the floor stops.
func _add_skirting(wall_index: int, from: float, to: float) -> void:
	if to - from <= 0.01:
		return
	var body_h := skirting_height * 0.86
	var cap_h := skirting_height - body_h
	_add_trim_run(wall_index, from, to, body_h * 0.5, body_h, skirting_depth, "Skirt")
	_add_trim_run(wall_index, from, to, body_h + cap_h * 0.5, cap_h, skirting_depth * 1.5, "SkirtCap")


## Coving: two steps, wider at the bottom, so it reads as a moulding from below
## rather than as a strip of paint.
func _add_cornice(wall_index: int, from: float, to: float) -> void:
	if to - from <= 0.01:
		return
	_add_trim_run(wall_index, from, to, height - 0.028, 0.055, 0.03, "Cove")
	_add_trim_run(wall_index, from, to, height - 0.066, 0.022, 0.052, "CoveLip")


## Architrave round a doorway, plus the lining inside the reveal -- the surface
## your eye actually lands on as you walk through.
func _add_doorway_trim(wall_index: int, hole: Dictionary, index: int) -> void:
	var centre_offset: float = hole["centre"]
	var width: float = hole["width"]
	var top: float = hole["top"]
	var w := architrave_width

	# An opening that reaches the ceiling has no lintel to trim, so there is
	# nowhere to put the head: the jambs run up to the ceiling on their own.
	var head_fits := top + w <= height - 0.004
	var jamb_h: float = top + w if head_fits else height - 0.004

	# NOT a ternary. GDScript cannot infer the element type of an array literal
	# that comes out of a conditional expression, so
	#     var sides: Array[float] = [1.0, -1.0] if both else [1.0]
	# compiles cleanly and then fails at RUNTIME with "Trying to assign an array
	# of type Array to a variable of type Array[float]" -- which took out every
	# doorway in the hallway. A packed array has one unambiguous element type and
	# cannot go wrong this way.
	var faces := PackedFloat32Array([1.0])
	if architrave_both_sides:
		faces.append(-1.0)

	for face in faces:
		var tag := "Arch%d%s" % [index, "B" if face < 0.0 else ""]
		_add_trim_run(wall_index, centre_offset - width * 0.5 - w, centre_offset - width * 0.5,
			jamb_h * 0.5, jamb_h, architrave_depth, tag + "L", face)
		_add_trim_run(wall_index, centre_offset + width * 0.5, centre_offset + width * 0.5 + w,
			jamb_h * 0.5, jamb_h, architrave_depth, tag + "R", face)
		if head_fits:
			_add_trim_run(wall_index, centre_offset - width * 0.5 - w,
				centre_offset + width * 0.5 + w,
				top + w * 0.5, w, architrave_depth, tag + "H", face)

	_add_lining(wall_index, hole, index, 0.0)


## Window trim: the lining in the reveal, a projecting sill, a casing round the
## opening and two glazing bars across it.
func _add_window_trim(wall_index: int, hole: Dictionary, index: int) -> void:
	var centre_offset: float = hole["centre"]
	var width: float = hole["width"]
	var bottom: float = hole["bottom"]
	var top: float = hole["top"]
	var tall := top - bottom
	var w := architrave_width

	_add_lining(wall_index, hole, index, bottom)

	# The board under the opening, and the sill that projects into the room --
	# the shelf people put things on, and a strong horizontal the eye reads as a
	# real window rather than a picture of one.
	_add_in_wall(wall_index, centre_offset, bottom - LINING * 0.5, width, LINING,
		wall_thickness, "WinBed%d" % index, trim_surface)
	_add_trim_run(wall_index, centre_offset - width * 0.5 - 0.05, centre_offset + width * 0.5 + 0.05,
		bottom - 0.018, 0.036, 0.15, "WinSill%d" % index)

	# Casing: two jambs and a head, as for a doorway.
	var head_fits := top + w <= height - 0.004
	_add_trim_run(wall_index, centre_offset - width * 0.5 - w, centre_offset - width * 0.5,
		bottom + tall * 0.5, tall, architrave_depth, "WinCase%dL" % index)
	_add_trim_run(wall_index, centre_offset + width * 0.5, centre_offset + width * 0.5 + w,
		bottom + tall * 0.5, tall, architrave_depth, "WinCase%dR" % index)
	if head_fits:
		_add_trim_run(wall_index, centre_offset - width * 0.5 - w, centre_offset + width * 0.5 + w,
			top + w * 0.5, w, architrave_depth, "WinCase%dH" % index)

	# Glazing bars: one upright, one across. Two bars turn a sheet of glass into
	# a window at almost no cost.
	_add_in_wall(wall_index, centre_offset, bottom + tall * 0.5, 0.03, tall,
		0.045, "WinBarV%d" % index, trim_surface)
	_add_in_wall(wall_index, centre_offset, bottom + tall * 0.55, width, 0.03,
		0.045, "WinBarH%d" % index, trim_surface)


## The three or four boards that face the inside of a reveal.
func _add_lining(wall_index: int, hole: Dictionary, index: int, bottom: float) -> void:
	var start: float = hole["start"]
	var end: float = hole["end"]
	var top: float = hole["top"]
	var tall := top - bottom
	if tall <= 0.001:
		return
	var inset := 0.002
	_add_in_wall(wall_index, start + inset, bottom + tall * 0.5, LINING, tall,
		wall_thickness, "Lin%dL" % index, trim_surface)
	_add_in_wall(wall_index, end - inset, bottom + tall * 0.5, LINING, tall,
		wall_thickness, "Lin%dR" % index, trim_surface)
	_add_in_wall(wall_index, hole["centre"], top - LINING * 0.5,
		float(hole["width"]) - inset * 2.0, LINING, wall_thickness,
		"Lin%dT" % index, trim_surface)


## A hardwood strip in the doorway, where two floor finishes meet.
func _add_threshold(wall_index: int, hole: Dictionary, index: int) -> void:
	var thick := 0.008
	_add_in_wall(wall_index, hole["centre"], thick * 0.5, float(hole["width"]),
		thick, wall_thickness + 0.05, "Threshold%d" % index, "oak_wood")


## The pane. Unlike every other piece of joinery here this one is SOLID: a
## StaticBody3D on the world layer, so the teleport arc and the pointer ray stop
## at it exactly as they would at a real window.
func _add_glazing(wall_index: int, hole: Dictionary, index: int) -> void:
	var bottom: float = hole["bottom"]
	var top: float = hole["top"]
	var width: float = hole["width"]
	var pane_w := maxf(width - 0.02, 0.01)
	var pane_h := maxf(top - bottom - 0.02, 0.01)

	var box_size: Vector3
	if wall_index <= 1:
		box_size = Vector3(pane_w, pane_h, 0.014)
	else:
		box_size = Vector3(0.014, pane_h, pane_w)

	var axis := _wall_axis(wall_index)
	# Typed locals rather than `axis["centre"] as Vector3`: `as` is for object
	# types, and using it on a Variant holding a built-in is the kind of thing
	# that parses fine and returns something unexpected at runtime.
	var centre: Vector3 = axis["centre"]
	var along: Vector3 = axis["along"]
	var at := centre + along * float(hole["centre"]) \
		+ Vector3(0.0, (bottom + top) * 0.5, 0.0)
	# Not added to "walkable": a window is not somewhere you can teleport to.
	_add_slab("Glazing%d_%d" % [index, wall_index], box_size, at,
		Color(0.8, 0.88, 0.92, 0.2), glazing_surface)


# ---------------------------------------------------------------------------
#  Trim geometry helpers
# ---------------------------------------------------------------------------

## A length of trim running along a wall, standing `depth` proud of its face.
## `face` is +1 for the inside of the room and -1 for the far side.
func _add_trim_run(wall_index: int, from: float, to: float, centre_y: float,
		tall: float, depth: float, tag: String, face: float = 1.0) -> void:
	var axis := _wall_axis(wall_index)
	var length: float = axis["length"]
	# An architrave beside a doorway close to the end of a wall would otherwise
	# run out past the corner and hang in mid-air.
	var start := clampf(from, -length * 0.5, length * 0.5)
	var end := clampf(to, -length * 0.5, length * 0.5)
	var run := end - start
	if run <= 0.005 or tall <= 0.001:
		return
	var centre: Vector3 = axis["centre"]
	var along: Vector3 = axis["along"]
	var inward: Vector3 = axis["inward"] * face

	var box_size: Vector3
	if wall_index <= 1:
		box_size = Vector3(run, tall, depth)
	else:
		box_size = Vector3(depth, tall, run)

	var at := (centre
		+ along * ((start + end) * 0.5)
		+ inward * (wall_thickness * 0.5 + depth * 0.5)
		+ Vector3(0.0, centre_y, 0.0))
	_add_trim("%s_%d" % [tag, wall_index], box_size, at, trim_surface, 0.004)


## A box sitting INSIDE a wall rather than proud of it: a lining board, a
## glazing bar, a threshold. Positioned by its offset along the wall and its
## centre height, with its own thickness through the wall.
func _add_in_wall(wall_index: int, along_offset: float, centre_y: float,
		along_size: float, up_size: float, through_size: float,
		tag: String, surface: String) -> void:
	if along_size <= 0.001 or up_size <= 0.001:
		return
	var axis := _wall_axis(wall_index)
	var centre: Vector3 = axis["centre"]
	var along: Vector3 = axis["along"]

	var box_size: Vector3
	if wall_index <= 1:
		box_size = Vector3(along_size, up_size, through_size)
	else:
		box_size = Vector3(through_size, up_size, along_size)

	var at := centre + along * along_offset + Vector3(0.0, centre_y, 0.0)
	_add_trim("%s_%d" % [tag, wall_index], box_size, at, surface, 0.003)


## Trim is VISUAL ONLY -- a MeshInstance3D and nothing else. No StaticBody3D, so
## it cannot stop a teleport arc, catch a pointer ray or change what the hand can
## reach. See the note at the top of this file. Window glass is the exception and
## goes through _add_slab instead.
func _add_trim(trim_name: String, box_size: Vector3, at: Vector3,
		surface: String, radius: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	_trim_serial += 1
	mesh_instance.name = "%s_%03d" % [trim_name, _trim_serial]
	mesh_instance.position = at
	mesh_instance.mesh = MeshKit.rounded_box(box_size, radius, 1)
	mesh_instance.material_override = AutoShape.make_material(
		Color("#f3f1ec"), 0.35, 0.0, surface)
	mesh_instance.add_to_group(GROUP)
	add_child(mesh_instance)
	return mesh_instance


# ---------------------------------------------------------------------------
#  Geometry helper
# ---------------------------------------------------------------------------

## A visible box plus a static collision body on layer 1 ("world"), which is the
## layer the teleport arc and the pointer beam stop at.
##
## The generated nodes are deliberately NOT given an owner, even in the editor:
## they are rebuilt from the exported numbers on every load, and owning them
## would write them into the .tscn on save -- after which each reload would add
## another copy on top of the saved one.
func _add_slab(slab_name: String, box_size: Vector3, at: Vector3,
		color: Color, surface: String = "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = slab_name
	body.position = at
	body.collision_layer = 1 << 0
	body.collision_mask = 0
	body.add_to_group(GROUP)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box_size
	shape.shape = box_shape
	body.add_child(shape)

	# Walls and floors keep sharp arrises: they are metres across, the corners
	# are hidden behind skirting and coving, and a fillet there would only cost
	# triangles.
	body.add_child(AutoShape.make_box_mesh(box_size, color, 0.9, surface))
	add_child(body)
	return body
