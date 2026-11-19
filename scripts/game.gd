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
const TURN_SPEED := 10.0
const CAMERA_DISTANCE := 6.5

var player: CharacterBody3D
var player_model: Node3D
var player_arm_parts: Array[MeshInstance3D] = []
var player_leg_parts: Array[MeshInstance3D] = []
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
var look_pitch := 0.28
var target_look_pitch := 0.28
const CAMERA_SENSITIVITY := 0.00155
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

func _ready() -> void:
	_build_world()
	_build_player()
	_build_ui()
	_load_collection()
	_build_creature()
	_update_status("Explore o vale e encontre uma criatura!")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var screen_size := get_viewport().get_visible_rect().size
		if event.pressed:
			# A câmera usa somente a área livre do lado direito, sem disputar
			# os botões de movimento e captura na parte inferior.
			var in_camera_area: bool = event.position.x > screen_size.x * 0.44
			in_camera_area = in_camera_area and event.position.y > screen_size.y * 0.17
			in_camera_area = in_camera_area and event.position.y < screen_size.y * 0.66
			if in_camera_area and camera_touch_index == -1:
				camera_touch_index = event.index
				camera_drag_active = true
		elif event.index == camera_touch_index:
			camera_touch_index = -1
			camera_drag_active = false
	elif event is InputEventScreenDrag and camera_drag_active and event.index == camera_touch_index:
		target_look_yaw -= event.relative.x * CAMERA_SENSITIVITY
		target_look_pitch = clampf(target_look_pitch + event.relative.y * CAMERA_SENSITIVITY, -0.62, 0.88)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var screen_size := get_viewport().get_visible_rect().size
		var in_camera_area: bool = event.position.x > screen_size.x * 0.44
		in_camera_area = in_camera_area and event.position.y > screen_size.y * 0.17
		in_camera_area = in_camera_area and event.position.y < screen_size.y * 0.66
		camera_drag_active = event.pressed and in_camera_area
	elif event is InputEventMouseMotion and camera_drag_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		target_look_yaw -= event.relative.x * CAMERA_SENSITIVITY
		target_look_pitch = clampf(target_look_pitch + event.relative.y * CAMERA_SENSITIVITY, -0.62, 0.88)

func _process(delta: float) -> void:
	if player == null:
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
	var camera_query := PhysicsRayQueryParameters3D.create(target, desired_camera_position)
	camera_query.collision_mask = 1
	camera_query.exclude = [player.get_rid()]
	var camera_hit := get_world_3d().direct_space_state.intersect_ray(camera_query)
	if not camera_hit.is_empty():
		var hit_position: Vector3 = camera_hit.position
		var safe_direction := (desired_camera_position - target).normalized()
		desired_camera_position = hit_position - safe_direction * 0.42
	# Mantém a câmera acima da superfície mesmo em inclinações e transições do relevo.
	var camera_floor := _terrain_height(desired_camera_position.x, desired_camera_position.z) + 1.25
	desired_camera_position.y = maxf(desired_camera_position.y, camera_floor)
	camera.global_position = camera.global_position.lerp(desired_camera_position, minf(delta * 4.4, 1.0))
	var actual_camera_floor := _terrain_height(camera.global_position.x, camera.global_position.z) + 1.1
	camera.global_position.y = maxf(camera.global_position.y, actual_camera_floor)
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
	if player == null:
		return
	var input_dir := Vector2(movement_input.x, -movement_input.y)
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
	bounded_position.x = clampf(bounded_position.x, -64.0, 64.0)
	bounded_position.z = clampf(bounded_position.z, -64.0, 64.0)
	if bounded_position != player.global_position:
		player.global_position = bounded_position
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	# Recuperação defensiva: nunca deixa a câmera acompanhar o jogador sob o mapa.
	if player.global_position.y < -2.0:
		player.global_position = Vector3(0.0, _terrain_height(0.0, 4.0) + 1.1, 4.0)
		player.velocity = Vector3.ZERO
	if player_model:
		var moving := direction.length() > 0.1
		var gait := sin(Time.get_ticks_msec() * 0.012) if moving else 0.0
		player_model.position.y = absf(gait) * 0.045
		player_model.rotation.z = lerpf(player_model.rotation.z, gait * 0.025, min(delta * 8.0, 1.0))
		for arm_index in range(player_arm_parts.size()):
			var arm_target := gait * 0.42 * (1.0 if arm_index == 0 else -1.0) if moving else 0.0
			player_arm_parts[arm_index].rotation.x = lerpf(player_arm_parts[arm_index].rotation.x, arm_target, minf(delta * 9.0, 1.0))
		for leg_index in range(player_leg_parts.size()):
			var leg_target := gait * 0.58 * (1.0 if leg_index == 0 else -1.0) if moving else 0.0
			player_leg_parts[leg_index].rotation.x = lerpf(player_leg_parts[leg_index].rotation.x, leg_target, minf(delta * 9.0, 1.0))
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
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.62
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -32, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.91, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 52.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)

	_build_terrain()
	# Piso de segurança muito abaixo do mapa: só impede queda infinita caso
	# algum objeto saia dos limites, sem aparecer na câmera durante o jogo.
	var ground_body := StaticBody3D.new()
	ground_body.position.y = -14.0
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
	# Bosques em manchas irregulares, com árvores isoladas entre os grupos.
	var grove_centers := [Vector2(-43.0, -39.0), Vector2(43.0, -37.0), Vector2(-46.0, 39.0), Vector2(45.0, 40.0)]
	for i in range(68):
		var px: float
		var pz: float
		if i % 7 == 0:
			px = rng.randf_range(-65.0, 65.0)
			pz = rng.randf_range(-66.0, 66.0)
		else:
			var center: Vector2 = grove_centers[i % grove_centers.size()]
			px = center.x + rng.randf_range(-14.0, 14.0)
			pz = center.y + rng.randf_range(-13.0, 13.0)
		if absf(px) < 9.0 and pz < 11.0 and pz > -31.0:
			continue
		if Vector2(px + 17.0, pz + 12.0).length() < 8.0:
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

	_build_biome_details(rng)
	_build_biome_floor_patches()
	_build_biome_ground_cover(rng)

