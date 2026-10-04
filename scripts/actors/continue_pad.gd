extends Area2D
## Only exists when a save does. Step on it to load the saved game.

const FONT := preload("res://assets/fonts/m5x7.ttf")

var _t := 0.0
var _used := false


func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	var has := SaveSystem.has_save()
	visible = has
	monitoring = has
	if has:
		body_entered.connect(_on_body)


func _on_body(body: Node) -> void:
	if body is Cat and not _used:
		_used = true
		Sfx.play(self, "checkpoint")
		SaveSystem.continue_game.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Color("ffe27a")
	draw_rect(Rect2(-11, -3, 22, 3), c)
	draw_rect(Rect2(-9, -4, 18, 1), c.lightened(0.5))
	var y := -14.0 - 2.0 * sin(_t * 4.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-4, y - 4), Vector2(4, y), Vector2(-4, y + 4)]), c)
	draw_string(FONT, Vector2(-30, -26), "CONTINUE", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 16, c)
