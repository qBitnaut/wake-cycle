extends Node
## The audio director, the autoload "AudioDirector": buses, music, the scene's sound and
## ducking. Everything that is not a one-shot (see Sfx) or a positional loop (LoopSfx).
##
## Buses: Master <- Music, Ambience, SFX, Voice, laid out STATICALLY in res://default_bus_layout.tres
## (project setting audio/buses/default_bus_layout). They must exist before any player does: on the
## web a one-shot is a sample, and samples are only routed to buses present at start-up (a bus
## added at run time left every SFX one-shot silent). _make_buses only sets the levels (and adds
## a bus that is missing, as a fallback).
##
## Music: one track per scene, chosen by the scene's file (PROFILES). When the scene
## changes the new track fades in over CROSSFADE seconds while the old one fades out, on a
## pair of players. Home asks for its own track when the ending begins (play_music), the
## credits keep whatever is playing, and the map has its own. Tracks are seamless loops
## made by tools/audio/gen_music.py (loop = true in their .import).
##
## Ambience: a room's bed belongs to its Ambience node (so it goes with the scene); the
## map and credits, which have none, get theirs here (BEDS).
##
## Ducking: while the cat's voice plays (Monologue.voice_active) the Music and Ambience
## buses sink by DUCK_MUSIC / DUCK_AMB and come back after it. A memory fragment
## (Monologue.memory_active) ducks deeper (MEMORY_*), slower in and slower out.
##
## Web: audio only starts after the first key, click or touch (the browser keeps the
## audio context suspended until then). Loops are always played as streams
## (playback_type STREAM), never as the web's default samples, which cannot be stopped or
## re-levelled reliably (see LoopSfx).

signal music_changed(key: String)
signal unlocked

const MUSIC_DIR := "res://assets/audio/music/wc_%s.ogg"
const BED_DIR := "res://assets/audio/amb/%s.ogg"
const CROSSFADE := 2.5
const MUSIC_DB := -7.0
const SILENT_DB := -60.0
const DUCK_MUSIC := -9.0
const DUCK_AMB := -7.0
const DUCK_IN := 0.25
const MEMORY_MUSIC := -18.0
const MEMORY_AMB := -14.0
const MEMORY_IN := 0.8
const MEMORY_OUT := 2.0
const DUCK_OUT := 1.2
## Bus levels, dB. The mix, as heard (integrated loudness): voice about -18 LUFS and always on
## top, SFX about -20, music about -27, every scene bed about -32 (atmosphere, not a wall).
## The voice clips are -16 LUFS files, so the Voice bus is a little under 0 and the Master
## never clips (Master is -3 dB in default_bus_layout.tres: headroom by gain, because bus effects
## such as a limiter do not apply to web sample playback); the bed files differ in loudness, so BED_TRIM_DB levels each to the same -32.
const BUS_DB := {"Music": 0.0, "Ambience": -3.0, "SFX": -4.0, "Voice": -2.0}
## Per-bed trim, dB (what each file needs to land at the same level as heard, with the room's
## rain_db of -6 and the Ambience bus above). amb_warehouse and the rest were measured with
## ffmpeg ebur128 (-23.0, -14.3, -19.4, -22.8, -23.4, -15.7 LUFS).
const BED_TRIM_DB := {
	"amb_warehouse": 0.0, "amb_yard": -8.7, "amb_stacks": -5.6, "amb_perimeter": -0.2,
	"amb_home": 0.0, "amb_map": -3.3,
}
## Scene file -> music key ("" = none, "keep" = leave whatever plays).
const PROFILES := {
	"room1.tscn": "warehouse",
	"room2.tscn": "yard",
	"room3.tscn": "stacks",
	"room4.tscn": "perimeter",
	"test_room.tscn": "warehouse",
	"home.tscn": "",
	"credits.tscn": "keep",
	"world_map.tscn": "map",
}
## Scene file -> a bed this director plays (scenes without an Ambience node).
const BEDS := {"world_map.tscn": "amb_map"}

## Whether sound has been allowed to start (always true off the web).
var is_unlocked := not OS.has_feature("web")
var music_key := ""
var scene_key := ""   ## the profile key of the current scene file
## Every change of music, in order: [key, fade seconds]. For audits.
var music_log: Array = []

