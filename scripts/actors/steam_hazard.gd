class_name SteamHazard
extends Hazard
## A floor vent that vents on a cycle and hurts while the steam column is up.
## The hurt area is synced to the SteamVent's own signals: it starts short when
## the vent opens and grows with the plume, and it drops 0.35 s after the vent
## closes (the last puffs are thin). A hit hurts (one pip) and knocks back,
## it never kills. Origin = the nozzle, on the floor.

@export var column_height := 96.0
@export var column_width := 22.0
@export var cycle_on := 1.4
@export var cycle_off := 2.0
@export var cycle_offset := 0.0
## Seconds for the plume to reach full height after the vent opens.
@export var rise_time := 0.55

var vent: SteamVent

var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()
var _age := 0.0
var _off_timer := 0.0


func _ready() -> void:
	super()
	kill = false
	phase_through = false
	vent = SteamVent.new()
	vent.name = "Vent"
	vent.art_scale = 1
	vent.amount = 18
	vent.lifetime = 1.0
	vent.speed = 60.0
	vent.spread_deg = 7.0
	vent.cycle_on = cycle_on
	vent.cycle_off = cycle_off
	vent.cycle_offset = cycle_offset
	add_child(vent)
	_cs.shape = _shape
	add_child(_cs)
	vent.vent_started.connect(_on_started)
	vent.vent_stopped.connect(_on_stopped)
	if vent.is_venting():
		_on_started()
		_age = fmod(cycle_offset, cycle_on + cycle_off)
	else:
		active = false
	_apply_shape()


func _on_started() -> void:
	active = true
	_age = 0.0
	_off_timer = 0.0


func _on_stopped() -> void:
	_off_timer = 0.35


func is_dangerous() -> bool:
	return active and _shape.size.y > 24.0


func _physics_process(delta: float) -> void:
	if active:
		_age += delta
		if _off_timer > 0.0:
			_off_timer -= delta
			if _off_timer <= 0.0:
				active = false
	_apply_shape()
	super(delta)


func _apply_shape() -> void:
	var k := clampf(_age / rise_time, 0.12, 1.0) if active else 0.12
	var h := column_height * k
	_shape.size = Vector2(column_width, h)
	_cs.position = Vector2(0, -h / 2.0 - 2.0)
