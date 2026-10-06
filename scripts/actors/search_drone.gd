class_name SearchDrone
extends Node2D
## A security drone with a searchlight. When the cat crosses its `trigger_x`
## the drone swings in from `start_x` and sweeps along the yard at `speed`
## until `end_x`, where it gives up and flies off. Its beam rocks side to side.
## Seen (inside the cone, with a clear line from the lamp, for `seen_time`)
## means the alarm: the cat is sent back to the last checkpoint. Cover (a solid
## roof over the cat) hides it. Not a hit and not death: no health is lost.
## Being ahead of it is the whole point, so it is slower than a Surge run and
## barely slower than a plain one.

signal triggered
signal seen

@export var trigger_x := 0.0
@export var start_x := 0.0
@export var end_x := 0.0
@export var speed := 120.0
@export var height := 160.0         ## lamp height above the floor line
@export var half_angle := 14.0      ## degrees, half the cone's opening
@export var sway := 12.0            ## degrees the beam rocks either side of straight down
@export var sway_period := 2.4
@export var seen_time := 0.30
@export var beam_length := 230.0

enum State { IDLE, SWEEP, LEAVING, GONE }

## B' size: hand-drawn at 2/3 of the ansimuz drone (tools/art/repixel.py), 36x34.
const DRONE := preload("res://assets/art_hd/robots/drone_3_23.png")
## The beam leaves the drone here (its apex: what it sees from); the body is
## placed so the bottom of its face plate, under the lamps, sits on it.
const LAMP := Vector2(0, 10)
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const BEAM_COLOR := Color(1.0, 0.93, 0.72)
const HUM_RANGE := 480.0   ## px: silent beyond this distance from the cat

var state := State.IDLE
var seen_meter := 0.0
var alarmed := false
var cat: Cat
## Audit hook: true while the cat is currently lit.
var lit := false

## The drone's whirr: a looping sound that follows the drone, fades with the distance to
## the cat, and ends when the drone does (see LoopSfx).
var hum: LoopSfx

var _t := 0.0
var _body: Sprite2D
var _beam: Polygon2D
var _pool: PointLight2D
var _eye: Polygon2D
var _flash: ColorRect


func _ready() -> void:
	z_index = 4
	_body = Sprite2D.new()
	_body.texture = DRONE
	_body.position = Vector2(0, 2)
	_body.self_modulate = Color(0.85, 0.85, 0.9)
	add_child(_body)
	_eye = Polygon2D.new()
	_eye.polygon = PackedVector2Array([Vector2(-4, 4), Vector2(4, 4), Vector2(4, 6), Vector2(-4, 6)])
	_eye.color = Color(FXPalette.LASER * 1.5, 1.0)
	_body.add_child(_eye)
	_eye.visible = false  # the art already carries red lenses; the glow lifts them
	_beam = Polygon2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_beam.material = mat
	add_child(_beam)
	_pool = PointLight2D.new()
	_pool.texture = LIGHT_TEX
	_pool.texture_scale = 1.1
	_pool.energy = 0.0
	_pool.color = BEAM_COLOR
	_pool.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(_pool)
	global_position = Vector2(start_x, height_y())
	visible = false


func height_y() -> float:
	return 320.0 - height


func _physics_process(delta: float) -> void:
	if cat == null:
		cat = get_tree().get_first_node_in_group("player") as Cat
		return
	_t += delta
	match state:
		State.IDLE:
			if cat.global_position.x >= trigger_x:
				state = State.SWEEP
				visible = true
				global_position = Vector2(start_x, height_y())
				triggered.emit()
				hum = LoopSfx.attach(self, Sfx.stream("drone_hover"), Sfx.level_db("drone_hover") + 2.0, 1.0, HUM_RANGE)
		State.SWEEP:
			global_position.x += speed * delta
			global_position.y = height_y() + sin(_t * 2.0) * 3.0
			if global_position.x >= end_x:
				state = State.LEAVING
		State.LEAVING:
			global_position.x += speed * 1.6 * delta
			global_position.y -= 90.0 * delta
			if global_position.y < -80.0:
				state = State.GONE
				visible = false
				if hum:
					hum.retire()
	_update_beam()
	_update_seen(delta)


func beam_angle() -> float:
	return deg_to_rad(sway) * sin(_t * TAU / sway_period)


func _cone_points() -> PackedVector2Array:
	var a := beam_angle()
	var ha := deg_to_rad(half_angle)
	var l := Vector2(sin(a - ha), cos(a - ha)) * beam_length
	var r := Vector2(sin(a + ha), cos(a + ha)) * beam_length
	return PackedVector2Array([LAMP, l, r])


func _update_beam() -> void:
	var on := state == State.SWEEP and not alarmed
	_beam.visible = on
	_pool.energy = 0.8 if on else 0.0
	if not on:
		return
	var pts := _cone_points()
	_beam.polygon = pts
	_beam.vertex_colors = PackedColorArray([
		Color(BEAM_COLOR, 0.30), Color(BEAM_COLOR, 0.05), Color(BEAM_COLOR, 0.05)])
	# The lit spot where the beam centre meets the floor.
	var a := beam_angle()
	var floor_dist := height / cos(a)
	_pool.position = Vector2(sin(a), cos(a)) * floor_dist


## True when the cat's body is in the cone and nothing solid is between.
func sees_cat() -> bool:
	if state != State.SWEEP or cat == null or cat.dead:
		return false
	var p := cat.global_position + Vector2(0, -10.0 if cat.crouched else -13.0)
	var pts := _cone_points()
	var local := p - global_position
	# Widen by the cat's half width so a shoulder in the beam counts.
	var inside := Geometry2D.is_point_in_polygon(local, pts)
	if not inside:
		var e1 := Geometry2D.get_closest_point_to_segment(local, pts[0], pts[1])
		var e2 := Geometry2D.get_closest_point_to_segment(local, pts[0], pts[2])
		inside = local.distance_to(e1) < 8.0 or local.distance_to(e2) < 8.0
	if not inside:
		return false
	var q := PhysicsRayQueryParameters2D.create(global_position + LAMP, p, 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _update_seen(delta: float) -> void:
	if alarmed:
		return
	lit = sees_cat()
	if lit:
		seen_meter += delta
	else:
		seen_meter = maxf(seen_meter - delta * 2.0, 0.0)
	_body.self_modulate = Color(0.85, 0.85, 0.9).lerp(Color(1.8, 0.9, 0.8), clampf(seen_meter / seen_time, 0.0, 1.0))
	if seen_meter >= seen_time:
		_alarm()


func _alarm() -> void:
	alarmed = true
	seen.emit()
	Sfx.play(self, "turret_charge")
	cat.set_can_move(false)
	cat.velocity.x = 0.0
	_flash = ColorRect.new()
	_flash.color = Color(FXPalette.LASER, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(_flash)
	add_child(layer)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.45, 0.12)
	tw.tween_property(_flash, "color:a", 0.15, 0.2)
	tw.tween_property(_flash, "color:a", 0.5, 0.15)
	tw.tween_interval(0.2)
	tw.tween_callback(func(): SaveSystem.respawn())
