class_name KitEnemy
extends CharacterBody2D
## Base of every kit enemy. Owns what they share, so each subclass is only its
## behaviour (`_tick`):
##
##  * art from the manifest (`actor_id`), scaled by the exported `sprite_scale`
##    (0 = the manifest's default); the body and hit boxes come from the art bounds
##  * the defeat rules, a table per source of harm (stomp / shock / pound / blast):
##    "none" (clank, nothing happens), "stun" or "destroy". A stunned enemy is
##    finished by a stomp or a pound. `armour_hits` > 0 makes it take that many
##    harming hits first (the heavy mech). A cat with no power and no shockwave
##    harms nothing: a stomp only bounces it off with a clank
##  * stun look (stars, sparks, a fizzling flicker), hit-flash, and the defeat:
##    flash, then ExplosionFX (+ score pop-up), a data-chip drop, `defeated`
##  * telegraph bookkeeping (`begin_telegraph` / `end_telegraph`), so an audit can
##    measure the warning each attack gives
##
## Groups: enemy, kit_enemy, shock_receiver (on_shockwave from the cat's burst).

signal defeated(enemy: KitEnemy)
signal stunned(enemy: KitEnemy)

enum Life { ACTIVE, STUNNED, DEAD }

const MIN_TELEGRAPH := 0.4
const BOUNDS_MASK := 64
const FLASH_TIME := 0.12

@export_group("Look")
## Pixel scale of the art. 0 = the manifest's default for this actor.
@export var sprite_scale := 0.0
@export_group("Defeat rules")
@export_enum("none", "stun", "destroy") var stomp_effect := "stun"
@export_enum("none", "stun", "destroy") var shock_effect := "stun"
@export_enum("none", "stun", "destroy") var pound_effect := "destroy"
@export_enum("none", "stun", "destroy") var blast_effect := "destroy"
## Harming hits it takes before a destroy lands (0 = none: the table decides).
@export var armour_hits := 0
## A stomp or a pound on a stunned enemy finishes it.
@export var stun_destroys := true
@export var stun_time := 3.0
@export_group("Reward")
@export var points := 200
@export var explosion_size := 1.0
@export_range(0.0, 1.0) var chip_chance := 0.35
@export_group("Contact")
@export var touch_damage := true
@export var stompable := true
@export var uses_gravity := true
@export var falls_when_stunned := false
## Share of the art box used for the solid body (the hit box is the full box + 4).
@export_range(0.4, 1.0) var body_shrink := 0.8

var actor_id := ""
var life := Life.ACTIVE
var facing := -1
var hp := 0
var stomps := 0
## Unscaled-art box scaled by sprite_scale, relative to the origin.
var rect := Rect2(-12, -30, 24, 30)
var art_scale := 1.0
## Box centre (offset from origin) and half size, used by the cat's burst range check.
var shock_offset := Vector2(0, -15)
var shock_half := Vector2(12, 15)
var tint := Color.WHITE
var telegraphing := false
var last_telegraph := 0.0
var static_body := false

var sprite: AnimatedSprite2D
var hitbox: Area2D
var body_cs: CollisionShape2D

var _t := 0.0
var _stun_left := 0.0
var _stomp_lock := 0.0
var _flash := 0.0
var _flinch := 0.0
var _dead_left := 0.0
var _tele_t := 0.0
var _spark_t := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0 if static_body else (1 | BOUNDS_MASK)
	add_to_group("enemy")
	add_to_group("kit_enemy")
	add_to_group("shock_receiver")
	art_scale = sprite_scale if sprite_scale > 0.0 else KitArt.default_scale(actor_id)
	var b := KitArt.bounds(actor_id)
	rect = Rect2(b.position * art_scale, b.size * art_scale)
	_refresh_shock_box()
	sprite = KitArt.make_sprite(actor_id, "", art_scale)
	sprite.name = "Sprite"
	add_child(sprite)
	body_cs = CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(rect.size.x * body_shrink, rect.size.y * lerpf(1.0, body_shrink, 0.4))
	body_cs.shape = sh
	body_cs.position = rect.get_center() + Vector2(0, (rect.size.y - sh.size.y) * 0.5)
	add_child(body_cs)
	hitbox = Area2D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = 2
	var hs := CollisionShape2D.new()
	var hsh := RectangleShape2D.new()
	hsh.size = rect.size + Vector2(4, 4)
	hs.shape = hsh
	hs.position = rect.get_center()
	hitbox.add_child(hs)
	add_child(hitbox)
	hp = armour_hits
	_setup()


