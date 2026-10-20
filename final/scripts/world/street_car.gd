@tool
class_name StreetCar
extends Node3D
## One slow car on a loop, for the street-crossing exercise.
##
## SAFETY FIRST, DELIBERATELY
## --------------------------
## This cohort is the most susceptible to a startle response in a headset, and
## a vehicle that hits you (or brakes hard at you) is exactly the sort of thing
## that ends a session badly. So:
##
##   * it travels at `speed` -- roughly a brisk cycle, not traffic speed;
##   * it NEVER occupies the participant's space: if they are in the road ahead
##     it eases to a stop well short of them, waits, and moves off again
##     smoothly when the way is clear;
##   * there is no horn, no screech, no collision and no camera movement of any
##     kind. The warning is a spoken, head-locked line.
##
## What it is for is the judgement, not the threat: is there time to cross, is
## the car coming or going, and has the participant looked before stepping out.
## `StreetCrossing` reads `time_to_reach()` to score that.
##
## Between runs the car waits `gap_seconds` off-screen, so there are real gaps
## in the traffic to be found rather than a permanent wall of it.
##
## FOUR OF THEM, IN TWO LANES, OBEYING A SIGNAL.
## The direction of travel comes from `start_x` and `end_x`, so a car in the far
## lane is the same node with those two swapped; it turns itself round and its
## headlights end up at the right end. Each car yields to three things and takes
## whichever is nearest: a person in the road ahead, the car ahead in its own
## lane, and a red light at its stop line. Without the second of those, two cars
## in one lane drive through each other the first time one of them waits.

## Metres per second. 3.5 m/s is about 13 km/h.
@export var speed: float = 3.5

## Where the run starts and ends along X, in local space. Travel direction is
## taken from these: end_x < start_x is a car in the other lane.
@export var start_x: float = -24.0
@export var end_x: float = 24.0

## Seconds of empty road between runs.
@export var gap_seconds: float = 11.0

## Held off-screen this long before its first run, so four cars do not all set
## off together on the first frame.
@export var start_delay: float = 0.0

## Begins slowing this far from anyone standing in the road, measured from the
## NOSE. See _distance_to_person_ahead() for why that word matters.
@export var stopping_distance: float = 6.0

## How far short of a person the nose comes to rest.
@export var person_buffer: float = 1.5

## Inside this, the car stops dead rather than easing down. Somebody stepping
## off the kerb straight in front of a moving car is the one case where a
## smooth deceleration is the wrong answer: at 3.5 m/s, easing to a halt takes
## 1.4 seconds and over two metres, and the participant spends them inside the
## bonnet.
@export var emergency_distance: float = 2.0

## Length of the body, used for the nose position at the stop line and for the
## gap to the car in front.
@export var body_length: float = 4.2

## The signal this car obeys, and the X of the line it must stop at. Leave the
## path empty for a car on a road with no signal.
@export var signal_path: NodePath
@export var stop_line_x: float = -2.8

## Cars within this distance in Z are in the same lane.
@export var lane_tolerance: float = 1.2

## How far either side of this car's own line a person still counts as being in
## front of it. Wider than `lane_tolerance`, because a person standing on the
## lane marking is in the way of both lanes, and because being over-cautious
## about a pedestrian is the correct failure.
@export var person_lane_tolerance: float = 2.4

## Speak a warning when the participant is in the road and the car is closer
## than this.
@export var warn_distance: float = 14.0
@export var warn_cooldown: float = 8.0

@export var body_color: Color = Color("#9c3a34")

var _x: float = 0.0
var _waiting: float = 0.0
var _current_speed: float = 0.0
var _last_warning: float = -999.0
var _probe: Area3D
var _signal: TrafficSignal
var _direction: float = 1.0


func _ready() -> void:
	_direction = 1.0 if end_x >= start_x else -1.0
	_build()
	# Built facing +X; a car going the other way is turned round rather than
	# built mirrored, so the headlights and tail lights stay correct.
	if _direction < 0.0:
		rotation_degrees.y = 180.0
	_x = start_x
	position.x = _x
	if Engine.is_editor_hint():
		set_process(false)
		return
	add_to_group("street_car")
	_waiting = start_delay
	_signal = get_node_or_null(signal_path) as TrafficSignal
	if _signal == null:
		_signal = get_tree().get_first_node_in_group("traffic_signal") as TrafficSignal


