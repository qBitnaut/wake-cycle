class_name KitBeam
extends Hazard
## A short laser burst: a hazard rectangle drawn as a hot red beam, live only while
## `fire()` runs. A phasing cat passes through. It is stopped by the world, like the
## bot that fires it. Origin = the muzzle; it points along local +x (rotate the node).

@export var reach := 200.0
@export var thickness := 5.0

var firing := false
var length := 0.0
var _left := 0.0
var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()
var _t := 0.0


func _ready() -> void:
	super()
	kill = false
	phase_through = true
	active = false
	_cs.shape = _shape
	_shape.size = Vector2(8, thickness)
	add_child(_cs)
	z_index = 7


## Fire for `seconds`: the beam is measured against the world first.
func fire(seconds: float) -> void:
	var from := global_position
	var to := from + Vector2.RIGHT.rotated(global_rotation) * reach
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = 1
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	length = from.distance_to(hit.position) if not hit.is_empty() else reach
	_shape.size = Vector2(maxf(length, 4.0), thickness)
	_cs.position = Vector2(length * 0.5, 0.0)
	_left = seconds
	firing = true
	active = true
	queue_redraw()


func _physics_process(delta: float) -> void:
	_t += delta
	if not firing:
		return
	_left -= delta
	if _left <= 0.0:
		firing = false
		active = false
		queue_redraw()
		return
	super(delta)
	queue_redraw()


func _draw() -> void:
	if not firing:
		return
	var f := 0.8 + 0.2 * sin(_t * 90.0)
	draw_line(Vector2.ZERO, Vector2(length, 0), Color(1.0 * 1.4, 0.29 * 1.4, 0.23 * 1.4, 0.45 * f), thickness + 4.0)
	draw_line(Vector2.ZERO, Vector2(length, 0), Color(1.0 * 1.6, 0.29 * 1.6, 0.23 * 1.6, 1.0), thickness)
	draw_line(Vector2.ZERO, Vector2(length, 0), Color(1.0, 0.94 * 1.2, 0.88 * 1.2, 1.0), 2.0)
	draw_circle(Vector2.ZERO, 5.0, Color(2.0, 1.2, 0.9, 0.8))
