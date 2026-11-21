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
# Contrato de escala (PROJECT_RULES.md, secao 2): arvores de 6 a 18 m. Altere aqui para ajustar.
const TREE_HEIGHT_MIN_M := 9.0
const TREE_HEIGHT_MAX_M := 15.0
const TRUNK_RADIUS_M := 0.35 # raio da colisao do tronco, em metros reais
const TRUNK_COLLISION_HEIGHT_M := 4.0
const SNAP_BASE_TO_GROUND := true # apoia a base real do modelo no chao (evita flutuar ou afundar)

# Caixa do modelo no espaco do proprio nó da arvore, sem escala, rotacao ou posicao.
static func _local_bounds(tree: Node3D) -> AABB:
	var inverse := tree.global_transform.affine_inverse()
	var result := AABB()
	var found := false
	var stack: Array[Node] = [tree]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null:
				continue
			var box: AABB = (inverse * mesh_node.global_transform) * mesh_node.get_aabb()
			if found:
				result = result.merge(box)
			else:
				result = box
				found = true
	return result

static func build(game: Node, terrain: Node) -> void:
	if not USE_TREES:
		return
	for model_name in TREE_NAMES:
		if not ResourceLoader.exists("res://assets/nature/" + model_name + ".gltf"):
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = FIXED_SEED
	# Gerador separado para as alturas: nao muda as posicoes ja conhecidas das arvores.
	var height_rng := RandomNumberGenerator.new()
	height_rng.seed = FIXED_SEED + 1
	var min_final := 1000.0
	var max_final := 0.0
	var min_native := 1000.0
	var max_native := 0.0
	var unmeasured := 0
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
		# Escala: mede a altura real do modelo e ajusta para uma altura-alvo em metros.
		var bounds := _local_bounds(tree)
		var native_height := bounds.size.y
		var tree_scale := tree.scale.x
		var target_height := height_rng.randf_range(TREE_HEIGHT_MIN_M, TREE_HEIGHT_MAX_M)
		if native_height > 0.01:
			tree_scale = target_height / native_height
			tree.scale = Vector3.ONE * tree_scale
			if SNAP_BASE_TO_GROUND:
				tree.position.y = y - bounds.position.y * tree_scale
			min_native = minf(min_native, native_height)
			max_native = maxf(max_native, native_height)
			min_final = minf(min_final, target_height)
			max_final = maxf(max_final, target_height)
			tree.set_meta("height_m", target_height)
		else:
			# Nao foi possivel medir: marca com 0 para o simulador acusar a falha.
			unmeasured += 1
			tree.set_meta("height_m", 0.0)
		tree.add_to_group("trees")
		var trunk_body := StaticBody3D.new()
		trunk_body.name = "TreeTrunkCollision"
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		# A colisao fica no espaco do no (escalado); divide pela escala para ter metros reais.
		cylinder.radius = TRUNK_RADIUS_M / tree_scale
		cylinder.height = TRUNK_COLLISION_HEIGHT_M / tree_scale
		collision.shape = cylinder
		collision.position.y = TRUNK_COLLISION_HEIGHT_M * 0.5 / tree_scale
		trunk_body.add_child(collision)
		tree.add_child(trunk_body)
		positions.append(p)
		placed += 1
	print("[TREES] colocadas: ", placed, " | altura nativa do modelo: ", snapped(min_native, 0.01), " a ", snapped(max_native, 0.01), " | altura final (m): ", snapped(min_final, 0.1), " a ", snapped(max_final, 0.1), " | sem medida: ", unmeasured)
