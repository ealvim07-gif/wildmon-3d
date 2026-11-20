extends SceneTree

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

	var ground := game.find_child("StableGrassPlane", true, false) as MeshInstance3D
	var ground_body := game.find_child("GroundCollision", true, false) as StaticBody3D
	var world_environment := game.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var player := game.find_child("CharacterBody3D", true, false) as CharacterBody3D
	var camera := game.get("camera") as Camera3D
	if camera == null:
		camera = game.find_child("Camera3D", true, false) as Camera3D

	if ground == null or not ground.mesh is PlaneMesh:
		_fail("Plano StableGrassPlane ausente ou não é PlaneMesh.")
		return
	var plane := ground.mesh as PlaneMesh
	if plane.size != Vector2(400.0, 400.0):
		_fail("Plano de chão não possui dimensões esperadas de 400x400.")
		return
	if ground_body == null or ground_body.find_child("CollisionShape3D", true, false) == null:
		_fail("Colisão do plano de chão ausente.")
		return
	if world_environment == null or world_environment.environment == null:
		_fail("WorldEnvironment ou Environment ausente.")
		return
	if world_environment.environment.background_mode != Environment.BG_SKY or world_environment.environment.sky == null:
		_fail("Céu não configurado com BG_SKY e Sky.")
		return
	if player == null or camera == null:
		_fail("Jogador ou câmera não foi instanciado.")
		return
	if player.global_position.y < -0.35:
		_fail("Protagonista iniciou abaixo do plano.")
		return

	print("WORLD_DIAGNOSTICS_OK: plano 400x400, colisão, céu, jogador e câmera validados.")
	quit(0)

func _fail(message: String) -> void:
	push_error("WORLD_DIAGNOSTICS_FAILED: " + message)
	quit(1)
