@tool
class_name BalanceOrb
extends Area3D
## The glowing reach target for Core System C.
##
## Counts as touched either by the hand entering it or by the grip being closed
## on it. Two ways to succeed, because a participant with arthritis may not be
## able to close a grip and must not be blocked by that.

signal touched

## Metres. Generous: the exercise measures *how they reach*, not fine motor aim.
@export var radius: float = 0.09

const COLOR_IDLE := Color(1.0, 0.82, 0.15)
const COLOR_HIT := Color(0.15, 0.95, 0.35)

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _armed: bool = false
var _pulse: float = 0.0


func _ready() -> void:
	# Layer 4 "grabbable" so the hand's grab detector sees it with no extra
	# wiring; masks layer 7 "hand" so a plain touch registers too.
	collision_layer = 1 << 3
	collision_mask = 1 << 6
	monitoring = true
	monitorable = true

	_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_shape.shape = sphere
	add_child(_shape)

	_mesh = MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	_mesh.mesh = sphere_mesh
	add_child(_mesh)

	update_configuration_warnings()

	if Engine.is_editor_hint():
		set_process(false)
		return
	area_entered.connect(_on_area_entered)
	set_armed(false)


## Show and enable the orb. Disarmed orbs are invisible and cannot be touched,
## so an early reach during the countdown does not end the trial.
func set_armed(value: bool) -> void:
	_armed = value
	visible = value
	monitoring = value
	_shape.disabled = not value
	_apply_color(COLOR_IDLE)
	set_process(value)


func _process(delta: float) -> void:
	# Slow pulse. Movement draws the eye far more reliably than brightness alone
	# for users with reduced contrast sensitivity.
	_pulse += delta * 2.4
	var scale_factor := 1.0 + sin(_pulse) * 0.10
	_mesh.scale = Vector3.ONE * scale_factor


func _on_area_entered(_area: Area3D) -> void:
	# Anything on the grabbable mask reaching us is a hand.
	_register_touch()


## Called by GrabController when the grip closes on the orb.
func grab(_hand: Node3D) -> bool:
	_register_touch()
	return false  # never actually held; the touch is the whole interaction


func _register_touch() -> void:
	if not _armed:
		return
	_armed = false
	monitoring = false
	_shape.disabled = true
	_apply_color(COLOR_HIT)
	AudioCues.play("success")
	touched.emit()


func _apply_color(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = mat
