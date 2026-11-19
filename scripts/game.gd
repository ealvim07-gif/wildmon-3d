extends Node3D

const MOVE_SPEED := 5.2
const TURN_SPEED := 10.0
const CAMERA_DISTANCE := 6.5

var player: CharacterBody3D
var player_model: Node3D
var camera: Camera3D
var creature: Node3D
var creature_home := Vector3(2.5, 0.72, -9.0)
var creature_captured := false
var creature_in_range := false
var look_yaw := 0.0
var target_look_yaw := 0.0
var look_pitch := 0.28
var target_look_pitch := 0.28
const CAMERA_SENSITIVITY := 0.0026
var nature_model_cache: Dictionary = {}
var status_label: Label
var capture_button: Button
var touch_left := false
var touch_right := false
var touch_forward := false
var touch_back := false
var camera_drag_active := false

func _ready() -> void:
	_build_world()
	_build_player()
	_build_creature()
	_build_ui()
	_update_status("Explore o vale e encontre uma criatura!")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var screen_size := get_viewport().get_visible_rect().size
			camera_drag_active = event.position.x > screen_size.x * 0.42 and event.position.y < screen_size.y * 0.84
		else:
			camera_drag_active = false
	elif event is InputEventScreenDrag and camera_drag_active:
		target_look_yaw -= event.relative.x * CAMERA_SENSITIVITY
		target_look_pitch = clampf(target_look_pitch + event.relative.y * CAMERA_SENSITIVITY, -0.34, 0.82)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		camera_drag_active = event.pressed
	elif event is InputEventMouseMotion and camera_drag_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		target_look_yaw -= event.relative.x * CAMERA_SENSITIVITY
		target_look_pitch = clampf(target_look_pitch + event.relative.y * CAMERA_SENSITIVITY, -0.34, 0.82)

func _process(delta: float) -> void:
	if player == null:
		return
	look_yaw = lerp_angle(look_yaw, target_look_yaw, minf(delta * 7.0, 1.0))
	look_pitch = lerpf(look_pitch, target_look_pitch, minf(delta * 7.0, 1.0))
	var target := player.global_position + Vector3(0, 1.25, 0)
	var horizontal := cos(look_pitch) * CAMERA_DISTANCE
	var cam_offset := Vector3(sin(look_yaw) * horizontal, sin(look_pitch) * CAMERA_DISTANCE, cos(look_yaw) * horizontal)
	camera.global_position = camera.global_position.lerp(target + cam_offset, minf(delta * 5.5, 1.0))
	camera.look_at(target, Vector3.UP)
	if creature and not creature_captured:
		creature.rotate_y(delta * 0.55)
		var creature_clock := Time.get_ticks_msec() * 0.00045
		creature.position = creature_home + Vector3(sin(creature_clock) * 0.55, sin(creature_clock * 4.0) * 0.10, cos(creature_clock * 0.8) * 0.32)
		var now_in_range := player.global_position.distance_to(creature.global_position) < 3.0
		if now_in_range != creature_in_range:
			creature_in_range = now_in_range
			if creature_in_range:
				_update_status("Uma criatura selvagem apareceu! Toque em CAPTURAR.")
			else:
				_update_status("Explore o vale e encontre uma criatura!")

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var x := float(touch_right) - float(touch_left)
	var z := float(touch_back) - float(touch_forward)
	var input_dir := Vector2(x, z)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	var forward := Vector3(sin(look_yaw), 0, cos(look_yaw))
	var right := Vector3(forward.z, 0, -forward.x)
	var direction := right * input_dir.x + forward * input_dir.y
	player.velocity.x = direction.x * MOVE_SPEED
	player.velocity.z = direction.z * MOVE_SPEED
	if not player.is_on_floor():
		player.velocity.y -= 9.8 * delta
	else:
		player.velocity.y = 0
	player.move_and_slide()
	var bounded_position := player.global_position
	bounded_position.x = clampf(bounded_position.x, -66.0, 66.0)
	bounded_position.z = clampf(bounded_position.z, -66.0, 66.0)
	if bounded_position != player.global_position:
		player.global_position = bounded_position
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	if player_model:
		var moving := direction.length() > 0.1
		var gait := sin(Time.get_ticks_msec() * 0.012) if moving else 0.0
		player_model.position.y = absf(gait) * 0.045
		player_model.rotation.z = lerpf(player_model.rotation.z, gait * 0.025, min(delta * 8.0, 1.0))
	if direction.length() > 0.1:
		player.rotation.y = lerp_angle(player.rotation.y, atan2(direction.x, direction.z) + PI, min(delta * TURN_SPEED, 1.0))

