class_name SceneryBuilder
extends Node3D
## Fills the world next to the road: trees, ferns, rocks, logs, stumps, road posts and
## guard rails. Everything is created in code at start-up, from the road's centre line.
##
## Performance:
##  - Trees are 3 crossed "cards" (a picture of the real tree), ferns / rocks / logs are real
##    low-poly meshes. Each kind is drawn with MultiMesh (one draw call per 160 m chunk).
##  - Every chunk is hidden beyond a view distance, so far away parts cost nothing.
##  - Placement uses a fixed random seed: the world looks the same every time you play.

const PROP_DIR: String = "res://assets/props/"
const FERN_PATH: String = "res://assets/models/fern_02/fern_02_2k.gltf"
const TREE_SHADER: Shader = preload("res://shaders/tree_card.gdshader")
## Size of the tree picture in metres (set by the tool that rendered the cards).
const TREE_HEIGHT: float = 4.577
const TREE_HALF_WIDTH: float = 2.835

@export_group("General")
@export var random_seed: int = 20261011
## The world is split into square chunks of this size (metres) for distance culling.
@export var chunk_size: float = 160.0
## Distance between the road points that scenery is placed along.
@export var sample_spacing: float = 4.0
## Where the road and its shoulder end, measured from the centre line.
@export var edge_offset: float = 5.95

@export_group("Trees")
@export var trees_enabled: bool = true
@export var trees_per_slot: int = 2
@export var tree_near_offset: float = 3.0
@export var tree_far_offset: float = 62.0
@export var tree_min_gap: float = 3.5
@export var tree_scale_min: float = 1.4
@export var tree_scale_max: float = 2.6
@export var tree_view_distance: float = 480.0
## Trees closer to the road than this get a solid trunk the car can crash into.
@export var tree_collision_range: float = 14.0

@export_group("Ferns")
@export var ferns_enabled: bool = true
@export var ferns_per_slot: int = 3
@export var fern_near_offset: float = 0.8
@export var fern_far_offset: float = 14.0
@export var fern_min_gap: float = 1.3
@export var fern_scale_min: float = 0.8
@export var fern_scale_max: float = 1.5
@export var fern_view_distance: float = 170.0

@export_group("Rocks, logs, stumps")
@export var rocks_enabled: bool = true
## Chance of a rock per road point and side (before the forest-patch noise).
@export var rock_chance: float = 0.16
@export var rock_near_offset: float = 1.5
@export var rock_far_offset: float = 28.0
@export var rock_scale_min: float = 0.5
@export var rock_scale_max: float = 1.5
@export var rock_view_distance: float = 300.0
## Chance of a fallen log or a stump per road point and side.
@export var log_chance: float = 0.014
@export var rock_collision_range: float = 14.0

@export_group("Road furniture")
@export var posts_enabled: bool = true
## A white post with a red reflector every this many road points (5 x 4 m = 20 m).
@export var post_every_points: int = 5
@export var post_view_distance: float = 220.0
@export var guardrails_enabled: bool = true
## Guard rails stand on the outside of every curve tighter than this radius (metres).
@export var guardrail_max_radius: float = 250.0
@export var guardrail_min_points: int = 8

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _noise: FastNoiseLite
var _line: PackedVector3Array = PackedVector3Array()
var _tangents: Array[Vector3] = []
var _sides: Array[Vector3] = []
## For every road point: +1 / -1 = the outside of a tight curve is on that side, 0 = straight.
var _outer: Array[float] = []
## chunk (Vector2i) -> list of {position, radius, height}
var _colliders: Dictionary = {}


func _ready() -> void:
	_rng.seed = random_seed
	_noise = FastNoiseLite.new()
	_noise.seed = random_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012

	_prepare_road()
	if _line.size() < 8:
		push_error("SceneryBuilder: the road layout has too few points.")
		return

	if trees_enabled:
		_build_trees()
	if ferns_enabled:
		_build_ferns()
	if rocks_enabled:
		_build_rocks()
	if posts_enabled:
		_build_posts()
	if guardrails_enabled:
		_build_guardrails()
	_build_colliders()


# ---------------------------------------------------------------- road helpers

