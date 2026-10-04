class_name DripFX
extends Node2D
## An indoor drip from a roof hole or pipe: a drop swells, falls, splashes,
## and rings a puddle if one is set. The origin is where the drop hangs.

signal landed(global_pos: Vector2)

@export var fall_height := 120.0
@export var interval_min := 1.2
@export var interval_max := 2.6
@export var puddle: Puddle
@export var drop_color := Color(0.75, 0.86, 1.0)
## Reference px/s^2 (scaled by FXScale).
@export var gravity := 420.0

enum _State { WAIT, SWELL, FALL }

var _state := _State.WAIT
var _t := 0.0
var _wait := 0.5
var _y := 0.0
var _vy := 0.0
var _splash: CPUParticles2D
var _f := 1.0
var _px := 1.0


func _ready() -> void:
	_f = FXScale.factor(self)
	_px = float(FXScale.whole(self))
	var self_mat := CanvasItemMaterial.new()
	self_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = self_mat
	_splash = CPUParticles2D.new()
	_splash.emitting = false
	_splash.one_shot = true
	_splash.explosiveness = 1.0
	_splash.amount = 6
	_splash.lifetime = 0.35
	_splash.direction = Vector2(0, -1)
	_splash.spread = 60.0
	_splash.gravity = Vector2(0, 300) * _f
	_splash.initial_velocity_min = 18.0 * _f
	_splash.initial_velocity_max = 38.0 * _f
	_splash.scale_amount_min = _px
	_splash.scale_amount_max = _px
	_splash.color = drop_color
	_splash.position = Vector2(0, fall_height)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	_splash.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_splash.material = mat
	add_child(_splash)
	_wait = randf_range(0.2, interval_max)


## Drop right now (skips the wait).
func drip() -> void:
	_state = _State.SWELL
	_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	match _state:
		_State.WAIT:
			if _t >= _wait:
				drip()
		_State.SWELL:
			if _t >= 0.6:
				_state = _State.FALL
				_y = 1.0
				_vy = 0.0
		_State.FALL:
			_vy += gravity * _f * delta
			_y += _vy * delta
			if _y >= fall_height:
				_land()
	queue_redraw()


func _land() -> void:
	_state = _State.WAIT
	_t = 0.0
	_wait = randf_range(interval_min, interval_max)
	_splash.restart()
	var p := to_global(Vector2(0, fall_height))
	if puddle:
		puddle.ripple(p.x)
	landed.emit(p)


func _draw() -> void:
	# Pixel drop: 1 px hanging bead that swells to 2, then a 1x2 falling streak.
	match _state:
		_State.SWELL:
			var h := 1.0 if _t < 0.35 else 2.0
			draw_rect(Rect2(0, 0, _px, h * _px), drop_color)
		_State.FALL:
			var y := floorf(_y)
			draw_rect(Rect2(0, y - 2 * _px, _px, 3 * _px), Color(drop_color, 0.9))
