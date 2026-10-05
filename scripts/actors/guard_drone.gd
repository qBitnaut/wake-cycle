class_name GuardDrone
extends Hazard
## A guard drone hovering back and forth in a corridor. Touching it costs a hit
## (like a laser); a dashing (PHASE) cat passes straight through it. It never
## leaves its patrol, so it can be timed, but the corridor is built so that a
## dash is the clean way. Origin = the centre of the patrol; it travels
## +-`range_x` and bobs +-`bob`.

const DRONE := preload("res://assets/art_hd/robots/drone_1.png")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")

@export var range_x := 96.0
@export var bob := 28.0
@export var speed := 1.0          ## patrol cycles per ~5 s
@export var phase_offset := 0.0

var _t := 0.0
var _origin := Vector2.ZERO
var _body: Sprite2D
var _glow: PointLight2D


func _ready() -> void:
	super()
	kill = false
	phase_through = true
	_origin = position
	_t = phase_offset
	z_index = 4
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(36, 26)
	cs.shape = r
	add_child(cs)
	_body = Sprite2D.new()
	_body.texture = DRONE
	_body.self_modulate = Color(0.85, 0.85, 0.92)
	add_child(_body)
	_glow = PointLight2D.new()
	_glow.texture = LIGHT_TEX
	_glow.texture_scale = 0.9
	_glow.energy = 0.8
	_glow.color = Color(1.0, 0.35, 0.28)
	_glow.range_item_cull_mask = LightingRig.MASK_WORLD
	_glow.position = Vector2(0, 8)
	add_child(_glow)


func _physics_process(delta: float) -> void:
	_t += delta * speed
	position = _origin + Vector2(sin(_t * 1.3) * range_x, sin(_t * 2.1) * bob)
	_body.flip_h = cos(_t * 1.3) < 0.0
	super(delta)
