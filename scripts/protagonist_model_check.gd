extends SceneTree

func _initialize() -> void:
	var packed := load("res://assets/characters/Superhero_Male_FullBody.gltf") as PackedScene
	if packed == null:
		print("FALLBACK ANTIGO")
		push_error("Could not load protagonist GLTF scene.")
		quit(1)
		return
	var model := packed.instantiate()
	if model == null:
		print("FALLBACK ANTIGO")
		push_error("Could not instantiate protagonist GLTF.")
		quit(1)
		return
	print("MODELO NOVO CARREGADO")
	model.free()
	quit(0)
