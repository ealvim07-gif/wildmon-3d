extends Node3D
# Terreno estilizado com WORLD_SEED deterministico, cache local, multi-textura e relva 3D.
const DEBUG_TERRAIN_UNSHADED := false
const WORLD_SEED := 82471
const CHUNK_SIZE := 32.0
const CHUNKS := 8
const CELLS := 12
const FLAT_RADIUS := 80.0
const WATER_LEVEL := -1.35
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_RADIUS := 19.0
const TEXTURE_SIZE := 256

# --- Cache de altura apenas dentro da area inicial gerada ---
const CACHE_HALF_EXTENT := 128.0
const CACHE_STEP := 2.0

# --- Escalas e contrastes das texturas do solo ---
const GRASS_SCALE_NEAR := 0.22
const GRASS_SCALE_FAR := 0.055
const DETAIL_TEX_SCALE := 0.16
const SLOPE_ROCK_START := 0.22
const SLOPE_ROCK_END := 0.48
const SHORE_SAND_BAND := 1.45
const SNOW_ALTITUDE_START := 2.2
const SNOW_ALTITUDE_END := 3.6
const TERRAIN_CONTRAST := 1.05

# --- Configuracao da Grama 3D Dinamica ---
const GRASS_COUNT := 7500
const GRASS_RADIUS := 48.0
const GRASS_UPDATE_STEP := 5.0

# --- Neblina Atmosferica ---
const HORIZON_FOG_COLOR := Color(0.69, 0.86, 0.98)
const FOG_START_M := 58.0
const FOG_END_M := 118.0

# --- Paleta procedural de reserva ---
const SOIL_DARK := Color(0.24, 0.34, 0.16)
const MOSS_BASE := Color(0.31, 0.44, 0.19)
const GRASS_OLIVE := Color(0.39, 0.54, 0.23)
const DRY_EARTH := Color(0.50, 0.45, 0.27)

var height_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var tint_noise := FastNoiseLite.new()
var _noises_ready := false

var _height_cache: Dictionary = {}
var _cache_active := false

var tex_grass: Texture2D
var tex_ground: Texture2D
var tex_rock: Texture2D
var tex_snow: Texture2D
var tex_forest: Texture2D
var _loaded_texture_names: Array[String] = []

var _grass_mm: MultiMesh
var _last_grass_center := Vector2(99999.0, 99999.0)
var _grass_offsets: PackedVector3Array
var _grass_scales: PackedVector2Array
var _grass_rotations: PackedFloat32Array
var _grass_colors: PackedColorArray

func _ensure_noises_initialized() -> void:
	if _noises_ready:
		return
	height_noise.seed = WORLD_SEED
	height_noise.frequency = 0.009
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	height_noise.fractal_octaves = 3
	height_noise.fractal_gain = 0.45
	height_noise.fractal_lacunarity = 2.0

	lake_noise.seed = WORLD_SEED ^ 0x5A17
	lake_noise.frequency = 0.012
	lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	tint_noise.seed = WORLD_SEED ^ 0x3C91
	tint_noise.frequency = 0.016
	tint_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tint_noise.fractal_octaves = 2
	_noises_ready = true

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
	_ensure_noises_initialized()
	_load_terrain_textures()
	_build_chunks()
	_cache_active = true
	_init_dynamic_grass()
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

func _compute_height_formula(x: float, z: float) -> float:
	_ensure_noises_initialized()
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

func height_at(x: float, z: float) -> float:
	_ensure_noises_initialized()
	# Usa a grade em cache apenas dentro da area ja gerada; fora dela, calcula direto pela formula.
	if _cache_active and absf(x) <= CACHE_HALF_EXTENT and absf(z) <= CACHE_HALF_EXTENT:
		var gx := int(roundf(x / CACHE_STEP))
		var gz := int(roundf(z / CACHE_STEP))
		var wx := float(gx) * CACHE_STEP
		var wz := float(gz) * CACHE_STEP
		if is_equal_approx(x, wx) and is_equal_approx(z, wz):
			var key := Vector2i(gx, gz)
			if _height_cache.has(key):
				return _height_cache[key]
			var h := _compute_height_formula(wx, wz)
			_height_cache[key] = h
			return h
	return _compute_height_formula(x, z)

func _try_load_first_existing(candidates: Array[String], fallback: Texture2D, slot_label: String) -> Texture2D:
	for file_name in candidates:
		var path := "res://assets/terrain/" + file_name
		if ResourceLoader.exists(path):
			var loaded = load(path)
			if loaded is Texture2D:
				_loaded_texture_names.append(slot_label + "=" + file_name)
				return loaded
	_loaded_texture_names.append(slot_label + "=fallback")
	return fallback

