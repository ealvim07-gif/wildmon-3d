extends Node3D
class_name ChunkManager
# Gerenciador dinamico de chunks de 32 m com arvores e grama deterministicas por chunk (Etapa 3).

const CHUNK_SIZE := 32.0
const CELLS := 12
const CHUNK_VIEW_RADIUS := 4
const MAX_CHUNKS_PER_FRAME := 1

# --- Contrato de vegetacao por chunk (Etapa 3) ---
const MAX_TREES_PER_CHUNK := 20
const MAX_GRASS_PER_CHUNK := 1500
const GRASS_CHUNK_MAX_DIST := 3 # Apenas chunks com distancia < 3 exibem tufos de grama

var _terrain: Node3D
var _shared_material: Material
var _world_seed: int = 82471
var _active_chunks: Dictionary = {} # Vector2i -> Node3D
var _chunk_grass_nodes: Dictionary = {} # Vector2i -> MultiMeshInstance3D
var _last_center_chunk := Vector2i(999999, 999999)

var _shared_grass_mesh: ArrayMesh
var _shared_trunk_mesh: CylinderMesh
var _shared_canopy_mesh: SphereMesh

func setup(terrain: Node3D, shared_material: Material, world_seed: int = 82471) -> void:
	_terrain = terrain
	_shared_material = shared_material
	_world_seed = world_seed
	_build_shared_vegetation_meshes()

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / CHUNK_SIZE)),
		int(floor(world_pos.z / CHUNK_SIZE))
	)

func max_allowed_chunks() -> int:
	var side := 2 * (CHUNK_VIEW_RADIUS + 1) + 1
	return side * side

func get_active_chunk_count() -> int:
	return _active_chunks.size()

func has_chunk_at_world_pos(world_pos: Vector3) -> bool:
	return _active_chunks.has(world_to_chunk(world_pos))

func _chunk_seed(coord: Vector2i) -> int:
	# Hash deterministico combinando WORLD_SEED + coordenadas do chunk
	var h := int(_world_seed)
	h = int((h ^ (coord.x * 73856093)) * 19349663)
	h = int((h ^ (coord.y * 83492791)) * 2971215073)
	return absi(h)

func compute_chunk_tree_positions(coord: Vector2i) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if _terrain == null:
		return transforms

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(coord) ^ 0x4A1B

	var ox := float(coord.x) * CHUNK_SIZE
	var oz := float(coord.y) * CHUNK_SIZE
	var water_level: float = _terrain.WATER_LEVEL if _terrain.get("WATER_LEVEL") != null else -1.35
	var target_count := rng.randi_range(4, MAX_TREES_PER_CHUNK)

	var placed_points: Array[Vector2] = []
	var attempts := target_count * 4
	for _i in range(attempts):
		if transforms.size() >= MAX_TREES_PER_CHUNK or transforms.size() >= target_count:
			break
		var lx := rng.randf_range(1.5, CHUNK_SIZE - 1.5)
		var lz := rng.randf_range(1.5, CHUNK_SIZE - 1.5)
		var wx := ox + lx
		var wz := oz + lz
		var p2 := Vector2(wx, wz)

		# Mantem clareira livre ao redor do ponto de spawn (-4, -42)
		if p2.distance_to(Vector2(-4.0, -42.0)) < 14.0:
			continue

		var wy: float = _terrain.height_at(wx, wz)
		if wy < water_level + 0.30:
			continue

		# Evita arvores coladas umas nas outras
		var too_close := false
		for prev in placed_points:
			if prev.distance_squared_to(p2) < 16.0:
				too_close = true
				break
		if too_close:
			continue

		placed_points.append(p2)
		var scale_xz := rng.randf_range(0.85, 1.35)
		var scale_y := rng.randf_range(0.90, 1.45)
		var yaw := rng.randf() * TAU
		var t := Transform3D().scaled(Vector3(scale_xz, scale_y, scale_xz)).rotated(Vector3.UP, yaw)
		t.origin = Vector3(wx, wy - 0.08, wz)
		transforms.append(t)

	return transforms

