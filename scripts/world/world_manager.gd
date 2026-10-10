class_name WorldManager
extends Node3D
## Builds the sky, sun/moon, fog and tone mapping of a place and runs the day/night change.
## Put one WorldManager in the main scene and give it a PlaceData.
##
## The day and night skies are real HDR photographs, so the sun does not travel
## across the sky. Instead the two panoramas cross-fade, and the light direction,
## colour, ambient light and fog follow the fade.

const SKY_SHADER: Shader = preload("res://shaders/sky_blend.gdshader")
const DEFAULT_PLACE: String = "res://data/places/forest.tres"

const PRESET_NAMES = ["DAY", "NIGHT"]
const PRESET_HOURS = [15.0, 22.0]
const FADE_SECONDS: float = 2.5

@export var place: PlaceData
@export var shadows_enabled: bool = true
@export var shadow_distance: float = 90.0
@export var glow_enabled: bool = true
## 0 = time stands still. Otherwise one full day takes this many minutes.
@export var cycle_minutes: float = 0.0

## Hour of the day (0-24). Setting it updates the whole look.
var time_of_day: float = 15.0:
	set = set_time_of_day

var _environment: Environment
var _sky: Sky
var _sky_material: ShaderMaterial
var _sun: DirectionalLight3D
var _tween: Tween
var _preset_index: int = 0
var _last_night: float = -1.0
var _sky_dirty: bool = false


func _ready() -> void:
	add_to_group("world_manager")
	if place == null:
		place = load(DEFAULT_PLACE) as PlaceData
	if place == null:
		push_error("WorldManager: no PlaceData assigned and %s was not found." % DEFAULT_PLACE)
		return

	_build_sky()
	_build_environment()
	_build_sun()
	set_time_of_day(place.start_hour)


func _process(delta: float) -> void:
	# The sky's ambient light is only re-rendered every frame while the sky is changing.
	if _sky != null:
		if _sky_dirty:
			_sky_dirty = false
		elif _sky.process_mode != Sky.PROCESS_MODE_AUTOMATIC:
			_sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	if cycle_minutes > 0.0:
		set_time_of_day(time_of_day + delta * 24.0 / (cycle_minutes * 60.0))


func set_time_of_day(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	if _environment != null:
		_apply()


## Switches DAY <-> NIGHT with a smooth fade. Returns the new name for the UI.
func cycle_time_preset() -> String:
	_preset_index = (_preset_index + 1) % PRESET_NAMES.size()
	if _tween != null:
		_tween.kill()
	# TWEEN_PAUSE_PROCESS: the fade also plays while the pause menu is open.
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var target_hour: float = PRESET_HOURS[_preset_index]
	_tween.tween_method(set_time_of_day, time_of_day, target_hour, FADE_SECONDS)
	return String(PRESET_NAMES[_preset_index])


func get_time_label() -> String:
	return String(PRESET_NAMES[_preset_index])


## 0 = full day, 1 = full night. The fade happens around 18:00 and 06:00.
func _night_amount(hour: float) -> float:
	if hour < 12.0:
		return 1.0 - smoothstep(5.5, 6.5, hour)
	return smoothstep(17.5, 18.5, hour)


func _build_sky() -> void:
	_sky = Sky.new()
	_sky.radiance_size = Sky.RADIANCE_SIZE_128

	var day_texture: Texture2D = _load_texture(place.day_sky_path)
	var night_texture: Texture2D = _load_texture(place.night_sky_path)
	if day_texture == null:
		# Never leave the player with a white screen: fall back to a plain sky.
		push_warning("WorldManager: day sky missing, using a procedural sky.")
		_sky.sky_material = ProceduralSkyMaterial.new()
		return

	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	_sky_material.set_shader_parameter("day_sky", day_texture)
	_sky_material.set_shader_parameter("night_sky", night_texture if night_texture != null else day_texture)
	_sky.sky_material = _sky_material


func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = _sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.adjustment_enabled = true
	_environment.adjustment_contrast = 1.05
	_environment.adjustment_saturation = 1.1

	# Distance haze. It does not cover the sky (fog_sky_affect = 0).
	_environment.fog_enabled = true
	_environment.fog_density = place.fog_density
	_environment.fog_sky_affect = 0.0

	# Soft glow around very bright things such as the brake lights.
	_environment.glow_enabled = glow_enabled
	_environment.glow_intensity = 0.5
	_environment.glow_strength = 0.9
	_environment.glow_hdr_threshold = 1.2

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)


func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = shadows_enabled
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = shadow_distance
	add_child(_sun)


func _apply() -> void:
	var night: float = _night_amount(time_of_day)

	if _sky_material != null:
		_sky_material.set_shader_parameter("night_amount", night)
		# While fading, the sky's ambient light must be re-rendered every frame.
		if absf(night - _last_night) > 0.0005:
			_sky.process_mode = Sky.PROCESS_MODE_REALTIME
			_sky_dirty = true
	_last_night = night

	# The light comes from the sun's (or moon's) position in the panorama.
	var toward_light: Vector3 = place.day_sun_direction.normalized().lerp(
		place.night_light_direction.normalized(), night).normalized()
	_sun.transform = Transform3D(Basis.looking_at(-toward_light, Vector3.UP), Vector3.ZERO)
	_sun.light_color = place.sun_color.lerp(place.moon_color, night)
	_sun.light_energy = lerpf(place.sun_energy, place.moon_energy, night)

	_environment.ambient_light_energy = lerpf(place.ambient_energy_day, place.ambient_energy_night, night)
	_environment.tonemap_exposure = lerpf(place.exposure_day, place.exposure_night, night)
	_environment.fog_light_color = place.fog_color_day.lerp(place.fog_color_night, night)


func _load_texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("WorldManager: sky file not found: %s" % path)
		return null
	return load(path) as Texture2D