func _process(delta: float) -> void:
	if _probe == null or not is_instance_valid(_probe):
		var player := get_tree().get_first_node_in_group("xr_player") as XRPlayer
		_probe = player.probe if player != null else null

	if _waiting > 0.0:
		_waiting -= delta
		visible = false
		return
	if not visible:
		# A car coming back on at the end of the road must not appear on top of
		# the one still crawling away from it. Simulating seven minutes of this
		# street found exactly that: the follower reappeared 1.9 m inside the
		# leader, and because the gap was negative the car-following test
		# ignored it and drove straight through.
		if not _spawn_clear():
			return
		visible = true

	# Three reasons to slow down; obey whichever is nearest.
	var target_speed := speed

	var blocker := _distance_to_person_ahead()
	if blocker >= 0.0 and blocker < stopping_distance:
		target_speed = minf(target_speed, _ramp(blocker, person_buffer))
		_warn()

	# Other people in the road are yielded to as well, and silently: the spoken
	# warning is for the participant. Without this a car would drive through the
	# pedestrian who crosses at the lights, which would rather undo the point of
	# having somebody cross at the lights.
	var walker := _distance_to_pedestrian_ahead()
	if walker >= 0.0 and walker < stopping_distance:
		target_speed = minf(target_speed, _ramp(walker, person_buffer))
		blocker = walker if blocker < 0.0 else minf(blocker, walker)

	var ahead := _distance_to_car_ahead()
	if ahead >= 0.0 and ahead < stopping_distance:
		# _distance_to_car_ahead already subtracts the body length, so this is
		# clear space bumper to bumper and the buffer is a standoff, not another
		# car length. Counting the length twice left an 0.8 m window to stop in,
		# which at 2.5 m/s^2 is not enough, and the cars drove into each other.
		target_speed = minf(target_speed, _ramp(ahead, 1.5))

	var line := _distance_to_stop_line()
	if line >= 0.0:
		target_speed = minf(target_speed, _ramp(line, 0.2))

	_current_speed = move_toward(_current_speed, target_speed, 2.5 * delta)
	# The promise this project makes is that no car will ever touch the
	# participant. Easing down cannot keep it on its own, so inside
	# `emergency_distance` the car simply stops.
	if (blocker >= 0.0 and blocker < emergency_distance) or _person_alongside():
		_current_speed = 0.0

	_x += _current_speed * _direction * delta
	position.x = _x
	if (_x - end_x) * _direction > 0.0:
		_x = start_x
		position.x = _x
		_current_speed = 0.0
		_waiting = gap_seconds


## Speed to aim for when the thing to stop short of is `distance` away and we
## want to be stopped `buffer` short of it.
func _ramp(distance: float, buffer: float) -> float:
	return speed * clampf((distance - buffer) / maxf(stopping_distance - buffer, 0.1), 0.0, 1.0)


## Front of the car, in global X.
func nose_x() -> float:
	return global_position.x + _direction * body_length * 0.5


## Distance from the nose to the stop line, or -1 when there is nothing to stop
## for. A car already over the line keeps going: stopping on the crossing is
## worse than crossing it.
func _distance_to_stop_line() -> float:
	if _signal == null:
		return -1.0
	var to_line := (stop_line_x - nose_x()) * _direction
	if to_line <= 0.0:
		return -1.0
	if _signal.traffic_must_stop():
		return to_line
	# Amber: stop if there is comfortably room to, otherwise clear the junction.
	if _signal.traffic_stopping() and to_line > 4.0:
		return to_line
	return -1.0


## Gap to the back of the nearest car ahead in this lane, or -1 if the lane is
## clear. Without this, two cars in one lane pass through each other the first
## time the leader stops at a red.
func _distance_to_car_ahead() -> float:
	var best := -1.0
	for node in get_tree().get_nodes_in_group("street_car"):
		var other := node as StreetCar
		if other == null or other == self or not other.visible:
			continue
		if absf(other.global_position.z - global_position.z) > lane_tolerance:
			continue
		var along := (other.global_position.x - global_position.x) * _direction
		if along <= 0.0:
			continue                      # that one is behind us
		# Clamped at zero rather than skipped: a car we are already overlapping
		# is the one case where stopping matters most.
		var gap := maxf(along - body_length, 0.0)
		if best < 0.0 or gap < best:
			best = gap
	return best


## Is the start of the lane free enough to come back on?
func _spawn_clear() -> bool:
	for node in get_tree().get_nodes_in_group("street_car"):
		var other := node as StreetCar
		if other == null or other == self or not other.visible:
			continue
		if absf(other.global_position.z - global_position.z) > lane_tolerance:
			continue
		var along := (other.global_position.x - global_position.x) * _direction
		if along > -body_length and along < body_length + 6.0:
			return false
	return true


