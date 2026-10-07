## What dominates the sound in Room 1 at a few spots: per bus level, per looping player (its
## effective dB: player volume plus bus) and per one-shot (count, manifest level), over a few
## seconds at each spot. A mix tool, not a pass/fail audit.
##   godot --headless --path . --script res://tools/audit/room1_mix.gd -- [secs_per_spot]
extends SceneTree

const BUSES := ["Master", "Music", "Ambience", "SFX", "Voice"]

var _secs := 8.0
var _room: Node
var _cat: Node2D
var _spots := []
var _i := -1
var _t := 0.0
var _acc := {}      ## bus -> [sum_power, n, peak]
var _loops := {}    ## label -> max effective dB
var _shots := {}    ## name -> count
var _started := false
var _warm := 3.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	args.erase("--skip-intro")
	if args.size() > 0:
		_secs = float(args[0])
	_room = load("res://scenes/levels/room1.tscn").instantiate()
	root.add_child(_room)
	current_scene = _room
	process_frame.connect(_tick)


func _bus_db(bus: StringName) -> float:
	var db := 0.0
	var b := AudioServer.get_bus_index(bus)
	while b > 0:
		db += AudioServer.get_bus_volume_db(b)
		b = AudioServer.get_bus_index(AudioServer.get_bus_send(b))
	return db


func _setup_spots() -> void:
	_cat = _room.get_node("Cat")
	var find := func(cls: String) -> Node2D:
		for n in _room.find_children("*", cls, true, false):
			return n
		return null
	var cr: Node2D = _room.get_node_or_null("Crusher1")
	var cv: Node2D = find.call("KitConveyor")
	var bm: Node2D = _room.get_node_or_null("BotMachine")
	var lab: Node2D = _room.get_node_or_null("LampLab")
	_spots = [["opening nook", _cat.global_position]]
	if cr:
		_spots.append(["crusher", cr.global_position + Vector2(0, 150)])
	if cv:
		_spots.append(["conveyor", cv.global_position + Vector2(0, -20)])
	if bm:
		_spots.append(["machine corridor", bm.global_position])
	if lab:
		_spots.append(["lab", lab.global_position + Vector2(0, 90)])


func _tick() -> void:
	var dt := root.get_process_delta_time()
	var ad := root.get_node("AudioDirector")
	if not ad.is_unlocked:
		ad.unlock()
	_t += dt
	if not _started:
		if _t < _warm:
			return
		_started = true
		_setup_spots()
		KitSfx.record = true
		_next()
		return
	if not is_instance_valid(_cat):
		print("cat gone, stopping")
		quit(1)
		return
	_cat.set("_invuln", 999.0)   # a spot inside a hazard must not kill the audit
	_cat.global_position = _spots[_i][1]
	_cat.velocity = Vector2.ZERO
	for b in BUSES:
		var bi := AudioServer.get_bus_index(b)
		var pk := maxf(AudioServer.get_bus_peak_volume_left_db(bi, 0), AudioServer.get_bus_peak_volume_right_db(bi, 0))
		var e: Array = _acc.get(b, [0.0, 0, -200.0])
		e[0] += db_to_linear(pk) * db_to_linear(pk)
		e[1] += 1
		e[2] = maxf(e[2], pk)
		_acc[b] = e
	for n in _walk(root):
		if (n is AudioStreamPlayer or n is AudioStreamPlayer2D) and n.playing and not n.stream_paused:
			if _is_loop(n.stream) or n.name == "Bed" or n.name.begins_with("Music"):
				var label := "%s/%s %s" % [n.get_parent().get_parent().name if n.get_parent() is LoopSfx else n.get_parent().name, n.name, n.stream.resource_path.get_file()]
				_loops[label] = maxf(_loops.get(label, -200.0), n.volume_db + _bus_db(n.bus))
	if _t > _secs:
		_report()
		_next()


func _is_loop(s: AudioStream) -> bool:
	if s == null:
		return false
	var v = s.get("loop")
	return v != null and bool(v)


func _next() -> void:
	_i += 1
	if _i >= _spots.size():
		quit(0)
		return
	_t = 0.0
	_acc = {}
	_loops = {}
	Sfx.played.clear()
	KitSfx.log.clear()


func _report() -> void:
	print("== %s  (%d, %d)" % [_spots[_i][0], _spots[_i][1].x, _spots[_i][1].y])
	var line := "  buses (rms/peak dB):"
	for b in BUSES:
		var e: Array = _acc.get(b, [0.0, 1, -200.0])
		line += "  %s %.1f/%.1f" % [b, linear_to_db(sqrt(e[0] / maxf(1.0, e[1]))), e[2]]
	print(line)
	var keys := _loops.keys()
	keys.sort_custom(func(a, b): return _loops[a] > _loops[b])
	for k in keys:
		print("  loop  %6.1f dB  %s" % [_loops[k], k])
	var counts := {}
	for s in Sfx.played:
		counts[s] = counts.get(s, 0) + 1
	for s in KitSfx.log:
		counts["kit:" + s] = counts.get("kit:" + s, 0) + 1
	var ck := counts.keys()
	ck.sort_custom(func(a, b): return counts[a] > counts[b])
	for k in ck:
		var nm: String = k.trim_prefix("kit:")
		print("  shot  x%-3d %6.1f dB (manifest)  %s" % [counts[k], Sfx.level_db(nm) + _bus_db(&"SFX"), k])


func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
