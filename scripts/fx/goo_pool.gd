@tool
class_name GooPool
extends Node2D
## The goo pool: black, oily liquid with no colour of its own (the colour
## of the transformation belongs to the cat). A dim desaturated mirror, a
## muted silver sheen, a slow viscous swell and dark bubbles that swell and
## pop; disturbing it (surge(), or the cat wading through) stirs it harder.
##
## grip(x) is the transformation's hold on the cat: the surface swells into
## a mound round the legs, the goo boils with dark bubbles and droplets, and
## dark tendrils climb. release() lets go. The origin is the pool's top-left
## (the surface line).
##
## `circuit` brings back the older nanotech look (glowing traces that wake
## up close, a coloured glow light, glowing bubbles); off by default.

const SHADER := preload("res://shaders/goo_pool.gdshader")
const NOISE := preload("res://assets/fx/noise_small.png")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
## Headroom above the surface for the grip mound, px.
const TOP_MARGIN := 8.0

@export var width := 72.0:
	set(v):
		width = v
		_apply()
@export var depth := 14.0:
	set(v):
		depth = v
		_apply()
@export var color_a: Color = FXPalette.NANO_BLUE:
	set(v):
		color_a = v
		_apply()
@export var color_b: Color = FXPalette.NANO_GREEN:
	set(v):
		color_b = v
		_apply()
## Keep near 1: higher clips the hue towards white; the 2D glow adds the bloom.
@export_range(0.0, 6.0, 0.05) var trace_energy := 1.4:
	set(v):
		trace_energy = v
		_apply()
@export_range(0.0, 6.0, 0.05) var light_energy := 2.0
## Glowing bubbles (circuit look only).
@export var bubbles := true
## The older nanotech look: circuit traces, glow light, glowing bubbles.
@export var circuit := false:
	set(v):
		circuit = v
		_apply()
## Strength of the slow swell and the surface bubbles (0 = still).
@export_range(0.0, 3.0, 0.05) var ripple := 1.0:
	set(v):
		ripple = v
		_apply()
## Circuit look only: 1 = traces wake near the cat or when disturbed;
## 0 = always awake.
@export_range(0.0, 1.0, 0.01) var dormancy := 1.0:
	set(v):
		dormancy = v
		_apply()
## Circuit look only: how near (px) the cat must be before traces show.
@export var reveal_radius := 72.0
## Wading through it disturbs it (a surge on entry, a trickle while moving).
@export var auto_disturb := true
## Strength of the dim screen mirror (a puddle is about 0.9).
@export_range(0.0, 1.0, 0.01) var reflectivity := 0.22:
	set(v):
		reflectivity = v
		_apply()
## Trace mask (white traces, tiles horizontally) and its pixel scale.
## 0 = auto (FXScale.whole, right for the baked mask); 1 with an HD mask.
@export var circuit_texture: Texture2D = preload("res://assets/fx/goo_circuit.png")
@export_range(0, 8) var art_scale := 0

var _rect: ColorRect
var _light: PointLight2D
var _bubbles: CPUParticles2D
var _boil: CPUParticles2D
var _back: GooTendrils
var _front: GooTendrils
var _t := 0.0
var _surge := 0.0
var _reveal := 0.0
var _grip := 0.0
var _grip_target := 0.0
var _grip_x := 0.0
var _wading := false


func _ready() -> void:
	add_to_group("goo_pool")
	# Fresh copy of the screen above the pool for the mirror.
	var bbc := BackBufferCopy.new()
	bbc.name = "Mirror"
	bbc.copy_mode = BackBufferCopy.COPY_MODE_RECT
	add_child(bbc)
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("noise", NOISE)
	mat.set_shader_parameter("circuit", circuit_texture)
	mat.set_shader_parameter("top_margin", TOP_MARGIN)
	_rect.material = mat
	add_child(_rect)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_bubbles = _particles(6, true)
	_bubbles.direction = Vector2(0, -1)
	_bubbles.spread = 5.0
	_bubbles.gravity = Vector2.ZERO
	add_child(_bubbles)
	_apply()


