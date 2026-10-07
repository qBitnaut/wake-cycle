## Audibility and mix audit: runs a real scene, measures what the buses actually carry and
## asserts that a narrated line is audible and sits on top of the beds.
##   godot --path . --audio-driver Pulse --script res://tools/audit/audio_levels.gd -- <scene> [secs]
## A real audio driver (Pulse/ALSA) is the honest measure; the dummy driver also mixes, so
## `--headless` gives numbers too, but only a real driver proves a device is fed. The web
## equivalent is tools/audit/web_audio_levels.mjs (an AnalyserNode on the AudioContext).
## Output: per bus, mean power and peak (dBFS) over the bed-only window and over the narrated
## line, as the AudioServer reports them (post-bus-volume, pre-Master), and Master.
## Exit code 1 when the Voice bus peak while a line is spoken is below VOICE_MIN_PEAK_DB, or the
## voice is not clearly above the beds.
extends SceneTree

const VOICE_MIN_PEAK_DB := -30.0
const BUSES := ["Master", "Music", "Ambience", "SFX", "Voice"]
const VOICE_OVER_BEDS_DB := 6.0

var _acc := {}   ## phase -> bus -> [sum_power, n, peak_db]
var _phase := ""
var _scene_path := "res://scenes/levels/room1.tscn"
var _bed_secs := 10.0
var _line := ["awakening", 1]
var _t := 0.0
var _state := 0
var _node: Node
var _bed_db := -80.0
var _voice_ok := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_scene_path = args[0]
	if args.size() > 1:
		_bed_secs = float(args[1])
	if args.size() > 2:
		_line = [args[2], int(args[3]) if args.size() > 3 else 0]
	var sc: Node = load(_scene_path).instantiate()
	root.add_child(sc)
	current_scene = sc
	_phase = "wait"
	process_frame.connect(_sample)


func _sample() -> void:
	var dt := root.get_process_delta_time()
	_t += dt
	var ad := root.get_node("AudioDirector")
	var mono := root.get_node("Monologue")
	if not ad.is_unlocked:
		ad.unlock()
	if _phase != "wait":
		var a: Dictionary = _acc.get(_phase, {})
		for b in BUSES:
			var i := AudioServer.get_bus_index(b)
			if i < 0:
				continue
			var pk := maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))
			var e: Array = a.get(b, [0.0, 0, -200.0])
			e[0] += db_to_linear(pk) * db_to_linear(pk)
			e[1] += 1
			e[2] = maxf(e[2], pk)
			a[b] = e
		_acc[_phase] = a
	match _state:
		0:
			if _t > 2.5:   # beds and music have faded in
				_phase = "beds"
				_t = 0.0
				_state = 1
		1:
			if _t > _bed_secs:
				_dump_players()
				mono.reset()
				mono.play_line(_line[0], _line[1])
				_phase = "voice"
				_t = 0.0
				_state = 2
		2:
			if _t > 3.0:
				_report()
				quit(0 if _voice_ok else 1)
				_state = 3


func _rms_db(phase: String, bus: String) -> float:
	var e: Array = _acc.get(phase, {}).get(bus, [0.0, 0, -200.0])
	return linear_to_db(sqrt(e[0] / maxf(1.0, e[1])))


func _pk(phase: String, bus: String) -> float:
	return _acc.get(phase, {}).get(bus, [0.0, 0, -200.0])[2]


func _report() -> void:
	print("== audio levels  scene=%s  driver=%s" % [_scene_path.get_file(), AudioServer.get_output_device()])
	for ph in ["beds", "voice"]:
		for b in BUSES:
			print("  %-5s %-9s rms %6.1f dB  peak %6.1f dB" % [ph, b, _rms_db(ph, b), _pk(ph, b)])
	var vp := _pk("voice", "Voice")
	var bed_rms := maxf(_rms_db("beds", "Ambience"), _rms_db("beds", "Music"))
	var v_rms := _rms_db("voice", "Voice")
	_voice_ok = vp > VOICE_MIN_PEAK_DB and v_rms > bed_rms + VOICE_OVER_BEDS_DB
	print("  voice peak %.1f dB (need > %.0f)  voice rms %.1f vs loudest bed rms %.1f (need +%.0f)  -> %s" % [vp, VOICE_MIN_PEAK_DB, v_rms, bed_rms, VOICE_OVER_BEDS_DB, "PASS" if _voice_ok else "FAIL"])


func _dump_players() -> void:
	for n in _walk(root):
		if n is AudioStreamPlayer and n.playing and n.bus in [&"SFX", &"Master", &"Ambience"]:
			print("  playing %s bus=%s db=%.1f stream=%s" % [n.get_path(), n.bus, n.volume_db, n.stream.resource_path.get_file() if n.stream else "?"])


func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
