class_name FallingDebris
extends Node2D
## A cracked ceiling that drops a rock when the cat passes under it. Origin = the
## crack on the ceiling. ARMED -> the cat is under it (inside `trigger_half` px
## sideways, within `trigger_depth` px down) -> WARN (the crack shudders and dust
## sifts: at least 0.4 s) -> the rock falls -> `respawn_time` s later it re-arms
## (0 = once only). The rock hurts one pip and breaks on the floor.

enum Mode { ARMED, WARN, COOL }

@export var trigger_half := 30.0
@export var trigger_depth := 280.0
@export var warn_time := 0.7
@export var respawn_time := 6.0

var mode := Mode.ARMED
var drops := 0
var last_warn := 0.0

var _t := 0.0
var _crack: AnimatedSprite2D
var _m_t := 0.0


func _ready() -> void:
	add_to_group("kit_hazard")
	_crack = KitArt.make_sprite("falling_debris", "crack", 1.0)
	add_child(_crack)
	z_index = 2


func is_warning() -> bool:
	return mode == Mode.WARN


func warn_seconds() -> float:
	return maxf(warn_time, 0.4)


func _physics_process(delta: float) -> void:
	_t += delta
	_m_t += delta
	match mode:
		Mode.ARMED:
			if _cat_under():
				mode = Mode.WARN
				_m_t = 0.0
				KitSfx.play(self, "rock_fall", -8.0, 1.4)
		Mode.WARN:
			_crack.position.x = roundf(sin(_t * 55.0))
			if int(_m_t * 20.0) % 2 == 0:
				Debris.burst(get_parent(), global_position + Vector2(randf_range(-10, 10), 12), Color(0.45, 0.5, 0.55), 1)
			if _m_t >= warn_seconds():
				last_warn = _m_t
				_drop()
				mode = Mode.COOL
				_m_t = 0.0
				_crack.position.x = 0.0
		Mode.COOL:
			if respawn_time > 0.0 and _m_t >= respawn_time:
				mode = Mode.ARMED


func _cat_under() -> bool:
	var c := get_tree().get_first_node_in_group("player") as Cat
	if c == null or c.dead:
		return false
	var d := c.global_position - global_position
	return absf(d.x) <= trigger_half and d.y > 16.0 and d.y <= trigger_depth


func _drop() -> void:
	drops += 1
	var rock := FallingRock.new()
	get_parent().add_child(rock)
	rock.global_position = global_position + Vector2(0, 14)
