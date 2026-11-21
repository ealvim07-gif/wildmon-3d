extends Node3D
# Terreno estilizado com tapete de grama baixa/rasteira 3D, capim florido, lago e neblina para Android.
const DEBUG_TERRAIN_UNSHADED := false
const CHUNK_SIZE := 32.0
const CHUNKS := 8
const CELLS := 12
const FLAT_RADIUS := 80.0
const WATER_LEVEL := -1.35
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_RADIUS := 19.0
const TEXTURE_SIZE := 256
const TEXTURE_REPEAT_M := 1.4

# --- Camada 1: Capim alto e florido (destaque visual) ---
const TALL_GRASS_COUNT := 3400
const TALL_GRASS_RADIUS := 52.0

# --- Camada 2: Grama baixa e rasteira (cobre 100% do chao e elimina a "chapa verde") ---
const LOW_GRASS_COUNT := 11500
const LOW_GRASS_RADIUS := 42.0
const GRASS_UPDATE_STEP := 5.0

# --- Neblina Atmosferica ---
const HORIZON_FOG_COLOR := Color(0.69, 0.86, 0.98)
const FOG_START_M := 56.0
const FOG_END_M := 116.0

# --- Paleta natural de relva rasteira (sem chapa lisa) ---
const SOIL_DARK := Color(0.18, 0.24, 0.11)
const MOSS_BASE := Color(0.24, 0.36, 0.14)
const GRASS_OLIVE := Color(0.34, 0.48, 0.18)
const GRASS_FRESH := Color(0.45, 0.60, 0.22)
const DRY_EARTH := Color(0.42, 0.37, 0.21)
const TINT_LOW := Color(0.84, 0.90, 0.74)
const TINT_HIGH := Color(1.00, 0.96, 0.82)
const GROUND_TINT := Color(0.92, 0.95, 0.86)

var height_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var tint_noise := FastNoiseLite.new()
var ground_albedo_tex: Texture2D
var ground_normal_tex: Texture2D

var _tall_mm: MultiMesh
var _low_mm: MultiMesh
var _last_grass_center := Vector2(99999.0, 99999.0)

var _tall_offsets: PackedVector3Array
var _tall_scales: PackedVector2Array
var _tall_rotations: PackedFloat32Array
var _tall_colors: PackedColorArray

var _low_offsets: PackedVector3Array
var _low_scales: PackedVector2Array
var _low_rotations: PackedFloat32Array
var _low_colors: PackedColorArray

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

	_build_ground_textures()
	_build_chunks()
	_init_dynamic_grass_layers()
	_update_grass_around(Vector2.ZERO)
	_build_lake()
	_build_clouds()
	_setup_atmosphere_fog()
	_adjust_directional_light_bias()

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var pos2d := Vector2(cam.global_position.x, cam.global_position.z)
		if pos2d.distance_to(_last_grass_center) >= GRASS_UPDATE_STEP:
			_update_grass_around(pos2d)

func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	if p.length() <= FLAT_RADIUS:
		return 0.0
	var fade := smoothstep(FLAT_RADIUS, FLAT_RADIUS + 22.0, p.length())
	var hills := height_noise.get_noise_2d(x, z) * 4.0
	var lake_distance := p.distance_to(LAKE_CENTER)
	var lake_basin := -3.0 * (1.0 - smoothstep(LAKE_RADIUS - 4.0, LAKE_RADIUS + 8.0, lake_distance))
	var d_a := p.distance_to(Vector2(132.0, 24.0)) / 24.0
	var d_b := p.distance_to(Vector2(94.0, -32.0)) / 23.0
	var hill_a := 3.8 * exp(-d_a * 2.0)
	var hill_b := 3.5 * exp(-d_b * 2.0)
	var basin_mask := smoothstep(0.50, 0.68, lake_noise.get_noise_2d(x, z))
	var basin := -0.8 * basin_mask
	return (hills + basin + hill_a + hill_b + lake_basin) * fade

