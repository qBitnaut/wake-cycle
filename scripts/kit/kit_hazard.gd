class_name KitHazard
extends Hazard
## A timed hazard with a built-in telegraph: IDLE (safe) -> WARN (visible and
## audible, still safe) -> LIVE (hurts) -> IDLE. The warning is never shorter than
## MIN_WARN (0.4 s) however `warn_time` is set. A hit hurts one pip and knocks back
## (it never kills). Subclasses draw themselves and react in `_on_phase`.
##
## `start_offset` staggers a row of hazards. `is_warning()` / `is_dangerous()` are
## the audit hooks; `last_warn` is the measured length of the last warning.

enum Phase { IDLE, WARN, LIVE }

const MIN_WARN := 0.4

@export var idle_time := 1.6
@export var warn_time := 0.8
@export var live_time := 0.9
@export var start_offset := 0.0

var phase := Phase.IDLE
var last_warn := 0.0
var cycles := 0
var phase_time := 0.0
var clock := 0.0


func warn_seconds() -> float:
	return maxf(warn_time, MIN_WARN)


func is_warning() -> bool:
	return phase == Phase.WARN


func is_dangerous() -> bool:
	return phase == Phase.LIVE


func _ready() -> void:
	super()
	kill = false
	active = false
	_build()
	var skip := start_offset
	while skip > 0.0:
		var left := _phase_len() - phase_time
		if skip < left:
			phase_time += skip
			break
		skip -= left
		_next_phase(true)
	_on_phase(phase, true)


## Subclass: create shapes and children.
func _build() -> void:
	pass


## Subclass: react to entering a phase (`silent` while fast-forwarding at start).
func _on_phase(_p: Phase, _silent: bool) -> void:
	pass


func _phase_len() -> float:
	match phase:
		Phase.IDLE:
			return idle_time
		Phase.WARN:
			return warn_seconds()
	return live_time


func _next_phase(silent := false) -> void:
	if phase == Phase.WARN:
		last_warn = phase_time
	phase = (phase + 1) % 3 as Phase
	phase_time = 0.0
	if phase == Phase.IDLE:
		cycles += 1
	active = phase == Phase.LIVE
	_on_phase(phase, silent)


func _physics_process(delta: float) -> void:
	clock += delta
	phase_time += delta
	if phase_time >= _phase_len():
		_next_phase()
	_step(delta)
	super(delta)
	queue_redraw()


## Subclass per-frame hook.
func _step(_delta: float) -> void:
	pass