func _load_terrain_textures() -> void:
	_loaded_texture_names.clear()
	var fallback_tex := ImageTexture.create_from_image(_make_procedural_fallback_texture())

	tex_grass = _try_load_first_existing(
		["grass_color.jpg", "Grass_Color.jpg", "grass_albedo.jpg"],
		fallback_tex,
		"grass"
	)
	tex_ground = _try_load_first_existing(
		["Ground_Color.jpg", "sand_color.jpg", "dirt_color.jpg", "path_color.jpg", "mud_color.jpg"],
		tex_grass,
		"ground_sand"
	)
	tex_rock = _try_load_first_existing(
		["Rock_Color.jpg", "rock_color.jpg"],
		tex_grass,
		"rock"
	)
	tex_snow = _try_load_first_existing(
		["Snow_Color.jpg", "snow_color.jpg", "Ice_Color.jpg"],
		tex_grass,
		"snow"
	)
	tex_forest = _try_load_first_existing(
		["forest_color.jpg", "Forest_Color.jpg", "Ground_Color.jpg"],
		tex_grass,
		"forest"
	)
	print("[TERRAIN] texturas em uso: ", ", ".join(_loaded_texture_names))

func _seamless_layer(seed_offset: int, frequency: float, octaves: int) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = WORLD_SEED ^ seed_offset
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = frequency
	n.fractal_octaves = octaves
	var img := n.get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE)
	if img == null:
		return PackedByteArray()
	img.convert(Image.FORMAT_L8)
	return img.get_data()

func _make_procedural_fallback_texture() -> Image:
	var size := TEXTURE_SIZE
	var total := size * size
	var broad := _seamless_layer(0x1A2, 0.018, 2)
	var mid := _seamless_layer(0x2DD, 0.055, 3)
	var fine := _seamless_layer(0x3DF, 0.18, 2)

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
	return albedo_img

func _make_terrain_blend_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform sampler2D u_grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D u_ground_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D u_rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D u_snow_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D u_forest_tex : source_color, filter_linear_mipmap, repeat_enable;

uniform float u_grass_scale_near = 0.22;
uniform float u_grass_scale_far = 0.055;
uniform float u_detail_scale = 0.16;
uniform float u_water_level = -1.35;
uniform float u_shore_band = 1.45;
uniform float u_slope_start = 0.22;
uniform float u_slope_end = 0.48;
uniform float u_snow_start = 2.2;
uniform float u_snow_end = 3.6;
uniform float u_contrast = 1.05;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_patch_mask;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_patch_mask = COLOR.r;
}

