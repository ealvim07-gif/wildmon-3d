extends Node3D

const MOVE_SPEED := 5.2
const TURN_SPEED := 10.0
const CAMERA_DISTANCE := 6.5

var player: CharacterBody3D
var camera: Camera3D
var creature: Node3D
var creature_captured := false
var move_vector := Vector2.ZERO
var look_yaw := 0.0
var status_label: Label
var capture_button: Button
var touch_left := false
var touch_right := false
var touch_forward := false
var touch_back := false

func _ready() -> void:
	_build_world()
	_build_player()
	_build_creature()
	_build_ui()
	_update_status("Explore o vale e encontre uma criatura!")

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
		if player.global_position.distance_to(creature.global_position) < 3.0:
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
	if direction.length() > 0.1:
		player.rotation.y = lerp_angle(player.rotation.y, atan2(direction.x, direction.z) + PI, min(delta * TURN_SPEED, 1.0))

func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.86, 0.96)
	env.ambient_light_energy = 0.8
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.15
	add_child(sun)

	_add_box(self, Vector3(0, -0.35, 0), Vector3(70, 0.5, 70), Color(0.30, 0.58, 0.30), true)
	_add_box(self, Vector3(0, -0.05, -12), Vector3(9, 0.12, 34), Color(0.72, 0.66, 0.48), false)
	for i in range(22):
		var px := float((i * 17) % 54) - 27.0
		var pz := float((i * 29) % 58) - 29.0
		if abs(px) < 7.0 and pz < 8.0 and pz > -30.0:
			continue
		_add_tree(Vector3(px, 0, pz))

func _add_tree(pos: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 1.7
	trunk.mesh = trunk_mesh
	trunk.position = pos + Vector3(0, 0.85, 0)
	trunk.material_override = _mat(Color(0.34, 0.22, 0.12))
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.0
	crown_mesh.height = 1.8
	crown.mesh = crown_mesh
	crown.scale = Vector3(1.0, 1.2, 1.0)
	crown.position = pos + Vector3(0, 2.2, 0)
	crown.material_override = _mat(Color(0.12, 0.38, 0.19))
	add_child(crown)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 1, 4)
	add_child(player)
	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	body.shape = capsule
	body.position.y = 0.9
	player.add_child(body)
	var model := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.8
	model.mesh = mesh
	model.position.y = 0.9
	model.material_override = _mat(Color(0.16, 0.42, 0.78))
	player.add_child(model)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.25
	head_mesh.height = 0.5
	head.mesh = head_mesh
	head.position = Vector3(0, 1.85, 0)
	head.material_override = _mat(Color(0.95, 0.72, 0.53))
	player.add_child(head)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 70
	add_child(camera)
	camera.global_position = Vector3(0, 4, 11)
	camera.look_at(Vector3(0, 1, 0))

func _build_creature() -> void:
	creature = Node3D.new()
	creature.position = Vector3(2.5, 0.75, -9)
	add_child(creature)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.72
	sphere.height = 1.4
	core.mesh = sphere
	core.material_override = _mat(Color(0.95, 0.55, 0.18))
	creature.add_child(core)
	var belly := MeshInstance3D.new()
	var belly_mesh := SphereMesh.new()
	belly_mesh.radius = 0.43
	belly_mesh.height = 0.8
	belly.mesh = belly_mesh
	belly.position = Vector3(0, -0.25, 0.38)
	belly.material_override = _mat(Color(1.0, 0.84, 0.54))
	creature.add_child(belly)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.09
		eye_mesh.height = 0.18
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.25, 0.18, 0.61)
		eye.material_override = _mat(Color(0.08, 0.08, 0.10))
		creature.add_child(eye)

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
	title.text = "WILDMON 3D  •  BETA 0.1"
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
	if creature_captured:
		_update_status("Você já capturou o Brasafofo! Beta concluída.")
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
