@tool
class_name LaserBeam
extends Node2D
## A laser beam as a reusable piece: an unshaded HDR strip (body plus a hot
## core line, pushed to about 1.6 so the 2D glow blooms it) and a red
## PointLight2D that spills on whatever the beam crosses.
##
## The origin is the beam's start. It runs `length` px along +X, or straight up
## when `vertical` is set. Red means hostile (palette.md), so the colours come
## from FXPalette.LASER and LASER_CORE.
##
##     var beam := LaserBeam.new()
##     beam.length = 96.0
##     beam.vertical = true
##     add_child(beam)
##     beam.set_on(false)      # beam off: strip and light both hidden

## Beam length in world px.
@export var length := 96.0:
	set(v):
		length = v
		_sync()
@export var vertical := false:
	set(v):
		vertical = v
		_sync()
## Body thickness in px; the core is two px (one for a thin beam).
@export_range(1, 12) var thickness := 5:
	set(v):
		thickness = v
		_sync()
## HDR multiplier for the strip. 1.6 blooms; 1.0 is flat.
@export_range(1.0, 3.0, 0.05) var hdr := 1.6
@export_range(0.0, 4.0, 0.05) var light_energy := 1.3
@export var on := true:
	set(v):
		on = v
		_sync()
## One-pixel sideways shimmer, for fences.
@export var jitter := false

var _strip: Node2D
var _light: PointLight2D
var _t := 0.0

const LIGHT_TEX := preload("res://assets/fx/light_soft.png")


func _ready() -> void:
	_strip = Node2D.new()
	_strip.name = "Strip"
	var um := CanvasItemMaterial.new()
	um.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_strip.material = um
	_strip.draw.connect(_draw_strip)
	add_child(_strip)
	_light = PointLight2D.new()
	_light.name = "Light"
	_light.texture = LIGHT_TEX
	_light.color = Color(1.0, 0.32, 0.24)
	_light.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(_light)
	_sync()


func set_on(v: bool) -> void:
	on = v


func _process(delta: float) -> void:
	if _strip == null or not on:
		return
	_t += delta
	if jitter:
		var j := float(int(_t * 30.0) % 2)
		_strip.position = Vector2(j, 0) if vertical else Vector2(0, j)


func _draw_strip() -> void:
	var t := float(thickness)
	var core := 2.0 if thickness > 2 else 1.0
	var body: Rect2
	var core_r: Rect2
	if vertical:
		body = Rect2(-t * 0.5, -length, t, length)
		core_r = Rect2(-core * 0.5, -length, core, length)
	else:
		body = Rect2(0, -t * 0.5, length, t)
		core_r = Rect2(0, -core * 0.5, length, core)
	_strip.draw_rect(body, Color(FXPalette.LASER * hdr, 1.0))
	_strip.draw_rect(core_r, Color(FXPalette.LASER_CORE * hdr, 1.0))


func _sync() -> void:
	if _strip == null:
		return
	_strip.visible = on
	_strip.queue_redraw()
	_light.enabled = on
	_light.energy = light_energy
	# light_soft is a 128 px radial; stretch it along the beam.
	if vertical:
		_light.position = Vector2(0, -length * 0.5)
		_light.rotation = PI * 0.5
	else:
		_light.position = Vector2(length * 0.5, 0)
		_light.rotation = 0.0
	_light.scale = Vector2(maxf(length, 16.0) / 80.0, 0.9)
