extends Node3D
class_name ChunkManager
# Gerenciador dinamico de chunks otimizado para mobile (MultiMesh para arvores + visibilidade por distancia).

const CHUNK_SIZE := 32.0
const CELLS := 12
const CHUNK_VIEW_RADIUS := 3
const MAX_CHUNKS_PER_FRAME := 1

# --- Contrato de vegetacao por chunk (otimizado para GPU mobile) ---
const MAX_TREES_PER_CHUNK := 14
const MAX_GRASS_PER_CHUNK := 450
const GRASS_CHUNK_MAX_DIST := 2
const TREE_CHUNK_MAX_DIST := 3

const DECIDUOUS_CANDIDATES := [
	"CommonTree_1",
	"CommonTree_2",
	"CommonTree_3",
	"BirchTree_1",
	"BirchTree_2"
]

const PINE_CANDIDATES := [
	"Pine_1",
	"Pine_2",
	"Pine_3"
]

var _terrain: Node3D
var _shared_material: Material
var _world_seed: int = 82471
var _active_chunks: Dictionary = {} # Vector2i -> Node3D
var _chunk_grass_nodes: Dictionary = {} # Vector2i -> MultiMeshInstance3D
var _chunk_tree_nodes: Dictionary = {} # Vector2i -> Node3D
var _last_center_chunk := Vector2i(999999, 999999)

var _shared_grass_mesh: ArrayMesh
var _deciduous_meshes: Array[Mesh] = []
var _pine_meshes: Array[Mesh] = []
var _fallback_trunk_mesh: CylinderMesh
var _fallback_canopy_mesh: SphereMesh
var _fallback_pine_mesh: CylinderMesh

func setup(terrain: Node3D, shared_material: Material, world_seed: int = 82471) -> void:
	_terrain = terrain
	_shared_material = shared_material
	_world_seed = world_seed
	_load_tree_meshes()
	_build_shared_vegetation_meshes()

func _load_tree_meshes() -> void:
	_deciduous_meshes.clear()
	_pine_meshes.clear()
	for model_name in DECIDUOUS_CANDIDATES:
		var m := _extract_merged_tree_mesh(model_name)
		if m != null:
			_deciduous_meshes.append(m)
	for model_name in PINE_CANDIDATES:
		var m := _extract_merged_tree_mesh(model_name)
		if m != null:
			_pine_meshes.append(m)

func _extract_merged_tree_mesh(model_name: String) -> Mesh:
	var paths := [
		"res://assets/nature/" + model_name + ".gltf",
		"res://assets/nature/" + model_name + ".glb",
		"res://assets/gobkit/" + model_name + ".glb",
		"res://assets/gobkit/" + model_name + ".gltf"
	]
	for path in paths:
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				var inst := scene.instantiate() as Node3D
				if inst != null:
					var found := _find_first_mesh(inst)
					inst.free()
					if found != null:
						return found
	return null

func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh
	for child in node.get_children():
		var m := _find_first_mesh(child)
		if m != null:
			return m
	return null

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
	var h := int(_world_seed)
	h = int((h ^ (coord.x * 73856093)) * 19349663)
	h = int((h ^ (coord.y * 83492791)) * 2971215073)
	return absi(h)

func _get_biome_at(wx: float, wz: float) -> String:
	if _terrain != null and _terrain.has_method("get_biome"):
		return str(_terrain.call("get_biome", wx, wz))
	return "prado"

