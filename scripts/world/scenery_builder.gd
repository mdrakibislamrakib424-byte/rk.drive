class_name SceneryBuilder
extends Node3D
## Fills the world next to the road and out to the horizon: trees (4 kinds), bushes, grass
## tufts and meadow flowers, ferns, rocks, logs, stumps, road posts and guard rails.
## Everything is created in code at start-up, from the road's centre line.
##
## How it stays fast on a phone:
##  - Trees are "cards" (a picture of the real tree on 3 crossed quads). Close trees use a big
##    picture, far trees use a small one (one draw call per chunk).
##  - Everything is drawn with MultiMesh and split into chunks that are hidden beyond a view
##    distance, so far away parts cost nothing.
##  - The QUALITY setting (pause menu) changes how much is created: LOW / MEDIUM / HIGH.
##  - A fixed random seed makes the world look the same every time.

const PROP_DIR: String = "res://assets/props/"
const FERN_PATH: String = "res://assets/models/fern_02/fern_02_2k.gltf"
const TREE_SHADER: Shader = preload("res://shaders/tree_card.gdshader")
const GRASS_SHADER: Shader = preload("res://shaders/grass_card.gdshader")

## Tree kinds: picture size (metres, set by the tool that rendered the pictures) and scale range.
const TREE_TYPES = [
	{"variant": "a", "height": 4.577, "half_width": 2.835, "scale_min": 1.5, "scale_max": 2.6, "weight": 3.0},
	{"variant": "b", "height": 4.577, "half_width": 2.835, "scale_min": 1.5, "scale_max": 2.6, "weight": 3.0},
	{"variant": "c", "height": 5.075, "half_width": 2.503, "scale_min": 1.4, "scale_max": 2.3, "weight": 3.0},
	{"variant": "d", "height": 8.953, "half_width": 8.814, "scale_min": 0.7, "scale_max": 1.1, "weight": 1.2},
]
const SHRUB_TYPE = {"variant": "e", "height": 2.640, "half_width": 1.934, "scale_min": 0.9, "scale_max": 1.9}
const GRASS_VARIANTS = ["green", "lush", "dry", "flowers_white", "flowers_mixed"]
const GRASS_HALF_WIDTH: float = 0.55
const GRASS_HEIGHT: float = 0.95

@export_group("General")
@export var random_seed: int = 20261011
## The world is split into square chunks of this size (metres) for distance culling.
@export var chunk_size: float = 160.0
## Distance between the road points that scenery is placed along.
@export var sample_spacing: float = 4.0
## Where the road and its shoulder end, measured from the centre line.
@export var edge_offset: float = 5.95

@export_group("Trees next to the road")
@export var trees_enabled: bool = true
@export var trees_per_slot: int = 2
@export var tree_near_offset: float = 3.0
@export var tree_far_offset: float = 62.0
@export var tree_min_gap: float = 3.5
## Trees closer to the road than this get a solid trunk the car can crash into.
@export var tree_collision_range: float = 14.0
## Trees closer than this (metres from the road edge) throw shadows (HIGH quality only).
@export var tree_shadow_range: float = 30.0

@export_group("Forest to the horizon")
@export var far_forest_enabled: bool = true
## Distance between far trees (smaller = denser forest, slower start).
@export var far_spacing: float = 18.0
## Far trees start this far from the road centre (the close trees end before it).
@export var far_clear_distance: float = 72.0
@export var far_chunk_size: float = 320.0

@export_group("Bushes")
@export var shrubs_enabled: bool = true
@export var shrub_near_offset: float = 1.5
@export var shrub_far_offset: float = 24.0
@export var shrub_min_gap: float = 2.6

@export_group("Grass and flowers")
@export var grass_enabled: bool = true
## Tufts tried per road point and side: close to the road (0-6 m) and further out (6-30 m).
@export var grass_near_attempts: int = 30
@export var grass_far_attempts: int = 40
@export var grass_far_offset: float = 30.0
@export var grass_min_gap: float = 0.6
@export var grass_scale_min: float = 0.8
@export var grass_scale_max: float = 1.9
@export var grass_chunk_size: float = 80.0

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
var _species_noise: FastNoiseLite
var _line: PackedVector3Array = PackedVector3Array()
var _tangents: Array[Vector3] = []
var _sides: Array[Vector3] = []
## For every road point: +1 / -1 = the outside of a tight curve is on that side, 0 = straight.
var _outer: Array[float] = []
## chunk (Vector2i) -> list of {position, radius, height}
var _colliders: Dictionary = {}

