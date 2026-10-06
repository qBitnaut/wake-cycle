class_name PushBarrel
extends RigidBody2D
## A plain barrel: the cat shoves it by walking into it; the shockwave and a blast
## kick it. It counts as "pushable" (floor plates feel its weight). Origin = its foot.

@export var sprite_scale := 0.0

var shock_offset := Vector2(0, -16)
var shock_half := Vector2(11, 16)


func _ready() -> void:
	add_to_group("pushable")
	add_to_group("shock_receiver")
	add_to_group("blast_receiver")
	lock_rotation = true
	collision_layer = 1
	collision_mask = 1 | 16 | 64
	mass = 2.0
	linear_damp = 0.6
	var m := PhysicsMaterial.new()
	m.friction = 0.5
	physics_material_override = m
	var s := sprite_scale if sprite_scale > 0.0 else KitArt.default_scale("barrel_plain")
	var b := KitArt.bounds("barrel_plain")
	var r := Rect2(b.position * s, b.size * s)
	shock_offset = r.get_center()
	shock_half = r.size * 0.5
	add_child(KitArt.make_sprite("barrel_plain", "", s))
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size * Vector2(0.9, 0.98)
	cs.shape = sh
	cs.position = r.get_center()
	add_child(cs)


func on_shockwave(origin: Vector2, _radius: float, _source: String) -> void:
	sleeping = false
	var side := signf(global_position.x - origin.x) if absf(global_position.x - origin.x) > 1.0 else 1.0
	apply_central_impulse(Vector2(side * 196.0, -160.0) * mass)


func on_blast(origin: Vector2, _radius: float) -> void:
	on_shockwave(origin, 0.0, "blast")
