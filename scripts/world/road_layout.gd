class_name RoadLayout
extends RefCounted
## The road centre line: a smooth closed loop of about 3 km.
## It starts at the world origin and points along +Z (where the car spawns).
## Control points are (x, z) positions in metres. A Catmull-Rom spline runs
## through them, so the road has no sharp corners.

const CONTROL_POINTS = [
	Vector2(0, 0),
	Vector2(-1, 108),
	Vector2(-7, 219),
	Vector2(-27, 325),
	Vector2(-68, 425),
	Vector2(-138, 510),
	Vector2(-231, 565),
	Vector2(-338, 588),
	Vector2(-446, 574),
	Vector2(-538, 517),
	Vector2(-589, 423),
	Vector2(-598, 315),
	Vector2(-584, 206),
	Vector2(-561, 100),
	Vector2(-537, -8),
	Vector2(-521, -115),
	Vector2(-519, -224),
	Vector2(-537, -331),
	Vector2(-567, -437),
	Vector2(-517, -518),
	Vector2(-409, -531),
	Vector2(-298, -530),
	Vector2(-191, -520),
	Vector2(-84, -496),
	Vector2(3, -434),
	Vector2(15, -327),
	Vector2(6, -219),
	Vector2(1, -110),
]

## Points of the spline sampled per control point before resampling.
const DENSE_STEPS: int = 40


static func catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3
	)


## Returns the centre line as points that are `spacing` metres apart (y = 0).
## The line is a closed loop: the last point connects back to the first one.
static func build_centerline(spacing: float) -> PackedVector3Array:
	var count: int = CONTROL_POINTS.size()
	var dense: PackedVector2Array = PackedVector2Array()
	for i: int in count:
		var p0: Vector2 = CONTROL_POINTS[(i - 1 + count) % count]
		var p1: Vector2 = CONTROL_POINTS[i]
		var p2: Vector2 = CONTROL_POINTS[(i + 1) % count]
		var p3: Vector2 = CONTROL_POINTS[(i + 2) % count]
		for k: int in DENSE_STEPS:
			dense.append(catmull_rom(p0, p1, p2, p3, float(k) / float(DENSE_STEPS)))

	# Resample so every point is the same distance from the next one.
	var result: PackedVector3Array = PackedVector3Array()
	result.append(Vector3(dense[0].x, 0.0, dense[0].y))
	var travelled: float = 0.0
	var next_at: float = spacing
	for i: int in dense.size():
		var a: Vector2 = dense[i]
		var b: Vector2 = dense[(i + 1) % dense.size()]
		var segment: float = a.distance_to(b)
		if segment < 0.0001:
			continue
		while travelled + segment >= next_at:
			var point: Vector2 = a.lerp(b, (next_at - travelled) / segment)
			result.append(Vector3(point.x, 0.0, point.y))
			next_at += spacing
		travelled += segment

	# The last sample can land almost on top of the first one: drop it.
	if result.size() > 2 and result[0].distance_to(result[result.size() - 1]) < spacing * 0.5:
		result.remove_at(result.size() - 1)
	return result
