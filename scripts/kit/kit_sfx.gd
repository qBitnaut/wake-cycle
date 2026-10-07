class_name KitSfx
extends RefCounted
## Sound hooks for the actor kit, by LOGICAL NAME: KitSfx.play(self, "turret_fire").
##
## Resolution order for a name:
##   1. the audio library, assets/audio/sfx/sfx.json (the Sfx autoload's manifest), when it
##      has the name itself (turret_fire, laser_zap, drone_hover, pickup_big...);
##   2. an older manifest (assets/audio/sfx_manifest.json, {"name": "path"} or
##      {"sounds": {...}}) and assets/audio/sfx_lib/<name>.ogg|.wav|.mp3, when present;
##   3. a stand-in: STAND_INS maps the name to another library sound with a level and pitch
##      shift, so every kit event makes noise until a dedicated sound is generated.
##      NO_DEDICATED_SOUND lists the names that are still stand-ins;
##   4. nothing: an unknown name is silently skipped.
## A dedicated sound lands by adding the name to sfx.json; no actor script changes. All
## names the kit uses are listed in LOGICAL_NAMES (and docs/KIT.md).

const LIB_DIR := "res://assets/audio/sfx_lib/"
const LIB_MANIFEST := "res://assets/audio/sfx_manifest.json"
## Set false to hear only dedicated library sounds (no stand-ins).
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

## Stand-ins: kit name -> [library sound, dB offset, pitch]. Loops use the same table.
const STAND_INS := {
	"laser_charge": ["power_up", -6.0, 2.2],
	"bomb_drop": ["drop", 0.0, 0.6], "robot_explode": ["robot_explosion", 0.0, 1.0],
	"robot_stun": ["land", 0.0, 1.5], "robot_clank": ["bot_stomp", 0.0, 1.3],
	"debris": ["robot_debris", 0.0, 1.0], "barrel_explode": ["shockwave_burst", 3.0, 0.7],
	"barrel_fuse": ["checkpoint", -6.0, 2.0], "acid_hiss": ["goo_bubble", 0.0, 1.6],
	"acid_splash": ["splash", 0.0, 1.0], "electric_warn": ["checkpoint", -6.0, 2.4],
	"crusher_warn": ["land", 0.0, 0.5], "crusher_slam": ["impact_pound", 0.0, 1.0],
	"spike_warn": ["checkpoint", -6.0, 1.6], "spike_pop": ["land", 0.0, 1.9],
	"steam_hiss": ["scanner_sweep", -4.0, 2.2], "flame_burst": ["power_up", -2.0, 0.5],
	"hopper_squat": ["land", -4.0, 1.2], "hopper_land": ["land", 0.0, 0.9],
	"crawler_drop": ["land", 0.0, 0.7], "camera_spot": ["checkpoint", 0.0, 1.8],
	"mech_charge": ["power_up", 0.0, 0.4], "mech_slam": ["impact_pound", 2.0, 0.8],
	"wall_break": ["crate_break", 0.0, 0.75], "wall_clank": ["bot_stomp", -2.0, 1.0],
	"platform_shake": ["land", -6.0, 0.8], "platform_fall": ["drop", 0.0, 0.5],
	"rock_fall": ["drop", -4.0, 0.5], "rock_land": ["crate_break", 0.0, 0.7],
	"pickup_heal": ["pickup_small", 0.0, 1.3], "memory_fragment": ["pickup_rare", 0.0, 1.2],
	# Loops.
	"electric_arc": ["laser_hum", 0.0, 2.2], "camera_alarm": ["laser_hum", 0.0, 3.0],
	"conveyor_hum": ["laser_hum", -6.0, 0.8],
}
## Kit names the library (sfx.json) has no dedicated sound for yet: stand-ins play. Empty now: every
## name has a dedicated sound; STAND_INS stays as the fallback if a library file goes missing.
const NO_DEDICATED_SOUND := []

## Held under the player's own sounds: a hazard's cycle (warn, slam, hiss, arc) is the
## factory's presence, not the cat's feedback. Pickups and memory fragments are exempt.
const HAZARD_TRIM_DB := -3.0
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


## The stream for a logical name from the real library, or null. Looks in sfx.json first.
static func library_stream(name: String) -> AudioStream:
	if Sfx.has(name):
		return Sfx.stream(name)
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


## [stream, dB, pitch] for a name (the library's own, else a stand-in), or [] for none.
static func _resolve(name: String) -> Array:
	var lib := library_stream(name)
	if lib != null:
		return [lib, Sfx.level_db(name) if Sfx.has(name) else -8.0, 1.0]
	if use_placeholders and STAND_INS.has(name):
		var ph: Array = STAND_INS[name]
		var s := Sfx.stream(ph[0])
		if s != null:
			return [s, Sfx.level_db(ph[0]) + float(ph[1]), float(ph[2])]
	return []


## True when a logical name would make a sound right now.
static func resolves(name: String) -> bool:
	return not _resolve(name).is_empty()


static func play(ctx: Node, name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if record:
		log.append(name)
	if ctx == null or not ctx.is_inside_tree():
		return
	var r := _resolve(name)
	if r.is_empty():
		return
	var near := Sfx.proximity(ctx)
	if near < Sfx.FLOOR_GAIN:
		return
	volume_db += linear_to_db(near)
	if not (name.begins_with("pickup") or name == "memory_fragment"):
		volume_db += HAZARD_TRIM_DB
	var st: AudioStream = r[0]
	if LoopSfx._loops(st):
		st = st.duplicate()
		st.set("loop", false)
	_one_shot(ctx, st, float(r[1]) + volume_db, float(r[2]) * pitch)


## A loop that belongs to `host` (see LoopSfx), or null when the name has none.
static func loop(host: Node2D, name: String, range_px := 420.0) -> LoopSfx:
	if record:
		log.append(name)
	var r := _resolve(name)
	if r.is_empty():
		return null
	return LoopSfx.attach(host, r[0], float(r[1]), float(r[2]), range_px)


static func _one_shot(ctx: Node, stream: AudioStream, db: float, pitch: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	ctx.get_tree().root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
