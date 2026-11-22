extends Node3D
# Terreno procedural infinito (Etapa 4): agua infinita seguindo o jogador, neblina e chunks dinamicos.
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

# --- Agua infinita acompanhando o jogador ---
const INFINITE_WATER_SPAN := 280.0
const INFINITE_WATER_SNAP := 8.0

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

# --- Neblina Atmosferica e corte de visao (esconde surgimento de chunks) ---
const HORIZON_FOG_COLOR := Color(0.69, 0.86, 0.98)
const FOG_START_M := 62.0
const FOG_END_M := 116.0
const CAMERA_FAR_M := 128.0

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

var chunk_manager: Node3D
var water_plane: MeshInstance3D

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

func _ready() -> void:
	_ensure_noises_initialized()
	_load_terrain_textures()

	var shared_terrain_mat := _make_terrain_blend_material()
	var chunk_manager_script := load("res://scripts/chunk_manager.gd") as GDScript
	if chunk_manager_script != null:
		chunk_manager = chunk_manager_script.new()
		chunk_manager.name = "ChunkManager"
		chunk_manager.call("setup", self, shared_terrain_mat, WORLD_SEED)
		add_child(chunk_manager)

	var spawn_pos := _find_focus_position()
	if chunk_manager != null:
		chunk_manager.call("ensure_initial_chunks_around", spawn_pos, 1)
	_cache_active = true

	_build_infinite_water()
	_update_water_follow(spawn_pos)
	_build_clouds()
	_setup_atmosphere_fog()
	_sync_camera_clip_and_fog()
	_adjust_directional_light_bias()

func _process(_delta: float) -> void:
	var focus := _find_focus_position()
	if chunk_manager != null:
		chunk_manager.call("update_around", focus)
	_update_water_follow(focus)
	_sync_camera_clip_and_fog()

func _find_focus_position() -> Vector3:
	var root := get_parent()
	if root != null:
		var player_node := root.get_node_or_null("Player") as Node3D
		if player_node != null:
			return player_node.global_position
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return Vector3(-4.0, 0.0, -42.0)

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
	var basin := -1.85 * basin_mask
	return (hills + basin + hill_a + hill_b + lake_basin) * fade

func height_at(x: float, z: float) -> float:
	_ensure_noises_initialized()
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

func get_terrain_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
	var dz := (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()

func get_patch_mask(x: float, z: float) -> Color:
	_ensure_noises_initialized()
	var u := clampf(tint_noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	return Color(u, u, u, 1.0)

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

func _build_infinite_water() -> void:
	# Plano de agua infinito que acompanha (x, z) do jogador na altura WATER_LEVEL, sem colisao.
	var plane := PlaneMesh.new()
	plane.size = Vector2(INFINITE_WATER_SPAN, INFINITE_WATER_SPAN)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32

	water_plane = MeshInstance3D.new()
	water_plane.name = "InfiniteWaterPlane"
	water_plane.mesh = plane
	water_plane.position = Vector3(0.0, WATER_LEVEL, 0.0)
	water_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sm := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wz = v_world_pos.xz;
	vec2 uv1 = wz * 0.28 + vec2(TIME * 0.08, TIME * 0.05);
	vec2 uv2 = wz * 0.52 + vec2(-TIME * 0.06, TIME * 0.09);
	float wave = sin(uv1.x * 6.28) * cos(uv1.y * 6.28) * 0.5 + sin((uv2.x + uv2.y) * 6.28) * 0.5;

	vec3 shallow_col = vec3(0.24, 0.72, 0.74);
	vec3 deep_col = vec3(0.09, 0.42, 0.62);
	float ripple_mix = clamp(0.45 + wave * 0.25, 0.0, 1.0);
	vec3 base_col = mix(shallow_col, deep_col, ripple_mix);
	base_col += wave * 0.03;

	float shimmer = smoothstep(0.68, 0.95, wave * 0.5 + 0.5);
	ALBEDO = mix(base_col, vec3(0.86, 0.95, 0.98), shimmer * 0.35);
}
"""
	sm.shader = shader
	water_plane.material_override = sm
	add_child(water_plane)

func _update_water_follow(focus: Vector3) -> void:
	if water_plane == null:
		return
	var snapped_x := roundf(focus.x / INFINITE_WATER_SNAP) * INFINITE_WATER_SNAP
	var snapped_z := roundf(focus.z / INFINITE_WATER_SNAP) * INFINITE_WATER_SNAP
	water_plane.global_position = Vector3(snapped_x, WATER_LEVEL, snapped_z)

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

func _sync_camera_clip_and_fog() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and not is_equal_approx(cam.far, CAMERA_FAR_M):
		cam.far = CAMERA_FAR_M

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
