class_name PuddleZone
extends Area2D
## A shallow floor puddle the cat can walk through: a reflective Puddle on the
## floor line plus a trigger that splashes and rings it when the cat steps in
## or wades through. Harmless. Origin = the middle of the water line, on the
## floor surface. Hand `puddle` to DripFX so roof leaks ring it too.

@export var width := 96.0

var puddle: Puddle

var _splash: CPUParticles2D
var _step_t := 0.0
var _px := 1.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(width, 8.0)
	cs.shape = r
	cs.position = Vector2(0, -4)
	add_child(cs)
	puddle = Puddle.new()
	puddle.name = "Puddle"
	puddle.position = Vector2(-width / 2.0, 0)
	puddle.size = Vector2(width, 11.0)
	puddle.water_tint = Color(0.24, 0.36, 0.55)
	puddle.edge_fade = 5.0
	puddle.z_index = 6  # above the cat (5): it reflects only what is drawn before it
	add_child(puddle)
	var f := FXScale.factor(self)
	_px = float(FXScale.whole(self))
	_splash = CPUParticles2D.new()
	_splash.emitting = false
	_splash.one_shot = true
	_splash.explosiveness = 1.0
	_splash.amount = 8
	_splash.lifetime = 0.4
	_splash.direction = Vector2(0, -1)
	_splash.spread = 55.0
	_splash.gravity = Vector2(0, 300) * f
	_splash.initial_velocity_min = 22.0 * f
	_splash.initial_velocity_max = 50.0 * f
	_splash.scale_amount_min = _px
	_splash.scale_amount_max = _px
	_splash.color = Color(0.75, 0.86, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	_splash.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_splash.material = mat
	_splash.z_index = 6
	add_child(_splash)
	body_entered.connect(_on_body)


func _on_body(body: Node) -> void:
	if body is Cat:
		var fall := maxf(body.velocity.y, 0.0) / 400.0
		_kick(body.global_position.x, clampf(0.5 + absf(body.velocity.x) / 250.0 + fall, 0.5, 1.4), true)


func _physics_process(delta: float) -> void:
	_step_t -= delta
	if _step_t > 0.0:
		return
	for b in get_overlapping_bodies():
		if b is Cat and b.is_on_floor() and absf(b.velocity.x) > 30.0:
			_kick(b.global_position.x, 0.5, false)
			_step_t = 0.26 if absf(b.velocity.x) > 100.0 else 0.4
			return


func _kick(global_x: float, strength: float, loud: bool) -> void:
	puddle.ripple(global_x, minf(strength, 1.0))
	_splash.global_position = Vector2(global_x, global_position.y)
	_splash.amount = 8 if loud else 4
	_splash.restart()
	_splash.emitting = true
	Sfx.play(self, "splash", -3.0 if loud else -9.0, 1.2)
