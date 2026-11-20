extends Node3D

class AnalogStick extends Control:
	signal value_changed(value: Vector2)
	var pointer_index := -1
	var stick_value := Vector2.ZERO
	var knob_position := Vector2.ZERO
	var active := false

	func _ready() -> void:
		custom_minimum_size = Vector2(196, 196)
		mouse_filter = Control.MOUSE_FILTER_STOP
		knob_position = size * 0.5
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			if not active:
				knob_position = size * 0.5
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		# Converte o toque do viewport para coordenadas locais do analógico.
		# _gui_input já entrega event.position em coordenadas locais do Control.
		if event is InputEventScreenTouch:
			if event.pressed and pointer_index == -1:
				pointer_index = event.index
				active = true
				_update_stick(event.position)
			elif not event.pressed and event.index == pointer_index:
				pointer_index = -1
				_reset_stick()
		elif event is InputEventScreenDrag and event.index == pointer_index:
			_update_stick(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				active = true
				_update_stick(event.position)
			else:
				_reset_stick()
		elif event is InputEventMouseMotion and active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update_stick(event.position)

	func _update_stick(pointer: Vector2) -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.34
		var offset := pointer - center
		if offset.length() > radius:
			offset = offset.normalized() * radius
		knob_position = center + offset
		stick_value = Vector2(offset.x / radius, offset.y / radius)
		var input_strength := stick_value.length()
		if input_strength <= 0.12:
			stick_value = Vector2.ZERO
		else:
			stick_value = stick_value.normalized() * ((input_strength - 0.12) / 0.88)
		if stick_value.length() > 1.0:
			stick_value = stick_value.normalized()
		value_changed.emit(stick_value)
		queue_redraw()

	func _reset_stick() -> void:
		active = false
		stick_value = Vector2.ZERO
		knob_position = size * 0.5
		value_changed.emit(stick_value)
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.43
		draw_circle(center, radius, Color(0.025, 0.065, 0.07, 0.58))
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.62, 0.78, 0.64, 0.88), 3.0, true)
		draw_circle(center, radius * 0.64, Color(0.35, 0.49, 0.39, 0.20))
		draw_circle(knob_position, radius * 0.48, Color(0.67, 0.82, 0.67, 0.94))
		draw_arc(knob_position, radius * 0.48, 0.0, TAU, 48, Color(0.93, 0.98, 0.86, 0.95), 2.0, true)

const MOVE_SPEED := 5.2
const MOVE_ACCEL := 17.0
const MOVE_DECEL := 22.0
const TURN_SPEED := 8.0
const CAMERA_DISTANCE := 5.2
const CAMERA_MIN_CLEARANCE := 2.2

var player: CharacterBody3D
var player_model: Node3D
var protagonist_animation_player: AnimationPlayer
var current_protagonist_animation := ""
var protagonist_tracks_ok := 0
var protagonist_tracks_total := 0
var protagonist_ignored_tracks := 0
var protagonist_first_track := ""
var protagonist_diagnostic_label: Label
var protagonist_model_status := "MODELO: NÃO TESTADO"
var player_arm_parts: Array[Node3D] = []
var player_leg_parts: Array[Node3D] = []
var camera: Camera3D
var creature: Node3D
var creature_tail: Node3D
var creature_leg_parts: Array[MeshInstance3D] = []
var creature_ear_parts: Array[MeshInstance3D] = []
var creature_crystal_parts: Array[Node3D] = []
var creature_home := Vector3(2.5, 0.72, -9.0)
var creature_captured := false
var captured_count := 0
var pedralume_count := 0
var creature_species := 0
var collection_label: Label
var creature_in_range := false
var look_yaw := 0.0
var target_look_yaw := 0.0
var look_pitch := 0.38
var target_look_pitch := 0.38
const CAMERA_SENSITIVITY := 0.0030
var nature_model_cache: Dictionary = {}
var status_label: Label
var variant_label: Label
var capture_button: Button
var movement_input := Vector2.ZERO
var movement_stick: AnalogStick
var foliage_sway_nodes: Array[Node3D] = []
var foliage_sway_base_rotations: Array[Vector3] = []
var foliage_sway_phases: Array[float] = []
var foliage_sway_strengths: Array[float] = []
var camera_drag_active := false
var camera_touch_index := -1
var started := false
var start_menu: Control
var wind_phase := 0.0
var day_time := 0.32
var sun_node: DirectionalLight3D
var weather_strength := 0.0

func _ready() -> void:
	# Etapa 2: inicia somente a interface leve; o mundo é criado após o toque.
	_build_start_menu()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var screen_size := get_viewport().get_visible_rect().size
		if event.pressed:
			# A câmera usa somente a área livre do lado direito, sem disputar
			# os botões de movimento e captura na parte inferior.
			var in_camera_area: bool = event.position.x > screen_size.x * 0.48
			in_camera_area = in_camera_area and event.position.y > screen_size.y * 0.16
			in_camera_area = in_camera_area and not (event.position.x > screen_size.x * 0.72 and event.position.y > screen_size.y * 0.78)
			if in_camera_area and camera_touch_index == -1:
				camera_touch_index = event.index
				camera_drag_active = true
		elif event.index == camera_touch_index:
			camera_touch_index = -1
			camera_drag_active = false
	elif event is InputEventScreenDrag and camera_drag_active and event.index == camera_touch_index:
		target_look_yaw -= event.relative.x * CAMERA_SENSITIVITY
		target_look_pitch = clampf(target_look_pitch + event.relative.y * CAMERA_SENSITIVITY, -0.38, 0.72)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var screen_size := get_viewport().get_visible_rect().size
		var in_camera_area: bool = event.position.x > screen_size.x * 0.48
		in_camera_area = in_camera_area and event.position.y > screen_size.y * 0.16
		in_camera_area = in_camera_area and not (event.position.x > screen_size.x * 0.72 and event.position.y > screen_size.y * 0.78)
		camera_drag_active = event.pressed and in_camera_area
	elif event is InputEventMouseMotion and camera_drag_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		target_look_yaw -= event.relative.x * CAMERA_SENSITIVITY
		target_look_pitch = clampf(target_look_pitch + event.relative.y * CAMERA_SENSITIVITY, -0.62, 0.88)

func _process(delta: float) -> void:
	if player == null:
		return
	wind_phase += delta * 0.55
	day_time = fmod(day_time + delta * 0.0008, 1.0)
	_update_day_cycle()
	if not started:
		return
	# Brisa suave em vegetação baixa; anima apenas raízes já instanciadas.
	var wind_time := Time.get_ticks_msec() * 0.001
	for foliage_index in range(foliage_sway_nodes.size()):
		var foliage := foliage_sway_nodes[foliage_index]
		if is_instance_valid(foliage):
			var phase := wind_time * 1.15 + foliage_sway_phases[foliage_index]
			var base_rotation: Vector3 = foliage_sway_base_rotations[foliage_index]
			var strength: float = foliage_sway_strengths[foliage_index]
			foliage.rotation.x = base_rotation.x + sin(phase) * strength
			foliage.rotation.z = base_rotation.z + cos(phase * 0.83) * strength * 0.72
	look_yaw = lerp_angle(look_yaw, target_look_yaw, minf(delta * 5.2, 1.0))
	look_pitch = lerpf(look_pitch, target_look_pitch, minf(delta * 7.0, 1.0))
	var target := player.global_position + Vector3(0, 1.25, 0)
	var horizontal := cos(look_pitch) * CAMERA_DISTANCE
	var cam_offset := Vector3(sin(look_yaw) * horizontal, sin(look_pitch) * CAMERA_DISTANCE, cos(look_yaw) * horizontal)
	var desired_camera_position := target + cam_offset
	# Câmera elevada: não deixa a própria encosta ficar entre a lente e o jogador.
	# O antigo raycast colocava a câmera 42 cm para dentro da superfície atingida.
	desired_camera_position.y = maxf(desired_camera_position.y, _terrain_height(desired_camera_position.x, desired_camera_position.z) + CAMERA_MIN_CLEARANCE)
	var camera_alpha := 1.0 - exp(-7.5 * delta)
	camera.global_position = camera.global_position.lerp(desired_camera_position, camera_alpha)
	# Colisão entre o alvo e a lente impede a câmera de atravessar encostas/árvores.
	var camera_query := PhysicsRayQueryParameters3D.create(target, camera.global_position)
	camera_query.collision_mask = 1
	camera_query.exclude = [player.get_rid()]
	var camera_hit := get_world_3d().direct_space_state.intersect_ray(camera_query)
	if not camera_hit.is_empty():
		camera.global_position = camera_hit.position + camera_hit.normal * 0.32
	var final_floor := _terrain_height(camera.global_position.x, camera.global_position.z) + CAMERA_MIN_CLEARANCE
	camera.global_position.y = maxf(camera.global_position.y, final_floor)
	camera.look_at(target, Vector3.UP)
	if creature and not creature_captured:
		creature.rotate_y(delta * 0.55)
		var creature_clock := Time.get_ticks_msec() * 0.00045
		creature.position = creature_home + Vector3(sin(creature_clock) * 0.55, sin(creature_clock * 4.0) * 0.10, cos(creature_clock * 0.8) * 0.32)
		if creature_tail:
			creature_tail.rotation.y = sin(creature_clock * 3.2) * 0.24
			creature_tail.rotation.x = cos(creature_clock * 2.4) * 0.10
		var creature_step := sin(creature_clock * 5.0) * 0.32
		for leg_index in range(creature_leg_parts.size()):
			var leg_target := creature_step * (1.0 if leg_index % 2 == 0 else -1.0)
			creature_leg_parts[leg_index].rotation.x = lerpf(creature_leg_parts[leg_index].rotation.x, leg_target, minf(delta * 5.0, 1.0))
		for ear_index in range(creature_ear_parts.size()):
			var ear_side := -1.0 if ear_index == 0 else 1.0
			var ear_idle := sin(creature_clock * 2.1 + float(ear_index) * 0.8) * 0.055
			creature_ear_parts[ear_index].rotation.z = ear_side * -0.20 + ear_idle
		for crystal_index in range(creature_crystal_parts.size()):
			var crystal_pulse := 1.0 + sin(creature_clock * 3.0 + float(crystal_index) * 0.9) * 0.055
			creature_crystal_parts[crystal_index].scale = Vector3(1.0, crystal_pulse, 1.0)
		var now_in_range := player.global_position.distance_to(creature.global_position) < 3.0
		if now_in_range != creature_in_range:
			creature_in_range = now_in_range
			if creature_in_range:
				_update_status("Uma criatura selvagem apareceu! Toque em CAPTURAR.")
			else:
				_update_status("Explore o vale e encontre uma criatura!")

