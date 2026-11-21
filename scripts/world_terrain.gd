extends Node3D
# Terreno estilizado com relva 3D fina, lago turquesa visivel e neblina suave para Android.
const DEBUG_TERRAIN_UNSHADED := false
const CHUNK_SIZE := 32.0
const CHUNKS := 10 # mundo de 320 m (antes 8 = 256 m). Cada chunk a mais soma 32 m.
const CELLS := 12
const FLAT_RADIUS := 80.0
const WATER_LEVEL := -1.35
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_RADIUS := 19.0
const TEXTURE_SIZE := 256
const TEXTURE_REPEAT_M := 6.0
# --- Foto de grama (opcional): coloque uma foto CC0 em assets/terrain/grass_color.jpg e ela e usada sozinha ---
const GROUND_PHOTO_PATH := "res://assets/terrain/grass_color.jpg"
const GROUND_PHOTO_REPEAT_M := 4.0
const GROUND_TINT_PHOTO := Color(0.92, 0.95, 0.88)
# --- Relevo ---
const ROLLING_HEIGHT_M := 0.35   # ondulacao suave na planicie inicial (para o chao nao parecer uma chapa)
const EDGE_RING_HEIGHT_M := 6.0  # colinas baixas no limite do mundo
const EDGE_RING_WIDTH_M := 30.0
const FAR_PLANE_M := 260.0       # distancia maxima de desenho da camera
const GRASS_SLICE := 1500        # tufos atualizados por quadro (evita travadas)

# --- Configuracao da Grama 3D (folhas finas e delicadas) ---
const GRASS_COUNT := 9000
const GRASS_RADIUS := 48.0
const GRASS_UPDATE_STEP := 5.0

# --- Neblina Atmosferica ---
const HORIZON_FOG_COLOR := Color(0.69, 0.86, 0.98)
const FOG_START_M := 80.0
const FOG_MAX_AMOUNT := 0.8 # 1.0 = o fundo vira 100% cor da neblina (parece neve); menos mantem a cor
const FOG_END_M := 220.0

# --- Paleta natural do solo (suave e sem grade) ---
const SOIL_DARK := Color(0.24, 0.34, 0.16)
const MOSS_BASE := Color(0.31, 0.44, 0.19)
const GRASS_OLIVE := Color(0.39, 0.54, 0.23)
const DRY_EARTH := Color(0.50, 0.45, 0.27)
const TINT_LOW := Color(0.86, 0.92, 0.78)
const TINT_HIGH := Color(0.98, 0.96, 0.84)
const GROUND_TINT := Color(0.84, 0.90, 0.78)

var height_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var tint_noise := FastNoiseLite.new()
var ground_albedo_tex: Texture2D
var ground_is_photo := false
var detail_noise := FastNoiseLite.new()
var patch_noise := FastNoiseLite.new()
var heights := PackedFloat32Array()
var normals_grid := PackedVector3Array()
var grid_nv := CHUNKS * CELLS + 1
var grid_step := CHUNK_SIZE / float(CELLS)
var grid_half := CHUNK_SIZE * float(CHUNKS) * 0.5
var _ground_mat: StandardMaterial3D
var _grass_cursor := 0
var _grass_write := 0
var _grass_center := Vector2.ZERO
var _grass_busy := false
var _far_cam_id := 0

var _grass_mm: MultiMesh
var _last_grass_center := Vector2(99999.0, 99999.0)
var _grass_offsets: PackedVector3Array
var _grass_scales: PackedVector2Array
var _grass_rotations: PackedFloat32Array
var _grass_colors: PackedColorArray

