extends SceneTree
# Simulador headless para validar Etapas 1, 2 e 3 do mundo infinito.
var failed := false

func _fail(msg: String) -> void:
	printerr("[SIM FAIL] ", msg)
	failed = true

func _ok(msg: String) -> void:
	print("[SIM OK] ", msg)

func _validate_infinite_height_stage1(terrain: Node) -> void:
	if terrain == null or not terrain.has_method("height_at"):
		_fail("No de terreno sem metodo height_at(x, z)")
		return
	var world_seed = terrain.get("WORLD_SEED")
	if world_seed == null:
		_fail("WORLD_SEED nao encontrado em world_terrain.gd")
		return
	_ok("WORLD_SEED encontrado: " + str(world_seed))

	var test_points: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1000.0, 0.0),
		Vector2(-1000.0, 1000.0),
		Vector2(5000.0, -5000.0),
		Vector2(0.0, 5000.0)
	]
	for pt in test_points:
		var h1: float = terrain.height_at(pt.x, pt.y)
		var h2: float = terrain.height_at(pt.x, pt.y)
		if not is_finite(h1) or not is_finite(h2):
			_fail("height_at retornou valor nao finito em " + str(pt))
			return
		if not is_equal_approx(h1, h2):
			_fail("height_at nao deterministico em " + str(pt) + ": " + str(h1) + " != " + str(h2))
			return
		_ok("height_at" + str(pt) + " = " + str(snappedf(h1, 0.001)) + " (deterministico)")

func _validate_chunk_manager_stage2(game: Node, terrain: Node) -> void:
	var cm = terrain.get("chunk_manager")
	if cm == null:
		_fail("ChunkManager nao inicializado em world_terrain.gd")
		return

	var max_allowed: int = cm.max_allowed_chunks()
	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_fail("Jogador nao encontrado para teste de caminhada de 300 m")
		return

	var start_pos := player.global_position
	if not cm.has_chunk_at_world_pos(start_pos):
		_fail("Chunk inicial sob o jogador nao foi gerado antes de liberar o movimento")
		return
	_ok("Chunk inicial presente sob o jogador em " + str(start_pos))

	var steps := 60
	var step_dist := 5.0
	for s in range(1, steps + 1):
		var target_x := start_pos.x + float(s) * step_dist
		var target_z := start_pos.z
		var ground_y: float = terrain.height_at(target_x, target_z)
		player.global_position = Vector3(target_x, ground_y + 0.12, target_z)
		cm.update_around(player.global_position)
		await process_frame

		var active_now: int = cm.get_active_chunk_count()
		if active_now > max_allowed:
			_fail("Chunks ativos (" + str(active_now) + ") ultrapassaram o limite (" + str(max_allowed) + ")")
			return
		if not cm.has_chunk_at_world_pos(player.global_position):
			_fail("Jogador afundaria sem chunk sob os pes em x=" + str(target_x))
			return
		if player.global_position.y < ground_y - 0.5:
			_fail("Jogador afundou abaixo do terreno em x=" + str(target_x))
			return

	_ok("Caminhada de 300 m concluida sem afundar. Chunks ativos finais: " + str(cm.get_active_chunk_count()) + " / max " + str(max_allowed))

func _validate_chunk_vegetation_stage3(terrain: Node) -> void:
	var cm = terrain.get("chunk_manager")
	if cm == null or not cm.has_method("generate_chunk_population_preview"):
		_fail("ChunkManager sem suporte a geracao deterministica de vegetacao (Etapa 3)")
		return

	var sample_coords: Array[Vector2i] = [
		Vector2i(2, -1),
		Vector2i(10, 15),
		Vector2i(-8, 6)
	]
	for coord in sample_coords:
		var pass1: Dictionary = cm.generate_chunk_population_preview(coord)
		var pass2: Dictionary = cm.generate_chunk_population_preview(coord)
		var trees1: int = int(pass1.get("trees", -1))
		var trees2: int = int(pass2.get("trees", -2))
		if trees1 != trees2 or trees1 < 0 or trees1 > 20:
			_fail("Geracao de arvores nao deterministica ou fora do limite [0..20] no chunk " + str(coord) + ": " + str(trees1) + " vs " + str(trees2))
			return
		_ok("Chunk " + str(coord) + " deterministico: " + str(trees1) + " arvores (<= 20)")

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Nao carregou res://scenes/main.tscn")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	if game.has_method("_start_game"):
		game.call("_start_game")
	await create_timer(0.25).timeout

	var terrain := game.get_node_or_null("ChunkTerrain")
	if terrain == null:
		for child in game.get_children():
			if child.has_method("height_at"):
				terrain = child
				break

	_validate_infinite_height_stage1(terrain)
	if not failed:
		await _validate_chunk_manager_stage2(game, terrain)
	if not failed:
		_validate_chunk_vegetation_stage3(terrain)

	var camera := game.get_node_or_null("Player/CameraRig/Camera3D") as Camera3D
	if camera == null:
		for cam in root.find_children("*", "Camera3D", true, false):
			if (cam as Camera3D).current:
				camera = cam as Camera3D
				break
	if camera == null:
		_fail("Camera ativa nao encontrada")
	else:
		_ok("Camera ativa: " + str(camera.current))

	if failed:
		quit(1)
	else:
		_ok("Simulacao Etapa 3 concluida com sucesso")
		quit(0)