var _near_meshes: Array = []
var _far_meshes: Array = []
var _type_weights: Array[float] = []
var _type_weight_sum: float = 1.0

# Set from the QUALITY setting (see _apply_quality).
var _far_radius: float = 1300.0
var _tree_view: float = 520.0
var _far_view: float = 1450.0
var _grass_scale: float = 1.0
var _grass_view: float = 95.0
var _tree_shadows: bool = true
var _fern_scale: float = 1.0


func _ready() -> void:
	_apply_quality()
	_rng.seed = random_seed
	_noise = FastNoiseLite.new()
	_noise.seed = random_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012
	# A slower noise decides which tree kind grows where (patches of oak, olive, fir).
	_species_noise = FastNoiseLite.new()
	_species_noise.seed = random_seed + 7
	_species_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_species_noise.frequency = 0.004
	for type: Dictionary in TREE_TYPES:
		_type_weights.append(float(type["weight"]))
		_type_weight_sum += float(type["weight"])
	_type_weight_sum -= 1.0

	_prepare_road()
	if _line.size() < 8:
		push_error("SceneryBuilder: the road layout has too few points.")
		return

	if trees_enabled:
		_build_trees()
		if far_forest_enabled and _far_radius > 0.0:
			_build_far_forest()
		if shrubs_enabled:
			_build_shrubs()
	if grass_enabled:
		_build_grass()
	if ferns_enabled:
		_build_ferns()
	if rocks_enabled:
		_build_rocks()
	if posts_enabled:
		_build_posts()
	if guardrails_enabled:
		_build_guardrails()
	_build_colliders()


## LOW / MEDIUM / HIGH (pause menu) decides how much of the world is created.
func _apply_quality() -> void:
	var quality: int = GameSettings.get_quality()
	_far_radius = [0.0, 700.0, 1300.0][quality]
	_tree_view = [320.0, 420.0, 520.0][quality]
	_far_view = [0.0, 800.0, 1450.0][quality]
	_grass_scale = [0.0, 0.5, 1.0][quality]
	_grass_view = [0.0, 70.0, 95.0][quality]
	_tree_shadows = quality >= 2
	_fern_scale = [0.4, 0.7, 1.0][quality]


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
func _add_instance(batches: Dictionary, point: Vector3, variant: int, transform_value: Transform3D,
		color: Color, chunk: float = -1.0) -> void:
	var size_value: float = chunk_size if chunk <= 0.0 else chunk
	var key: Vector3i = Vector3i(floori(point.x / size_value), floori(point.z / size_value), variant)
	if not batches.has(key):
		batches[key] = []
	var list: Array = batches[key]
	list.append([transform_value, color])


func _emit(batches: Dictionary, meshes: Array, view_distance: float, casts_shadow: bool,
		use_colors: bool, group_name: String, chunk: float = -1.0) -> void:
	if batches.is_empty():
		return
	var size_value: float = chunk_size if chunk <= 0.0 else chunk
	var group: Node3D = Node3D.new()
	group.name = group_name
	add_child(group)
	for key: Vector3i in batches:
		var items: Array = batches[key]
		# Each chunk node sits in the middle of its chunk (so distance culling measures the
		# right place); the instances are stored relative to it.
		var origin: Vector3 = Vector3((float(key.x) + 0.5) * size_value, 0.0, (float(key.y) + 0.5) * size_value)
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


# ---------------------------------------------------------------- tree cards

func _load_tree_meshes() -> void:
	for type: Dictionary in TREE_TYPES:
		var near: ArrayMesh = _make_tree_mesh(type, false)
		if near == null:
			_near_meshes.clear()
			_far_meshes.clear()
			return
		var far: ArrayMesh = _make_tree_mesh(type, true)
		_near_meshes.append(near)
		_far_meshes.append(far if far != null else near)


