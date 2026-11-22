extends Node3D
class_name ChunkManager
# Gerenciador dinamico de chunks de 32 m para mundo procedural infinito.

const CHUNK_SIZE := 32.0
const CELLS := 12
const CHUNK_VIEW_RADIUS := 4
const MAX_CHUNKS_PER_FRAME := 1

var _terrain: Node3D
var _shared_material: Material
var _active_chunks: Dictionary = {} # Vector2i -> Node3D
var _last_center_chunk := Vector2i(999999, 999999)

func setup(terrain: Node3D, shared_material: Material) -> void:
	_terrain = terrain
	_shared_material = shared_material

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

func ensure_initial_chunks_around(world_pos: Vector3, initial_radius: int = 1) -> void:
	# Gera imediatamente os chunks sob o jogador antes de liberar o movimento.
	var center := world_to_chunk(world_pos)
	var created := 0
	for dz in range(-initial_radius, initial_radius + 1):
		for dx in range(-initial_radius, initial_radius + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			if not _active_chunks.has(coord):
				_create_chunk(coord)
				created += 1
	if created > 0:
		print("[CHUNKS] ativos: ", _active_chunks.size(), ", criados: ", created, ", apagados: 0")

func update_around(world_pos: Vector3) -> void:
	if _terrain == null:
		return
	var center := world_to_chunk(world_pos)
	var deleted := 0

	# Apaga chunks que ficaram alem de CHUNK_VIEW_RADIUS + 1
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
		deleted += 1

	# Coleta candidatos faltantes dentro de CHUNK_VIEW_RADIUS e ordena do mais perto para o mais longe
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
			_create_chunk(missing[i])
			created += 1

	if created > 0 or deleted > 0 or center != _last_center_chunk:
		_last_center_chunk = center
		if created > 0 or deleted > 0:
			print("[CHUNKS] ativos: ", _active_chunks.size(), ", criados: ", created, ", apagados: ", deleted)

func _create_chunk(coord: Vector2i) -> void:
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

	add_child(chunk_root)
	_active_chunks[coord] = chunk_root