func _physics_process(delta: float) -> void:
	if player == null or not started:
		return
	var input_dir := movement_input
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	# Movimento relativo à câmera: cima no analógico sempre significa ir para frente.
	var forward := Vector3(-sin(look_yaw), 0.0, -cos(look_yaw)).normalized()
	var right := Vector3(cos(look_yaw), 0.0, -sin(look_yaw)).normalized()
	var direction := (right * input_dir.x - forward * input_dir.y).normalized()
	if player.is_on_floor() and direction.length_squared() > 0.001:
		direction = direction.slide(player.get_floor_normal()).normalized()
	var target_velocity := direction * MOVE_SPEED
	var horizontal_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var accel := MOVE_ACCEL if direction.length() > 0.08 else MOVE_DECEL
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, accel * delta)
	player.velocity.x = horizontal_velocity.x
	player.velocity.z = horizontal_velocity.z
	if not player.is_on_floor():
		player.velocity.y -= 18.0 * delta
	else:
		player.velocity.y = minf(player.velocity.y, 0.0)
	player.floor_snap_length = 0.9
	player.move_and_slide()
	var bounded_position := player.global_position
	bounded_position.x = clampf(bounded_position.x, -64.0, 64.0)
	bounded_position.z = clampf(bounded_position.z, -64.0, 64.0)
	if bounded_position != player.global_position:
		player.global_position = bounded_position
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	# Recuperação defensiva: nunca deixa a câmera acompanhar o jogador sob o mapa.
	var floor_height := _terrain_height(player.global_position.x, player.global_position.z)
	if player.global_position.y < floor_height - 0.85 or player.global_position.y < -2.0:
		player.global_position = Vector3(player.global_position.x, floor_height + 0.08, player.global_position.z)
		player.velocity = Vector3.ZERO
	_update_protagonist_animation(horizontal_velocity.length(), delta)
	if direction.length() > 0.1:
		player.rotation.y = lerp_angle(player.rotation.y, atan2(direction.x, direction.z) + PI, 1.0 - exp(-TURN_SPEED * delta))

func _build_world() -> void:
	# Etapa 1: mundo simplificado e confiável para Android.
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.68, 0.82, 0.96)
	sky_mat.ground_bottom_color = Color(0.22, 0.30, 0.22)
	sky_mat.ground_horizon_color = Color(0.48, 0.60, 0.42)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 24.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun_node = sun
	add_child(sun)

	# Plano único de 400 x 400 m: sem Terrain3D, relevo, patches ou triângulos extras.
	var ground := MeshInstance3D.new()
	ground.name = "StableGrassPlane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_texture = ImageTexture.create_from_image(_make_terrain_albedo(false))
	grass.albedo_color = Color(0.82, 0.90, 0.76)
	grass.roughness = 1.0
	grass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Repetição UV: evita que uma textura minúscula fique esticada sobre 400 m.
	grass.uv1_scale = Vector3(48.0, 48.0, 1.0)
	ground.material_override = grass
	add_child(ground)

	var ground_body := StaticBody3D.new()
	ground_body.name = "GroundCollision"
	var ground_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 0.2, 400.0)
	ground_shape.shape = shape
	ground_shape.position.y = -0.1
	ground_body.add_child(ground_shape)
	add_child(ground_body)

func _build_biome_ground_cover(rng: RandomNumberGenerator) -> void:
	# Sub-bosque em manchas: vegetação baixa acompanha as copas, sem cobrir tudo.
	var forest_centers := [Vector2(-31.0, -29.0), Vector2(31.0, -29.0), Vector2(-34.0, 34.0), Vector2(34.0, 34.0)]
	for center_index in range(forest_centers.size()):
		var center: Vector2 = forest_centers[center_index]
		for i in range(7):
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * 11.0
			var px := center.x + cos(angle) * radius
			var pz := center.y + sin(angle) * radius * 0.78
			if absf(px) < 10.0 and pz < 12.0 and pz > -31.0:
				continue
			var pos := Vector3(px, _terrain_height(px, pz), pz)
			if i % 3 == 0:
				_add_fern(pos, 900 + center_index * 19 + i)
			else:
				_add_plant(pos, 940 + center_index * 19 + i)
			if i % 2 == 0:
				_add_grass_tuft(pos + Vector3(0.55, 0.0, -0.25), 1020 + center_index * 19 + i)

	# Flores em pequenos agrupamentos nas clareiras, deixando o centro mais aberto.
	var flower_centers := [Vector2(-37.0, 8.0), Vector2(35.0, 28.0)]
	for center_index in range(flower_centers.size()):
		var center: Vector2 = flower_centers[center_index]
		for i in range(14):
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(3.0, 8.0)
			var px := center.x + cos(angle) * radius
			var pz := center.y + sin(angle) * radius * 0.68
			_add_meadow_flower(Vector3(px, _terrain_height(px, pz), pz), 1100 + center_index * 17 + i)

	# Vegetação mais rala nas bordas dos afloramentos, com rocha exposta dominante.
	var rocky_centers := [Vector2(48.0, 4.0), Vector2(-48.0, -5.0), Vector2(8.0, 49.0)]
	for center_index in range(rocky_centers.size()):
		var center: Vector2 = rocky_centers[center_index]
		for i in range(7):
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(7.0, 11.0)
			var px := center.x + cos(angle) * radius
			var pz := center.y + sin(angle) * radius * 0.8
			_add_grass_tuft(Vector3(px, _terrain_height(px, pz), pz), 1200 + center_index * 11 + i)

func _build_biome_floor_patches() -> void:
	# Camadas discretas de chão ajudam a separar visualmente os biomas.
	# As malhas seguem o relevo e têm bordas orgânicas, sem círculos perfeitos.
	var forest_centers := [Vector2(-31.0, -29.0), Vector2(31.0, -29.0), Vector2(-34.0, 34.0), Vector2(34.0, 34.0)]
	for i in range(forest_centers.size()):
		_add_biome_floor_patch(forest_centers[i], 11.5, 9.0, Color(0.23, 0.29, 0.15), 210 + i)
	var meadow_centers := [Vector2(-37.0, 8.0), Vector2(35.0, 28.0)]
	for i in range(meadow_centers.size()):
		_add_biome_floor_patch(meadow_centers[i], 8.6, 6.4, Color(0.31, 0.39, 0.17), 230 + i)
	var rocky_centers := [Vector2(48.0, 4.0), Vector2(-48.0, -5.0), Vector2(8.0, 49.0)]
	for i in range(rocky_centers.size()):
		_add_biome_floor_patch(rocky_centers[i], 7.2, 5.8, Color(0.34, 0.33, 0.28), 250 + i)

func _add_biome_floor_patch(center: Vector2, radius_x: float, radius_z: float, base_color: Color, seed: int) -> void:
	# Cinco faixas concêntricas irregulares fazem a cor do bioma desaparecer
	# gradualmente no gramado, evitando bordas circulares e manchas abruptas.
	var segments := 40
	var ring_count := 5
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass_color := Color(0.27, 0.37, 0.19)
	var center_pos := Vector3(center.x, _terrain_height(center.x, center.y) + 0.065, center.y)
	var center_color := base_color.lerp(grass_color, 0.04)
	for i in range(segments):
		var angle_a := TAU * float(i) / float(segments)
		var angle_b := TAU * float(i + 1) / float(segments)
		var wave_a := 1.0 + sin(angle_a * 3.0 + float(seed)) * 0.105 + cos(angle_a * 5.0 - float(seed)) * 0.055
		var wave_b := 1.0 + sin(angle_b * 3.0 + float(seed)) * 0.105 + cos(angle_b * 5.0 - float(seed)) * 0.055
		var outer_a := Vector3(center.x + cos(angle_a) * radius_x * wave_a, 0.0, center.y + sin(angle_a) * radius_z * wave_a)
		var outer_b := Vector3(center.x + cos(angle_b) * radius_x * wave_b, 0.0, center.y + sin(angle_b) * radius_z * wave_b)
		outer_a.y = _terrain_height(outer_a.x, outer_a.z) + 0.065
		outer_b.y = _terrain_height(outer_b.x, outer_b.z) + 0.065
		var variation_a := 0.07 + absf(sin(angle_a * 4.0 + float(seed))) * 0.12
		var variation_b := 0.07 + absf(sin(angle_b * 4.0 + float(seed))) * 0.12
		var edge_color_a := base_color.lerp(Color(0.52, 0.48, 0.34), variation_a)
		var edge_color_b := base_color.lerp(Color(0.52, 0.48, 0.34), variation_b)
		for band in range(ring_count):
			var inner_ratio := float(band) / float(ring_count)
			var outer_ratio := float(band + 1) / float(ring_count)
			var inner_a := center_pos.lerp(outer_a, inner_ratio)
			var inner_b := center_pos.lerp(outer_b, inner_ratio)
			var band_outer_a := center_pos.lerp(outer_a, outer_ratio)
			var band_outer_b := center_pos.lerp(outer_b, outer_ratio)
			inner_a.y = _terrain_height(inner_a.x, inner_a.z) + 0.065
			inner_b.y = _terrain_height(inner_b.x, inner_b.z) + 0.065
			var inner_blend := clampf((inner_ratio - 0.38) / 0.62, 0.0, 1.0)
			var outer_blend := clampf((outer_ratio - 0.38) / 0.62, 0.0, 1.0)
			inner_blend = inner_blend * inner_blend * (3.0 - 2.0 * inner_blend)
			outer_blend = outer_blend * outer_blend * (3.0 - 2.0 * outer_blend)
			var color_inner_a := base_color.lerp(grass_color, inner_blend).lerp(edge_color_a, variation_a * 0.45)
			var color_inner_b := base_color.lerp(grass_color, inner_blend).lerp(edge_color_b, variation_b * 0.45)
			var color_outer_a := base_color.lerp(grass_color, outer_blend).lerp(edge_color_a, variation_a * 0.45)
			var color_outer_b := base_color.lerp(grass_color, outer_blend).lerp(edge_color_b, variation_b * 0.45)
			# Dois triângulos por faixa, com a face voltada para cima.
			surface.set_color(color_inner_a)
			surface.add_vertex(inner_a)
			surface.set_color(color_outer_b)
			surface.add_vertex(band_outer_b)
			surface.set_color(color_outer_a)
			surface.add_vertex(band_outer_a)
			surface.set_color(color_inner_a)
			surface.add_vertex(inner_a)
			surface.set_color(color_inner_b)
			surface.add_vertex(inner_b)
			surface.set_color(color_outer_b)
			surface.add_vertex(band_outer_b)
	surface.generate_normals()
	var patch := MeshInstance3D.new()
	patch.mesh = surface.commit()
	var patch_material := StandardMaterial3D.new()
	patch_material.vertex_color_use_as_albedo = true
	patch_material.roughness = 1.0
	patch_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	patch.material_override = patch_material
	add_child(patch)