func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.30, 0.62)
	sky_mat.sky_horizon_color = Color(0.68, 0.79, 0.84)
	sky_mat.ground_bottom_color = Color(0.17, 0.23, 0.17)
	sky_mat.ground_horizon_color = Color(0.54, 0.62, 0.48)
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.18
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.78, 0.84, 0.91)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.65, 0.75, 0.78)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.55
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -32, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.91, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)

	_build_terrain()
	var ground_body := StaticBody3D.new()
	ground_body.position.y = -4.5
	add_child(ground_body)
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(148, 1.0, 148)
	ground_shape.shape = ground_box
	ground_body.add_child(ground_shape)

	_build_trail()
	_build_distant_ridges()
	_build_waterhole()

	var rng := RandomNumberGenerator.new()
	rng.seed = 81027
	for i in range(68):
		var px := rng.randf_range(-65.0, 65.0)
		var pz := rng.randf_range(-66.0, 66.0)
		if absf(px) < 9.0 and pz < 11.0 and pz > -31.0:
			continue
		_add_tree(Vector3(px, _terrain_height(px, pz), pz), i)
	for i in range(72):
		var px := rng.randf_range(-66.0, 66.0)
		var pz := rng.randf_range(-66.0, 66.0)
		if absf(px) < 7.0 and pz < 12.0 and pz > -31.0:
			continue
		_add_plant(Vector3(px, _terrain_height(px, pz), pz), i)
	for i in range(36):
		var px := rng.randf_range(-66.0, 66.0)
		var pz := rng.randf_range(-66.0, 66.0)
		if absf(px) < 9.0 and pz < 12.0 and pz > -30.0:
			continue
		_add_rock(Vector3(px, _terrain_height(px, pz), pz), i)
	for i in range(84):
		var px := rng.randf_range(-67.0, 67.0)
		var pz := rng.randf_range(-67.0, 67.0)
		if absf(px) < 8.0 and pz < 12.0 and pz > -31.0:
			continue
		_add_grass_tuft(Vector3(px, _terrain_height(px, pz), pz), i)