func compute_chunk_tree_spawns(coord: Vector2i) -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	if _terrain == null:
		return spawns

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(coord) ^ 0x4A1B

	var ox := float(coord.x) * CHUNK_SIZE
	var oz := float(coord.y) * CHUNK_SIZE
	var water_level: float = _terrain.WATER_LEVEL if _terrain.get("WATER_LEVEL") != null else -1.35

	var center_biome := _get_biome_at(ox + CHUNK_SIZE * 0.5, oz + CHUNK_SIZE * 0.5)
	var max_for_biome := 5
	match center_biome:
		"floresta":
			max_for_biome = MAX_TREES_PER_CHUNK
		"montanha", "montanha_nevada":
			max_for_biome = 7
		"lago", "praia":
			max_for_biome = 1
		_:
			max_for_biome = 5

	var placed_points: Array[Vector2] = []
	var attempts := MAX_TREES_PER_CHUNK * 3
	for _i in range(attempts):
		if spawns.size() >= MAX_TREES_PER_CHUNK or spawns.size() >= max_for_biome:
			break
		var lx := rng.randf_range(1.5, CHUNK_SIZE - 1.5)
		var lz := rng.randf_range(1.5, CHUNK_SIZE - 1.5)
		var wx := ox + lx
		var wz := oz + lz
		var p2 := Vector2(wx, wz)

		if p2.distance_to(Vector2(-4.0, -42.0)) < 14.0:
			continue

		var wy: float = _terrain.height_at(wx, wz)
		if wy < water_level + 0.35:
			continue

		var biome := _get_biome_at(wx, wz)
		if biome == "lago" or biome == "praia":
			continue

		var density_chance := 0.32
		var is_pine := false
		var min_dist_sq := 24.0
		var scale_min := 1.05
		var scale_max := 1.45

		match biome:
			"floresta":
				density_chance = 0.88
				is_pine = rng.randf() < 0.25
				min_dist_sq = 16.0
				scale_min = 1.15
				scale_max = 1.60
			"montanha", "montanha_nevada":
				density_chance = 0.50
				is_pine = true
				min_dist_sq = 20.0
				scale_min = 1.10
				scale_max = 1.50
			_:
				density_chance = 0.25
				is_pine = rng.randf() < 0.15
				min_dist_sq = 30.0
				scale_min = 1.00
				scale_max = 1.38

		if rng.randf() > density_chance:
			continue

		var too_close := false
		for prev in placed_points:
			if prev.distance_squared_to(p2) < min_dist_sq:
				too_close = true
				break
		if too_close:
			continue

		placed_points.append(p2)
		var scale_factor := rng.randf_range(scale_min, scale_max)
		var yaw := rng.randf() * TAU
		var variant_idx := rng.randi()
		spawns.append({
			"pos": Vector3(wx, wy - 0.06, wz),
			"scale": Vector3.ONE * scale_factor,
			"yaw": yaw,
			"variant": variant_idx,
			"pine": is_pine,
			"biome": biome
		})

	return spawns

func generate_chunk_population_preview(coord: Vector2i) -> Dictionary:
	var trees := compute_chunk_tree_spawns(coord)
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
	_update_chunk_lod_visibility(center)
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
		_chunk_tree_nodes.erase(coord)
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
		_update_chunk_lod_visibility(center)

	if created > 0 or deleted > 0 or center != _last_center_chunk:
		_last_center_chunk = center
		if created > 0 or deleted > 0:
			print("[CHUNKS] ativos: ", _active_chunks.size(), ", criados: ", created, ", apagados: ", deleted)

func _update_chunk_lod_visibility(center: Vector2i) -> void:
	for coord in _chunk_grass_nodes.keys():
		var grass_node: MultiMeshInstance3D = _chunk_grass_nodes[coord]
		if is_instance_valid(grass_node):
			var dist := maxi(absi(coord.x - center.x), absi(coord.y - center.y))
			grass_node.visible = dist < GRASS_CHUNK_MAX_DIST
	for coord in _chunk_tree_nodes.keys():
		var tree_node: Node3D = _chunk_tree_nodes[coord]
		if is_instance_valid(tree_node):
			var dist := maxi(absi(coord.x - center.x), absi(coord.y - center.y))
			tree_node.visible = dist <= TREE_CHUNK_MAX_DIST

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

	var dist := maxi(absi(coord.x - current_center.x), absi(coord.y - current_center.y))

	var trees_group := _populate_chunk_trees(chunk_root, coord)
	if trees_group != null:
		trees_group.visible = dist <= TREE_CHUNK_MAX_DIST
		_chunk_tree_nodes[coord] = trees_group

	var grass_mmi := _populate_chunk_grass(chunk_root, coord)
	grass_mmi.visible = dist < GRASS_CHUNK_MAX_DIST
	_chunk_grass_nodes[coord] = grass_mmi

	add_child(chunk_root)
	_active_chunks[coord] = chunk_root

