class_name Projectile
extends Area2D
## Generic enemy projectile: BOLT (slow energy bolt), BOMB (falls, blasts) or
## SPARK (falls fast, small). A hitbox on the hazards layer with a trail, a glow,
## an impact FX and a lifetime. A phasing (dashing) cat passes through. Anything
## in "projectile_target" (barrels) with on_projectile_hit(p) is set off by it;
## solid world and walls stop it.
##
##     Projectile.spawn(level, muzzle, dir * 120.0, Projectile.Kind.BOLT)

signal despawned(reason: String)

enum Kind { BOLT, BOMB, SPARK }

const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const TRAIL_POINTS := 9

@export var kind: Kind = Kind.BOLT
@export var lifetime := 4.0
## Beyond this distance from where it was fired it despawns.
@export var max_range := 900.0
## 0 = manifest default.
@export var sprite_scale := 0.0
@export var blast_radius := 0.0
@export var fall_gravity := 0.0

var velocity := Vector2.ZERO
var age := 0.0
var done := false
var reason := ""

var _origin := Vector2.ZERO
var _sprite: AnimatedSprite2D
var _light: PointLight2D
var _trail: Array[Vector2] = []
var _col := Color(1.0, 0.55, 0.16)


static func spawn(parent: Node, pos: Vector2, vel: Vector2, kind_ := Kind.BOLT, scale_ := 0.0) -> Projectile:
	var p := Projectile.new()
	p.kind = kind_
	p.velocity = vel
	p.sprite_scale = scale_
	match kind_:
		Kind.BOMB:
			p.fall_gravity = 700.0
			p.blast_radius = 44.0
			p.lifetime = 5.0
		Kind.SPARK:
			p.fall_gravity = 420.0
			p.lifetime = 3.0
		_:
			p.lifetime = 5.0
	parent.add_child(p)
	p.global_position = pos
	return p


func _ready() -> void:
	add_to_group("kit_projectile")
	collision_layer = 8
	collision_mask = 2 | 1 | 16
	var aid: String = ["bolt", "bomb", "spark"][kind]
	var s := sprite_scale if sprite_scale > 0.0 else KitArt.default_scale(aid)
	_sprite = KitArt.make_sprite(aid, "body", s)
	_sprite.self_modulate = Color(1.5, 1.4, 1.3)
	add_child(_sprite)
	var b := KitArt.bounds(aid)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = b.size * s * 0.8
	cs.shape = sh
	cs.position = b.get_center() * s
	add_child(cs)
	_col = [Color(1.0, 0.55, 0.16), Color(1.0, 0.3, 0.2), Color(0.3, 0.9, 1.0)][kind]
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 0.45
	_light.color = _col
	_light.energy = 1.0
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_origin = global_position
	z_index = 6
	if kind == Kind.BOLT:
		_sprite.rotation = velocity.angle()
	elif kind == Kind.BOMB:
		KitSfx.play(self, "bomb_drop")


func _physics_process(delta: float) -> void:
	if done:
		return
	age += delta
	velocity.y += fall_gravity * delta
	global_position += velocity * delta
	if kind == Kind.BOLT:
		_sprite.rotation = velocity.angle()
	_trail.push_front(global_position)
	if _trail.size() > TRAIL_POINTS:
		_trail.pop_back()
	for b in get_overlapping_bodies():
		if b is Cat:
			if b.is_phasing() or b.dead:
				continue
			b.hurt(global_position)
			_impact("cat")
			return
		if b.has_method("on_projectile_hit"):
			b.on_projectile_hit(self)
			_impact("target")
			return
		_impact("world")
		return
	if age >= lifetime:
		_despawn("lifetime")
	elif global_position.distance_to(_origin) > max_range:
		_despawn("range")
	queue_redraw()


func _impact(why: String) -> void:
	if done:
		return
	var parent := get_parent()
	if kind == Kind.BOMB:
		Blast.explode(self, global_position, blast_radius)
	else:
		ExplosionFX.spawn(parent, global_position, 0.28, 0, _col, false)
	_despawn("impact_" + why)


func _despawn(why: String) -> void:
	if done:
		return
	done = true
	reason = why
	despawned.emit(why)
	queue_free()


func _draw() -> void:
	# Trail: fading additive-looking dots behind the head, in local space.
	for i in range(1, _trail.size()):
		var k := 1.0 - float(i) / TRAIL_POINTS
		var p := to_local(_trail[i])
		draw_circle(p, (1.0 + 2.5 * k) * (1.4 if kind == Kind.BOMB else 1.0), Color(_col.r * 1.6, _col.g * 1.6, _col.b * 1.6, 0.5 * k))
	draw_circle(Vector2.ZERO, 7.0, Color(_col.r * 1.5, _col.g * 1.5, _col.b * 1.5, 0.18))
