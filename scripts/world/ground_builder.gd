class_name GroundBuilder
extends StaticBody3D
## The ground of the world: a huge flat collision box (its top is at y = 0) and
## a good-looking grass / forest soil surface drawn on top of it.
## Everything is created in code at start-up.

const TEXTURE_DIR: String = "res://assets/textures/"
const TERRAIN_SHADER: Shader = preload("res://shaders/terrain.gdshader")

## Width and length of the ground in metres.
@export var size: float = 4000.0
## The picture sits a little below the collision surface, so the road
## (which is at y = 0) never flickers against the ground.
@export var visual_offset: float = -0.03
## 0 = very slippery, 1 = normal grip (used by the physics engine).
@export_range(0.0, 2.0) var friction: float = 1.0
## The ground moves along with the car, so it never ends (the picture is mapped by
## world position, so nothing visibly changes when it moves).
@export var follow_car: bool = true
## The ground jumps in steps of this many metres.
@export var snap_step: float = 200.0

var _car: Node3D


func _ready() -> void:
	var physics_material: PhysicsMaterial = PhysicsMaterial.new()
	physics_material.friction = friction
	physics_material_override = physics_material

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(size, 2.0, size)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	collision.position = Vector3(0.0, -1.0, 0.0)
	add_child(collision)

	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(size, size)
	var surface: MeshInstance3D = MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = plane
	surface.position = Vector3(0.0, visual_offset, 0.0)
	surface.material_override = _terrain_material()
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)


func _physics_process(_delta: float) -> void:
	if not follow_car:
		return
	if not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group("car") as Node3D
		if _car == null:
			return
	var snapped_x: float = snappedf(_car.global_position.x, snap_step)
	var snapped_z: float = snappedf(_car.global_position.z, snap_step)
	if not is_equal_approx(global_position.x, snapped_x) or not is_equal_approx(global_position.z, snapped_z):
		global_position = Vector3(snapped_x, 0.0, snapped_z)


func _terrain_material() -> Material:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	var textures: Dictionary = {
		"grass_color": "Grass001_2K-JPG_Color.jpg",
		"grass_normal": "Grass001_2K-JPG_NormalGL.jpg",
		"grass_rough": "Grass001_2K-JPG_Roughness.jpg",
		"dirt_color": "Ground037_2K-JPG_Color.jpg",
		"dirt_normal": "Ground037_2K-JPG_NormalGL.jpg",
		"dirt_rough": "Ground037_2K-JPG_Roughness.jpg",
	}
	var missing: bool = false
	for parameter: String in textures:
		var path: String = TEXTURE_DIR + String(textures[parameter])
		if ResourceLoader.exists(path):
			material.set_shader_parameter(parameter, load(path))
		else:
			push_warning("GroundBuilder: texture not found: %s" % path)
			missing = true

	if missing:
		# A plain green ground is better than a broken-looking one.
		var fallback: StandardMaterial3D = StandardMaterial3D.new()
		fallback.albedo_color = Color(0.2, 0.3, 0.12)
		fallback.roughness = 0.95
		return fallback
	return material
