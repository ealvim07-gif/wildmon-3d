extends Node3D

const MOVE_SPEED := 5.2
const TURN_SPEED := 10.0
const CAMERA_DISTANCE := 6.5

var player: CharacterBody3D
var camera: Camera3D
var creature: Node3D
var creature_captured := false
var creature_in_range := false
var look_yaw := 0.0
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
		look_yaw -= event.relative.x * 0.008
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		camera_drag_active = event.pressed
	elif event is InputEventMouseMotion and camera_drag_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		look_yaw -= event.relative.x * 0.008

func _process(delta: float) -> void:
	if player == null:
		return
	var target := player.global_position + Vector3(0, 1.25, 0)
	var cam_offset := Vector3(sin(look_yaw) * CAMERA_DISTANCE, 3.0, cos(look_yaw) * CAMERA_DISTANCE)
	camera.global_position = camera.global_position.lerp(target + cam_offset, min(delta * 5.0, 1.0))
	camera.look_at(target, Vector3.UP)
	if creature and not creature_captured:
		creature.rotate_y(delta * 0.8)
		creature.position.y = 0.75 + sin(Time.get_ticks_msec() * 0.002) * 0.12
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
	bounded_position.x = clampf(bounded_position.x, -33.0, 33.0)
	bounded_position.z = clampf(bounded_position.z, -33.0, 33.0)
	if bounded_position != player.global_position:
		player.global_position = bounded_position
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	if direction.length() > 0.1:
		player.rotation.y = lerp_angle(player.rotation.y, atan2(direction.x, direction.z) + PI, min(delta * TURN_SPEED, 1.0))

func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 1.0
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.38, 0.78)
	sky_mat.sky_horizon_color = Color(0.48, 0.72, 0.91)
	sky_mat.ground_bottom_color = Color(0.16, 0.22, 0.16)
	sky_mat.ground_horizon_color = Color(0.62, 0.70, 0.59)
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.72, 0.82, 0.91)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	add_child(sun)

	_build_terrain()
	var ground_body := StaticBody3D.new()
	ground_body.position.y = -0.32
	add_child(ground_body)
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(76, 0.5, 76)
	ground_shape.shape = ground_box
	ground_body.add_child(ground_shape)

	# A winding sandy trail, made from several low, overlapping sections.
	for i in range(7):
		var trail := MeshInstance3D.new()
		var trail_mesh := BoxMesh.new()
		trail_mesh.size = Vector3(7.0 + sin(float(i)) * 1.0, 0.035, 6.2)
		trail.mesh = trail_mesh
		trail.position = Vector3(sin(float(i) * 0.48) * 2.8, -0.075, 15.0 - float(i) * 6.0)
		trail.rotation.y = sin(float(i) * 0.48) * 0.18
		trail.material_override = _mat(Color(0.66, 0.56, 0.39))
		add_child(trail)

	# Soft rolling hills frame the playable clearing.
	for hill_data in [
		[Vector3(-29, 1.1, -20), Vector3(12, 3.2, 18)],
		[Vector3(29, 1.0, -26), Vector3(14, 3.0, 20)],
		[Vector3(-28, 0.8, 24), Vector3(15, 2.7, 17)],
		[Vector3(28, 0.9, 22), Vector3(16, 3.0, 18)]
	]:
		var hill := MeshInstance3D.new()
		var hill_mesh := SphereMesh.new()
		hill_mesh.radius = 1.0
		hill_mesh.height = 2.0
		hill.mesh = hill_mesh
		hill.position = hill_data[0]
		hill.scale = hill_data[1]
		hill.material_override = _mat(Color(0.25, 0.43, 0.24))
		add_child(hill)

	for i in range(38):
		var px := float((i * 17) % 62) - 31.0
		var pz := float((i * 29) % 66) - 33.0
		if abs(px) < 8.0 and pz < 10.0 and pz > -32.0:
			continue
		_add_tree(Vector3(px, 0, pz))
	for i in range(55):
		var px := float((i * 13) % 64) - 32.0
		var pz := float((i * 19) % 64) - 32.0
		if abs(px) < 6.0 and pz < 10.0 and pz > -28.0:
			continue
		_add_plant(Vector3(px, 0, pz), i)

	# Extra rocks and grass tufts add detail without external assets.
	for i in range(28):
		var rx := float((i * 23) % 66) - 33.0
		var rz := float((i * 31) % 68) - 34.0
		if abs(rx) < 9.0 and rz < 12.0 and rz > -30.0:
			continue
		_add_rock(Vector3(rx, 0, rz), i)

	for i in range(85):
		var gx := float((i * 11) % 70) - 35.0
		var gz := float((i * 17) % 70) - 35.0
		if abs(gx) < 7.0 and gz < 12.0 and gz > -30.0:
			continue
		_add_grass_tuft(Vector3(gx, 0, gz), i)


