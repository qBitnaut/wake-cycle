class_name Ambience
extends Node
## Room sound bed: a rain loop, a far machine hum, drip plinks (one per
## DripFX landing, positional) and the cat's footsteps. Kept quiet: the world
## is asleep. Add it to a level and call `setup(cat)`; it finds the DripFX
## nodes in the level by itself.

const RAIN := preload("res://assets/audio/ambient/rain.ogg")
const HUM := preload("res://assets/audio/ambient/pump_01.ogg")
const STEPS := [
	preload("res://assets/audio/sfx/footstep_concrete_000.ogg"),
	preload("res://assets/audio/sfx/footstep_concrete_001.ogg"),
	preload("res://assets/audio/sfx/footstep_concrete_002.ogg"),
	preload("res://assets/audio/sfx/footstep_concrete_003.ogg"),
	preload("res://assets/audio/sfx/footstep_concrete_004.ogg"),
]
const PLINK := [
	preload("res://assets/audio/sfx/impactMetal_light_000.ogg"),
	preload("res://assets/audio/sfx/impactMetal_light_001.ogg"),
	preload("res://assets/audio/sfx/impactMetal_light_002.ogg"),
]

## The two loops of the bed (a day room swaps them, e.g. birdsong and drips).
@export var rain_stream: AudioStream = RAIN
@export var hum_stream: AudioStream = HUM
@export var rain_db := -17.0
@export var hum_db := -24.0
@export var step_db := -20.0

var cat: Cat
var steps_played := 0
## 0..1: how loud the rain loop should be (a room whose rain thins and stops, e.g.
## SkyProgress, sets it). The loop eases to it and is paused once silent.
var rain_level := 1.0

var _rain_gain := 1.0

var _rain: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _step: AudioStreamPlayer
var _step_t := 0.0


func _ready() -> void:
	var c := get_parent().get_node_or_null("Cat") as Cat
	if c:
		setup(c)


func setup(player: Cat) -> void:
	cat = player
	_rain = _loop(rain_stream, rain_db)
	_hum = _loop(hum_stream, hum_db)
	_step = AudioStreamPlayer.new()
	_step.volume_db = step_db
	add_child(_step)
	for d in get_parent().find_children("*", "DripFX", true, false):
		(d as DripFX).landed.connect(_plink)


func _loop(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var s: AudioStream = stream.duplicate()
	s.set("loop", true)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	p.autoplay = true
	add_child(p)
	return p


func _plink(pos: Vector2) -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = PLINK[randi() % PLINK.size()]
	p.volume_db = -22.0
	p.pitch_scale = randf_range(2.2, 3.0)
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
		_step.stream = STEPS[randi() % STEPS.size()]
		_step.pitch_scale = randf_range(1.1, 1.4)
		_step.volume_db = step_db - (6.0 if cat.crouched else 0.0)
		_step.play()
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