func _tint_at(x: float, z: float) -> Color:
	var u := tint_noise.get_noise_2d(x, z) * 0.5 + 0.5
	var base := TINT_LOW.lerp(TINT_HIGH, clampf(u, 0.0, 1.0))
	var lake_dist := Vector2(x, z).distance_to(LAKE_CENTER)
	var shore_sand := 1.0 - smoothstep(LAKE_RADIUS - 2.0, LAKE_RADIUS + 5.5, lake_dist)
	return base.lerp(Color(1.08, 1.00, 0.80), shore_sand * 0.72)

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

func _build_ground_textures() -> void:
	# Gera textura densa de relva rasteira + Normal Map para dar relevo real entre os talos
	var size := TEXTURE_SIZE
	var total := size * size
	var broad := _seamless_layer(418, 0.025, 2)
	var fine := _seamless_layer(991, 0.35, 3)

	var albedo_bytes := PackedByteArray()
	albedo_bytes.resize(total * 4)
	var heights := PackedFloat32Array()
	heights.resize(total)

	var inv := TAU / float(size)
	for y in range(size):
		var fy := float(y) * inv
		for x in range(size):
			var fx := float(x) * inv
			var i := y * size + x
			var b := float(broad[i]) / 255.0 if broad.size() == total else 0.5
			var f := float(fine[i]) / 255.0 if fine.size() == total else 0.5

			# Micro-laminas de grama rasteira em alta frequencia
			var micro_a := sin(fx * 34.0 + fy * 11.0 + f * 4.5) * 0.5 + 0.5
			var micro_b := cos(fx * 15.0 - fy * 31.0 - f * 3.8) * 0.5 + 0.5
			var h_val := clampf(micro_a * 0.45 + micro_b * 0.35 + f * 0.20, 0.0, 1.0)
			heights[i] = h_val

			var col: Color
			if h_val < 0.32:
				col = SOIL_DARK.lerp(MOSS_BASE, h_val / 0.32)
			elif h_val < 0.72:
				col = MOSS_BASE.lerp(GRASS_OLIVE, (h_val - 0.32) / 0.40)
			else:
				col = GRASS_OLIVE.lerp(GRASS_FRESH, (h_val - 0.72) / 0.28)
			col = col.lerp(DRY_EARTH, smoothstep(0.65, 0.92, b) * 0.42)

			var j := i * 4
			albedo_bytes[j] = int(col.r * 255.0)
			albedo_bytes[j + 1] = int(col.g * 255.0)
			albedo_bytes[j + 2] = int(col.b * 255.0)
			albedo_bytes[j + 3] = 255

	var albedo_img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, albedo_bytes)
	albedo_img.generate_mipmaps()
	ground_albedo_tex = ImageTexture.create_from_image(albedo_img)

	# Normal map a partir da altura das micro-folhas
	var norm_bytes := PackedByteArray()
	norm_bytes.resize(total * 4)
	for y in range(size):
		var ym := (y - 1 + size) % size
		var yp := (y + 1) % size
		for x in range(size):
			var xm := (x - 1 + size) % size
			var xp := (x + 1) % size
			var dx := (heights[y * size + xp] - heights[y * size + xm]) * 2.4
			var dy := (heights[yp * size + x] - heights[ym * size + x]) * 2.4
			var n := Vector3(-dx, -dy, 1.0).normalized()
			var j := (y * size + x) * 4
			norm_bytes[j] = int((n.x * 0.5 + 0.5) * 255.0)
			norm_bytes[j + 1] = int((n.y * 0.5 + 0.5) * 255.0)
			norm_bytes[j + 2] = int((n.z * 0.5 + 0.5) * 255.0)
			norm_bytes[j + 3] = 255

	var norm_img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, norm_bytes)
	norm_img.generate_mipmaps()
	ground_normal_tex = ImageTexture.create_from_image(norm_img)