func _make_marker_rock(position_x: float, position_z: float, size: Vector3) -> void:
	var rock := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 1.4
	mesh.radial_segments = 7
	mesh.rings = 4
	rock.mesh = mesh
	rock.scale = size
	rock.position = Vector3(position_x, size.y * 0.55, position_z)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.48, 0.39)
	stone.roughness = 1.0
	rock.material_override = stone
	add_child(rock)

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	height_noise.seed = 82471
	height_noise.frequency = 0.009
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	height_noise.fractal_octaves = 3
	height_noise.fractal_gain = 0.45
	height_noise.fractal_lacunarity = 2.0
	lake_noise.seed = 823
	lake_noise.frequency = 0.012
	lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tint_noise.seed = 5521
	tint_noise.frequency = 0.016
	tint_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tint_noise.fractal_octaves = 2
	detail_noise.seed = 311
	detail_noise.frequency = 0.03
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.fractal_octaves = 2
	patch_noise.seed = 144
	patch_noise.frequency = 0.045
	patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	patch_noise.fractal_octaves = 2

	_sample_height_grid()
	_build_ground_texture()
	_build_chunks()
	_init_dynamic_grass()
	_grass_begin(Vector2.ZERO)
	_grass_step(GRASS_COUNT)
	_build_lake()
	_build_clouds()
	_setup_atmosphere_fog()
	_adjust_directional_light_bias()
	print("[TERRAIN] pronto em ", Time.get_ticks_msec() - t0, " ms | chunks: ", CHUNKS, " | foto de grama: ", ground_is_photo)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if cam.get_instance_id() != _far_cam_id:
		cam.far = maxf(cam.far, FAR_PLANE_M)
		_far_cam_id = cam.get_instance_id()
	var pos2d := Vector2(cam.global_position.x, cam.global_position.z)
	if _grass_busy:
		_grass_step(GRASS_SLICE)
	elif pos2d.distance_to(_last_grass_center) >= GRASS_UPDATE_STEP:
		_grass_begin(pos2d)
		_grass_step(GRASS_SLICE)

