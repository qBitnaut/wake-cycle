## Renders frame sequences of kit actors in the lab (needs a display or xvfb):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##       --script res://tools/audit/kit_shots.gd -- <scenario> <outdir>
## Writes <outdir>/<scenario>_NN.png; tools/art/kit_strips.py stitches them into strips.
## Scenarios: sentry patrol drone hopper crawler camera mech barrels walls electric
## crusher spikes vents debris platforms collectibles conveyor and defeat_<enemy>.
extends SceneTree

var lab: Node
var scenario := ""
var outdir := ""
var n := 0
var every := 6
var count := 12
var start_at := 30
var shots := 0
var actions := {}   # frame -> Callable


func gs() -> Node:
	return root.get_node("GameState")


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	scenario = a[0]
	outdir = a[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	lab = load("res://scenes/lab/kit_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	_setup.call_deferred()


func arena(i: int) -> Node:
	return lab.arena_nodes[i]


func first(i: int, group: String) -> Node:
	for c in arena(i).get_children():
		if c.is_in_group(group):
			return c
	return null


func at_cat(i: int, lx: float, y := 320.0) -> void:
	lab.cat.global_position = Vector2(lab.arena_x(i) + lx, y)
	lab.cat.velocity = Vector2.ZERO


func _setup() -> void:
	gs().new_game()
	var s := scenario
	if s.begins_with("defeat_"):
		_defeat(s.substr(7))
		return
	match s:
		"sentry":
			at_cat(1, 250)
			every = 7
			count = 14
		"patrol":
			at_cat(2, 250)
			arena(2).get_child(0).speed = 0.001
			every = 6
			count = 14
		"drone":
			at_cat(3, 330)
			arena(3).get_child(0).patrol_range = 0.0
			every = 8
			count = 14
		"hopper":
			at_cat(4, 300)
			every = 8
			count = 14
		"crawler":
			at_cat(5, 300)
			every = 9
			count = 14
		"camera":
			gs().grant_power(4, 600.0)
			at_cat(6, 200)
			every = 14
			count = 14
		"mech":
			at_cat(7, 250)
			arena(7).get_child(0).dir = -1
			every = 9
			count = 14
		"barrels":
			gs().shockwave_unlocked = true
			at_cat(8, 180)
			start_at = 20
			every = 3
			count = 14
			actions[24] = func(): first(8, "explosive").trigger(0.0)
		"walls":
			gs().shockwave_unlocked = true
			gs().grant_power(4, 600.0)
			at_cat(9, 100)
			every = 4
			count = 12
			actions[24] = func():
				for w in arena(9).get_children():
					if w.has_method("break_it"):
						w.on_shockwave(Vector2.ZERO, 50.0, "pound")
		"electric":
			at_cat(10, 40)
			every = 12
			count = 14
			start_at = 10
		"spikes":
			at_cat(10, 240)
			every = 12
			count = 14
			start_at = 40
		"crusher":
			at_cat(10, 380)
			every = 12
			count = 14
			start_at = 20
		"vents":
			at_cat(11, 160)
			every = 12
			count = 14
			start_at = 10
		"debris":
			at_cat(11, 420)
			every = 6
			count = 14
			start_at = 10
			actions[12] = func(): at_cat(11, 490)
		"platforms":
			at_cat(13, 300, 250)
			every = 20
			count = 14
		"collectibles":
			at_cat(14, 280)
			every = 10
			count = 3
		"conveyor":
			at_cat(12, 150)
			every = 12
			count = 8
		_:
			push_error("unknown scenario " + s)
			quit(1)


func _defeat(id: String) -> void:  # coroutine: waits a frame for the arena
	var map := {"patrol": [2, "kit_enemy"], "hopper": [4, "kit_enemy"], "drone": [3, "kit_enemy"], "mech": [7, "kit_enemy"],
		"sentry": [1, "kit_turret"], "crawler": [5, "kit_enemy"]}
	var m: Array = map[id]
	var e := first(m[0], m[1])
	if id == "sentry":
		e = first(1, "kit_turret")
	await process_frame
	at_cat(m[0], 0)
	lab.cat.global_position.x = e.global_position.x - (110.0 if id == "mech" else 80.0)
	if id == "patrol":
		e.speed = 0.001
		e.shoots = false
	if id == "drone":
		e.patrol_range = 0.0
	e.set("chip_chance", 1.0)
	gs().grant_power(4, 600.0)
	gs().shockwave_unlocked = true
	start_at = 30
	every = 4
	count = 14
	actions[40] = func():
		if is_instance_valid(e):
			e.hit("pound")
			e.hit("pound")
			e.hit("pound")


func _process(_d: float) -> bool:
	n += 1
	if actions.has(n):
		actions[n].call()
	if n >= start_at and (n - start_at) % every == 0 and shots < count:
		var img := root.get_texture().get_image()
		img.save_png("%s/%s_%02d.png" % [outdir, scenario, shots])
		shots += 1
		if shots >= count:
			print("SHOTS ", scenario, " ", shots)
			quit()
	return false
