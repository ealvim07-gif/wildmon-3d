extends SceneTree

const SAMPLE_COORDS := [-55.0, -30.0, 0.0, 30.0, 55.0]
const HEIGHT_TOLERANCE := 0.18

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Não foi possível carregar scenes/main.tscn.")
		return

	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	await physics_frame

	var terrain := game.find_child("GroundSurface", true, false) as MeshInstance3D
	var terrain_body := game.find_child("TerrainCollision", true, false) as StaticBody3D
	var world_environment := _find_typed_node(game, "WorldEnvironment") as WorldEnvironment
	var player := _find_typed_node(game, "CharacterBody3D") as CharacterBody3D
	var camera := _find_typed_node(game, "Camera3D") as Camera3D

	if terrain == null or terrain.mesh == null:
		_fail("A malha visível do terreno não foi criada.")
		return
	if terrain_body == null:
		_fail("O corpo de colisão do terreno não foi criado.")
		return
	var collision_node := terrain_body.find_child("TerrainMeshCollision", true, false) as CollisionShape3D
	if collision_node == null or not (collision_node.shape is ConcavePolygonShape3D):
		_fail("A colisão não usa a malha triangular estática esperada.")
		return
	if world_environment == null or world_environment.environment == null:
		_fail("WorldEnvironment ou Environment ausente.")
		return
	if world_environment.environment.background_mode != Environment.BG_SKY or world_environment.environment.sky == null:
		_fail("O céu não está configurado como BG_SKY com recurso Sky.")
		return

	var arrays := terrain.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if vertices.is_empty() or normals.size() != vertices.size():
		_fail("A malha do terreno está vazia ou sem normais.")
		return
	var invalid_normals := 0
	for normal in normals:
		if not is_finite(normal.x) or not is_finite(normal.y) or not is_finite(normal.z) or normal.length_squared() < 0.9 or normal.y <= 0.0:
			invalid_normals += 1
	if invalid_normals > 0:
		_fail("%d normais do terreno são inválidas ou não apontam para cima." % invalid_normals)
		return

	# Confere também a orientação geométrica real dos triângulos, não apenas
	# as normais armazenadas na malha.
	var inverted_faces := 0
	var triangle_count := int(vertices.size() / 3)
	for triangle in range(triangle_count):
		var base := triangle * 3
		var face_normal := (vertices[base + 1] - vertices[base]).cross(vertices[base + 2] - vertices[base])
		if face_normal.length_squared() < 0.000001 or face_normal.y <= 0.0:
			inverted_faces += 1
	if inverted_faces > 0:
		_fail("%d triângulos do terreno têm orientação inválida." % inverted_faces)
		return

	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var checked_points := 0
	for x in SAMPLE_COORDS:
		for z in SAMPLE_COORDS:
			var expected_height: float = game.call("_terrain_height", x, z)
			if is_nan(expected_height) or is_inf(expected_height):
				_fail("A função de altura retornou valor inválido em (%s, %s)." % [x, z])
				return
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, 100.0, z),
				Vector3(x, -100.0, z),
				1
			)
			query.hit_back_faces = true
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				_fail("Sem colisão do chão no ponto (%s, %s)." % [x, z])
				return
			if hit.get("collider") != terrain_body:
				_fail("O raio atingiu outro corpo em (%s, %s), não a malha de colisão do terreno." % [x, z])
				return
			var actual_height: float = hit.position.y
			if absf(actual_height - expected_height) > HEIGHT_TOLERANCE:
				_fail("Colisão diverge do relevo em (%s, %s): esperado %.3f, obtido %.3f." % [x, z, expected_height, actual_height])
				return
			checked_points += 1

	if player == null or camera == null:
		_fail("Jogador ou câmera não foi instanciado.")
		return
	# Verifica que a posição inicial e os limites de inclinação não colocam a câmera
	# dentro da superfície; o _process normal também faz a correção por raycast.
	game.call("_process", 0.20)
	await process_frame
	var camera_floor: float = game.call("_terrain_height", camera.global_position.x, camera.global_position.z)
	if camera.global_position.y < camera_floor + 1.0:
		_fail("A câmera ficou abaixo da margem segura sobre o terreno.")
		return

	print("WORLD_DIAGNOSTICS_OK: %d pontos de colisão, normais para cima, céu válido e câmera acima do solo." % checked_points)
	quit(0)

func _fail(message: String) -> void:
	push_error("WORLD_DIAGNOSTICS_FAILED: " + message)
	quit(1)

func _find_typed_node(node: Node, kind: String) -> Node:
	match kind:
		"WorldEnvironment":
			if node is WorldEnvironment:
				return node
		"CharacterBody3D":
			if node is CharacterBody3D:
				return node
		"Camera3D":
			if node is Camera3D:
				return node
	for child in node.get_children():
		var found := _find_typed_node(child, kind)
		if found != null:
			return found
	return null