## Seconds until the car reaches `world_x`, or a big number if it is already
## past it or waiting off-screen. `StreetCrossing` scores the gap with this.
func time_to_reach(world_x: float) -> float:
	if _waiting > 0.0:
		var from_start := (world_x - to_global(Vector3(start_x, 0.0, 0.0)).x) * _direction
		return _waiting + maxf(from_start, 0.0) / maxf(speed, 0.1)
	var ahead := (world_x - global_position.x) * _direction
	if ahead <= 0.0:
		return 999.0  # already past: this car is no longer a reason to wait
	return ahead / maxf(speed, 0.1)


## True while the car is approaching `world_x` rather than receding from it.
##
## A car that is stationary -- held at a red light, or waiting for someone in
## the road -- is not approaching anything, and counting it would mean the
## crossing scored a stopped queue as a reason not to cross, which is the exact
## opposite of what a signal is for.
func is_approaching(world_x: float) -> bool:
	if _waiting > 0.0 or _current_speed < 0.3:
		return false
	return (world_x - global_position.x) * _direction > 0.0


## How far in front of the NOSE the participant is, or -1 if they are not in
## front of this car at all.
##
## From the nose, not from the origin. It used to measure from the origin and
## stop when that was 1.5 m from the person -- but the origin is the middle of
## the car, so on a 4.2 m body the nose was 2.1 m further on, which put it 0.6 m
## PAST the participant. The car stopped exactly as designed, with the
## participant standing inside the bonnet, and from in there it looks like the
## car drove straight through you. Which is what was reported.
func _distance_to_person_ahead() -> float:
	if _probe == null:
		return -1.0
	var probe_position := _probe.global_position
	# Only people actually in front of this car matter.
	if absf(probe_position.z - global_position.z) > person_lane_tolerance:
		return -1.0
	var ahead := (probe_position.x - nose_x()) * _direction
	return ahead if ahead > 0.0 else -1.0


## Is the participant level with the car, rather than in front of it?
##
## `_distance_to_person_ahead()` only sees what is AHEAD of the nose, so
## somebody who teleports beside a moving car, or who is already past the nose
## when it arrives, is invisible to it -- and the car would drive on with them
## inside the bodywork. This is the backstop: anything inside the body plus a
## margin stops the car dead, and it stays stopped until they step clear.
## The nearest OTHER pedestrian in front of this car, or -1.
func _distance_to_pedestrian_ahead() -> float:
	var best := -1.0
	for node in get_tree().get_nodes_in_group("pedestrian"):
		var walker := node as Node3D
		if walker == null:
			continue
		var at := walker.global_position
		if absf(at.z - global_position.z) > person_lane_tolerance:
			continue
		var ahead := (at.x - nose_x()) * _direction
		if ahead <= 0.0:
			continue
		if best < 0.0 or ahead < best:
			best = ahead
	return best


func _person_alongside() -> bool:
	if _probe == null:
		return false
	var at := _probe.global_position
	return absf(at.x - global_position.x) < body_length * 0.5 + 0.6 \
		and absf(at.z - global_position.z) < 1.5


func _warn() -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _last_warning < warn_cooldown:
		return
	_last_warning = now
	AudioCues.play("reminder")
	AudioCues.speak_text("There is a car. Wait on the pavement until it has passed.", true)
	SessionManager.log_event("car_yielded", {"room": "street"})


# ---------------------------------------------------------------------------
#  Blockout car
# ---------------------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_add_box(Vector3(body_length, 0.75, 1.8), Vector3(0.0, 0.62, 0.0), body_color)
	_add_box(Vector3(2.1, 0.55, 1.62), Vector3(-0.15, 1.27, 0.0), Color("#2f3a46"))
	for x in [-1.35, 1.35]:
		for z in [-0.82, 0.82]:
			_add_wheel(Vector3(x, 0.32, z))
	# Lights: white at the front (+X, the way it travels), red at the back.
	for z in [-0.6, 0.6]:
		_add_box(Vector3(0.08, 0.16, 0.3), Vector3(2.06, 0.7, z), Color("#fff3cf"))
		_add_box(Vector3(0.08, 0.16, 0.3), Vector3(-2.06, 0.7, z), Color("#a02a20"))


func _add_box(size: Vector3, offset: Vector3, color: Color) -> void:
	var mesh_instance := AutoShape.make_box_mesh(size, color, 0.45)
	mesh_instance.position = offset
	add_child(mesh_instance)


func _add_wheel(offset: Vector3) -> void:
	var wheel := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.32
	cylinder.bottom_radius = 0.32
	cylinder.height = 0.22
	cylinder.radial_segments = 12
	wheel.mesh = cylinder
	# Cylinders stand along Y; the axle runs across the road (Z).
	wheel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	wheel.position = offset
	wheel.material_override = AutoShape.make_material(Color("#1c1c1f"), 0.9)
	add_child(wheel)