# Usada pelo jogo, arvores e grama. Dentro do mundo le a grade pre-calculada (rapido).
func height_at(x: float, z: float) -> float:
	if heights.is_empty():
		return _raw_height(x, z)
	var fx := (x + grid_half) / grid_step
	var fz := (z + grid_half) / grid_step
	if fx < 0.0 or fz < 0.0 or fx >= float(grid_nv - 1) or fz >= float(grid_nv - 1):
		return _raw_height(x, z)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := heights[iz * grid_nv + ix]
	var h10 := heights[iz * grid_nv + ix + 1]
	var h01 := heights[(iz + 1) * grid_nv + ix]
	var h11 := heights[(iz + 1) * grid_nv + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

# Formula do relevo (usada uma vez para montar a grade).
func _raw_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var dist := p.length()
	var rolling := detail_noise.get_noise_2d(x, z) * ROLLING_HEIGHT_M * 1.2
	if dist <= FLAT_RADIUS:
		return rolling
	var fade := smoothstep(FLAT_RADIUS, FLAT_RADIUS + 22.0, dist)
	var hills := height_noise.get_noise_2d(x, z) * 4.0
	var lake_distance := p.distance_to(LAKE_CENTER)
	var lake_basin := -3.0 * (1.0 - smoothstep(LAKE_RADIUS - 4.0, LAKE_RADIUS + 8.0, lake_distance))
	var d_a := p.distance_to(Vector2(132.0, 24.0)) / 24.0
	var d_b := p.distance_to(Vector2(94.0, -32.0)) / 23.0
	var hill_a := 3.8 * exp(-d_a * d_a * 2.0)
	var hill_b := 3.5 * exp(-d_b * d_b * 2.0)
	var basin_mask := smoothstep(0.50, 0.68, lake_noise.get_noise_2d(x, z))
	var basin := -0.8 * basin_mask
	var edge := smoothstep(grid_half - EDGE_RING_WIDTH_M, grid_half, maxf(absf(x), absf(z))) * EDGE_RING_HEIGHT_M
	return (hills + basin + hill_a + hill_b + lake_basin + edge) * fade + rolling * (1.0 - fade)

func _sample_height_grid() -> void:
	heights.resize(grid_nv * grid_nv)
	for gz in range(grid_nv):
		var wz := -grid_half + float(gz) * grid_step
		for gx in range(grid_nv):
			heights[gz * grid_nv + gx] = _raw_height(-grid_half + float(gx) * grid_step, wz)
	normals_grid.resize(grid_nv * grid_nv)
	for gz in range(grid_nv):
		for gx in range(grid_nv):
			var x0 := maxi(gx - 1, 0)
			var x1 := mini(gx + 1, grid_nv - 1)
			var z0 := maxi(gz - 1, 0)
			var z1 := mini(gz + 1, grid_nv - 1)
			var dx := (heights[gz * grid_nv + x1] - heights[gz * grid_nv + x0]) / (float(x1 - x0) * grid_step)
			var dz := (heights[z1 * grid_nv + gx] - heights[z0 * grid_nv + gx]) / (float(z1 - z0) * grid_step)
			normals_grid[gz * grid_nv + gx] = Vector3(-dx, 1.0, -dz).normalized()

func _tint_at(x: float, z: float, _h: float, n: Vector3) -> Color:
	var u := clampf(tint_noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var col := TINT_LOW.lerp(TINT_HIGH, u)
	var dry := smoothstep(0.58, 0.82, patch_noise.get_noise_2d(x, z) * 0.5 + 0.5)
	col = col.lerp(Color(0.86, 0.78, 0.56), dry * 0.55)
	var lush := 1.0 - smoothstep(0.20, 0.55, patch_noise.get_noise_2d(x + 410.0, z - 170.0) * 0.5 + 0.5)
	col = col.lerp(Color(0.62, 0.78, 0.52), lush * 0.45)
	var lake_dist := Vector2(x, z).distance_to(LAKE_CENTER)
	var shore_sand := 1.0 - smoothstep(LAKE_RADIUS - 2.0, LAKE_RADIUS + 5.5, lake_dist)
	col = col.lerp(Color(1.0, 0.96, 0.78), shore_sand * 0.72)
	var rock := 1.0 - smoothstep(0.88, 0.95, n.y)
	col = col.lerp(Color(0.68, 0.66, 0.60), rock * 0.8)
	return Color(clampf(col.r, 0.0, 1.0), clampf(col.g, 0.0, 1.0), clampf(col.b, 0.0, 1.0), 1.0)

func _seamless_layer(seed_value: int, frequency: float, octaves: int) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = frequency
	n.fractal_octaves = octaves
	var img := n.get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE)
	if img == null:
		return PackedByteArray()
	img.convert(Image.FORMAT_L8)
	return img.get_data()

func _build_ground_texture() -> void:
	# Se existir uma foto de grama em assets/terrain/grass_color.jpg, usa a foto (mais realista e carrega mais rapido).
	if ResourceLoader.exists(GROUND_PHOTO_PATH):
		var photo = load(GROUND_PHOTO_PATH)
		if photo is Texture2D:
			ground_albedo_tex = photo
			ground_is_photo = true
			return
	# Textura organica suave sem padrao quadriculado
	var size := TEXTURE_SIZE
	var total := size * size
	var broad := _seamless_layer(418, 0.018, 2)
	var mid := _seamless_layer(733, 0.055, 3)
	var fine := _seamless_layer(991, 0.18, 2)

	var albedo_bytes := PackedByteArray()
	albedo_bytes.resize(total * 4)

	for i in range(total):
		var b := float(broad[i]) / 255.0 if broad.size() == total else 0.5
		var m := float(mid[i]) / 255.0 if mid.size() == total else 0.5
		var f := float(fine[i]) / 255.0 if fine.size() == total else 0.5
		var h_val := clampf(m * 0.58 + f * 0.27 + b * 0.15, 0.0, 1.0)

		var col: Color
		if h_val < 0.35:
			col = SOIL_DARK.lerp(MOSS_BASE, h_val / 0.35)
		else:
			col = MOSS_BASE.lerp(GRASS_OLIVE, (h_val - 0.35) / 0.65)
		col = col.lerp(DRY_EARTH, smoothstep(0.62, 0.90, b) * 0.45)

		var j := i * 4
		albedo_bytes[j] = int(col.r * 255.0)
		albedo_bytes[j + 1] = int(col.g * 255.0)
		albedo_bytes[j + 2] = int(col.b * 255.0)
		albedo_bytes[j + 3] = 255

	var albedo_img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, albedo_bytes)
	albedo_img.generate_mipmaps()
	ground_albedo_tex = ImageTexture.create_from_image(albedo_img)