func _build_trail() -> void:
	var points := [
		Vector3(0.0, 0.0, 18.0), Vector3(-1.2, 0.0, 12.0),
		Vector3(1.0, 0.0, 6.0), Vector3(0.2, 0.0, 0.0),
		Vector3(-2.0, 0.0, -7.0), Vector3(-0.8, 0.0, -14.0),
		Vector3(2.0, 0.0, -22.0), Vector3(1.0, 0.0, -31.0)
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var side := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized() * 2.5
		var a_left := a - side
		var a_right := a + side
		var b_left := b - side
		var b_right := b + side
		a_left.y = _terrain_height(a_left.x, a_left.z) + 0.035
		a_right.y = _terrain_height(a_right.x, a_right.z) + 0.035
		b_left.y = _terrain_height(b_left.x, b_left.z) + 0.035
		b_right.y = _terrain_height(b_right.x, b_right.z) + 0.035
		surface.add_vertex(a_left)
		surface.add_vertex(b_left)
		surface.add_vertex(a_right)
		surface.add_vertex(a_right)
		surface.add_vertex(b_left)
		surface.add_vertex(b_right)
	surface.generate_normals()
	var trail := MeshInstance3D.new()
	trail.mesh = surface.commit()
	trail.material_override = _mat(Color(0.48, 0.38, 0.25))
	add_child(trail)

func _build_distant_ridges() -> void:
	# Silhuetas facetadas em vez de montes esféricos repetidos.
	for i in range(12):
		var ridge := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.15 + float(i % 3) * 0.22
		mesh.bottom_radius = 7.0 + float(i % 4) * 2.0
		mesh.height = 10.0 + float(i % 5) * 2.5
		mesh.radial_segments = 7 + (i % 3)
		mesh.rings = 1
		ridge.mesh = mesh
		var angle := TAU * float(i) / 12.0
		ridge.position = Vector3(cos(angle) * 76.0, mesh.height * 0.40 - 1.0, sin(angle) * 76.0)
		ridge.rotation.y = angle * 0.37
		ridge.material_override = _mat([Color(0.20, 0.32, 0.26), Color(0.25, 0.37, 0.29), Color(0.29, 0.39, 0.31)][i % 3])
		add_child(ridge)

func _build_waterhole() -> void:
	var shore := MeshInstance3D.new()
	var shore_mesh := CylinderMesh.new()
	shore_mesh.top_radius = 4.8
	shore_mesh.bottom_radius = 5.2
	shore_mesh.height = 0.18
	shore.mesh = shore_mesh
	shore.position = Vector3(-17.0, _terrain_height(-17.0, -12.0) + 0.05, -12.0)
	shore.material_override = _mat(Color(0.52, 0.43, 0.29))
	add_child(shore)
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 4.0
	water_mesh.bottom_radius = 4.0
	water_mesh.height = 0.035
	water.mesh = water_mesh
	water.position = shore.position + Vector3(0.0, 0.10, 0.0)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.12, 0.39, 0.49, 0.88)
	water_mat.roughness = 0.18
	water_mat.metallic = 0.12
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	water.material_override = water_mat
	add_child(water)
	for i in range(18):
		var angle := TAU * float(i) / 18.0
		_add_rock(Vector3(-17.0 + cos(angle) * 4.45, shore.position.y + 0.08, -12.0 + sin(angle) * 4.45), i + 90)

func _build_terrain() -> void:
	# Terrain3D gera malha com LOD e colisão própria, substituindo a malha
	# densa fixa do protótipo. O mapa é criado a partir do mesmo relevo usado
	# para posicionar árvores, plantas, trilha e criaturas.
	if not ClassDB.can_instantiate("Terrain3D"):
		push_error("Terrain3D não foi carregado. Confira addons/terrain_3d.")
		return

	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.region_size = 256
	terrain.mesh_lods = 6
	terrain.mesh_size = 32
	terrain.collision.mode = Terrain3DCollision.FULL_GAME
	add_child(terrain)

	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", 18.0)
	terrain.material.set_shader_param("blend_sharpness", 0.965)

	var terrain_assets := Terrain3DAssets.new()
	terrain_assets.set_texture(0, _make_terrain_texture(
		"Vale - grama", Color(0.17, 0.29, 0.12), Color(0.34, 0.43, 0.19), 713
	))
	terrain_assets.set_texture(1, _make_terrain_texture(
		"Solo - terra e pedra", Color(0.31, 0.25, 0.16), Color(0.48, 0.40, 0.28), 927
	))
	terrain.assets = terrain_assets

	var height_map := Image.create(256, 256, false, Image.FORMAT_RF)
	for z in range(256):
		for x in range(256):
			var world_x := float(x) - 128.0
			var world_z := float(z) - 128.0
			height_map.set_pixel(x, z, Color(_terrain_height(world_x, world_z) / 3.5, 0.0, 0.0, 1.0))
	terrain.data.import_images([height_map, null, null], Vector3(-128.0, 0.0, -128.0), 0.0, 3.5)