## Three crossed quads (60 degrees apart); each carries a picture of the tree seen from that side.
## near: three big pictures. far: one small picture ("atlas") that holds the three views.
func _make_tree_mesh(type: Dictionary, far: bool) -> ArrayMesh:
	var variant: String = String(type["variant"])
	var half_width: float = float(type["half_width"])
	var height: float = float(type["height"])
	var yaws: Array = [30.0, 90.0, 150.0] if variant == "b" else [0.0, 60.0, 120.0]
	var mesh: ArrayMesh = ArrayMesh.new()
	if far:
		var path: String = PROP_DIR + "tree_atlas_%s.png" % variant
		if not ResourceLoader.exists(path):
			return null
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k: int in 3:
			_add_card(surface, float(yaws[k]), half_width, height,
				Vector2(float(k % 2) * 0.5, float(k / 2) * 0.5), Vector2(0.5, 0.5))
		surface.commit(mesh)
		mesh.surface_set_material(0, _card_material(load(path), height, 0.12))
		return mesh
	for k: int in 3:
		var path_near: String = PROP_DIR + "tree_card_%s_%d.png" % [variant, k]
		if not ResourceLoader.exists(path_near):
			push_warning("SceneryBuilder: tree picture not found: %s" % path_near)
			return null
		var surface_near: SurfaceTool = SurfaceTool.new()
		surface_near.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_card(surface_near, float(yaws[k]), half_width, height, Vector2.ZERO, Vector2.ONE)
		surface_near.commit(mesh)
		mesh.surface_set_material(k, _card_material(load(path_near), height, 0.12))
	return mesh


func _card_material(texture: Resource, height: float, sway: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TREE_SHADER
	material.set_shader_parameter("albedo_tex", texture)
	material.set_shader_parameter("card_height", height)
	material.set_shader_parameter("sway_amount", sway)
	return material


## One flat quad standing on the ground, turned by yaw_deg. uv_min / uv_size pick the part of
## the picture to show.
func _add_card(surface: SurfaceTool, yaw_deg: float, half_width: float, height: float,
		uv_min: Vector2, uv_size: Vector2) -> void:
	var angle: float = deg_to_rad(yaw_deg)
	var right: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * half_width
	var up: Vector3 = Vector3.UP * height
	var corners: Array[Vector3] = [-right, right, right + up, -right + up]
	var uvs: Array[Vector2] = [
		Vector2(uv_min.x, uv_min.y + uv_size.y), Vector2(uv_min.x + uv_size.x, uv_min.y + uv_size.y),
		Vector2(uv_min.x + uv_size.x, uv_min.y), Vector2(uv_min.x, uv_min.y)]
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(Vector3.UP)
		surface.set_uv(uvs[index])
		surface.add_vertex(corners[index])


## Picks a tree kind: mostly by patches (so oaks, olives and firs grow in groups), a little random.
func _pick_type(point: Vector3) -> int:
	if _rng.randf() < 0.3:
		return _pick_weighted(_type_weights)
	var n: float = (_species_noise.get_noise_2d(point.x, point.z) + 1.0) * 0.5
	var accumulated: float = 0.0
	for i: int in _type_weights.size():
		accumulated += _type_weights[i] / _type_weight_sum
		if n <= accumulated:
			return i
	return _type_weights.size() - 1


func _tree_color() -> Color:
	var shade: float = _rng.randf_range(0.8, 1.15)
	return Color(shade * _rng.randf_range(0.95, 1.05), shade, shade * _rng.randf_range(0.9, 1.0))


## Close forest: along both sides of the road, denser near the road.
func _build_trees() -> void:
	_load_tree_meshes()
	if _near_meshes.is_empty():
		return
	var plain: Dictionary = {}
	var shadowed: Dictionary = {}
	var taken: Dictionary = {}
	var count: int = _line.size()
	for i: int in count:
		for direction: float in [1.0, -1.0]:
			for attempt: int in trees_per_slot:
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
				var type_index: int = _pick_type(point)
				var type: Dictionary = TREE_TYPES[type_index]
				var scale_value: float = _rng.randf_range(float(type["scale_min"]), float(type["scale_max"]))
				var transform_value: Transform3D = _make_transform(
					point, _rng.randf() * TAU, Vector3.ONE * scale_value, Vector3.ZERO)
				var batch: Dictionary = shadowed if (_tree_shadows and offset - edge_offset < tree_shadow_range) else plain
				_add_instance(batch, point, type_index, transform_value, _tree_color())
				if offset - edge_offset < tree_collision_range:
					_queue_collider(point, 0.18 * scale_value + 0.1, 3.0 * scale_value)
	_emit(plain, _near_meshes, _tree_view, false, true, "Trees")
	_emit(shadowed, _near_meshes, _tree_view, true, true, "TreesShadow")


## Far forest: trees all over the land around the road, as far as the eye can see.
## A coarse "distance to the road" map tells where far trees may grow.
func _build_far_forest() -> void:
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for point: Vector3 in _line:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)

	var cell: float = 60.0
	var margin: float = _far_radius
	var origin_x: float = min_x - margin - cell
	var origin_z: float = min_z - margin - cell
	var width: int = int(ceil((max_x - min_x + 2.0 * margin + 2.0 * cell) / cell)) + 1
	var depth: int = int(ceil((max_z - min_z + 2.0 * margin + 2.0 * cell) / cell)) + 1
	var field: PackedFloat32Array = PackedFloat32Array()
	field.resize(width * depth)
	field.fill(1.0e9)
	for point: Vector3 in _line:
		field[int((point.z - origin_z) / cell) * width + int((point.x - origin_x) / cell)] = 0.0
	_chamfer(field, width, depth, cell)

	# Road points grouped in 40 m cells, for the exact "too close to the road" test.
	var road_cells: Dictionary = {}
	for point: Vector3 in _line:
		var key: Vector2i = Vector2i(floori(point.x / 40.0), floori(point.z / 40.0))
		if not road_cells.has(key):
			road_cells[key] = []
		var list: Array = road_cells[key]
		list.append(point)

	var batches: Dictionary = {}
	var step: float = far_spacing
	for grid_z: int in range(floori((min_z - margin) / step), ceili((max_z + margin) / step) + 1):
		for grid_x: int in range(floori((min_x - margin) / step), ceili((max_x + margin) / step) + 1):
			var x: float = (float(grid_x) + _rng.randf()) * step
			var z: float = (float(grid_z) + _rng.randf()) * step
			var cx: int = int((x - origin_x) / cell)
			var cz: int = int((z - origin_z) / cell)
			if cx < 0 or cz < 0 or cx >= width or cz >= depth:
				continue
			var coarse: float = field[cz * width + cx]
			if coarse > margin or coarse < 25.0:
				continue
			var point: Vector3 = Vector3(x, 0.0, z)
			if coarse < far_clear_distance + 80.0 and _too_close_to_road(road_cells, point, far_clear_distance):
				continue
			var chance: float = lerpf(0.2, 1.0, _density(point)) \
				* (1.0 - 0.45 * smoothstep(far_clear_distance, margin, coarse))
			if _rng.randf() > chance:
				continue
			var type_index: int = _pick_type(point)
			var type: Dictionary = TREE_TYPES[type_index]
			var scale_value: float = _rng.randf_range(float(type["scale_min"]), float(type["scale_max"]))
			_add_instance(batches, point, type_index,
				_make_transform(point, _rng.randf() * TAU, Vector3.ONE * scale_value, Vector3.ZERO),
				_tree_color(), far_chunk_size)
	_emit(batches, _far_meshes, _far_view, false, true, "FarForest", far_chunk_size)


