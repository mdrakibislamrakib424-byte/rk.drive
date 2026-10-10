class_name FollowCamera
extends Camera3D
## Camera rig with three views (switch with the CAM pad or the C key):
##   CHASE     behind the car (default)
##   TOP VIEW  straight above the car; the road ahead is at the top of the screen
##   COCKPIT   inside the car, at the driver's eyes
## Changing the view blends smoothly instead of cutting.
##
## The chase view only follows the car's heading (yaw), so bumps and body roll do
## not shake the picture. At speed it pulls back, widens the field of view, and
## during a slide it swings towards the direction the car is really travelling.

signal mode_changed(mode_name: String)

enum Mode { CHASE, TOP_VIEW, COCKPIT }

const MODE_NAMES = ["CHASE", "TOP VIEW", "COCKPIT"]
## How long a view change blends, in seconds.
const TRANSITION_TIME: float = 0.6
const TRANSITION_SPEED: float = 9.0

@export var target: VehicleBody3D
@export var start_mode: Mode = Mode.CHASE

@export_group("Chase view")
@export var distance: float = 7.5
## Extra distance at max speed.
@export var speed_distance_extra: float = 1.8
@export var height: float = 2.8
@export var look_height: float = 1.0
@export var position_smoothing: float = 7.0
@export var rotation_smoothing: float = 3.5
## 0 = always behind the car's nose, 1 = follows the direction of travel in a slide.
@export_range(0.0, 1.0) var drift_follow: float = 0.45
@export var base_fov: float = 65.0
@export var max_fov_boost: float = 14.0

@export_group("Top view")
## Height above the car in metres (more at speed, to see further ahead).
@export var top_height: float = 22.0
@export var top_height_speed_extra: float = 16.0
## The view is moved this far ahead of the car, so more road is visible in front.
@export var top_look_ahead: float = 8.0
@export var top_fov: float = 55.0

@export_group("Cockpit view")
## Driver's eye position relative to the car (x = left of the centre, y = up, z = forward).
@export var cockpit_eye: Vector3 = Vector3(0.37, 0.95, 0.12)
@export var cockpit_fov: float = 78.0
@export var cockpit_fov_boost: float = 8.0
## How much the view turns into a corner (relative to the steering angle).
@export var cockpit_look_into_turn: float = 0.6
## 0 = the view rolls with the car, 1 = the horizon always stays level.
@export_range(0.0, 1.0) var cockpit_level_horizon: float = 0.5

@export_group("Fallback")
## Used when the target is not a CarController (a CarController supplies its own max speed).
@export var max_speed_kmh: float = 140.0

## 0 = CHASE, 1 = TOP_VIEW, 2 = COCKPIT.
var mode: int = Mode.CHASE
## Time (msec) of the last view change, the HUD uses it to show the view name.
var mode_changed_at_ms: int = -100000

var _yaw: float = 0.0
var _speed_ratio: float = 0.0
var _chase_position: Vector3 = Vector3.ZERO
var _cockpit_turn: float = 0.0
var _transition_left: float = 0.0
var _bound: bool = false


func _ready() -> void:
	add_to_group("camera_rig")
	fov = base_fov
	mode = start_mode
	make_current()
	_bind_target()


## Switches CHASE -> TOP VIEW -> COCKPIT -> CHASE ... Returns the new view name.
func cycle_mode() -> String:
	set_mode((mode + 1) % MODE_NAMES.size())
	return get_mode_name()


func set_mode(new_mode: int) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	_transition_left = TRANSITION_TIME
	mode_changed_at_ms = Time.get_ticks_msec()
	mode_changed.emit(get_mode_name())


func get_mode_name() -> String:
	return String(MODE_NAMES[mode])


## Finds the car (scene wiring first, then node name, then "car" group)
## and snaps behind it once. Retries every frame until the car exists,
## so the camera can never get stuck at the world origin again.
func _bind_target() -> bool:
	if _bound and is_instance_valid(target):
		return true
	if not is_instance_valid(target):
		var found: Node = get_node_or_null("../Car")
		if found == null:
			found = get_tree().get_first_node_in_group("car")
		target = found as VehicleBody3D
	if not is_instance_valid(target):
		return false
	_bound = true
	_update_speed_ratio()
	_yaw = _get_target_yaw()
	_chase_position = _chase_desired_position()
	global_transform = _wanted_transform()
	fov = _wanted_fov()
	return true


