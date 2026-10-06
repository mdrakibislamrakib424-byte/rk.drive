class_name FollowCamera
extends Camera3D
## Smooth chase camera that follows a vehicle from behind.
## It only follows the vehicle's heading (yaw), so bumps and body roll do not shake the view.

@export var target: VehicleBody3D

@export_group("Position")
@export var distance: float = 7.5
@export var height: float = 2.8
@export var look_height: float = 1.0

@export_group("Smoothing")
@export var position_smoothing: float = 7.0
@export var rotation_smoothing: float = 3.5

@export_group("Field of view")
@export var base_fov: float = 65.0
@export var max_fov_boost: float = 14.0
@export var max_speed_kmh: float = 140.0

var _yaw: float = 0.0


func _ready() -> void:
	if target == null:
		push_error("FollowCamera: 'target' is not assigned.")
		set_process(false)
		return
	fov = base_fov
	_yaw = _get_target_yaw()
	global_position = _get_desired_position()
	_look_at_target()
	make_current()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	_yaw = lerp_angle(_yaw, _get_target_yaw(), 1.0 - exp(-rotation_smoothing * delta))
	global_position = global_position.lerp(
		_get_desired_position(), 1.0 - exp(-position_smoothing * delta))
	_look_at_target()

	# Widen the field of view with speed for a stronger sense of motion.
	var speed_kmh: float = target.linear_velocity.length() * 3.6
	var speed_ratio: float = clampf(speed_kmh / max_speed_kmh, 0.0, 1.0)
	fov = lerpf(fov, base_fov + max_fov_boost * speed_ratio, 1.0 - exp(-3.0 * delta))


## Heading of the vehicle around the Y axis (its forward axis is +Z).
func _get_target_yaw() -> float:
	var forward: Vector3 = target.global_transform.basis.z
	return atan2(forward.x, forward.z)


func _get_desired_position() -> Vector3:
	var heading: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	return target.global_position - heading * distance + Vector3.UP * height


func _look_at_target() -> void:
	look_at(target.global_position + Vector3.UP * look_height, Vector3.UP)