func _build_terrain() -> void:
	# Malha de terreno com ondulações suaves e uma clareira central jogável.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var divisions := 64
	var world_size := 76.0
	for z in range(divisions):
		for x in range(divisions):
			var x0 := -world_size * 0.5 + world_size * float(x) / float(divisions)
			var x1 := -world_size * 0.5 + world_size * float(x + 1) / float(divisions)
			var z0 := -world_size * 0.5 + world_size * float(z) / float(divisions)
			var z1 := -world_size * 0.5 + world_size * float(z + 1) / float(divisions)
			var p00 := Vector3(x0, _terrain_height(x0, z0), z0)
			var p10 := Vector3(x1, _terrain_height(x1, z0), z0)
			var p01 := Vector3(x0, _terrain_height(x0, z1), z1)
			var p11 := Vector3(x1, _terrain_height(x1, z1), z1)
			surface.add_vertex(p00)
			surface.add_vertex(p01)
			surface.add_vertex(p10)
			surface.add_vertex(p10)
			surface.add_vertex(p01)
			surface.add_vertex(p11)
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.mesh = surface.commit()
	terrain.material_override = _mat(Color(0.29, 0.46, 0.24))
	add_child(terrain)

func _terrain_height(x: float, z: float) -> float:
	var edge_factor := clampf((maxf(absf(x), absf(z)) - 13.0) / 23.0, 0.0, 1.0)
	var rolling := sin(x * 0.19 + z * 0.08) * 0.62 + cos(z * 0.17 - x * 0.06) * 0.48
	var ridge_a := exp(-pow((x + 25.0) / 9.0, 2.0) - pow((z + 7.0) / 24.0, 2.0)) * 2.0
	var ridge_b := exp(-pow((x - 27.0) / 10.0, 2.0) - pow((z - 8.0) / 22.0, 2.0)) * 1.7
	return maxf(-0.08, (rolling + ridge_a + ridge_b) * edge_factor)

func _add_rock(pos: Vector3, seed: int) -> void:
	var rock := MeshInstance3D.new()
	var rock_mesh := SphereMesh.new()
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 3
	rock.mesh = rock_mesh
	rock.position = pos + Vector3(0, 0.18, 0)
	var width := 0.35 + float(seed % 4) * 0.12
	rock.scale = Vector3(width, 0.22 + float(seed % 3) * 0.08, width * 0.82)
	rock.rotation_degrees = Vector3(float(seed * 13 % 25), float(seed * 37 % 360), float(seed * 7 % 18))
	rock.material_override = _mat([Color(0.39, 0.42, 0.39), Color(0.48, 0.46, 0.40), Color(0.32, 0.36, 0.34)][seed % 3])
	add_child(rock)

