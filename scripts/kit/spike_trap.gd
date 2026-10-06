class_name SpikeTrap
extends KitHazard
## A pop-up spike trap set into the floor. IDLE: flat. WARN: the tips peek out and it
## clicks (0.8 s by default). LIVE: the spikes pop up and hurt. Origin = the middle of
## the trap, on the floor line.

@export var width_tiles := 2
@export var spike_height := 20.0

var _sprites: Array[AnimatedSprite2D] = []
var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()


func _init() -> void:
	idle_time = 1.4
	warn_time = 0.8
	live_time = 0.9


func _build() -> void:
	phase_through = false
	var w := width_tiles * 32.0
	for i in width_tiles:
		var s := KitArt.make_sprite("spike_trap", "body", 1.0)
		s.position = Vector2(-w * 0.5 + 16.0 + i * 32.0, 0)
		s.play("down")
		add_child(s)
		_sprites.append(s)
	_shape.size = Vector2(w - 6.0, spike_height)
	_cs.shape = _shape
	_cs.position = Vector2(0, -spike_height * 0.5)
	add_child(_cs)
	z_index = 2


func _on_phase(p: Phase, silent: bool) -> void:
	var anim: String = ["down", "warn", "up"][p]
	for s in _sprites:
		s.play(anim)
	if silent:
		return
	if p == Phase.WARN:
		KitSfx.play(self, "spike_warn")
	elif p == Phase.LIVE:
		KitSfx.play(self, "spike_pop")