func _populate_chunk_trees(chunk_root: Node3D, coord: Vector2i) -> Node3D:
	var tree_spawns := compute_chunk_tree_spawns(coord)
	if tree_spawns.is_empty():
		return null

	var trees_container := Node3D.new()
	trees_container.name = "ChunkTrees"
	chunk_root.add_child(trees_container)

	# Agrupa por Mesh para renderizar via MultiMeshInstance3D (1 draw call por especie no chunk)
	var buckets: Dictionary = {} # Mesh -> Array[Transform3D]
	var fallback_items: Array[Dictionary] = []

	for item in tree_spawns:
		var wants_pine: bool = bool(item.get("pine", false))
		var pool := _pine_meshes if (wants_pine and not _pine_meshes.is_empty()) else _deciduous_meshes
		if pool.is_empty() and not _pine_meshes.is_empty():
			pool = _pine_meshes

		if not pool.is_empty():
			var variant: int = int(item["variant"]) % pool.size()
			var chosen_mesh := pool[variant]
			var t := Transform3D().scaled(item["scale"]).rotated(Vector3.UP, float(item["yaw"]))
			t.origin = item["pos"]
			if not buckets.has(chosen_mesh):
				buckets[chosen_mesh] = []
			buckets[chosen_mesh].append(t)
		else:
			fallback_items.append(item)

	for mesh_key in buckets.keys():
		var t_list: Array = buckets[mesh_key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh_key
		mm.instance_count = t_list.size()
		for i in range(t_list.size()):
			mm.set_instance_transform(i, t_list[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 105.0
		trees_container.add_child(mmi)

	for item in fallback_items:
		_add_fallback_tree(trees_container, item)

	return trees_container

func _add_fallback_tree(parent: Node3D, item: Dictionary) -> void:
	var holder := Node3D.new()
	holder.position = item["pos"]
	holder.scale = item["scale"]
	holder.rotation.y = float(item["yaw"])

	var trunk := MeshInstance3D.new()
	trunk.mesh = _fallback_trunk_mesh
	trunk.position = Vector3(0.0, 1.8, 0.0)
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(trunk)

	var crown := MeshInstance3D.new()
	crown.mesh = _fallback_pine_mesh if bool(item.get("pine", false)) else _fallback_canopy_mesh
	crown.position = Vector3(0.0, 4.2, 0.0)
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(crown)

	parent.add_child(holder)

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
		if wy < water_level + 0.18:
			continue

		var biome := _get_biome_at(wx, wz)
		if biome == "lago" or biome == "praia" or biome == "montanha_nevada":
			continue
		if biome == "montanha" and rng.randf() > 0.35:
			continue

		var sc_xz := rng.randf_range(0.75, 1.15)
		var sc_y := rng.randf_range(0.26, 0.62)
		var yaw := rng.randf() * TAU
		var t := Transform3D().scaled(Vector3(sc_xz, sc_y, sc_xz)).rotated(Vector3.UP, yaw)
		t.origin = Vector3(wx, wy - 0.03, wz)
		transforms.append(t)

		var col := Color(0.86, 0.95, 0.76).lerp(Color(1.04, 1.00, 0.80), rng.randf())
		if biome == "floresta":
			col = Color(0.68, 0.84, 0.60).lerp(Color(0.82, 0.92, 0.68), rng.randf())
		colors.append(col)

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
	_fallback_trunk_mesh = CylinderMesh.new()
	_fallback_trunk_mesh.top_radius = 0.16
	_fallback_trunk_mesh.bottom_radius = 0.26
	_fallback_trunk_mesh.height = 3.6
	_fallback_trunk_mesh.radial_segments = 7
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.24, 0.14)
	trunk_mat.roughness = 0.95
	_fallback_trunk_mesh.material = trunk_mat

	_fallback_canopy_mesh = SphereMesh.new()
	_fallback_canopy_mesh.radius = 1.45
	_fallback_canopy_mesh.height = 2.6
	_fallback_canopy_mesh.radial_segments = 8
	_fallback_canopy_mesh.rings = 5
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.24, 0.46, 0.17)
	canopy_mat.roughness = 0.9
	_fallback_canopy_mesh.material = canopy_mat

	_fallback_pine_mesh = CylinderMesh.new()
	_fallback_pine_mesh.top_radius = 0.05
	_fallback_pine_mesh.bottom_radius = 1.45
	_fallback_pine_mesh.height = 3.8
	_fallback_pine_mesh.radial_segments = 7
	var pine_mat := StandardMaterial3D.new()
	pine_mat.albedo_color = Color(0.16, 0.34, 0.18)
	pine_mat.roughness = 0.9
	_fallback_pine_mesh.material = pine_mat

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_width := 0.42
	var height := 1.0
	var angles := [0.0, PI / 2.0] # 2 planos cruzados em vez de 3 (corta 33% dos triangulos da grama)
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
