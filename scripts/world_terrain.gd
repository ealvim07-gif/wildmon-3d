extends Node3D
# Terreno por chunks, agua do lago e nuvens estilizadas otimizadas para Android.
const DEBUG_TERRAIN_UNSHADED := false
const CHUNK_SIZE := 32.0
const CHUNKS := 8
const CELLS := 12
const FLAT_RADIUS := 80.0
const WATER_LEVEL := -1.35
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_RADIUS := 19.0
const TEXTURE_SIZE := 256
const TEXTURE_REPEAT_M := 3.2
const GRASS_ALBEDO_PATH := "res://assets/terrain/grass_albedo.jpg"
const GRASS_NORMAL_PATH := "res://assets/terrain/grass_normal.jpg"

# --- Paleta de grama estilizada (Legends: Arceus) ---
const GRASS_DEEP := Color(0.18, 0.34, 0.13)
const GRASS_DARK := Color(0.25, 0.44, 0.17)
const GRASS_MID := Color(0.38, 0.58, 0.23)
const GRASS_LIGHT := Color(0.58, 0.72, 0.32)
const GRASS_TIP := Color(0.72, 0.80, 0.40)
const GRASS_DRY := Color(0.72, 0.65, 0.34)
const GRASS_DIRT := Color(0.46, 0.36, 0.23)
const TINT_LOW := Color(0.84, 0.92, 0.74)
const TINT_HIGH := Color(1.00, 0.97, 0.84)
const GROUND_TINT := Color(0.95, 0.97, 0.92)

var height_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var tint_noise := FastNoiseLite.new()
var grass_texture: Texture2D
var grass_normal: Texture2D

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
	_load_grass_textures()
	_build_chunks()
	_build_lake()
	_build_clouds()
	_diagnose_terrain_cover()
	_adjust_directional_light_bias()

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

func _load_grass_textures() -> void:
	if ResourceLoader.exists(GRASS_ALBEDO_PATH):
		var photo = load(GRASS_ALBEDO_PATH)
		if photo is Texture2D:
			grass_texture = photo
			if ResourceLoader.exists(GRASS_NORMAL_PATH):
				var normal_photo = load(GRASS_NORMAL_PATH)
				if normal_photo is Texture2D:
					grass_normal = normal_photo
			print("[TERRAIN] Textura do chao: foto ", GRASS_ALBEDO_PATH)
			return
	grass_texture = ImageTexture.create_from_image(_make_grass_texture())
	print("[TERRAIN] Textura do chao: grama estilizada com laminas")

func _tint_at(x: float, z: float) -> Color:
	var u := tint_noise.get_noise_2d(x, z) * 0.5 + 0.5
	return TINT_LOW.lerp(TINT_HIGH, clampf(u, 0.0, 1.0))

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