## Subclass hook, after the art and boxes exist.
func _setup() -> void:
	pass


func _refresh_shock_box() -> void:
	shock_offset = rect.get_center()
	shock_half = rect.size * 0.5


# ---- the cat and the world ---------------------------------------------------

func cat() -> Cat:
	return get_tree().get_first_node_in_group("player") as Cat


func cat_centre() -> Vector2:
	var c := cat()
	return c.global_position + Vector2(0, -13) if c else global_position


## True when nothing solid lies between `from` and `to` (the world layer only).
func line_clear(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func can_be_harmed() -> bool:
	return GameState.shockwave_unlocked or GameState.power != NanoPalette.Power.NONE


func centre() -> Vector2:
	return to_global(rect.get_center())


func is_stunned() -> bool:
	return life == Life.STUNNED


func is_dead() -> bool:
	return life == Life.DEAD


# ---- telegraphs --------------------------------------------------------------

func begin_telegraph() -> void:
	telegraphing = true
	_tele_t = 0.0


func end_telegraph() -> void:
	if telegraphing:
		last_telegraph = _tele_t
	telegraphing = false


# ---- the loop ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	_stomp_lock = maxf(_stomp_lock - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_flinch = maxf(_flinch - delta, 0.0)
	if telegraphing:
		_tele_t += delta
	match life:
		Life.DEAD:
			_dead_left -= delta
			_apply_look()
			if _dead_left <= 0.0:
				_explode()
			return
		Life.ACTIVE:
			_tick(delta)
		Life.STUNNED:
			_stun_tick(delta)
	if (uses_gravity and life == Life.ACTIVE) or (life == Life.STUNNED and (uses_gravity or falls_when_stunned)):
		velocity.y = minf(velocity.y + 1600.0 * delta, 533.0)
	if not static_body:
		move_and_slide()
	_contact()
	_apply_look()
	queue_redraw()
	if global_position.y > 4000.0:
		queue_free()


## Subclass behaviour while ACTIVE.
func _tick(_delta: float) -> void:
	pass


func _stun_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 711.0 * delta)
	_stun_left -= delta
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = 0.45
		Debris.burst(get_parent(), centre() + Vector2(0, rect.position.y * 0.0 - rect.size.y * 0.25), Color(1.0, 0.8, 0.3), 3)
	if _stun_left <= 0.0:
		_recover()


func _recover() -> void:
	life = Life.ACTIVE
	if sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")
	_recovered()


func _recovered() -> void:
	pass


# ---- contact ---------------------------------------------------------------------

func _contact() -> void:
	if life == Life.DEAD:
		return
	for b in hitbox.get_overlapping_bodies():
		if b is Cat:
			_touch(b)


func _stomp_zone_y() -> float:
	return to_global(Vector2(0, rect.position.y + rect.size.y * 0.4)).y


func _touch(c: Cat) -> void:
	if c.is_phasing() or c.dead:
		return
	var above := stompable and c.global_position.y <= _stomp_zone_y() and c.velocity.y > 0.0
	if above:
		if _stomp_lock <= 0.0:
			_stomp(c)
	elif life == Life.ACTIVE and touch_damage:
		# Hopping over a bot it cannot hurt is free: only the sides hurt.
		if stompable and c.global_position.y <= _stomp_zone_y():
			return
		_hurt_cat(c)


func _hurt_cat(c: Cat) -> void:
	c.hurt(global_position)


func _stomp(c: Cat) -> void:
	_stomp_lock = 0.3
	c.bounce(462.0)
	if hit("stomp") == "stun":
		stomps += 1


# ---- harm ----------------------------------------------------------------------------

func effect_for(source: String) -> String:
	match source:
		"stomp":
			return stomp_effect
		"shock":
			return shock_effect
		"pound":
			return pound_effect
		"blast":
			return blast_effect
	return "none"


## Apply harm from `source` ("stomp", "shock", "pound", "blast"). Returns what
## happened: "clank", "stun", "destroy" or "ignored".
func hit(source: String) -> String:
	if life == Life.DEAD:
		return "ignored"
	var eff := effect_for(source)
	if source == "stomp" and not can_be_harmed():
		eff = "none"
	if eff == "none":
		clank()
		return "clank"
	var was_stunned := life == Life.STUNNED
	if armour_hits > 0:
		hp -= 1
		_flash = FLASH_TIME
		eff = "destroy" if hp <= 0 else "stun"
	elif eff == "stun" and was_stunned and stun_destroys and source != "shock":
		eff = "destroy"
	if eff == "destroy":
		defeat(source)
		return "destroy"
	stun(stun_time)
	return "stun"