func _add_grass_tuft(pos: Vector3, seed: int) -> void:
	for blade in range(3):
		var grass := MeshInstance3D.new()
		var grass_mesh := BoxMesh.new()
		grass_mesh.size = Vector3(0.055, 0.28 + float((seed + blade) % 3) * 0.06, 0.045)
		grass.mesh = grass_mesh
		grass.position = pos + Vector3((float(blade) - 1.0) * 0.09, grass_mesh.size.y * 0.5, 0.0)
		grass.rotation_degrees = Vector3(0, float(blade) * 60.0 + float(seed % 30), float(blade - 1) * 18.0)
		grass.material_override = _mat([Color(0.22, 0.42, 0.16), Color(0.32, 0.50, 0.19), Color(0.42, 0.53, 0.22)][(seed + blade) % 3])
		add_child(grass)

func _add_tree(pos: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 2.2
	trunk.mesh = trunk_mesh
	trunk.position = pos + Vector3(0, 1.1, 0)
	trunk.material_override = _mat(Color(0.30, 0.19, 0.11))
	add_child(trunk)
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, 1.0, 0)
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = 2.0
	collision.shape = shape
	body.add_child(collision)

	var green_tone := 0.30 + float(abs(int(pos.x * 13.0 + pos.z * 7.0)) % 5) * 0.018
	for crown_data in [
		[Vector3(0, 2.55, 0), 1.05],
		[Vector3(-0.62, 2.38, 0.12), 0.78],
		[Vector3(0.62, 2.42, -0.12), 0.82],
		[Vector3(0.02, 3.12, 0.10), 0.72],
		[Vector3(-0.28, 2.82, 0.55), 0.62]
	]:
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radial_segments = 9
		crown_mesh.rings = 6
		crown.mesh = crown_mesh
		crown.position = pos + crown_data[0]
		var crown_size: float = crown_data[1]
		crown.scale = Vector3(crown_size, crown_size * 0.82, crown_size)
		crown.material_override = _mat(Color(0.12, green_tone, 0.16))
		add_child(crown)

func _add_plant(pos: Vector3, seed: int) -> void:
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.025
	stem_mesh.bottom_radius = 0.045
	stem_mesh.height = 0.48
	stem.mesh = stem_mesh
	stem.position = pos + Vector3(0, 0.24, 0)
	stem.material_override = _mat(Color(0.20, 0.38, 0.16))
	add_child(stem)
	if seed % 3 == 0:
		var flower := MeshInstance3D.new()
		var flower_mesh := SphereMesh.new()
		flower_mesh.radius = 0.13
		flower_mesh.height = 0.18
		flower.mesh = flower_mesh
		flower.position = pos + Vector3(0, 0.52, 0)
		flower.material_override = _mat([Color(0.95, 0.72, 0.30), Color(0.92, 0.54, 0.62), Color(0.92, 0.88, 0.70)][seed % 3])
		add_child(flower)


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

	# Stylized explorer silhouette with layered clothing and a small field backpack.
	_add_sphere_part(player, Vector3(0, 1.18, 0), Vector3(0.43, 0.54, 0.30), Color(0.20, 0.43, 0.62))
	_add_sphere_part(player, Vector3(0, 1.92, 0.015), Vector3(0.31, 0.34, 0.30), Color(0.88, 0.66, 0.49))
	_add_sphere_part(player, Vector3(0, 2.12, -0.035), Vector3(0.33, 0.20, 0.32), Color(0.22, 0.18, 0.15))
	_add_sphere_part(player, Vector3(0, 0.63, 0), Vector3(0.34, 0.22, 0.27), Color(0.22, 0.25, 0.31))
	_add_sphere_part(player, Vector3(0, 1.22, -0.34), Vector3(0.30, 0.40, 0.18), Color(0.78, 0.42, 0.16))
	for side in [-1.0, 1.0]:
		_add_capsule_part(player, Vector3(side * 0.48, 1.18, 0), Vector3(0.13, 0.40, 0.13), Color(0.88, 0.66, 0.49))
		_add_sphere_part(player, Vector3(side * 0.49, 0.91, 0.02), Vector3(0.14, 0.14, 0.14), Color(0.88, 0.66, 0.49))
		_add_capsule_part(player, Vector3(side * 0.19, 0.32, 0), Vector3(0.16, 0.42, 0.17), Color(0.16, 0.24, 0.34))
		_add_sphere_part(player, Vector3(side * 0.19, 0.10, 0.10), Vector3(0.19, 0.11, 0.29), Color(0.12, 0.13, 0.15))
	_add_sphere_part(player, Vector3(0, 1.91, 0.29), Vector3(0.045, 0.045, 0.035), Color(0.12, 0.12, 0.13))
	_add_sphere_part(player, Vector3(0.17, 1.97, 0.27), Vector3(0.035, 0.045, 0.025), Color(0.10, 0.10, 0.11))

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 68
	add_child(camera)
	camera.global_position = Vector3(0, 4.2, 11.5)
	camera.look_at(Vector3(0, 1, 0))


