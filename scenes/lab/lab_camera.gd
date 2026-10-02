extends Camera3D
## Slow cinematic drift for the atmosphere lab, so the beams show parallax.

@export var target := Vector3.ZERO
@export var sway := Vector3(0.7, 0.12, 0.35)
@export var period := 46.0

var _base: Vector3
var _t := 0.0


func _ready() -> void:
	_base = position
	look_at(target)


func _process(delta: float) -> void:
	_t += delta
	var w := TAU / period
	position = _base + Vector3(sin(_t * w) * sway.x, sin(_t * w * 0.7) * sway.y, (cos(_t * w) - 1.0) * sway.z)
	look_at(target + Vector3(sin(_t * w * 0.5) * 0.3, 0.0, 0.0))