func _add_meadow_flower(pos: Vector3, seed: int) -> void:
	var flower_scene := _get_nature_scene(["Flower_3_Group", "Clover_1"], seed)
	if flower_scene:
		var flowers := flower_scene.instantiate() as Node3D
		add_child(flowers)
		flowers.position = pos
		var scale_factor := 0.34 + float(seed % 4) * 0.08
		flowers.scale = Vector3.ONE * scale_factor
		flowers.rotation.y = float(seed * 47 % 360) * PI / 180.0
		_register_foliage_sway(flowers, seed, 0.055)
		return
	_add_plant(pos, seed)

func _build_biome_details(rng: RandomNumberGenerator) -> void:
	# Afloramentos rochosos assimétricos, com pedras de tamanhos variados.
	var outcrop_centers := [Vector2(48.0, 4.0), Vector2(-48.0, -5.0), Vector2(8.0, 49.0)]
	for center_index in range(outcrop_centers.size()):
		var center: Vector2 = outcrop_centers[center_index]
		for i in range(7):
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(1.5, 8.5)
			var px := center.x + cos(angle) * radius * rng.randf_range(0.65, 1.25)
			var pz := center.y + sin(angle) * radius
			_add_rock(Vector3(px, _terrain_height(px, pz), pz), 180 + center_index * 17 + i)

	# Paredões baixos de rocha nas bordas do vale, usando os modelos de penhasco CC0.
	var cliff_points := [
		[Vector2(57.0, 13.0), 0.92, 0.35],
		[Vector2(-58.0, -12.0), 0.82, 1.10],
		[Vector2(18.0, 57.0), 0.88, 2.05],
		[Vector2(-19.0, -58.0), 0.76, 2.70]
	]
	for i in range(cliff_points.size()):
		var cliff_data: Array = cliff_points[i]
		var cliff_pos: Vector2 = cliff_data[0]
		_add_cliff(
			Vector3(cliff_pos.x, _terrain_height(cliff_pos.x, cliff_pos.y) - 0.12, cliff_pos.y),
			float(cliff_data[1]), float(cliff_data[2]), 760 + i
		)

	# Clareiras floridas com bordas irregulares e vegetação baixa.
	var meadow_centers := [Vector2(-37.0, 8.0), Vector2(35.0, 28.0)]
	for center_index in range(meadow_centers.size()):
		var center: Vector2 = meadow_centers[center_index]
		for i in range(5):
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * 10.0
			var px := center.x + cos(angle) * radius
			var pz := center.y + sin(angle) * radius * 0.72
			_add_plant(Vector3(px, _terrain_height(px, pz), pz), 240 + center_index * 23 + i)
			if i % 2 == 0:
				_add_grass_tuft(Vector3(px + 0.45, _terrain_height(px + 0.45, pz), pz), 300 + i)

	# Moitas de samambaias em baixadas úmidas, com distribuição em pequenos grupos.
	var fern_centers := [Vector2(-25.0, -22.0), Vector2(26.0, -18.0), Vector2(-5.0, 43.0)]
	for center_index in range(fern_centers.size()):
		var center: Vector2 = fern_centers[center_index]
		for i in range(10):
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * 7.0
			var px := center.x + cos(angle) * radius * 1.25
			var pz := center.y + sin(angle) * radius * 0.72
			_add_fern(Vector3(px, _terrain_height(px, pz), pz), 520 + center_index * 13 + i)

	# Faixas de cascalho acompanham as cristas, em vez de formar círculos perfeitos.
	for ridge_index in range(2):
		for i in range(12):
			var t := float(i) / 11.0
			var px := -54.0 + t * 108.0
			var ridge_base_z := 20.0 if ridge_index == 0 else -43.0
			var pz := ridge_base_z + sin(t * TAU * 1.4 + ridge_index) * 5.5
			px += rng.randf_range(-2.0, 2.0)
			pz += rng.randf_range(-2.5, 2.5)
			_add_rock(Vector3(px, _terrain_height(px, pz), pz), 580 + ridge_index * 19 + i)

	# Madeira caída e galhos quebrados dão escala e quebram a repetição das árvores.
	var fallen_logs := [
		[Vector2(-52.0, -27.0), Vector2(-46.0, -24.5), 0.19],
		[Vector2(39.0, -48.0), Vector2(45.0, -43.5), 0.22],
		[Vector2(-43.0, 47.0), Vector2(-37.0, 43.5), 0.17],
		[Vector2(48.0, 31.0), Vector2(53.0, 27.0), 0.20],
		[Vector2(-8.0, -51.0), Vector2(-2.0, -48.0), 0.16]
	]
	for i in range(fallen_logs.size()):
		var log_data: Array = fallen_logs[i]
		var start: Vector2 = log_data[0]
		var finish: Vector2 = log_data[1]
		_add_fallen_log(
			Vector3(start.x, _terrain_height(start.x, start.y), start.y),
			Vector3(finish.x, _terrain_height(finish.x, finish.y), finish.y),
			float(log_data[2]), 700 + i
		)

func _add_cliff(pos: Vector3, scale_factor: float, yaw: float, seed: int) -> void:
	var cliff_scene := _get_nature_scene(["Cliff001", "Cliff002"], seed)
	if cliff_scene:
		var cliff := cliff_scene.instantiate() as Node3D
		add_child(cliff)
		cliff.position = pos
		cliff.scale = Vector3(scale_factor * 1.15, scale_factor, scale_factor * 0.82)
		cliff.rotation.y = yaw
		return
	# Alternativa facetada caso os modelos externos não estejam disponíveis.
	_add_rock(pos, seed)

func _add_fern(pos: Vector3, seed: int) -> void:
	var fern_scene := _get_nature_scene(["Fern_1", "Bush_Common", "Bush001"], seed)
	if fern_scene:
		var fern := fern_scene.instantiate() as Node3D
		add_child(fern)
		fern.position = pos
		var scale_factor := 0.42 + float(seed % 5) * 0.09
		fern.scale = Vector3.ONE * scale_factor
		fern.rotation.y = float(seed * 43 % 360) * PI / 180.0
		_register_foliage_sway(fern, seed, 0.065)
		return
	_add_plant(pos, seed)

