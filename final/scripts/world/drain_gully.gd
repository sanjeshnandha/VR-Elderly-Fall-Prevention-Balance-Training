@tool
class_name DrainGully
extends Node3D
## An open road gully: the hole, its cast iron frame, and the grating lifted out
## and left on the path beside it.
##
## WHY THIS IS NOT THREE BOXES
##
## It was. A dark flat box for the recess, a thinner one for the frame, and a
## third lying 20 mm above the paving for the lifted cover -- which is what the
## participant actually saw: a dark tile hovering over the path with daylight
## under it, and no hole anywhere. Three separate things were wrong:
##
##   * the cover floated. Its underside was at -0.125 and the paving top is at
##     -0.140, so it hung 15 mm clear and cast a shadow with a gap in it;
##   * the frame was BELOW the paving (top at -0.140 against the paving's
##     -0.140, then buried by the slab's own surface), so no rim read at all;
##   * and the recess could never have read as a hole, because the path is a
##     solid slab and a dark box sitting on top of a solid slab is a stain.
##
## A hole has to be a real gap. The scene therefore paves AROUND this node --
## FrontPath stops short of it, FrontPathBeyond carries on past it, and
## FrontPathWest/East fill the strips either side -- and what is left is a
## genuine opening that this node lines, rims and leaves uncovered. Everything
## here is measured from the PAVING SURFACE, so place the node at the paving top
## and local y = 0 is the ground: nothing can float by construction.
##
## The grating is a grating, not a slab: a rim and seven bars with daylight
## between them. That is what says "this is the thing that should be over the
## hole" at a glance, and it is also why the old one read as a floor tile.

## The opening in the paving, before the frame is added (metres, x by z).
@export var opening: Vector2 = Vector2(0.37, 0.26): set = _set_opening

## Width of the cast iron frame around the opening. The paved gap the scene
## leaves for this node is `opening` plus twice this on each axis.
@export var frame_margin: float = 0.045: set = _set_margin

## How far the frame stands above the paving. Real ones sit a few millimetres
## proud; it is enough to catch the light and to be worth a trip.
@export var frame_proud: float = 0.008

## How far the frame reaches down into the hole.
@export var frame_depth: float = 0.06

## Depth of the shaft. Deep enough that the bottom is in shadow from standing
## height, which is what sells it as a hole rather than a dark patch.
@export var depth: float = 0.42

## Thickness of the shaft lining.
@export var wall: float = 0.04

## Where the BOTTOM EDGE of the lifted grating rests, relative to this node.
##
## The bottom edge rather than the centre, so that leaning it further or less
## far pivots it about the ground instead of sinking it into the ground. Which
## is the whole lesson of the version this replaced: a part placed by its centre
## floats the moment anything about its size changes.
@export var grate_base: Vector3 = Vector3(-1.0, -0.01, 0.95): set = _set_grate_base

## How far the grating is tipped up: 0 is flat on the ground, 90 is standing
## against the wall. A cover left leaning on the garden wall is what a crew
## actually does with it, and it is the one position that cannot read as a
## paving slab.
@export var grate_lean_degrees: float = 68.0: set = _set_lean

## And nobody stands it square to the wall.
@export var grate_yaw_degrees: float = 9.0: set = _set_yaw

## Bars across the grating.
@export var grate_bars: int = 7

## Thickness of the grating. It lies ON the paving, so this is also how far it
## sticks up, and why it is worth walking round.
@export var grate_thickness: float = 0.035

@export var iron_surface: String = "cast_iron"
@export var iron_color: Color = Color(0.29, 0.28, 0.27, 1.0)
@export var shaft_color: Color = Color(0.13, 0.13, 0.12, 1.0)
@export var sump_color: Color = Color(0.05, 0.05, 0.05, 1.0)

## Rebuild now (editor button).
@export var rebuild: bool = false: set = _set_rebuild

const GROUP := "gully_part"
## Arris on the ironwork. Small: a casting is not a sanded table edge.
const ARRIS := 0.004


func _ready() -> void:
	build()


func _set_opening(value: Vector2) -> void:
	opening = value
	if is_inside_tree():
		build()


func _set_margin(value: float) -> void:
	frame_margin = value
	if is_inside_tree():
		build()


func _set_grate_base(value: Vector3) -> void:
	grate_base = value
	if is_inside_tree():
		build()


func _set_lean(value: float) -> void:
	grate_lean_degrees = value
	if is_inside_tree():
		build()


func _set_yaw(value: float) -> void:
	grate_yaw_degrees = value
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

	_spawn("Frame", _frame_mesh(), AutoShape.make_material(
		iron_color, 0.55, 0.65, iron_surface))
	_spawn("Shaft", _shaft_mesh(), AutoShape.make_material(shaft_color, 0.98))

	var grate := _spawn("Grate", _grate_mesh(), AutoShape.make_material(
		iron_color, 0.55, 0.65, iron_surface))
	_place_grate(grate)


