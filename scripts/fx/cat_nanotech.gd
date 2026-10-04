class_name CatNanotech
extends Node2D
## The goo transformation on the cat: glossy black goo rising from the feet,
## circuit veins racing up to the eyes, then the goo soaking in.
##
##     var nano := CatNanotech.attach(cat.sprite)
##     create_tween().tween_property(nano, "goo_level", 1.0, 3.0)
##
## Two CatOverlay sprites mirror the cat's frame: GooCoat (lit,
## shaders/cat_nanotech.gdshader) and GooGlow (unshaded and additive,
## shaders/cat_nanotech_glow.gdshader). Both read the cat's nano map
## (assets/fx/cat_nano, from tools/art/cat_anchors.py), which carries every
## frame's height, silhouette and vein network, so the effect fits every
## animation frame. Values above 1 bloom through the LightingRig glow.
##
## Everything is driven by the properties below, so a tween, an
## AnimationPlayer or TransformSequence can play it. With all of them at 0
## the overlays are hidden and cost nothing.

const NANO_SHEETS := "res://assets/fx/cat_nano/nano_%s.png"
const COAT_SHADER := preload("res://shaders/cat_nanotech.gdshader")
const GLOW_SHADER := preload("res://shaders/cat_nanotech_glow.gdshader")

## 0 = no goo, 1 = the goo covers the cat to the ear tips.
@export_range(0.0, 1.0, 0.001) var goo_level := 0.0:
	set(v):
		goo_level = v
		_push()
## 0 = no veins, 1 = every vein lit and the eyes glowing.
@export_range(0.0, 1.0, 0.001) var vein_progress := 0.0:
	set(v):
		vein_progress = v
		_push()
## 0 = goo on the skin, 1 = soaked in: the normal-looking tabby again.
@export_range(0.0, 1.0, 0.001) var absorb := 0.0:
	set(v):
		absorb = v
		_push()
## Overall surge of veins, eyes and skin (the pulse; the last flicker).
@export_range(0.0, 4.0, 0.01) var flash := 0.0:
	set(v):
		flash = v
		_push()
## Side branches glow vein_color; the trunk from the feet to the eyes
## glows vein_color_alt (and the eyes eye_color).
@export var vein_color: Color = FXPalette.NANO_BLUE:
	set(v):
		vein_color = v
		_push()
@export var vein_color_alt: Color = FXPalette.NANO_GREEN:
	set(v):
		vein_color_alt = v
		_push()
@export var eye_color: Color = FXPalette.NANO_GREEN:
	set(v):
		eye_color = v
		_push()
## Brightness of the pixel veins. Keep near 1 on their own; lower it when
## NanoHD draws the smooth HD veins on top, so these read as the traces
## embedded in the goo under the glow.
@export_range(0.0, 2.0, 0.01) var vein_energy := 1.15:
	set(v):
		vein_energy = v
		_push()

var coat: CatOverlay
var glow: CatOverlay


## Add a CatNanotech to the cat's sprite (or return the one already there).
static func attach(cat_sprite: AnimatedSprite2D) -> CatNanotech:
	for c in cat_sprite.get_children():
		if c is CatNanotech:
			return c
	var n := CatNanotech.new()
	n.name = "Nanotech"
	cat_sprite.add_child(n)
	return n


func _ready() -> void:
	var src := get_parent() as AnimatedSprite2D
	if src == null:
		push_warning("CatNanotech must be a child of the cat's AnimatedSprite2D")
		return
	var frames := CatOverlay.frames_from(NANO_SHEETS)
	var cm := ShaderMaterial.new()
	cm.shader = COAT_SHADER
	coat = CatOverlay.make(src, frames, cm, "GooCoat")
	add_child(coat)
	var gm := ShaderMaterial.new()
	gm.shader = GLOW_SHADER
	glow = CatOverlay.make(src, frames, gm, "GooGlow")
	add_child(glow)
	_push()


## Tint the veins and eyes with one colour (a pad's), or restore the
## nanotech blue-green with reset_colors().
func set_vein_tint(c: Color) -> void:
	vein_color = c
	vein_color_alt = c.lightened(0.25)
	eye_color = c


func reset_colors() -> void:
	vein_color = FXPalette.NANO_BLUE
	vein_color_alt = FXPalette.NANO_GREEN
	eye_color = FXPalette.NANO_GREEN


## Back to the plain cat.
func clear() -> void:
	goo_level = 0.0
	vein_progress = 0.0
	absorb = 0.0
	flash = 0.0


func _push() -> void:
	if coat == null:
		return
	var on_coat := goo_level > 0.0 and absorb < 1.0
	var on_glow := on_coat or vein_progress > 0.0 or flash > 0.0
	coat.active = on_coat
	glow.active = on_glow
	var cm := coat.material as ShaderMaterial
	cm.set_shader_parameter("goo_level", goo_level)
	cm.set_shader_parameter("absorb", absorb)
	var gm := glow.material as ShaderMaterial
	gm.set_shader_parameter("goo_level", goo_level)
	gm.set_shader_parameter("vein_progress", vein_progress)
	gm.set_shader_parameter("absorb", absorb)
	gm.set_shader_parameter("flash", flash)
	gm.set_shader_parameter("vein_color", vein_color)
	gm.set_shader_parameter("vein_color_alt", vein_color_alt)
	gm.set_shader_parameter("eye_color", eye_color)
	gm.set_shader_parameter("energy", vein_energy)