func _add_fallen_log(start: Vector3, finish: Vector3, radius: float, seed: int) -> void:
	var direction := finish - start
	var midpoint := (start + finish) * 0.5
	var log := MeshInstance3D.new()
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = radius * 0.78
	log_mesh.bottom_radius = radius
	log_mesh.height = direction.length()
	log_mesh.radial_segments = 6
	log_mesh.rings = 1
	log.mesh = log_mesh
	log.position = midpoint + Vector3(0.0, radius * 0.58, 0.0)
	log.quaternion = Quaternion(Vector3.UP, direction.normalized())
	log.material_override = _mat(Color(0.25, 0.16, 0.085) if seed % 2 == 0 else Color(0.34, 0.22, 0.11))
	add_child(log)

	# Um galho curto e anguloso em parte dos troncos, sem criar excesso de polígonos.
	if seed % 2 == 0:
		var branch := MeshInstance3D.new()
		var branch_mesh := CylinderMesh.new()
		branch_mesh.top_radius = 0.018
		branch_mesh.bottom_radius = radius * 0.42
		branch_mesh.height = 0.72
		branch_mesh.radial_segments = 5
		branch_mesh.rings = 1
		branch.mesh = branch_mesh
		branch.position = midpoint + Vector3(0.0, radius * 0.72, 0.0) + direction.normalized() * 0.18
		branch.rotation = Vector3(0.0, 0.0, -0.82)
		branch.material_override = log.material_override
		add_child(branch)

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
	# Cordilheira baixa facetada no horizonte, com picos assimétricos conectados.
	# Uma única malha mantém o custo de desenho reduzido no Android.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var palette := [
		Color(0.30, 0.43, 0.40),
		Color(0.35, 0.48, 0.44),
		Color(0.40, 0.51, 0.46),
		Color(0.27, 0.39, 0.38)
	]
	for i in range(16):
		var angle := TAU * float(i) / 16.0
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		var center := radial * 70.0
		var half_width := 7.0 + float(i % 4) * 1.8
		var base_left := center - tangent * half_width
		var base_right := center + tangent * half_width
		var peak_height := 8.0 + float((i * 7) % 6) * 1.7
		var peak := center + radial * (3.0 + float(i % 3) * 2.0) + Vector3(0.0, peak_height, 0.0)
		var shoulder := center + radial * 2.0 + Vector3(0.0, peak_height * 0.42, 0.0)
		var color_a: Color = palette[i % palette.size()]
		var color_b: Color = palette[(i + 1) % palette.size()]
		# Face esquerda e direita formam uma silhueta quebrada, não cones repetidos.
		surface.set_color(color_a)
		surface.add_vertex(base_left)
		surface.set_color(color_b)
		surface.add_vertex(peak)
		surface.set_color(color_a.darkened(0.12))
		surface.add_vertex(shoulder)
		surface.set_color(color_a.darkened(0.08))
		surface.add_vertex(shoulder)
		surface.set_color(color_b.lightened(0.05))
		surface.add_vertex(peak)
		surface.set_color(color_b.darkened(0.18))
		surface.add_vertex(base_right)
	surface.generate_normals()
	var ridge := MeshInstance3D.new()
	ridge.name = "DistantMountainRange"
	ridge.mesh = surface.commit()
	var ridge_material := StandardMaterial3D.new()
	ridge_material.vertex_color_use_as_albedo = true
	ridge_material.roughness = 1.0
	ridge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ridge.material_override = ridge_material
	add_child(ridge)

func _waterline_radius(angle: float) -> float:
	return 1.0 + sin(angle * 2.0 + 0.45) * 0.075 + cos(angle * 3.0 - 0.8) * 0.045 + sin(angle * 5.0 + 1.7) * 0.025

