extends SceneTree
# Simulador de teste do Wildmon 3D (sem tela). NAO e carregado pelo jogo.
# Uso: godot --headless --fixed-fps 60 --path . --script res://scripts/sim_test.gd
# Imprime linhas "SIM: ..." e termina com "SIM_RESULT: PASS" ou "SIM_RESULT: FAIL".
#
# O que ele verifica (fatos medidos, nao opiniao sobre beleza):
#  1. O terreno carrega, tem height_at(x, z), a planicie inicial e plana e existe agua.
#  2. Um corpo com a altura do jogador anda de verdade sobre o terreno (colisao, subida, lago).
#  3. O jogo inicia ate o fim da tela inicial e roda 120 quadros sem parar.
#  4. Contrato de escala: arvores no grupo "trees" com meta "height_m"; camera no grupo "player_camera".

const PLAYER_HEIGHT := 1.8
const PLAYER_RADIUS := 0.35
const WALK_SPEED := 4.5
const GRAVITY := 18.0
const SPAWN := Vector3(-4.0, 0.0, -42.0)
const MAX_GEN_MS := 4000
const MAX_SLOPE_DEG := 45.0
const TREE_MIN_M := 4.0
const TREE_MAX_M := 25.0
const EYE_MIN_M := 1.4
const EYE_MAX_M := 1.9

var failures: Array[String] = []
var warnings: Array[String] = []

func _initialize() -> void:
	_run()

func _log(msg: String) -> void:
	print("SIM: ", msg)

func _fail(msg: String) -> void:
	failures.append(msg)
	print("SIM: FALHA - ", msg)

func _warn(msg: String) -> void:
	warnings.append(msg)
	print("SIM: AVISO - ", msg)

func _run() -> void:
	var terrain = _terrain_check()
	if terrain != null:
		await _walker_check(terrain)
	await _game_check()
	_finish()

# ------------------------------------------------------------ 1. terreno

var lowest_point := Vector3.ZERO
var highest_point := Vector3.ZERO

func _terrain_check():
	var script = load("res://scripts/world_terrain.gd")
	if script == null:
		_fail("world_terrain.gd nao pode ser carregado")
		return null
	var terrain = script.new()
	var t0 := Time.get_ticks_msec()
	root.add_child(terrain)
	var gen_ms := Time.get_ticks_msec() - t0
	_log("terreno gerado em %d ms" % gen_ms)
	if gen_ms > MAX_GEN_MS:
		_warn("geracao do terreno lenta (%d ms neste computador; no celular costuma ser pior)" % gen_ms)
	if not terrain.has_method("height_at"):
		_fail("o terreno nao tem a funcao height_at(x, z)")
		return null
	var max_flat := 0.0
	for xi in range(-60, 61, 6):
		for zi in range(-60, 61, 6):
			if Vector2(float(xi), float(zi)).length() <= 60.0:
				var hf: float = terrain.height_at(float(xi), float(zi))
				max_flat = maxf(max_flat, absf(hf))
	_log("altura maxima na planicie inicial (60 m): %.3f m" % max_flat)
	if max_flat > 0.05:
		_fail("a planicie inicial nao esta plana (%.3f m)" % max_flat)
	var water_points := 0
	var min_h := 1000.0
	var max_h := -1000.0
	var max_slope := 0.0
	for xi in range(-118, 119, 4):
		for zi in range(-118, 119, 4):
			var x := float(xi)
			var z := float(zi)
			var h: float = terrain.height_at(x, z)
			if h < min_h:
				min_h = h
				lowest_point = Vector3(x, h, z)
			if h > max_h:
				max_h = h
				highest_point = Vector3(x, h, z)
			if h < -1.0:
				water_points += 1
			var gx: float = (float(terrain.height_at(x + 2.0, z)) - float(terrain.height_at(x - 2.0, z))) / 4.0
			var gz: float = (float(terrain.height_at(x, z + 2.0)) - float(terrain.height_at(x, z - 2.0))) / 4.0
			max_slope = maxf(max_slope, sqrt(gx * gx + gz * gz))
	var slope_deg := rad_to_deg(atan(max_slope))
	_log("altura minima %.2f m, maxima %.2f m, inclinacao maxima %.1f graus" % [min_h, max_h, slope_deg])
	if slope_deg > MAX_SLOPE_DEG:
		_warn("inclinacao maxima alta (%.1f graus)" % slope_deg)
	_log("pontos de agua (altura < -1 m): %d" % water_points)
	if water_points == 0:
		_warn("nenhum ponto de agua encontrado")
	return terrain

# ------------------------------------------------------------ 2. jogador andando

func _walker_check(terrain) -> void:
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT
	cs.shape = capsule
	cs.position = Vector3(0.0, PLAYER_HEIGHT * 0.5, 0.0)
	body.add_child(cs)
	body.floor_max_angle = deg_to_rad(56.0)
	root.add_child(body)
	await physics_frame
	await physics_frame
	await _walk(body, terrain, Vector3(SPAWN.x + 20.0, 0.0, SPAWN.z), 4.0, "planicie (leste)")
	await _walk(body, terrain, Vector3(SPAWN.x, 0.0, SPAWN.z - 20.0), 4.0, "planicie (frente)")
	var to_lake := Vector2(lowest_point.x - SPAWN.x, lowest_point.z - SPAWN.z).length()
	await _walk(body, terrain, lowest_point, minf(to_lake / WALK_SPEED + 3.0, 35.0), "ponto mais baixo (lago)")
	var to_hill := Vector2(highest_point.x - SPAWN.x, highest_point.z - SPAWN.z).length()
	await _walk(body, terrain, highest_point, minf(to_hill / WALK_SPEED + 3.0, 35.0), "ponto mais alto (colina)")
	body.queue_free()