func _prepare_road() -> void:
	_line = RoadLayout.build_centerline(sample_spacing)
	var count: int = _line.size()
	for i: int in count:
		var tangent: Vector3 = (_line[(i + 1) % count] - _line[(i - 1 + count) % count]).normalized()
		_tangents.append(tangent)
		# The side vector points to the car's LEFT (+X when driving +Z), like in RoadBuilder.
		_sides.append(Vector3.UP.cross(tangent).normalized())
	for i: int in count:
		var before: Vector3 = _tangents[(i - 1 + count) % count]
		var after: Vector3 = _tangents[(i + 1) % count]
		var turn: float = before.angle_to(after)
		var outer: float = 0.0
		if turn > 0.0001 and 2.0 * sample_spacing / turn < guardrail_max_radius:
			# The road bends towards the side the tangent moves to; the outside is the other one.
			outer = -signf((after - before).dot(_sides[i]))
		_outer.append(outer)


func _point_beside(index: int, direction: float, offset: float, along: float) -> Vector3:
	return _line[index] + _sides[index] * direction * offset + _tangents[index] * along


## 0 (open clearing) .. 1 (dense forest): smooth patches along the road.
func _density(point: Vector3) -> float:
	return (_noise.get_noise_2d(point.x, point.z) + 1.0) * 0.5


## Returns false if another object of this kind already stands within `gap` metres.
func _claim(taken: Dictionary, point: Vector3, gap: float) -> bool:
	var key: Vector2i = Vector2i(floori(point.x / gap), floori(point.z / gap))
	if taken.has(key):
		return false
	taken[key] = true
	return true


func _make_transform(point: Vector3, yaw: float, scale_value: Vector3, base_offset: Vector3) -> Transform3D:
	var basis_value: Basis = Basis(Vector3.UP, yaw).scaled(scale_value)
	return Transform3D(basis_value, point) * Transform3D(Basis.IDENTITY, base_offset)


## Moves the mesh so its middle is on the point and its lowest part touches the ground.
func _base_offset(mesh: Mesh) -> Vector3:
	var box: AABB = mesh.get_aabb()
	return Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5))


# ---------------------------------------------------------------- batching

## batches: Vector3i(chunk_x, chunk_z, variant) -> Array of [Transform3D, Color]
func _add_instance(batches: Dictionary, point: Vector3, variant: int, transform_value: Transform3D, color: Color) -> void:
	var key: Vector3i = Vector3i(floori(point.x / chunk_size), floori(point.z / chunk_size), variant)
	if not batches.has(key):
		batches[key] = []
	var list: Array = batches[key]
	list.append([transform_value, color])


func _emit(batches: Dictionary, meshes: Array, view_distance: float, casts_shadow: bool,
		use_colors: bool, group_name: String) -> void:
	var group: Node3D = Node3D.new()
	group.name = group_name
	add_child(group)
	for key: Vector3i in batches:
		var items: Array = batches[key]
		# Each chunk node sits in the middle of its chunk (so distance culling measures the
		# right place); the instances are stored relative to it.
		var origin: Vector3 = Vector3((float(key.x) + 0.5) * chunk_size, 0.0, (float(key.y) + 0.5) * chunk_size)
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = use_colors
		multimesh.mesh = meshes[key.z]
		multimesh.instance_count = items.size()
		for i: int in items.size():
			var transform_value: Transform3D = items[i][0]
			transform_value.origin -= origin
			multimesh.set_instance_transform(i, transform_value)
			if use_colors:
				multimesh.set_instance_color(i, items[i][1])
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.multimesh = multimesh
		node.position = origin
		node.visibility_range_end = view_distance
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(node)


func _queue_collider(point: Vector3, radius: float, height: float) -> void:
	var key: Vector2i = Vector2i(floori(point.x / chunk_size), floori(point.z / chunk_size))
	if not _colliders.has(key):
		_colliders[key] = []
	var list: Array = _colliders[key]
	list.append({"position": point, "radius": radius, "height": height})


## One StaticBody3D per chunk, with a simple cylinder for every solid object.
func _build_colliders() -> void:
	var shapes: Dictionary = {}
	for key: Vector2i in _colliders:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "Colliders_%d_%d" % [key.x, key.y]
		add_child(body)
		for item: Dictionary in _colliders[key]:
			var radius: float = maxf(snappedf(float(item["radius"]), 0.05), 0.05)
			var height: float = maxf(snappedf(float(item["height"]), 0.1), 0.1)
			var shape_key: Vector2 = Vector2(radius, height)
			if not shapes.has(shape_key):
				var cylinder: CylinderShape3D = CylinderShape3D.new()
				cylinder.radius = radius
				cylinder.height = height
				shapes[shape_key] = cylinder
			var collision: CollisionShape3D = CollisionShape3D.new()
			collision.shape = shapes[shape_key]
			collision.position = (item["position"] as Vector3) + Vector3(0.0, height * 0.5, 0.0)
			body.add_child(collision)


# ---------------------------------------------------------------- trees

