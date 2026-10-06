class_name ExplosionFX
extends Node2D
## A proper defeat: white flash, fireball (CC0 Warped City frames), debris chunks
## that fly, bounce off the floor and fade, a smoke puff, a screen shake scaled to
## `size`, and a score pop-up.
##
##     ExplosionFX.spawn(level, enemy.global_position + Vector2(0, -20), 1.0, 200)
##
## size: ~0.3 a spark, 1 a bot, 2 a mech. Frees itself. Built on the existing FX
## kit (ScreenShake, the puff sheet, the light texture).

const PUFFS := preload("res://assets/fx/puff_sheet.png")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const LIFE := 1.7
const FADE := 0.5
const GRAVITY := 900.0

var size := 1.0
var score := 0
var shake := true
var debris_tint := Color(0.55, 0.65, 0.7)
## Audit hooks.
var chunk_count := 0
var bounces := 0
var _chunks: Array = []
var _t := 0.0
var _light: PointLight2D
var _boom: AnimatedSprite2D
var _flash := 0.0


static func spawn(parent: Node, pos: Vector2, size_ := 1.0, score_ := 0, debris := Color(0.55, 0.65, 0.7), shake_ := true) -> ExplosionFX:
	var fx := ExplosionFX.new()
	fx.size = size_
	fx.score = score_
	fx.debris_tint = debris
	fx.shake = shake_
	fx.z_index = 40
	KitUtil.add_at(parent, fx, pos)
	return fx


func _ready() -> void:
	add_to_group("explosion_fx")
	_build_fireball()
	_build_chunks()
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 0.9 * size + 0.3
	_light.color = Color(1.0, 0.62, 0.25)
	_light.energy = 2.2
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	if size >= 0.6:
		_build_smoke()
	if shake:
		ScreenShake.shake_at(self, clampf(0.12 + 0.28 * size, 0.1, 0.9), clampf(0.2 + 0.12 * size, 0.2, 0.6))
	if score > 0:
		ScorePopup.spawn(get_parent(), global_position + Vector2(0, -22.0 * size - 6.0), "+%d" % score)


func _build_fireball() -> void:
	var d := KitArt.fx("explosion")
	if d.is_empty():
		return
	var tex: Texture2D = load("res://" + str(d.file))
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("boom")
	sf.set_animation_speed("boom", float(d.fps))
	sf.set_animation_loop("boom", false)
	for i in int(d.frames):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * d.cell[0], 0, d.cell[0], d.cell[1])
		sf.add_frame("boom", at)
	_boom = AnimatedSprite2D.new()
	_boom.sprite_frames = sf
	_boom.scale = Vector2.ONE * (0.55 + 0.5 * size)
	_boom.self_modulate = Color(1.3, 1.2, 1.1)
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_boom.material = mat
	add_child(_boom)
	_boom.animation_finished.connect(_boom.queue_free)
	_boom.play("boom")


func _build_chunks() -> void:
	if size < 0.5:
		chunk_count = 3
	else:
		chunk_count = clampi(int(5.0 + 6.0 * size), 5, 22)
	var tex := KitArt.frames("debris_chunk", "body")
	for i in chunk_count:
		var ang := randf_range(-PI * 0.95, -PI * 0.05)
		var spd := randf_range(90.0, 230.0) * (0.7 + 0.5 * size)
		_chunks.append({
			"pos": Vector2(randf_range(-5, 5), randf_range(-5, 5)) * size,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"rot": randf() * TAU, "spin": randf_range(-9.0, 9.0),
			"tex": tex.get_frame_texture(["a", "b", "c"][i % 3], 0) if tex.has_animation("a") else null,
			"s": randf_range(0.8, 1.5) * (0.8 + 0.3 * size),
			"n": 0, "rest": false,
		})


func _build_smoke() -> void:
	var p := CPUParticles2D.new()
	p.texture = PUFFS
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.4 + 0.4 * size
	var pm := CanvasItemMaterial.new()
	pm.particles_animation = true
	pm.particles_anim_h_frames = 5
	pm.particles_anim_v_frames = 1
	p.material = pm
	p.anim_speed_min = 1.0
	p.anim_speed_max = 1.0
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = clampi(int(4.0 + 3.0 * size), 4, 12)
	p.lifetime = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, -28)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 40.0 * (0.7 + 0.4 * size)
	p.color = Color(0.5, 0.52, 0.6, 0.55)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true


func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, 1.0 - _t / 0.3)
	if _light:
		_light.energy = 2.2 * _flash * _flash
		_light.enabled = _flash > 0.02
	var space := get_world_2d().direct_space_state
	for c in _chunks:
		if c.rest:
			continue
		c.vel.y += GRAVITY * delta
		var from: Vector2 = c.pos
		var to: Vector2 = from + c.vel * delta
		var q := PhysicsRayQueryParameters2D.create(to_global(from), to_global(to))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			c.pos = to
			c.rot += c.spin * delta
		else:
			c.pos = to_local(hit.position + hit.normal * 0.5)
			c.vel = c.vel.bounce(hit.normal) * 0.45
			c.spin *= 0.5
			c.n += 1
			bounces += 1
			if c.n >= 3 or c.vel.length() < 30.0:
				c.rest = true
				c.vel = Vector2.ZERO
	queue_redraw()
	if _t >= LIFE:
		queue_free()


func _draw() -> void:
	var a := clampf((LIFE - _t) / FADE, 0.0, 1.0)
	if _t < 0.09:
		draw_circle(Vector2.ZERO, (10.0 + 18.0 * size) * (_t / 0.09 + 0.3), Color(2.0, 1.9, 1.6, 0.9))
	for c in _chunks:
		if c.tex == null:
			continue
		draw_set_transform(c.pos.round(), c.rot, Vector2.ONE * c.s)
		draw_texture(c.tex, Vector2(-4, -4), Color(debris_tint.r * 1.2, debris_tint.g * 1.2, debris_tint.b * 1.2, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
