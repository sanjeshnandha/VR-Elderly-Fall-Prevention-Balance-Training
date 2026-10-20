@tool
class_name GatedRegion
extends Area3D
## Architectural Fix 5.1, part 2 -- the region where free teleport is switched off.
##
## Wrap this around the staircase (and anywhere else where *how* you travel is
## the thing being trained). While the player probe is inside, the teleporter
## drops into "points only" mode: the beam will resolve to an active
## `GatedTeleportPoint` or to nothing at all. Bare floor stops being a
## destination, so the stairs cannot be skipped.
##
## Outside every gated region, teleport behaves normally: aim anywhere on a
## walkable floor. Locomotion friction is applied exactly where it teaches
## something and nowhere else.

signal region_entered
signal region_exited

@export var region_name: String = "staircase"

## Set false to temporarily restore free teleport here (useful when filming a
## demo or when a participant is struggling and needs to be moved along).
@export var enforce: bool = true

## Full size of the auto-generated trigger box, in metres.
@export var extents: Vector3 = Vector3(3.0, 4.0, 4.0)

## Every gated region currently containing the player.
static var _occupied: Array[GatedRegion] = []
## Every gated region in the scene, occupied or not.
static var _all: Array[GatedRegion] = []


func _ready() -> void:
	AutoShape.ensure_box(self, extents)
	if Engine.is_editor_hint():
		return

	if not _all.has(self):
		_all.append(self)
	collision_layer = 0
	collision_mask = 1 << 1  # player probe
	monitoring = true
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _exit_tree() -> void:
	_occupied.erase(self)
	_all.erase(self)


func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player_probe"):
		return
	if not _occupied.has(self):
		_occupied.append(self)
	SessionManager.log_event("gated_region_entered", {"region": region_name})
	region_entered.emit()


func _on_area_exited(area: Area3D) -> void:
	if not area.is_in_group("player_probe"):
		return
	_occupied.erase(self)
	SessionManager.log_event("gated_region_exited", {"region": region_name})
	region_exited.emit()


## True when the player is inside at least one enforcing gated region.
## The teleporter calls this every frame.
static func is_player_gated() -> bool:
	for region in _occupied:
		if is_instance_valid(region) and region.enforce:
			return true
	return false


## True when `world_point` lies inside an enforcing gated region.
##
## This closes the other half of the teleport loophole: without it, a
## participant standing in the hallway (ungated) could aim the beam through the
## doorway and land halfway up the stairs, arriving above the flight without
## ever having held the rail. Gating has to apply to the DESTINATION as well as
## to the origin.
static func is_point_gated(world_point: Vector3) -> bool:
	for region in _all:
		if not is_instance_valid(region) or not region.enforce:
			continue
		var local := region.to_local(world_point)
		var half := region.extents * 0.5
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false