func _make_fine_grass_texture() -> ImageTexture:
	# Folhas finas, delicadas e verticais (sem faixas grossas deitadas)
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	for b in range(34):
		var base_x := rng.randf_range(16.0, float(w - 16))
		var tip_x := base_x + rng.randf_range(-14.0, 14.0)
		var blade_h := rng.randf_range(44.0, 112.0)
		var base_w := rng.randf_range(1.6, 3.0)
		var has_flower := rng.randf() < 0.24
		var is_pink_flower := rng.randf() < 0.45

		var col_base := Color(0.28, 0.44, 0.17).lerp(Color(0.36, 0.54, 0.21), rng.randf())
		var col_tip := Color(0.54, 0.72, 0.28).lerp(Color(0.72, 0.82, 0.35), rng.randf())
		var flower_col := Color(0.92, 0.66, 0.64) if is_pink_flower else Color(0.98, 0.90, 0.42)

		var steps := int(blade_h)
		for s in range(steps):
			var t := float(s) / maxf(1.0, blade_h)
			var y := h - 1 - s
			if y < 0:
				break
			var curve := sin(t * PI * 0.5)
			var cx := lerpf(base_x, tip_x, curve * curve)
			var half_w := maxf(0.5, base_w * (1.0 - t * 0.88))
			var c := col_base.lerp(col_tip, t)
			if has_flower and t > 0.66:
				var bud := sin(t * 46.0) * 0.5 + 0.5
				half_w += bud * 1.1
				c = c.lerp(flower_col, 0.75 + bud * 0.25)

			var x0 := clampi(int(cx - half_w), 0, w - 1)
			var x1 := clampi(int(cx + half_w), 0, w - 1)
			for px in range(x0, x1 + 1):
				img.set_pixel(px, y, Color(c.r, c.g, c.b, 1.0))

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_star_tuft_mesh(half_width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
	return st.commit()

func _init_dynamic_grass() -> void:
	var tuft_mesh := _build_star_tuft_mesh(0.42, 1.0)
	var mat := ShaderMaterial.new()
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
	float cam_dist = length(VERTEX);
	float dist_fade = 1.0 - smoothstep(32.0, 47.0, cam_dist);
	if (dist_fade < 0.05) {
		discard;
	}
	float height_grad = clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 root_shade = vec3(0.62, 0.70, 0.46);
	vec3 sun_lit = vec3(1.04, 1.03, 0.94);
	vec3 light_tint = mix(root_shade, sun_lit, smoothstep(0.0, 0.72, height_grad));
	ALBEDO = tex.rgb * COLOR.rgb * light_tint;
}
"""
	mat.shader = shader
	mat.set_shader_parameter("grass_tex", _make_fine_grass_texture())
	tuft_mesh.surface_set_material(0, mat)

	_grass_mm = MultiMesh.new()
	_grass_mm.transform_format = MultiMesh.TRANSFORM_3D
	_grass_mm.use_colors = true
	_grass_mm.mesh = tuft_mesh
	_grass_mm.instance_count = GRASS_COUNT

	_grass_offsets.resize(GRASS_COUNT)
	_grass_scales.resize(GRASS_COUNT)
	_grass_rotations.resize(GRASS_COUNT)
	_grass_colors.resize(GRASS_COUNT)

	var rng := RandomNumberGenerator.new()
	rng.seed = 774411
	for i in range(GRASS_COUNT):
		var r := sqrt(rng.randf()) * GRASS_RADIUS
		var theta := rng.randf() * TAU
		_grass_offsets[i] = Vector3(cos(theta) * r, 0.0, sin(theta) * r)
		# Altura variada (relva baixa de 26 cm ate capim medio de 64 cm), sem largura exagerada
		_grass_scales[i] = Vector2(rng.randf_range(0.75, 1.15), rng.randf_range(0.26, 0.64))
		_grass_rotations[i] = rng.randf() * TAU
		_grass_colors[i] = Color(0.86, 0.95, 0.76).lerp(Color(1.05, 1.00, 0.80), rng.randf())

	var grass_node := MultiMeshInstance3D.new()
	grass_node.name = "StylizedGrassField"
	grass_node.multimesh = _grass_mm
	grass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass_node)

func _grass_begin(center: Vector2) -> void:
	_last_grass_center = center
	_grass_center = center
	_grass_cursor = 0
	_grass_write = 0
	_grass_busy = true

# Atualiza so um pedaco dos tufos por quadro (nao trava ao andar).
func _grass_step(budget: int) -> void:
	if not _grass_busy:
		return
	var center := _grass_center
	var span := GRASS_RADIUS * 2.0
	var last := mini(_grass_cursor + budget, GRASS_COUNT)
	for i in range(_grass_cursor, last):
		var wx := center.x + fposmod((_grass_offsets[i].x - center.x) + GRASS_RADIUS, span) - GRASS_RADIUS
		var wz := center.y + fposmod((_grass_offsets[i].z - center.y) + GRASS_RADIUS, span) - GRASS_RADIUS
		var p := Vector2(wx, wz)
		if p.distance_to(center) > GRASS_RADIUS:
			continue
		if p.distance_to(LAKE_CENTER) < LAKE_RADIUS + 2.0:
			continue
		var y := height_at(wx, wz)
		if y < WATER_LEVEL + 0.14:
			continue
		var sc := _grass_scales[i]
		var t := Transform3D().scaled(Vector3(sc.x, sc.y, sc.x)).rotated(Vector3.UP, _grass_rotations[i])
		t.origin = Vector3(wx, y - 0.03, wz)
		_grass_mm.set_instance_transform(_grass_write, t)
		_grass_mm.set_instance_color(_grass_write, _grass_colors[i])
		_grass_write += 1
	_grass_cursor = last
	if _grass_cursor >= GRASS_COUNT:
		_grass_mm.visible_instance_count = _grass_write
		_grass_busy = false

func _terrain_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
	var dz := (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()

func _build_chunks() -> void:
	_ground_mat = _make_ground_material()
	for cx in range(CHUNKS):
		for cz in range(CHUNKS):
			_build_chunk(cx, cz)

func _make_ground_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ground_albedo_tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.vertex_color_use_as_albedo = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	var repeat_m := GROUND_PHOTO_REPEAT_M if ground_is_photo else TEXTURE_REPEAT_M
	mat.uv1_scale = Vector3(1.0 / repeat_m, 1.0 / repeat_m, 1.0 / repeat_m)
	mat.albedo_color = GROUND_TINT_PHOTO if ground_is_photo else GROUND_TINT
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if DEBUG_TERRAIN_UNSHADED else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat

func _build_chunk(cx: int, cz: int) -> void:
	var side := CELLS + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for lz in range(side):
		for lx in range(side):
			var gx := cx * CELLS + lx
			var gz := cz * CELLS + lz
			var gi := gz * grid_nv + gx
			var wx := -grid_half + float(gx) * grid_step
			var wz := -grid_half + float(gz) * grid_step
			var h := heights[gi]
			var n := normals_grid[gi]
			verts.append(Vector3(wx, h, wz))
			norms.append(n)
			cols.append(_tint_at(wx, wz, h, n))
	var indices := PackedInt32Array()
	for lz in range(CELLS):
		for lx in range(CELLS):
			var a := lz * side + lx
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(d)
			indices.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.material_override = _ground_mat
	add_child(ground)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var trimesh := mesh.create_trimesh_shape()
	trimesh.backface_collision = true
	cs.shape = trimesh
	body.add_child(cs)
	add_child(body)

func _build_clouds() -> void:
	var dome := MeshInstance3D.new()
	dome.name = "StylizedCloudDome"
	var sphere := SphereMesh.new()
	sphere.radius = 420.0
	sphere.height = 420.0
	sphere.radial_segments = 40
	sphere.rings = 20
	dome.mesh = sphere
	dome.position = Vector3(0.0, 0.0, 0.0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sm := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded, fog_disabled;

varying vec3 local_dir;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	float h = local_dir.y;
	if (h <= -0.02) {
		discard;
	}
	float pos_h = max(h, 0.001);
	vec2 sky_uv = local_dir.xz / (pos_h + 0.42);
	vec2 wind = vec2(TIME * 0.007, TIME * 0.003);
	vec2 p = sky_uv * 1.65 + wind;

	float base_n = fbm(p);
	float puff = fbm(p * 2.2 - wind * 1.3);
	float density = base_n * 0.74 + puff * 0.26;

	float cloud_alpha = smoothstep(0.46, 0.66, density);
	float horizon_cloud_fade = smoothstep(0.02, 0.16, pos_h);
	float zenith_fade = 1.0 - smoothstep(0.45, 0.85, pos_h);

	vec3 base_shadow = vec3(0.75, 0.85, 0.96);
	vec3 sunlit_top = vec3(1.00, 0.99, 0.95);
	float shade = smoothstep(0.45, 0.72, density + (pos_h * 0.18));
	vec3 cloud_col = mix(base_shadow, sunlit_top, shade);

	vec3 horizon_haze = vec3(0.69, 0.86, 0.98);
	float haze_band = 1.0 - smoothstep(0.0, 0.14, pos_h);

	ALBEDO = mix(cloud_col, horizon_haze, haze_band * 0.85);
	ALPHA = max(cloud_alpha * horizon_cloud_fade * zenith_fade * 0.92, haze_band * 0.88);
}
"""
	sm.shader = shader
	dome.material_override = sm
	add_child(dome)