func _make_irregular_water_mesh(radius: float, segments: int, y_offset: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(-17.0, _terrain_height(-17.0, -12.0) + y_offset, -12.0)
	for i in range(segments):
		var angle_a := TAU * float(i) / float(segments)
		var angle_b := TAU * float(i + 1) / float(segments)
		var point_a := center + Vector3(cos(angle_a) * radius * _waterline_radius(angle_a), 0.0, sin(angle_a) * radius * _waterline_radius(angle_a))
		var point_b := center + Vector3(cos(angle_b) * radius * _waterline_radius(angle_b), 0.0, sin(angle_b) * radius * _waterline_radius(angle_b))
		# Ordem dos vértices voltada para cima.
		surface.add_vertex(center)
		surface.add_vertex(point_b)
		surface.add_vertex(point_a)
	surface.generate_normals()
	return surface.commit()

func _make_irregular_shore_mesh(inner_radius: float, outer_radius: float, segments: int, y_offset: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(-17.0, _terrain_height(-17.0, -12.0) + y_offset, -12.0)
	for i in range(segments):
		var angle_a := TAU * float(i) / float(segments)
		var angle_b := TAU * float(i + 1) / float(segments)
		var inner_a := center + Vector3(cos(angle_a) * inner_radius * _waterline_radius(angle_a), 0.0, sin(angle_a) * inner_radius * _waterline_radius(angle_a))
		var inner_b := center + Vector3(cos(angle_b) * inner_radius * _waterline_radius(angle_b), 0.0, sin(angle_b) * inner_radius * _waterline_radius(angle_b))
		var outer_a := center + Vector3(cos(angle_a) * outer_radius * _waterline_radius(angle_a), 0.0, sin(angle_a) * outer_radius * _waterline_radius(angle_a))
		var outer_b := center + Vector3(cos(angle_b) * outer_radius * _waterline_radius(angle_b), 0.0, sin(angle_b) * outer_radius * _waterline_radius(angle_b))
		surface.add_vertex(outer_a)
		surface.add_vertex(inner_a)
		surface.add_vertex(outer_b)
		surface.add_vertex(outer_b)
		surface.add_vertex(inner_a)
		surface.add_vertex(inner_b)
	surface.generate_normals()
	return surface.commit()

func _build_waterhole() -> void:
	# Margem e lâmina d'água são malhas poligonais irregulares, sem cilindros.
	var shore := MeshInstance3D.new()
	shore.mesh = _make_irregular_shore_mesh(3.72, 5.15, 40, 0.045)
	shore.material_override = _mat(Color(0.49, 0.40, 0.27))
	add_child(shore)

	var water := MeshInstance3D.new()
	water.mesh = _make_irregular_water_mesh(3.82, 40, 0.105)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.12, 0.39, 0.49, 0.92)
	water_mat.roughness = 0.28
	water_mat.metallic = 0.025
	water_mat.disable_receive_shadows = true
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	water.material_override = water_mat
	add_child(water)

	# Pedras em grupos assimétricos, concentradas em trechos da margem.
	var rock_angles := [0.12, 0.39, 0.57, 1.42, 1.68, 2.73, 3.02, 3.31, 4.18, 4.52, 5.31, 5.72]
	for i in range(rock_angles.size()):
		var angle: float = rock_angles[i]
		var radius := 4.45 + float((i * 7) % 5) * 0.19
		var rock_x := -17.0 + cos(angle) * radius * _waterline_radius(angle)
		var rock_z := -12.0 + sin(angle) * radius * _waterline_radius(angle)
		_add_rock(Vector3(rock_x, _terrain_height(rock_x, rock_z), rock_z), i + 90)

	# Juncos em três manchas úmidas, sem formar um anel artificial.
	var reed_angles := [0.72, 0.91, 1.08, 2.12, 2.31, 2.48, 4.82, 5.02, 5.19]
	for i in range(reed_angles.size()):
		var angle: float = reed_angles[i]
		var radius := 4.18 + float(i % 3) * 0.20
		var reed_x := -17.0 + cos(angle) * radius * _waterline_radius(angle)
		var reed_z := -12.0 + sin(angle) * radius * _waterline_radius(angle)
		_add_reed(Vector3(reed_x, _terrain_height(reed_x, reed_z) + 0.03, reed_z), 410 + i)

func _build_terrain() -> void:
	# O terreno principal agora é gerado pelo Terrain3D (GDExtension),
	# usando uma região real 256x256 com heightmap de 32 bits.
	if not ClassDB.class_exists("Terrain3D"):
		push_error("Terrain3D GDExtension não foi carregada; não é seguro exportar.")
		return

	var terrain = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	terrain.set("region_size", 256)
	terrain.set("vertex_spacing", 1.0)
	terrain.position = Vector3(-128.0, 0.0, -128.0)
	var terrain_data_path := "user://wildmon_terrain"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(terrain_data_path))
	terrain.set("data_directory", terrain_data_path)
	add_child(terrain)

	var data = terrain.get("data")
	if data == null:
		push_error("Terrain3D não inicializou Terrain3DData.")
		return

	var region = data.add_region_blank(Vector2i.ZERO, false)
	if region == null:
		push_error("Terrain3D não conseguiu criar a região principal.")
		return

	var height_map := Image.create(256, 256, false, Image.FORMAT_RF)
	var control_map := Image.create(256, 256, false, Image.FORMAT_RF)
	var color_map := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for z in range(256):
		for x in range(256):
			var world_x := float(x) - 128.0
			var world_z := float(z) - 128.0
			height_map.set_pixel(x, z, Color(_terrain_height(world_x, world_z), 0.0, 0.0, 1.0))
			control_map.set_pixel(x, z, Color(0.0, 0.0, 0.0, 0.0))
			color_map.set_pixel(x, z, Color.WHITE)
	region.set_map(0, height_map)
	region.set_map(1, control_map)
	region.set_map(2, color_map)
	region.calc_height_range()
	data.calc_height_range()
	data.update_maps()

	# Texturas tileáveis geradas para o Terrain3D: grama de altitude e rocha.
	var assets = ClassDB.instantiate("Terrain3DAssets")
	var grass_asset = ClassDB.instantiate("Terrain3DTextureAsset")
	grass_asset.set("name", "Grama alpina")
	grass_asset.set("albedo_texture", ImageTexture.create_from_image(_make_terrain_albedo(false)))
	grass_asset.set("uv_scale", 0.18)
	var rock_asset = ClassDB.instantiate("Terrain3DTextureAsset")
	rock_asset.set("name", "Rocha exposta")
	rock_asset.set("albedo_texture", ImageTexture.create_from_image(_make_terrain_albedo(true)))
	rock_asset.set("uv_scale", 0.12)
	assets.set("texture_list", [grass_asset, rock_asset])
	terrain.set("assets", assets)

	var terrain_material = ClassDB.instantiate("Terrain3DMaterial")
	terrain_material.set("auto_shader", true)
	terrain_material.set("dual_scaling", false)
	terrain_material.set("max_regions", 64)
	terrain.set("material", terrain_material)
	terrain.set("collision_mask", 1)
	terrain.set("mesh_lods", 4)
	terrain.set("mesh_size", 16)
	terrain.set("cast_shadows", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	print("WILDMON_TERRAIN3D_READY regions=", data.get_region_count(), " height_range=", data.get_height_range())

func _make_terrain_albedo(rock: bool) -> Image:
	# Textura procedural de grama em tile: variação macro, micro e pequenas fibras.
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var broad := FastNoiseLite.new()
	broad.seed = 418
	broad.frequency = 0.035
	var detail := FastNoiseLite.new()
	detail.seed = 733
	detail.frequency = 0.19
	var grain := FastNoiseLite.new()
	grain.seed = 991
	grain.frequency = 0.62
	for y in range(256):
		for x in range(256):
			var n1 := broad.get_noise_2d(float(x), float(y))
			var n2 := detail.get_noise_2d(float(x), float(y))
			var n3 := grain.get_noise_2d(float(x), float(y))
			var fleck := sin(float(x) * 1.7 + n2 * 8.0) * cos(float(y) * 1.3 + n3 * 7.0) * 0.035
			var value := clampf(0.5 + n1 * 0.25 + n2 * 0.18 + n3 * 0.09 + fleck, 0.0, 1.0)
			var dark := Color(0.105, 0.23, 0.075)
			var light := Color(0.34, 0.47, 0.20)
			var color := dark.lerp(light, value)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
	image.generate_mipmaps()
	return image

func _terrain_normal(x: float, z: float) -> Vector3:
	# Normal calculada pelo gradiente do relevo; evita depender da orientação
	# implícita do SurfaceTool em triângulos com vértices duplicados.
	var epsilon := 0.25
	var slope_x := (_terrain_height(x + epsilon, z) - _terrain_height(x - epsilon, z)) / (2.0 * epsilon)
	var slope_z := (_terrain_height(x, z + epsilon) - _terrain_height(x, z - epsilon)) / (2.0 * epsilon)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()

func _terrain_vertex_color(x: float, z: float, height: float, noise: FastNoiseLite) -> Color:
	var variation := noise.get_noise_2d(x, z) * 0.095 + sin(x * 0.21 + z * 0.16) * 0.025
	var lowland := Color(0.25, 0.37, 0.19)
	var hillside := Color(0.34, 0.43, 0.25)
	var alpine_grass := Color(0.39, 0.43, 0.30)
	var rocky := Color(0.48, 0.46, 0.40)
	var exposed_stone := Color(0.57, 0.55, 0.49)
	var color := lowland.lerp(hillside, smoothstep(-0.2, 3.2, height))
	color = color.lerp(alpine_grass, smoothstep(3.0, 6.0, height) * 0.62)
	color = color.lerp(rocky, smoothstep(6.0, 9.0, height) * 0.68)
	color = color.lerp(exposed_stone, smoothstep(9.0, 13.0, height) * 0.55)
	color += Color(variation, variation, variation * 0.78, 0.0)
	return color

func _terrain_height(x: float, z: float) -> float:
	# Terreno completamente plano na base da Etapa 1.
	return 0.0

func _add_reed(pos: Vector3, seed: int) -> void:
	var reed_scene := _get_nature_scene(["Reed001", "Reed002"], seed)
	if reed_scene:
		var reeds := reed_scene.instantiate() as Node3D
		add_child(reeds)
		reeds.position = pos
		var scale_factor := 0.48 + float(seed % 4) * 0.10
		reeds.scale = Vector3.ONE * scale_factor
		reeds.rotation.y = float(seed * 31 % 360) * PI / 180.0
		return
	for blade in range(3):
		_add_box(self, pos + Vector3((float(blade) - 1.0) * 0.10, 0.38, 0.0), Vector3(0.045, 0.76, 0.045), Color(0.25, 0.39, 0.17), false)

func _add_rock(pos: Vector3, seed: int) -> void:
	var rock_scene := _get_nature_scene(["Rock_Medium_1", "Rock_Medium_2", "Rock001", "Rock002", "Rock003"], seed)
	if rock_scene:
		var rock := rock_scene.instantiate() as Node3D
		add_child(rock)
		rock.position = pos
		rock.scale = Vector3.ONE * (0.48 + float(seed % 5) * 0.075)
		rock.rotation.y = float(seed * 37 % 360) * PI / 180.0
		return
	# Fallback usado apenas se a transferência dos modelos não estiver disponível.
	var rock := MeshInstance3D.new()
	var rock_mesh := PrismMesh.new()
	rock_mesh.size = Vector3(0.78, 0.52, 0.66)
	rock.mesh = rock_mesh
	rock.position = pos + Vector3(0, 0.18, 0)
	rock.rotation.y = float(seed * 31 % 360) * PI / 180.0
	rock.scale = Vector3(0.82, 0.72, 0.86)
	rock.material_override = _mat(Color(0.39, 0.42, 0.39))
	add_child(rock)

func _add_grass_tuft(pos: Vector3, seed: int) -> void:
	var grass_scene := _get_nature_scene(["Grass_Common_Tall", "Clover_1", "Grass001", "Grass002"], seed)
	if grass_scene:
		var grass := grass_scene.instantiate() as Node3D
		_disable_scene_shadows(grass)
		add_child(grass)
		_set_scene_visibility_range(grass, 42.0)
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
	var tree_scene := _get_nature_scene(["CommonTree_1", "CommonTree_2", "CommonTree_3", "Pine_1", "Pine_2", "TreeHigh001", "TreeHigh002", "TreeHigh003"], seed)
	if tree_scene:
		var tree := tree_scene.instantiate() as Node3D
		_disable_scene_shadows(tree)
		add_child(tree)
		_set_scene_visibility_range(tree, 108.0)
		tree.position = pos
		var scale_factor := 0.88 + float(seed % 5) * 0.12
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
		var paths := [
			"res://assets/nature/" + model_name + ".gltf",
			"res://assets/gobkit/" + model_name + ".glb"
		]
		var loaded: PackedScene = null
		for path in paths:
			if ResourceLoader.exists(path):
				loaded = load(path) as PackedScene
				if loaded:
					break
		nature_model_cache[model_name] = loaded
	return nature_model_cache[model_name] as PackedScene

func _set_scene_visibility_range(root: Node, range_end: float) -> void:
	# Distância de desenho reduz trabalho de GPU em vegetação distante.
	# Aplicado recursivamente para alcançar as malhas dentro dos modelos importados.
	if root is GeometryInstance3D:
		var visual := root as GeometryInstance3D
		visual.visibility_range_end = range_end
	for child in root.get_children():
		_set_scene_visibility_range(child, range_end)

func _disable_scene_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_scene_shadows(child)

func _register_foliage_sway(foliage: Node3D, seed: int, strength: float) -> void:
	# Vento procedural de baixa frequência: só objetos já instanciados, sem partículas.
	if foliage_sway_nodes.size() >= 96:
		return
	foliage_sway_nodes.append(foliage)
	foliage_sway_base_rotations.append(foliage.rotation)
	foliage_sway_phases.append(float(seed % 97) * 0.173)
	foliage_sway_strengths.append(strength)

func _add_plant(pos: Vector3, seed: int) -> void:
	var plant_scene := _get_nature_scene(["Fern_1", "Bush_Common", "Clover_1", "Flower_3_Group", "Bush001", "Bush002", "Reed001", "Reed002"], seed)
	if plant_scene:
		var plant := plant_scene.instantiate() as Node3D
		_disable_scene_shadows(plant)
		add_child(plant)
		_set_scene_visibility_range(plant, 58.0)
		plant.position = pos
		var scale_factor := 0.42 + float(seed % 5) * 0.11
		plant.scale = Vector3.ONE * scale_factor
		plant.rotation.y = float(seed * 41 % 360) * PI / 180.0
		_register_foliage_sway(plant, seed, 0.045)
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

func _snap_player_to_terrain() -> void:
	# Aguarda a GDExtension concluir a geração da colisão antes de posicionar o jogador.
	var hit: Dictionary = {}
	for attempt in range(8):
		await get_tree().physics_frame
		var origin := Vector3(player.global_position.x, 80.0, player.global_position.z)
		var destination := Vector3(player.global_position.x, -30.0, player.global_position.z)
		var query := PhysicsRayQueryParameters3D.create(origin, destination)
		query.collision_mask = 1
		hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			break
	# Fallback determinístico pelo mesmo heightmap que alimenta o Terrain3D.
	var floor_y := _terrain_height(player.global_position.x, player.global_position.z)
	if not hit.is_empty():
		floor_y = float(hit.position.y)
	player.global_position = Vector3(player.global_position.x, floor_y + 0.14, player.global_position.z)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if camera:
		camera.global_position = player.global_position + Vector3(0.0, 3.0, 7.0)
		camera.look_at(player.global_position + Vector3(0.0, 1.2, 0.0))

func _build_player() -> void:
	var model_path := "res://assets/characters/Superhero_Male_FullBody.gltf"
	if not ResourceLoader.exists(model_path):
		protagonist_model_status = "MODELO: FALLBACK (arquivo ausente no APK: ResourceLoader.exists)"
		print("FALLBACK ANTIGO: arquivo ausente no APK (ResourceLoader.exists)")
		_build_player_fallback()
		return
	var model_scene := load(model_path) as PackedScene
	if model_scene == null:
		protagonist_model_status = "MODELO: FALLBACK (load() retornou nulo)"
		print("FALLBACK ANTIGO: load() retornou nulo")
		_build_player_fallback()
		return
	var model_instance := model_scene.instantiate() as Node3D
	if model_instance == null:
		protagonist_model_status = "MODELO: FALLBACK (instantiate() falhou)"
		print("FALLBACK ANTIGO: instantiate() falhou")
		_build_player_fallback()
		return
	protagonist_model_status = "MODELO: NOVO"
	print("MODELO NOVO CARREGADO")
	# Instancia explicitamente o protagonista GLTF; nenhum modelo procedural e criado nesse caminho.
	player = CharacterBody3D.new()
	player.position = Vector3(-4.0, _terrain_height(-4.0, -42.0) + 0.12, -42.0)
	add_child(player)
	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.78
	body.shape = capsule
	body.position.y = 0.90
	player.add_child(body)
	player.floor_snap_length = 0.55
	player.floor_max_angle = deg_to_rad(56.0)
	player.safe_margin = 0.04
	player_model = Node3D.new()
	player_model.rotation.y = PI
	player_model.add_child(model_instance)
	player.add_child(player_model)
	_setup_protagonist_animations(model_instance)
	print("MODELO NOVO CARREGADO")
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 62
	camera.near = 0.18
	camera.far = 140.0
	add_child(camera)
	var terrain_for_camera := get_node_or_null("Terrain3D")
	if terrain_for_camera and terrain_for_camera.has_method("set_camera"):
		terrain_for_camera.call("set_camera", camera)
	camera.global_position = Vector3(0.0, player.global_position.y + 2.7, 10.8)
	camera.look_at(player.global_position + Vector3(0.0, 1.15, 0.0))

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

func _setup_protagonist_animations(model_instance: Node3D) -> void:
	var skeleton := _find_skeleton(model_instance)
	if skeleton == null:
		push_warning("Protagonist Skeleton3D not found; animations cannot be retargeted.")
		return
	var source_scene := load("res://assets/characters/UAL1_Standard.glb") as PackedScene
	if source_scene == null:
		push_warning("UAL1 animation asset failed to load.")
		return
	var source_instance := source_scene.instantiate()
	var source_player := _find_animation_player(source_instance)
	if source_player == null:
		source_instance.free()
		push_warning("AnimationPlayer not found in UAL1 scene.")
		return
	protagonist_animation_player = AnimationPlayer.new()
	protagonist_animation_player.name = "ProtagonistAnimationPlayer"
	player_model.add_child(protagonist_animation_player)
	# As animações são copiadas com o root_node explicitamente relativo ao AnimationPlayer.
	protagonist_animation_player.root_node = NodePath(".")
	var target_skeleton_path := protagonist_animation_player.get_path_to(skeleton)
	var library := AnimationLibrary.new()
	var ignored := 0
	var ok_tracks := 0
	var total_tracks := 0
	var first_converted := ""
	for library_name in source_player.get_animation_library_list():
		var source_library: AnimationLibrary = source_player.get_animation_library(library_name)
		for animation_name in source_library.get_animation_list():
			var animation_key := str(animation_name)
			if not ["Idle", "Walk", "Jog_Fwd", "Sprint"].has(animation_key):
				continue
			var source_animation: Animation = source_library.get_animation(animation_name)
			var retargeted: Animation = source_animation.duplicate(true)
			for track_index in range(retargeted.get_track_count()):
				var original_path: NodePath = retargeted.track_get_path(track_index)
				total_tracks += 1
				# A origem do caminho é irrelevante: aproveita somente o nome após ':'.
				var bone_name := ""
				for subname_index in range(original_path.get_subname_count()):
					var subname := str(original_path.get_subname(subname_index))
					if subname_index == 0:
						bone_name = subname
				# Descartar deslocamento do osso raiz para não aplicar root motion.
				var track_type := retargeted.track_get_type(track_index)
				var track_property := str(original_path)
				var is_root_position := bone_name.to_lower() in ["root", "armature", "hips"] and track_type == Animation.TYPE_POSITION_3D
				if is_root_position or skeleton.find_bone(bone_name) < 0:
					retargeted.remove_track(track_index)
					ignored += 1
					continue
				var converted_path := str(target_skeleton_path) + ":" + bone_name
				retargeted.track_set_path(track_index, NodePath(converted_path))
				ok_tracks += 1
				if first_converted == "":
					first_converted = converted_path
			retargeted.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(animation_key, retargeted)
	if library.get_animation_list().size() > 0:
		protagonist_animation_player.add_animation_library("", library)
		protagonist_tracks_ok = ok_tracks
		protagonist_tracks_total = total_tracks
		protagonist_ignored_tracks = ignored
		protagonist_first_track = first_converted
		protagonist_animation_player.play("Idle")
		current_protagonist_animation = "Idle"
		print("ANIMATION TRACKS OK=", ok_tracks, "/", total_tracks, " ignored=", ignored, " first=", first_converted)
	else:
		push_warning("UAL1 library did not contain Idle/Walk/Jog_Fwd/Sprint.")
	source_instance.free()
	_update_protagonist_diagnostic()

func _update_protagonist_animation(speed: float, _delta: float) -> void:
	if protagonist_animation_player == null:
		return
	var animation_name := "Idle"
	if speed > 0.15:
		if speed >= MOVE_SPEED * 0.98:
			animation_name = "Sprint"
		elif speed >= MOVE_SPEED * 0.50:
			animation_name = "Jog_Fwd"
		else:
			animation_name = "Walk"
	if animation_name != current_protagonist_animation:
		protagonist_animation_player.play(animation_name, 0.22)
		current_protagonist_animation = animation_name
		_update_protagonist_diagnostic()

func _update_protagonist_diagnostic() -> void:
	if protagonist_diagnostic_label:
		protagonist_diagnostic_label.text = "MODELO: NOVO | ANIM: " + current_protagonist_animation + " | TRACKS OK: " + str(protagonist_tracks_ok) + "/" + str(protagonist_tracks_total) + " | TRACK: " + protagonist_first_track

func _build_player_fallback() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(-4.0, _terrain_height(-4.0, -42.0) + 0.12, -42.0) # Planície inicial segura.
	add_child(player)

	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.78
	body.shape = capsule
	body.position.y = 0.90
	player.add_child(body)
	player.floor_snap_length = 0.55
	player.floor_max_angle = deg_to_rad(56.0)
	player.safe_margin = 0.04

	player_model = Node3D.new()
	player_model.rotation.y = PI # Ajuste visual de 180°: o modelo original aponta para +Z.
	player.add_child(player_model)

	# Explorador estilizado: silhueta legível, roupas em camadas e acessórios.
	_add_prism_part(player_model, Vector3(0.0, 1.22, 0.0), Vector3(0.72, 0.78, 0.43), Color(0.10, 0.25, 0.39))
	_add_box(player_model, Vector3(0.0, 0.88, 0.015), Vector3(0.72, 0.13, 0.46), Color(0.18, 0.17, 0.14), false)
	_add_box(player_model, Vector3(0.0, 0.91, 0.255), Vector3(0.23, 0.12, 0.035), Color(0.88, 0.65, 0.27), false)

	# Mochila arredondada, com tampa, bolsos e alças visíveis por trás.
	_add_prism_part(player_model, Vector3(0.0, 1.28, -0.285), Vector3(0.48, 0.58, 0.22), Color(0.48, 0.20, 0.10))
	_add_box(player_model, Vector3(0.0, 1.56, -0.30), Vector3(0.43, 0.13, 0.24), Color(0.67, 0.31, 0.13), false)
	_add_box(player_model, Vector3(-0.13, 1.19, -0.405), Vector3(0.17, 0.20, 0.055), Color(0.34, 0.16, 0.09), false)
	_add_box(player_model, Vector3(0.13, 1.19, -0.405), Vector3(0.17, 0.20, 0.055), Color(0.34, 0.16, 0.09), false)
	for side in [-1.0, 1.0]:
		_add_box(player_model, Vector3(side * 0.235, 1.30, 0.02), Vector3(0.075, 0.56, 0.075), Color(0.82, 0.61, 0.31), false)

	# Gola e lenço de aventura.
	_add_prism_part(player_model, Vector3(0.0, 1.62, 0.025), Vector3(0.38, 0.17, 0.36), Color(0.82, 0.38, 0.13))
	_add_box(player_model, Vector3(0.10, 1.54, 0.225), Vector3(0.12, 0.24, 0.045), Color(0.94, 0.68, 0.30), false)

	# Cabeça, orelhas, olhos e nariz.
	_add_faceted_part(player_model, Vector3(0.0, 1.91, 0.035), Vector3(0.265, 0.31, 0.245), Color(0.83, 0.62, 0.48))
	_add_faceted_part(player_model, Vector3(-0.265, 1.91, 0.04), Vector3(0.055, 0.10, 0.055), Color(0.72, 0.47, 0.36))
	_add_faceted_part(player_model, Vector3(0.265, 1.91, 0.04), Vector3(0.055, 0.10, 0.055), Color(0.72, 0.47, 0.36))
	_add_faceted_part(player_model, Vector3(-0.105, 1.96, 0.255), Vector3(0.035, 0.045, 0.025), Color(0.07, 0.06, 0.05))
	_add_faceted_part(player_model, Vector3(0.105, 1.96, 0.255), Vector3(0.035, 0.045, 0.025), Color(0.07, 0.06, 0.05))
	_add_faceted_part(player_model, Vector3(0.0, 1.88, 0.275), Vector3(0.045, 0.04, 0.035), Color(0.68, 0.39, 0.31))

	# Chapéu de explorador em duas peças, em vez de uma barra retangular.
	var hat_brim := MeshInstance3D.new()
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.36
	brim_mesh.bottom_radius = 0.38
	brim_mesh.height = 0.075
	brim_mesh.radial_segments = 12
	hat_brim.mesh = brim_mesh
	hat_brim.position = Vector3(0.0, 2.15, 0.02)
	hat_brim.material_override = _mat(Color(0.17, 0.20, 0.18))
	player_model.add_child(hat_brim)
	var hat_crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.255
	crown_mesh.bottom_radius = 0.29
	crown_mesh.height = 0.22
	crown_mesh.radial_segments = 10
	hat_crown.mesh = crown_mesh
	hat_crown.position = Vector3(0.0, 2.28, 0.02)
	hat_crown.material_override = _mat(Color(0.73, 0.30, 0.13))
	player_model.add_child(hat_crown)

	for side_index in range(2):
		var side := -1.0 if side_index == 0 else 1.0
		var arm := _add_limb_part(player_model, Vector3(side * 0.42, 1.23, 0.0), Vector3(0.15, 0.42, 0.15), Color(0.78, 0.56, 0.43))
		player_arm_parts.append(arm)
		_add_box(player_model, Vector3(side * 0.43, 0.91, 0.035), Vector3(0.18, 0.16, 0.18), Color(0.20, 0.22, 0.22), false)
		var leg := _add_limb_part(player_model, Vector3(side * 0.19, 0.40, 0.0), Vector3(0.17, 0.48, 0.17), Color(0.16, 0.22, 0.29))
		player_leg_parts.append(leg)
		_add_box(player_model, Vector3(side * 0.19, 0.13, 0.12), Vector3(0.30, 0.20, 0.42), Color(0.12, 0.13, 0.15), false)
		_add_box(player_model, Vector3(side * 0.19, 0.045, 0.12), Vector3(0.30, 0.045, 0.42), Color(0.31, 0.25, 0.17), false)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 62
	camera.near = 0.18
	camera.far = 140.0
	add_child(camera)
	var terrain_for_camera := get_node_or_null("Terrain3D")
	if terrain_for_camera and terrain_for_camera.has_method("set_camera"):
		terrain_for_camera.call("set_camera", camera)
	camera.global_position = Vector3(0.0, player.global_position.y + 2.7, 10.8)
	camera.look_at(player.global_position + Vector3(0.0, 1.15, 0.0))

func _build_creature() -> void:
	# Alterna espécies para que a coleção tenha criaturas com silhuetas realmente diferentes.
	creature_species = (captured_count + pedralume_count) % 2
	creature_tail = null
	creature_leg_parts.clear()
	creature_ear_parts.clear()
	creature_crystal_parts.clear()
	if creature_species == 0:
		_build_brasafofo()
	else:
		_build_pedralume()

func _build_brasafofo() -> void:
	creature = Node3D.new()
	creature.position = creature_home
	add_child(creature)
	# Variações visuais alternadas para a coleção.
	var variant := captured_count % 3
	var body_color: Color = Color(0.72, 0.17, 0.045)
	var highlight_color: Color = Color(0.91, 0.29, 0.055)
	var flame_color: Color = Color(1.0, 0.43, 0.025)
	var tip_color: Color = Color(1.0, 0.86, 0.30)
	if variant == 1:
		body_color = Color(0.20, 0.39, 0.68)
		highlight_color = Color(0.30, 0.61, 0.88)
		flame_color = Color(0.35, 0.78, 1.0)
		tip_color = Color(0.80, 0.95, 1.0)
	elif variant == 2:
		body_color = Color(0.43, 0.25, 0.62)
		highlight_color = Color(0.67, 0.39, 0.78)
		flame_color = Color(0.91, 0.42, 0.70)
		tip_color = Color(1.0, 0.78, 0.90)
	_update_variant_label(variant)
	_add_prism_part(creature, Vector3(0, 0.00, 0), Vector3(0.78, 0.43, 0.56), body_color)
	_add_prism_part(creature, Vector3(0, 0.29, 0.35), Vector3(0.43, 0.39, 0.40), highlight_color)
	var muzzle := MeshInstance3D.new()
	var muzzle_mesh := PrismMesh.new()
	muzzle_mesh.size = Vector3(0.32, 0.20, 0.40)
	muzzle.mesh = muzzle_mesh
	muzzle.position = Vector3(0, 0.12, 0.66)
	muzzle.rotation.x = PI * 0.5
	muzzle.material_override = _mat(Color(1.0, 0.73, 0.39))
	creature.add_child(muzzle)
	_add_faceted_part(creature, Vector3(0, -0.15, 0.16), Vector3(0.39, 0.19, 0.31), Color(1.0, 0.68, 0.31))
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := PrismMesh.new()
		ear_mesh.size = Vector3(0.23, 0.46, 0.18)
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.23, 0.64, 0.33)
		ear.rotation.z = side * -0.20
		ear.material_override = _mat(body_color)
		creature.add_child(ear)
		creature_ear_parts.append(ear)
		_add_prism_part(creature, Vector3(side * 0.23, 0.64, 0.435), Vector3(0.085, 0.25, 0.045), flame_color)
		_add_faceted_part(creature, Vector3(side * 0.27, 0.18, 0.48), Vector3(0.11, 0.075, 0.035), highlight_color)
		_add_faceted_part(creature, Vector3(side * 0.16, 0.39, 0.64), Vector3(0.065, 0.085, 0.045), Color(0.98, 0.91, 0.68))
		_add_faceted_part(creature, Vector3(side * 0.16, 0.39, 0.675), Vector3(0.027, 0.047, 0.022), Color(0.08, 0.06, 0.05))
		var leg := _add_limb_part(creature, Vector3(side * 0.40, -0.28, 0.12), Vector3(0.12, 0.26, 0.12), body_color)
		creature_leg_parts.append(leg)
		_add_box(creature, Vector3(side * 0.40, -0.44, 0.18), Vector3(0.19, 0.12, 0.23), Color(0.24, 0.10, 0.055), false)
	creature_tail = Node3D.new()
	creature_tail.position = Vector3(0, 0.12, -0.48)
	creature.add_child(creature_tail)
	_add_cone_part(creature_tail, Vector3(0, 0.0, 0.0), 0.29, 0.82, body_color, -PI * 0.5)
	_add_cone_part(creature_tail, Vector3(0, 0.17, -0.24), 0.20, 0.62, flame_color, -PI * 0.5)
	_add_cone_part(creature_tail, Vector3(0, 0.34, -0.41), 0.105, 0.38, tip_color, -PI * 0.5)
	_add_faceted_part(creature_tail, Vector3(0, 0.50, -0.51), Vector3(0.055, 0.12, 0.06), Color(1.0, 0.97, 0.68))

