class_name VentHazard
extends KitHazard
## Steam or flame vent on a telegraphed cycle: the SteamHazard of the rooms,
## generalised. WARN: a pilot puff / flickering pilot flame and a hiss. LIVE: a column
## of steam (existing SteamVent particles) or a flame jet rises and hurts; it grows
## over `rise_time`. Origin = the nozzle's mouth; rotate the node for a ceiling or wall
## vent. SteamHazard (unchanged) is still what the rooms use.

enum Kind { STEAM, FLAME }

@export var kind: Kind = Kind.STEAM
@export var column_height := 88.0
@export var column_width := 22.0
@export var rise_time := 0.35

var vent: SteamVent
var column := 0.0

var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()
var _light: PointLight2D
var _seed := randf() * 10.0


func _init() -> void:
	idle_time = 1.6
	warn_time = 0.8
	live_time = 1.3


func _build() -> void:
	phase_through = false
	var aid := "vent_steam" if kind == Kind.STEAM else "vent_flame"
	add_child(KitArt.make_sprite(aid, "nozzle", 1.0))
	_cs.shape = _shape
	add_child(_cs)
	if kind == Kind.STEAM:
		vent = SteamVent.new()
		vent.name = "Vent"
		vent.art_scale = 1
		vent.amount = 18
		vent.lifetime = 1.0
		vent.speed = 60.0
		vent.spread_deg = 7.0
		vent.active = false
		add_child(vent)
	else:
		_light = PointLight2D.new()
		_light.texture = preload("res://assets/fx/light_soft.png")
		_light.color = Color(1.0, 0.55, 0.2)
		_light.energy = 0.0
		_light.texture_scale = 1.2
		_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
		add_child(_light)
	z_index = 2
	_size_column(0.0)


func _size_column(h: float) -> void:
	column = h
	_shape.size = Vector2(column_width, maxf(h, 2.0))
	_cs.position = Vector2(0, -2.0 - maxf(h, 2.0) * 0.5)


func _on_phase(p: Phase, silent: bool) -> void:
	if vent:
		vent.active = p == Phase.LIVE
	if silent:
		return
	if p == Phase.WARN:
		KitSfx.play(self, "steam_hiss" if kind == Kind.STEAM else "spike_warn")
	elif p == Phase.LIVE and kind == Kind.FLAME:
		KitSfx.play(self, "flame_burst")


func _step(_delta: float) -> void:
	if phase == Phase.LIVE:
		_size_column(column_height * clampf(phase_time / rise_time, 0.12, 1.0))
	else:
		_size_column(0.0)
	if _light:
		_light.position = Vector2(0, -column * 0.5)
		_light.energy = 1.6 if phase == Phase.LIVE else (0.3 + 0.3 * sin(clock * 25.0) if phase == Phase.WARN else 0.0)


func _draw() -> void:
	if phase == Phase.WARN:
		# Pilot: a few flickering puffs / a small flame.
		for i in 3:
			var y := -4.0 - fposmod(clock * 18.0 + i * 5.0, 14.0)
			var x := sin(clock * 9.0 + i * 2.0 + _seed) * 3.0
			var c := Color(1.3, 1.4, 1.6, 0.5) if kind == Kind.STEAM else Color(2.0, 1.2, 0.4, 0.9)
			draw_circle(Vector2(x, y), 2.0 if kind == Kind.STEAM else 1.5, c)
	if kind == Kind.FLAME and phase == Phase.LIVE and column > 4.0:
		var h := column
		var w := column_width * 0.5
		for layer in 3:
			var k := 1.0 - layer * 0.28
			var flick := sin(clock * 38.0 + layer * 1.7 + _seed) * 2.0
			var cols := [Color(1.8, 0.45, 0.12, 0.85), Color(2.0, 1.1, 0.25, 0.9), Color(2.2, 1.9, 1.2, 0.95)]
			draw_colored_polygon(PackedVector2Array([
				Vector2(-w * k, -2), Vector2(-w * 0.6 * k + flick, -h * 0.55 * k),
				Vector2(flick * 1.5, -h * k), Vector2(w * 0.6 * k + flick, -h * 0.55 * k), Vector2(w * k, -2)]), cols[layer])
