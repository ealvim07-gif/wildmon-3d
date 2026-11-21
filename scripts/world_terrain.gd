extends Node3D
# Terreno estilizado com grama 3D florida (MultiMesh), lago e nuvens suaves para Android.
const DEBUG_TERRAIN_UNSHADED := false
const CHUNK_SIZE := 32.0
const CHUNKS := 8
const CELLS := 12
const FLAT_RADIUS := 80.0
const WATER_LEVEL := -1.35
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_RADIUS := 19.0
const TEXTURE_SIZE := 256
const TEXTURE_REPEAT_M := 3.5

# --- Configuracao da Grama 3D Florida (MultiMesh leve para Android) ---
const GRASS_BLADE_COUNT := 4500
const GRASS_SPAWN_RADIUS := 68.0
const GRASS_MIN_HEIGHT := 0.48
const GRASS_MAX_HEIGHT := 0.92

# --- Paleta do solo sob a grama ---
const GRASS_DEEP := Color(0.20, 0.36, 0.14)
const GRASS_DARK := Color(0.28, 0.47, 0.19)
const GRASS_MID := Color(0.40, 0.60, 0.25)
const GRASS_LIGHT := Color(0.56, 0.72, 0.33)
const GRASS_SAND := Color(0.76, 0.71, 0.48)
const TINT_LOW := Color(0.86, 0.94, 0.78)
const TINT_HIGH := Color(1.00, 0.97, 0.85)
const GROUND_TINT := Color(0.95, 0.97, 0.92)

var height_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var tint_noise := FastNoiseLite.new()
var grass_texture: Texture2D
var _grass_multimesh_node: MultiMeshInstance3D

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
	_build_3d_grass_field()
	_build_lake()
	_build_clouds()
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
	grass_texture = ImageTexture.create_from_image(_make_ground_texture())

func _tint_at(x: float, z: float) -> Color:
	var u := tint_noise.get_noise_2d(x, z) * 0.5 + 0.5
	var base := TINT_LOW.lerp(TINT_HIGH, clampf(u, 0.0, 1.0))
	# Borda arenosa perto do lago
	var lake_dist := Vector2(x, z).distance_to(LAKE_CENTER)
	var shore_sand := 1.0 - smoothstep(LAKE_RADIUS - 2.0, LAKE_RADIUS + 5.5, lake_dist)
	return base.lerp(Color(1.05, 0.98, 0.78), shore_sand * 0.65)

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

func _make_ground_texture() -> Image:
	var size := TEXTURE_SIZE
	var total := size * size
	var broad := _seamless_layer(418, 0.015, 2)
	var tuft := _seamless_layer(733, 0.06, 3)
	var data := PackedByteArray()
	data.resize(total * 4)

	for i in range(total):
		var b := float(broad[i]) / 255.0 if broad.size() == total else 0.5
		var m := float(tuft[i]) / 255.0 if tuft.size() == total else 0.5
		var shade := clampf(m * 0.7 + b * 0.3, 0.0, 1.0)
		var col: Color
		if shade < 0.35:
			col = GRASS_DEEP.lerp(GRASS_DARK, shade / 0.35)
		elif shade < 0.70:
			col = GRASS_DARK.lerp(GRASS_MID, (shade - 0.35) / 0.35)
		else:
			col = GRASS_MID.lerp(GRASS_LIGHT, (shade - 0.70) / 0.30)
		col = col.lerp(GRASS_SAND, smoothstep(0.75, 0.95, b) * 0.35)
		var j := i * 4
		data[j] = int(col.r * 255.0)
		data[j + 1] = int(col.g * 255.0)
		data[j + 2] = int(col.b * 255.0)
		data[j + 3] = 255

	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	image.generate_mipmaps()
	return image