func _make_terrain_texture(asset_name: String, base_color: Color, accent_color: Color, noise_seed: int) -> Terrain3DTextureAsset:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.035
	var albedo_image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var normal_image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	normal_image.fill(Color(0.5, 0.5, 1.0, 0.82))
	for y in range(256):
		for x in range(256):
			var variation := clampf(0.5 + noise.get_noise_2d(float(x), float(y)) * 0.48, 0.0, 1.0)
			var color := base_color.lerp(accent_color, variation)
			albedo_image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.5 + variation * 0.2))
	var asset := Terrain3DTextureAsset.new()
	asset.name = asset_name
	asset.albedo_texture = ImageTexture.create_from_image(albedo_image)
	asset.normal_texture = ImageTexture.create_from_image(normal_image)
	asset.uv_scale = 0.12
	return asset

func _terrain_height(x: float, z: float) -> float:
	var edge_factor := clampf((maxf(absf(x), absf(z)) - 4.0) / 25.0, 0.0, 1.0)
	# Ondas cruzadas e cristas alongadas quebram o padrão de colinas circulares.
	var rolling := sin(x * 0.105 + z * 0.072) * 0.62 + cos(z * 0.091 - x * 0.063) * 0.48
	var warped_x := x + sin(z * 0.075) * 3.2
	var ridge_a := pow(1.0 - absf(sin((warped_x + z * 0.22) * 0.082)), 2.2) * 1.55
	var ridge_b := pow(1.0 - absf(sin((x * 0.17 - z * 0.31 + 11.0) * 0.071)), 2.8) * 0.92
	var detail := sin(x * 0.31 + z * 0.19) * 0.16 + cos(z * 0.27 - x * 0.23) * 0.13
	var erosion := -absf(sin(x * 0.045 + z * 0.031)) * 0.24
	return maxf(-0.28, (rolling + ridge_a + ridge_b + detail + erosion) * edge_factor)

func _add_rock(pos: Vector3, seed: int) -> void:
	var rock_scene := _get_nature_scene(["Rock_Medium_1", "Rock_Medium_2"], seed)
	if rock_scene:
		var rock := rock_scene.instantiate() as Node3D
		add_child(rock)
		rock.position = pos
		rock.scale = Vector3.ONE * (0.62 + float(seed % 5) * 0.13)
		rock.rotation.y = float(seed * 37 % 360) * PI / 180.0
		return
	# Fallback usado apenas se a transferência dos modelos não estiver disponível.
	var rock := MeshInstance3D.new()
	var rock_mesh := SphereMesh.new()
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 3
	rock.mesh = rock_mesh
	rock.position = pos + Vector3(0, 0.18, 0)
	rock.scale = Vector3(0.48, 0.30, 0.40)
	rock.material_override = _mat(Color(0.39, 0.42, 0.39))
	add_child(rock)

func _add_grass_tuft(pos: Vector3, seed: int) -> void:
	var grass_scene := _get_nature_scene(["Grass_Common_Tall", "Clover_1"], seed)
	if grass_scene:
		var grass := grass_scene.instantiate() as Node3D
		add_child(grass)
		grass.position = pos
		var scale_factor := 0.48 + float(seed % 5) * 0.10
		grass.scale = Vector3.ONE * scale_factor
		grass.rotation.y = float(seed * 29 % 360) * PI / 180.0
		return
	for blade in range(3):
		var grass := MeshInstance3D.new()
		var grass_mesh := BoxMesh.new()
		grass_mesh.size = Vector3(0.055, 0.28, 0.045)
		grass.mesh = grass_mesh
		grass.position = pos + Vector3((float(blade) - 1.0) * 0.09, 0.14, 0.0)
		grass.rotation_degrees = Vector3(0, float(blade) * 60.0, float(blade - 1) * 18.0)
		grass.material_override = _mat(Color(0.28, 0.46, 0.18))
		add_child(grass)

