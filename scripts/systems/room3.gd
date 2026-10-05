class_name Room3
extends Level
## Room 3, "The Stacks": rooftops and container towers above the yard, the rain
## easing. The cat arrives with its mind awake and Surge behind it, and the
## room teaches Spring and then the shockwave with level design and the cat's
## own thoughts only:
##   1 discovery  a Spring pad at the foot of a 7-tile wall, a ledge above
##   2 use it     a chain of Spring jumps up two ledges to the long roof
##   conduit      a sparking power conduit (unavoidable, harmless): the shockwave
##   shockwave    a crate stack, a patrol bot in a low corridor, a shock switch and shutter
##   mirror       a loader bot that copies the cat's steps: walk it onto its plate
##   3 combine    Spring up a tower, Surge across a ten-tile gap, to the exit roof
##
## Powers come only from the PowerPads here (Spring and Surge); the shockwave
## only from the ConduitEvent. `power_grants`, `power_violations` and
## `shock_unlocks` are audit hooks. The rain follows the camera in both axes
## (the room is tall), the night skyline sits on the horizon below the view and
## the suburbs fade in towards the exit.
##
## Web debug hooks for tools/audit/web_room3.mjs: window.__wake is published
## every physics frame; window.wakeTeleport(x, y) moves the cat.

const RAIN_NODES := ["RainFar", "RainNear"]
const HORIZON_BELOW_CENTRE := 70.0   ## the skyline's base sits this far under the camera centre

var power_grants: Array = []     ## [power, on_a_pad] per grant, in order
var power_violations := 0        ## grants that were not Spring or Surge, or not from a pad
var shock_unlocks: Array = []    ## [x, y, at_conduit] per unlock event
var crates_total := 0
var _js_callbacks: Array = []
var _shock_line_done := false
## World rects (set by the builder) under a roof: the near rain is switched off in them.
@export var covered: Array[Rect2] = []
var _rain_near_k := 1.0
var _exterior: Node2D
var _suburbs: Node2D
var _crates: Array[Node] = []


func _ready() -> void:
	super()
	GameState.power_changed.connect(_on_power)
	GameState.shockwave_unlock_changed.connect(_on_unlock)
	_exterior = get_node_or_null("Exterior")
	_suburbs = get_node_or_null("Suburbs")
	for c in get_tree().get_nodes_in_group("breakable"):
		# Crates already broken in an earlier visit free themselves in their own _ready.
		if is_ancestor_of(c) and not c.is_queued_for_deletion():
			_crates.append(c)
	crates_total = _crates.size()
	_follow_camera(1.0)
	if OS.has_feature("web"):
		_setup_web()


func _on_power(p: int, _duration: float) -> void:
	if p == NanoPalette.Power.NONE:
		return
	var on_pad := false
	for pad in find_children("*", "PowerPad", true, false):
		for b in (pad as Area2D).get_overlapping_bodies():
			if b is Cat:
				on_pad = true
	power_grants.append([p, on_pad])
	if (p != NanoPalette.Power.SPRING and p != NanoPalette.Power.SURGE) or not on_pad:
		power_violations += 1


func _on_unlock(on: bool) -> void:
	if not on:
		return
	var conduit := get_node_or_null("Conduit") as ConduitEvent
	var at_conduit := conduit != null and conduit.has_fired
	shock_unlocks.append([cat.global_position.x, cat.global_position.y, at_conduit])
	if not at_conduit:
		power_violations += 1


func _follow_camera(delta: float) -> void:
	var c := cat.camera.get_screen_center_position()
	for n in RAIN_NODES:
		var r := get_node_or_null(n) as Node2D
		if r:
			r.global_position = Vector2(c.x, c.y - 190.0)
	# The near rain stays out from under roofs.
	var under := false
	for rc in covered:
		if rc.has_point(cat.global_position + Vector2(0, -16)):
			under = true
	_rain_near_k = move_toward(_rain_near_k, 0.0 if under else 1.0, delta * 2.5)
	var near := get_node_or_null("RainNear") as CanvasItem
	if near:
		near.modulate.a = _rain_near_k
	if _exterior:
		_exterior.global_position.y = c.y + HORIZON_BELOW_CENTRE
	if _suburbs:
		_suburbs.global_position.y = c.y + HORIZON_BELOW_CENTRE


func _physics_process(delta: float) -> void:
	super(delta)
	_follow_camera(delta)
	if not _shock_line_done:
		for c in _crates:
			if not is_instance_valid(c) or c.is_queued_for_deletion():
				_shock_line_done = true
				Monologue.play_once("shock_first")
				break
	if OS.has_feature("web"):
		_publish()


func crates_left() -> int:
	var n := 0
	for c in _crates:
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			n += 1
	return n


# ---- web debug --------------------------------------------------------------

func _setup_web() -> void:
	var win := JavaScriptBridge.get_interface("window")
	var cb := JavaScriptBridge.create_callback(func(a):
		cat.global_position = Vector2(float(a[0]), float(a[1]))
		cat.velocity = Vector2.ZERO)
	_js_callbacks.append(cb)
	win["wakeTeleport"] = cb


func _flag(node_name: String, prop: String) -> Variant:
	var n := get_node_or_null(node_name)
	return n.get(prop) if n else null


func _probe(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	return not cat.get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _publish() -> void:
	var hud := get_node_or_null("Hud") as CanvasLayer
	var bot := get_node_or_null("MirrorBot") as MirrorBot
	var patrol := get_node_or_null("StackBot") as PatrolBot
	var d := {
		"f": Engine.get_physics_frames(),
		"x": cat.global_position.x, "y": cat.global_position.y,
		"vx": cat.velocity.x, "vy": cat.velocity.y, "floor": cat.is_on_floor(),
		"hp": GameState.health, "power": GameState.power, "powerTime": GameState.power_time,
		"shock": GameState.shockwave_unlocked, "mind": GameState.intelligence, "dead": cat.dead,
		"crouch": cat.crouched, "save": SaveSystem.has_save(),
		"cp": SaveSystem.session_checkpoint, "scene": get_tree().current_scene.scene_file_path,
		"can_move": cat.can_move, "anim": cat.sprite.animation, "hud": hud.visible if hud else false,
		"violations": power_violations, "grants": power_grants.size(), "unlocks": shock_unlocks.size(),
		"mono": Monologue.history.size(), "monoIds": Monologue.history.map(func(l): return l[0]),
		"speaking": Monologue.is_speaking(),
		"crates": crates_left(), "switch": _flag("ShockSwitch", "active"), "shutter": _flag("GalleryShutter", "open"),
		"patrol": [patrol.global_position.x, patrol.global_position.y, int(patrol.state)] if patrol else null,
		"mirror": [bot.global_position.x, bot.global_position.y, bot.awake] if bot else null,
		"plate": _flag("BayPlate", "active"), "bayShutter": _flag("BayShutter", "open"),
		"cam": [cat.camera.get_screen_center_position().x, cat.camera.get_screen_center_position().y],
		# Probes for the audit's reactive runner: a wall 34 px ahead, floor within 80 px below, patrol bots.
		"wallAhead": _probe(cat.global_position + Vector2(0, -8), cat.global_position + Vector2(34, -8)),
		"groundBelow": _probe(cat.global_position + Vector2(0, -2), cat.global_position + Vector2(0, 80)),
		"bots": get_tree().get_nodes_in_group("enemy").map(func(b): return [b.global_position.x, b.global_position.y]),
	}
	d["loops"] = LoopSfx.census_cached(get_tree())
	JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))