## Stand the grating on its bottom edge at `grate_base` and tip it back.
##
## The mesh is built flat, so leaning it is a rotation about X; the centre then
## has to move so that the resting edge stays exactly where it was put. Working
## it out from the edge is what guarantees the thing touches the ground: there
## is no number in the scene file that could be 15 mm wrong.
func _place_grate(grate: MeshInstance3D) -> void:
	var lean := deg_to_rad(grate_lean_degrees)
	var depth_of := (opening.y + frame_margin) * 0.5
	var half_t := grate_thickness * 0.5
	grate.position = grate_base + Vector3(
		0.0,
		depth_of * sin(lean) + half_t * cos(lean),
		depth_of * cos(lean) - half_t * sin(lean))
	grate.rotation_degrees = Vector3(-grate_lean_degrees, grate_yaw_degrees, 0.0)


func _spawn(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.add_to_group(GROUP)
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)
	return mi


## The rim: four bars filling the paved gap, standing `frame_proud` above the
## paving and reaching `frame_depth` down, so the cut edge of the slab is never
## visible.
func _frame_mesh() -> Mesh:
	var outer := opening + Vector2(frame_margin, frame_margin) * 2.0
	var height := frame_proud + frame_depth
	var y := frame_proud - height * 0.5
	var boxes: Array = []
	for sign_z in [-1.0, 1.0]:
		boxes.append({
			"size": Vector3(outer.x, height, frame_margin),
			"centre": Vector3(0.0, y, sign_z * (opening.y + frame_margin) * 0.5),
		})
	for sign_x in [-1.0, 1.0]:
		boxes.append({
			"size": Vector3(frame_margin, height, opening.y),
			"centre": Vector3(sign_x * (opening.x + frame_margin) * 0.5, y, 0.0),
		})
	return _merge(boxes)


## The hole: four walls and a sump. The walls start just under the frame so no
## seam shows between the two, and the sump is darker than the lining because
## the bottom of a gully is wet silt, not concrete.
func _shaft_mesh() -> Mesh:
	var top := -frame_depth * 0.5
	var height := depth - frame_depth * 0.5
	var boxes: Array = []
	for sign_z in [-1.0, 1.0]:
		boxes.append({
			"size": Vector3(opening.x + wall * 2.0, height, wall),
			"centre": Vector3(0.0, top - height * 0.5, sign_z * (opening.y + wall) * 0.5),
			"radius": 0.0,
		})
	for sign_x in [-1.0, 1.0]:
		boxes.append({
			"size": Vector3(wall, height, opening.y),
			"centre": Vector3(sign_x * (opening.x + wall) * 0.5, top - height * 0.5, 0.0),
			"radius": 0.0,
		})
	boxes.append({
		"size": Vector3(opening.x + wall * 2.0, 0.03, opening.y + wall * 2.0),
		"centre": Vector3(0.0, -depth - 0.015, 0.0),
		"radius": 0.0,
	})
	return _merge(boxes)


## The grating, built flat around its own centre: a rim with bars across it and
## daylight in between.
func _grate_mesh() -> Mesh:
	var size := opening + Vector2(frame_margin, frame_margin)
	var rim := frame_margin * 0.8
	var boxes: Array = []
	for sign_z in [-1.0, 1.0]:
		boxes.append({
			"size": Vector3(size.x, grate_thickness, rim),
			"centre": Vector3(0.0, 0.0, sign_z * (size.y - rim) * 0.5),
		})
	for sign_x in [-1.0, 1.0]:
		boxes.append({
			"size": Vector3(rim, grate_thickness, size.y - rim * 2.0),
			"centre": Vector3(sign_x * (size.x - rim) * 0.5, 0.0, 0.0),
		})
	# Bars run the short way across, which is how a gully grating is cast: the
	# gaps lie along the kerb so a wheel crosses them rather than drops in.
	#
	# Gap wider than bar, deliberately. Equal bars and gaps read as a solid dark
	# rectangle from three metres away, which is the mistake the thing this
	# replaced made; at roughly one third bar to two thirds gap you can see
	# daylight through it and it is unmistakably a grating.
	var bars := maxi(grate_bars, 1)
	var span := size.x - rim * 2.0
	var pitch := span / float(bars)
	var bar_w := pitch * 0.38
	for i in bars:
		var x := -span * 0.5 + pitch * (float(i) + 0.5)
		boxes.append({
			"size": Vector3(bar_w, grate_thickness * 0.78, size.y - rim * 2.0),
			"centre": Vector3(x, 0.0, 0.0),
		})
	return _merge(boxes)


## One mesh out of many filleted boxes.
##
## Each part is still a MeshKit box, so the ironwork keeps the arris every other
## prop in the house has, but the result is a single named MeshInstance3D -- one
## draw call, and one thing for `Hazard.highlight_meshes` to point at.
func _merge(boxes: Array) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in boxes:
		var radius: float = b.get("radius", ARRIS)
		var mesh := MeshKit.rounded_box(b["size"], radius)
		st.append_from(mesh, 0, Transform3D(Basis(), b["centre"]))
	st.index()
	return st.commit()