func _make_low_grass_texture() -> ImageTexture:
	# Tufo baixo, largo e cheio de folhinhas abertas para cobrir o solo como tapete natural
	var w := 128
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 445566

	for b in range(42):
		var base_x := rng.randf_range(12.0, float(w - 12))
		var spread := rng.randf_range(-34.0, 34.0)
		var tip_x := clampf(base_x + spread, 4.0, float(w - 4))
		var blade_h := rng.randf_range(34.0, 82.0)
		var base_w := rng.randf_range(4.5, 8.0)

		var col_base := Color(0.24, 0.38, 0.14).lerp(Color(0.32, 0.48, 0.18), rng.randf())
		var col_tip := Color(0.46, 0.64, 0.24).lerp(Color(0.62, 0.76, 0.30), rng.randf())

		var steps := int(blade_h)
		for s in range(steps):
			var t := float(s) / maxf(1.0, blade_h)
			var y := h - 1 - s
			if y < 0:
				break
			# Folhas rasteiras arqueadas para fora
			var arch := pow(t, 1.35)
			var cx := lerpf(base_x, tip_x, arch)
			var half_w := maxf(1.1, base_w * (1.0 - t * 0.82))
			var c := col_base.lerp(col_tip, t)

			var x0 := clampi(int(cx - half_w), 0, w - 1)
			var x1 := clampi(int(cx + half_w), 0, w - 1)
			for px in range(x0, x1 + 1):
				img.set_pixel(px, y, Color(c.r, c.g, c.b, 1.0))

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_tall_grass_texture() -> ImageTexture:
	# Capim alto com espigas floridas amarelas e rosadas
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	for b in range(24):
		var base_x := rng.randf_range(16.0, float(w - 16))
		var tip_x := base_x + rng.randf_range(-24.0, 24.0)
		var blade_h := rng.randf_range(56.0, 118.0)
		var base_w := rng.randf_range(4.0, 6.8)
		var has_flower := rng.randf() < 0.38
		var is_pink_flower := rng.randf() < 0.45

		var col_base := Color(0.28, 0.42, 0.18).lerp(Color(0.36, 0.52, 0.22), rng.randf())
		var col_tip := Color(0.56, 0.72, 0.28).lerp(Color(0.76, 0.84, 0.36), rng.randf())
		var flower_col := Color(0.92, 0.66, 0.64) if is_pink_flower else Color(0.98, 0.91, 0.44)

		var steps := int(blade_h)
		for s in range(steps):
			var t := float(s) / maxf(1.0, blade_h)
			var y := h - 1 - s
			if y < 0:
				break
			var curve := sin(t * PI * 0.5)
			var cx := lerpf(base_x, tip_x, curve * curve)
			var half_w := maxf(1.0, base_w * (1.0 - t * 0.84))
			var c := col_base.lerp(col_tip, t)
			if has_flower and t > 0.58:
				var bud := sin(t * 44.0) * 0.5 + 0.5
				half_w += bud * 2.4
				c = c.lerp(flower_col, 0.78 + bud * 0.22)

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

func _make_grass_shader_material(tex: Texture2D, fade_start: float, fade_end: float, wind_amp: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap;
uniform float u_fade_start = 36.0;
uniform float u_fade_end = 52.0;
uniform float u_wind_amp = 0.14;

void vertex() {
	float sway_mask = 1.0 - UV.y;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.9 + world_pos.x * 0.34 + world_pos.z * 0.28) * u_wind_amp;
	VERTEX.x += gust * sway_mask;
	VERTEX.z += gust * 0.65 * sway_mask;
}

