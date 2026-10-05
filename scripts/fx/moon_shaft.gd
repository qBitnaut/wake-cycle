@tool
class_name MoonShaft
extends Node2D
## A shaft of light through a roof hole, a window or leaves: the lit air (an
## additive god-ray trapezoid with slow streaks), a cone-textured PointLight2D,
## a soft pool where it lands, and dust motes that only show where light falls.
##
## The node's origin is the opening (top centre of the shaft). The shaft runs
## `length` px down, leaning `angle` degrees (positive leans right).
##
## Adaptive (on by default): every frame the shaft reads the scene's lighting
## and follows it, so the same shaft is cool moonlight in the dark warehouse,
## pales and fades as dawn comes, and turns to a golden sunbeam by day.
##   Inputs                                      Outputs
##   key light (the LightingRig's moon, or the   haze tint (follow_light);
##     sun by day): colour, live energy against  strength of the haze, light
##     the rig's authored energy                   and pool
##   CanvasModulate against the rig's authored   brighter ambient (SkyProgress's
##     night_tint                                  dawn, a lightning flash): the
##                                                 shaft washes out and pales
##                                                 towards the sky's hue; by day,
##                                                 finer, crisper streaks
##   rain falling through the opening (a RainFX  thinner, fainter haze; fainter
##     over it, at its live intensity)             motes
##   setting INDOOR / OUTDOOR                    the shape: a defined beam,
##                                                 brightest under the opening, or
##                                                 open-air rays, softer, fading
##                                                 at both ends
##   the cat inside the shaft                    a soft shadow down the haze
## At the rig's authored lighting a shaft looks exactly as its exports say, so
## ray_intensity, light_energy, floor_glow and dust_amount are the per-room
## overrides. Without a rig (or with `adaptive` off) the exports apply as they are.

enum Setting { INDOOR, OUTDOOR }

const RAY_SHADER := preload("res://shaders/god_ray.gdshader")
const NOISE := preload("res://assets/fx/noise_small.png")
const CONE := preload("res://assets/fx/light_cone.png")
const MOTE_SHADER := preload("res://shaders/mote.gdshader")
const HALO := preload("res://assets/fx/halo.png")

## Haze shape per setting: soft_top, soft_bottom, roundness, fade_in,
## far_level, fade_out, streak_amount.
const SHAPES := {
	Setting.INDOOR: [0.14, 0.5, 0.65, 0.09, 0.4, 0.0, 0.28],
	Setting.OUTDOOR: [0.3, 0.6, 0.4, 0.1, 0.7, 0.45, 0.25],
}
## Damps how strongly a brighter ambient washes the shaft out (higher = gentler).
const WASH := 0.3
## Streak feature size across the shaft, reference px (x FXScale): soft haze
## by night, finer and crisper rays in daylight (strong sun through dusty air).
const STREAK_PX := 5.0
const STREAK_PX_DAY := 2.5
const STREAK_DAY := 0.5
## How many times longer than wide the streaks are, by night and by day.
const STRETCH := 10.0
const STRETCH_DAY := 24.0

@export var length := 140.0:
	set(v):
		length = v
		_rebuild()
@export var top_width := 26.0:
	set(v):
		top_width = v
		_rebuild()
@export var bottom_width := 54.0:
	set(v):
		bottom_width = v
		_rebuild()
@export_range(-60.0, 60.0, 0.5) var angle := 18.0:
	set(v):
		angle = v
		_rebuild()
## The shaft's own colour: the cone light's, and the haze's where it does not
## follow the key light.
@export var color: Color = FXPalette.MOON_RAY:
	set(v):
		color = v
		_rebuild()

@export_group("Ray")
## Strength of the lit air at the scene's authored lighting.
@export_range(0.0, 2.0, 0.01) var ray_intensity := 0.32:
	set(v):
		ray_intensity = v
		_rebuild()
@export_range(0.0, 1.0, 0.01) var ray_flicker := 0.0:
	set(v):
		ray_flicker = v
		_rebuild()
## Where the lit air starts, px below the origin (the underside of a thick roof).
@export_range(0.0, 200.0, 1.0) var ray_start := 0.0:
	set(v):
		ray_start = v
		_rebuild()

## Soft additive pool where the shaft meets the floor (0 = off).
@export_range(0.0, 2.0, 0.01) var floor_glow := 0.35:
	set(v):
		floor_glow = v
		_rebuild()

