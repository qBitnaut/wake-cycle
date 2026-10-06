class_name KitConveyor
extends StaticBody2D
## A conveyor belt: a solid floor strip that carries whatever stands on it (the cat,
## crates, barrels) at `speed` px/s (positive = right). Origin = the middle of the
## belt's top surface. Embed it in the floor line.

@export var width_tiles := 3
@export var speed := 70.0

var _frame := 0.0
var _tex: Array[Texture2D] = []


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("conveyor")
	var w := width_tiles * 32.0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(w, 11.0)
	cs.shape = sh
	cs.position = Vector2(0, 5.5)
	add_child(cs)
	constant_linear_velocity = Vector2(speed, 0.0)
	for i in 4:
		_tex.append(KitArt.frame_texture("conveyor", "belt", "run", i))
	KitSfx.loop(self, "conveyor_hum", 240.0)


func set_speed(v: float) -> void:
	speed = v
	constant_linear_velocity = Vector2(v, 0.0)


func _process(delta: float) -> void:
	_frame += delta * absf(speed) / 8.0
	queue_redraw()


func _draw() -> void:
	var w := width_tiles * 32.0
	var f := int(_frame) % 4
	if speed < 0.0:
		f = 3 - f
	for i in width_tiles:
		var t := _tex[f]
		if t:
			draw_texture(t, Vector2(-w * 0.5 + i * 32.0, -3.0))