func _make_tuft_sprite_texture() -> ImageTexture:
	# Desenha um tufo de grama estilizada com folhas verdes e espigas amarelas/rosadas
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	# 16 laminas de grama por tufo
	for b in range(16):
		var base_x := rng.randf_range(18.0, float(w - 18))
		var tip_x := base_x + rng.randf_range(-22.0, 22.0)
		var blade_h := rng.randf_range(58.0, 114.0)
		var base_w := rng.randf_range(3.5, 6.0)
		var has_flower := rng.randf() < 0.32
		var is_pink_flower := rng.randf() < 0.45

		var col_base := Color(0.22, 0.42, 0.14).lerp(Color(0.32, 0.54, 0.18), rng.randf())
		var col_tip := Color(0.55, 0.74, 0.28).lerp(Color(0.78, 0.84, 0.36), rng.randf())
		var flower_col := Color(0.88, 0.64, 0.62) if is_pink_flower else Color(0.95, 0.88, 0.42)

		var steps := int(blade_h)
		for s in range(steps):
			var t := float(s) / maxf(1.0, blade_h)
			var y := h - 1 - s
			if y < 0:
				break
			# Curva suave da folha
			var curve := sin(t * PI * 0.5)
			var cx := lerpf(base_x, tip_x, curve * curve)
			var half_w := maxf(0.8, base_w * (1.0 - t * 0.88))
			var c := col_base.lerp(col_tip, t)
			if has_flower and t > 0.62:
				# Pequenos graos de flor na ponta da haste
				var bud := sin(t * 42.0) * 0.5 + 0.5
				half_w += bud * 2.2
				c = c.lerp(flower_col, 0.75 + bud * 0.25)

			var x0 := clampi(int(cx - half_w), 0, w - 1)
			var x1 := clampi(int(cx + half_w), 0, w - 1)
			for px in range(x0, x1 + 1):
				img.set_pixel(px, y, Color(c.r, c.g, c.b, 1.0))

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_3d_grass_field() -> void:
	# Malha em X (2 planos cruzados = 4 triangulos por tufo)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 0.55
	var hh := 1.0
	var angles := [0.0, PI * 0.5]
	for ang in angles:
		var dx := cos(ang) * hw
		var dz := sin(ang) * hw
		var p0 := Vector3(-dx, 0.0, -dz)
		var p1 := Vector3(dx, 0.0, dz)
		var p2 := Vector3(-dx, hh, -dz)
		var p3 := Vector3(dx, hh, dz)
		st.set_uv(Vector2(0.0, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(p1)
		st.set_uv(Vector2(0.0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(p2)

		st.set_uv(Vector2(1.0, 1.0)); st.set_normal(Vector3.UP); st.add_vertex(p1)
		st.set_uv(Vector2(1.0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(p3)
		st.set_uv(Vector2(0.0, 0.0)); st.set_normal(Vector3.UP); st.add_vertex(p2)

	var tuft_mesh := st.commit()
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap;

void vertex() {
	// Balanco suave no vento apenas na ponta superior (UV.y perto de 0)
	float sway_mask = 1.0 - UV.y;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.8 + world_pos.x * 0.35 + world_pos.z * 0.28) * 0.14;
	VERTEX.x += gust * sway_mask;
	VERTEX.z += gust * 0.6 * sway_mask;
}

void fragment() {
	vec4 tex = texture(grass_tex, UV);
	if (tex.a < 0.45) {
		discard;
	}
	// Fade suave na distancia para nao aparecer borda brusca
	float cam_dist = length(VERTEX);
	float dist_fade = 1.0 - smoothstep(42.0, 66.0, cam_dist);
	if (dist_fade < 0.05) {
		discard;
	}
	ALBEDO = tex.rgb * COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.05;
}
"""
	mat.shader = shader
	mat.set_shader_parameter("grass_tex", _make_tuft_sprite_texture())
	tuft_mesh.surface_set_material(0, mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tuft_mesh
	mm.instance_count = GRASS_BLADE_COUNT

	var rng := RandomNumberGenerator.new()
	rng.seed = 774411
	var placed := 0
	var attempts := 0
	while placed < GRASS_BLADE_COUNT and attempts < GRASS_BLADE_COUNT * 4:
		attempts += 1
		var r := sqrt(rng.randf()) * GRASS_SPAWN_RADIUS
		var theta := rng.randf() * TAU
		var x := cos(theta) * r
		var z := sin(theta) * r

		# Deixa uma pequena clareira bem no ponto inicial (0,0) e nao planta dentro da agua
		if Vector2(x, z).length() < 3.2:
			continue
		if Vector2(x, z).distance_to(LAKE_CENTER) < LAKE_RADIUS + 2.5:
			continue
		var y := height_at(x, z)
		if y < WATER_LEVEL + 0.15:
			continue

		var scale_h := rng.randf_range(GRASS_MIN_HEIGHT, GRASS_MAX_HEIGHT)
		var scale_w := rng.randf_range(0.85, 1.35)
		var rot := rng.randf() * TAU
		var t := Transform3D()
		t = t.scaled(Vector3(scale_w, scale_h, scale_w))
		t = t.rotated(Vector3.UP, rot)
		t.origin = Vector3(x, y - 0.04, z)
		mm.set_instance_transform(placed, t)

		# Variacao de cor por moita (algumas mais douradas, outras mais verdes)
		var patch := tint_noise.get_noise_2d(x * 1.8, z * 1.8) * 0.5 + 0.5
		var c := Color(0.86, 0.96, 0.80).lerp(Color(1.06, 1.00, 0.78), patch)
		mm.set_instance_color(placed, c)
		placed += 1

	mm.visible_instance_count = placed
	_grass_multimesh_node = MultiMeshInstance3D.new()
	_grass_multimesh_node.name = "StylizedGrassField"
	_grass_multimesh_node.multimesh = mm
	_grass_multimesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grass_multimesh_node)

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
	mat.albedo_texture = grass_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.vertex_color_use_as_albedo = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / TEXTURE_REPEAT_M, 1.0 / TEXTURE_REPEAT_M, 1.0 / TEXTURE_REPEAT_M)
	mat.albedo_color = GROUND_TINT
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.98
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
	# Cupula curva de nuvens estilizadas (sem esticar perto do horizonte)
	var dome := MeshInstance3D.new()
	dome.name = "StylizedCloudDome"
	var sphere := SphereMesh.new()
	sphere.radius = 240.0
	sphere.height = 140.0
	sphere.radial_segments = 32
	sphere.rings = 16
	dome.mesh = sphere
	dome.position = Vector3(0.0, 12.0, 0.0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sm := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

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
	if (h <= 0.02) {
		discard;
	}
	// Projecao esferica suave (evita pixelizacao e serrilhado perto do horizonte)
	vec2 sky_uv = local_dir.xz / (h + 0.35);
	vec2 wind = vec2(TIME * 0.008, TIME * 0.004);
	vec2 p = sky_uv * 2.1 + wind;

	float base_n = fbm(p);
	float puff = fbm(p * 2.3 - wind * 1.4);
	float density = base_n * 0.72 + puff * 0.28;

	float cloud_alpha = smoothstep(0.47, 0.68, density);
	float horizon_fade = smoothstep(0.03, 0.24, h);

	// Iluminacao estilo anime: base azulada macia e topo creme brilhante
	vec3 base_shadow = vec3(0.76, 0.86, 0.96);
	vec3 sunlit_top = vec3(1.00, 0.99, 0.95);
	float shade = smoothstep(0.46, 0.74, density + (h * 0.15));
	ALBEDO = mix(base_shadow, sunlit_top, shade);
	ALPHA = cloud_alpha * horizon_fade * 0.92;
}
"""
	sm.shader = shader
	dome.material_override = sm
	add_child(dome)

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
	# Encaixa estritamente na depressao do lago para nao invadir a planicie ao redor
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