func _add_tree(pos: Vector3, seed: int) -> void:
	var tree_scene := _get_nature_scene(["CommonTree_1", "CommonTree_2", "CommonTree_3", "Pine_1", "Pine_2"], seed)
	if tree_scene:
		var tree := tree_scene.instantiate() as Node3D
		add_child(tree)
		tree.position = pos
		var scale_factor := 0.78 + float(seed % 5) * 0.11
		tree.scale = Vector3.ONE * scale_factor
		tree.rotation.y = float(seed * 53 % 360) * PI / 180.0
		var trunk_body := StaticBody3D.new()
		trunk_body.position = pos + Vector3(0.0, 1.35 * scale_factor, 0.0)
		add_child(trunk_body)
		var trunk_collision := CollisionShape3D.new()
		var trunk_shape := CylinderShape3D.new()
		trunk_shape.radius = 0.28 * scale_factor
		trunk_shape.height = 2.7 * scale_factor
		trunk_collision.shape = trunk_shape
		trunk_body.add_child(trunk_collision)
		return
	# Fallback geométrico para execução local sem os arquivos externos.
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 3.2
	trunk.mesh = trunk_mesh
	trunk.position = pos + Vector3(0, 1.6, 0)
	trunk.material_override = _mat(Color(0.25, 0.15, 0.085))
	add_child(trunk)

func _get_nature_scene(names: Array, seed: int) -> PackedScene:
	if names.is_empty():
		return null
	var model_name: String = names[seed % names.size()]
	if not nature_model_cache.has(model_name):
		var path := "res://assets/nature/" + model_name + ".gltf"
		if ResourceLoader.exists(path):
			nature_model_cache[model_name] = load(path)
		else:
			nature_model_cache[model_name] = null
	return nature_model_cache[model_name] as PackedScene

func _add_plant(pos: Vector3, seed: int) -> void:
	var plant_scene := _get_nature_scene(["Fern_1", "Bush_Common", "Clover_1", "Flower_3_Group"], seed)
	if plant_scene:
		var plant := plant_scene.instantiate() as Node3D
		add_child(plant)
		plant.position = pos
		var scale_factor := 0.30 + float(seed % 5) * 0.10
		plant.scale = Vector3.ONE * scale_factor
		plant.rotation.y = float(seed * 41 % 360) * PI / 180.0
		return
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.025
	stem_mesh.bottom_radius = 0.045
	stem_mesh.height = 0.48
	stem.mesh = stem_mesh
	stem.position = pos + Vector3(0, 0.24, 0)
	stem.material_override = _mat(Color(0.20, 0.38, 0.16))
	add_child(stem)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 1, 4)
	add_child(player)
	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.75
	body.shape = capsule
	body.position.y = 0.88
	player.add_child(body)
	player_model = Node3D.new()
	player.add_child(player_model)

	_add_sphere_part(player_model, Vector3(0, 1.20, 0), Vector3(0.43, 0.55, 0.31), Color(0.12, 0.31, 0.48))
	_add_sphere_part(player_model, Vector3(0, 1.92, 0.015), Vector3(0.30, 0.34, 0.29), Color(0.88, 0.67, 0.52))
	_add_sphere_part(player_model, Vector3(0, 2.13, -0.025), Vector3(0.34, 0.18, 0.32), Color(0.12, 0.15, 0.19))
	_add_sphere_part(player_model, Vector3(0, 2.04, 0.015), Vector3(0.34, 0.10, 0.31), Color(0.86, 0.33, 0.12))
	_add_sphere_part(player_model, Vector3(0, 0.63, 0), Vector3(0.34, 0.22, 0.27), Color(0.17, 0.20, 0.25))
	_add_sphere_part(player_model, Vector3(0, 1.22, -0.34), Vector3(0.29, 0.39, 0.18), Color(0.72, 0.31, 0.12))
	_add_sphere_part(player_model, Vector3(-0.17, 1.26, 0.27), Vector3(0.035, 0.40, 0.035), Color(0.91, 0.75, 0.42))
	_add_sphere_part(player_model, Vector3(0.17, 1.26, 0.27), Vector3(0.035, 0.40, 0.035), Color(0.91, 0.75, 0.42))
	for side in [-1.0, 1.0]:
		_add_capsule_part(player_model, Vector3(side * 0.47, 1.18, 0), Vector3(0.13, 0.40, 0.13), Color(0.82, 0.57, 0.42))
		_add_sphere_part(player_model, Vector3(side * 0.49, 0.91, 0.02), Vector3(0.14, 0.14, 0.14), Color(0.18, 0.20, 0.23))
		_add_capsule_part(player_model, Vector3(side * 0.19, 0.32, 0), Vector3(0.16, 0.42, 0.17), Color(0.12, 0.18, 0.27))
		_add_sphere_part(player_model, Vector3(side * 0.19, 0.10, 0.10), Vector3(0.19, 0.11, 0.29), Color(0.09, 0.10, 0.12))
	_add_sphere_part(player_model, Vector3(0, 1.91, 0.285), Vector3(0.045, 0.045, 0.035), Color(0.10, 0.09, 0.08))
	_add_sphere_part(player_model, Vector3(0.17, 1.97, 0.27), Vector3(0.035, 0.045, 0.025), Color(0.10, 0.09, 0.08))

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 62
	add_child(camera)
	camera.global_position = Vector3(0, 3.2, 11.5)
	camera.look_at(Vector3(0, 1, 0))

