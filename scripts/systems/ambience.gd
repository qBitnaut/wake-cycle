class_name Ambience
extends Node
## Room sound bed: the scene's ambience loop (rain, a far machine hum ... one file per
## room, see assets/audio/amb), an optional second loop, water drops (one per DripFX
## landing, positional) and the cat's footsteps on the room's surface. Kept quiet: the
## world is asleep. Add it to a level and call `setup(cat)`; it finds the DripFX nodes
## in the level by itself. The loops are streams on the Ambience bus, started once the
## AudioDirector has unlocked sound (the web's first input).

## Footstep surfaces: a room sets `surface` (an Sfx name prefix: step_metal, step_concrete,
## step_wet, step_wood). A crouched cat crawls.
const SURFACES := ["step_metal", "step_concrete", "step_wet", "step_wood"]

## The two loops of the bed (a day room swaps them, e.g. birdsong and drips).
## The room's bed: a name in res://assets/audio/amb (e.g. "amb_yard"), or `rain_stream` itself.
@export var bed := ""
@export var rain_stream: AudioStream
@export var hum_stream: AudioStream
@export var rain_db := -6.0
@export var hum_db := -12.0
@export var step_db := 0.0
@export_enum("step_metal", "step_concrete", "step_wet", "step_wood") var surface := "step_concrete"

var cat: Cat
var steps_played := 0
## 0..1: how loud the rain loop should be (a room whose rain thins and stops, e.g.
## SkyProgress, sets it). The loop eases to it and is paused once silent.
var rain_level := 1.0

var _rain_gain := 1.0

var _rain: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _step_t := 0.0


func _ready() -> void:
	var c := get_parent().get_node_or_null("Cat") as Cat
	if c:
		setup(c)


func setup(player: Cat) -> void:
	cat = player
	if rain_stream == null and bed != "":
		rain_stream = load("res://assets/audio/amb/%s.ogg" % bed)
	if rain_stream:
		_rain = _loop(rain_stream, rain_db)
	if hum_stream:
		_hum = _loop(hum_stream, hum_db)
	for d in get_parent().find_children("*", "DripFX", true, false):
		(d as DripFX).landed.connect(_plink)


func _loop(stream: AudioStream, db: float) -> AudioStreamPlayer:
	return AudioDirector.loop_player(self, stream, db)


func _plink(pos: Vector2) -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = Sfx.stream("drop")
	p.bus = &"SFX"
	p.volume_db = Sfx.level_db("drop") - 6.0
	p.pitch_scale = randf_range(0.9, 1.15)
	p.max_distance = 420.0
	p.global_position = pos
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _physics_process(delta: float) -> void:
	_ease_rain(delta)
	if cat == null or cat.dead:
		return
	_step_t -= delta
	var speed := absf(cat.velocity.x)
	if cat.is_on_floor() and speed > 40.0 and _step_t <= 0.0:
		_step_t = 0.27 if speed > 117.0 else 0.4
		if cat.crouched:
			_step_t = 0.5
		Sfx.play(self, "crawl" if cat.crouched else surface, step_db)
		steps_played += 1


func _ease_rain(delta: float) -> void:
	if _rain == null or is_equal_approx(_rain_gain, rain_level):
		return
	_rain_gain = move_toward(_rain_gain, rain_level, delta * 0.5)
	# Write stream_paused only when it changes: on the web (samples) every write restarts
	# the loop's sample, and an easing rain did that every frame (about ten stacked copies).
	if _rain_gain < 0.003:
		_rain.volume_db = -80.0
		if not _rain.stream_paused:
			_rain.stream_paused = true
	else:
		if _rain.stream_paused:
			_rain.stream_paused = false
		_rain.volume_db = rain_db + linear_to_db(_rain_gain)


## Current rain loop state: an audit hook.
func rain_playing() -> bool:
	return _rain != null and _rain.playing and not _rain.stream_paused
