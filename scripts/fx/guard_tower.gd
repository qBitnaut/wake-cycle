class_name GuardTower
extends Node2D
## A guard tower with a searchlight that sweeps back and forth: scenery for the
## perimeter. A lattice on four legs, a glazed cabin with a warm lamp, a roof,
## and a faint additive beam rocking over the ground. It does not see the cat
## (the SearchDrone does the hunting). Origin = the foot of the tower.

const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const LEG := Color("2a4658")
const LEG_LIT := Color("5b7280")
const INK := Color("141a2c")
const BEAM_COLOR := Color(1.0, 0.93, 0.72)

@export var tower_height := 200.0
@export var sweep_deg := 38.0
@export var sweep_period := 5.0
@export var beam_length := 300.0
@export var beam_half := 7.0
@export var phase := 0.0

var _t := 0.0
var _beam: Polygon2D
var _pool: PointLight2D


func _ready() -> void:
	_t = phase
	z_index = -3
	_beam = Polygon2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_beam.material = mat
	_beam.position = Vector2(0, -tower_height + 6.0)
	add_child(_beam)
	var lamp := PointLight2D.new()
	lamp.texture = LIGHT_TEX
	lamp.texture_scale = 1.8
	lamp.color = Color(1.0, 0.72, 0.42)
	lamp.energy = 0.8
	lamp.position = Vector2(0, -tower_height + 14.0)
	lamp.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(lamp)
	_pool = PointLight2D.new()
	_pool.texture = LIGHT_TEX
	_pool.texture_scale = 1.3
	_pool.color = BEAM_COLOR
	_pool.energy = 0.6
	_pool.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(_pool)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var a := deg_to_rad(sweep_deg) * sin(_t * TAU / sweep_period)
	var ha := deg_to_rad(beam_half)
	var l := Vector2(sin(a - ha), cos(a - ha)) * beam_length
	var r := Vector2(sin(a + ha), cos(a + ha)) * beam_length
	_beam.polygon = PackedVector2Array([Vector2(0, 0), l, r])
	_beam.vertex_colors = PackedColorArray([Color(BEAM_COLOR, 0.22), Color(BEAM_COLOR, 0.03), Color(BEAM_COLOR, 0.03)])
	var hit := minf((tower_height - 6.0) / maxf(cos(a), 0.2), beam_length)
	_pool.position = Vector2(0, -tower_height + 6.0) + Vector2(sin(a), cos(a)) * hit


func _draw() -> void:
	var h := tower_height
	# Four legs (two seen, braced), cross bracing, the platform.
	for sx in [-18.0, 18.0]:
		draw_line(Vector2(sx * 1.4, 0), Vector2(sx * 0.6, -h + 34.0), LEG, 4.0)
		draw_line(Vector2(sx * 1.4, 0), Vector2(sx * 0.6, -h + 34.0), LEG_LIT, 1.0)
	var steps := 5
	for i in steps:
		var y0 := -(h - 34.0) * float(i) / steps
		var y1 := -(h - 34.0) * float(i + 1) / steps
		var x0 := lerpf(25.0, 11.0, float(i) / steps)
		var x1 := lerpf(25.0, 11.0, float(i + 1) / steps)
		draw_line(Vector2(-x0, y0), Vector2(x1, y1), LEG, 2.0)
		draw_line(Vector2(x0, y0), Vector2(-x1, y1), LEG, 2.0)
	draw_rect(Rect2(-30, -h + 30, 60, 6), INK)
	draw_rect(Rect2(-29, -h + 31, 58, 3), LEG_LIT)
	# Cabin.
	draw_rect(Rect2(-24, -h + 2, 48, 28), INK)
	draw_rect(Rect2(-22, -h + 4, 44, 24), Color("1c2c3b"))
	draw_rect(Rect2(-18, -h + 8, 36, 14), Color(1.0, 0.72, 0.42, 0.85))
	draw_rect(Rect2(-18, -h + 8, 36, 2), Color(1.0, 0.9, 0.6, 0.9))
	draw_rect(Rect2(-2, -h + 8, 4, 14), INK)
	# Roof and the lamp housing.
	draw_colored_polygon(PackedVector2Array([Vector2(-30, -h + 2), Vector2(0, -h - 14), Vector2(30, -h + 2)]), INK)
	draw_colored_polygon(PackedVector2Array([Vector2(-27, -h + 1), Vector2(0, -h - 11), Vector2(27, -h + 1)]), Color("354655"))
	draw_rect(Rect2(-6, -h + 2, 12, 8), Color("536a74"))