func _build_pedralume() -> void:
	creature = Node3D.new()
	creature.position = creature_home
	add_child(creature)
	if status_label:
		_update_status("Um Pedralume surgiu entre as pedras!")
	if variant_label:
		variant_label.text = "NOVA ESPÉCIE: PEDRALUME • ROCHA VIVA"
	var stone_color := Color(0.30, 0.39, 0.37)
	var stone_light := Color(0.48, 0.56, 0.49)
	# Corpo baixo, largo e facetado; quatro patas dão uma silhueta própria.
	_add_prism_part(creature, Vector3(0, 0.02, 0), Vector3(0.92, 0.66, 0.78), stone_color)
	_add_prism_part(creature, Vector3(0, 0.23, 0.34), Vector3(0.52, 0.42, 0.42), stone_light)
	_add_prism_part(creature, Vector3(0, 0.16, 0.58), Vector3(0.28, 0.16, 0.20), Color(0.22, 0.29, 0.27))
	for side in [-1.0, 1.0]:
		_add_faceted_part(creature, Vector3(side * 0.19, 0.30, 0.57), Vector3(0.065, 0.075, 0.035), Color(0.95, 0.83, 0.48))
		_add_faceted_part(creature, Vector3(side * 0.19, 0.30, 0.60), Vector3(0.026, 0.045, 0.018), Color(0.06, 0.08, 0.07))
		var front_leg := _add_limb_part(creature, Vector3(side * 0.34, -0.28, 0.28), Vector3(0.16, 0.28, 0.16), stone_color)
		var rear_leg := _add_limb_part(creature, Vector3(side * 0.34, -0.28, -0.28), Vector3(0.16, 0.28, 0.16), stone_color)
		creature_leg_parts.append(front_leg)
		creature_leg_parts.append(rear_leg)
		_add_prism_part(creature, Vector3(side * 0.34, -0.43, 0.31), Vector3(0.22, 0.11, 0.23), stone_light)
		_add_prism_part(creature, Vector3(side * 0.34, -0.43, -0.25), Vector3(0.22, 0.11, 0.23), stone_light)
	# Cristais dorsais assimétricos: cada fragmento pulsa em um ritmo próprio.
	var crystal_specs := [
		[Vector3(-0.23, 0.48, -0.12), Vector3(0.20, 0.42, 0.18), Color(0.20, 0.78, 0.72)],
		[Vector3(0.02, 0.54, -0.08), Vector3(0.22, 0.56, 0.19), Color(0.32, 0.91, 0.78)],
		[Vector3(0.25, 0.45, -0.15), Vector3(0.18, 0.36, 0.16), Color(0.13, 0.61, 0.61)]
	]
	for crystal_spec in crystal_specs:
		var crystal_pivot := Node3D.new()
		crystal_pivot.position = crystal_spec[0]
		creature.add_child(crystal_pivot)
		_add_prism_part(crystal_pivot, Vector3.ZERO, crystal_spec[1], crystal_spec[2])
		creature_crystal_parts.append(crystal_pivot)
	# Placas laterais quebram a forma do tronco e reforçam a aparência mineral.
	_add_prism_part(creature, Vector3(-0.43, 0.10, -0.02), Vector3(0.18, 0.38, 0.50), Color(0.22, 0.30, 0.29))
	_add_prism_part(creature, Vector3(0.43, 0.10, -0.02), Vector3(0.18, 0.38, 0.50), Color(0.22, 0.30, 0.29))
	_add_prism_part(creature, Vector3(-0.02, 0.31, -0.43), Vector3(0.28, 0.24, 0.24), stone_light)