void fragment() {
	vec2 xz = v_world_pos.xz;

	vec3 grass_near = texture(u_grass_tex, xz * u_grass_scale_near).rgb;
	vec3 grass_far = texture(u_grass_tex, xz * u_grass_scale_far + vec2(0.37, 0.61)).rgb;
	vec3 grass_col = mix(grass_near, grass_far, 0.45);

	vec3 forest_col = texture(u_forest_tex, xz * u_detail_scale).rgb;
	float forest_w = smoothstep(0.55, 0.85, v_patch_mask);
	vec3 base_col = mix(grass_col, forest_col, forest_w * 0.60);

	vec3 ground_col = texture(u_ground_tex, xz * u_detail_scale).rgb;
	float shore_w = 1.0 - smoothstep(u_water_level - 0.3, u_water_level + u_shore_band, v_world_pos.y);
	float dirt_patch = smoothstep(0.76, 0.95, 1.0 - v_patch_mask) * 0.45;
	base_col = mix(base_col, ground_col, clamp(max(shore_w, dirt_patch), 0.0, 1.0));

	vec3 rock_col = texture(u_rock_tex, xz * u_detail_scale).rgb;
	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float rock_w = smoothstep(u_slope_start, u_slope_end, slope);
	base_col = mix(base_col, rock_col, rock_w);

	vec3 snow_col = texture(u_snow_tex, xz * u_detail_scale).rgb;
	float snow_w = smoothstep(u_snow_start, u_snow_end, v_world_pos.y) * (1.0 - rock_w * 0.65);
	base_col = mix(base_col, snow_col, snow_w);

	base_col = clamp((base_col - 0.5) * u_contrast + 0.5, 0.0, 1.0);
	ALBEDO = base_col * mix(vec3(0.86, 0.90, 0.82), vec3(0.98, 0.97, 0.90), v_patch_mask);
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
"""
	sm.shader = shader
	sm.set_shader_parameter("u_grass_tex", tex_grass)
	sm.set_shader_parameter("u_ground_tex", tex_ground)
	sm.set_shader_parameter("u_rock_tex", tex_rock)
	sm.set_shader_parameter("u_snow_tex", tex_snow)
	sm.set_shader_parameter("u_forest_tex", tex_forest)

	sm.set_shader_parameter("u_grass_scale_near", GRASS_SCALE_NEAR)
	sm.set_shader_parameter("u_grass_scale_far", GRASS_SCALE_FAR)
	sm.set_shader_parameter("u_detail_scale", DETAIL_TEX_SCALE)
	sm.set_shader_parameter("u_water_level", WATER_LEVEL)
	sm.set_shader_parameter("u_shore_band", SHORE_SAND_BAND)
	sm.set_shader_parameter("u_slope_start", SLOPE_ROCK_START)
	sm.set_shader_parameter("u_slope_end", SLOPE_ROCK_END)
	sm.set_shader_parameter("u_snow_start", SNOW_ALTITUDE_START)
	sm.set_shader_parameter("u_snow_end", SNOW_ALTITUDE_END)
	sm.set_shader_parameter("u_contrast", TERRAIN_CONTRAST)
	return sm

func _patch_mask_at(x: float, z: float) -> Color:
	_ensure_noises_initialized()
	var u := clampf(tint_noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	return Color(u, u, u, 1.0)

func _make_fine_grass_texture() -> ImageTexture:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED ^ 0x16062

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
	rng.seed = WORLD_SEED ^ 0xBD0CB
	for i in range(GRASS_COUNT):
		var r := sqrt(rng.randf()) * GRASS_RADIUS
		var theta := rng.randf() * TAU
		_grass_offsets[i] = Vector3(cos(theta) * r, 0.0, sin(theta) * r)
		_grass_scales[i] = Vector2(rng.randf_range(0.75, 1.15), rng.randf_range(0.26, 0.64))
		_grass_rotations[i] = rng.randf() * TAU
		_grass_colors[i] = Color(0.86, 0.95, 0.76).lerp(Color(1.05, 1.00, 0.80), rng.randf())

	var grass_node := MultiMeshInstance3D.new()
	grass_node.name = "StylizedGrassField"
	grass_node.multimesh = _grass_mm
	grass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass_node)

func _update_grass_around(center: Vector2) -> void:
	_last_grass_center = center
	var span := GRASS_RADIUS * 2.0
	var idx := 0
	for i in range(GRASS_COUNT):
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
		_grass_mm.set_instance_transform(idx, t)
		_grass_mm.set_instance_color(idx, _grass_colors[i])
		idx += 1
	_grass_mm.visible_instance_count = idx

func _terrain_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
	var dz := (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()

func _build_chunks() -> void:
	var shared_terrain_mat := _make_terrain_blend_material()
	for cx in range(CHUNKS):
		for cz in range(CHUNKS):
			var ox: float = (float(cx) - CHUNKS * 0.5) * CHUNK_SIZE
			var oz: float = (float(cz) - CHUNKS * 0.5) * CHUNK_SIZE
			_build_chunk(ox, oz, shared_terrain_mat)
	_make_marker_rock(18.0, -42.0, Vector3(0.65, 0.42, 0.58))
	_make_marker_rock(34.0, -42.0, Vector3(0.9, 0.55, 0.75))
	_make_marker_rock(50.0, -42.0, Vector3(1.1, 0.7, 0.9))
	_make_marker_rock(56.0, -36.0, Vector3(0.7, 0.45, 0.65))

func _build_chunk(ox: float, oz: float, shared_mat: Material) -> void:
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
			var wy := _compute_height_formula(wx, wz)
			pts[idx] = Vector3(wx, wy, wz)
			norms[idx] = _terrain_normal(wx, wz)
			masks[idx] = _patch_mask_at(wx, wz)

			# Preenche a grade de cache para pontos alinhados dentro da area gerada
			if absf(wx) <= CACHE_HALF_EXTENT and absf(wz) <= CACHE_HALF_EXTENT:
				var cgx := int(roundf(wx / CACHE_STEP))
				var cgz := int(roundf(wz / CACHE_STEP))
				if is_equal_approx(wx, float(cgx) * CACHE_STEP) and is_equal_approx(wz, float(cgz) * CACHE_STEP):
					_height_cache[Vector2i(cgx, cgz)] = wy

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
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.material_override = shared_mat
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