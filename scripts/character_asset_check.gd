extends SceneTree

const MODEL_PATH := "res://assets/characters/Superhero_Male_FullBody.gltf"
const ANIM_PATH := "res://assets/characters/UAL1_Standard.glb"
const OUTPUT_PATH := "assets/characters/animations_list.txt"

var animation_names: Array[String] = []
var report := ""

func _initialize() -> void:
	print("=== CHARACTER ASSET IMPORT CHECK ===")
	var model = ResourceLoader.load(MODEL_PATH)
	if model == null:
		push_error("MODEL IMPORT FAILED: " + MODEL_PATH)
		quit(1)
		return
	print("MODEL IMPORT OK: ", MODEL_PATH, " (", model.get_class(), ")")
	if model is PackedScene:
		var model_instance: Node = model.instantiate()
		print("--- MODEL ANIMATION PLAYERS / SKELETONS ---")
		_inspect_nodes(model_instance, "MODEL")
		model_instance.free()
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
	print("--- UAL1 ANIMATION PLAYERS / SKELETONS ---")
	_inspect_nodes(instance, "UAL1")
	instance.free()
	if animation_names.is_empty():
		push_error("No animations found in imported character assets.")
		quit(1)
		return
	var absolute_path := OS.get_environment("GITHUB_WORKSPACE").path_join(OUTPUT_PATH)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write animation list file: " + absolute_path)
		quit(1)
		return
	file.store_string(report)
	file.close()
	print("ANIMATION/SKELETON REPORT WRITTEN: ", absolute_path)
	print(report)
	print("=== IMPORT CHECK COMPLETE ===")
	quit(0)

func _inspect_nodes(node: Node, asset_name: String) -> void:
	if node is AnimationPlayer:
		report += "\n[" + asset_name + "] AnimationPlayer: " + str(node.name) + "\n"
		print("PLAYER ", asset_name, " ", str(node.name))
		for library_name in node.get_animation_library_list():
			var library: AnimationLibrary = node.get_animation_library(library_name)
			for anim_name in library.get_animation_list():
				var full_name := str(library_name) + "/" + str(anim_name)
				animation_names.append(full_name)
				report += "ANIMATION: " + full_name + "\n"
				print("ANIMATION: ", asset_name, " ", full_name)\n\t\t\t\tvar animation: Animation = library.get_animation(anim_name)\n\t\t\t\tfor track_index in range(animation.get_track_count()):\n\t\t\t\t\tvar track_path := str(animation.track_get_path(track_index))\n\t\t\t\t\tvar track_type := str(animation.track_get_type(track_index))\n\t\t\t\t\treport += "TRACK: " + full_name + " | " + track_path + " | " + track_type + "\\n"\n\t\t\t\t\tprint("TRACK: ", asset_name, " ", full_name, " | ", track_path, " | ", track_type)
	if node is Skeleton3D:
		report += "\n[" + asset_name + "] Skeleton3D: " + str(node.name) + "\n"
		print("SKELETON ", asset_name, " ", str(node.name), " bone_count=", node.get_bone_count())
		for bone_index in range(node.get_bone_count()):
			var bone_name: String = str(node.get_bone_name(bone_index))
			report += "BONE " + str(bone_index) + ": " + bone_name + "\n"
			print("BONE ", asset_name, " ", bone_index, " ", bone_name)
	for child in node.get_children():
		_inspect_nodes(child, asset_name)
