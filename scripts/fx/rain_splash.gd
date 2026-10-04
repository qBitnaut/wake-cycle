class_name RainSplash
extends CPUParticles2D
## Rain splashes along a surface: tiny pixel droplets kicked up and pulled
## back down. Place the node on the surface line; it spans `width` px centred
## on its origin. RainFX adds one on its floor; add more for ledges and sills.

@export var width := 120.0:
	set(v):
		width = v
		_apply()
## Splashes per second per 100 px of surface.
@export var rate := 30.0:
	set(v):
		rate = v
		_apply()
@export var splash_color := Color(0.75, 0.85, 1.0, 0.9):
	set(v):
		splash_color = v
		_apply()


func _ready() -> void:
	lifetime = 0.28
	emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	direction = Vector2(0, -1)
	spread = 55.0
	var f := FXScale.factor(self)
	var px := float(FXScale.whole(self))
	gravity = Vector2(0, 260) * f
	initial_velocity_min = 14.0 * f
	initial_velocity_max = 30.0 * f
	scale_amount_min = px
	scale_amount_max = px
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	color_ramp = ramp
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	emission_rect_extents = Vector2(width * 0.5, 0.5)
	amount = maxi(int(rate * width / 100.0 * lifetime) + 1, 1)
	color = splash_color