func _setup_atmosphere_fog() -> void:
	var root := get_parent()
	if root == null:
		return
	var world_env := _find_world_environment(root)
	if world_env == null:
		world_env = WorldEnvironment.new()
		world_env.name = "AtmosphereWorldEnvironment"
		world_env.environment = Environment.new()
		root.add_child.call_deferred(world_env)
	elif world_env.environment == null:
		world_env.environment = Environment.new()

	var env := world_env.environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = HORIZON_FOG_COLOR
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.18
	env.fog_density = FOG_MAX_AMOUNT
	env.fog_depth_begin = FOG_START_M
	env.fog_depth_end = FOG_END_M
	env.fog_sky_affect = 0.0

func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found := _find_world_environment(child)
		if found != null:
			return found
	return null

func _adjust_directional_light_bias() -> void:
	var root := get_parent()
	if root:
		for light in _find_directional_lights(root):
			light.shadow_bias = maxf(light.shadow_bias, 0.08)
			light.shadow_normal_bias = maxf(light.shadow_normal_bias, 1.0)

func _find_directional_lights(node: Node) -> Array:
	var found: Array = []
	if node is DirectionalLight3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_directional_lights(child))
	return found

func _build_lake() -> void:
	var lake_span := LAKE_RADIUS + 4.5
	var grid := 28
	var step := (lake_span * 2.0) / float(grid)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for gz in range(grid):
		for gx in range(grid):
			var x0 := LAKE_CENTER.x - lake_span + float(gx) * step
			var z0 := LAKE_CENTER.y - lake_span + float(gz) * step
			var x1 := x0 + step
			var z1 := z0 + step

			var c00 := _water_vertex_color(x0, z0)
			var c10 := _water_vertex_color(x1, z0)
			var c01 := _water_vertex_color(x0, z1)
			var c11 := _water_vertex_color(x1, z1)

			var v00 := Vector3(x0, WATER_LEVEL, z0)
			var v10 := Vector3(x1, WATER_LEVEL, z0)
			var v01 := Vector3(x0, WATER_LEVEL, z1)
			var v11 := Vector3(x1, WATER_LEVEL, z1)

			st.set_uv(Vector2(x0 * 0.15, z0 * 0.15)); st.set_color(c00); st.set_normal(Vector3.UP); st.add_vertex(v00)
			st.set_uv(Vector2(x1 * 0.15, z0 * 0.15)); st.set_color(c10); st.set_normal(Vector3.UP); st.add_vertex(v10)
			st.set_uv(Vector2(x0 * 0.15, z1 * 0.15)); st.set_color(c01); st.set_normal(Vector3.UP); st.add_vertex(v01)

			st.set_uv(Vector2(x1 * 0.15, z0 * 0.15)); st.set_color(c10); st.set_normal(Vector3.UP); st.add_vertex(v10)
			st.set_uv(Vector2(x1 * 0.15, z1 * 0.15)); st.set_color(c11); st.set_normal(Vector3.UP); st.add_vertex(v11)
			st.set_uv(Vector2(x0 * 0.15, z1 * 0.15)); st.set_color(c01); st.set_normal(Vector3.UP); st.add_vertex(v01)

	var water := MeshInstance3D.new()
	water.name = "MainLakeWater"
	water.mesh = st.commit()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sm := ShaderMaterial.new()
	var shader := Shader.new()
	# Render mode unshaded opaco: 100% visivel no Android Compatibility sem desaparecer
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

