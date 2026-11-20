extends SceneTree

const MODEL_PATH := "res://assets/characters/Superhero_Male_FullBody.gltf"
const ANIM_PATH := "res://assets/characters/UAL1_Standard.glb"
const OUTPUT_PATH := "assets/characters/animations_list.txt"

var animation_names: Array[String] = []

func _initialize() -> void:
	print("=== CHARACTER ASSET IMPORT CHECK ===")
	var model = ResourceLoader.load(MODEL_PATH)
	if model == null:
		push_error("MODEL IMPORT FAILED: " + MODEL_PATH)
		quit(1)
		return
	print("MODEL IMPORT OK: ", MODEL_PATH, " (", model.get_class(), ")")
	var animation_asset = ResourceLoader.load(ANIM_PATH)
	if animation_asset == null:
		push_error("ANIMATION GLB IMPORT FAILED: " + ANIM_PATH)
		quit(1)
		return
	print("ANIMATION GLB IMPORT OK: ", ANIM_PATH, " (", animation_asset.get_class(), ")")
	if not animation_asset is PackedScene:
		push_error("UAL1 import did not produce a PackedScene.")
		quit(1)
		return
	var instance: Node = animation_asset.instantiate()
	_collect_animation_players(instance)
	instance.free()
	if animation_names.is_empty():
		push_error("No animations found in imported UAL1 scene.")
		quit(1)
		return
	var output := "Animations found in UAL1_Standard.glb\n"
	output += "Model import: OK\nAnimation GLB import: OK\n\n"
	for animation_name in animation_names:
		output += animation_name + "\n"
	var absolute_path := OS.get_environment("GITHUB_WORKSPACE").path_join(OUTPUT_PATH)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write animation list file: " + absolute_path)
		quit(1)
		return
	file.store_string(output)
	file.close()
	print("ANIMATION LIST FILE WRITTEN: ", absolute_path)
	print(output)
	print("=== IMPORT CHECK COMPLETE ===")
	quit(0)

func _collect_animation_players(node: Node) -> void:
	if node is AnimationPlayer:
		for library_name in node.get_animation_library_list():
			var library: AnimationLibrary = node.get_animation_library(library_name)
			for animation_name in library.get_animation_list():
				var full_name := str(library_name) + "/" + str(animation_name)
				animation_names.append(full_name)
				print("ANIMATION: ", full_name)
	for child in node.get_children():
		_collect_animation_players(child)