func _build_biome_ground_cover(rng: RandomNumberGenerator) -> void:
	# Sub-bosque em manchas: vegetação baixa acompanha as copas, sem cobrir tudo.
	var forest_centers := [Vector2(-43.0, -39.0), Vector2(43.0, -37.0), Vector2(-46.0, 39.0), Vector2(45.0, 40.0)]
	for center_index in range(forest_centers.size()):
		var center: Vector2 = forest_centers[center_index]
		for i in range(12):
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
	var forest_centers := [Vector2(-43.0, -39.0), Vector2(43.0, -37.0), Vector2(-46.0, 39.0), Vector2(45.0, 40.0)]
	for i in range(forest_centers.size()):
		_add_biome_floor_patch(forest_centers[i], 10.5, 8.2, Color(0.19, 0.24, 0.12), 210 + i)
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
	var grass_color := Color(0.19, 0.30, 0.13)
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
		for i in range(13):
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
		for i in range(22):
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
	# Malha de terreno explícita: a superfície visível e a colisão são geradas
	# dos mesmos vértices, evitando divergência de altura entre render e física.
	var segments := 176
	var world_size := 132.0
	var step := world_size / float(segments)
	var half_size := world_size * 0.5
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = 41827
	terrain_noise.frequency = 0.12
	for z in range(segments + 1):
		for x in range(segments + 1):
			var world_x := -half_size + float(x) * step
			var world_z := -half_size + float(z) * step
			var height := _terrain_height(world_x, world_z)
			var color := _terrain_vertex_color(world_x, world_z, height, terrain_noise)
			var p00 := Vector3(world_x, height, world_z)
			if x < segments and z < segments:
				var p10 := Vector3(world_x + step, _terrain_height(world_x + step, world_z), world_z)
				var p01 := Vector3(world_x, _terrain_height(world_x, world_z + step), world_z + step)
				var p11 := Vector3(world_x + step, _terrain_height(world_x + step, world_z + step), world_z + step)
				var c10 := _terrain_vertex_color(p10.x, p10.z, p10.y, terrain_noise)
				var c01 := _terrain_vertex_color(p01.x, p01.z, p01.y, terrain_noise)
				var c11 := _terrain_vertex_color(p11.x, p11.z, p11.y, terrain_noise)
				# Ordem anti-horária vista de cima: normais apontam para +Y.
				surface.set_color(color)
				surface.add_vertex(p00)
				surface.set_color(c01)
				surface.add_vertex(p01)
				surface.set_color(c10)
				surface.add_vertex(p10)
				surface.set_color(c10)
				surface.add_vertex(p10)
				surface.set_color(c01)
				surface.add_vertex(p01)
				surface.set_color(c11)
				surface.add_vertex(p11)
	surface.generate_normals()
	var terrain_mesh := MeshInstance3D.new()
	terrain_mesh.name = "GroundSurface"
	terrain_mesh.mesh = surface.commit()
	var terrain_material := StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 1.0
	terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain_mesh.material_override = terrain_material
	add_child(terrain_mesh)

	# Colisão por heightmap amostrada nos mesmos pontos da malha visual.
	# Mais estável para terreno contínuo no Android que a trimesh automática.
	var height_values := PackedFloat32Array()
	height_values.resize((segments + 1) * (segments + 1))
	for z in range(segments + 1):
		for x in range(segments + 1):
			var world_x := -half_size + float(x) * step
			var world_z := -half_size + float(z) * step
			height_values[z * (segments + 1) + x] = _terrain_height(world_x, world_z) / step
	var height_shape := HeightMapShape3D.new()
	height_shape.map_width = segments + 1
	height_shape.map_depth = segments + 1
	height_shape.map_data = height_values
	
	var terrain_body := StaticBody3D.new()
	terrain_body.name = "TerrainCollision"
	terrain_body.collision_layer = 1
	terrain_body.collision_mask = 1
	var terrain_collision := CollisionShape3D.new()
	terrain_collision.shape = height_shape
	# Escala uniforme é compatível com o backend de física do Godot.
	terrain_collision.scale = Vector3.ONE * step
	terrain_body.add_child(terrain_collision)
	add_child(terrain_body)

