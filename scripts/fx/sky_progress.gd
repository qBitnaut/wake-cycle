class_name SkyProgress
extends Node
## The storm's last gasp, then dawn: lightens the night over the length of a
## room. The cat's x between `x_from` and `x_to` sets a target 0..1; the real
## `progress` eases towards it (so a checkpoint reload or a teleport does not
## jump). It drives:
##   the LightingRig's CanvasModulate (deep night to blue-grey pre-dawn),
##   moon energy, vignette and glow,
##   the NightBackdrop brightness and its moon,
##   a warm additive DawnGlow band on the horizon,
##   the rain (each RainFX's intensity, thinning to a drizzle).
## `dawn` (0..1) is a separate boost for the finale: the sky blushes and the
## last rain stops. While LightningFX is mid-flash the tint is left to it.

@export var rig: LightingRig
@export var backdrop: NightBackdrop
@export var lightning: LightningFX
@export var rains: Array[RainFX] = []
@export var x_from := 0.0
@export var x_to := 1000.0
@export var horizon_y := 250.0
@export var follow_speed := 1.2

@export_group("Night")
@export var night_tint := Color(0.36, 0.40, 0.58)
@export var night_moon := 0.85
@export var night_vignette := 0.30
@export var night_backdrop := 1.0
@export_group("Pre-dawn")
@export var dawn_tint := Color(0.70, 0.76, 0.92)
@export var dawn_moon := 0.35
@export var dawn_vignette := 0.12
@export var dawn_backdrop := 2.3
@export var rain_floor := 0.12
@export_group("Sunrise (finale boost)")
@export var sunrise_tint := Color(0.95, 0.86, 0.84)
@export var sunrise_backdrop := 3.0

## Eased progress 0..1 (what is applied) and the target for the cat's x.
var progress := 0.0
var target := 0.0
var dawn := 0.0

var _cat: Node2D
var _glow: Sprite2D
var _throttle := 0.0


func _ready() -> void:
	_glow = Sprite2D.new()
	_glow.name = "DawnGlow"
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.62, 0.42, 0.0), Color(1.0, 0.66, 0.5, 0.55), Color(1.0, 0.82, 0.62, 1.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 8
	_glow.texture = tex
	_glow.scale = Vector2(120.0, 26.0)  # 960 x 208 px
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow.material = m
	_glow.z_index = -9  # above the exterior backdrop (-9, earlier in the tree), below the suburbs (-8)
	_glow.modulate.a = 0.0
	add_child(_glow)
	_glow.top_level = true


func target_for(x: float) -> float:
	return clampf((x - x_from) / maxf(x_to - x_from, 1.0), 0.0, 1.0)


## Jump to the target at once (a teleport, an audit).
func snap() -> void:
	_find_cat()
	if _cat:
		target = target_for(_cat.global_position.x)
	progress = target
	_apply(true)


func _find_cat() -> void:
	if _cat == null or not is_instance_valid(_cat):
		_cat = get_tree().get_first_node_in_group("player") as Node2D


func _process(delta: float) -> void:
	_find_cat()
	if _cat:
		target = target_for(_cat.global_position.x)
	progress = move_toward(progress, target, delta * follow_speed * (0.25 + absf(progress - target) * 2.0))
	_apply(false, delta)


## Warm brightness of the sky, 0 (night) .. 1 (pre-dawn) .. 1.5 (sunrise): an audit hook.
func light_level() -> float:
	return progress + dawn * 0.5


func _apply(force: bool, delta := 0.0) -> void:
	var p := progress * progress * (3.0 - 2.0 * progress)  # smoothstep
	var cam := get_viewport().get_camera_2d()
	var cx := cam.get_screen_center_position().x if cam else 0.0
	if rig:
		var cm := rig.get_canvas_modulate()
		if cm and (lightning == null or lightning._level < 0.001):
			cm.color = night_tint.lerp(dawn_tint, p).lerp(sunrise_tint, dawn)
	if _glow:
		# (The sprite is centred: 960 px wide on the camera, 208 px tall from 168 above the horizon to 40 below.)
		_glow.global_position = Vector2(cx, horizon_y - 64.0)
		_glow.modulate.a = clampf(p * p * 0.35 + dawn * 0.35, 0.0, 1.0)
	_throttle -= delta
	if not force and _throttle > 0.0:
		return
	_throttle = 0.2
	if rig:
		rig.moon_energy = lerpf(night_moon, dawn_moon, p)
		rig.vignette = lerpf(night_vignette, dawn_vignette, p)
	if backdrop:
		backdrop.brightness = lerpf(night_backdrop, dawn_backdrop, p) + (sunrise_backdrop - dawn_backdrop) * dawn
		var moon := backdrop.get_node_or_null("MoonLayer") as Node2D
		if moon:
			moon.modulate.a = clampf(1.0 - p * 1.2, 0.0, 1.0)
	var k := snappedf(lerpf(1.0, rain_floor, p) * (1.0 - dawn), 0.1)
	for r in rains:
		if r:
			r.set_intensity(k)


## Ease the finale boost in or out (the gate opens: sunrise).
func set_dawn(v: float, seconds := 3.0) -> void:
	create_tween().tween_property(self, "dawn", v, seconds).set_trans(Tween.TRANS_SINE)
