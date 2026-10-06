class_name Collectible
extends Area2D
## Kit collectibles (they replace the plain diamond). Keep the C-A-T letters:
## those are Pickup.Kind.LETTER and are not part of this.
##
##   FISH    heals 2 pips            YARN   100     BELL   250     MOUSE  500
##   BONE    golden fish bone 2000   CHIP   1000 (robot loot)      MEMORY 5000 + a story line
##
## Each has its own sprite (manifest "pickup_<name>"), a glint, a pickup sparkle,
## a score pop-up and a logical SFX (pickup_small / pickup_big / pickup_rare).
## `persist` records a placed item in GameState.collected so it stays gone after a
## respawn; drops from robots are not persistent.

signal collected(kind: int)

enum Kind { FISH, YARN, BELL, MOUSE, BONE, CHIP, MEMORY }

const TABLE := {
	Kind.FISH: {"id": "pickup_fish", "score": 0, "heal": 2, "sfx": "pickup_heal", "col": Color("e89a7a"), "name": "FISH"},
	Kind.YARN: {"id": "pickup_yarn", "score": 100, "heal": 0, "sfx": "pickup_small", "col": Color("c98068"), "name": "YARN"},
	Kind.BELL: {"id": "pickup_bell", "score": 250, "heal": 0, "sfx": "pickup_big", "col": Color("ffd23f"), "name": "BELL"},
	Kind.MOUSE: {"id": "pickup_mouse", "score": 500, "heal": 0, "sfx": "pickup_big", "col": Color("e8a0a8"), "name": "MOUSE"},
	Kind.BONE: {"id": "pickup_bone", "score": 2000, "heal": 0, "sfx": "pickup_rare", "col": Color("ffd23f"), "name": "BONE"},
	Kind.CHIP: {"id": "pickup_chip", "score": 1000, "heal": 0, "sfx": "pickup_big", "col": Color("41b5c0"), "name": "CHIP"},
	Kind.MEMORY: {"id": "pickup_memory", "score": 5000, "heal": 0, "sfx": "pickup_rare", "col": Color("e8dcff"), "name": "MEMORY"},
}
const GLINT_PERIOD := 2.4
const GLINT_TIME := 0.6

@export var kind: Kind = Kind.YARN
@export var persist := true
## 0 = the manifest's scale.
@export var sprite_scale := 0.0
## MEMORY: a Monologue set id to play, else `line` is spoken.
@export var memory_id := ""
@export var line := "...I know this place. I have been here before."

var sprite: AnimatedSprite2D
var picked := false

var _t := randf() * 6.0
var _id := ""
var _drop_vel := Vector2.ZERO
var _dropping := false
var _grace := 0.0
var _scale := 1.0
var _rect := Rect2(-12, -12, 24, 24)


## A robot's loot: pops up out of `pos` and falls to the floor.
static func drop(parent: Node, pos: Vector2, kind_: Kind) -> Collectible:
	var c := Collectible.new()
	c.kind = kind_
	c.persist = false
	c._dropping = true
	c._drop_vel = Vector2(randf_range(-70.0, 70.0), -230.0)
	c._grace = 0.35
	KitUtil.add_at(parent, c, pos, true)
	return c


func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	add_to_group("collectible")
	var info: Dictionary = TABLE[kind]
	_scale = sprite_scale if sprite_scale > 0.0 else KitArt.default_scale(info.id)
	var b := KitArt.bounds(info.id)
	_rect = Rect2(b.position * _scale, b.size * _scale)
	sprite = KitArt.make_sprite(info.id, "", _scale)
	sprite.self_modulate = Color(1.15, 1.15, 1.15)
	add_child(sprite)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(maxf(_rect.size.x + 8.0, 26.0), maxf(_rect.size.y + 8.0, 26.0))
	cs.shape = sh
	cs.position = _rect.get_center()
	add_child(cs)
	body_entered.connect(_on_body)
	if persist:
		_id = str(get_path())
		if GameState.is_collected(_id):
			queue_free()
	z_index = 4


