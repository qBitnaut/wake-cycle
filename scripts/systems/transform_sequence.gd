class_name TransformSequence
extends Node
## The goo transformation (Room 1): the cat is claimed by the nanotech pool and
## comes out augmented. THIS IS A STUB: a timed placeholder with a tint pulse
## that walks through the phases and emits `finished`. The real effect plugs
## into the same API (listen to `phase_started`, drive the cat via
## Cat.fx_tint / Cat.set_forced_anim, free yourself and emit `finished` last).
##
##   var seq := TransformSequence.play(cat)
##   seq.finished.connect(_on_transform_finished)
##
## Phases, in order: the goo rises up the cat, the veins reach the eyes, the
## cat is absorbed (the colour takes over), the cat looks normal again, then
## the robotic augments appear.

signal phase_started(phase: StringName)
signal finished

const GOO_RISES := &"goo_rises"
const VEINS_REACH_EYES := &"veins_reach_eyes"
const ABSORB := &"absorb"
const LOOKS_NORMAL := &"looks_normal"
const AUGMENTS_APPEAR := &"augments_appear"

## [phase, seconds]. The stub totals 6 s.
const PHASES := [
	[GOO_RISES, 2.0],
	[VEINS_REACH_EYES, 1.5],
	[ABSORB, 1.2],
	[LOOKS_NORMAL, 0.8],
	[AUGMENTS_APPEAR, 0.5],
]

var cat: Cat
var phase: StringName = &""
var running := false

var _tween: Tween


## Start the sequence on `cat`. The node lives next to the cat and frees
## itself after `finished`.
static func play(target: Cat) -> TransformSequence:
	var seq := TransformSequence.new()
	seq.name = "TransformSequence"
	seq.cat = target
	target.get_parent().add_child(seq)
	seq.start()
	return seq


func start() -> void:
	running = true
	_tween = create_tween()
	for p in PHASES:
		_tween.tween_callback(_enter.bind(p[0]))
		_tween.tween_method(_pulse.bind(p[0]), 0.0, 1.0, p[1])
	_tween.tween_callback(_finish)


func _enter(p: StringName) -> void:
	phase = p
	phase_started.emit(p)


## Placeholder look: the cat's tint breathes towards the nanotech blue, harder
## each phase, and settles back to normal for the last two.
func _pulse(t: float, p: StringName) -> void:
	if not is_instance_valid(cat):
		return
	var strength := 0.0
	match p:
		GOO_RISES:
			strength = 0.25 + 0.2 * t
		VEINS_REACH_EYES:
			strength = 0.5 + 0.2 * t
		ABSORB:
			strength = 0.8 - 0.3 * t
		LOOKS_NORMAL:
			strength = 0.0
		AUGMENTS_APPEAR:
			strength = 0.3 * sin(t * PI)
	var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	cat.fx_tint = Color.WHITE.lerp(FXPalette.NANO_BLUE.lerp(Color.WHITE, 0.4), strength * (0.6 + 0.4 * wave))


func _finish() -> void:
	running = false
	if is_instance_valid(cat):
		cat.fx_tint = Color.WHITE
	finished.emit()
	queue_free()