var _players: Array[AudioStreamPlayer] = []   ## the music pair
var _live := 0                                ## index of the player that carries music_key
var _fades: Array = [null, null]
var _bed: AudioStreamPlayer
var _bed_key := ""
var _pending := ""                            ## a music key asked for before the unlock
var _pending_fade := CROSSFADE
var _memory_duck := 0.0                       ## 0..1 how deep the duck is (memory fragment)
var _duck := 0.0                              ## 0..1 how far the buses are ducked
var _scene_path := "?"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = &"Music"
		p.volume_db = SILENT_DB
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(p)
		_players.append(p)
	_bed = AudioStreamPlayer.new()
	_bed.name = "Bed"
	_bed.bus = &"Ambience"
	_bed.volume_db = SILENT_DB
	_bed.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_bed)
	if OS.has_feature("web") and true:
		_setup_web_hooks()


var _js_callbacks: Array = []


## Debug web builds only (tools/audit/web_sfx_levels.mjs), in every scene:
## wakeSfx(name) plays one sound through the game's own path (Sfx.play, else KitSfx.play),
## "meow:<n>" one variant of the meow, "loop:<name>" attaches a LoopSfx to the cat for 3 s; wakeBus(name, muted) mutes a bus.
func _setup_web_hooks() -> void:
	var win := JavaScriptBridge.get_interface("window")
	var sfx := JavaScriptBridge.create_callback(func(a):
		var n := String(a[0])
		var cat := get_tree().get_first_node_in_group("player") as Node2D
		if n.begins_with("loop:"):
			var st := KitSfx.library_stream(n.substr(5))
			if st != null and cat != null:
				var l := LoopSfx.attach(cat, st, Sfx.level_db(n.substr(5)), 1.0, 420.0)
				get_tree().create_timer(3.0).timeout.connect(l.retire)
		elif n.begins_with("meow:"):
			Sfx.play(self, "meow", 0.0, 1.0, int(n.substr(5)))  # one variant of the cat's meow
		elif Sfx.has(n):
			Sfx.play(self, n)
		else:
			KitSfx.play(self, n))
	_js_callbacks.append(sfx)
	win["wakeSfx"] = sfx
	var bus := JavaScriptBridge.create_callback(func(a):
		AudioServer.set_bus_mute(AudioServer.get_bus_index(String(a[0])), bool(a[1])))
	_js_callbacks.append(bus)
	win["wakeBus"] = bus


func _make_buses() -> void:
	for n in ["Music", "Ambience", "SFX", "Voice"]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, &"Master")
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(n), BUS_DB[n])


func _input(event: InputEvent) -> void:
	if is_unlocked:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton:
		unlock()


## Allow sound to start (the first input on the web). Starts what was waiting.
func unlock() -> void:
	if is_unlocked:
		return
	is_unlocked = true
	unlocked.emit()
	_scene_path = "?"   # re-read the scene: music and bed start now
	if _pending != "":
		var k := _pending
		_pending = ""
		_start_music(k, _pending_fade)


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene else ""
	if path != _scene_path:
		_scene_path = path
		_on_scene(path.get_file())
	_update_duck(delta)
	for i in 2:
		var f: Tween = _fades[i]
		if f and not f.is_valid():
			_fades[i] = null
		var p := _players[i]
		if p.playing and p.volume_db <= SILENT_DB + 0.5 and (i != _live or music_key == ""):
			p.stop()


func _on_scene(file: String) -> void:
	scene_key = String(PROFILES.get(file, ""))
	if scene_key != "keep":
		play_music(scene_key)
	var bed := String(BEDS.get(file, ""))
	_set_bed(bed)


## Crossfade to the music `key` ("" fades it out). Same key: nothing happens.
func play_music(key: String, fade := CROSSFADE) -> AudioStreamPlayer:
	if key == music_key:
		return music_player()
	music_log.append([key, fade])
	if not is_unlocked:
		_pending = key
		_pending_fade = fade
		music_key = key
		music_changed.emit(key)
		return null
	return _start_music(key, fade)


func _start_music(key: String, fade: float) -> AudioStreamPlayer:
	var old := _players[_live]
	music_key = key
	music_changed.emit(key)
	if is_instance_valid(old) and old.playing:
		_fade(_live, SILENT_DB, fade)
	if key == "":
		return null
	var path := MUSIC_DIR % key
	if not ResourceLoader.exists(path):
		push_warning("AudioDirector: no music '%s'" % key)
		music_key = ""
		return null
	_live = 1 - _live
	var p := _players[_live]
	var s: AudioStream = (load(path) as AudioStream).duplicate()
	s.set("loop", true)
	p.stream = s
	p.volume_db = SILENT_DB
	p.play()
	_fade(_live, MUSIC_DB, fade)
	return p