void fragment() {
	vec4 tex = texture(grass_tex, UV);
	if (tex.a < 0.42) {
		discard;
	}
	float cam_dist = length(VERTEX);
	float dist_fade = 1.0 - smoothstep(u_fade_start, u_fade_end, cam_dist);
	if (dist_fade < 0.05) {
		discard;
	}
	float height_grad = clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 root_shade = vec3(0.56, 0.64, 0.42);
	vec3 sun_lit = vec3(1.06, 1.05, 0.94);
	vec3 light_tint = mix(root_shade, sun_lit, smoothstep(0.0, 0.72, height_grad));
	ALBEDO = tex.rgb * COLOR.rgb * light_tint;
}
"""
	mat.shader = shader
	mat.set_shader_parameter("grass_tex", tex)
	mat.set_shader_parameter("u_fade_start", fade_start)
	mat.set_shader_parameter("u_fade_end", fade_end)
	mat.set_shader_parameter("u_wind_amp", wind_amp)
	return mat

func _init_dynamic_grass_layers() -> void:
	# 1. Camada Rasteira Densa (cobre toda a superficie do solo)
	var low_mesh := _build_star_tuft_mesh(0.95, 1.0)
	low_mesh.surface_set_material(0, _make_grass_shader_material(_make_low_grass_texture(), 26.0, LOW_GRASS_RADIUS, 0.05))

	_low_mm = MultiMesh.new()
	_low_mm.transform_format = MultiMesh.TRANSFORM_3D
	_low_mm.use_colors = true
	_low_mm.mesh = low_mesh
	_low_mm.instance_count = LOW_GRASS_COUNT

	_low_offsets.resize(LOW_GRASS_COUNT)
	_low_scales.resize(LOW_GRASS_COUNT)
	_low_rotations.resize(LOW_GRASS_COUNT)
	_low_colors.resize(LOW_GRASS_COUNT)

	var rng := RandomNumberGenerator.new()
	rng.seed = 112233
	for i in range(LOW_GRASS_COUNT):
		var r := sqrt(rng.randf()) * LOW_GRASS_RADIUS
		var theta := rng.randf() * TAU
		_low_offsets[i] = Vector3(cos(theta) * r, 0.0, sin(theta) * r)
		# Bem baixinha (16 a 28 cm) e larga para fechar o tapete no chao
		_low_scales[i] = Vector2(rng.randf_range(1.15, 1.75), rng.randf_range(0.16, 0.28))
		_low_rotations[i] = rng.randf() * TAU
		_low_colors[i] = Color(0.84, 0.94, 0.74).lerp(Color(1.04, 1.00, 0.80), rng.randf())

	var low_node := MultiMeshInstance3D.new()
	low_node.name = "LowCarpetGrassField"
	low_node.multimesh = _low_mm
	low_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(low_node)

	# 2. Camada Alta Florida (moitas de destaque)
	var tall_mesh := _build_star_tuft_mesh(0.65, 1.0)
	tall_mesh.surface_set_material(0, _make_grass_shader_material(_make_tall_grass_texture(), 36.0, TALL_GRASS_RADIUS, 0.16))

	_tall_mm = MultiMesh.new()
	_tall_mm.transform_format = MultiMesh.TRANSFORM_3D
	_tall_mm.use_colors = true
	_tall_mm.mesh = tall_mesh
	_tall_mm.instance_count = TALL_GRASS_COUNT

	_tall_offsets.resize(TALL_GRASS_COUNT)
	_tall_scales.resize(TALL_GRASS_COUNT)
	_tall_rotations.resize(TALL_GRASS_COUNT)
	_tall_colors.resize(TALL_GRASS_COUNT)

	rng.seed = 774411
	for i in range(TALL_GRASS_COUNT):
		var r := sqrt(rng.randf()) * TALL_GRASS_RADIUS
		var theta := rng.randf() * TAU
		_tall_offsets[i] = Vector3(cos(theta) * r, 0.0, sin(theta) * r)
		_tall_scales[i] = Vector2(rng.randf_range(0.95, 1.45), rng.randf_range(0.52, 0.98))
		_tall_rotations[i] = rng.randf() * TAU
		_tall_colors[i] = Color(0.86, 0.96, 0.76).lerp(Color(1.08, 1.02, 0.78), rng.randf())

	var tall_node := MultiMeshInstance3D.new()
	tall_node.name = "TallFloweringGrassField"
	tall_node.multimesh = _tall_mm
	tall_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tall_node)

func _update_grass_around(center: Vector2) -> void:
	_last_grass_center = center

	# Atualiza grama baixa/rasteira
	var low_span := LOW_GRASS_RADIUS * 2.0
	var low_idx := 0
	for i in range(LOW_GRASS_COUNT):
		var wx := center.x + fposmod((_low_offsets[i].x - center.x) + LOW_GRASS_RADIUS, low_span) - LOW_GRASS_RADIUS
		var wz := center.y + fposmod((_low_offsets[i].z - center.y) + LOW_GRASS_RADIUS, low_span) - LOW_GRASS_RADIUS
		var p := Vector2(wx, wz)
		if p.distance_to(center) > LOW_GRASS_RADIUS:
			continue
		if p.distance_to(LAKE_CENTER) < LAKE_RADIUS + 1.8:
			continue
		var y := height_at(wx, wz)
		if y < WATER_LEVEL + 0.12:
			continue
		var sc := _low_scales[i]
		var t := Transform3D().scaled(Vector3(sc.x, sc.y, sc.x)).rotated(Vector3.UP, _low_rotations[i])
		t.origin = Vector3(wx, y - 0.02, wz)
		_low_mm.set_instance_transform(low_idx, t)
		_low_mm.set_instance_color(low_idx, _low_colors[i])
		low_idx += 1
	_low_mm.visible_instance_count = low_idx

	# Atualiza capim alto florido
	var tall_span := TALL_GRASS_RADIUS * 2.0
	var tall_idx := 0
	for i in range(TALL_GRASS_COUNT):
		var wx := center.x + fposmod((_tall_offsets[i].x - center.x) + TALL_GRASS_RADIUS, tall_span) - TALL_GRASS_RADIUS
		var wz := center.y + fposmod((_tall_offsets[i].z - center.y) + TALL_GRASS_RADIUS, tall_span) - TALL_GRASS_RADIUS
		var p := Vector2(wx, wz)
		if p.distance_to(center) > TALL_GRASS_RADIUS:
			continue
		if p.distance_to(LAKE_CENTER) < LAKE_RADIUS + 2.4:
			continue
		var y := height_at(wx, wz)
		if y < WATER_LEVEL + 0.18:
			continue
		var sc := _tall_scales[i]
		var t := Transform3D().scaled(Vector3(sc.x, sc.y, sc.x)).rotated(Vector3.UP, _tall_rotations[i])
		t.origin = Vector3(wx, y - 0.04, wz)
		_tall_mm.set_instance_transform(tall_idx, t)
		_tall_mm.set_instance_color(tall_idx, _tall_colors[i])
		tall_idx += 1
	_tall_mm.visible_instance_count = tall_idx

func _terrain_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
	var dz := (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()

func _build_chunks() -> void:
	for cx in range(CHUNKS):
		for cz in range(CHUNKS):
			var ox: float = (float(cx) - CHUNKS * 0.5) * CHUNK_SIZE
			var oz: float = (float(cz) - CHUNKS * 0.5) * CHUNK_SIZE
			_build_chunk(ox, oz)
	_make_marker_rock(18.0, -42.0, Vector3(0.65, 0.42, 0.58))
	_make_marker_rock(34.0, -42.0, Vector3(0.9, 0.55, 0.75))
	_make_marker_rock(50.0, -42.0, Vector3(1.1, 0.7, 0.9))
	_make_marker_rock(56.0, -36.0, Vector3(0.7, 0.45, 0.65))

func _build_chunk(ox: float, oz: float) -> void:
	var stride := CELLS + 1
	var count := stride * stride
	var pts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tints := PackedColorArray()
	pts.resize(count)
	norms.resize(count)
	tints.resize(count)

	var cell_step := CHUNK_SIZE / float(CELLS)
	for gz in range(stride):
		var wz := oz + float(gz) * cell_step
		for gx in range(stride):
			var wx := ox + float(gx) * cell_step
			var idx := gz * stride + gx
			pts[idx] = Vector3(wx, height_at(wx, wz), wz)
			norms[idx] = _terrain_normal(wx, wz)
			tints[idx] = _tint_at(wx, wz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(CELLS):
		for x in range(CELLS):
			var i00 := z * stride + x
			var i10 := i00 + 1
			var i01 := (z + 1) * stride + x
			var i11 := i01 + 1

			st.set_color(tints[i00]); st.set_normal(norms[i00]); st.add_vertex(pts[i00])
			st.set_color(tints[i10]); st.set_normal(norms[i10]); st.add_vertex(pts[i10])
			st.set_color(tints[i01]); st.set_normal(norms[i01]); st.add_vertex(pts[i01])

			st.set_color(tints[i10]); st.set_normal(norms[i10]); st.add_vertex(pts[i10])
			st.set_color(tints[i11]); st.set_normal(norms[i11]); st.add_vertex(pts[i11])
			st.set_color(tints[i01]); st.set_normal(norms[i01]); st.add_vertex(pts[i01])

	var mesh := st.commit()
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ground_albedo_tex
	mat.normal_enabled = true
	mat.normal_texture = ground_normal_tex
	mat.normal_scale = 1.25
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.vertex_color_use_as_albedo = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / TEXTURE_REPEAT_M, 1.0 / TEXTURE_REPEAT_M, 1.0 / TEXTURE_REPEAT_M)
	mat.albedo_color = GROUND_TINT
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if DEBUG_TERRAIN_UNSHADED else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	ground.material_override = mat
	add_child(ground)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var trimesh := mesh.create_trimesh_shape()
	trimesh.backface_collision = true
	cs.shape = trimesh
	body.add_child(cs)
	add_child(body)

func _build_clouds() -> void:
	# Cupula ampla sem borda de arco visivel no ceu
	var dome := MeshInstance3D.new()
	dome.name = "StylizedCloudDome"
	var sphere := SphereMesh.new()
	sphere.radius = 380.0
	sphere.height = 340.0
	sphere.radial_segments = 40
	sphere.rings = 20
	dome.mesh = sphere
	dome.position = Vector3(0.0, -25.0, 0.0)
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
	float zenith_fade = 1.0 - smoothstep(0.55, 0.92, pos_h);

	vec3 base_shadow = vec3(0.75, 0.85, 0.96);
	vec3 sunlit_top = vec3(1.00, 0.99, 0.95);
	float shade = smoothstep(0.45, 0.72, density + (pos_h * 0.18));
	vec3 cloud_col = mix(base_shadow, sunlit_top, shade);

	vec3 horizon_haze = vec3(0.69, 0.86, 0.98);
	float haze_band = 1.0 - smoothstep(0.0, 0.15, pos_h);

	ALBEDO = mix(cloud_col, horizon_haze, haze_band * 0.88);
	ALPHA = max(cloud_alpha * horizon_cloud_fade * zenith_fade * 0.92, haze_band * 0.90);
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
	env.fog_density = 1.0
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
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap;

void fragment() {
	float shore = COLOR.r;
	float depth_factor = COLOR.g;

	vec2 uv1 = UV * 3.5 + vec2(TIME * 0.08, TIME * 0.05);
	vec2 uv2 = UV * 6.0 + vec2(-TIME * 0.06, TIME * 0.09);
	float wave = sin(uv1.x * 6.28) * cos(uv1.y * 6.28) * 0.5 + sin((uv2.x + uv2.y) * 6.28) * 0.5;

	vec3 shallow_col = vec3(0.22, 0.66, 0.68);
	vec3 deep_col = vec3(0.07, 0.34, 0.52);
	vec3 base_col = mix(shallow_col, deep_col, depth_factor);
	base_col += wave * 0.035;

	float foam_line = smoothstep(0.45, 0.92, shore + wave * 0.12);
	vec3 final_col = mix(base_col, vec3(0.86, 0.95, 0.96), foam_line * 0.65);

	ALBEDO = final_col;
	ROUGHNESS = 0.22;
	METALLIC = 0.05;
	SPECULAR = 0.65;
	ALPHA = clamp(mix(0.55, 0.92, depth_factor) + foam_line * 0.25, 0.0, 1.0);
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