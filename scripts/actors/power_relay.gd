class_name PowerRelay
extends Area2D
## A power relay for the Master Gate: a steel console the cat lights by
## stepping up to it. It latches (saved with the checkpoint snapshot as a
## collected id) and tells the finale which one it was. Where it stands is the
## puzzle: every relay is behind a different power. Origin = the floor line.

signal activated(index: int)

const FONT := preload("res://assets/fonts/monogram.ttf")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")

@export var index := 1
@export var size := Vector2(44, 56)

var lit := false
## True when it loaded already lit (a checkpoint after it was done).
var restored := false

var _id := ""
var _t := 0.0
var _flash := 0.0
var _light: PointLight2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	cs.position = Vector2(0, -size.y / 2.0)
	add_child(cs)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 1.6
	_light.color = FXPalette.INDICATOR
	_light.energy = 0.0
	_light.position = Vector2(0, -26)
	_light.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(_light)
	_id = "r4_relay%d" % index
	if GameState.is_collected(_id):
		lit = true
		restored = true
		_light.energy = 1.0
	z_index = 1


func _physics_process(_delta: float) -> void:
	if lit:
		return
	for b in get_overlapping_bodies():
		if b is Cat and not (b as Cat).dead:
			_activate()
			return


func _activate() -> void:
	lit = true
	_flash = 1.0
	GameState.mark_collected(_id)
	Sfx.play(self, "power_up", -4.0, 1.0 + 0.12 * index)
	Debris.burst(get_parent(), global_position + Vector2(0, -30), FXPalette.INDICATOR, 12)
	_light.energy = 1.6
	activated.emit(index)


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta * 1.2, 0.0)
	if lit:
		_light.energy = 1.0 + 0.6 * _flash
	queue_redraw()


func _draw() -> void:
	var steel := Color("5b7280")
	var ink := Color("10121f")
	var c := FXPalette.INDICATOR if lit else FXPalette.SODIUM
	var glow := 1.0 + _flash
	# Pedestal, console head and the lamp.
	draw_rect(Rect2(-14, -36, 28, 36), ink)
	draw_rect(Rect2(-13, -35, 26, 34), Color("2a4658"))
	draw_rect(Rect2(-13, -35, 26, 2), steel)
	draw_rect(Rect2(-16, -44, 32, 12), ink)
	draw_rect(Rect2(-15, -43, 30, 10), Color("354655"))
	draw_rect(Rect2(-11, -41, 22, 6), Color("141a2c"))
	var lamp := Color(c.r * glow, c.g * glow, c.b * glow, 1.0)
	var pulse := 1.0 if lit else 0.55 + 0.45 * sin(_t * 5.0)
	draw_rect(Rect2(-9, -40, 18, 4), Color(lamp, pulse))
	draw_string(FONT, Vector2(-16, -48), "R%d" % index, HORIZONTAL_ALIGNMENT_CENTER, 32.0, 16, Color(c, 0.9))
	if not lit:
		# A bobbing arrow above: step up to it.
		var b := sin(_t * 4.0) * 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(-5, -64 + b), Vector2(5, -64 + b), Vector2(0, -57 + b)]), Color(c, 0.8))
	else:
		draw_arc(Vector2(0, -38), 14.0 + 10.0 * _flash, 0.0, TAU, 24, Color(lamp, 0.5 * (0.3 + _flash)), 2.0)