func generate_chunk_population_preview(coord: Vector2i) -> Dictionary:
	# Usado pelo simulador para validar determinismo sem depender da fila assincrona
	var trees := compute_chunk_tree_positions(coord)
	return {
		"trees": trees.size(),
		"max_trees": MAX_TREES_PER_CHUNK,
		"max_grass": MAX_GRASS_PER_CHUNK
	}

func ensure_initial_chunks_around(world_pos: Vector3, initial_radius: int = 1) -> void:
	var center := world_to_chunk(world_pos)
	var created := 0
	for dz in range(-initial_radius, initial_radius + 1):
		for dx in range(-initial_radius, initial_radius + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			if not _active_chunks.has(coord):
				_create_chunk(coord, center)
				created += 1
	_update_chunk_grass_visibility(center)
	if created > 0:
		print("[CHUNKS] ativos: ", _active_chunks.size(), ", criados: ", created, ", apagados: 0")

func update_around(world_pos: Vector3) -> void:
	if _terrain == null:
		return
	var center := world_to_chunk(world_pos)
	var deleted := 0

	var unload_limit := CHUNK_VIEW_RADIUS + 1
	var coords_to_remove: Array[Vector2i] = []
	for coord in _active_chunks.keys():
		var dist := maxi(absi(coord.x - center.x), absi(coord.y - center.y))
		if dist > unload_limit:
			coords_to_remove.append(coord)

	for coord in coords_to_remove:
		var chunk_node: Node3D = _active_chunks[coord]
		if is_instance_valid(chunk_node):
			chunk_node.queue_free()
		_active_chunks.erase(coord)
		_chunk_grass_nodes.erase(coord)
		deleted += 1

	var missing: Array[Vector2i] = []
	for dz in range(-CHUNK_VIEW_RADIUS, CHUNK_VIEW_RADIUS + 1):
		for dx in range(-CHUNK_VIEW_RADIUS, CHUNK_VIEW_RADIUS + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			if not _active_chunks.has(coord):
				missing.append(coord)

	var created := 0
	if not missing.is_empty():
		missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := (a.x - center.x) * (a.x - center.x) + (a.y - center.y) * (a.y - center.y)
			var db := (b.x - center.x) * (b.x - center.x) + (b.y - center.y) * (b.y - center.y)
			return da < db
		)
		var to_build := mini(MAX_CHUNKS_PER_FRAME, missing.size())
		for i in range(to_build):
			_create_chunk(missing[i], center)
			created += 1

	if center != _last_center_chunk or created > 0:
		_update_chunk_grass_visibility(center)

	if created > 0 or deleted > 0 or center != _last_center_chunk:
		_last_center_chunk = center
		if created > 0 or deleted > 0:
			print("[CHUNKS] ativos: ", _active_chunks.size(), ", criados: ", created, ", apagados: ", deleted)

func _update_chunk_grass_visibility(center: Vector2i) -> void:
	for coord in _chunk_grass_nodes.keys():
		var grass_node: MultiMeshInstance3D = _chunk_grass_nodes[coord]
		if is_instance_valid(grass_node):
			var dist := maxi(absi(coord.x - center.x), absi(coord.y - center.y))
			grass_node.visible = dist < GRASS_CHUNK_MAX_DIST

func _create_chunk(coord: Vector2i, current_center: Vector2i) -> void:
	var ox := float(coord.x) * CHUNK_SIZE
	var oz := float(coord.y) * CHUNK_SIZE
	var stride := CELLS + 1
	var count := stride * stride
	var pts := PackedVector3Array()
	var norms := PackedVector3Array()
	var masks := PackedColorArray()
	pts.resize(count)
	norms.resize(count)
	masks.resize(count)

	var cell_step := CHUNK_SIZE / float(CELLS)
	for gz in range(stride):
		var wz := oz + float(gz) * cell_step
		for gx in range(stride):
			var wx := ox + float(gx) * cell_step
			var idx := gz * stride + gx
			var wy: float = _terrain.height_at(wx, wz)
			pts[idx] = Vector3(wx, wy, wz)
			norms[idx] = _terrain.get_terrain_normal(wx, wz)
			masks[idx] = _terrain.get_patch_mask(wx, wz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(CELLS):
		for x in range(CELLS):
			var i00 := z * stride + x
			var i10 := i00 + 1
			var i01 := (z + 1) * stride + x
			var i11 := i01 + 1

			st.set_color(masks[i00]); st.set_normal(norms[i00]); st.add_vertex(pts[i00])
			st.set_color(masks[i10]); st.set_normal(norms[i10]); st.add_vertex(pts[i10])
			st.set_color(masks[i01]); st.set_normal(norms[i01]); st.add_vertex(pts[i01])

			st.set_color(masks[i10]); st.set_normal(norms[i10]); st.add_vertex(pts[i10])
			st.set_color(masks[i11]); st.set_normal(norms[i11]); st.add_vertex(pts[i11])
			st.set_color(masks[i01]); st.set_normal(norms[i01]); st.add_vertex(pts[i01])

	var mesh := st.commit()
	var chunk_root := Node3D.new()
	chunk_root.name = "Chunk_%d_%d" % [coord.x, coord.y]

	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.material_override = _shared_material
	chunk_root.add_child(ground)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var trimesh := mesh.create_trimesh_shape()
	trimesh.backface_collision = true
	cs.shape = trimesh
	body.add_child(cs)
	chunk_root.add_child(body)

	# Vegetacao deterministica do chunk (apagada automaticamente junto com chunk_root)
	_populate_chunk_trees(chunk_root, coord)
	var grass_mmi := _populate_chunk_grass(chunk_root, coord)
	var dist := maxi(absi(coord.x - current_center.x), absi(coord.y - current_center.y))
	grass_mmi.visible = dist < GRASS_CHUNK_MAX_DIST
	_chunk_grass_nodes[coord] = grass_mmi

	add_child(chunk_root)
	_active_chunks[coord] = chunk_root

func _populate_chunk_trees(chunk_root: Node3D, coord: Vector2i) -> void:
	var tree_transforms := compute_chunk_tree_positions(coord)
	if tree_transforms.is_empty():
		return

	var count := tree_transforms.size()

	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.mesh = _shared_trunk_mesh
	trunk_mm.instance_count = count

	var canopy_mm := MultiMesh.new()
	canopy_mm.transform_format = MultiMesh.TRANSFORM_3D
	canopy_mm.use_colors = true
	canopy_mm.mesh = _shared_canopy_mesh
	canopy_mm.instance_count = count

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(coord) ^ 0x77E1

	for i in range(count):
		var base_t := tree_transforms[i]
		var trunk_t := base_t.translated_local(Vector3(0.0, 1.4, 0.0))
		trunk_mm.set_instance_transform(i, trunk_t)

		var canopy_t := base_t.translated_local(Vector3(0.0, 3.6, 0.0))
		canopy_mm.set_instance_transform(i, canopy_t)
		var leaf_tint := Color(0.22, 0.45, 0.16).lerp(Color(0.36, 0.58, 0.21), rng.randf())
		canopy_mm.set_instance_color(i, leaf_tint)

	var trunk_mmi := MultiMeshInstance3D.new()
	trunk_mmi.name = "ChunkTrunks"
	trunk_mmi.multimesh = trunk_mm
	trunk_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk_root.add_child(trunk_mmi)

	var canopy_mmi := MultiMeshInstance3D.new()
	canopy_mmi.name = "ChunkCanopies"
	canopy_mmi.multimesh = canopy_mm
	canopy_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk_root.add_child(canopy_mmi)

func _populate_chunk_grass(chunk_root: Node3D, coord: Vector2i) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(coord) ^ 0x99C3

	var ox := float(coord.x) * CHUNK_SIZE
	var oz := float(coord.y) * CHUNK_SIZE
	var water_level: float = _terrain.WATER_LEVEL if _terrain.get("WATER_LEVEL") != null else -1.35

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []

	for _i in range(MAX_GRASS_PER_CHUNK):
		var wx := ox + rng.randf_range(0.2, CHUNK_SIZE - 0.2)
		var wz := oz + rng.randf_range(0.2, CHUNK_SIZE - 0.2)
		var wy: float = _terrain.height_at(wx, wz)
		if wy < water_level + 0.14:
			continue

		var sc_xz := rng.randf_range(0.75, 1.15)
		var sc_y := rng.randf_range(0.26, 0.62)
		var yaw := rng.randf() * TAU
		var t := Transform3D().scaled(Vector3(sc_xz, sc_y, sc_xz)).rotated(Vector3.UP, yaw)
		t.origin = Vector3(wx, wy - 0.03, wz)
		transforms.append(t)
		colors.append(Color(0.86, 0.95, 0.76).lerp(Color(1.04, 1.00, 0.80), rng.randf()))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _shared_grass_mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ChunkGrass"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk_root.add_child(mmi)
	return mmi

func _build_shared_vegetation_meshes() -> void:
	# Tronco e copa estilizados leves para instanciamento em massa
	_shared_trunk_mesh = CylinderMesh.new()
	_shared_trunk_mesh.top_radius = 0.22
	_shared_trunk_mesh.bottom_radius = 0.34
	_shared_trunk_mesh.height = 2.8
	_shared_trunk_mesh.radial_segments = 6
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.24, 0.14)
	trunk_mat.roughness = 0.95
	_shared_trunk_mesh.material = trunk_mat

	_shared_canopy_mesh = SphereMesh.new()
	_shared_canopy_mesh.radius = 1.65
	_shared_canopy_mesh.height = 2.8
	_shared_canopy_mesh.radial_segments = 8
	_shared_canopy_mesh.rings = 5
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.vertex_color_use_as_albedo = true
	canopy_mat.roughness = 0.9
	_shared_canopy_mesh.material = canopy_mat

	# Malha estrela de 3 planos cruzados para tufos de grama
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_width := 0.42
	var height := 1.0
	var angles := [0.0, PI / 3.0, 2.0 * PI / 3.0]
	for ang in angles:
		var dx := cos(ang) * half_width
		var dz := sin(ang) * half_width
		var p0 := Vector3(-dx, 0.0, -dz)
		var p1 := Vector3(dx, 0.0, dz)
		var p2 := Vector3(-dx, height, -dz)
		var p3 := Vector3(dx, height, dz)
		st.set_uv(Vector2(0.0, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(p1)
		st.set_uv(Vector2(0.0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(p2)

		st.set_uv(Vector2(1.0, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(p1)
		st.set_uv(Vector2(1.0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(p3)
		st.set_uv(Vector2(0.0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(p2)

	_shared_grass_mesh = st.commit()
	var grass_mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap;

void vertex() {
	float sway_mask = 1.0 - UV.y;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.9 + world_pos.x * 0.34 + world_pos.z * 0.28) * 0.12;
	VERTEX.x += gust * sway_mask;
	VERTEX.z += gust * 0.65 * sway_mask;
}

void fragment() {
	vec4 tex = texture(grass_tex, UV);
	if (tex.a < 0.42) {
		discard;
	}
	float height_grad = clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 root_shade = vec3(0.62, 0.70, 0.46);
	vec3 sun_lit = vec3(1.04, 1.03, 0.94);
	vec3 light_tint = mix(root_shade, sun_lit, smoothstep(0.0, 0.72, height_grad));
	ALBEDO = tex.rgb * COLOR.rgb * light_tint;
}
"""
	grass_mat.shader = shader
	grass_mat.set_shader_parameter("grass_tex", _make_grass_blade_texture())
	_shared_grass_mesh.surface_set_material(0, grass_mat)

func _make_grass_blade_texture() -> ImageTexture:
	var w := 64
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = _world_seed ^ 0x16062
	for _b in range(26):
		var base_x := rng.randf_range(8.0, float(w - 8))
		var tip_x := base_x + rng.randf_range(-8.0, 8.0)
		var blade_h := rng.randf_range(24.0, 56.0)
		var base_w := rng.randf_range(1.2, 2.2)
		var col_base := Color(0.28, 0.44, 0.17)
		var col_tip := Color(0.56, 0.74, 0.28)
		var steps := int(blade_h)
		for s in range(steps):
			var t := float(s) / maxf(1.0, blade_h)
			var y := h - 1 - s
			if y < 0:
				break
			var cx := lerpf(base_x, tip_x, t * t)
			var half_w := maxf(0.5, base_w * (1.0 - t * 0.88))
			var c := col_base.lerp(col_tip, t)
			var x0 := clampi(int(cx - half_w), 0, w - 1)
			var x1 := clampi(int(cx + half_w), 0, w - 1)
			for px in range(x0, x1 + 1):
				img.set_pixel(px, y, Color(c.r, c.g, c.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)