@export_group("Adaptive")
## Follow the scene's lighting, the rain and the cat (see the class notes).
@export var adaptive := true:
	set(v):
		adaptive = v
		_rebuild()
## INDOOR: a beam through a roof hole or window. OUTDOOR: open-air rays
## (through leaves, breaking cloud), softer, fading at both ends.
@export var setting := Setting.INDOOR:
	set(v):
		setting = v
		_rebuild()
## How far the haze takes the key light's colour (moon silver-blue, sun gold)
## rather than `color`. 0 pins `color`.
@export_range(0.0, 1.0, 0.01) var follow_light := 1.0:
	set(v):
		follow_light = v
		_rebuild()
## How much rain falling through the opening thins and dims the haze (0 = none).
@export_range(0.0, 1.0, 0.01) var rain_response := 1.0
## How dark the cat's shadow down the haze is (0 = none).
@export_range(0.0, 1.0, 0.01) var cat_shadow := 0.5

@export_group("Light")
@export var light_enabled := true:
	set(v):
		light_enabled = v
		_rebuild()
@export_range(0.0, 6.0, 0.01) var light_energy := 1.2:
	set(v):
		light_energy = v
		_rebuild()
## Shadowed lights are costly on the web; the moon DirectionalLight2D usually
## already shades the room, so this is off by default.
@export var light_shadows := false:
	set(v):
		light_shadows = v
		_rebuild()
## Whether the light also reveals light-only motes (dust, hole rain). Turn it
## off for weak spill shafts so motes appear only in the main beams.
@export var light_motes := true:
	set(v):
		light_motes = v
		_rebuild()

@export_group("Dust")
@export_range(0, 200) var dust_amount := 40:
	set(v):
		dust_amount = v
		_rebuild()
## Mote size in px. 1 = one art pixel (HD); 0 = auto (FXScale.whole, 2 px at 640x360).
@export_range(0, 8) var dust_px := 1:
	set(v):
		dust_px = v
		_rebuild()
@export var dust_color := Color(1.6, 1.7, 2.0):
	set(v):
		dust_color = v
		_rebuild()

var _ray: Polygon2D
var _light: PointLight2D
var _dust: CPUParticles2D
var _pool: Sprite2D

var _rig: LightingRig
var _rains: Array[RainFX] = []
var _cat: Node2D
var _strength := 1.0
var _shade := 0.0
## Live state, for audits: 1 at the rig's authored lighting.
var presence := 1.0
## Rain through the opening, 0..1.
var rain := 0.0
## How far the shaft has paled towards the ambient hue, 0..1.
var pale := 0.0
## The haze colour in use.
var tint := Color.WHITE
## How much the scene reads as day (bright ambient), 0..1: crisper streaks.
var daylight := 0.0


func _ready() -> void:
	_ray = Polygon2D.new()
	_ray.name = "Ray"
	var mat := ShaderMaterial.new()
	mat.shader = RAY_SHADER
	mat.set_shader_parameter("noise", NOISE)
	_ray.material = mat
	add_child(_ray)
	_pool = Sprite2D.new()
	_pool.name = "FloorGlow"
	_pool.texture = HALO
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_pool.material = pm
	add_child(_pool)
	_light = PointLight2D.new()
	_light.name = "Light"
	_light.texture = CONE
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_dust = CPUParticles2D.new()
	_dust.name = "Dust"
	var lm := ShaderMaterial.new()
	lm.shader = MOTE_SHADER
	_dust.material = lm
	_dust.light_mask = LightingRig.MASK_MOTES
	_dust.lifetime = 7.0
	_dust.preprocess = 7.0
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.direction = Vector2(1, 0)
	_dust.spread = 180.0
	var f := FXScale.factor(self)
	_dust.gravity = Vector2(0.4, 0.8) * f
	_dust.initial_velocity_min = 0.5 * f
	_dust.initial_velocity_max = 3.0 * f
	_dust.damping_min = 0.1 * f
	_dust.damping_max = 0.4 * f
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	_dust.color_ramp = ramp
	add_child(_dust)
	_rebuild()
	if not Engine.is_editor_hint():
		# After the siblings' _ready: the rig records its authored lighting there.
		_find_context.call_deferred()