func _terrain_vertex_color(x: float, z: float, height: float, noise: FastNoiseLite) -> Color:
	var variation := noise.get_noise_2d(x, z) * 0.045
	var lowland := Color(0.24, 0.34, 0.16)
	var hillside := Color(0.31, 0.36, 0.19)
	var rocky := Color(0.39, 0.37, 0.30)
	var color := lowland.lerp(hillside, clampf((height - 0.25) / 1.35, 0.0, 1.0))
	color = color.lerp(rocky, clampf((height - 1.8) / 1.0, 0.0, 0.72))
	color += Color(variation, variation, variation * 0.72, 0.0)
	return color

func _make_terrain_texture(asset_name: String, base_color: Color, accent_color: Color, noise_seed: int) -> Terrain3DTextureAsset:
	var broad_noise := FastNoiseLite.new()
	broad_noise.seed = noise_seed
	broad_noise.frequency = 0.035
	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = noise_seed + 137
	detail_noise.frequency = 0.19
	var grain_noise := FastNoiseLite.new()
	grain_noise.seed = noise_seed + 293
	grain_noise.frequency = 0.63
	var albedo_image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var normal_image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var fx := float(x)
			var fy := float(y)
			var broad := broad_noise.get_noise_2d(fx, fy)
			var detail := detail_noise.get_noise_2d(fx, fy)
			var grain := grain_noise.get_noise_2d(fx, fy)
			var variation := clampf(0.50 + broad * 0.29 + detail * 0.15 + grain * 0.06, 0.0, 1.0)
			var color := base_color.lerp(accent_color, variation)
			var earthy_grain := 0.94 + grain * 0.075
			color *= earthy_grain
			albedo_image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
			# Derivadas da mesma camada de ruído criam relevo fino sem geometria extra.
			var dx := (broad_noise.get_noise_2d(fx + 1.0, fy) - broad_noise.get_noise_2d(fx - 1.0, fy)) * 0.5
			var dy := (broad_noise.get_noise_2d(fx, fy + 1.0) - broad_noise.get_noise_2d(fx, fy - 1.0)) * 0.5
			dx += (detail_noise.get_noise_2d(fx + 1.0, fy) - detail_noise.get_noise_2d(fx - 1.0, fy)) * 0.35
			dy += (detail_noise.get_noise_2d(fx, fy + 1.0) - detail_noise.get_noise_2d(fx, fy - 1.0)) * 0.35
			var normal := Vector3(-dx * 8.0, -dy * 8.0, 1.0).normalized()
			normal_image.set_pixel(x, y, Color(
				normal.x * 0.5 + 0.5,
				normal.y * 0.5 + 0.5,
				normal.z * 0.5 + 0.5,
				1.0
			))
	albedo_image.generate_mipmaps()
	normal_image.generate_mipmaps()
	var asset := Terrain3DTextureAsset.new()
	asset.name = asset_name
	asset.albedo_texture = ImageTexture.create_from_image(albedo_image)
	asset.normal_texture = ImageTexture.create_from_image(normal_image)
	asset.uv_scale = 0.12
	return asset

func _terrain_height(x: float, z: float) -> float:
	var edge_factor := clampf((maxf(absf(x), absf(z)) - 4.0) / 25.0, 0.0, 1.0)
	# Relevo com cristas compridas, ombros assimétricos e pequenos vales de erosão.
	var rolling := sin(x * 0.105 + z * 0.072) * 0.48 + cos(z * 0.091 - x * 0.063) * 0.38
	var warped_x := x + sin(z * 0.075) * 3.2 + cos(z * 0.031) * 2.1
	var ridge_a := pow(1.0 - absf(sin((warped_x + z * 0.22) * 0.082)), 2.0) * 1.72
	var ridge_b := pow(1.0 - absf(sin((x * 0.17 - z * 0.31 + 11.0) * 0.071)), 2.5) * 1.05
	var shoulder := pow(maxf(0.0, cos((x * 0.043 + z * 0.092) + sin(z * 0.035))), 5.0) * 0.42
	var drainage := -pow(maxf(0.0, 1.0 - absf(sin(x * 0.052 + z * 0.12 + sin(z * 0.04) * 1.3))), 5.0) * 0.62
	var detail := sin(x * 0.31 + z * 0.19) * 0.19 + cos(z * 0.27 - x * 0.23) * 0.15
	var erosion := -absf(sin(x * 0.045 + z * 0.031)) * 0.30
	return maxf(-0.32, (rolling + ridge_a + ridge_b + shoulder + drainage + detail + erosion) * edge_factor)

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
		rock.scale = Vector3.ONE * (0.62 + float(seed % 5) * 0.13)
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
		add_child(tree)
		_set_scene_visibility_range(tree, 108.0)
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