func _build_start_menu() -> void:
	# Tela inicial de beta; controles/HUD ainda não foram criados neste momento.
	var layer := CanvasLayer.new()
	layer.name = "StartMenuLayer"
	add_child(layer)
	start_menu = Control.new()
	start_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(start_menu)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.06, 0.07, 0.72)
	start_menu.add_child(shade)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.18
	panel.anchor_right = 0.82
	panel.anchor_top = 0.28
	panel.anchor_bottom = 0.72
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.15, 0.14, 0.94)
	style.set_corner_radius_all(24)
	style.border_color = Color(0.58, 0.75, 0.60, 0.8)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	start_menu.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "WILDMON 3D"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	box.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "BETA DE EXPLORAÇÃO"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	box.add_child(subtitle)
	var start_button := Button.new()
	start_button.text = "Iniciar"
	start_button.custom_minimum_size = Vector2(0, 76)
	start_button.add_theme_font_size_override("font_size", 25)
	start_button.pressed.connect(_start_game)
	box.add_child(start_button)
	var footer := Label.new()
	footer.text = "Planície de treinamento • Ambiente e movimentação"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	box.add_child(footer)

func _start_game() -> void:
	if started:
		return
	# Constrói o mundo atual somente após pressionar Iniciar, sem alterar terreno,
	# iluminação ou personagem.
	_build_world()
	_build_player()
	await get_tree().physics_frame
	await _snap_player_to_terrain()
	_build_ui()
	started = true
	_update_status("Explore a planície inicial.")
	if start_menu:
		start_menu.queue_free()

