class_name ConduitEvent
extends Area2D
## The sparking broken power conduit in Room 3: a torn floor panel and a frayed
## cable that spit sparks. The cat cannot avoid it (the tunnel is two tiles
## high and the trigger spans the whole panel) and it never hurts. Walking over
## it is the story beat that grants the shockwave: the augments flare, the
## screen flashes, GameState.unlock_shockwave() is called and the cat is held
## for a moment. Origin = bottom-centre of the panel (the floor line).
##
## It fires once. If the shockwave is already unlocked (a reload after the
## beat) it only sparks.

signal fired

@export var size := Vector2(96, 64)
## Seconds the cat is held while the augments drink the charge.
@export var hold_time := 0.8
## Where the cable hangs from, relative to the origin (the ceiling over the panel).
@export var cable_anchor := Vector2(0, -64)

var has_fired := false
var _cable: SparksFX
var _floor: SparksFX
var _t := randf() * 4.0
var _arc := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	cs.position = Vector2(0, -size.y / 2.0)
	add_child(cs)
	_cable = SparksFX.new()
	_cable.name = "CableSparks"
	_cable.position = cable_anchor
	_cable.cable_length = absf(cable_anchor.y) - 30.0
	_cable.interval_min = 0.5
	_cable.interval_max = 1.6
	_cable.flash_energy = 2.2
	add_child(_cable)
	_floor = SparksFX.new()
	_floor.name = "PanelSparks"
	_floor.position = Vector2(0, -3)
	_floor.cable_length = 0.0
	_floor.amount = 14
	_floor.interval_min = 0.7
	_floor.interval_max = 2.0
	_floor.flash_energy = 1.4
	add_child(_floor)
	z_index = 1


func _physics_process(_delta: float) -> void:
	if has_fired or GameState.shockwave_unlocked:
		return
	for b in get_overlapping_bodies():
		if b is Cat and not (b as Cat).dead:
			_fire(b)
			return


func _fire(cat: Cat) -> void:
	has_fired = true
	GameState.unlock_shockwave()
	_cable.burst(1.5)
	_floor.burst(1.5)
	_arc = 1.0
	Sfx.play(self, "power_up")
	Sfx.play(self, "shockwave_burst")
	var aug := cat.get_node_or_null("Sprite/Augments") as CatAugments
	if aug:
		aug.flare(1.6)
	ScreenShake.shake_at(self, 0.7, 0.5)
	_flash()
	if hold_time > 0.0:
		cat.set_can_move(false)
		get_tree().create_timer(hold_time).timeout.connect(func():
			if is_instance_valid(cat) and not cat.dead:
				cat.set_can_move(true))
	fired.emit()


## A white-blue full-screen flash that fades out (above the world, below the subtitles).
func _flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	var rect := ColorRect.new()
	rect.color = Color(0.85, 0.95, 1.0, 0.9)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.0, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_callback(layer.queue_free)


func _process(delta: float) -> void:
	_t += delta
	_arc = maxf(_arc - delta * 1.5, 0.0)
	queue_redraw()


func _draw() -> void:
	# A torn floor panel: dark plate with a jagged crack, hot copper and a flickering arc.
	var w := size.x
	draw_rect(Rect2(-w / 2.0, -4, w, 4), Color("141a2c"))
	draw_rect(Rect2(-w / 2.0 + 2, -4, w - 4, 2), Color("2a4658"))
	var crack := PackedVector2Array([
		Vector2(-w / 2.0 + 6, -4), Vector2(-w * 0.28, -3), Vector2(-w * 0.12, -4), Vector2(0, -2),
		Vector2(w * 0.14, -4), Vector2(w * 0.3, -3), Vector2(w / 2.0 - 6, -4)])
	draw_polyline(crack, Color("05060d"), 2.0)
	draw_rect(Rect2(-5, -6, 10, 3), Color(0.75, 0.45, 0.2))
	var live := 0.5 + 0.5 * sin(_t * 23.0) * sin(_t * 7.0)
	var c := Color(FXPalette.SPARK, 0.6 + 0.4 * live) if not has_fired else Color(0.7, 0.95, 1.0, 0.5 + 0.5 * _arc)
	var y := -6.0
	var pts := PackedVector2Array()
	for i in 9:
		pts.append(Vector2(-w * 0.3 + i * w * 0.075, y - 4.0 * absf(sin(_t * 31.0 + i * 1.7)) - 2.0 * _arc))
	draw_polyline(pts, c, 1.0)
