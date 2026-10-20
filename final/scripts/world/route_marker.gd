@tool
class_name RouteMarker
extends Area3D
## One stop on a room's walking route -- Core System I.
##
## A ring on the floor that the participant has to stand on. Rooms are crossed
## one marker at a time, in order, and the stretch between two markers is a
## "leg" that is judged clean or not (see room_route.gd).
##
## WHY IT DETECTS THE PLAYER RATHER THAN BEING A TELEPORT TARGET.
## The staircase solves a different problem: there, the point of the gating is to
## make it IMPOSSIBLE to skip the stairs, so its discs are the only legal
## teleport destinations and the teleporter refuses everything else. A room is
## not like that. Forcing someone to teleport from ring to ring would make an
## ordinary living room feel like a board game, and it would score the teleporter
## rather than the person.
##
## So a marker is simply a place you have to GET TO, and it does not care how:
## walk there, teleport there, shuffle there in a headset. It fires when the
## player's probe volume enters it. What is judged is the route taken, not the
## method of travel.
##
## Markers never block anything. Collision layer 0, mask = the player probe only:
## nothing can stand on one, bump into one, or have a teleport arc stopped by it.

signal reached(marker: RouteMarker)

enum State { PENDING, NEXT, DONE }

## Stable id for the log. Generated from the room and node name if left empty.
@export var marker_id: String = ""
@export var room: String = "unknown"

## Shown above the ring while it is the one to go to ("by the window").
@export var label_text: String = ""

## Full size of the auto-generated trigger box. Generous on purpose: this is a
## "did you get here", not a precision test, and an older participant should
## never be made to shuffle about hunting for the exact centre.
##
## The one hard rule is that two markers on the same route must not have
## overlapping boxes, or you could satisfy the next ring without leaving the one
## you are standing on -- a free leg. tools/check_project.py enforces it.
@export var extents: Vector3 = Vector3(0.9, 2.0, 0.9): set = _set_extents

@export var outer_radius: float = 0.34: set = _set_outer_radius
@export var inner_radius: float = 0.26

# Amber for "attend to this" and green for "done" are the two states the rest of
# the house already uses -- the focus beacon is amber, a found hazard turns
# green -- so the vocabulary stays consistent. The ring you have to go to is the
# amber one, and it is the ONLY one you can see.
const COLOR_PENDING := Color(0.38, 0.40, 0.44)
const COLOR_NEXT := Color(1.00, 0.72, 0.16)
const COLOR_DONE := Color(0.16, 0.82, 0.38)

## How long a ring stays green after you stand on it before it disappears. Long
## enough to register as "yes, that one counted", short enough that it is gone
## before you look for the next.
const DONE_LINGER_S := 1.2

var state: int = State.PENDING

# One ring at a time. A PENDING ring is not dimmed, it is not drawn at all: the
# participant should see exactly one place to go to, not a trail of five that
# turns the room into a puzzle. _dismissed is the end of the route, when even
# the last green ring goes away.
var _done_timer: float = -1.0
var _dismissed: bool = false

var _ring: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _pulse: float = 0.0


func _ready() -> void:
	AutoShape.ensure_box(self, extents)
	_build_visuals()
	_apply_visual_state()
	if Engine.is_editor_hint():
		return

	if marker_id.is_empty():
		marker_id = "%s_%s" % [room, name.to_snake_case()]

	collision_layer = 0
	collision_mask = 1 << 1          # the player probe, and nothing else
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	set_process(true)


func _process(delta: float) -> void:
	if state == State.DONE and _done_timer > 0.0:
		_done_timer -= delta
		if _done_timer <= 0.0:
			_done_timer = -1.0
			_refresh_ring_visibility()
		return
	if state != State.NEXT or _material == null:
		return
	# A slow breath rather than a flash: anything faster reads as an alarm, and
	# this is an invitation.
	_pulse = fmod(_pulse + delta * 1.6, TAU)
	var glow := 0.75 + 0.45 * (0.5 + 0.5 * sin(_pulse))
	_material.emission_energy_multiplier = glow
	if _ring != null:
		_ring.scale = Vector3.ONE * (1.0 + 0.03 * sin(_pulse))


