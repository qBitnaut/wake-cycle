extends Node2D
## Placeholder glow around the cat, recoloured by the active nano power.
## FX can replace this node; it only listens to GameState.power_changed.

var _color := Color.WHITE
var _on := false
var _t := 0.0


func _ready() -> void:
	GameState.power_changed.connect(_on_power)
	_on_power(GameState.power, 0.0)


func _on_power(power: int, _duration: float) -> void:
	_on = power != NanoPalette.Power.NONE
	_color = NanoPalette.color_of(power)
	visible = _on


func _process(delta: float) -> void:
	if _on:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 8.0)
	# Hugs the cat (about 31x23 px) and still rings its 22x26 box.
	draw_circle(Vector2.ZERO, 17.0, Color(_color, 0.12 + 0.08 * pulse))
	draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 24, Color(_color, 0.5 + 0.3 * pulse), 1.0)