func _update_day_cycle() -> void:
	if sun_node == null:
		return
	# Sol alto no início, com ciclo lento para uma sessão de jogo.
	var angle := day_time * TAU
	sun_node.rotation_degrees = Vector3(-25.0 - sin(angle) * 48.0, -32.0, 0.0)
	sun_node.light_energy = 0.35 + maxf(0.0, sin(angle)) * 1.05
	if day_time > 0.22 and day_time < 0.78:
		sun_node.light_color = Color(1.0, 0.97, 0.88)
	else:
		sun_node.light_color = Color(0.70, 0.78, 0.94)
	# Brisa e céu variam lentamente sem processamento pesado de partículas.
	if wind_phase > 18.0:
		wind_phase = 0.0


func _build_ui() -> void:
	var diagnostic_layer := CanvasLayer.new()
	diagnostic_layer.name = "ProtagonistDiagnostic"
	add_child(diagnostic_layer)
	var diagnostic_label := Label.new()
	protagonist_diagnostic_label = diagnostic_label
	diagnostic_label.text = protagonist_model_status
	diagnostic_label.anchor_left = 0.0
	diagnostic_label.anchor_top = 0.0
	diagnostic_label.anchor_right = 0.0
	diagnostic_label.anchor_bottom = 0.0
	diagnostic_label.offset_left = 12.0
	diagnostic_label.offset_top = 160.0
	diagnostic_label.offset_right = 320.0
	diagnostic_label.offset_bottom = 188.0
	diagnostic_label.add_theme_font_size_override("font_size", 16)
	diagnostic_layer.add_child(diagnostic_label)
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
	collection_label = Label.new()
	collection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	collection_label.add_theme_font_size_override("font_size", 12)
	collection_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42))
	collection_label.text = "COLEÇÃO: 0 BRASAFOFO • 0 PEDRALUME"
	vbox.add_child(collection_label)
	variant_label = Label.new()
	variant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	variant_label.add_theme_font_size_override("font_size", 11)
	variant_label.add_theme_color_override("font_color", Color(0.70, 0.88, 1.0))
	vbox.add_child(variant_label)

	# Analógico grande no canto inferior esquerdo, com área de toque generosa.
	movement_stick = AnalogStick.new()
	movement_stick.anchor_left = 0.025
	movement_stick.anchor_top = 1.0
	movement_stick.anchor_right = 0.025
	movement_stick.anchor_bottom = 1.0
	movement_stick.offset_left = 0
	movement_stick.offset_top = -216
	movement_stick.offset_right = 196
	movement_stick.offset_bottom = -20
	movement_stick.value_changed.connect(func(value: Vector2): movement_input = value)
	layer.add_child(movement_stick)

	# Captura fica separada do analógico e maior para facilitar o toque.
	capture_button = _make_button("CAPTURAR")
	capture_button.anchor_left = 1.0
	capture_button.anchor_top = 1.0
	capture_button.anchor_right = 1.0
	capture_button.anchor_bottom = 1.0
	capture_button.offset_left = -196
	capture_button.offset_top = -116
	capture_button.offset_right = -20
	capture_button.offset_bottom = -28
	capture_button.custom_minimum_size = Vector2(176, 88)
	capture_button.add_theme_font_size_override("font_size", 19)
	capture_button.focus_mode = Control.FOCUS_NONE
	var capture_style := StyleBoxFlat.new()
	capture_style.bg_color = Color(0.70, 0.25, 0.09, 0.96)
	capture_style.border_color = Color(1.0, 0.72, 0.38)
	capture_style.set_border_width_all(2)
	capture_style.set_corner_radius_all(16)
	capture_button.add_theme_stylebox_override("normal", capture_style)
	var capture_hover := capture_style.duplicate()
	capture_hover.bg_color = Color(0.86, 0.34, 0.11, 1.0)
	capture_button.add_theme_stylebox_override("hover", capture_hover)
	var capture_pressed := capture_style.duplicate()
	capture_pressed.bg_color = Color(0.48, 0.16, 0.06, 1.0)
	capture_button.add_theme_stylebox_override("pressed", capture_pressed)
	capture_button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.87))
	capture_button.pressed.connect(_try_capture)
	layer.add_child(capture_button)

func _make_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(76, 76)
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
		_update_status("Você já capturou esta criatura!")
		return
	if creature == null or not is_instance_valid(creature):
		_update_status("Não há criatura disponível para capturar.")
		return
	if player.global_position.distance_to(creature.global_position) > 3.5:
		_update_status("Chegue mais perto da criatura para capturá-la.")
		return
	creature_captured = true
	if creature_species == 0:
		captured_count += 1
	else:
		pedralume_count += 1
	_save_collection()
	if collection_label:
		collection_label.text = "COLEÇÃO: " + str(captured_count) + " BRASAFOFO • " + str(pedralume_count) + " PEDRALUME"
	var captured_creature := creature
	capture_button.disabled = true
	capture_button.text = "CAPTURADO!"
	var capture_tween := create_tween()
	capture_tween.set_parallel(true)
	capture_tween.tween_property(captured_creature, "scale", Vector3.ZERO, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	capture_tween.tween_property(captured_creature, "position:y", captured_creature.position.y + 1.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	capture_tween.chain().tween_callback(func():
		captured_creature.queue_free()
		_schedule_creature_respawn()
	)
	var captured_name := "Brasafofo" if creature_species == 0 else "Pedralume"
	_update_status(captured_name + " capturado e adicionado à coleção!")

func _schedule_creature_respawn() -> void:
	await get_tree().create_timer(3.5).timeout
	if not is_inside_tree():
		return
	creature_captured = false
	creature_in_range = false
	creature_home = _choose_creature_spawn()
	_build_creature()
	if capture_button:
		capture_button.disabled = false
		capture_button.text = "CAPTURAR"
	_update_status("Outra criatura apareceu no vale! Continue explorando.")

func _choose_creature_spawn() -> Vector3:
	# Mantém os reaparecimentos em áreas exploráveis e evita repetir sempre o mesmo ponto.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spawn_x := rng.randf_range(-22.0, 22.0)
	var spawn_z := rng.randf_range(-24.0, -5.0)
	var spawn := Vector3(spawn_x, _terrain_height(spawn_x, spawn_z) + 0.72, spawn_z)
	if Vector2(spawn_x + 17.0, spawn_z + 12.0).length() < 9.0:
		spawn_x += 12.0 if spawn_x < 0.0 else -12.0
		spawn.x = spawn_x
		spawn.y = _terrain_height(spawn_x, spawn_z) + 0.72
	return spawn


func _update_variant_label(variant: int) -> void:
	if variant_label == null:
		return
	var names := ["BRASAFOFO • FOGO", "BRASAFOFO • GELO", "BRASAFOFO • MÍSTICO"]
	variant_label.text = "APARÊNCIA ENCONTRADA: " + names[variant]

func _load_collection() -> void:
	var save_data := ConfigFile.new()
	var load_error := save_data.load("user://wildmon_save.cfg")
	if load_error == OK:
		captured_count = int(save_data.get_value("collection", "brasafofo_count", 0))
		pedralume_count = int(save_data.get_value("collection", "pedralume_count", 0))
	if collection_label:
		collection_label.text = "COLEÇÃO: " + str(captured_count) + " BRASAFOFO • " + str(pedralume_count) + " PEDRALUME"

func _save_collection() -> void:
	var save_data := ConfigFile.new()
	save_data.set_value("collection", "brasafofo_count", captured_count)
	save_data.set_value("collection", "pedralume_count", pedralume_count)
	var save_error := save_data.save("user://wildmon_save.cfg")
	if save_error != OK:
		push_warning("Não foi possível salvar a coleção: " + str(save_error))

func _update_status(message: String) -> void:
	if status_label:
		status_label.text = message

func _add_faceted_part(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	part.mesh = mesh
	part.position = pos
	part.scale = size
	part.material_override = _mat(color)
	parent.add_child(part)

func _add_prism_part(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	# Volumes triangulares dão uma silhueta mais angular ao corpo e à cabeça.
	var part := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = pos
	part.material_override = _mat(color)
	parent.add_child(part)

func _add_cone_part(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, rotation_x: float) -> void:
	var part := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.015
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 1
	part.mesh = mesh
	part.position = pos
	part.rotation.x = rotation_x
	part.material_override = _mat(color)
	parent.add_child(part)

func _add_sphere_part(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	# Malha facetada: silhuetas menos infladas e mais próximas de modelos 3D estilizados.
	mesh.radial_segments = 10
	mesh.rings = 6
	part.mesh = mesh
	part.position = pos
	part.scale = size
	part.material_override = _mat(color)
	parent.add_child(part)

func _add_limb_part(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> Node3D:
	# Pivô no ombro/quadril: os membros giram a partir da articulação, não do centro.
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	parent.add_child(pivot)
	var part := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var radius := minf(size.x, size.z) * 0.5
	mesh.top_radius = radius * 0.78
	mesh.bottom_radius = radius
	mesh.height = size.y * 2.0
	mesh.radial_segments = 6
	mesh.rings = 1
	part.mesh = mesh
	part.position.y = -size.y * 0.5
	part.material_override = _mat(color)
	pivot.add_child(part)
	return pivot

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