class_name LoopSfx
extends Node
## A looping sound that belongs to something in a level (a drone, a scanner).
##
## Always a child of its source, so it is freed with it, and a level change frees
## the lot: nothing is parented to the root (the old Sfx.play of a looping stream
## was, and, being a loop, never finished and never stopped).
##
## The volume is set by hand from the distance to the cat, not by the engine's
## positional audio: on the web the export plays audio as samples by default, and
## AudioStreamPlayer2D attenuation can be missing there. So this is a plain
## AudioStreamPlayer (forced to stream playback, which keeps volume and stop
## honest on every platform) whose volume_db follows a smooth falloff between
## `min_distance` (full) and `max_distance` (silent). Beyond that range, or when
## `active` is false, it fades out and then really stops; it starts again when the
## cat comes back into range. `retire()` fades it out and frees it.

const GROUP := "loop_sfx"
## Level-independent loops that are meant to outlive a scene (named in the root). The
## AudioDirector's own music and bed players are persistent by parentage (see playing_loops).
const PERSISTENT := []
const FADE_RATE := 3.0   ## gain per second, up or down
const SILENT := 0.004    ## below this linear gain the player is stopped

@export var stream: AudioStream
@export var base_db := -12.0
@export var pitch := 1.0
@export var min_distance := 90.0
@export var max_distance := 520.0
## Whether the source is making the sound at all (a drone that is idle or gone sets it false).
@export var active := true

## The emitter whose position is used (default: the parent, when it is a Node2D).
var source: Node2D
var gain := 0.0
var _player: AudioStreamPlayer
var _retiring := false


## Add a loop to `host` (a Node2D: its position is the source).
static func attach(host: Node2D, snd: AudioStream, db := -12.0, pitch_scale := 1.0, range_px := 520.0) -> LoopSfx:
	var l := LoopSfx.new()
	l.stream = snd
	l.base_db = db
	l.pitch = pitch_scale
	l.max_distance = range_px
	l.min_distance = minf(90.0, range_px * 0.3)
	l.name = "LoopSfx"
	host.add_child(l)
	return l


func _ready() -> void:
	add_to_group(GROUP)
	if source == null:
		source = get_parent() as Node2D
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	var s: AudioStream = stream.duplicate()
	s.set("loop", true)
	_player.stream = s
	_player.pitch_scale = pitch
	_player.volume_db = -80.0
	# Stream playback, not the web's default samples: a sample cannot be re-leveled
	# or stopped as reliably, and this is the one sound that must do both.
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	add_child(_player)
	_update(0.0)


func _physics_process(delta: float) -> void:
	_update(delta)


## The loudness 0..1 the cat should hear from here: 1 inside min_distance, a smooth
## falloff to 0 at max_distance.
func target_gain() -> float:
	if not active or _retiring:
		return 0.0
	var cat := get_tree().get_first_node_in_group("player") as Node2D
	if cat == null or source == null or not is_instance_valid(source):
		return 0.0
	var d := source.global_position.distance_to(cat.global_position)
	var t := clampf(1.0 - (d - min_distance) / maxf(max_distance - min_distance, 1.0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _update(delta: float) -> void:
	if _player == null:
		return
	var target := target_gain()
	gain = move_toward(gain, target, FADE_RATE * delta) if delta > 0.0 else target
	if gain <= SILENT and target <= SILENT:
		gain = 0.0
		if _player.playing:
			_player.stop()
		_player.volume_db = -80.0
		if _retiring:
			queue_free()
		return
	_player.volume_db = base_db + linear_to_db(gain)
	if not _player.playing:
		_player.play()


## True while the loop is audible (playing and above the floor).
func audible() -> bool:
	return _player != null and _player.playing and gain > SILENT


## Fade out and free.
func retire() -> void:
	_retiring = true
	active = false


func _exit_tree() -> void:
	if _player and _player.playing:
		_player.stop()


# ---- audit hooks -------------------------------------------------------------------------

static func _loops(stream: AudioStream) -> bool:
	if stream == null:
		return false
	var v = stream.get("loop")
	if v != null:
		return bool(v)
	var m = stream.get("loop_mode")
	return m != null and int(m) != 0


## Every looping AudioStreamPlayer / AudioStreamPlayer2D in the tree that is playing:
## [{path, owner_scene (the current scene's name or "" for a node outside it), persistent}].
static func playing_loops(tree: SceneTree) -> Array:
	var out := []
	var scene := tree.current_scene
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer2D"]:
		for n in tree.root.find_children("*", kind, true, false):
			if n.get("playing") != true or n.get("stream_paused") == true:
				continue
			if not _loops(n.get("stream")):
				continue
			var inside: bool = scene != null and scene.is_ancestor_of(n)
			var director := tree.root.get_node_or_null("AudioDirector")
			var kept := PERSISTENT.has(n.name) or (director != null and director.is_ancestor_of(n))
			out.append({"path": str(n.get_path()), "in_scene": inside, "persistent": kept})
	return out


## Players that are playing a loop outside the current scene and not meant to persist:
## the leak. Empty when the sound is clean.
static func orphans(tree: SceneTree) -> Array:
	return playing_loops(tree).filter(func(l): return not l["in_scene"] and not l["persistent"])


## Published to window.__wake by the room scripts: {playing: n, orphans: n, drone: n}.
## `drone` counts the positional loops (LoopSfx) that are audible right now.
static func census(tree: SceneTree) -> Dictionary:
	var drones := 0
	for l in tree.get_nodes_in_group(GROUP):
		if (l as LoopSfx).audible():
			drones += 1
	return {"playing": playing_loops(tree).size(), "orphans": orphans(tree).size(), "positional": drones}


static var _census_frame := -1000
static var _census_cache := {}


## census(), refreshed every 10 physics frames: cheap enough to publish every frame.
static func census_cached(tree: SceneTree) -> Dictionary:
	var f := Engine.get_physics_frames()
	if f - _census_frame >= 10:
		_census_frame = f
		_census_cache = census(tree)
	return _census_cache
