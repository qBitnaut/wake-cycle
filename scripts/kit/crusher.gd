class_name Crusher
extends KitHazard
## A piston crusher. Origin = the attachment point on the ceiling (top-centre). The
## head rests up; WARN: the rod shudders, a red strip lights on the head and dust
## sifts down; LIVE: the head slams down `stroke` px in ~0.1 s and holds (hurting
## anything under it), then rises slowly through the idle time. A hit hurts one pip.
## Set `stroke` so the head's underside reaches the floor.

@export var width_tiles := 1
@export var stroke := 96.0
@export var slam_time := 0.1
@export var retract_time := 0.9

var head_y := 0.0
var _slammed := false

var _head: AnimatedSprite2D
var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()
var _rod_tex: Texture2D


func _init() -> void:
	idle_time = 1.8
	warn_time = 0.9
	live_time = 0.5


func _build() -> void:
	phase_through = false
	_head = KitArt.make_sprite("crusher", "head", 1.0)
	add_child(_head)
	_rod_tex = KitArt.frame_texture("crusher", "rod", "idle")
	var w := width_tiles * 32.0
	_shape.size = Vector2(w - 4.0, 20.0)
	_cs.shape = _shape
	add_child(_cs)
	z_index = 3
	_pose(0.0)


func _pose(y: float) -> void:
	head_y = y
	_head.position = Vector2(0, y)
	_cs.position = Vector2(0, y + 14.0)


func _on_phase(p: Phase, silent: bool) -> void:
	if p == Phase.WARN:
		_head.play("warn")
		if not silent:
			KitSfx.play(self, "crusher_warn")
	elif p == Phase.LIVE:
		_head.play("idle")
		if not silent:
			KitSfx.play(self, "crusher_slam")
			ScreenShake.shake_at(self, 0.45, 0.3)
			Debris.burst(get_parent(), global_position + Vector2(0, stroke + 24.0), Color(0.6, 0.65, 0.7), 5)
	else:
		_head.play("idle")


func _step(_delta: float) -> void:
	match phase:
		Phase.IDLE:
			var k := clampf(phase_time / retract_time, 0.0, 1.0)
			_pose(stroke * (1.0 - k) if _slammed else 0.0)
			_head.position.x = 0.0
		Phase.WARN:
			_pose(0.0)
			_head.position.x = roundf(sin(clock * 60.0)) * 1.0
			_head.position.y = roundf(sin(clock * 40.0)) * 1.0
		Phase.LIVE:
			_slammed = true
			_pose(stroke * clampf(phase_time / slam_time, 0.0, 1.0))
			_head.position.x = 0.0


func _draw() -> void:
	if _rod_tex == null:
		return
	var y := 0.0
	while y < head_y:
		draw_texture(_rod_tex, Vector2(-4.0 + _head.position.x, y), Color.WHITE)
		y += 8.0
	if phase == Phase.WARN:
		var a := 0.3 + 0.3 * sin(clock * 24.0)
		draw_rect(Rect2(Vector2(-width_tiles * 16.0, stroke + 4.0), Vector2(width_tiles * 32.0, 2.0)), Color(2.0, 0.4, 0.3, a))
