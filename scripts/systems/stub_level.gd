class_name StubLevel
extends Level
## A placeholder level ("coming soon") that a finished room's exit can lead to
## while the next room is being built. Publishes the same window.__wake shape as
## the rooms on the web so the audits can see the cat arrive.


func _physics_process(delta: float) -> void:
	super(delta)
	if OS.has_feature("web"):
		var d := {
			"f": Engine.get_physics_frames(),
			"x": cat.global_position.x, "y": cat.global_position.y,
			"scene": scene_file_path, "shock": GameState.shockwave_unlocked, "mind": GameState.intelligence,
			"power": GameState.power, "save": SaveSystem.has_save(), "can_move": cat.can_move,
		}
		JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
