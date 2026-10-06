class_name KitSfx
extends RefCounted
## Sound hooks for the actor kit, by LOGICAL NAME: KitSfx.play(self, "turret_fire").
##
## Resolution order for a name:
##   1. the audio library's manifest (res://assets/audio/sfx_manifest.json, either
##      {"name": "path"} or {"sounds": {"name": "path"}}), when it exists;
##   2. a file assets/audio/sfx_lib/<name>.ogg|.wav|.mp3 (the ElevenLabs library);
##   3. a stand-in from the shipped 8-bit set (PLACEHOLDERS), so a build with no
##      library still makes noise;
##   4. nothing: an unknown name is silently skipped.
## So the audio pass lands by dropping files in; no actor script changes. All
## names the kit uses are listed in LOGICAL_NAMES (and docs/KIT.md).

const LIB_DIR := "res://assets/audio/sfx_lib/"
const LIB_MANIFEST := "res://assets/audio/sfx_manifest.json"
## Set false to hear only the real library (no stand-ins).
static var use_placeholders := true
## Audit hook: every name requested, in order (cleared by the audit).
static var log: Array[String] = []
static var record := false

const LOGICAL_NAMES := [
	"turret_charge", "turret_fire", "laser_charge", "laser_zap", "drone_hover", "bomb_drop",
	"robot_explode", "robot_stun", "robot_clank", "debris", "barrel_explode", "barrel_fuse",
	"acid_hiss", "acid_splash", "electric_arc", "electric_warn", "crusher_warn", "crusher_slam",
	"spike_warn", "spike_pop", "steam_hiss", "flame_burst", "hopper_squat", "hopper_land",
	"crawler_drop", "camera_alarm", "camera_spot", "mech_charge", "mech_slam", "wall_break",
	"wall_clank", "platform_shake", "platform_fall", "conveyor_hum", "rock_fall", "rock_land",
	"pickup_small", "pickup_big", "pickup_rare", "pickup_heal", "memory_fragment",
]

## Stand-ins: logical name -> [8-bit sound or res:// path, volume dB, pitch].
const PLACEHOLDERS := {
	"turret_charge": ["power_up", -12.0, 1.7], "turret_fire": ["hurt", -10.0, 2.0],
	"laser_charge": ["power_up", -14.0, 2.2], "laser_zap": ["hurt", -12.0, 2.6],
	"bomb_drop": ["jump", -12.0, 0.6], "robot_explode": ["crate_break", -2.0, 0.55],
	"robot_stun": ["land", -6.0, 1.5], "robot_clank": ["res://assets/audio/sfx/impactMetal_heavy_002.ogg", -6.0, 1.3],
	"debris": ["crate_break", -12.0, 1.5], "barrel_explode": ["shockwave_thump", -2.0, 0.7],
	"barrel_fuse": ["checkpoint", -14.0, 2.0], "acid_hiss": ["land", -12.0, 2.4],
	"acid_splash": ["crate_break", -8.0, 1.8], "electric_warn": ["checkpoint", -14.0, 2.4],
	"crusher_warn": ["land", -10.0, 0.5], "crusher_slam": ["shockwave_thump", -3.0, 0.9],
	"spike_warn": ["checkpoint", -14.0, 1.6], "spike_pop": ["land", -6.0, 1.9],
	"steam_hiss": ["land", -14.0, 2.6], "flame_burst": ["power_up", -10.0, 0.5],
	"hopper_squat": ["land", -12.0, 1.2], "hopper_land": ["land", -8.0, 0.9],
	"crawler_drop": ["land", -8.0, 0.7], "camera_spot": ["checkpoint", -8.0, 1.8],
	"mech_charge": ["power_up", -8.0, 0.4], "mech_slam": ["shockwave_thump", -2.0, 0.6],
	"wall_break": ["crate_break", -4.0, 0.75], "wall_clank": ["res://assets/audio/sfx/impactMetal_heavy_002.ogg", -8.0, 1.0],
	"platform_shake": ["land", -14.0, 0.8], "platform_fall": ["jump", -10.0, 0.5],
	"rock_fall": ["jump", -14.0, 0.5], "rock_land": ["crate_break", -6.0, 0.7],
	"pickup_small": ["pickup", -6.0, 1.0], "pickup_big": ["pickup", -3.0, 0.8],
	"pickup_rare": ["power_up", -3.0, 1.2], "pickup_heal": ["pickup", -4.0, 1.3],
	"memory_fragment": ["power_up", -4.0, 1.5],
}
## Loops (the library's, or a stand-in): name -> [8-bit loop, dB, pitch].
const LOOP_PLACEHOLDERS := {
	"drone_hover": ["laser_hum_loop", -16.0, 1.5], "electric_arc": ["laser_hum_loop", -14.0, 2.2],
	"camera_alarm": ["laser_hum_loop", -12.0, 3.0], "conveyor_hum": ["laser_hum_loop", -20.0, 0.8],
}

static var _lib := {}
static var _lib_loaded := false
static var _cache := {}


static func _load_lib() -> void:
	if _lib_loaded:
		return
	_lib_loaded = true
	if not FileAccess.file_exists(LIB_MANIFEST):
		return
	var f := FileAccess.open(LIB_MANIFEST, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
	if parsed is Dictionary:
		var d: Dictionary = parsed.get("sounds", parsed)
		for k in d:
			var v: Variant = d[k]
			_lib[str(k)] = str(v.get("file", v.get("path", ""))) if v is Dictionary else str(v)


## The stream for a logical name from the real library, or null.
static func library_stream(name: String) -> AudioStream:
	_load_lib()
	var cands: Array[String] = []
	if _lib.has(name) and _lib[name] != "":
		var p: String = _lib[name]
		cands.append(p if p.begins_with("res://") else "res://assets/audio/" + p)
	for ext in ["ogg", "wav", "mp3"]:
		cands.append("%s%s.%s" % [LIB_DIR, name, ext])
	for c in cands:
		if _cache.has(c):
			return _cache[c]
		if ResourceLoader.exists(c):
			var s: AudioStream = load(c)
			_cache[c] = s
			return s
	return null


## True when a logical name would make a sound right now.
static func resolves(name: String) -> bool:
	return library_stream(name) != null or (use_placeholders and (PLACEHOLDERS.has(name) or LOOP_PLACEHOLDERS.has(name)))


static func play(ctx: Node, name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if record:
		log.append(name)
	if ctx == null or not ctx.is_inside_tree():
		return
	var lib := library_stream(name)
	if lib != null:
		_one_shot(ctx, lib, volume_db - 4.0, pitch)
		return
	if use_placeholders and PLACEHOLDERS.has(name):
		var ph: Array = PLACEHOLDERS[name]
		Sfx.play(ctx, ph[0], float(ph[1]) + volume_db, float(ph[2]) * pitch)


## A loop that belongs to `host` (see LoopSfx), or null when the name has none.
static func loop(host: Node2D, name: String, range_px := 420.0) -> LoopSfx:
	if record:
		log.append(name)
	var s := library_stream(name)
	var db := -12.0
	var pt := 1.0
	if s == null and use_placeholders and LOOP_PLACEHOLDERS.has(name):
		var ph: Array = LOOP_PLACEHOLDERS[name]
		s = load("res://assets/audio/sfx8bit/%s.ogg" % ph[0])
		db = float(ph[1])
		pt = float(ph[2])
	if s == null:
		return null
	return LoopSfx.attach(host, s, db, pt, range_px)


static func _one_shot(ctx: Node, stream: AudioStream, db: float, pitch: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	ctx.get_tree().root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