func _build_trees() -> void:
	var meshes: Array = []
	for variant: String in ["a", "b"]:
		var mesh: ArrayMesh = _make_tree_mesh(variant)
		if mesh != null:
			meshes.append(mesh)
	if meshes.is_empty():
		return

	var batches: Dictionary = {}
	var taken: Dictionary = {}
	var count: int = _line.size()
	for i: int in count:
		for direction: float in [1.0, -1.0]:
			for attempt: int in trees_per_slot:
				# More trees close to the road, fewer further away.
				var offset: float = edge_offset + tree_near_offset \
					+ pow(_rng.randf(), 1.6) * (tree_far_offset - tree_near_offset)
				var along: float = _rng.randf_range(-sample_spacing * 0.5, sample_spacing * 0.5)
				var point: Vector3 = _point_beside(i, direction, offset, along)
				var chance: float = lerpf(0.3, 1.0, _density(point)) \
					* (1.0 - 0.5 * smoothstep(20.0, tree_far_offset, offset - edge_offset))
				if _rng.randf() > chance:
					continue
				if not _claim(taken, point, tree_min_gap):
					continue
				var scale_value: float = _rng.randf_range(tree_scale_min, tree_scale_max)
				var shade: float = _rng.randf_range(0.8, 1.15)
				var color: Color = Color(shade * _rng.randf_range(0.95, 1.05), shade, shade * _rng.randf_range(0.9, 1.0))
				var transform_value: Transform3D = _make_transform(
					point, _rng.randf() * TAU, Vector3.ONE * scale_value, Vector3.ZERO)
				_add_instance(batches, point, _rng.randi() % meshes.size(), transform_value, color)
				if offset - edge_offset < tree_collision_range:
					_queue_collider(point, 0.18 * scale_value + 0.1, 3.0 * scale_value)
	_emit(batches, meshes, tree_view_distance, false, true, "Trees")


## Three crossed quads (60 degrees apart); each one carries a picture of the tree seen from that side.
func _make_tree_mesh(variant: String) -> ArrayMesh:
	var yaw_sets: Dictionary = {"a": [0.0, 60.0, 120.0], "b": [30.0, 90.0, 150.0]}
	var yaws: Array = yaw_sets[variant]
	var mesh: ArrayMesh = ArrayMesh.new()
	for k: int in 3:
		var path: String = PROP_DIR + "tree_card_%s_%d.png" % [variant, k]
		if not ResourceLoader.exists(path):
			push_warning("SceneryBuilder: tree picture not found: %s" % path)
			return null
		var angle: float = deg_to_rad(float(yaws[k]))
		var right: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * TREE_HALF_WIDTH
		var up: Vector3 = Vector3.UP * TREE_HEIGHT

		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var corners: Array[Vector3] = [-right, right, right + up, -right + up]
		var uvs: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(uvs[index])
			surface.add_vertex(corners[index])
		surface.commit(mesh)

		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = TREE_SHADER
		material.set_shader_parameter("albedo_tex", load(path))
		mesh.surface_set_material(k, material)
	return mesh


# ---------------------------------------------------------------- ferns

func _build_ferns() -> void:
	var meshes: Array = _load_scene_meshes(FERN_PATH)
	if meshes.is_empty():
		return
	var offsets: Array[Vector3] = []
	var weights: Array[float] = []
	for mesh: Mesh in meshes:
		offsets.append(_base_offset(mesh))
		# Light variants are used more often than heavy ones.
		weights.append(1.0 / pow(maxf(float(mesh.get_faces().size() / 3), 100.0), 0.7))

	var batches: Dictionary = {}
	var taken: Dictionary = {}
	var count: int = _line.size()
	for i: int in count:
		for direction: float in [1.0, -1.0]:
			for attempt: int in ferns_per_slot:
				var offset: float = edge_offset + fern_near_offset \
					+ pow(_rng.randf(), 1.3) * (fern_far_offset - fern_near_offset)
				var point: Vector3 = _point_beside(i, direction, offset,
					_rng.randf_range(-sample_spacing * 0.5, sample_spacing * 0.5))
				# Ferns grow in patches.
				if _rng.randf() > lerpf(0.1, 0.9, _density(point + Vector3(300.0, 0.0, 300.0))):
					continue
				if not _claim(taken, point, fern_min_gap):
					continue
				var variant: int = _pick_weighted(weights)
				var scale_value: float = _rng.randf_range(fern_scale_min, fern_scale_max)
				var shade: float = _rng.randf_range(0.85, 1.1)
				var transform_value: Transform3D = _make_transform(
					point, _rng.randf() * TAU, Vector3.ONE * scale_value, offsets[variant])
				_add_instance(batches, point, variant, transform_value, Color(shade, shade, shade))
	_emit(batches, meshes, fern_view_distance, false, true, "Ferns")


