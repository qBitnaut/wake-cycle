class_name ShieldPanel
extends StaticBody2D
## An energy shield across a way through: solid until the cat's double-jump
## shockwave hits it. A ground pound or a stomp only makes it flicker. Not a
## cracked floor: it answers to the shockwave alone. `height_tiles` tall, one
## tile wide; origin = the middle of the base.

signal broken

@export var height_tiles := 3

var shock_offset := Vector2.ZERO
var shock_half := Vector2(16, 48)
var is_broken := false

var _t := 0.0
var _flinch := 0.0
var _id := ""
var _shape := RectangleShape2D.new()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("shock_receiver")
	_id = str(get_path())
	if GameState.is_collected(_id):
		queue_free()
		return
	var h := height_tiles * 32.0
	_shape.size = Vector2(18, h)
	var cs := CollisionShape2D.new()
	cs.shape = _shape
	cs.position = Vector2(0, -h / 2.0)
	add_child(cs)
	shock_offset = Vector2(0, -h / 2.0)
	shock_half = Vector2(9, h / 2.0)
	var l := PointLight2D.new()
	l.texture = preload("res://assets/fx/light_soft.png")
	l.color = NanoPalette.SHOCKWAVE
	l.energy = 0.7
	l.texture_scale = 1.2
	l.position = Vector2(0, -h / 2.0)
	l.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(l)


func on_shockwave(origin: Vector2, _radius: float, source: String) -> void:
	if is_broken:
		return
	if source != "shock":
		_flinch = 0.3
		Sfx.play(self, "res://assets/audio/sfx/impactMetal_light_001.ogg", -8.0, 1.4)
		return
	is_broken = true
	GameState.mark_collected(_id)
	Sfx.play(self, "crate_break", -4.0, 1.5)
	Debris.burst(get_parent(), global_position + Vector2(0, -height_tiles * 16.0), NanoPalette.SHOCKWAVE, 14)
	broken.emit()
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	_flinch = maxf(_flinch - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var h := height_tiles * 32.0
	var a := 0.34 + 0.08 * sin(_t * 4.0) + (0.4 if _flinch > 0.0 and int(_flinch * 30.0) % 2 == 0 else 0.0)
	var c := Color(NanoPalette.SHOCKWAVE.r * 1.3, NanoPalette.SHOCKWAVE.g * 1.3, NanoPalette.SHOCKWAVE.b * 1.3, a)
	draw_rect(Rect2(-8, -h, 16, h), c)
	var y := -h
	var i := 0
	while y < 0.0:
		draw_line(Vector2(-8, y), Vector2(8, y + 8.0 * (1 if i % 2 == 0 else -1)), Color(1.0, 0.9, 0.55, 0.8), 1.0)
		y += 16.0
		i += 1
	draw_rect(Rect2(-9, -h, 2, h), Color(1.2, 1.0, 0.6, 0.85))
	draw_rect(Rect2(7, -h, 2, h), Color(1.2, 1.0, 0.6, 0.85))