func _particles(n: int, unshaded: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = n
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.3, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	if unshaded:
		var bm := CanvasItemMaterial.new()
		bm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		p.material = bm
	return p


## Flare the pool (0..1), e.g. when the cat steps in. Decays on its own.
func surge(amount := 1.0) -> void:
	_surge = clampf(maxf(_surge, amount), 0.0, 1.0)


## The goo takes hold at global x: the surface swells, boils (dark bubbles
## and droplets) and sends dark tendrils up the legs. `actor_z` is the held actor's z_index; tendrils are
## drawn just behind and just in front of it.
func grip(global_x: float, amount := 1.0, actor_z := 5) -> void:
	_grip_x = global_x - global_position.x
	var tighter := amount > _grip_target
	_grip_target = clampf(amount, 0.0, 1.0)
	if _front == null:
		_back = _make_tendrils(3, 9.0, 14.0, 3.0)
		_front = _make_tendrils(3, 11.0, 18.0, 11.0)
		_boil = _particles(10, false)
		_boil.direction = Vector2(0, -1)
		_boil.spread = 35.0
		_boil.gravity = Vector2(0, 260)
		_boil.initial_velocity_min = 30.0
		_boil.initial_velocity_max = 60.0
		_boil.lifetime = 0.45
		_boil.scale_amount_min = 2.0
		_boil.scale_amount_max = 2.0
		_boil.color = Color(0.06, 0.07, 0.11)
		add_child(_boil)
	for t in [_back, _front]:
		t.position = Vector2(_grip_x, 0)
		t.z_as_relative = false
	_back.z_index = actor_z - 1
	_front.z_index = actor_z + 2
	_boil.position = Vector2(_grip_x, 0)
	_boil.emission_rect_extents = Vector2(12, 1)
	if tighter:
		surge(0.8)


## Let go: the mound settles and the tendrils sink back.
func release() -> void:
	_grip_target = 0.0


func _make_tendrils(n: int, spread: float, h: float, seed: float) -> GooTendrils:
	var t := GooTendrils.new()
	t.count = n
	t.spread = spread
	t.max_height = h
	t.seed_offset = seed
	t.glowing_tips = circuit
	t.tip_a = color_a
	t.tip_b = color_b
	add_child(t)
	return t


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _light == null:
		return
	_t += delta
	_surge = maxf(_surge - delta * 0.8, 0.0)
	_grip = move_toward(_grip, _grip_target, delta * (0.8 if _grip_target > _grip else 1.0))
	_track_cat(delta)
	var awake := clampf(maxf(maxf(1.0 - dormancy, _surge), maxf(_reveal * 0.4, _grip)), 0.0, 1.0) if circuit else 0.0
	# The light wakes less than the traces: a held cat stands right on it.
	var lit := clampf(maxf(maxf(1.0 - dormancy, _surge), maxf(_reveal * 0.3, _grip * 0.6)), 0.0, 1.0)
	var k := 0.5 + 0.5 * sin(_t * 0.9)
	# Leans blue: green light on warm fur turns it lime.
	_light.color = color_a.lerp(color_b, k * 0.55)
	_light.energy = light_energy * (0.8 + 0.2 * sin(_t * 2.3)) * lerpf(0.1, 1.0, lit)
	var mat := _rect.material as ShaderMaterial
	mat.set_shader_parameter("surge", _surge)
	mat.set_shader_parameter("reveal", _reveal)
	mat.set_shader_parameter("grip", _grip)
	mat.set_shader_parameter("grip_x", _grip_x)
	_bubbles.color = Color(color_a.lerp(color_b, 1.0 - k) * 1.8, awake)
	if _front:
		_back.amount = _grip
		_front.amount = _grip
		_boil.emitting = _grip > 0.15


## The nearest player sets the proximity reveal; wading disturbs the goo.
func _track_cat(delta: float) -> void:
	var cat := get_tree().get_first_node_in_group("player") as Node2D
	if cat == null:
		_reveal = move_toward(_reveal, 0.0, delta)
		return
	var lp := cat.global_position - global_position
	var dx := maxf(maxf(-lp.x, lp.x - width), 0.0)
	var dy := absf(lp.y)
	var want := 1.0 - smoothstep(reveal_radius * 0.5, reveal_radius, maxf(dx, dy * 0.5))
	_reveal = move_toward(_reveal, want, delta * 1.5)
	(_rect.material as ShaderMaterial).set_shader_parameter("reveal_x", clampf(lp.x, 0.0, width))
	if not auto_disturb:
		return
	var inside := dx <= 0.0 and lp.y > -6.0 and lp.y < depth
	if inside and not _wading:
		surge(0.7)
	elif inside and cat.get("velocity") is Vector2 and absf((cat.get("velocity") as Vector2).x) > 10.0:
		surge(0.3)
	_wading = inside


func _apply() -> void:
	if _rect == null:
		return
	_rect.position = Vector2(0, -TOP_MARGIN)
	_rect.size = Vector2(width, depth + TOP_MARGIN)
	var bbc := get_node_or_null("Mirror") as BackBufferCopy
	if bbc:
		bbc.rect = Rect2(-4, -depth * 2.0 - TOP_MARGIN - 4.0, width + 8, depth * 3.0 + TOP_MARGIN + 8.0)
	var mat := _rect.material as ShaderMaterial
	mat.set_shader_parameter("color_a", color_a)
	mat.set_shader_parameter("color_b", color_b)
	mat.set_shader_parameter("glow_energy", trace_energy)
	mat.set_shader_parameter("rect_width", width)
	mat.set_shader_parameter("rect_height", depth)
	mat.set_shader_parameter("dormancy", dormancy)
	mat.set_shader_parameter("reveal_radius", reveal_radius)
	mat.set_shader_parameter("reflectivity", reflectivity)
	mat.set_shader_parameter("circuit_on", 1.0 if circuit else 0.0)
	mat.set_shader_parameter("ripple", ripple)
	mat.set_shader_parameter("px_scale", float(art_scale if art_scale > 0 else FXScale.whole(self)))
	_light.position = Vector2(width * 0.5, -2)
	_light.texture_scale = maxf(width / 128.0 * 2.2, 0.6)
	_light.color = color_a
	_light.energy = light_energy
	_bubbles.position = Vector2(width * 0.5, depth * 0.8)
	_bubbles.emission_rect_extents = Vector2(width * 0.42, 1)
	var f := FXScale.factor(self)
	_bubbles.initial_velocity_min = 3.0 * f
	_bubbles.initial_velocity_max = 6.0 * f
	_bubbles.scale_amount_min = float(FXScale.whole(self))
	_bubbles.scale_amount_max = _bubbles.scale_amount_min
	_bubbles.lifetime = maxf(depth * 0.8 / (4.5 * f), 0.4)
	_bubbles.emitting = bubbles and circuit
	_bubbles.visible = circuit
	_light.enabled = circuit
