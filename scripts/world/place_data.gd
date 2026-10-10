class_name PlaceData
extends Resource
## Everything that makes one place (forest, desert, snow...) look and feel different.
## To add a new place: copy data/places/forest.tres, change the values, done.

@export var display_name: String = "Place"

@export_group("Sky")
## Equirectangular HDR panoramas (.hdr) for day and night.
@export_file("*.hdr") var day_sky_path: String = ""
@export_file("*.hdr") var night_sky_path: String = ""
## Direction TOWARDS the sun inside the day panorama (where the brightest spot is).
@export var day_sun_direction: Vector3 = Vector3(0.0, 0.5, -1.0)
## Direction TOWARDS the moon / main light of the night panorama.
@export var night_light_direction: Vector3 = Vector3(0.0, 0.7, -0.7)

@export_group("Light")
@export var sun_color: Color = Color(1.0, 0.93, 0.8)
@export var sun_energy: float = 2.5
@export var moon_color: Color = Color(0.55, 0.68, 1.0)
@export var moon_energy: float = 0.5
## Fill light that comes from the sky (it lights the shadows).
@export var ambient_energy_day: float = 2.5
@export var ambient_energy_night: float = 5.0
@export var exposure_day: float = 1.0
@export var exposure_night: float = 1.2

@export_group("Fog")
@export var fog_color_day: Color = Color(0.45, 0.5, 0.5)
@export var fog_color_night: Color = Color(0.05, 0.06, 0.09)
@export var fog_density: float = 0.003

@export_group("Time")
## Hour of the day when the place starts (0-24). 12 = noon.
@export_range(0.0, 24.0) var start_hour: float = 15.0