func _build_creature() -> void:
	creature = Node3D.new()
	creature.position = creature_home
	add_child(creature)
	# Brasafofo: raposa elemental original, com focinho, marcas e cauda flamejante.
	_add_sphere_part(creature, Vector3(0, 0.02, 0), Vector3(0.70, 0.45, 0.43), Color(0.78, 0.22, 0.075))
	_add_sphere_part(creature, Vector3(0, 0.31, 0.37), Vector3(0.41, 0.39, 0.38), Color(0.94, 0.36, 0.09))
	_add_sphere_part(creature, Vector3(0, 0.13, 0.69), Vector3(0.24, 0.17, 0.19), Color(1.0, 0.78, 0.47))
	_add_sphere_part(creature, Vector3(0, -0.12, 0.18), Vector3(0.43, 0.25, 0.31), Color(1.0, 0.70, 0.34))
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := PrismMesh.new()
		ear_mesh.size = Vector3(0.25, 0.48, 0.18)
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.25, 0.66, 0.34)
		ear.rotation.z = side * -0.18
		ear.material_override = _mat(Color(0.77, 0.20, 0.055))
		creature.add_child(ear)
		_add_sphere_part(creature, Vector3(side * 0.25, 0.67, 0.405), Vector3(0.075, 0.20, 0.035), Color(1.0, 0.62, 0.32))
		_add_sphere_part(creature, Vector3(side * 0.18, 0.40, 0.70), Vector3(0.075, 0.095, 0.045), Color(0.98, 0.91, 0.68))
		_add_sphere_part(creature, Vector3(side * 0.18, 0.40, 0.735), Vector3(0.035, 0.055, 0.025), Color(0.08, 0.06, 0.05))
		_add_capsule_part(creature, Vector3(side * 0.43, -0.29, 0.12), Vector3(0.13, 0.27, 0.13), Color(0.78, 0.22, 0.075))
		_add_sphere_part(creature, Vector3(side * 0.43, -0.46, 0.19), Vector3(0.16, 0.09, 0.19), Color(0.25, 0.12, 0.08))
	_add_sphere_part(creature, Vector3(0, 0.10, -0.52), Vector3(0.19, 0.22, 0.20), Color(0.86, 0.25, 0.06))
	_add_sphere_part(creature, Vector3(0, 0.34, -0.76), Vector3(0.29, 0.36, 0.25), Color(1.0, 0.46, 0.045))
	_add_sphere_part(creature, Vector3(0, 0.48, -0.84), Vector3(0.18, 0.25, 0.15), Color(1.0, 0.84, 0.22))
	_add_sphere_part(creature, Vector3(0, 0.63, -0.87), Vector3(0.09, 0.14, 0.08), Color(1.0, 0.97, 0.63))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.025
	panel.anchor_top = 0.025
	panel.anchor_right = 0.975
	panel.anchor_bottom = 0.155
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.075, 0.085, 0.84)
	panel_style.border_color = Color(0.47, 0.66, 0.54, 0.75)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(13)
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 7
	panel_style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "WILDMON 3D   •   BETA 2.0"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.91, 0.96, 0.87))
	vbox.add_child(title)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.72, 0.84, 0.73))
	status_label.text = "Explore o vale e encontre uma criatura!"
	vbox.add_child(status_label)

	var controls := HBoxContainer.new()
	controls.anchor_left = 0.025
	controls.anchor_top = 0.69
	controls.anchor_right = 0.975
	controls.anchor_bottom = 0.975
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 12)
	layer.add_child(controls)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 3)
	controls.add_child(left_col)
	var up := _make_button("▲")
	left_col.add_child(up)
	up.button_down.connect(func(): touch_forward = true)
	up.button_up.connect(func(): touch_forward = false)
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 3)
	left_col.add_child(middle)
	var left := _make_button("◀")
	middle.add_child(left)
	left.button_down.connect(func(): touch_left = true)
	left.button_up.connect(func(): touch_left = false)
	var down := _make_button("▼")
	middle.add_child(down)
	down.button_down.connect(func(): touch_back = true)
	down.button_up.connect(func(): touch_back = false)
	var right := _make_button("▶")
	middle.add_child(right)
	right.button_down.connect(func(): touch_right = true)
	right.button_up.connect(func(): touch_right = false)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	capture_button = _make_button("CAPTURAR")
	capture_button.custom_minimum_size = Vector2(148, 62)
	capture_button.add_theme_font_size_override("font_size", 16)
	var capture_style := StyleBoxFlat.new()
	capture_style.bg_color = Color(0.70, 0.25, 0.09, 0.96)
	capture_style.border_color = Color(1.0, 0.72, 0.38)
	capture_style.set_border_width_all(2)
	capture_style.set_corner_radius_all(12)
	capture_button.add_theme_stylebox_override("normal", capture_style)
	var capture_hover := capture_style.duplicate()
	capture_hover.bg_color = Color(0.86, 0.34, 0.11, 1.0)
	capture_button.add_theme_stylebox_override("hover", capture_hover)
	var capture_pressed := capture_style.duplicate()
	capture_pressed.bg_color = Color(0.48, 0.16, 0.06, 1.0)
	capture_button.add_theme_stylebox_override("pressed", capture_pressed)
	capture_button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.87))
	capture_button.pressed.connect(_try_capture)
	controls.add_child(capture_button)