func set_state(value: int) -> void:
	if state == value:
		return
	state = value
	_pulse = 0.0
	_done_timer = DONE_LINGER_S if state == State.DONE else -1.0
	_apply_visual_state()
	if state == State.NEXT and not Engine.is_editor_hint():
		# The participant may ALREADY be standing where this ring just appeared
		# -- the first ring of the hallway route is right by the welcome panel.
		# area_entered only fires on a crossing, so without this the route would
		# wait forever for them to step onto a spot they never left.
		call_deferred("_check_already_inside")


func _check_already_inside() -> void:
	if state != State.NEXT or not is_inside_tree():
		return
	# One physics frame so the overlap list is populated after the state change.
	await get_tree().physics_frame
	if state != State.NEXT or not is_inside_tree():
		return
	for area in get_overlapping_areas():
		if area.is_in_group("player_probe"):
			reached.emit(self)
			return


## Put the ring away for good: the route is over, or the session ended.
func dismiss() -> void:
	set_shown(false)


## Hide or re-show the ring WITHOUT touching the route's progress. Used when the
## participant steps out of the room part-way through: the room they are not in
## should not be glowing at them through a doorway, but its route is still where
## they left it and comes back lit when they do.
func set_shown(value: bool) -> void:
	_dismissed = not value
	_refresh_ring_visibility()
	if _label != null:
		_label.visible = value and state == State.NEXT and not label_text.is_empty()


## Bring a dismissed route back to its "not started" state (hidden, pending).
func reset() -> void:
	_dismissed = false
	state = State.PENDING
	_pulse = 0.0
	_done_timer = -1.0
	_apply_visual_state()


func _on_area_entered(area: Area3D) -> void:
	if state != State.NEXT or not area.is_in_group("player_probe"):
		return
	reached.emit(self)


# ---------------------------------------------------------------------------
#  Looks
# ---------------------------------------------------------------------------

func _build_visuals() -> void:
	for child in get_children():
		if child.is_in_group("route_marker_visual"):
			child.free()

	_ring = MeshInstance3D.new()
	_ring.add_to_group("route_marker_visual")
	var torus := TorusMesh.new()
	torus.inner_radius = inner_radius
	torus.outer_radius = outer_radius
	torus.rings = 24
	torus.ring_segments = 8
	_ring.mesh = torus
	# A ring rather than a filled disc, so it reads as somewhere to stand rather
	# than something to step over -- and so it is not mistaken for one of the
	# staircase's teleport discs, which are solid.
	_ring.position = Vector3(0.0, 0.035, 0.0)
	add_child(_ring)

	_label = Label3D.new()
	_label.add_to_group("route_marker_visual")
	_label.pixel_size = 0.0012
	_label.font_size = 64
	_label.outline_size = 22
	_label.outline_modulate = Color(0.05, 0.05, 0.05)
	# Full billboard, single sided: these lie on the floor and are often read
	# from almost directly above, where a Y-axis billboard shows its BACK and
	# draws the text mirrored.
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.double_sided = false
	_label.no_depth_test = true
	_label.position = Vector3(0.0, 0.5, 0.0)
	add_child(_label)


func _apply_visual_state() -> void:
	if _ring == null:
		return
	var color := COLOR_PENDING
	var visible_now := not _dismissed
	match state:
		State.NEXT:
			color = COLOR_NEXT
		State.DONE:
			color = COLOR_DONE
		_:
			color = COLOR_PENDING

	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 1.0 if state == State.NEXT else 0.5
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_ring.material_override = _material
	_ring.scale = Vector3.ONE
	_refresh_ring_visibility()

	if _label != null:
		_label.text = label_text if state == State.NEXT else ""
		_label.modulate = color
		_label.visible = visible_now and state == State.NEXT and not label_text.is_empty()


## Exactly one ring is on screen at a time, and none at all until the route
## starts. In the editor every ring is drawn regardless, or they could not be
## placed.
func _refresh_ring_visibility() -> void:
	if _ring == null:
		return
	if Engine.is_editor_hint():
		_ring.visible = true
		return
	match state:
		State.NEXT:
			_ring.visible = not _dismissed
		State.DONE:
			_ring.visible = not _dismissed and _done_timer > 0.0
		_:
			_ring.visible = false


func _set_extents(value: Vector3) -> void:
	extents = value
	if is_inside_tree() and Engine.is_editor_hint():
		for child in get_children():
			if child is CollisionShape3D and child.name == "AutoShape":
				child.free()
		AutoShape.ensure_box(self, extents)


func _set_outer_radius(value: float) -> void:
	outer_radius = value
	if is_inside_tree():
		_build_visuals()
		_apply_visual_state()