func _walk(body: CharacterBody3D, terrain, target: Vector3, seconds: float, label: String) -> void:
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var start_ground: float = terrain.height_at(SPAWN.x, SPAWN.z)
	var start := Vector3(SPAWN.x, start_ground + 0.1, SPAWN.z)
	body.global_position = start
	body.velocity = Vector3.ZERO
	await physics_frame
	var worst_sink := 0.0
	var steps := int(seconds / delta)
	for i in range(steps):
		var pos := body.global_position
		var to_target := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		var dir := Vector3.ZERO
		if to_target.length() > 1.5:
			dir = to_target.normalized()
		var v := body.velocity
		v.x = dir.x * WALK_SPEED
		v.z = dir.z * WALK_SPEED
		if body.is_on_floor():
			v.y = 0.0
		else:
			v.y -= GRAVITY * delta
		body.velocity = v
		body.move_and_slide()
		var p := body.global_position
		var ground: float = terrain.height_at(p.x, p.z)
		worst_sink = maxf(worst_sink, ground - p.y)
		await physics_frame
	var end := body.global_position
	var moved := Vector2(end.x - start.x, end.z - start.z).length()
	var wanted := minf(Vector2(target.x - start.x, target.z - start.z).length(), WALK_SPEED * seconds)
	_log("%s: andou %.1f m de %.1f m, afundamento maximo %.2f m" % [label, moved, wanted, worst_sink])
	if worst_sink > 0.3:
		_fail("%s: o jogador afundou %.2f m no chao" % [label, worst_sink])
	if moved < wanted * 0.6:
		_fail("%s: o jogador travou (andou %.1f de %.1f m)" % [label, moved, wanted])

# ------------------------------------------------------------ 3 e 4. jogo completo e contrato

func _game_check() -> void:
	var packed = load("res://scenes/main.tscn")
	if packed == null:
		_warn("scenes/main.tscn nao encontrada: teste de inicializacao pulado")
		return
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(10):
		await process_frame
	if not game.has_method("_start_game"):
		_warn("funcao _start_game nao encontrada em game.gd: teste de inicializacao pulado")
		return
	game.call("_start_game")
	for i in range(120):
		await physics_frame
	_log("o jogo iniciou e rodou 120 quadros")
	var player = game.get("player")
	var gterrain = game.get("generated_terrain")
	if player is Node3D and gterrain != null:
		var pp: Vector3 = player.global_position
		var ground: float = gterrain.height_at(pp.x, pp.z)
		_log("jogador em y=%.2f, chao em y=%.2f" % [pp.y, ground])
		if pp.y < ground - 0.5:
			_fail("o jogador esta abaixo do chao depois de iniciar")
	else:
		_warn("nao achei 'player' ou 'generated_terrain' em game.gd")
	var trees := get_nodes_in_group("trees")
	if trees.is_empty():
		_warn("nenhuma arvore no grupo 'trees' (contrato: toda arvore entra no grupo 'trees' e tem a meta 'height_m')")
	else:
		var bad := 0
		for t in trees:
			var hm := float(t.get_meta("height_m", -1.0))
			if hm < TREE_MIN_M or hm > TREE_MAX_M:
				bad += 1
		_log("arvores no grupo 'trees': %d, fora da escala (%.0f a %.0f m): %d" % [trees.size(), TREE_MIN_M, TREE_MAX_M, bad])
		if bad > 0:
			_fail("%d arvores fora da escala permitida" % bad)
	var cams := get_nodes_in_group("player_camera")
	if cams.is_empty():
		_warn("nenhuma camera no grupo 'player_camera' (contrato: meta 'mode' = 'first' ou 'third')")
	else:
		var cam = cams[0]
		var mode := str(cam.get_meta("mode", "?"))
		_log("camera do jogador: modo %s" % mode)
		if mode == "first" and player is Node3D and gterrain != null:
			var cp: Vector3 = cam.global_position
			var eye: float = cp.y - float(gterrain.height_at(cp.x, cp.z))
			_log("altura dos olhos na primeira pessoa: %.2f m" % eye)
			if eye < EYE_MIN_M or eye > EYE_MAX_M:
				_fail("altura dos olhos fora do contrato (%.2f m, esperado %.1f a %.1f m)" % [eye, EYE_MIN_M, EYE_MAX_M])

func _finish() -> void:
	for w in warnings:
		print("SIM: resumo aviso - ", w)
	if failures.is_empty():
		print("SIM_RESULT: PASS (%d avisos)" % warnings.size())
		quit(0)
	else:
		for f in failures:
			print("SIM: resumo falha - ", f)
		print("SIM_RESULT: FAIL (%d falhas)" % failures.size())
		quit(1)
