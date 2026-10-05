class_name Room2
extends Level
## Room 2, "The Yard": the rainy loading yard behind the warehouse. The cat
## arrives with its mind awake and no powers, and the room teaches Surge one
## step at a time, with level design and the cat's own thoughts only:
##   1 discovery  a pad in a low service tunnel (unavoidable) and a long clear run
##   2 use it     a nine-tile gap (past the double jump) and a security gate on a clock
##   3 combine    a searchlight drone chases the cat past stairs, a pit and a crawl vent
## Plus the first patrol walkers, a docked bot that reacts to the augmented cat
## (a teaser for the supervisor idea) and the way out through the fence to Room 3.
##
## Surge comes only from the PowerPads in this scene; nothing else grants a
## power or the shockwave. `power_grants` and `power_violations` are audit hooks.
##
## Web debug hooks for tools/audit/web_room2.mjs: window.__wake is published
## every physics frame; window.wakeTeleport(x, y) moves the cat and
## window.wakeStrike() fires a lightning strike.

## Rain is a moving window of RainFX that follows the camera.
const RAIN_NODES := ["RainFar", "RainNear"]
const THUNDER := preload("res://assets/audio/ambient/rolling.ogg")

var power_grants: Array = []     ## [power, on_a_pad] per grant, in order
var power_violations := 0        ## grants that were not Surge, or not from a pad
var thunders := 0
var _js_callbacks: Array = []
var _lightning: LightningFX
var _thunder: AudioStreamPlayer


func _ready() -> void:
	super()
	_thunder = AudioStreamPlayer.new()
	_thunder.stream = THUNDER
	_thunder.volume_db = -8.0
	_thunder.pitch_scale = 0.55
	add_child(_thunder)
	_lightning = get_node_or_null("Lightning") as LightningFX
	if _lightning:
		_lightning.thunder.connect(_on_thunder)
	GameState.power_changed.connect(_on_power)
	GameState.shockwave_unlock_changed.connect(func(on: bool):
		if on:
			power_violations += 1)
	_follow_camera()
	if OS.has_feature("web"):
		_setup_web()


func _on_thunder(strength: float) -> void:
	thunders += 1
	_thunder.volume_db = lerpf(-16.0, -6.0, clampf(strength, 0.0, 1.0))
	_thunder.play()


func _on_power(p: int, _duration: float) -> void:
	if p == NanoPalette.Power.NONE:
		return
	var on_pad := false
	for pad in find_children("*", "PowerPad", true, false):
		for b in (pad as Area2D).get_overlapping_bodies():
			if b is Cat:
				on_pad = true
	power_grants.append([p, on_pad])
	if p != NanoPalette.Power.SURGE or not on_pad:
		power_violations += 1


func _follow_camera() -> void:
	var cx := cat.camera.get_screen_center_position().x
	for n in RAIN_NODES:
		var r := get_node_or_null(n) as Node2D
		if r:
			r.global_position.x = cx


func _physics_process(delta: float) -> void:
	super(delta)
	_follow_camera()
	if OS.has_feature("web"):
		_publish()


# ---- web debug --------------------------------------------------------------

func _setup_web() -> void:
	var win := JavaScriptBridge.get_interface("window")
	var cb := JavaScriptBridge.create_callback(func(a):
		cat.global_position = Vector2(float(a[0]), float(a[1]))
		cat.velocity = Vector2.ZERO)
	_js_callbacks.append(cb)
	win["wakeTeleport"] = cb
	var strike := JavaScriptBridge.create_callback(func(_a):
		if _lightning:
			_lightning.strike(1.0))
	_js_callbacks.append(strike)
	win["wakeStrike"] = strike


func _flag(node_name: String, prop: String) -> Variant:
	var n := get_node_or_null(node_name)
	return n.get(prop) if n else null


func _probe(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	return not cat.get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _publish() -> void:
	var hud := get_node_or_null("Hud") as CanvasLayer
	var d := {
		"f": Engine.get_physics_frames(),
		"x": cat.global_position.x, "y": cat.global_position.y,
		"vx": cat.velocity.x, "vy": cat.velocity.y, "floor": cat.is_on_floor(),
		"hp": GameState.health, "score": GameState.score, "power": GameState.power,
		"powerTime": GameState.power_time,
		"shock": GameState.shockwave_unlocked, "mind": GameState.intelligence, "dead": cat.dead,
		"crouch": cat.crouched, "save": SaveSystem.has_save(),
		"cp": SaveSystem.session_checkpoint, "scene": get_tree().current_scene.scene_file_path,
		"can_move": cat.can_move, "anim": cat.sprite.animation,
		"hud": hud.visible if hud else false,
		"violations": power_violations, "grants": power_grants.size(),
		"mono": Monologue.history.size(), "monoIds": Monologue.history.map(func(l): return l[0]),
		"speaking": Monologue.is_speaking(),
		"gateShut": _flag("TimedGate", "open") == false, "gateLeft": _flag("TimedGate", "time_left"),
		"plate": _flag("GatePlate", "active"),
		"drone": _flag("SearchDrone", "state"), "droneX": _flag("SearchDrone", "global_position"),
		"lit": _flag("SearchDrone", "lit"), "alarm": _flag("SearchDrone", "alarmed"),
		"dock": _flag("DockBot", "wake"), "dockReacted": _flag("DockBot", "has_reacted"),
		"thunders": thunders, "flash": _lightning._level if _lightning else 0.0,
		# Probes for the audit's reactive runner: a wall 34 px ahead, floor within 80 px below, bots.
		"wallAhead": _probe(cat.global_position + Vector2(0, -8), cat.global_position + Vector2(34, -8)),
		"groundBelow": _probe(cat.global_position + Vector2(0, -2), cat.global_position + Vector2(0, 80)),
		"bots": get_tree().get_nodes_in_group("enemy").map(func(b): return [b.global_position.x, b.global_position.y]),
		"cam": [cat.camera.get_screen_center_position().x, cat.camera.get_screen_center_position().y],
	}
	var dp = d["droneX"]
	d["droneX"] = dp.x if dp is Vector2 else null
	JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
