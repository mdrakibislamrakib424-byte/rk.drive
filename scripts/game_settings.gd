class_name GameSettings
extends RefCounted
## Saved player settings (kept between games in user://settings.cfg).
## Graphics quality: 0 = LOW, 1 = MEDIUM, 2 = HIGH.

const FILE_PATH: String = "user://settings.cfg"
const QUALITY_NAMES = ["LOW", "MEDIUM", "HIGH"]
const DEFAULT_QUALITY: int = 2

static var _quality: int = -1


static func get_quality() -> int:
	if _quality < 0:
		_quality = DEFAULT_QUALITY
		var config: ConfigFile = ConfigFile.new()
		if config.load(FILE_PATH) == OK:
			_quality = clampi(int(config.get_value("graphics", "quality", DEFAULT_QUALITY)), 0, 2)
	return _quality


static func set_quality(value: int) -> void:
	_quality = clampi(value, 0, 2)
	var config: ConfigFile = ConfigFile.new()
	config.load(FILE_PATH)
	config.set_value("graphics", "quality", _quality)
	config.save(FILE_PATH)


static func get_quality_name() -> String:
	return String(QUALITY_NAMES[get_quality()])
