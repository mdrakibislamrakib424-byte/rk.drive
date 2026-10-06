class_name TouchControls
extends Control
## On-screen driving pad drawn entirely in code (multi-touch capable).
## Also reads the keyboard (WASD / arrows / Space) so the game can be tested on PC.
## Place under a CanvasLayer and point `car` at the CarController node.

enum Pad { LEFT, RIGHT, GAS, BRAKE, HANDBRAKE }

const COLOR_IDLE: Color = Color(1.0, 1.0, 1.0, 0.18)
const COLOR_ACTIVE: Color = Color(1.0, 1.0, 1.0, 0.45)
const COLOR_RING: Color = Color(1.0, 1.0, 1.0, 0.6)
const COLOR_TEXT: Color = Color(1.0, 1.0, 1.0, 0.9)
## Touch hit area is slightly larger than the drawn circle (easier on thumbs).
const HIT_PADDING: float = 1.15

@export var car: CarController
@export_range(0.5, 2.0, 0.05) var button_scale: float = 1.0

var _centers: Array[Vector2] = []
var _radii: Array[float] = []
var _labels: Array[String] = ["<", ">", "GAS", "BRAKE", "HAND"]
var _pressed: Array[bool] = [false, false, false, false, false]
## Touch finger index -> Pad enum value.
var _touch_to_pad: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _notification(what: int) -> void:
	# Release every finger if the app loses focus, so the car never gets stuck on gas.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_to_pad.clear()
		_refresh_pressed()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_assign_touch(touch.index, touch.position)
		else:
			_release_touch(touch.index)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		_assign_touch(drag.index, drag.position)


## Finds the car by scene path first, then by the "car" group.
func _find_car() -> CarController:
	var found: Node = get_node_or_null("../../Car")
	if found == null:
		found = get_tree().get_first_node_in_group("car")
	return found as CarController


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(car):
		car = _find_car()
	if not is_instance_valid(car):
		return

	var left: bool = _pressed[Pad.LEFT] or _key(KEY_A) or _key(KEY_LEFT)
	var right: bool = _pressed[Pad.RIGHT] or _key(KEY_D) or _key(KEY_RIGHT)
	var gas: bool = _pressed[Pad.GAS] or _key(KEY_W) or _key(KEY_UP)
	var brake_pressed: bool = _pressed[Pad.BRAKE] or _key(KEY_S) or _key(KEY_DOWN)
	var hand: bool = _pressed[Pad.HANDBRAKE] or _key(KEY_SPACE)

	# Godot's VehicleBody3D: positive steering turns LEFT.
	var steer: float = (1.0 if left else 0.0) - (1.0 if right else 0.0)
	car.set_inputs(1.0 if gas else 0.0, 1.0 if brake_pressed else 0.0, steer, hand)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for i: int in _centers.size():
		var fill: Color = COLOR_ACTIVE if _pressed[i] else COLOR_IDLE
		draw_circle(_centers[i], _radii[i], fill)
		draw_arc(_centers[i], _radii[i], 0.0, TAU, 48, COLOR_RING, 3.0, true)
		var font_size: int = int(_radii[i] * 0.4)
		var text_width: float = font.get_string_size(
			_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var text_pos: Vector2 = _centers[i] + Vector2(-text_width * 0.5, font_size * 0.35)
		draw_string(font, text_pos, _labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_TEXT)


func _key(keycode: Key) -> bool:
	return Input.is_physical_key_pressed(keycode)


## Positions the five pads relative to the current screen size.
func _update_layout() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var margin: float = screen.y * 0.04
	var r_big: float = screen.y * 0.12 * button_scale
	var r_gas: float = r_big * 1.25
	var r_small: float = r_big * 0.8

	var left_center: Vector2 = Vector2(margin + r_big, screen.y - margin - r_big)
	var right_center: Vector2 = left_center + Vector2(r_big * 2.0 + margin, 0.0)
	var gas_center: Vector2 = Vector2(screen.x - margin - r_gas, screen.y - margin - r_gas)
	var brake_center: Vector2 = Vector2(gas_center.x - r_gas - margin - r_big, screen.y - margin - r_big)
	var hand_center: Vector2 = Vector2(brake_center.x, brake_center.y - r_big - margin - r_small)

	_centers = [left_center, right_center, gas_center, brake_center, hand_center]
	_radii = [r_big, r_big, r_gas, r_big, r_small]
	queue_redraw()


func _pad_at(pos: Vector2) -> int:
	for i: int in _centers.size():
		if pos.distance_to(_centers[i]) <= _radii[i] * HIT_PADDING:
			return i
	return -1


func _assign_touch(index: int, pos: Vector2) -> void:
	var pad: int = _pad_at(pos)
	if pad == -1:
		_touch_to_pad.erase(index)
	else:
		_touch_to_pad[index] = pad
	_refresh_pressed()


func _release_touch(index: int) -> void:
	_touch_to_pad.erase(index)
	_refresh_pressed()


func _refresh_pressed() -> void:
	var next: Array[bool] = [false, false, false, false, false]
	for pad: int in _touch_to_pad.values():
		next[pad] = true
	if next != _pressed:
		_pressed = next
		queue_redraw()
