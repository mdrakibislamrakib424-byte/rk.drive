class_name MountainRing
extends MeshInstance3D
## Distant mountains all around the world. A flat grid follows the car; the height of every
## point is computed in the shader from noise of its world position (see mountains.gdshader),
## so the mountains stay put and cost almost nothing on the CPU.

const SHADER: Shader = preload("res://shaders/mountains.gdshader")

## Half the size of the grid in metres (9000 = the mountains reach 9 km away).
@export var half_extent: float = 9000.0
## Number of grid cells along one side. cell size = 2 * half_extent / cells.
@export var cells: int = 120
@export var amplitude: float = 1300.0
## Distance from the car where the mountains start to rise.
@export var inner_radius: float = 1500.0
@export var blend_distance: float = 1400.0
@export var noise_scale: float = 2600.0

var _car: Node3D
var _material: ShaderMaterial
var _cell_size: float = 150.0


func _ready() -> void:
	_cell_size = 2.0 * half_extent / float(cells)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("amplitude", amplitude)
	_material.set_shader_parameter("inner_radius", inner_radius)
	_material.set_shader_parameter("blend_distance", blend_distance)
	_material.set_shader_parameter("noise_scale", noise_scale)
	_material.set_shader_parameter("cell_size", _cell_size)

	mesh = _build_grid()
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader raises the vertices, so the real bounds are taller than the flat grid.
	custom_aabb = AABB(Vector3(-half_extent, -50.0, -half_extent),
		Vector3(half_extent * 2.0, amplitude * 1.6, half_extent * 2.0))


func _process(_delta: float) -> void:
	if not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group("car") as Node3D
		if _car == null:
			return
	var car_position: Vector3 = _car.global_position
	# The grid jumps in whole cells, so its vertices always sit on the same world points
	# (no "swimming" of the mountain surface).
	global_position = Vector3(
		snappedf(car_position.x, _cell_size), 0.0, snappedf(car_position.z, _cell_size))
	_material.set_shader_parameter("center_xz", Vector2(car_position.x, car_position.z))


func _build_grid() -> ArrayMesh:
	var side: int = cells + 1
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.resize(side * side)
	for row: int in side:
		for column: int in side:
			vertices[row * side + column] = Vector3(
				-half_extent + float(column) * _cell_size, 0.0, -half_extent + float(row) * _cell_size)

	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(cells * cells * 6)
	var write: int = 0
	for row: int in cells:
		for column: int in cells:
			var a: int = row * side + column
			var b: int = a + 1
			var c: int = a + side + 1
			var d: int = a + side
			# Clockwise when seen from above (that is the front side in Godot).
			indices[write] = a
			indices[write + 1] = b
			indices[write + 2] = c
			indices[write + 3] = a
			indices[write + 4] = c
			indices[write + 5] = d
			write += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var grid: ArrayMesh = ArrayMesh.new()
	grid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return grid
