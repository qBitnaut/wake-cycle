@tool
extends EditorScenePostImport
## Post-import for the tabby cat ("cat toon shader" by ssombrinha570, CC BY 4.0).
##  * Renames the source clips and sets loop modes.
##  * Cuts the single "cat jump" clip into Jump_Start / Jump_Air / Land.
##  * Adds a one-frame "Stand" rest pose (frame 0 of Walk).
##  * Adds hidden BoneAttachment3D sockets for the robotic augments.
##
## Source clips and the frames they were cut from (sampled at 0.1 s; the jump
## clip is 2.083 s long):
##   0.0-0.5   slow anticipation (head dips, weight shifts)  -> dropped
##   0.5-1.0   coil down and push off, front paws reach      -> Jump_Start
##   1.05-1.25 airborne stretch, body long, hind legs trail  -> Jump_Air
##   1.35-end  touchdown, crouch, recover to standing        -> Land

const RENAMES := {
	"walk cat": &"Walk",
	"run cat": &"Run",
	"iddle cat": &"Idle_Sit",
	"cat sitdown": &"Sit_Down",
}
const LOOPING: Array[StringName] = [&"Walk", &"Run", &"Idle_Sit"]

const JUMP_SOURCE := "cat jump"
const JUMP_START := Vector2(0.5, 1.0)
const JUMP_AIR := Vector2(1.05, 1.25)
const LAND_FROM := 1.35

## Socket name -> bone name prefix. The imported bone names carry a numeric
## suffix ("Bone.003_11"), so match on the prefix. Bone positions in the
## skeleton's rest pose (raw units, +Z is the nose):
##   Socket_Head      Bone.007  head, between the ears (z 1.95)
##   Socket_Spine     Bone.003  shoulder blades / upper back (z 0.53)
##   Socket_Tail      Bone.016  tail base (z -1.29)
##   Socket_ForelegL  osso_do_jeolho_frente.l  left foreleg, below the elbow
##   Socket_ForelegR  osso_do_jeolho_frente.r
##   Socket_HindlegL  osso_do_joelho2.l  left hind leg, below the hock
##   Socket_HindlegR  osso_do_joelho2.r
const SOCKETS := {
	"Socket_Head": "Bone.007",
	"Socket_Spine": "Bone.003",
	"Socket_Tail": "Bone.016",
	"Socket_ForelegL": "osso_do_jeolho_frente.l",
	"Socket_ForelegR": "osso_do_jeolho_frente.r",
	"Socket_HindlegL": "osso_do_joelho2.l",
	"Socket_HindlegR": "osso_do_joelho2.r",
}

const STEP := 1.0 / 30.0


func _post_import(scene: Node) -> Object:
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		_process_animations(player)
	var skeleton := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		_add_sockets(scene, skeleton)
	return scene


func _process_animations(player: AnimationPlayer) -> void:
	var library := player.get_animation_library(&"")
	for old_name in RENAMES:
		if not library.has_animation(old_name):
			continue
		var anim := library.get_animation(old_name)
		var clean: StringName = RENAMES[old_name]
		anim.loop_mode = Animation.LOOP_LINEAR if clean in LOOPING else Animation.LOOP_NONE
		library.rename_animation(old_name, clean)
	if library.has_animation(&"Walk"):
		library.add_animation(&"Stand", _slice(library.get_animation(&"Walk"), 0.0, 0.0, Animation.LOOP_LINEAR))
	if library.has_animation(JUMP_SOURCE):
		var jump := library.get_animation(JUMP_SOURCE)
		library.add_animation(&"Jump_Start", _slice(jump, JUMP_START.x, JUMP_START.y, Animation.LOOP_NONE))
		library.add_animation(&"Jump_Air", _slice(jump, JUMP_AIR.x, JUMP_AIR.y, Animation.LOOP_PINGPONG))
		library.add_animation(&"Land", _slice(jump, LAND_FROM, jump.length, Animation.LOOP_NONE))
		library.remove_animation(JUMP_SOURCE)


## Copy of anim covering [from, to], re-timed to start at 0. Keys are resampled
## at 30 fps so the cut points are exact.
func _slice(source: Animation, from: float, to: float, loop: Animation.LoopMode) -> Animation:
	var out := Animation.new()
	var span := maxf(to - from, STEP)
	out.length = span
	out.loop_mode = loop
	for t in source.get_track_count():
		var type := source.track_get_type(t)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var idx := out.add_track(type)
		out.track_set_path(idx, source.track_get_path(t))
		out.track_set_interpolation_type(idx, source.track_get_interpolation_type(t))
		var time := 0.0
		while true:
			var value: Variant = _sample(source, t, type, minf(from + time, source.length))
			match type:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(idx, time, value)
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(idx, time, value)
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(idx, time, value)
			if time >= span - 0.0001:
				break
			time = minf(time + STEP, span)
	return out


func _sample(source: Animation, track: int, type: int, time: float) -> Variant:
	match type:
		Animation.TYPE_POSITION_3D:
			return source.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D:
			return source.rotation_track_interpolate(track, time)
	return source.scale_track_interpolate(track, time)


func _add_sockets(scene: Node, skeleton: Skeleton3D) -> void:
	for socket_name in SOCKETS:
		var bone := _find_bone(skeleton, SOCKETS[socket_name])
		if bone.is_empty():
			push_warning("cat_post_import: no bone for %s" % socket_name)
			continue
		var socket := BoneAttachment3D.new()
		socket.name = socket_name
		skeleton.add_child(socket)
		socket.owner = scene
		socket.bone_name = bone
		var augment := Node3D.new()
		augment.name = "Augment"
		augment.visible = false
		socket.add_child(augment)
		augment.owner = scene


func _find_bone(skeleton: Skeleton3D, prefix: String) -> String:
	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i)
		# Match "Bone.003" but not "Bone.0030"; names end in "_<n>".
		if bone_name == prefix or bone_name.begins_with(prefix + "_"):
			return bone_name
	return ""
