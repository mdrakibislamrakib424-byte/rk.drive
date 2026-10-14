class_name GameHud
extends Control
## Racing HUD drawn in code at the top right: speed, gear (D1-D5 / R / N)
## and an RPM bar, plus a short message when the camera view changes and an optional
## FPS counter (top left). Everything scales with the screen height.

const WHITE: Color = Color(1.0, 1.0, 1.0, 0.95)
const SOFT_WHITE: Color = Color(1.0, 1.0, 1.0, 0.75)
const DIM: Color = Color(1.0, 1.0, 1.0, 0.16)
const ORANGE: Color = Color(1.0, 0.62, 0.1)
const RED: Color = Color(1.0, 0.2, 0.15)
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.85)
const SEGMENTS: int = 24
## The FPS numbers are calculated over this many seconds.
const FPS_WINDOW_SECONDS: float = 5.0

@export var car: CarController

var _camera_rig: FollowCamera

var _show_fps: bool = true
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _window_seconds: float = 0.0
var _fps_average: float = 0.0
var _fps_low: float = 0.0
var _fps_timer: float = 0.0


func _ready() -> void:
	add_to_group("game_hud")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Called by the pause menu.
func toggle_fps() -> void:
	_show_fps = not _show_fps


func is_fps_visible() -> bool:
	return _show_fps


## Finds the car by scene path first, then by the "car" group.
func _find_car() -> CarController:
	var found: Node = get_node_or_null("../../Car")
	if found == null:
		found = get_tree().get_first_node_in_group("car")
	return found as CarController


func _process(delta: float) -> void:
	_record_frame(delta)
	if not is_instance_valid(car):
		car = _find_car()
	if not is_instance_valid(_camera_rig):
		_camera_rig = get_tree().get_first_node_in_group("camera_rig") as FollowCamera
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var u: float = size.y / 720.0
	var right: float = size.x - 36.0 * u

	if _show_fps:
		_draw_fps(font, u)

	if not is_instance_valid(car):
		_text_right(font, "CAR NOT FOUND", right, 60.0 * u, int(32.0 * u), WHITE)
		return

	# Speed.
	_text_right(font, str(roundi(car.get_speed_kmh())), right, 100.0 * u, int(96.0 * u), WHITE)
	_text_right(font, "KM/H", right, 132.0 * u, int(26.0 * u), SOFT_WHITE)

	# RPM bar.
	var bar_width: float = 340.0 * u
	var bar_height: float = 16.0 * u
	var bar_x: float = right - bar_width
	var bar_y: float = 150.0 * u
	var gap: float = 3.0 * u
	var segment_width: float = (bar_width - gap * float(SEGMENTS - 1)) / float(SEGMENTS)
	var rpm: float = car.get_rpm_ratio()
	for i: int in SEGMENTS:
		var position_ratio: float = float(i + 1) / float(SEGMENTS)
		var color: Color = DIM
		if position_ratio <= rpm + 0.001:
			if position_ratio < 0.7:
				color = WHITE
			elif position_ratio < 0.85:
				color = ORANGE
			else:
				color = RED
		var x: float = bar_x + float(i) * (segment_width + gap)
		draw_rect(Rect2(x, bar_y, segment_width, bar_height), color)

	# Gear, left of the RPM bar.
	var gear_text: String = car.get_gear_text()
	var gear_color: Color = WHITE
	if gear_text == "R":
		gear_color = ORANGE
	elif gear_text == "N":
		gear_color = SOFT_WHITE
	_text_right(font, gear_text, bar_x - 20.0 * u, bar_y + bar_height, int(46.0 * u), gear_color)

	# Handbrake warning.
	if car.handbrake_active:
		_text_left(font, "HANDBRAKE", bar_x, 132.0 * u, int(24.0 * u), RED)

	_draw_camera_message(font, u)


func _text_right(font: Font, text: String, right_x: float, baseline_y: float, font_size: int, color: Color) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text_left(font, text, right_x - width, baseline_y, font_size, color)


func _text_left(font: Font, text: String, left_x: float, baseline_y: float, font_size: int, color: Color) -> void:
	var position_xy: Vector2 = Vector2(left_x, baseline_y)
	var outline_size: int = int(maxf(2.0, float(font_size) * 0.12))
	draw_string_outline(font, position_xy, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, OUTLINE)
	draw_string(font, position_xy, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Shows "CAMERA: <view>" in the top centre for a moment after the view changes.
func _draw_camera_message(font: Font, u: float) -> void:
	if not is_instance_valid(_camera_rig):
		return
	var age: int = Time.get_ticks_msec() - _camera_rig.mode_changed_at_ms
	if age < 0 or age > 1800:
		return
	var alpha: float = 1.0 - smoothstep(1200.0, 1800.0, float(age))
	var label: String = "CAMERA: " + _camera_rig.get_mode_name()
	var font_size: int = int(34.0 * u)
	var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var position_xy: Vector2 = Vector2((size.x - width) * 0.5, 190.0 * u)
	draw_string_outline(font, position_xy, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		int(maxf(2.0, float(font_size) * 0.12)), Color(0.0, 0.0, 0.0, 0.85 * alpha))
	draw_string(font, position_xy, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(1.0, 1.0, 1.0, alpha))


## Remembers how long the last frames took (the last few seconds).
func _record_frame(delta: float) -> void:
	_frame_times.append(delta)
	_window_seconds += delta
	while _window_seconds > FPS_WINDOW_SECONDS and _frame_times.size() > 1:
		_window_seconds -= _frame_times[0]
		_frame_times.remove_at(0)

	# Recalculate twice a second, so the numbers are readable.
	_fps_timer += delta
	if _fps_timer < 0.5 or _window_seconds <= 0.0:
		return
	_fps_timer = 0.0
	var slowest: float = 0.0001
	for frame_time: float in _frame_times:
		slowest = maxf(slowest, frame_time)
	_fps_average = float(_frame_times.size()) / _window_seconds
	_fps_low = 1.0 / slowest


## "FPS 58  LOW 41": average over the last seconds, and the worst single frame in that time.
## Green is smooth (50+), orange is playable (30-50), red is laggy (under 30).
func _draw_fps(font: Font, u: float) -> void:
	var color: Color = Color(0.5, 1.0, 0.55)
	if _fps_average < 30.0:
		color = RED
	elif _fps_average < 50.0:
		color = ORANGE
	var label: String = "FPS %d   LOW %d" % [roundi(_fps_average), roundi(_fps_low)]
	_text_left(font, label, 28.0 * u, 160.0 * u, int(26.0 * u), color)
