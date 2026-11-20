extends Node3D
# Terrain chunks simples para Android.
const CHUNK_SIZE := 32.0
const CHUNKS := 8
const CELLS := 16
const FLAT_RADIUS := 80.0
const WATER_LEVEL := -1.8
var height_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
func _ready() -> void:
	height_noise.seed = 82471
	height_noise.frequency = 0.012
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	height_noise.fractal_octaves = 3
	height_noise.fractal_gain = 0.48
	height_noise.fractal_lacunarity = 2.0
	lake_noise.seed = 823
	lake_noise.frequency = 0.025
	lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_build_chunks()
func height_at(x: float, z: float) -> float:
	if Vector2(x,z).length() <= FLAT_RADIUS:
		return 0.0
	var h := height_noise.get_noise_2d(x,z)*9.0
	if lake_noise.get_noise_2d(x,z)>0.48:
		h-=4.0
	return h
func _build_chunks() -> void:
	for cx in range(CHUNKS):
		for cz in range(CHUNKS):
			var ox := (float(cx)-CHUNKS*0.5)*CHUNK_SIZE
			var oz := (float(cz)-CHUNKS*0.5)*CHUNK_SIZE
			_build_chunk(ox,oz)
			_build_water_chunk(ox,oz)
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
			st.add_vertex(a);st.add_vertex(c);st.add_vertex(b)
			st.add_vertex(b);st.add_vertex(c);st.add_vertex(d)
	st.generate_normals()
	var mesh:=st.commit()
	var ground:=MeshInstance3D.new()
	ground.mesh=mesh
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color(0.34,0.48,0.26)
	mat.roughness=1.0
	ground.material_override=mat
	add_child(ground)
	var body:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	cs.shape=mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
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
			if mid.length()<=FLAT_RADIUS or lake_noise.get_noise_2d(mid.x,mid.y)<=0.48 or height_at(mid.x,mid.y)>=WATER_LEVEL:
				continue
			st.add_vertex(Vector3(x0,WATER_LEVEL,z0))
			st.add_vertex(Vector3(x0,WATER_LEVEL,z1))
			st.add_vertex(Vector3(x1,WATER_LEVEL,z0))
			st.add_vertex(Vector3(x1,WATER_LEVEL,z0))
			st.add_vertex(Vector3(x0,WATER_LEVEL,z1))
			st.add_vertex(Vector3(x1,WATER_LEVEL,z1))
			has_water=true
	if not has_water:return
	var water:=MeshInstance3D.new()
	water.mesh=st.commit()
	var sm:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode unshaded, cull_disabled; void fragment(){float r=sin(UV.x*32.0+TIME*0.7)*sin(UV.y*24.0+TIME*0.45); ALBEDO=vec3(0.08,0.28,0.36)+r*0.015;}"
	sm.shader=shader
	water.material_override=sm
	add_child(water)
