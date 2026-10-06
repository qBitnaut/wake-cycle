class_name AcidPool
extends Hazard
## An acid pool: a shallow hazard (one pip and a knock-back, never fatal). Placed in
## a level it is permanent; spawned by a broken acid barrel it spreads over
## `spread_time` (a hiss, the telegraph), lasts `lifetime` s, then dries up. Origin =
## the middle of the pool's surface line on the floor.

@export var width := 64.0
## 0 = permanent.
@export var lifetime := 0.0
@export var spread_time := 0.5
@export var depth := 12.0

var age := 0.0
var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()
var _frames := 0.0
var _t := randf() * 3.0


static func spawn(parent: Node, pos: Vector2, width_ := 80.0, life := 8.0) -> AcidPool:
	var p := AcidPool.new()
	p.width = width_
	p.lifetime = life
	parent.add_child(p)
	p.global_position = pos
	return p


func _ready() -> void:
	super()
	kill = false
	phase_through = false
	add_to_group("acid_pool")
	_cs.shape = _shape
	add_child(_cs)
	z_index = 2
	_layout(1.0 if spread_time <= 0.0 else 0.1)
	if lifetime > 0.0 or spread_time > 0.0:
		KitSfx.play(self, "acid_hiss")


func _current_width_k() -> float:
	return clampf(age / maxf(spread_time, 0.001), 0.1, 1.0) if spread_time > 0.0 else 1.0


func is_dangerous() -> bool:
	return active and _current_width_k() > 0.35


func _layout(k: float) -> void:
	var dry := 1.0
	if lifetime > 0.0:
		dry = clampf((lifetime - age) / 1.5, 0.0, 1.0)
	_shape.size = Vector2(maxf(width * k, 4.0), depth * dry)
	_cs.position = Vector2(0, -depth * dry * 0.5)
	active = dry > 0.1 and k > 0.35


func _physics_process(delta: float) -> void:
	age += delta
	_t += delta
	if lifetime > 0.0 and age >= lifetime:
		queue_free()
		return
	_layout(_current_width_k())
	super(delta)
	queue_redraw()


func _draw() -> void:
	var k := _current_width_k()
	var w := width * k
	var dry := 1.0
	if lifetime > 0.0:
		dry = clampf((lifetime - age) / 1.5, 0.0, 1.0)
	var tex := KitArt.frame_texture("acid_pool", "pool", "bubble", int(_t * 4.0) % 3)
	if tex == null:
		return
	var x := -w * 0.5
	var h := 14.0 * dry
	while x < w * 0.5 - 0.5:
		var seg := minf(32.0, w * 0.5 - x)
		draw_texture_rect_region(tex, Rect2(Vector2(x, -h + 1.0), Vector2(seg, h)), Rect2(0, 14.0 - h, seg, h), Color(1.2, 1.2, 1.2, 0.5 + 0.5 * dry))
		x += 32.0