func _process(delta: float) -> void:
	if not _bind_target():
		return
	_update_speed_ratio()

	# The chase state is updated in every view, so switching back is smooth.
	_yaw = lerp_angle(_yaw, _get_target_yaw(), 1.0 - exp(-rotation_smoothing * delta))
	_chase_position = _chase_position.lerp(
		_chase_desired_position(), 1.0 - exp(-position_smoothing * delta))
	_cockpit_turn = lerpf(
		_cockpit_turn, target.steering * cockpit_look_into_turn, 1.0 - exp(-6.0 * delta))

	var wanted: Transform3D = _wanted_transform()
	if _transition_left > 0.0:
		_transition_left -= delta
		global_transform = global_transform.interpolate_with(
			wanted, 1.0 - exp(-TRANSITION_SPEED * delta))
	else:
		global_transform = wanted
	fov = lerpf(fov, _wanted_fov(), 1.0 - exp(-3.0 * delta))


func _wanted_transform() -> Transform3D:
	match mode:
		Mode.TOP_VIEW:
			return _top_transform()
		Mode.COCKPIT:
			return _cockpit_transform()
	return _chase_transform()


func _wanted_fov() -> float:
	match mode:
		Mode.TOP_VIEW:
			return top_fov
		Mode.COCKPIT:
			return cockpit_fov + cockpit_fov_boost * _speed_ratio
	return base_fov + max_fov_boost * _speed_ratio


func _update_speed_ratio() -> void:
	var top_speed: float = max_speed_kmh
	if target is CarController:
		top_speed = (target as CarController).max_speed_kmh
	var speed_kmh: float = target.linear_velocity.length() * 3.6
	_speed_ratio = clampf(speed_kmh / maxf(top_speed, 1.0), 0.0, 1.0)


## Heading of the vehicle around the Y axis (its forward axis is +Z).
## While sliding forwards, it blends towards the direction of travel.
func _get_target_yaw() -> float:
	var forward: Vector3 = target.global_transform.basis.z
	var heading_yaw: float = atan2(forward.x, forward.z)

	var velocity: Vector3 = target.linear_velocity
	var forward_speed: float = forward.dot(velocity)
	if drift_follow > 0.0 and forward_speed > 6.0:
		var travel_yaw: float = atan2(velocity.x, velocity.z)
		var weight: float = drift_follow * clampf((forward_speed - 6.0) / 10.0, 0.0, 1.0)
		return lerp_angle(heading_yaw, travel_yaw, weight)
	return heading_yaw


func _chase_desired_position() -> Vector3:
	var heading: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var back: float = distance + speed_distance_extra * _speed_ratio
	return target.global_position - heading * back + Vector3.UP * height


func _chase_transform() -> Transform3D:
	var look_point: Vector3 = target.global_position + Vector3.UP * look_height
	return Transform3D(Basis.looking_at(look_point - _chase_position, Vector3.UP), _chase_position)


## Straight down. The camera's "up" on the screen is the direction the car is heading.
func _top_transform() -> Transform3D:
	var heading: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var height_now: float = top_height + top_height_speed_extra * _speed_ratio
	var ahead: float = top_look_ahead * (0.4 + 0.6 * _speed_ratio)
	var position_now: Vector3 = target.global_position + heading * ahead + Vector3.UP * height_now
	var right: Vector3 = heading.cross(Vector3.UP).normalized()
	return Transform3D(Basis(right, heading, Vector3.UP), position_now)


## Exactly at the driver's eyes. No smoothing, so the car's interior never "swims".
func _cockpit_transform() -> Transform3D:
	var car_transform: Transform3D = target.global_transform
	var up: Vector3 = car_transform.basis.y.lerp(Vector3.UP, cockpit_level_horizon).normalized()
	var forward: Vector3 = car_transform.basis.z.normalized().rotated(
		car_transform.basis.y.normalized(), _cockpit_turn)
	var eye: Vector3 = car_transform * cockpit_eye
	return Transform3D(Basis.looking_at(forward, up), eye)