func _make_grass_texture() -> Image:
	var size := TEXTURE_SIZE
	var total := size * size
	var broad := _seamless_layer(418, 0.015, 2)
	var tuft := _seamless_layer(733, 0.055, 3)
	var blade_noise := _seamless_layer(991, 0.14, 2)
	if broad.size() != total or tuft.size() != total or blade_noise.size() != total:
		return _make_grass_texture_legacy()

	var data := PackedByteArray()
	data.resize(total * 4)
	var inv_size := TAU / float(size)

	for y in range(size):
		var fy := float(y) * inv_size
		for x in range(size):
			var fx := float(x) * inv_size
			var i := y * size + x
			var b := float(broad[i]) / 255.0
			var m := float(tuft[i]) / 255.0
			var n := float(blade_noise[i]) / 255.0

			# Padrao direcional de fios/laminas de grama entrelaçados (sem emendas nas bordas)
			var swirl := (n - 0.5) * 2.2 + (m - 0.5) * 1.4
			var strand_a := sin(fx * 18.0 + fy * 4.0 + swirl) * 0.5 + 0.5
			var strand_b := cos(fx * 7.0 - fy * 16.0 - swirl * 0.8) * 0.5 + 0.5
			var blades := clampf(strand_a * 0.6 + strand_b * 0.4, 0.0, 1.0)

			var shade := clampf(m * 0.52 + blades * 0.36 + (n - 0.5) * 0.18, 0.0, 1.0)
			var col: Color
			if shade < 0.25:
				col = GRASS_DEEP.lerp(GRASS_DARK, shade / 0.25)
			elif shade < 0.55:
				col = GRASS_DARK.lerp(GRASS_MID, (shade - 0.25) / 0.30)
			elif shade < 0.82:
				col = GRASS_MID.lerp(GRASS_LIGHT, (shade - 0.55) / 0.27)
			else:
				col = GRASS_LIGHT.lerp(GRASS_TIP, (shade - 0.82) / 0.18)

			# Manchas naturais de grama dourada e pequenos trechos de terra
			col = col.lerp(GRASS_DRY, smoothstep(0.60, 0.90, b) * 0.45)
			col = col.lerp(GRASS_DIRT, smoothstep(0.82, 0.96, b * 0.65 + (1.0 - blades) * 0.35) * 0.50)

			var j := i * 4
			data[j] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			data[j + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			data[j + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			data[j + 3] = 255

	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	image.generate_mipmaps()
	return image

func _make_grass_texture_legacy() -> Image:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var broad := FastNoiseLite.new(); broad.seed = 418; broad.frequency = 0.035
	var detail := FastNoiseLite.new(); detail.seed = 733; detail.frequency = 0.19
	for y in range(256):
		for x in range(256):
			var n1 := broad.get_noise_2d(float(x), float(y))
			var n2 := detail.get_noise_2d(float(x), float(y))
			var value := clampf(0.5 + n1 * 0.28 + n2 * 0.22, 0.0, 1.0)
			var color := Color(0.20, 0.38, 0.13).lerp(Color(0.52, 0.68, 0.29), value)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
	image.generate_mipmaps()
	return image

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
	# Pedras de orientacao na direcao do lago (+X)
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
	mat.albedo_texture = grass_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.vertex_color_use_as_albedo = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / TEXTURE_REPEAT_M, 1.0 / TEXTURE_REPEAT_M, 1.0 / TEXTURE_REPEAT_M)
	if grass_normal != null:
		mat.normal_enabled = true
		mat.normal_texture = grass_normal
	mat.albedo_color = GROUND_TINT
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.96
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if DEBUG_TERRAIN_UNSHADED else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.disable_receive_shadows = false
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
	# Camada de nuvens estilizadas altas e leves, movendo-se suavemente com o vento.
	var sky_clouds := MeshInstance3D.new()
	sky_clouds.name = "StylizedClouds"
	var plane := PlaneMesh.new()
	plane.size = Vector2(560.0, 560.0)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	sky_clouds.mesh = plane
	sky_clouds.position = Vector3(0.0, 68.0, 0.0)
	sky_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sm := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

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
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;
	float horizon_fade = 1.0 - smoothstep(0.58, 0.98, dist);

	vec2 wind = vec2(TIME * 0.0045, TIME * 0.0022);
	vec2 p = UV * 9.5 + wind;
	float n = fbm(p);
	float detail = fbm(p * 2.2 - wind * 1.6);
	float cloud = smoothstep(0.48, 0.76, n * 0.78 + detail * 0.22);

	vec3 shadow_tint = vec3(0.82, 0.89, 0.97);
	vec3 bright_tint = vec3(1.00, 0.99, 0.96);
	float light = smoothstep(0.45, 0.82, n);
	ALBEDO = mix(shadow_tint, bright_tint, light);
	ALPHA = cloud * horizon_fade * 0.88;
}
"""
	sm.shader = shader
	sky_clouds.material_override = sm
	add_child(sky_clouds)

func _diagnose_terrain_cover() -> void:
	print("[TERRAIN DEBUG] DEBUG_TERRAIN_UNSHADED=", DEBUG_TERRAIN_UNSHADED)
	print("[TERRAIN DEBUG] Planicie: grama estilizada com laminas + lago continuo + nuvens.")
	var found_cover := false
	var root := get_parent()
	if root:
		for node in root.get_children():
			if node == self:
				continue
			if node is MeshInstance3D and node.global_position.y >= -0.5 and node.global_position.y <= 0.5:
				found_cover = true
			if node is Node3D and node.name.to_lower().contains("plane"):
				found_cover = true
	print("[TERRAIN DEBUG] Outra malha/plano detectado na faixa de altura da planicie: ", found_cover)

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
	var lake_span := LAKE_RADIUS + 10.0
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