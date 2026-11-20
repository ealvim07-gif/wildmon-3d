extends SceneTree

const SAMPLE_COORDS := [-55.0, -30.0, 0.0, 30.0, 55.0]

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

	var terrain := game.find_child("Terrain3D", true, false)
	var world_environment := _find_typed_node(game, "WorldEnvironment") as WorldEnvironment
	var player := _find_typed_node(game, "CharacterBody3D") as CharacterBody3D
	var camera := _find_typed_node(game, "Camera3D") as Camera3D

	if terrain == null or terrain.get_class() != "Terrain3D":
		_fail("O terreno principal não é uma instância real do Terrain3D.")
		return
	var data = terrain.get("data")
	if data == null or data.get_region_count() < 1:
		_fail("Terrain3D não carregou nenhuma região de terreno.")
		return

	for x in SAMPLE_COORDS:
		for z in SAMPLE_COORDS:
			var expected: float = game.call("_terrain_height", x, z)
			var actual: float = data.get_height(Vector3(x + 128.0, 0.0, z + 128.0))
			if not is_finite(actual) or absf(actual - expected) > 0.35:
				_fail("Heightmap Terrain3D divergente em (%s,%s): esperado %.2f, obtido %.2f." % [x, z, expected, actual])
				return

	if world_environment == null or world_environment.environment == null:
		_fail("WorldEnvironment ou Environment ausente.")
		return
	if world_environment.environment.background_mode != Environment.BG_SKY or world_environment.environment.sky == null:
		_fail("O céu não está configurado como BG_SKY com recurso Sky.")
		return
	if player == null or camera == null:
		_fail("Jogador ou câmera não foi instanciado.")
		return

	game.call("_process", 0.20)
	await process_frame
	var camera_floor: float = game.call("_terrain_height", camera.global_position.x, camera.global_position.z)
	if camera.global_position.y < camera_floor + 1.0:
		_fail("A câmera ficou abaixo da margem segura sobre o terreno.")
		return
	if player.global_position.y < game.call("_terrain_height", player.global_position.x, player.global_position.z) - 0.35:
		_fail("O protagonista iniciou abaixo da superfície do mapa.")
		return

	print("WORLD_DIAGNOSTICS_OK: Terrain3D real, %d região(ões), heightmap conferido em 25 pontos, céu e câmera válidos." % data.get_region_count())
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
