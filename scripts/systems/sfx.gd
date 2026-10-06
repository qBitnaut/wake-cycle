class_name Sfx
extends RefCounted
## One-shot sound effects by logical name: Sfx.play(self, "jump").
##
## The names live in res://assets/audio/sfx/sfx.json (tools/audio/make_manifest.py):
## each maps to one or more files (a variant is picked at random), a level in dB and a
## little pitch jitter. `volume_db` and `pitch` passed to play() are applied on top.
## Everything goes out on the "SFX" bus. A name that is not in the manifest is a warning
## and silence, never a crash.

const DIR := "res://assets/audio/sfx/"
const MANIFEST := DIR + "sfx.json"
static var _manifest := {}
static var _loaded := false
static var _cache := {}
## Every name played, in order (the last few hundred): for audits.
static var played: Array = []


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_warning("Sfx: %s missing" % MANIFEST)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_manifest = parsed
	else:
		push_warning("Sfx: %s is not a JSON object" % MANIFEST)


static func has(sound: String) -> bool:
	_load()
	return _manifest.has(sound)


## The names in the manifest.
static func names() -> Array:
	_load()
	return _manifest.keys()


## A stream of `sound` (a random variant, or variant `index`). Null if unknown.
static func stream(sound: String, index := -1) -> AudioStream:
	_load()
	if not _manifest.has(sound):
		push_warning("Sfx: no sound named '%s'" % sound)
		return null
	var files: Array = _manifest[sound]["files"]
	var path: String = DIR + String(files[index if index >= 0 else randi() % files.size()])
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## The manifest level of `sound`, dB.
static func level_db(sound: String) -> float:
	_load()
	return float(_manifest.get(sound, {}).get("db", -8.0))


## Play `sound` once. `volume_db` and `pitch` adjust the manifest's level and the pitch.
static func play(ctx: Node, sound: String, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var s := stream(sound)
	if s == null or ctx == null or not ctx.is_inside_tree():
		return null
	if LoopSfx._loops(s):
		# A looping stream never emits `finished`: played here it would live on the root
		# for ever (the drone hum did exactly that). One-shots are always played once;
		# a real loop belongs to LoopSfx.
		s = s.duplicate()
		s.set("loop", false)
	var jitter := float(_manifest[sound].get("jitter", 0.0))
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	p.volume_db = level_db(sound) + volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-jitter, jitter))
	ctx.get_tree().root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	played.append(sound)
	if played.size() > 400:
		played = played.slice(200)
	return p
