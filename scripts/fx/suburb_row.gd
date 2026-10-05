class_name SuburbRow
extends Node2D
## A far row of suburban house silhouettes along a road, for the dawn at the end
## of the perimeter: gabled roofs, chimneys, a few windows lit warm, trees
## between them. Flat cut-outs in a hazy blue-grey; no collision. Origin = the
## ground line at the left end.

@export var length := 640.0
@export var seed_value := 7
@export var tint := Color(0.30, 0.36, 0.52)
@export var window_lit := Color(1.0, 0.78, 0.42)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var x := 0.0
	while x < length:
		var w := rng.randf_range(54.0, 92.0)
		var h := rng.randf_range(34.0, 58.0)
		var roof := rng.randf_range(16.0, 28.0)
		var shade := rng.randf_range(0.85, 1.1)
		var c := Color(tint.r * shade, tint.g * shade, tint.b * shade)
		draw_rect(Rect2(x, -h, w, h), c)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 5, -h), Vector2(x + w * 0.5, -h - roof), Vector2(x + w + 5, -h)]), c.darkened(0.12))
		if rng.randf() < 0.5:
			draw_rect(Rect2(x + w * 0.7, -h - roof * 0.9, 6, roof * 0.7), c.darkened(0.18))
		for i in 2:
			if rng.randf() < 0.6:
				var wx := x + 10.0 + i * (w - 28.0)
				var lit := rng.randf() < 0.45
				draw_rect(Rect2(wx, -h + 12, 8, 10), Color(window_lit, 0.9) if lit else c.darkened(0.3))
		x += w
		# A tree or a gap between houses.
		var gap := rng.randf_range(10.0, 34.0)
		if rng.randf() < 0.6 and gap > 18.0:
			var tx := x + gap * 0.5
			draw_rect(Rect2(tx - 2, -16, 4, 16), c.darkened(0.3))
			draw_circle(Vector2(tx, -28), rng.randf_range(11.0, 16.0), c.darkened(0.1))
		x += gap
