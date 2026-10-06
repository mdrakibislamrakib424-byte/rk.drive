class_name SpeedHud
extends Label
## Speedometer shown at the top right. Listens to CarController.speed_changed.

@export var car: CarController
@export var font_size: int = 44

var _connected: bool = false


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(280.0, 0.0)
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 8)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_show_speed(0.0)


func _find_car() -> CarController:
	var found: Node = get_node_or_null("../../Car")
	if found == null:
		found = get_tree().get_first_node_in_group("car")
	return found as CarController


## Connects to the car as soon as it can be found.
## Shows a visible warning if it can't (handy when testing on a phone).
func _process(_delta: float) -> void:
	if _connected:
		return
	if not is_instance_valid(car):
		car = _find_car()
	if is_instance_valid(car):
		car.speed_changed.connect(_show_speed)
		_connected = true
		_show_speed(0.0)
	else:
		text = "CAR NOT FOUND"


func _show_speed(speed_kmh: float) -> void:
	text = "%d km/h" % roundi(speed_kmh)
