@tool
class_name RoomZone
extends Area3D
## Marks the floor area of one room so the session knows where the participant
## is. Drives per-room time, the "you are in your focus room" hint and the live
## per-room scores on the performance board.
##
## One per room scene, sized to the room's interior. Rooms touch at doorways,
## so the probe can briefly be inside two zones; SessionManager treats the most
## recently entered one as current.

## Must match the `room` used by the Hazards in this room.
@export var room: String = "unknown"

## Full size of the auto-generated trigger box, in metres. Usually the room's
## floor size, and as tall as the room.
@export var extents: Vector3 = Vector3(4.0, 2.4, 4.0)


func _ready() -> void:
	AutoShape.ensure_box(self, extents)
	if Engine.is_editor_hint():
		return
	collision_layer = 0
	collision_mask = 1 << 1  # player probe
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("player_probe"):
		SessionManager.enter_room(room)


func _on_area_exited(area: Area3D) -> void:
	if area.is_in_group("player_probe"):
		SessionManager.exit_room(room)