func _make_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(54, 54)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.91, 0.95, 0.88))
	button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.055, 0.12, 0.13, 0.84)
	normal.border_color = Color(0.50, 0.67, 0.54, 0.85)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(11)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.23, 0.19, 0.95)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.20, 0.33, 0.22, 1.0)
	button.add_theme_stylebox_override("pressed", pressed)
	return button

func _try_capture() -> void:
	if player == null:
		return
	if creature_captured:
		_update_status("Você já capturou o Brasafofo! Beta concluída.")
		return
	if creature == null or not is_instance_valid(creature):
		_update_status("Não há criatura disponível para capturar.")
		return
	if player.global_position.distance_to(creature.global_position) > 3.5:
		_update_status("Chegue mais perto da criatura para capturá-la.")
		return
	creature_captured = true
	creature.queue_free()
	creature = null
	capture_button.text = "CAPTURADO!"
	_update_status("Captura realizada! Você capturou um Brasafofo.")

func _update_status(message: String) -> void:
	if status_label:
		status_label.text = message

func _add_sphere_part(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	part.mesh = mesh
	part.position = pos
	part.scale = size
	part.material_override = _mat(color)
	parent.add_child(part)

func _add_capsule_part(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 2.0
	part.mesh = mesh
	part.position = pos
	part.scale = size
	part.material_override = _mat(color)
	parent.add_child(part)

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	material.metallic = 0.0
	return material

func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, collision: bool) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.material_override = _mat(color)
	parent.add_child(mesh_instance)
	if collision:
		var body := StaticBody3D.new()
		body.position = pos
		parent.add_child(body)
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
