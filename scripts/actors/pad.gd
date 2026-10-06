class_name PowerPad
extends Area2D
## Enhancement pad: step on it to gain a timed nano power (or, for the debug /
## story stand-in, to unlock the shockwave). Re-usable after a cooldown.

signal activated(power: int)

const UNLOCK_SHOCKWAVE := 99

@export_enum("Surge:1", "Spring:2", "Phase:3", "Impact:4", "Unlock Shockwave:99") var power := 1
@export var duration := 10.0
@export var cooldown := 3.0

var _cd := 0.0
var _fx: PadFX


func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	body_entered.connect(_on_body)
	# The look is the FX kit's PadFX, tinted by the pad's power. FXPalette and
	# NanoPalette carry the same colours (NanoPalette points at FXPalette).
	_fx = PadFX.new()
	_fx.name = "PadFX"
	if power == UNLOCK_SHOCKWAVE:
		_fx.set_color(NanoPalette.SHOCKWAVE)  # not one of the four powers
		_fx.use_custom_color = true
		_fx.custom_color = NanoPalette.SHOCKWAVE
	else:
		_fx.set_kind((power - 1) as FXPalette.Pad)  # Power 1..4 -> Pad.SURGE..IMPACT
	add_child(_fx)


func _color() -> Color:
	return NanoPalette.SHOCKWAVE if power == UNLOCK_SHOCKWAVE else NanoPalette.color_of(power)


func _on_body(body: Node) -> void:
	if _cd > 0.0 or not body is Cat:
		return
	if power == UNLOCK_SHOCKWAVE:
		if GameState.shockwave_unlocked:
			return
		GameState.shockwave_unlocked = true
		_cd = 1e9
	else:
		GameState.grant_power(power, duration)
		_cd = cooldown
	Sfx.play(self, "power_up" if power == UNLOCK_SHOCKWAVE else ["pad_surge", "pad_spring", "pad_phase", "pad_impact"][clampi(power - 1, 0, 3)])
	_fx.pulse()
	_fx.set_enabled(false)
	activated.emit(power)


func _process(delta: float) -> void:
	if _cd > 0.0 and _cd < 1e8:
		_cd -= delta
		if _cd <= 0.0:
			_fx.set_enabled(true)
			for b in get_overlapping_bodies():
				_on_body(b)
