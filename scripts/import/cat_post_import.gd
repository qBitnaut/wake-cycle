@tool
extends EditorScenePostImport
## Renames the Quaternius cat clips to clean names and sets loop modes.
## Source names look like "AnimalArmature|AnimalArmature|AnimalArmature|Idle".

const LOOPING := ["Idle", "Idle_Eating", "Walk", "Run", "Jump"]


func _post_import(scene: Node) -> Object:
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return scene
	var library := player.get_animation_library(&"")
	for full_name in library.get_animation_list():
		var clean := String(full_name).get_slice("|", String(full_name).get_slice_count("|") - 1)
		var anim := library.get_animation(full_name)
		anim.loop_mode = Animation.LOOP_LINEAR if clean in LOOPING else Animation.LOOP_NONE
		library.rename_animation(full_name, clean)
	return scene
