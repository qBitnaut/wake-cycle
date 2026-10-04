class_name Room2
extends Level
## Room 2 stub: a tiny lit loading dock with a "coming soon" label, so the
## room transition from Room 1 can be tested. The cat arrives with the
## mind awakened (no powers) and the room auto-saves on entry (see Level._ready).


func _physics_process(delta: float) -> void:
	super(delta)
	if OS.has_feature("web"):
		# Same shape as Room 1's published state (tools/audit/web_room1.mjs).
		var d := {
			"f": Engine.get_physics_frames(),
			"x": cat.global_position.x, "y": cat.global_position.y,
			"scene": scene_file_path, "shock": GameState.shockwave_unlocked, "mind": GameState.intelligence, "power": GameState.power,
			"save": SaveSystem.has_save(), "can_move": cat.can_move,
		}
		JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
