@tool
class_name WaterDrip
extends Node3D
## A drop forms at this node (the ceiling), falls, and lands fall_height
## below with a splash and an expanding ripple ring, at random intervals.
## Assign a Puddle and the drop lands on it and ripples its surface.

signal impacted(position: Vector3)

@export var puddle: Puddle:
	set(v):
		puddle = v
		_place_impact()
## Used when no puddle is set: distance from this node down to the surface.
@export var fall_height := 6.0:
	set(v):
		fall_height = maxf(v, 0.1)
		_place_impact()
@export var interval_min := 1.4
@export var interval_max := 4.2
@export var form_time := 0.7
@export var gravity := 9.8
@export var ripple_strength := 1.0

@onready var _drop: MeshInstance3D = $Drop
@onready var _impact: Node3D = $Impact
@onready var _splash: CPUParticles3D = $Impact/Splash
@onready var _rings: CPUParticles3D = $Impact/Rings

enum State { WAIT, FORM, FALL }

var _state := State.WAIT
var _timer := 0.0
var _speed := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_place_impact()
	_drop.visible = false
	_timer = _rng.randf_range(0.2, interval_max)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	match _state:
		State.WAIT:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.FORM
				_timer = 0.0
				_drop.position = Vector3.ZERO
				_drop.visible = true
		State.FORM:
			_timer += delta
			var k := clampf(_timer / form_time, 0.0, 1.0)
			# Swells, then necks down just before letting go.
			var s := ease(k, 0.6)
			_drop.scale = Vector3(s, s * (1.0 + k * 0.4), s)
			_drop.position.y = -0.02 * k
			if k >= 1.0:
				_state = State.FALL
				_speed = 0.0
		State.FALL:
			_speed += gravity * delta
			_drop.position.y -= _speed * delta
			var stretch := 1.0 + minf(_speed * 0.12, 1.4)
			_drop.scale = Vector3(1.0 / sqrt(stretch), stretch, 1.0 / sqrt(stretch))
			if _drop.position.y <= _impact.position.y:
				_land()


func _land() -> void:
	_drop.visible = false
	_splash.restart()
	_rings.restart()
	var at := _impact.global_position
	if puddle:
		puddle.add_ripple(at, ripple_strength)
	impacted.emit(at)
	_state = State.WAIT
	_timer = _rng.randf_range(interval_min, interval_max)


func _place_impact() -> void:
	if not is_node_ready():
		return
	var h := fall_height
	if puddle and puddle.is_inside_tree() and is_inside_tree():
		h = global_position.y - puddle.global_position.y
	_impact.position = Vector3(0.0, -h + 0.01, 0.0)
