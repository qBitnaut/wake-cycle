class_name LaserTurret
extends Node2D
## A wall turret that sweeps a laser along the floor of a corridor. Always
## telegraphed and always dodgeable: it idles, then draws a thin flickering aim
## line for `warn_time` (blinking faster as it arms), then fires the full beam
## for `fire_time`, then cools down. The beam runs `reach` px at `beam_y` above
## the floor: a standing cat is hit, a crouched one slips under, and a dash goes
## through it. The safe window each cycle is the idle and warn time. Phasing
## passes through. Origin = the turret's foot on the floor; `facing` -1 fires
## to the left, +1 to the right.

enum State { IDLE, WARN, FIRE }

const SPRITE := preload("res://assets/art_hd/robots/turret_5.png")
const BEAM_H := 6.0

@export var facing := -1
@export var reach := 288.0
@export var beam_y := 24.0
@export var idle_time := 1.6
@export var warn_time := 1.0
@export var fire_time := 0.5
@export var start_offset := 0.0

var state := State.IDLE
## True while the beam is deadly (audit hook).
var firing := false

var _t := 0.0
var _body: Sprite2D
var _aim: LaserBeam
var _beam: LaserBeam
var _hazard: Hazard


func _ready() -> void:
	z_index = 2
	_body = Sprite2D.new()
	_body.texture = SPRITE
	_body.scale = Vector2(1.5, 1.5)
	_body.flip_h = facing < 0  # the art faces right
	_body.position = Vector2(0, -SPRITE.get_height() * 0.75)
	_body.self_modulate = Color(0.85, 0.85, 0.92)
	add_child(_body)
	_aim = LaserBeam.new()
	_aim.length = reach
	_aim.thickness = 1
	_aim.hdr = 1.0
	_aim.light_energy = 0.4
	_aim.rotation = 0.0 if facing > 0 else PI
	_aim.position = Vector2(0, -beam_y)
	add_child(_aim)
	_beam = LaserBeam.new()
	_beam.length = reach
	_beam.thickness = int(BEAM_H)
	_beam.rotation = _aim.rotation
	_beam.position = _aim.position
	add_child(_beam)
	_hazard = Hazard.new()
	_hazard.kill = false
	_hazard.phase_through = true
	_hazard.active = false
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(reach, BEAM_H + 2.0)
	cs.shape = r
	cs.position = Vector2(facing * reach * 0.5, -beam_y)
	_hazard.add_child(cs)
	add_child(_hazard)
	_t = start_offset
	_aim.set_on(false)
	_beam.set_on(false)


func _process(delta: float) -> void:
	_t += delta
	var cycle := idle_time + warn_time + fire_time
	var u := fmod(_t, cycle)
	if u < idle_time:
		state = State.IDLE
	elif u < idle_time + warn_time:
		state = State.WARN
	else:
		state = State.FIRE
	firing = state == State.FIRE
	_hazard.active = firing
	_beam.set_on(firing)
	var blink := false
	if state == State.WARN:
		var k := (u - idle_time) / warn_time
		blink = int(_t * lerpf(6.0, 28.0, k)) % 2 == 0
	_aim.set_on(blink)
	_body.self_modulate = Color(1.7, 0.8, 0.75) if state != State.IDLE else Color(0.85, 0.85, 0.92)
