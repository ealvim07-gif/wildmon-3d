extends Node3D
# Terreno por chunks, com textura triplanar e colisao triangulada para Android.
const DEBUG_TERRAIN_UNSHADED := true # Diagnostico visual temporario deste build.
const CHUNK_SIZE := 32.0
const CHUNKS := 8
const CELLS := 12 # menos triangulos: carrega ~4x mais rapido no celular
const FLAT_RADIUS := 80.0
const WATER_LEVEL := -1.35
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_RADIUS := 19.0
const TEXTURE_SIZE := 256 # tamanho da textura procedural (pixels)
const TEXTURE_REPEAT_M := 4.0 # a textura se repete a cada 4 m
# Opcional: foto CC0 (Poly Haven / ambientCG). Se estes arquivos existirem, sao usados no lugar da procedural.
const GRASS_ALBEDO_PATH := "res://assets/terrain/grass_albedo.jpg"
const GRASS_NORMAL_PATH := "res://assets/terrain/grass_normal.jpg"
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
	tint_noise.frequency = 0.018
	tint_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tint_noise.fractal_octaves = 2
	_load_grass_textures()
	_build_chunks()
	_diagnose_terrain_cover()
	_adjust_directional_light_bias()

func height_at(x: float, z: float) -> float:
	var p := Vector2(x,z)
	if p.length() <= FLAT_RADIUS:
		return 0.0
	# Fade suave na borda da planicie, para evitar degrau.
	var fade := smoothstep(FLAT_RADIUS, FLAT_RADIUS + 22.0, p.length())
	var hills := height_noise.get_noise_2d(x,z) * 4.0
	# Lago predeterminado e encontravel a ~112 m, com bordas suavizadas.
	var lake_distance := p.distance_to(LAKE_CENTER)
	var lake_basin := -3.0 * (1.0 - smoothstep(LAKE_RADIUS - 4.0, LAKE_RADIUS + 8.0, lake_distance))
	# Colinas suaves perto do lago, sem paredes nem recortes abruptos.
	var hill_a := 3.8 * exp(-p.distance_to(Vector2(132.0, 24.0)) / 24.0) * exp(-p.distance_to(Vector2(132.0,24.0)) / 24.0)
	var hill_b := 3.5 * exp(-p.distance_to(Vector2(94.0,-32.0)) / 23.0) * exp(-p.distance_to(Vector2(94.0,-32.0)) / 23.0)
	var basin_mask := smoothstep(0.50, 0.68, lake_noise.get_noise_2d(x,z))
	var basin := -0.8 * basin_mask
	return (hills + basin + hill_a + hill_b + lake_basin) * fade

func _load_grass_textures() -> void:
	# 1) Se existir uma foto CC0 em assets/terrain/, usa ela.
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
	# 2) Senao, gera a textura procedural melhorada (sem emendas).
	grass_texture = ImageTexture.create_from_image(_make_grass_texture())
	print("[TERRAIN] Textura do chao: procedural melhorada")

