extends SceneTree

const MODEL_PATH := "res://assets/characters/Superhero_Male_FullBody.gltf"
const ANIM_PATH := "res://assets/characters/UAL1_Standard.glb"

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
	var instance: Node = null
	if animation_asset is PackedScene:
		instance = animation_asset.instantiate()
	elif model is PackedScene:
		instance = model.instantiate()
	if instance == null:
		push_error("Could not instantiate imported GLB scene.")
		quit(1)
		return
	var found := 0
	_collect_animation_players(instance)
	instance.free()
	if found == 0:
		push_error("No AnimationPlayer nodes or animations found in imported UAL1 scene.")
		quit(1)
		return
	print("=== IMPORT CHECK COMPLETE ===")
	quit(0)

var found := 0
func _collect_animation_players(node: Node) -> void:
	if node is AnimationPlayer:
		for library_name in node.get_animation_library_list():
			var library: AnimationLibrary = node.get_animation_library(library_name)
			for animation_name in library.get_animation_list():
				found += 1
				print("ANIMATION: ", library_name, "/", animation_name)
	for child in node.get_children():
		_collect_animation_players(child)