## Two-pass chamfer distance (metres): how far every cell is from the nearest road cell.
func _chamfer(field: PackedFloat32Array, width: int, depth: int, cell: float) -> void:
	var diagonal: float = cell * 1.4142
	for z: int in depth:
		for x: int in width:
			var best: float = field[z * width + x]
			if x > 0:
				best = minf(best, field[z * width + x - 1] + cell)
			if z > 0:
				best = minf(best, field[(z - 1) * width + x] + cell)
				if x > 0:
					best = minf(best, field[(z - 1) * width + x - 1] + diagonal)
				if x < width - 1:
					best = minf(best, field[(z - 1) * width + x + 1] + diagonal)
			field[z * width + x] = best
	for z: int in range(depth - 1, -1, -1):
		for x: int in range(width - 1, -1, -1):
			var best_back: float = field[z * width + x]
			if x < width - 1:
				best_back = minf(best_back, field[z * width + x + 1] + cell)
			if z < depth - 1:
				best_back = minf(best_back, field[(z + 1) * width + x] + cell)
				if x < width - 1:
					best_back = minf(best_back, field[(z + 1) * width + x + 1] + diagonal)
				if x > 0:
					best_back = minf(best_back, field[(z + 1) * width + x - 1] + diagonal)
			field[z * width + x] = best_back


func _too_close_to_road(road_cells: Dictionary, point: Vector3, distance: float) -> bool:
	var reach: int = ceili(distance / 40.0)
	var cx: int = floori(point.x / 40.0)
	var cz: int = floori(point.z / 40.0)
	var limit: float = distance * distance
	for dz: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var key: Vector2i = Vector2i(cx + dx, cz + dz)
			if road_cells.has(key):
				for road_point: Vector3 in road_cells[key]:
					var delta_x: float = road_point.x - point.x
					var delta_z: float = road_point.z - point.z
					if delta_x * delta_x + delta_z * delta_z < limit:
						return true
	return false