func _pick_weighted(weights: Array[float]) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += weight
	var pick: float = _rng.randf() * total
	for i: int in weights.size():
		pick -= weights[i]
		if pick <= 0.0:
			return i
	return weights.size() - 1


## Loads a model file and returns the meshes inside it (every variant of a set is one mesh).
func _load_scene_meshes(path: String) -> Array:
	var result: Array = []
	if not ResourceLoader.exists(path):
		push_warning("SceneryBuilder: model not found: %s" % path)
		return result
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return result
	var root: Node = scene.instantiate()
	_collect_meshes(root, result)
	root.free()
	return result


func _collect_meshes(node: Node, result: Array) -> void:
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		result.append(mesh_instance.mesh)
	for child: Node in node.get_children():
		_collect_meshes(child, result)


# ---------------------------------------------------------------- rocks, logs, stumps

func _build_rocks() -> void:
	var rocks: Array = _load_scene_meshes(PROP_DIR + "rocks_moss.glb")
	var logs: Array = _load_scene_meshes(PROP_DIR + "log_dead.glb")
	logs.append_array(_load_scene_meshes(PROP_DIR + "stump.glb"))

	var rock_batches: Dictionary = {}
	var log_batches: Dictionary = {}
	var taken: Dictionary = {}
	var count: int = _line.size()
	for i: int in count:
		for direction: float in [1.0, -1.0]:
			var offset: float = edge_offset + rock_near_offset \
				+ pow(_rng.randf(), 1.4) * (rock_far_offset - rock_near_offset)
			var point: Vector3 = _point_beside(i, direction, offset,
				_rng.randf_range(-sample_spacing * 0.5, sample_spacing * 0.5))
			var density: float = _density(point + Vector3(-500.0, 0.0, 700.0))
			if not rocks.is_empty() and _rng.randf() < rock_chance * (0.4 + 1.2 * density):
				if _claim(taken, point, 4.0):
					var variant: int = _rng.randi() % rocks.size()
					var rock_mesh: Mesh = rocks[variant]
					var size: float = _rng.randf_range(rock_scale_min, rock_scale_max)
					var stretch: Vector3 = Vector3(size * _rng.randf_range(0.85, 1.2), size * _rng.randf_range(0.8, 1.1), size * _rng.randf_range(0.85, 1.2))
					# Sink the rock a little into the ground.
					var base: Vector3 = _base_offset(rock_mesh) + Vector3(0.0, -0.12 * rock_mesh.get_aabb().size.y, 0.0)
					var shade: float = _rng.randf_range(0.85, 1.1)
					_add_instance(rock_batches, point, variant,
						_make_transform(point, _rng.randf() * TAU, stretch, base), Color(shade, shade, shade))
					if offset - edge_offset < rock_collision_range:
						var box: AABB = rock_mesh.get_aabb()
						_queue_collider(point, 0.4 * maxf(box.size.x, box.size.z) * size, box.size.y * size * 0.8)
			elif not logs.is_empty() and _rng.randf() < log_chance:
				if _claim(taken, point, 4.0):
					var log_variant: int = _rng.randi() % logs.size()
					var log_mesh: Mesh = logs[log_variant]
					var log_scale: float = _rng.randf_range(0.9, 1.3)
					var shade_log: float = _rng.randf_range(0.85, 1.05)
					_add_instance(log_batches, point, log_variant,
						_make_transform(point, _rng.randf() * TAU, Vector3.ONE * log_scale, _base_offset(log_mesh)),
						Color(shade_log, shade_log, shade_log))
	if not rocks.is_empty():
		_emit(rock_batches, rocks, rock_view_distance, true, true, "Rocks")
	if not logs.is_empty():
		_emit(log_batches, logs, rock_view_distance, true, true, "Logs")


# ---------------------------------------------------------------- posts and guard rails

func _build_posts() -> void:
	var mesh: ArrayMesh = _make_post_mesh()
	var batches: Dictionary = {}
	var count: int = _line.size()
	var i: int = 0
	while i < count:
		for direction: float in [1.0, -1.0]:
			# No posts where a guard rail already stands.
			if _outer[i] == direction:
				continue
			var point: Vector3 = _point_beside(i, direction, edge_offset - 0.45, 0.0)
			var yaw: float = atan2(_tangents[i].x, _tangents[i].z)
			_add_instance(batches, point, 0,
				Transform3D(Basis(Vector3.UP, yaw), point), Color.WHITE)
		i += maxi(post_every_points, 1)
	_emit(batches, [mesh], post_view_distance, false, false, "Posts")