func _tint_at(x: float, z: float) -> Color:
	# Variacao de cor em escala grande (dezenas de metros), para quebrar a repeticao da textura.
	var u := tint_noise.get_noise_2d(x, z) * 0.5 + 0.5
	return Color(0.80, 0.88, 0.72).lerp(Color(1.0, 1.0, 0.96), clampf(u, 0.0, 1.0))

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
	var broad := _seamless_layer(418, 0.012, 2)
	var mid := _seamless_layer(733, 0.045, 3)
	var fine := _seamless_layer(991, 0.16, 2)
	if broad.size() != total or mid.size() != total or fine.size() != total:
		print("[TERRAIN] Textura nova indisponivel, usando a antiga")
		return _make_grass_texture_legacy()
	var data := PackedByteArray()
	data.resize(total * 4)
	var c_dark := Color(0.16, 0.30, 0.08)
	var c_mid := Color(0.31, 0.50, 0.16)
	var c_light := Color(0.52, 0.66, 0.27)
	var c_dry := Color(0.58, 0.54, 0.26)
	var c_dirt := Color(0.34, 0.26, 0.14)
	for y in range(size):
		for x in range(size):
			var i := y * size + x
			var b := float(broad[i]) / 255.0
			var m := float(mid[i]) / 255.0
			var f := float(fine[i]) / 255.0
			var t := clampf(0.15 + m * 0.65 + (f - 0.5) * 0.55, 0.0, 1.0)
			var col: Color
			if t < 0.5:
				col = c_dark.lerp(c_mid, t * 2.0)
			else:
				col = c_mid.lerp(c_light, (t - 0.5) * 2.0)
			# Manchas de grama seca e pequenos trechos de terra, em escala grande.
			col = col.lerp(c_dry, smoothstep(0.55, 0.9, b) * 0.55)
			col = col.lerp(c_dirt, smoothstep(0.78, 0.95, b * 0.6 + f * 0.4) * 0.6)
			# Pontinhos claros e escuros isolados, parecendo folhas de grama.
			var h := fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
			if h > 0.965:
				col = col.lightened(0.18)
			elif h < 0.04:
				col = col.darkened(0.22)
			var j := i * 4
			data[j] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			data[j + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			data[j + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			data[j + 3] = 255
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	image.generate_mipmaps()
	return image

func _make_grass_texture_legacy() -> Image:
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
	var broad:=FastNoiseLite.new(); broad.seed=418; broad.frequency=0.035
	var detail:=FastNoiseLite.new(); detail.seed=733; detail.frequency=0.19
	var grain:=FastNoiseLite.new(); grain.seed=991; grain.frequency=0.62
	for y in range(256):
		for x in range(256):
			var n1:=broad.get_noise_2d(float(x),float(y))
			var n2:=detail.get_noise_2d(float(x),float(y))
			var n3:=grain.get_noise_2d(float(x),float(y))
			var fleck:=sin(float(x)*1.7+n2*8.0)*cos(float(y)*1.3+n3*7.0)*0.035
			var value:=clampf(0.5+n1*0.25+n2*0.18+n3*0.09+fleck,0.0,1.0)
			var color:=Color(0.19,0.36,0.11).lerp(Color(0.46,0.61,0.29),value)
			image.set_pixel(x,y,Color(color.r,color.g,color.b,1.0))
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
			var ox:float=(float(cx)-CHUNKS*0.5)*CHUNK_SIZE
			var oz:float=(float(cz)-CHUNKS*0.5)*CHUNK_SIZE
			_build_chunk(ox,oz)
			_build_water_chunk(ox,oz)
	# Pedras de orientação na direção do lago (+X), dentro da área alcançável.
	_make_marker_rock(18.0, -42.0, Vector3(0.65,0.42,0.58))
	_make_marker_rock(34.0, -42.0, Vector3(0.9,0.55,0.75))
	_make_marker_rock(50.0, -42.0, Vector3(1.1,0.7,0.9))
	_make_marker_rock(56.0, -36.0, Vector3(0.7,0.45,0.65))

func _build_chunk(ox:float,oz:float) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(CELLS):
		for x in range(CELLS):
			var x0:=ox+float(x)*CHUNK_SIZE/CELLS
			var z0:=oz+float(z)*CHUNK_SIZE/CELLS
			var x1:=x0+CHUNK_SIZE/CELLS
			var z1:=z0+CHUNK_SIZE/CELLS
			var a:=Vector3(x0,height_at(x0,z0),z0)
			var b:=Vector3(x1,height_at(x1,z0),z0)
			var c:=Vector3(x0,height_at(x0,z1),z1)
			var d:=Vector3(x1,height_at(x1,z1),z1)
			var ta:=_tint_at(x0,z0)
			var tb:=_tint_at(x1,z0)
			var tc:=_tint_at(x0,z1)
			var td:=_tint_at(x1,z1)
			# UVs em coordenadas de mundo: textura repetida aproximadamente a cada 4 m.
			# Normais calculadas pelo gradiente para evitar faces escuras/facetadas.
			# Ordem horaria vista de cima (frente da face = para cima), exigida pela colisao do Godot.
			st.set_uv(Vector2(x0 / 4.0, z0 / 4.0)); st.set_color(ta); st.set_normal(_terrain_normal(x0,z0)); st.add_vertex(a)
			st.set_uv(Vector2(x1 / 4.0, z0 / 4.0)); st.set_color(tb); st.set_normal(_terrain_normal(x1,z0)); st.add_vertex(b)
			st.set_uv(Vector2(x0 / 4.0, z1 / 4.0)); st.set_color(tc); st.set_normal(_terrain_normal(x0,z1)); st.add_vertex(c)
			st.set_uv(Vector2(x1 / 4.0, z0 / 4.0)); st.set_color(tb); st.set_normal(_terrain_normal(x1,z0)); st.add_vertex(b)
			st.set_uv(Vector2(x1 / 4.0, z1 / 4.0)); st.set_color(td); st.set_normal(_terrain_normal(x1,z1)); st.add_vertex(d)
			st.set_uv(Vector2(x0 / 4.0, z1 / 4.0)); st.set_color(tc); st.set_normal(_terrain_normal(x0,z1)); st.add_vertex(c)
	var mesh:=st.commit()
	var ground:=MeshInstance3D.new()
	ground.mesh=mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=StandardMaterial3D.new()
	mat.albedo_texture=grass_texture
	mat.roughness=1.0
	mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.vertex_color_use_as_albedo = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / TEXTURE_REPEAT_M, 1.0 / TEXTURE_REPEAT_M, 1.0 / TEXTURE_REPEAT_M)
	if grass_normal != null:
		mat.normal_enabled = true
		mat.normal_texture = grass_normal
	mat.albedo_color=Color(1.0,1.0,1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness=1.0
	mat.metallic=0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if DEBUG_TERRAIN_UNSHADED else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.disable_receive_shadows=false
	ground.material_override=mat
	add_child(ground)
	var body:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	var trimesh := mesh.create_trimesh_shape()
	trimesh.backface_collision = true # o jogador nunca atravessa o chao, mesmo se a ordem das faces falhar
	cs.shape=trimesh
	body.add_child(cs)
	add_child(body)

func _diagnose_terrain_cover() -> void:
	print("[TERRAIN DEBUG] DEBUG_TERRAIN_UNSHADED=", DEBUG_TERRAIN_UNSHADED)
	print("[TERRAIN DEBUG] Planicie: material StandardMaterial3D triplanar com grama procedural.")
	print("[TERRAIN DEBUG] Normais calculadas por gradiente; planicie deve ter Vector3.UP.")
	var found_cover := false
	var root := get_parent()
	if root:
		for node in root.get_children():
			if node == self:
				continue
			if node is MeshInstance3D and node.global_position.y >= -0.5 and node.global_position.y <= 0.5:
				print("[TERRAIN DEBUG] Outra MeshInstance3D vizinha: ", node.name, " pos=", node.global_position)
				found_cover = true
			if node is Node3D and node.name.to_lower().contains("plane"):
				print("[TERRAIN DEBUG] Possivel plano cobrindo area: ", node.name)
				found_cover = true
	print("[TERRAIN DEBUG] Outra malha/plano detectado na faixa de altura da planicie: ", found_cover)

func _adjust_directional_light_bias() -> void:
	var root := get_parent()
	if root:
		for light in _find_directional_lights(root):
			light.shadow_bias = maxf(light.shadow_bias, 0.08)
			light.shadow_normal_bias = maxf(light.shadow_normal_bias, 1.0)
			print("[TERRAIN DEBUG] DirectionalLight3D ", light.name, " bias=", light.shadow_bias, " normal_bias=", light.shadow_normal_bias)

func _find_directional_lights(node: Node) -> Array:
	var found: Array = []
	if node is DirectionalLight3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_directional_lights(child))
	return found

func _build_water_chunk(ox:float,oz:float) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_water:=false
	for z in range(CELLS):
		for x in range(CELLS):
			var x0:=ox+float(x)*CHUNK_SIZE/CELLS
			var z0:=oz+float(z)*CHUNK_SIZE/CELLS
			var x1:=x0+CHUNK_SIZE/CELLS
			var z1:=z0+CHUNK_SIZE/CELLS
			var mid:=Vector2((x0+x1)*0.5,(z0+z1)*0.5)
			var in_forced_lake := mid.distance_to(LAKE_CENTER) <= LAKE_RADIUS
			if mid.length()<=FLAT_RADIUS+12.0 or (not in_forced_lake and height_at(mid.x,mid.y)>=WATER_LEVEL-0.08):
				continue
			# Face superior, plano de agua em celulas de bacia abaixo do nivel.
			st.add_vertex(Vector3(x0,WATER_LEVEL,z0))
			st.add_vertex(Vector3(x0,WATER_LEVEL,z1))
			st.add_vertex(Vector3(x1,WATER_LEVEL,z0))
			st.add_vertex(Vector3(x1,WATER_LEVEL,z0))
			st.add_vertex(Vector3(x0,WATER_LEVEL,z1))
			st.add_vertex(Vector3(x1,WATER_LEVEL,z1))
			has_water=true
	if not has_water:
		return
	st.generate_normals()
	var water:=MeshInstance3D.new()
	water.mesh=st.commit()
	var sm:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode unshaded, cull_disabled; void fragment(){float r=sin(UV.x*32.0+TIME*0.7)*sin(UV.y*24.0+TIME*0.45); ALBEDO=vec3(0.08,0.28,0.36)+r*0.015;}"
	sm.shader=shader
	water.material_override=sm
	add_child(water)
