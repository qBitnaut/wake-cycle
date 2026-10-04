class_name CatAugments
extends Node2D
## The cat's nanotech augments: a thin ear implant with an emitter at the
## tip, slim plates along the spine with glowing seams, a tail band with an
## emitter, and a faint ring round one eye. Subtle and sleek; the emitters
## pulse in the active power colour.
##
##     var aug := CatAugments.attach(cat)        # hidden until reveal()
##     aug.reveal(1.2)                            # materialise, flash, settle
##     aug.set_power(FXPalette.SPRING)            # emitters go green
##     aug.clear_power()                          # neutral soft blue-green
##     aug.flare()                                # burst (shockwave, dash)
##
## The art is one overlay sheet per cat sheet (assets/sprites/cat/augments,
## drawn by tools/art/cat_augments.py from per-frame anchors), so every
## piece is pixel-placed and clipped to the silhouette on every frame of
## every animation, including flips. Two CatOverlay sprites draw it: metal
## (lit) and emitters (unshaded, additive, blooming).
##
## With follow_game_state on, the emitters track GameState.power_changed.
## With auto_flare on, it flares on the cat's shockwave signal and when the
## cat starts a dash (Cat.is_phasing()).

signal revealed

const SHEETS := "res://assets/sprites/cat/augments/aug_%s.png"
const METAL_SHADER := preload("res://shaders/cat_augment.gdshader")
const GLOW_SHADER := preload("res://shaders/cat_augment_glow.gdshader")

## Emitter colour and level with no power active: a soft blue-green.
@export var idle_color := Color(0.13, 0.65, 0.82)
@export_range(0.0, 2.0, 0.01) var idle_energy := 0.75
## Emitter level while a power is active.
@export_range(0.0, 2.0, 0.01) var power_energy := 1.3
@export var follow_game_state := true
@export var auto_flare := true

var metal: CatOverlay
var glow: CatOverlay
var shown := false

var _color := Color(0.13, 0.65, 0.82)
var _energy := 0.75
var _reveal := 0.0
var _flash := 0.0
var _flare := 0.0
var _tween: Tween
var _color_tween: Tween
var _cat: Node
var _was_phasing := false


## Add augments to `cat` (a Cat, or anything with a `sprite` or a "Sprite"
## child). Hidden until reveal(), unless `show_now` (e.g. after a reload,
## once the story has already given the cat its augments).
static func attach(cat: Node, show_now := false) -> CatAugments:
	var spr: AnimatedSprite2D = cat.get("sprite") if cat.get("sprite") is AnimatedSprite2D else cat.get_node_or_null("Sprite")
	for c in spr.get_children():
		if c is CatAugments:
			if show_now:
				c.set_shown(true)
			return c
	var a := CatAugments.new()
	a.name = "Augments"
	a._cat = cat
	spr.add_child(a)
	a.set_shown(show_now)
	return a


func _ready() -> void:
	var src := get_parent() as AnimatedSprite2D
	if src == null:
		push_warning("CatAugments must be a child of the cat's AnimatedSprite2D")
		return
	if _cat == null:
		_cat = src.get_parent()
	_color = idle_color
	_energy = idle_energy
	var frames := CatOverlay.frames_from(SHEETS, 2)
	var mm := ShaderMaterial.new()
	mm.shader = METAL_SHADER
	metal = CatOverlay.make(src, frames, mm, "Metal")
	add_child(metal)
	var gm := ShaderMaterial.new()
	gm.shader = GLOW_SHADER
	glow = CatOverlay.make(src, frames, gm, "Emitters")
	add_child(glow)
	if auto_flare and _cat and _cat.has_signal("shockwave"):
		_cat.connect("shockwave", func(_p, _r, _s): flare())
	if follow_game_state:
		var gs := get_node_or_null("/root/GameState")
		if gs and gs.has_signal("power_changed"):
			gs.power_changed.connect(_on_power)
			if gs.power != NanoPalette.Power.NONE:
				_color = NanoPalette.color_of(gs.power)
				_energy = power_energy
	_push()


## Materialise: the pieces print outward from their emitters with a bright
## edge, the emitters flash, then settle into the gentle pulse.
func reveal(duration := 1.2) -> void:
	shown = true
	if _tween:
		_tween.kill()
	_reveal = 0.0
	_flash = 0.0
	_tween = create_tween()
	_tween.tween_method(_set_reveal, 0.0, 1.0, duration * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_set_flash.bind(1.0))
	_tween.tween_method(_set_flash, 1.0, 0.0, duration * 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(revealed.emit)


## Show or hide instantly (no animation).
func set_shown(on: bool) -> void:
	shown = on
	if _tween:
		_tween.kill()
	_reveal = 1.0 if on else 0.0
	_flash = 0.0
	_push()


## Emitters take on a power's colour (FXPalette.SURGE, SPRING, PHASE, IMPACT).
func set_power(color: Color) -> void:
	_tween_color(color, power_energy)
	_flare = maxf(_flare, 0.6)


## Back to the neutral soft blue-green idle glow.
func clear_power() -> void:
	_tween_color(idle_color, idle_energy)


## A burst through the emitters and metal edges, e.g. on shockwave or dash.
func flare(strength := 1.0) -> void:
	_flare = maxf(_flare, strength)


func _process(delta: float) -> void:
	if _cat and auto_flare and _cat.has_method("is_phasing"):
		var ph: bool = _cat.is_phasing()
		if ph and not _was_phasing:
			flare(0.8)
		_was_phasing = ph
	if _flare > 0.0:
		_flare = maxf(_flare - delta * 3.0, 0.0)
		_push()


func _on_power(power: int, _duration: float) -> void:
	if power == NanoPalette.Power.NONE:
		clear_power()
	else:
		set_power(NanoPalette.color_of(power))


func _tween_color(c: Color, e: float) -> void:
	if _color_tween:
		_color_tween.kill()
	_color_tween = create_tween().set_parallel(true)
	_color_tween.tween_method(_set_color, _color, c, 0.35)
	_color_tween.tween_method(_set_energy, _energy, e, 0.35)


func _set_color(v: Color) -> void:
	_color = v
	_push()


func _set_energy(v: float) -> void:
	_energy = v
	_push()


func _set_reveal(v: float) -> void:
	_reveal = v
	_push()


func _set_flash(v: float) -> void:
	_flash = v
	_push()


func _push() -> void:
	if metal == null:
		return
	var on := _reveal > 0.0
	metal.active = on
	glow.active = on
	var mm := metal.material as ShaderMaterial
	mm.set_shader_parameter("reveal", _reveal)
	var gm := glow.material as ShaderMaterial
	gm.set_shader_parameter("reveal", _reveal)
	gm.set_shader_parameter("power_color", _color)
	gm.set_shader_parameter("energy", _energy)
	gm.set_shader_parameter("flash", _flash)
	gm.set_shader_parameter("flare", _flare)