void fragment() {
	float shore = COLOR.r;
	float depth_factor = COLOR.g;

	vec2 uv1 = UV * 3.5 + vec2(TIME * 0.08, TIME * 0.05);
	vec2 uv2 = UV * 6.0 + vec2(-TIME * 0.06, TIME * 0.09);
	float wave = sin(uv1.x * 6.28) * cos(uv1.y * 6.28) * 0.5 + sin((uv2.x + uv2.y) * 6.28) * 0.5;

	vec3 shallow_col = vec3(0.24, 0.72, 0.74);
	vec3 deep_col = vec3(0.08, 0.38, 0.58);
	vec3 base_col = mix(shallow_col, deep_col, depth_factor);
	base_col += wave * 0.035;

	float foam_line = smoothstep(0.45, 0.92, shore + wave * 0.12);
	ALBEDO = mix(base_col, vec3(0.88, 0.96, 0.98), foam_line * 0.68);
}
"""
	sm.shader = shader
	water.material_override = sm
	add_child(water)

func _water_vertex_color(x: float, z: float) -> Color:
	var ground_y := height_at(x, z)
	var depth := maxf(0.0, WATER_LEVEL - ground_y)
	var shore := 1.0 - clampf(depth / 0.55, 0.0, 1.0)
	var depth_factor := clampf(depth / 1.8, 0.0, 1.0)
	return Color(shore, depth_factor, 0.0, 1.0)