func _fade(i: int, to_db: float, seconds: float) -> void:
	var f: Tween = _fades[i]
	if f:
		f.kill()
	if seconds <= 0.0:
		_players[i].volume_db = to_db
		return
	_fades[i] = create_tween()
	_fades[i].tween_property(_players[i], "volume_db", to_db, seconds).set_trans(Tween.TRANS_SINE)


## Fade the music out (the credits end).
func stop_music(fade := 2.0) -> void:
	play_music("", fade)


## The player of the music that carries the current key (null when none).
func music_player() -> AudioStreamPlayer:
	return _players[_live] if music_key != "" and _players[_live].playing else null


## dB of the music now (-80 when none): an audit hook.
func music_db() -> float:
	var p := music_player()
	return p.volume_db if p else -80.0


## True while a crossfade is under way (both players audible).
func crossfading() -> bool:
	var n := 0
	for p in _players:
		if p.playing and p.volume_db > SILENT_DB + 3.0:
			n += 1
	return n > 1


func _set_bed(key: String) -> void:
	if key == _bed_key and (key == "" or _bed.playing or not is_unlocked):
		return
	_bed_key = key
	if key == "":
		_bed.stop()
		return
	if not is_unlocked:
		return
	var s: AudioStream = (load(BED_DIR % key) as AudioStream).duplicate()
	s.set("loop", true)
	_bed.stream = s
	_bed.volume_db = SILENT_DB
	_bed.play()
	create_tween().tween_property(_bed, "volume_db", -10.0 + bed_trim(key), 2.0)


## The level trim of the bed file `key` (e.g. "amb_yard"), dB.
static func bed_trim(key: String) -> float:
	return float(BED_TRIM_DB.get(key, 0.0))


## A looping player for a scene's sound bed (rain, a hum): a stream, on `bus`, started once
## sound is unlocked. Child of `parent`, so it goes with the scene.
func loop_player(parent: Node, stream: AudioStream, db: float, bus := &"Ambience") -> AudioStreamPlayer:
	var s: AudioStream = stream.duplicate()
	s.set("loop", true)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	p.bus = bus
	p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	parent.add_child(p)
	if is_unlocked:
		p.play()
	else:
		unlocked.connect(p.play, CONNECT_ONE_SHOT)
	return p


func _update_duck(delta: float) -> void:
	var mem: bool = Monologue.memory_active
	var want := 1.0 if (Monologue.voice_active or mem) else 0.0
	_duck = move_toward(_duck, want, delta / ((MEMORY_IN if mem else DUCK_IN) if want > _duck else (MEMORY_OUT if _memory_duck > 0.0 else DUCK_OUT)))
	# Depth eases between the normal and the memory duck, so entering and leaving is smooth.
	_memory_duck = move_toward(_memory_duck, 1.0 if mem else 0.0, delta / (MEMORY_IN if mem else MEMORY_OUT))
	var dm := lerpf(DUCK_MUSIC, MEMORY_MUSIC, _memory_duck)
	var da := lerpf(DUCK_AMB, MEMORY_AMB, _memory_duck)
	var m := AudioServer.get_bus_index(&"Music")
	var a := AudioServer.get_bus_index(&"Ambience")
	if m >= 0:
		AudioServer.set_bus_volume_db(m, BUS_DB["Music"] + dm * _duck)
	if a >= 0:
		AudioServer.set_bus_volume_db(a, BUS_DB["Ambience"] + da * _duck)


## 0..1: how far the music and ambience are ducked under the voice (an audit hook).
func ducked() -> float:
	return _duck


## Published to window.__wake / window.__map by the scenes, for the web audits: what the
## director is doing. `voice` is [clips voiced so far, shortest hold minus (clip + tail) in
## seconds (>= 0 when every line was held long enough), the last clip's length].
func web_state() -> Dictionary:
	var log: Array = Monologue.voice_log
	var margin := 99.0
	for v in log:
		margin = minf(margin, float(v[3]) - float(v[2]) - Monologue.VOICE_TAIL)
	return {
		"music": music_key, "musicDb": music_db(), "fading": crossfading(), "duck": _duck,
		"unlocked": is_unlocked, "bed": _bed_key, "log": music_log.size(),
		"voice": [log.size(), margin, float(log.back()[2]) if not log.is_empty() else 0.0],
		"speaking": Monologue.voice_active,
	}
