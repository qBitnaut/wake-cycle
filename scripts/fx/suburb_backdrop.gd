class_name SuburbBackdrop
extends Node2D
## The first hint of the suburbs, far beyond the city: a low strip of dark house
## silhouettes, trees and little warm windows, drawn on the horizon in front of
## the towers. It scrolls slower than the camera (like NightBackdrop's layers)
## and fades in between `fade_from` and `fade_to` (the camera's x), so the room
## begins with the machine city only and ends with lights in windows.
## Origin = the horizon (house bases sit on it). The owner sets position.y.

const WARM := Color(2.0, 1.15, 0.5)
const WARM_DIM := Color(1.4, 0.8, 0.38)
const DARK := Color(0.055, 0.065, 0.12)
const DARKER := Color(0.04, 0.05, 0.095)
const TREE := Color(0.035, 0.07, 0.09)

@export var scroll := 0.22
@export var fade_from := 2600.0
@export var fade_to := 4700.0
@export var span := 2600.0

var _fade_cache := -1.0


func _ready() -> void:
	z_index = -8
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	modulate.a = 0.0
	queue_redraw()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var cx := cam.get_screen_center_position().x
	global_position.x = roundf(cx * (1.0 - scroll))
	modulate.a = smoothstep(fade_from, fade_to, cx)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	# The strip covers layer x 0..span, denser towards the right (the suburbs proper).
	var x := 0.0
	while x < span:
		var density := clampf(x / span, 0.0, 1.0)
		if rng.randf() < 0.35 + 0.5 * density:
			_house(x, rng, density)
			x += rng.randf_range(26.0, 54.0)
		else:
			if rng.randf() < 0.6:
				_tree(x + 8.0, rng)
			x += rng.randf_range(14.0, 34.0)
	# A ground line under everything.
	draw_rect(Rect2(0, -2, span, 8), DARKER)


func _tree(x: float, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(6.0, 11.0)
	draw_rect(Rect2(x - 1, -r, 2, r), DARKER)
	draw_circle(Vector2(x, -r - r * 0.6), r, TREE)
	draw_circle(Vector2(x + r * 0.5, -r - r * 0.2), r * 0.7, TREE)


func _house(x: float, rng: RandomNumberGenerator, density: float) -> void:
	var w := rng.randf_range(20.0, 34.0)
	var h := rng.randf_range(12.0, 20.0)
	var roof := rng.randf_range(7.0, 12.0)
	var body := DARK if rng.randf() < 0.5 else DARKER
	draw_rect(Rect2(x, -h, w, h), body)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 2, -h), Vector2(x + w * 0.5, -h - roof), Vector2(x + w + 2, -h)]), body)
	draw_rect(Rect2(x + w * 0.72, -h - roof * 0.9, 3, roof * 0.7), body)  # chimney
	# Windows: a few lit, warmer and more of them towards the right.
	var cols := 2 if w < 27.0 else 3
	for i in cols:
		var wx := x + 4.0 + i * (w - 8.0) / cols
		var lit := rng.randf() < 0.3 + 0.55 * density
		if lit:
			draw_rect(Rect2(wx, -h + 4, 3, 4), WARM if rng.randf() < 0.6 else WARM_DIM)
		if h > 15.0 and rng.randf() < 0.5:
			draw_rect(Rect2(wx, -h + 11, 3, 3), WARM_DIM if rng.randf() < 0.5 else DARKER)
	if rng.randf() < 0.25:
		draw_circle(Vector2(x + w + 6.0, -14.0), 1.5, WARM)  # a street lamp
		draw_rect(Rect2(x + w + 5.5, -13, 1, 13), DARKER)
