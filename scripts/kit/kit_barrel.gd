class_name KitBarrel
extends StaticBody2D
## Explosive and acid barrels (Duke Nukem style).
##
## EXPLOSIVE: the shockwave, the ground pound, a turret bolt, a bomb or another
## blast sets it off. A short flashing fuse, then a Blast: enemies and the cat in
## the radius are hurt, breakable walls that take blasts break, and neighbouring
## barrels go off in turn (the chain reaction).
## ACID: breaks into an AcidPool puddle that lasts a while; no blast.
## Origin = the foot of the barrel. The cat cannot walk through it (breakables layer).
## For a pushable barrel see PushBarrel.

enum Kind { EXPLOSIVE, ACID }

@export var kind: Kind = Kind.EXPLOSIVE
@export var blast_radius := 84.0
@export var fuse := 0.2
@export var pool_width := 80.0
@export var pool_life := 8.0
## Stay gone after a respawn (use for barrels that open a way).
@export var persist := false
## 0 = manifest scale.
@export var sprite_scale := 0.0

var armed := false
var sprite: AnimatedSprite2D
var shock_offset := Vector2(0, -16)
var shock_half := Vector2(12, 16)
var _fuse_left := 0.0
var _id := ""
var _t := 0.0
var _scale := 1.0
var _aid := ""
var _rect := Rect2(-11, -33, 22, 33)


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	add_to_group("shock_receiver")
	add_to_group("explosive")
	add_to_group("projectile_target")
	_aid = "barrel_explosive" if kind == Kind.EXPLOSIVE else "barrel_acid"
	_scale = sprite_scale if sprite_scale > 0.0 else KitArt.default_scale(_aid)
	var b := KitArt.bounds(_aid)
	_rect = Rect2(b.position * _scale, b.size * _scale)
	shock_offset = _rect.get_center()
	shock_half = _rect.size * 0.5
	sprite = KitArt.make_sprite(_aid, "", _scale)
	add_child(sprite)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = _rect.size * Vector2(0.9, 1.0)
	cs.shape = sh
	cs.position = _rect.get_center()
	add_child(cs)
	if persist:
		_id = str(get_path())
		if GameState.is_collected(_id):
			queue_free()


func on_shockwave(_origin: Vector2, _radius: float, _source: String) -> void:
	trigger(0.0)


func on_projectile_hit(_p: Node) -> void:
	trigger(0.0)


func on_blast(_origin: Vector2, _radius: float) -> void:
	trigger(0.0)


## Set it off after `delay` seconds (plus the fuse). Chain reactions pass a delay.
func trigger(delay := 0.0) -> void:
	if armed:
		return
	armed = true
	_fuse_left = delay + fuse
	if kind == Kind.EXPLOSIVE:
		sprite.play("lit")
		KitSfx.play(self, "barrel_fuse")
	else:
		sprite.play("leak")


func _physics_process(delta: float) -> void:
	_t += delta
	if not armed:
		return
	_fuse_left -= delta
	sprite.modulate = Color(2.2, 2.0, 1.8) if int(_t * 24.0) % 2 == 0 else Color.WHITE
	if _fuse_left <= 0.0:
		_burst()


func _burst() -> void:
	if persist:
		GameState.mark_collected(_id)
	var c := to_global(_rect.get_center())
	if kind == Kind.EXPLOSIVE:
		armed = false
		remove_from_group("explosive")
		Blast.explode(self, c, blast_radius, self)
		queue_free()
	else:
		remove_from_group("explosive")
		KitSfx.play(self, "acid_splash")
		Debris.burst(get_parent(), c, Color(0.5, 0.95, 0.85), 10)
		AcidPool.spawn(get_parent(), _floor_point(), pool_width, pool_life)
		queue_free()


func _floor_point() -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -4), global_position + Vector2(0, 200))
	q.collision_mask = 1
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else global_position