func clank() -> void:
	_flinch = 0.28
	KitSfx.play(self, "robot_clank")
	Debris.burst(get_parent(), centre(), Color(1.0, 0.85, 0.5), 3)


func stun(t: float) -> void:
	if life == Life.DEAD:
		return
	var fresh := life != Life.STUNNED
	life = Life.STUNNED
	_stun_left = maxf(t, _stun_left) if not fresh else t
	_flash = FLASH_TIME
	end_telegraph()
	if sprite.sprite_frames.has_animation("stun"):
		sprite.play("stun")
	if fresh:
		KitSfx.play(self, "robot_stun")
		stunned.emit(self)
		_on_stunned()


func _on_stunned() -> void:
	pass


func on_shockwave(origin: Vector2, _radius: float, source: String) -> void:
	if life == Life.DEAD:
		return
	var r := hit(source)
	if r == "stun" and not static_body and uses_gravity:
		velocity.y = -140.0
		velocity.x = signf(global_position.x - origin.x) * 100.0


func on_blast(_origin: Vector2, _radius: float) -> void:
	hit("blast")


func defeat(_source := "") -> void:
	if life == Life.DEAD:
		return
	life = Life.DEAD
	end_telegraph()
	_dead_left = FLASH_TIME
	collision_layer = 0
	hitbox.set_deferred("monitoring", false)
	remove_from_group("enemy")
	remove_from_group("shock_receiver")
	_on_defeated()


func _on_defeated() -> void:
	pass


func _explode() -> void:
	var parent := get_parent()
	var pos := centre()
	ExplosionFX.spawn(parent, pos, explosion_size, points, Color(0.62, 0.66, 0.74))
	KitSfx.play(self, "robot_explode", 0.0, 1.0 / maxf(explosion_size, 0.5) * 0.8 + 0.4)
	KitSfx.play(self, "debris", -2.0)
	GameState.add_score(points)
	if randf() < chip_chance:
		Collectible.drop(parent, pos, Collectible.Kind.CHIP)
	defeated.emit(self)
	queue_free()


# ---- look ----------------------------------------------------------------------------

func _apply_look() -> void:
	var m := tint
	var jitter := 0.0
	if life == Life.DEAD:
		m = Color(3.0, 3.0, 3.0) if int(_dead_left * 60.0) % 2 == 0 else Color(1.6, 1.0, 0.8)
	elif _flash > 0.0:
		m = Color(2.6, 2.6, 2.8)
	elif _flinch > 0.0:
		m = Color(1.9, 1.9, 2.0) if int(_flinch * 36.0) % 2 == 0 else tint
		jitter = roundf(sin(_flinch * 90.0))
	elif life == Life.STUNNED:
		# Fizzle: a steady dim flicker that speeds up and gutters as the stun runs out.
		var left := maxf(_stun_left, 0.0)
		var rate := 14.0 if left > 0.9 else 34.0
		var lit := int(_t * rate) % 2 == 0
		m = Color(0.65, 0.7, 0.85) if lit else Color(1.25, 1.2, 1.1)
		jitter = roundf(sin(_t * 40.0)) * (1.0 if left > 0.9 else 2.0)
	sprite.modulate = m
	sprite.position.x = jitter


func _draw() -> void:
	if life != Life.STUNNED:
		return
	var top := Vector2(rect.get_center().x, rect.position.y - 7.0)
	for i in 3:
		var a := _t * 5.0 + i * TAU / 3.0
		var p := top + Vector2(cos(a) * 12.0, sin(a) * 4.0).round()
		var col := Color(2.0, 1.7, 0.6)
		draw_line(p + Vector2(-2, 0), p + Vector2(2, 0), col, 1.0)
		draw_line(p + Vector2(0, -2), p + Vector2(0, 2), col, 1.0)
	if int(_t * 12.0) % 3 == 0:
		var q := rect.get_center() + Vector2(randf_range(-0.5, 0.5) * rect.size.x, randf_range(-0.5, 0.5) * rect.size.y)
		draw_line(q, q + Vector2(randf_range(-4, 4), randf_range(-4, 4)), Color(0.6, 1.6, 1.8), 1.0)
