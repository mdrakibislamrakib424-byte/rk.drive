class_name RoadBuilder
extends Node3D
## Builds the road (asphalt with lane lines) and the dirt shoulders next to it
## from the RoadLayout centre line. Everything is created in code at start-up.
##
## The Road007 texture is one tile wide: left edge line, dashed centre line,
## right edge line. At 8.27 m wide the lanes are 3.5 m and the lines 12 cm,
## like a real road. The tile is stretched along the road so one dash is 3 m.

const TEXTURE_DIR: String = "res://assets/textures/"

@export var road_width: float = 8.27
@export var shoulder_width: float = 1.8
## Length of one texture tile along the road (one tile holds 4 dashes).
@export var tile_length: float = 24.0
## Distance between two points of the centre line.
@export var sample_spacing: float = 2.0
## Size in metres of one tile of the shoulder (dirt) texture.
@export var shoulder_tile_size: float = 4.0
## Shoulder height relative to the road (slightly lower, so there is no flicker).
@export var shoulder_drop: float = 0.012
@export var shoulder_tint: Color = Color(0.62, 0.57, 0.5)


func _ready() -> void:
	var centerline: PackedVector3Array = RoadLayout.build_centerline(sample_spacing)
	if centerline.size() < 4:
		push_error("RoadBuilder: the road layout has too few points.")
		return

	# Make the texture repeat a whole number of times around the loop,
	# so the dashed line has no jump where the loop closes.
	var loop_length: float = _loop_length(centerline)
	var tiles: int = maxi(1, roundi(loop_length / tile_length))
	var tile: float = loop_length / float(tiles)

	var sides: Array[Vector3] = _side_vectors(centerline)
	_add_mesh("Asphalt", _build_asphalt(centerline, sides, tile), _asphalt_material(), false)
	_add_mesh("Shoulders", _build_shoulders(centerline, sides), _shoulder_material(), false)


func _add_mesh(mesh_name: String, mesh: ArrayMesh, material: Material, casts_shadow: bool) -> void:
	mesh.surface_set_material(0, material)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	if not casts_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _loop_length(line: PackedVector3Array) -> float:
	var total: float = 0.0
	for i: int in line.size():
		total += line[i].distance_to(line[(i + 1) % line.size()])
	return total


## For every centre point: the sideways direction (towards the car's left, +X when driving +Z).
func _side_vectors(line: PackedVector3Array) -> Array[Vector3]:
	var sides: Array[Vector3] = []
	var count: int = line.size()
	for i: int in count:
		var tangent: Vector3 = (line[(i + 1) % count] - line[(i - 1 + count) % count]).normalized()
		sides.append(Vector3.UP.cross(tangent).normalized())
	return sides


func _build_asphalt(line: PackedVector3Array, sides: Array[Vector3], tile: float) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = road_width * 0.5
	var count: int = line.size()
	var distance: float = 0.0
	for i: int in count:
		var j: int = (i + 1) % count
		var step: float = line[i].distance_to(line[j])
		var v0: float = distance / tile
		var v1: float = (distance + step) / tile
		var left_a: Vector3 = line[i] + sides[i] * half
		var right_a: Vector3 = line[i] - sides[i] * half
		var left_b: Vector3 = line[j] + sides[j] * half
		var right_b: Vector3 = line[j] - sides[j] * half
		_add_quad(surface, left_a, right_a, right_b, left_b,
			Vector2(0.0, v0), Vector2(1.0, v0), Vector2(1.0, v1), Vector2(0.0, v1))
		distance += step
	surface.generate_tangents()
	return surface.commit()


func _build_shoulders(line: PackedVector3Array, sides: Array[Vector3]) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: float = road_width * 0.5
	var outer: float = inner + shoulder_width
	var drop: Vector3 = Vector3(0.0, -shoulder_drop, 0.0)
	var count: int = line.size()
	for i: int in count:
		var j: int = (i + 1) % count
		for direction: float in [1.0, -1.0]:
			var in_a: Vector3 = line[i] + sides[i] * inner * direction + drop
			var out_a: Vector3 = line[i] + sides[i] * outer * direction + drop
			var in_b: Vector3 = line[j] + sides[j] * inner * direction + drop
			var out_b: Vector3 = line[j] + sides[j] * outer * direction + drop
			# The dirt texture is mapped by world position, so it never stretches.
			_add_quad(surface, in_a, out_a, out_b, in_b,
				_world_uv(in_a), _world_uv(out_a), _world_uv(out_b), _world_uv(in_b))
	surface.generate_tangents()
	return surface.commit()


func _world_uv(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / shoulder_tile_size


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2) -> void:
	_add_triangle(surface, a, b, c, uv_a, uv_b, uv_c)
	_add_triangle(surface, a, c, d, uv_a, uv_c, uv_d)


## Godot draws the clockwise side of a triangle. For a surface facing up,
## the cross product therefore has to point down; flip the triangle if it does not.
func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	if (b - a).cross(c - a).y > 0.0:
		_add_vertex(surface, a, uv_a)
		_add_vertex(surface, c, uv_c)
		_add_vertex(surface, b, uv_b)
	else:
		_add_vertex(surface, a, uv_a)
		_add_vertex(surface, b, uv_b)
		_add_vertex(surface, c, uv_c)


func _add_vertex(surface: SurfaceTool, point: Vector3, uv: Vector2) -> void:
	surface.set_normal(Vector3.UP)
	surface.set_uv(uv)
	surface.add_vertex(point)


func _asphalt_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = _pbr_material(
		"Road007_2K-JPG_Color.jpg", "Road007_2K-JPG_NormalGL.jpg", "Road007_2K-JPG_Roughness.jpg",
		Color(0.2, 0.2, 0.2))
	return material


func _shoulder_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = _pbr_material(
		"Ground037_2K-JPG_Color.jpg", "Ground037_2K-JPG_NormalGL.jpg", "Ground037_2K-JPG_Roughness.jpg",
		shoulder_tint)
	material.albedo_color = shoulder_tint
	return material


## Standard PBR material from three texture files. If a file is missing the road
## still shows up (plain colour) instead of the game failing.
func _pbr_material(color_file: String, normal_file: String, rough_file: String,
		fallback: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.albedo_color = Color.WHITE

	var color_texture: Texture2D = _load_texture(color_file)
	if color_texture != null:
		material.albedo_texture = color_texture
	else:
		material.albedo_color = fallback

	var normal_texture: Texture2D = _load_texture(normal_file)
	if normal_texture != null:
		material.normal_enabled = true
		material.normal_texture = normal_texture

	var rough_texture: Texture2D = _load_texture(rough_file)
	if rough_texture != null:
		material.roughness_texture = rough_texture
		material.roughness = 1.0
	else:
		material.roughness = 0.9
	return material


func _load_texture(file_name: String) -> Texture2D:
	var path: String = TEXTURE_DIR + file_name
	if not ResourceLoader.exists(path):
		push_warning("RoadBuilder: texture not found: %s" % path)
		return null
	return load(path) as Texture2D