func _make_post_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var body: SurfaceTool = SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(body, Vector3(0.0, 0.45, 0.0), Basis.IDENTITY, Vector3(0.1, 0.9, 0.1))
	body.commit(mesh)
	var cap: SurfaceTool = SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(cap, Vector3(0.0, 0.76, 0.0), Basis.IDENTITY, Vector3(0.108, 0.16, 0.108))
	cap.commit(mesh)

	var white: StandardMaterial3D = StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.9, 0.87)
	white.roughness = 0.7
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, white)
	var red: StandardMaterial3D = StandardMaterial3D.new()
	red.albedo_color = Color(0.8, 0.05, 0.05)
	red.roughness = 0.4
	red.emission_enabled = true
	red.emission = Color(0.8, 0.05, 0.05)
	red.emission_energy_multiplier = 0.5
	red.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, red)
	return mesh


func _build_guardrails() -> void:
	var runs: Array = _find_curve_runs()
	if runs.is_empty():
		return
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pieces: Array = []
	var count: int = _line.size()
	var offset: float = edge_offset + 0.5
	for run: Dictionary in runs:
		var direction: float = float(run["outer"])
		var first: int = int(run["first"])
		for k: int in int(run["length"]) - 1:
			var i: int = (first + k) % count
			var j: int = (i + 1) % count
			var a: Vector3 = _line[i] + _sides[i] * direction * offset
			var b: Vector3 = _line[j] + _sides[j] * direction * offset
			var segment: Vector3 = b - a
			var length: float = segment.length()
			if length < 0.01:
				continue
			var basis_value: Basis = Basis.looking_at(segment / length, Vector3.UP)
			# The rail beam and a post at the start of every segment.
			_add_box(surface, (a + b) * 0.5 + Vector3.UP * 0.72, basis_value, Vector3(0.1, 0.34, length + 0.03))
			_add_box(surface, a + _sides[i] * direction * 0.15 + Vector3.UP * 0.45, basis_value, Vector3(0.14, 0.9, 0.14))
			if k % 2 == 0:
				pieces.append([b + Vector3.UP * 0.5, basis_value, length * 2.0])

	var mesh: ArrayMesh = surface.commit()
	var metal: StandardMaterial3D = StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.64, 0.67)
	metal.metallic = 0.6
	metal.roughness = 0.5
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, metal)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Guardrails"
	instance.mesh = mesh
	add_child(instance)

	# Solid: the car cannot drive through the rail.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "GuardrailCollision"
	add_child(body)
	for piece: Array in pieces:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(0.3, 1.0, float(piece[2]))
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		collision.transform = Transform3D(piece[1], piece[0])
		body.add_child(collision)


## Groups neighbouring road points whose curve has its outside on the same side.
func _find_curve_runs() -> Array:
	var runs: Array = []
	var count: int = _line.size()
	var i: int = 0
	while i < count:
		var side_value: float = _outer[i]
		if side_value == 0.0:
			i += 1
			continue
		var start: int = i
		while i < count and _outer[i] == side_value:
			i += 1
		if i - start >= guardrail_min_points:
			runs.append({"first": start, "length": i - start, "outer": side_value})
	return runs


## Adds the six faces of a box (any orientation) to a SurfaceTool.
func _add_box(surface: SurfaceTool, center: Vector3, basis_value: Basis, size: Vector3) -> void:
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var half: Vector3 = size * 0.5
	for axis: int in 3:
		for face_sign: float in [-1.0, 1.0]:
			var normal_local: Vector3 = axes[axis] * face_sign
			var u_local: Vector3 = axes[(axis + 1) % 3]
			var v_local: Vector3 = axes[(axis + 2) % 3]
			var middle: Vector3 = normal_local * half[axis]
			var hu: float = half[(axis + 1) % 3]
			var hv: float = half[(axis + 2) % 3]
			var p0: Vector3 = center + basis_value * (middle - u_local * hu - v_local * hv)
			var p1: Vector3 = center + basis_value * (middle + u_local * hu - v_local * hv)
			var p2: Vector3 = center + basis_value * (middle + u_local * hu + v_local * hv)
			var p3: Vector3 = center + basis_value * (middle - u_local * hu + v_local * hv)
			var face_normal: Vector3 = (basis_value * normal_local).normalized()
			for corner: Vector3 in [p0, p1, p2, p0, p2, p3]:
				surface.set_normal(face_normal)
				surface.add_vertex(corner)