func _build_creature() -> void:
	creature = Node3D.new()
	creature.position = Vector3(2.5, 0.72, -9)
	add_child(creature)
	# Brasafofo: a small fox-like fire creature with a curled flame tail.
	_add_sphere_part(creature, Vector3(0, 0.02, 0), Vector3(0.72, 0.48, 0.43), Color(0.91, 0.35, 0.12))
	_add_sphere_part(creature, Vector3(0, 0.32, 0.37), Vector3(0.43, 0.40, 0.39), Color(0.98, 0.48, 0.16))
	_add_sphere_part(creature, Vector3(0, 0.12, 0.66), Vector3(0.27, 0.20, 0.16), Color(1.0, 0.83, 0.55))
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := PrismMesh.new()
		ear_mesh.size = Vector3(0.25, 0.42, 0.18)
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.27, 0.68, 0.34)
		ear.rotation.z = side * -0.18
		ear.material_override = _mat(Color(0.86, 0.27, 0.10))
		creature.add_child(ear)
		_add_sphere_part(creature, Vector3(side * 0.19, 0.39, 0.69), Vector3(0.055, 0.075, 0.035), Color(0.08, 0.07, 0.07))
		_add_capsule_part(creature, Vector3(side * 0.43, -0.31, 0.12), Vector3(0.14, 0.28, 0.14), Color(0.83, 0.29, 0.10))
		_add_sphere_part(creature, Vector3(side * 0.43, -0.47, 0.19), Vector3(0.17, 0.10, 0.21), Color(0.26, 0.16, 0.12))
	_add_capsule_part(creature, Vector3(0, 0.05, -0.55), Vector3(0.16, 0.48, 0.16), Color(0.91, 0.35, 0.12))
	_add_sphere_part(creature, Vector3(0, 0.40, -0.76), Vector3(0.25, 0.32, 0.22), Color(1.0, 0.65, 0.12))
	_add_sphere_part(creature, Vector3(0, 0.48, -0.82), Vector3(0.15, 0.22, 0.14), Color(1.0, 0.88, 0.30))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.02
	panel.anchor_top = 0.025
	panel.anchor_right = 0.98
	panel.anchor_bottom = 0.16
	layer.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "WILDMON 3D  •  BETA 0.5"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "Carregando..."
	vbox.add_child(status_label)

	var controls := HBoxContainer.new()
	controls.anchor_left = 0.03
	controls.anchor_top = 0.70
	controls.anchor_right = 0.97
	controls.anchor_bottom = 0.96
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(controls)
	var left_col := VBoxContainer.new()
	controls.add_child(left_col)
	var up := _make_button("▲")
	left_col.add_child(up)
	up.button_down.connect(func(): touch_forward = true)
	up.button_up.connect(func(): touch_forward = false)
	var middle := HBoxContainer.new()
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
	capture_button.custom_minimum_size = Vector2(150, 66)
	capture_button.pressed.connect(_try_capture)
	controls.add_child(capture_button)

func _make_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(58, 58)
	button.add_theme_font_size_override("font_size", 20)
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
	mesh.radial_segments = 7
	mesh.rings = 4
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