func _register_foliage_sway(foliage: Node3D, seed: int, strength: float) -> void:
	foliage_sway_nodes.append(foliage)
	foliage_sway_base_rotations.append(foliage.rotation)
	foliage_sway_phases.append(float(seed % 97) * 0.173)
	foliage_sway_strengths.append(strength)

func _add_plant(pos: Vector3, seed: int) -> void:
	var plant_scene := _get_nature_scene(["Fern_1", "Bush_Common", "Clover_1", "Flower_3_Group", "Bush001", "Bush002", "Reed001", "Reed002"], seed)
	if plant_scene:
		var plant := plant_scene.instantiate() as Node3D
		add_child(plant)
		_set_scene_visibility_range(plant, 58.0)
		plant.position = pos
		var scale_factor := 0.30 + float(seed % 5) * 0.10
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

	# Silhueta de explorador com volumes mais retos e peças sobrepostas.
	_add_box(player_model, Vector3(0, 1.20, 0), Vector3(0.72, 0.82, 0.48), Color(0.10, 0.27, 0.42), false)
	_add_box(player_model, Vector3(0, 0.78, 0.015), Vector3(0.76, 0.16, 0.50), Color(0.16, 0.18, 0.19), false)
	_add_faceted_part(player_model, Vector3(0, 1.91, 0.02), Vector3(0.29, 0.34, 0.27), Color(0.88, 0.67, 0.52))
	_add_box(player_model, Vector3(0, 2.18, -0.015), Vector3(0.66, 0.13, 0.58), Color(0.10, 0.13, 0.17), false)
	_add_box(player_model, Vector3(0, 2.09, 0.015), Vector3(0.66, 0.09, 0.58), Color(0.86, 0.30, 0.10), false)
	_add_box(player_model, Vector3(0, 1.22, -0.31), Vector3(0.48, 0.52, 0.22), Color(0.63, 0.25, 0.10), false)
	_add_box(player_model, Vector3(-0.18, 1.26, 0.25), Vector3(0.055, 0.42, 0.055), Color(0.91, 0.75, 0.42), false)
	_add_box(player_model, Vector3(0.18, 1.26, 0.25), Vector3(0.055, 0.42, 0.055), Color(0.91, 0.75, 0.42), false)
	for side_index in range(2):
		var side := -1.0 if side_index == 0 else 1.0
		var arm := _add_limb_part(player_model, Vector3(side * 0.43, 1.18, 0), Vector3(0.13, 0.40, 0.13), Color(0.82, 0.57, 0.42))
		player_arm_parts.append(arm)
		_add_box(player_model, Vector3(side * 0.45, 0.91, 0.02), Vector3(0.20, 0.13, 0.19), Color(0.18, 0.20, 0.23), false)
		var leg := _add_limb_part(player_model, Vector3(side * 0.19, 0.32, 0), Vector3(0.16, 0.42, 0.17), Color(0.12, 0.18, 0.27))
		player_leg_parts.append(leg)
		_add_box(player_model, Vector3(side * 0.19, 0.10, 0.11), Vector3(0.32, 0.16, 0.42), Color(0.08, 0.09, 0.11), false)
	_add_faceted_part(player_model, Vector3(0, 1.91, 0.275), Vector3(0.045, 0.045, 0.035), Color(0.10, 0.09, 0.08))
	_add_faceted_part(player_model, Vector3(0.16, 1.97, 0.26), Vector3(0.035, 0.045, 0.025), Color(0.10, 0.09, 0.08))

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 62
	add_child(camera)
	camera.global_position = Vector3(0, 3.2, 11.5)
	camera.look_at(Vector3(0, 1, 0))

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

func _add_limb_part(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	# Membros com seção hexagonal e leve afunilamento: silhueta mais firme e menos arredondada.
	var part := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var radius := minf(size.x, size.z) * 0.5
	mesh.top_radius = radius * 0.78
	mesh.bottom_radius = radius
	mesh.height = size.y * 2.0
	mesh.radial_segments = 6
	mesh.rings = 1
	part.mesh = mesh
	part.position = pos
	part.material_override = _mat(color)
	parent.add_child(part)
	return part

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