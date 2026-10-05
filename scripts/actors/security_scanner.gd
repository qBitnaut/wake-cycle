class_name SecurityScanner
extends Node2D
## The Master Gate's security scanner: an arch the cat walks into, with three
## relay lamps on its header and a screen above. It does nothing until all
## three relays are lit; then it sweeps a beam over the cat and shows the
## verdict. Origin = the floor line, centred on the scan zone.

signal cat_entered
signal scan_finished

enum Mode { OFFLINE, READY, SCANNING, ACCEPTED }

const FONT := preload("res://assets/fonts/monogram.ttf")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const INK := Color("10121f")
const STEEL := Color("354655")
const STEEL_LIT := Color("536a74")

@export var zone := Vector2(96, 80)

var mode := Mode.OFFLINE
var relays_lit := 0
var cat_inside := false
## The text on the screen, and its colour: audit hooks.
var screen_lines := PackedStringArray()
var screen_color := FXPalette.SODIUM
## Where the scan beam is, -1..1 across the zone (audit hook).
var beam_pos := -1.0

var _t := 0.0
var _beam_a := 0.0
var _flash_until := 0.0
var _light: PointLight2D
var _lamp_flash := [0.0, 0.0, 0.0]


func _ready() -> void:
	z_index = 2
	var a := Area2D.new()
	a.name = "Zone"
	a.collision_layer = 0
	a.collision_mask = 2
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = zone
	cs.shape = r
	cs.position = Vector2(0, -zone.y / 2.0)
	a.add_child(cs)
	add_child(a)
	a.body_entered.connect(_on_enter)
	a.body_exited.connect(func(b): if b is Cat: cat_inside = false)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 1.6
	_light.color = Color(0.7, 0.95, 1.0)
	_light.energy = 0.0
	_light.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(_light)
	_refresh()


func _on_enter(b: Node) -> void:
	if not b is Cat:
		return
	cat_inside = true
	cat_entered.emit()
	if mode == Mode.OFFLINE:
		screen_lines = PackedStringArray(["ACCESS DENIED", "POWER %d/3" % relays_lit])
		screen_color = FXPalette.LASER
		_flash_until = _t + 2.2
		Sfx.play(self, "hurt", -14.0, 0.5)


func set_relays(n: int) -> void:
	if n > relays_lit and n >= 1:
		_lamp_flash[n - 1] = 1.0
	relays_lit = n
	if mode == Mode.OFFLINE and n >= 3:
		mode = Mode.READY
	_refresh()


func _refresh() -> void:
	match mode:
		Mode.OFFLINE:
			screen_lines = PackedStringArray(["SECURITY SCANNER", "POWER %d/3" % relays_lit])
			screen_color = FXPalette.SODIUM
		Mode.READY:
			screen_lines = PackedStringArray(["POWER OK", "STEP INTO THE SCANNER"])
			screen_color = FXPalette.INDICATOR
		Mode.SCANNING:
			screen_lines = PackedStringArray(["SCANNING...", "HOLD STILL"])
			screen_color = Color(0.7, 0.95, 1.0)
		Mode.ACCEPTED:
			screen_lines = PackedStringArray(["SUPERVISOR CREDENTIAL ACCEPTED"])
			screen_color = FXPalette.INDICATOR


## Sweep the beam over the zone for `seconds`, then accept. Await it.
func begin_scan(seconds := 3.2) -> void:
	mode = Mode.SCANNING
	_refresh()
	var hum := LoopSfx.attach(self, preload("res://assets/audio/sfx8bit/laser_hum_loop.ogg"), -10.0, 1.9, 420.0)
	var tw := create_tween()
	# Left to right, back, and a last slow pass: a sweep that reads as thorough.
	tw.tween_property(self, "beam_pos", 1.0, seconds * 0.4).from(-1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "beam_pos", -1.0, seconds * 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "beam_pos", 0.0, seconds * 0.25).set_trans(Tween.TRANS_SINE)
	await tw.finished
	if is_instance_valid(hum):
		hum.retire()
	accept()


