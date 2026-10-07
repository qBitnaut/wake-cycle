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
## A sound made by a thing in the world (a hazard, a bot, a pad) is heard by distance from the
## cat: full inside NEAR px, a smooth fade to nothing at FAR px (a screen is 640 px wide).
## Sounds of the cat itself, and of nodes with no position, are not attenuated.
const NEAR := 160.0
const FAR := 560.0
const FLOOR_GAIN := 0.02   ## below this linear gain the sound is not played at all
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


## Linear gain 0..1 for a sound made at `ctx`, by its distance from the cat.
static func proximity(ctx: Node) -> float:
	var src := ctx as Node2D
	if src == null or not src.is_inside_tree() or src.is_in_group("player"):
		return 1.0
	var cat := src.get_tree().get_first_node_in_group("player") as Node2D
	if cat == null:
		return 1.0
	var t := clampf(1.0 - (src.global_position.distance_to(cat.global_position) - NEAR) / (FAR - NEAR), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The manifest level of `sound`, dB.
static func level_db(sound: String) -> float:
	_load()
	return float(_manifest.get(sound, {}).get("db", -8.0))


## Play `sound` once. `volume_db` and `pitch` adjust the manifest's level and the pitch;
## `variant` picks one file of the name (default: at random).
static func play(ctx: Node, sound: String, volume_db := 0.0, pitch := 1.0, variant := -1) -> AudioStreamPlayer:
	var s := stream(sound, variant)
	if s == null or ctx == null or not ctx.is_inside_tree():
		return null
	if LoopSfx._loops(s):
		# A looping stream never emits `finished`: played here it would live on the root
		# for ever (the drone hum did exactly that). One-shots are always played once;
		# a real loop belongs to LoopSfx.
		s = s.duplicate()
		s.set("loop", false)
	var near := proximity(ctx)
	if near < FLOOR_GAIN:
		return null
	volume_db += linear_to_db(near)
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
