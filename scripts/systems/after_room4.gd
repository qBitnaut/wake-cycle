class_name AfterRoom4
extends Level
## Stub for whatever follows Room 4: a short lit road and a "Home - coming soon"
## sign, so the exit from the Perimeter can be tested. Integration rewires
## Room 4's exit to scenes/levels/home.tscn.


func _enter_tree() -> void:
	super()
	if not GameState.intelligence or not GameState.shockwave_unlocked:
		GameState.intelligence = true
		GameState.shockwave_unlocked = true
		SaveSystem.session_snapshot = GameState.snapshot()


func _physics_process(delta: float) -> void:
	super(delta)
	if OS.has_feature("web"):
		var d := {
			"f": Engine.get_physics_frames(),
			"x": cat.global_position.x, "y": cat.global_position.y,
			"scene": scene_file_path, "shock": GameState.shockwave_unlocked, "mind": GameState.intelligence, "power": GameState.power,
			"save": SaveSystem.has_save(), "can_move": cat.can_move,
		}
		JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
