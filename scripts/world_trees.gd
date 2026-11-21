extends RefCounted

const USE_TREES := true
const TREE_COUNT := 80
const TREE_NAMES := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "Pine_1", "Pine_2"]
const AREA_LIMIT := 115.0
const START_EXCLUSION := 40.0
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_EXCLUSION := 30.0
const MIN_TREE_DISTANCE := 6.0
const MIN_GROUND_HEIGHT := -0.3
const FIXED_SEED := 24681357

static func build(game: Node, terrain: Node) -> void:
	if not USE_TREES:
		return
	for model_name in TREE_NAMES:
		if not ResourceLoader.exists("res://assets/nature/" + model_name + ".gltf"):
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = FIXED_SEED
	var positions: Array[Vector2] = []
	var placed := 0
	var attempts := 0
	while placed < TREE_COUNT and attempts < TREE_COUNT * 100:
		attempts += 1
		var x := rng.randf_range(-AREA_LIMIT, AREA_LIMIT)
		var z := rng.randf_range(-AREA_LIMIT, AREA_LIMIT)
		var p := Vector2(x, z)
		if p.length() <= START_EXCLUSION:
			continue
		if p.distance_to(LAKE_CENTER) <= LAKE_EXCLUSION:
			continue
		var y: float = terrain.height_at(x, z)
		if y < MIN_GROUND_HEIGHT:
			continue
		var too_close := false
		for existing in positions:
			if p.distance_to(existing) < MIN_TREE_DISTANCE:
				too_close = true
				break
		if too_close:
			continue
		var before_count := game.get_child_count()
		game.call("_add_tree", Vector3(x, y, z), placed)
		if game.get_child_count() <= before_count:
			continue
		var tree := game.get_child(game.get_child_count() - 1) as Node3D
		if tree == null:
			continue
		var trunk_body := StaticBody3D.new()
		trunk_body.name = "TreeTrunkCollision"
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.4
		cylinder.height = 4.0
		collision.shape = cylinder
		collision.position.y = 2.0
		trunk_body.add_child(collision)
		tree.add_child(trunk_body)
		positions.append(p)
		placed += 1
