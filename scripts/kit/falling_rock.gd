class_name FallingRock
extends Hazard
## A rock dropped by FallingDebris: falls, hurts the cat it hits (one pip), and
## shatters on the floor. Not meant to be placed by hand.

var vy := 0.0
var shattered := false
var _shape := RectangleShape2D.new()


func _ready() -> void:
	super()
	kill = false
	phase_through = false
	var cs := CollisionShape2D.new()
	_shape.size = Vector2(14, 14)
	cs.shape = _shape
	cs.position = Vector2(0, 0)
	add_child(cs)
	add_child(KitArt.make_sprite("falling_debris", "rock", 1.0))
	z_index = 6


func _physics_process(delta: float) -> void:
	if shattered:
		return
	for b in get_overlapping_bodies():
		if b is Cat and not b.dead and not b.is_phasing():
			b.hurt(global_position)
			shatter()
			return
	vy += 900.0 * delta
	var from := global_position
	var to := from + Vector2(0, vy * delta)
	var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, 6), to + Vector2(0, 8))
	q.collision_mask = 1
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = Vector2(from.x, hit.position.y - 8.0)
		shatter()
	else:
		global_position = to


func shatter() -> void:
	if shattered:
		return
	shattered = true
	KitSfx.play(self, "rock_land")
	ExplosionFX.spawn(get_parent(), global_position, 0.3, 0, Color(0.4, 0.5, 0.55), false)
	Debris.burst(get_parent(), global_position, Color(0.45, 0.52, 0.58), 6)
	queue_free()
