extends Node3D
# Terreno por chunks, com textura triplanar e colisao triangulada para Android.
const DEBUG_TERRAIN_UNSHADED := true # Diagnostico visual temporario deste build.
const CHUNK_SIZE := 32.0
const CHUNKS := 8
const CELLS := 24
const FLAT_RADIUS := 80.0
const WATER_LEVEL := -1.35
const LAKE_CENTER := Vector2(112.0, 0.0)
const LAKE_RADIUS := 19.0
var height_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var grass_texture: ImageTexture

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
	grass_texture = ImageTexture.create_from_image(_make_grass_texture())
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

func _make_grass_texture() -> Image:
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
			# UVs em coordenadas de mundo: textura repetida aproximadamente a cada 4 m.
			# Normais calculadas pelo gradiente para evitar faces escuras/facetadas.
			st.set_uv(Vector2(x0 / 4.0, z0 / 4.0)); st.set_normal(_terrain_normal(x0,z0)); st.add_vertex(a)
			st.set_uv(Vector2(x0 / 4.0, z1 / 4.0)); st.set_normal(_terrain_normal(x0,z1)); st.add_vertex(c)
			st.set_uv(Vector2(x1 / 4.0, z0 / 4.0)); st.set_normal(_terrain_normal(x1,z0)); st.add_vertex(b)
			st.set_uv(Vector2(x1 / 4.0, z0 / 4.0)); st.set_normal(_terrain_normal(x1,z0)); st.add_vertex(b)
			st.set_uv(Vector2(x0 / 4.0, z1 / 4.0)); st.set_normal(_terrain_normal(x0,z1)); st.add_vertex(c)
			st.set_uv(Vector2(x1 / 4.0, z1 / 4.0)); st.set_normal(_terrain_normal(x1,z1)); st.add_vertex(d)
	var mesh:=st.commit()
	var ground:=MeshInstance3D.new()
	ground.mesh=mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=StandardMaterial3D.new()
	mat.albedo_texture=grass_texture
	mat.roughness=1.0
	mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.25,0.25,0.25)
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
	cs.shape=mesh.create_trimesh_shape()
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
