extends Area2D
## Only exists when a save does. Step on it to load the saved game. A PadFX
## plate tinted warm gold (nothing here is a power), with a CONTINUE label.

const FONT := preload("res://assets/fonts/monogram.ttf")

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
		var fx := PadFX.new()
		fx.use_custom_color = true
		fx.custom_color = FXPalette.SODIUM
		add_child(fx)


func _on_body(body: Node) -> void:
	if body is Cat and not _used:
		_used = true
		Sfx.play(self, "checkpoint")
		SaveSystem.continue_game.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := FXPalette.SODIUM
	var y := -80.0 - 3.0 * sin(_t * 4.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-8, y - 8), Vector2(8, y), Vector2(-8, y + 8)]), c)
	draw_string(FONT, Vector2(-60, -100), "CONTINUE", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 16, c)