## Bushes next to the road (under the trees).
func _build_shrubs() -> void:
	var mesh: ArrayMesh = _make_tree_mesh(SHRUB_TYPE, false)
	if mesh == null:
		return
	var batches: Dictionary = {}
	var taken: Dictionary = {}
	var count: int = _line.size()
	for i: int in count:
		for direction: float in [1.0, -1.0]:
			var offset: float = edge_offset + shrub_near_offset \
				+ pow(_rng.randf(), 1.3) * (shrub_far_offset - shrub_near_offset)
			var point: Vector3 = _point_beside(i, direction, offset,
				_rng.randf_range(-sample_spacing * 0.5, sample_spacing * 0.5))
			if _rng.randf() > lerpf(0.05, 0.6, _density(point + Vector3(-200.0, 0.0, 150.0))):
				continue
			if not _claim(taken, point, shrub_min_gap):
				continue
			var scale_value: float = _rng.randf_range(float(SHRUB_TYPE["scale_min"]), float(SHRUB_TYPE["scale_max"]))
			_add_instance(batches, point, 0,
				_make_transform(point, _rng.randf() * TAU, Vector3.ONE * scale_value, Vector3.ZERO), _tree_color())
	_emit(batches, [mesh], _tree_view * 0.6, false, true, "Bushes")


# ---------------------------------------------------------------- grass and flowers

## Thick grass along both sides of the road, with patches of meadow flowers.
func _build_grass() -> void:
	if _grass_scale <= 0.0:
		return
	var meshes: Array = []
	for variant: String in GRASS_VARIANTS:
		var path: String = PROP_DIR + "grass_%s.png" % variant
		if not ResourceLoader.exists(path):
			push_warning("SceneryBuilder: grass picture not found: %s" % path)
			return
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k: int in 3:
			_add_card(surface, 60.0 * float(k), GRASS_HALF_WIDTH, GRASS_HEIGHT, Vector2.ZERO, Vector2.ONE)
		var mesh: ArrayMesh = ArrayMesh.new()
		surface.commit(mesh)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = GRASS_SHADER
		material.set_shader_parameter("albedo_tex", load(path))
		material.set_shader_parameter("card_height", GRASS_HEIGHT)
		mesh.surface_set_material(0, material)
		meshes.append(mesh)

	var base_weights: Array[float] = [3.0, 3.0, 1.2]
	var batches: Dictionary = {}
	var taken: Dictionary = {}
	var near_attempts: int = roundi(float(grass_near_attempts) * _grass_scale)
	var far_attempts: int = roundi(float(grass_far_attempts) * _grass_scale)
	var count: int = _line.size()
	for i: int in count:
		for direction: float in [1.0, -1.0]:
			for attempt: int in near_attempts + far_attempts:
				var offset: float
				if attempt < near_attempts:
					offset = edge_offset + 0.15 + _rng.randf() * 6.0
				else:
					offset = edge_offset + 6.0 + pow(_rng.randf(), 1.4) * (grass_far_offset - 6.0)
				var point: Vector3 = _point_beside(i, direction, offset,
					_rng.randf_range(-sample_spacing * 0.5, sample_spacing * 0.5))
				if _rng.randf() > lerpf(0.45, 1.0, _density(point + Vector3(120.0, 0.0, -90.0))):
					continue
				if not _claim(taken, point, grass_min_gap):
					continue
				var variant_index: int
				var flowers: float = _species_noise.get_noise_2d(point.x * 2.0 + 500.0, point.z * 2.0)
				if flowers > 0.3 and _rng.randf() < 0.45:
					variant_index = 3 + _rng.randi() % 2
				elif _rng.randf() < 0.03:
					variant_index = 3 + _rng.randi() % 2
				else:
					variant_index = _pick_weighted(base_weights)
				var scale_value: float = _rng.randf_range(grass_scale_min, grass_scale_max)
				var shade: float = _rng.randf_range(0.8, 1.15)
				_add_instance(batches, point, variant_index,
					_make_transform(point, _rng.randf() * TAU, Vector3(scale_value, scale_value * _rng.randf_range(0.8, 1.25), scale_value), Vector3.ZERO),
					Color(shade, shade, shade * 0.95), grass_chunk_size)
	_emit(batches, meshes, _grass_view, false, true, "Grass", grass_chunk_size)


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
			for attempt: int in maxi(roundi(float(ferns_per_slot) * _fern_scale), 1):
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
