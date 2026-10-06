class_name Room4
extends Level
## Room 4, "The Perimeter": the security checkpoint at the edge of the
## automated district, the storm's last gasp, then dawn. The cat arrives with
## its mind awake, the shockwave unlocked, and having met Surge and Spring. This
## room introduces the last two powers, one step at a time:
##   Phase   1 discovery (one laser fence, a safe run-up, no other route)
##           2 use (a corridor of fences and guard drones, a laser turret)
##           3 combine with Spring (up onto a guardhouse roof, then a fence)
##   Impact  1 discovery (a cracked floor below the pad, down to a tunnel)
##           2 use (an armoured bot stunned by the pound, chained hatches)
##           3 combine with the shockwave and Phase (a shield wall, a fence)
## and then the Master Gate: three power relays (Spring to a high console,
## Phase through a laser maze, Impact and the shockwave in a lower vault), the
## security scanner, "supervisor credential accepted", and the way out to the
## dawn-lit road. See PerimeterFinale. The sky lightens with the cat's x
## (SkyProgress).
##
## Direct start or test: the room makes sure the mind and the shockwave are set.
##
## Web debug hooks for tools/audit/web_room4.mjs: window.__wake is published
## every physics frame; window.wakeTeleport(x, y) moves the cat and
## window.wakeStrike() fires a lightning strike.

const RAIN_NODES := ["RainFar", "RainNear"]
## Phase's dash lasts a little longer here than the cat's default (0.16 s): a
## fence is 6 px of beam to a 22 px cat, and 0.2 s (82 px) makes the window to
## press Shift about a third of a second.
const DASH_TIME := 0.2

var power_grants: Array = []     ## [power, on_a_pad] per grant, in order
var thunders := 0
var finale: PerimeterFinale
var sky: SkyProgress
var _js_callbacks: Array = []
var _fences: Array = []
var _drones: Array = []
var _lightning: LightningFX
var _thunder: AudioStreamPlayer


func _enter_tree() -> void:
	super()
	# Safety net for a direct start (testing): the story has given the cat its mind and the shockwave.
	if not GameState.intelligence or not GameState.shockwave_unlocked:
		GameState.intelligence = true
		GameState.shockwave_unlocked = true
		SaveSystem.session_snapshot = GameState.snapshot()


func _ready() -> void:
	super()
	cat.death_y = deep_bottom + 200
	cat.dash_time = DASH_TIME
	_thunder = AudioStreamPlayer.new()
	_thunder.bus = &"SFX"
	add_child(_thunder)
	_lightning = get_node_or_null("Lightning") as LightningFX
	if _lightning:
		_lightning.thunder.connect(_on_thunder)
	sky = get_node_or_null("SkyProgress") as SkyProgress
	finale = get_node_or_null("Finale") as PerimeterFinale
	GameState.power_changed.connect(_on_power)
	if sky:
		sky.snap()
	_follow_camera()
	if OS.has_feature("web"):
		_fences = find_children("*", "LaserFence", true, false)
		_drones = find_children("*", "GuardDrone", true, false)
		_setup_web()


func _on_thunder(strength: float) -> void:
	thunders += 1
	_thunder.stream = Sfx.stream("thunder")
	_thunder.volume_db = Sfx.level_db("thunder") + lerpf(-9.0, 0.0, clampf(strength, 0.0, 1.0))
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


func _follow_camera() -> void:
	var cx := cat.camera.get_screen_center_position().x
	for n in RAIN_NODES:
		var r := get_node_or_null(n) as Node2D
		if r:
			r.global_position.x = cx


func _physics_process(delta: float) -> void:
	super(delta)
	_follow_camera()
	# Falling through a hatch: the camera floor drops with the cat (Level eases it at 6 px a frame,
	# which would leave the cat at the bottom edge for the first drop).
	if cat.global_position.y > 330.0:
		cat.camera.limit_bottom = maxi(cat.camera.limit_bottom, mini(int(cat.global_position.y) + 150, deep_bottom))
	if OS.has_feature("web"):
		_publish()


# ---- web debug --------------------------------------------------------------

func _setup_web() -> void:
	var win := JavaScriptBridge.get_interface("window")
	var cb := JavaScriptBridge.create_callback(func(a):
		cat.global_position = Vector2(float(a[0]), float(a[1]))
		cat.velocity = Vector2.ZERO
		if sky:
			sky.snap())
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
	var tint := Color.WHITE
	if sky and sky.rig:
		tint = sky.rig.get_canvas_modulate().color
	var scanner := get_node_or_null("Scanner") as SecurityScanner
	var gate := get_node_or_null("MasterGate") as MasterGate
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
		"mono": Monologue.history.size(), "monoIds": Monologue.history.map(func(l): return l[0]),
		"monoText": Monologue.history.map(func(l): return l[1]),
		"speaking": Monologue.is_speaking(),
		"phasing": cat.is_phasing(), "pounding": cat.pounding,
		"relays": finale.count if finale else 0,
		"relayLit": [_flag("Relay1", "lit"), _flag("Relay2", "lit"), _flag("Relay3", "lit")],
		"scanMode": scanner.mode if scanner else -1,
		"scanText": Array(scanner.screen_lines) if scanner else [],
		"scanning": finale.scanning if finale else false,
		"accepted": finale.accepted if finale else false,
		"pans": finale.pans if finale else 0, "panning": finale.panning if finale else false,
		"gateOpen": gate.is_open if gate else false, "gateLift": gate.lift if gate else 0.0,
		"sky": sky.progress if sky else 0.0, "dawn": sky.dawn if sky else 0.0,
		"tint": [tint.r, tint.g, tint.b],
		"hatches": get_tree().get_nodes_in_group("breakable").size(),
		"shields": [is_instance_valid(get_node_or_null("ShieldS1")), is_instance_valid(get_node_or_null("ShieldS2"))],
		"turret": _flag("TurretP2", "state"),
		"thunders": thunders, "flash": _lightning._level if _lightning else 0.0,
		"wallAhead": _probe(cat.global_position + Vector2(0, -8), cat.global_position + Vector2(34, -8)),
		"groundBelow": _probe(cat.global_position + Vector2(0, -2), cat.global_position + Vector2(0, 80)),
		"obs": _fences.map(func(f): return [f.global_position.x, f.global_position.y, 0]) + _drones.map(func(f): return [f.global_position.x, f.global_position.y, 1]),
		"bots": get_tree().get_nodes_in_group("enemy").map(func(b): return [b.global_position.x, b.global_position.y, b.get("state")]),
		"cam": [cat.camera.get_screen_center_position().x, cat.camera.get_screen_center_position().y],
	}
	d["loops"] = LoopSfx.census_cached(get_tree())
	d["audio"] = AudioDirector.web_state()
	JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