func accept() -> void:
	mode = Mode.ACCEPTED
	_refresh()
	Sfx.play(self, "checkpoint", -4.0, 1.0)
	_flash_until = _t + 1e9
	scan_finished.emit()


## Already accepted on load (the gate is open).
func set_accepted() -> void:
	relays_lit = 3
	mode = Mode.ACCEPTED
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	for i in 3:
		_lamp_flash[i] = maxf(_lamp_flash[i] - delta, 0.0)
	if mode == Mode.OFFLINE and _flash_until > 0.0 and _t > _flash_until:
		_flash_until = 0.0
		_refresh()
	var on := mode == Mode.SCANNING
	_light.energy = lerpf(_light.energy, 1.4 if on else 0.0, 0.2)
	_light.position = Vector2(beam_pos * zone.x * 0.5, -zone.y * 0.5)
	queue_redraw()


func _draw() -> void:
	var w := zone.x * 0.5 + 12.0
	var h := 112.0
	# Posts and header.
	for sx in [-w, w - 12.0]:
		draw_rect(Rect2(sx - 1, -h, 14, h), INK)
		draw_rect(Rect2(sx, -h, 12, h), Color("2a4658"))
		draw_rect(Rect2(sx, -h, 3, h), STEEL_LIT)
		for k in 5:
			draw_rect(Rect2(sx + 4, -h + 14 + k * 20, 4, 8), Color(FXPalette.INDICATOR, 0.5))
	draw_rect(Rect2(-w - 3, -h - 18, w * 2.0 + 6, 20), INK)
	draw_rect(Rect2(-w - 2, -h - 17, w * 2.0 + 4, 18), STEEL)
	draw_rect(Rect2(-w - 2, -h - 17, w * 2.0 + 4, 2), STEEL_LIT)
	# Three relay lamps on the header.
	for i in 3:
		var lx := (i - 1) * 34.0
		var on := i < relays_lit
		var f: float = _lamp_flash[i]
		var c := FXPalette.INDICATOR if on else Color("3a2410")
		var hdr := 1.0 + f * 1.5 if on else 1.0
		draw_rect(Rect2(lx - 11, -h - 14, 22, 12), INK)
		draw_rect(Rect2(lx - 9, -h - 12, 18, 8), Color(c.r * hdr, c.g * hdr, c.b * hdr, 1.0))
		if on:
			draw_circle(Vector2(lx, -h - 8), 14.0 + 14.0 * f, Color(FXPalette.INDICATOR, 0.10 + 0.25 * f))
	# Screen above the arch.
	var sw := 288.0
	var sy := -h - 66.0
	draw_rect(Rect2(-sw / 2.0 - 3, sy - 3, sw + 6, 46), INK)
	draw_rect(Rect2(-sw / 2.0, sy, sw, 40), STEEL)
	draw_rect(Rect2(-sw / 2.0 + 3, sy + 3, sw - 6, 34), Color("070b12"))
	draw_rect(Rect2(-6, sy + 40, 12, 14), STEEL)
	var col := screen_color
	var blink := mode == Mode.OFFLINE and _flash_until > 0.0 and int(_t * 6.0) % 2 == 0
	var tc := Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, 0.35 if blink else 1.0)
	var y := sy + 19.0 if screen_lines.size() == 1 else sy + 15.0
	for l in screen_lines:
		draw_string(FONT, Vector2(-sw / 2.0, y), l, HORIZONTAL_ALIGNMENT_CENTER, sw, 16, tc)
		y += 15.0
	# The beam: a bright vertical band sweeping the zone, with a soft wash.
	if mode == Mode.SCANNING:
		var bx := beam_pos * zone.x * 0.5
		draw_rect(Rect2(bx - 14, -h, 28, h), Color(0.6, 0.9, 1.0, 0.14))
		draw_rect(Rect2(bx - 3, -h, 6, h), Color(1.6, 2.0, 2.2, 0.9))
		draw_rect(Rect2(bx - 1, -h, 2, h), Color(2.4, 2.6, 2.6, 1.0))
