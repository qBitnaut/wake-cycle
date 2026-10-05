class_name Room3
extends Level
## Room 3 stub: a short lit stretch with a "coming soon" label, so the exit
## from Room 2 can be tested. The cat arrives as it left Room 2 and the room
## auto-saves on entry (see Level._ready).


func _physics_process(delta: float) -> void:
	super(delta)
	if OS.has_feature("web"):
		# Same shape as Room 2's published state (tools/audit/web_room2.mjs).
		var d := {
			"f": Engine.get_physics_frames(),
			"x": cat.global_position.x, "y": cat.global_position.y,
			"scene": scene_file_path, "shock": GameState.shockwave_unlocked, "mind": GameState.intelligence, "power": GameState.power,
			"save": SaveSystem.has_save(), "can_move": cat.can_move,
		}
		JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
