extends RefCounted

const USE_TREES := true
const TREE_COUNT := 80
const TREE_NAMES := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "Pine_1", "Pine_2"]
const TREE_RADIUS := 118.0
const START_EXCLUSION := 90.0
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_EXCLUSION := 30.0
const FIXED_SEED := 24681357

static func build(game: Node, terrain: Node) -> void:
	if not USE_TREES:
		return
	for name in TREE_NAMES:
		if not ResourceLoader.exists("res://assets/nature/" + name + ".gltf"):
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = FIXED_SEED
	var placed := 0
	var attempts := 0
	while placed < TREE_COUNT and attempts < TREE_COUNT * 30:
		attempts += 1
		var x := rng.randf_range(-TREE_RADIUS, TREE_RADIUS)
		var z := rng.randf_range(-TREE_RADIUS, TREE_RADIUS)
		var p := Vector2(x, z)
		if p.length() <= START_EXCLUSION or p.length() > TREE_RADIUS:
			continue
		if p.distance_to(LAKE_CENTER) <= LAKE_EXCLUSION:
			continue
		var y: float = terrain.height_at(x, z)
		game.call("_add_tree", Vector3(x, y, z), placed)
		placed += 1