func score_value() -> int:
	return int(TABLE[kind].score)


func _on_body(body: Node) -> void:
	if picked or _grace > 0.0 or not body is Cat:
		return
	pick(body as Cat)


func pick(_c: Cat) -> void:
	if picked:
		return
	picked = true
	var info: Dictionary = TABLE[kind]
	var col: Color = info.col
	if int(info.heal) > 0:
		GameState.set_health(GameState.health + int(info.heal))
	if int(info.score) > 0:
		GameState.add_score(int(info.score))
	KitSfx.play(self, info.sfx)
	var pos := global_position + _rect.get_center()
	var parent := get_parent()
	var label := ("+%d" % info.score) if int(info.score) > 0 else "+HP"
	ScorePopup.spawn(parent, pos + Vector2(0, -12), label, col)
	var tier := 0 if kind in [Kind.FISH, Kind.YARN] else (2 if kind in [Kind.BONE, Kind.MEMORY] else 1)
	Debris.burst(parent, pos, col, 6 + 4 * tier)
	if tier >= 1:
		ShockwaveFX.spawn(parent, pos, 22.0 + 10.0 * tier, col, 0.0)
	if kind == Kind.MEMORY:
		KitSfx.play(self, "memory_fragment")
		if memory_id != "" and Monologue.has_set(memory_id):
			Monologue.play(memory_id)
		else:
			Monologue.say(line)
	if persist:
		GameState.mark_collected(_id)
	collected.emit(kind)
	queue_free()


func _physics_process(delta: float) -> void:
	_grace = maxf(_grace - delta, 0.0)
	if not _dropping:
		return
	_drop_vel.y += 900.0 * delta
	var from := global_position
	var to := from + _drop_vel * delta
	var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, -2), to)
	q.collision_mask = 1
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
	else:
		global_position = hit.position
		if _drop_vel.y > 120.0 and hit.normal.y < -0.5:
			_drop_vel = Vector2(_drop_vel.x * 0.5, -_drop_vel.y * 0.35)
		else:
			_dropping = false
	if global_position.y > 4000.0:
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	sprite.position.y = roundf(sin(_t * 3.0) * 2.0) if not _dropping else 0.0
	queue_redraw()


func _draw() -> void:
	var col: Color = TABLE[kind].col
	var c := _rect.get_center()
	var breath := 0.5 + 0.5 * sin(_t * 2.2)
	# Emissive halo (HDR), so the night tint cannot bury it; rarer = bigger and brighter.
	var tier := 0 if kind in [Kind.FISH, Kind.YARN] else (2 if kind in [Kind.BONE, Kind.MEMORY] else 1)
	var r := 11.0 + 3.0 * tier + 1.5 * breath
	draw_circle(c, r, Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, 0.10 + 0.05 * tier + 0.05 * breath))
	if tier >= 1:
		_glint(c + Vector2(7, -8), _t, 1.0)
		_glint(c + Vector2(-8, 3), _t + GLINT_PERIOD * 0.5, 0.6)
	if tier >= 2:
		for i in 3:
			var a := _t * 1.6 + i * TAU / 3.0
			var p := c + Vector2(cos(a) * 15.0, sin(a) * 9.0).round()
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, 0.9))


func _glint(at: Vector2, t: float, strength: float) -> void:
	var ph := fmod(t, GLINT_PERIOD) / GLINT_TIME
	if ph >= 1.0:
		return
	var k := sin(ph * PI) * strength
	var rr := 2.0 + 5.0 * k
	var c := Color(1.0, 0.97, 0.78, minf(k * 1.4, 1.0))
	draw_line(at + Vector2(-rr, 0), at + Vector2(rr, 0), c, 1.0)
	draw_line(at + Vector2(0, -rr), at + Vector2(0, rr), c, 1.0)
