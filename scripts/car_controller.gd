class_name CarController
extends VehicleBody3D
## Arcade-realistic vehicle controller.
## Input is decoupled: touch UI, AI traffic or tests only call set_inputs().
## NOTE: VehicleBody3D drives towards its local +Z axis (Vector3.MODEL_FRONT).

signal speed_changed(speed_kmh: float)

@export_group("Engine")
@export var max_engine_force: float = 2200.0
@export var max_reverse_force: float = 1200.0
@export var max_brake_force: float = 70.0
@export var handbrake_force: float = 120.0
## Light braking while coasting, so the car slows down on its own.
@export var coast_brake: float = 1.5
@export var max_speed_kmh: float = 140.0
@export var max_reverse_speed_kmh: float = 35.0

@export_group("Steering")
@export var max_steer_angle_deg: float = 32.0
@export var steer_response: float = 4.0
## 0.0 = no reduction, 1.0 = full reduction at max speed.
@export_range(0.0, 1.0) var high_speed_steer_reduction: float = 0.6

var throttle_input: float = 0.0
var brake_input: float = 0.0
var steer_input: float = 0.0
var handbrake_active: bool = false

var _current_steer: float = 0.0
var _last_reported_speed: int = -1


func _ready() -> void:
	# Validate setup early so scene mistakes are easy to find.
	var wheel_count: int = 0
	for child: Node in get_children():
		if child is VehicleWheel3D:
			wheel_count += 1
	if wheel_count < 4:
		push_warning("CarController: expected 4 VehicleWheel3D children, found %d." % wheel_count)


## Single entry point for all input sources.
func set_inputs(throttle: float, brake_amount: float, steer: float, use_handbrake: bool = false) -> void:
	throttle_input = clampf(throttle, 0.0, 1.0)
	brake_input = clampf(brake_amount, 0.0, 1.0)
	steer_input = clampf(steer, -1.0, 1.0)
	handbrake_active = use_handbrake


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


## Positive when moving forward (the vehicle's forward axis is +Z).
func get_forward_speed() -> float:
	return global_transform.basis.z.dot(linear_velocity)


func _physics_process(delta: float) -> void:
	_apply_drive()
	_apply_steering(delta)
	_report_speed()


func _apply_drive() -> void:
	var forward_speed: float = get_forward_speed()
	var speed_kmh: float = get_speed_kmh()
	var force: float = 0.0
	var brake_value: float = 0.0

	if throttle_input > 0.0:
		if forward_speed < -1.0:
			# Rolling backwards: brake first, then drive forward.
			brake_value = throttle_input * max_brake_force
		elif speed_kmh < max_speed_kmh:
			force = throttle_input * max_engine_force
	elif brake_input > 0.0:
		if forward_speed > 1.0:
			# Still rolling forward: brake.
			brake_value = brake_input * max_brake_force
		elif speed_kmh < max_reverse_speed_kmh:
			# Stopped or rolling backward: reverse.
			force = -brake_input * max_reverse_force
	else:
		brake_value = coast_brake

	if handbrake_active:
		brake_value = handbrake_force

	engine_force = force
	brake = brake_value


func _apply_steering(delta: float) -> void:
	# Less steering at high speed keeps the car stable.
	var speed_ratio: float = clampf(get_speed_kmh() / max_speed_kmh, 0.0, 1.0)
	var limit: float = deg_to_rad(max_steer_angle_deg) * (1.0 - speed_ratio * high_speed_steer_reduction)
	var target: float = steer_input * limit
	_current_steer = lerpf(_current_steer, target, clampf(steer_response * delta, 0.0, 1.0))
	steering = _current_steer


func _report_speed() -> void:
	var rounded: int = roundi(get_speed_kmh())
	if rounded != _last_reported_speed:
		_last_reported_speed = rounded
		speed_changed.emit(float(rounded))
