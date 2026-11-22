extends SceneTree
# Simulador headless para validar mundo, terreno infinito (Etapa 1), protagonista e HUD.
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

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Nao carregou res://scenes/main.tscn")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	await create_timer(0.15).timeout

	var terrain := game.get_node_or_null("WorldTerrain")
	if terrain == null:
		for child in game.get_children():
			if child.has_method("height_at"):
				terrain = child
				break
	_validate_infinite_height_stage1(terrain)

	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_fail("Jogador nao encontrado")
		quit(1)
		return
	_ok("Jogador instanciado em " + str(player.global_position))

	var camera := game.get_node_or_null("Player/CameraRig/Camera3D") as Camera3D
	if camera == null:
		_fail("Camera nao encontrada")
	else:
		_ok("Camera ativa: " + str(camera.current))

	if failed:
		quit(1)
	else:
		_ok("Simulacao Etapa 1 concluida com sucesso")
		quit(0)