## Brighten or dim the whole shaft (haze, light, pool) at once, e.g. clouds passing.
func set_strength(s: float) -> void:
	_strength = s
	_update(0.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not adaptive:
		return
	_update(delta)


## The rig whose lighting this shaft follows (the nearest one up the tree),
## and the rain that could fall through it.
func _find_context() -> void:
	_rig = null
	var n := get_parent()
	var scope: Node = n
	while n and _rig == null:
		for c in n.get_children():
			if c is LightingRig:
				_rig = c
				scope = n
				break
		n = n.get_parent()
	_rains.clear()
	if scope:
		for r in scope.find_children("*", "RainFX", true, false):
			_rains.append(r as RainFX)
	_update(0.0)


func _rebuild() -> void:
	if _ray == null:
		return
	var shape: Array = SHAPES[setting]
	var lean := tan(deg_to_rad(angle)) * length
	var ht := top_width * 0.5
	var hb := bottom_width * 0.5
	# The polygon is the core grown by the penumbra at each end (the shader's
	# falloff reaches zero exactly on its edges).
	var pt: float = ht * (1.0 + shape[0])
	var pb: float = hb * (1.0 + shape[1])
	_ray.polygon = PackedVector2Array([
		Vector2(-pt, 0), Vector2(pt, 0), Vector2(lean + pb, length), Vector2(lean - pb, length)])
	var mat := _ray.material as ShaderMaterial
	mat.set_shader_parameter("shaft_length", maxf(length, 1.0))
	mat.set_shader_parameter("lean", lean)
	mat.set_shader_parameter("soft_top", shape[0])
	mat.set_shader_parameter("soft_bottom", shape[1])
	mat.set_shader_parameter("roundness", shape[2])
	mat.set_shader_parameter("start", ray_start)
	mat.set_shader_parameter("fade_in", shape[3])
	mat.set_shader_parameter("far_level", shape[4])
	mat.set_shader_parameter("fade_out", shape[5])
	mat.set_shader_parameter("drift", 0.6 * FXScale.factor(self))
	mat.set_shader_parameter("flicker", ray_flicker)
	# Cone light: the texture's apex is its top centre, so offset it down by
	# half its height and lean it with the shaft. Uniform scale only: a
	# non-uniform scale on a rotated Light2D shears its texture.
	_light.enabled = light_enabled
	_light.shadow_enabled = light_shadows
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_light.shadow_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | (LightingRig.MASK_MOTES if light_motes else 0)
	var tex_h := float(CONE.get_height())
	_light.texture_scale = length * 1.08 / tex_h
	_light.offset = Vector2(0, tex_h * 0.5)
	_light.rotation = deg_to_rad(-angle)
	_light.scale = Vector2.ONE
	_pool.visible = floor_glow > 0.0
	_pool.position = Vector2(lean, length - 2.0)
	_pool.scale = Vector2(bottom_width * 1.5, 14.0 * FXScale.factor(self)) / float(HALO.get_width())
	_dust.scale_amount_min = float(dust_px if dust_px > 0 else FXScale.whole(self))
	_dust.scale_amount_max = _dust.scale_amount_min
	_dust.amount = maxi(dust_amount, 1)
	_dust.emitting = dust_amount > 0
	_dust.visible = dust_amount > 0
	_dust.color = dust_color
	_dust.position = Vector2(lean * 0.5, length * 0.5)
	_dust.emission_rect_extents = Vector2(maxf(top_width, bottom_width) * 0.5 + absf(lean) * 0.5, length * 0.5)
	_update(0.0)


## Reads the scene's lighting, the rain and the cat, and applies them.
func _update(delta: float) -> void:
	if _ray == null:
		return
	var live := adaptive and not Engine.is_editor_hint()
	presence = 1.0
	pale = 0.0
	rain = 0.0
	daylight = 0.0
	var base := color
	var sky := Color.WHITE
	if live and _rig and is_instance_valid(_rig):
		var cm := _rig.get_canvas_modulate()
		var ambient: Color = cm.color if cm else _rig.night_tint
		var la := _luma(ambient)
		var la0 := _luma(_rig.design_tint)
		daylight = smoothstep(0.55, 0.8, la)
		presence = (la0 + WASH) / (la + WASH)
		var k0 := _rig.design_key_strength
		if k0 > 0.0:
			presence *= _rig.key_strength() / k0
		presence = clampf(presence, 0.0, 1.6)
		if _rig.moon_enabled:
			base = color.lerp(_vivid(_rig.moon_color), follow_light)
		pale = clampf((la - la0) / maxf(1.0 - la0, 0.05), 0.0, 1.0)
		sky = ambient / maxf(maxf(ambient.r, ambient.g), maxf(ambient.b, 0.001))
	if live:
		rain = _rain_through() * rain_response
	tint = _normalised(base.lerp(sky, pale * 0.75))
	var s := presence * _strength
	var mat := _ray.material as ShaderMaterial
	mat.set_shader_parameter("ray_color", tint)
	var shape: Array = SHAPES[setting]
	mat.set_shader_parameter("streak_amount", lerpf(shape[6], STREAK_DAY, daylight))
	mat.set_shader_parameter("streak_px", lerpf(STREAK_PX, STREAK_PX_DAY, daylight) * FXScale.factor(self))
	mat.set_shader_parameter("streak_stretch", lerpf(STRETCH, STRETCH_DAY, daylight))
	mat.set_shader_parameter("intensity", ray_intensity * s * (1.0 - 0.5 * rain))
	var thin := 1.0 - 0.3 * rain
	mat.set_shader_parameter("top_half", top_width * 0.5 * thin)
	mat.set_shader_parameter("bottom_half", bottom_width * 0.5 * thin)
	_light.color = color.lerp(Color.WHITE, 0.25).lerp(sky, pale * 0.5)
	_light.energy = light_energy * s
	_pool.modulate = Color(tint * floor_glow * s * (1.0 - 0.3 * rain), 1.0)
	_dust.self_modulate = Color(1, 1, 1, 1.0 - 0.6 * rain)
	_update_shade(mat, delta if live else -1.0)


## A soft shadow down the haze below the cat while it stands in the shaft.
func _update_shade(mat: ShaderMaterial, delta: float) -> void:
	if delta < 0.0 or cat_shadow <= 0.0:
		_shade = 0.0
		mat.set_shader_parameter("shade", Vector4.ZERO)
		return
	if _cat == null or not is_instance_valid(_cat):
		_cat = get_tree().get_first_node_in_group("player") as Node2D
	var want := 0.0
	var p := Vector2.ZERO
	var half := 14.0
	if _cat and _cat.is_visible_in_tree():
		var body := _cat.get_node_or_null("Shape") as CollisionShape2D
		var spr := _cat.get_node_or_null("Sprite") as CanvasItem
		p = to_local(body.global_position if body else _cat.global_position)
		if body and body.shape is RectangleShape2D:
			half = (body.shape as RectangleShape2D).size.x * 0.65
		var t := clampf(p.y / maxf(length, 1.0), 0.0, 1.0)
		var lean := tan(deg_to_rad(angle)) * length
		var reach := lerpf(top_width, bottom_width, t) * 0.5 + half
		var seen := spr == null or spr.modulate.a > 0.5
		if seen and p.y > -half and p.y < length and absf(p.x - lean * t) < reach:
			want = cat_shadow
	_shade = move_toward(_shade, want, delta * 2.5)
	mat.set_shader_parameter("shade", Vector4(p.x, p.y, half, _shade))


## The strongest rain falling through the opening, 0..1 (density 60 per 100 px = 1).
func _rain_through() -> float:
	var top := global_position
	var best := 0.0
	for r in _rains:
		if r == null or not is_instance_valid(r) or not r.is_visible_in_tree():
			continue
		var k := r.get_intensity()
		if k <= 0.01:
			continue
		var rp := r.global_position
		if absf(top.x - rp.x) > r.width * 0.5 + top_width * 0.5:
			continue
		if rp.y > top.y + 16.0 or rp.y + r.floor_y < top.y:
			continue
		best = maxf(best, k * clampf(r.density / 60.0, 0.0, 1.0))
	return best


static func _luma(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


## A light's colour made a touch more saturated: haze reads paler than the
## light that makes it, so the shaft keeps the light's hue.
static func _vivid(c: Color) -> Color:
	var l := _luma(c)
	return _normalised(Color(l + (c.r - l) * 1.3, l + (c.g - l) * 1.3, l + (c.b - l) * 1.3))


## Brightest channel 1, so intensity means the same for any hue.
static func _normalised(c: Color) -> Color:
	var m := maxf(maxf(c.r, c.g), maxf(c.b, 0.001))
	return Color(maxf(c.r, 0.0) / m, maxf(c.g, 0.0) / m, maxf(c.b, 0.0) / m, 1.0)
