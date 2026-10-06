class_name ElectricFloor
extends KitHazard
## Electrified floor panels on a timed cycle. WARN: the panels flash amber and spit
## sparks with a crackle. LIVE: blue-white arcs jump above them and hurt (a dashing
## cat passes through the arcs). Origin = the middle of the panel row, at floor level.

@export var width_tiles := 3
@export var arc_height := 22.0

var _panel: Array[AnimatedSprite2D] = []
var _light: PointLight2D
var _hum: LoopSfx
var _arcs: Array = []
var _arc_t := 0.0


func _init() -> void:
	idle_time = 1.4
	warn_time = 0.8
	live_time = 1.0


func _build() -> void:
	phase_through = true
	var w := width_tiles * 32.0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(w - 4.0, arc_height)
	cs.shape = sh
	cs.position = Vector2(0, -arc_height * 0.5)
	add_child(cs)
	for i in width_tiles:
		var s := KitArt.make_sprite("electric_floor", "panel", 1.0)
		s.position = Vector2(-w * 0.5 + 16.0 + i * 32.0, 0)
		s.play("off")
		add_child(s)
		_panel.append(s)
	_light = PointLight2D.new()
	_light.texture = preload("res://assets/fx/light_soft.png")
	_light.texture_scale = 1.4
	_light.color = Color(0.3, 0.8, 1.0)
	_light.energy = 0.0
	_light.position = Vector2(0, -10)
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	add_child(_light)
	_hum = KitSfx.loop(self, "electric_arc", 300.0)
	if _hum:
		_hum.active = false
	z_index = 2


func _on_phase(p: Phase, silent: bool) -> void:
	var anim: String = ["off", "warn", "live"][p]
	for s in _panel:
		s.play(anim)
	if _hum:
		_hum.active = p == Phase.LIVE
	if silent:
		return
	if p == Phase.WARN:
		KitSfx.play(self, "electric_warn")
	elif p == Phase.LIVE:
		KitSfx.play(self, "laser_zap", -8.0, 0.7)


func _step(delta: float) -> void:
	_arc_t -= delta
	if _arc_t <= 0.0 and phase != Phase.IDLE:
		_arc_t = 0.05
		_arcs.clear()
		var w := width_tiles * 32.0
		var count := width_tiles * (2 if phase == Phase.LIVE else 1)
		for i in count:
			var x0 := randf_range(-w * 0.5 + 4.0, w * 0.5 - 4.0)
			var pts := PackedVector2Array([Vector2(x0, -6.0)])
			var h := arc_height * (1.0 if phase == Phase.LIVE else 0.35) * randf_range(0.6, 1.0)
			var x := x0
			for k in 4:
				x += randf_range(-7.0, 7.0)
				pts.append(Vector2(clampf(x, -w * 0.5, w * 0.5), -6.0 - h * (k + 1) / 4.0))
			_arcs.append(pts)
	elif phase == Phase.IDLE:
		_arcs.clear()
	_light.energy = (1.2 + randf() * 0.6) if phase == Phase.LIVE else (0.4 * absf(sin(clock * 30.0)) if phase == Phase.WARN else 0.0)
	_light.color = Color(0.3, 0.8, 1.0) if phase == Phase.LIVE else Color(1.0, 0.6, 0.2)


func _draw() -> void:
	for pts in _arcs:
		var live := phase == Phase.LIVE
		var col := Color(0.6, 1.8, 2.2, 1.0) if live else Color(2.0, 1.2, 0.4, 0.9)
		draw_polyline(pts, Color(col.r * 0.5, col.g * 0.7, col.b, 0.35), 3.0 if live else 2.0)
		draw_polyline(pts, col, 1.0)
