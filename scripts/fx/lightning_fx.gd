class_name LightningFX
extends Node
## Occasional lightning: a double flash on the night tint (CanvasModulate), a
## bright DirectionalLight2D that throws window shadows into the room, the
## exterior backdrop flaring, and thunder `thunder_delay` seconds later.
##
## There is no thunder sound yet: connect `thunder` to an AudioStreamPlayer.

signal flashed(strength: float)
signal thunder(strength: float)

@export var rig: LightingRig
@export var backdrop: NightBackdrop
## Extra canvas items whose ShaderMaterial has a `flash` uniform (window rain).
@export var flash_targets: Array[CanvasItem] = []
@export var auto := true
@export var interval_min := 6.0
@export var interval_max := 14.0
@export var thunder_delay_min := 0.6
@export var thunder_delay_max := 2.2
@export var flash_color: Color = FXPalette.LIGHTNING
@export_range(0.0, 8.0, 0.1) var light_energy := 2.2
## Degrees from straight down, like LightingRig.moon_angle.
@export_range(-80.0, 80.0, 0.5) var light_angle := -28.0
@export var light_shadows := true

var _light: DirectionalLight2D
var _timer := 0.0
var _next := 3.0
var _tween: Tween
var _base_tint := Color.WHITE
var _level := 0.0


func _ready() -> void:
	_light = DirectionalLight2D.new()
	_light.name = "LightningLight"
	_light.color = flash_color
	_light.energy = 0.0
	_light.enabled = false
	_light.rotation = deg_to_rad(-light_angle)
	_light.shadow_enabled = light_shadows
	_light.shadow_filter = Light2D.SHADOW_FILTER_NONE
	_light.range_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	_light.shadow_item_cull_mask = LightingRig.MASK_WORLD | LightingRig.MASK_MOTES
	_light.max_distance = LightingRig.shadow_reach(self)
	add_child(_light)
	_next = randf_range(2.0, interval_min)


func _process(delta: float) -> void:
	if not auto:
		return
	_timer += delta
	if _timer >= _next:
		_timer = 0.0
		_next = randf_range(interval_min, interval_max)
		strike()


## Fire one strike now. `strength` 0..1 scales brightness and thunder.
func strike(strength := 1.0) -> void:
	var cm := rig.get_canvas_modulate() if rig else null
	if cm and (_tween == null or not _tween.is_running()):
		_base_tint = cm.color
	if _tween:
		_tween.kill()
	_tween = create_tween()
	# Flicker: quick flash, a dip, a second stronger flash, slow decay.
	_tween.tween_method(_set_level, 0.0, 0.6 * strength, 0.04)
	_tween.tween_method(_set_level, 0.6 * strength, 0.1 * strength, 0.07)
	_tween.tween_method(_set_level, 0.1 * strength, 1.0 * strength, 0.05)
	_tween.tween_method(_set_level, 1.0 * strength, 0.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	flashed.emit(strength)
	var delay := randf_range(thunder_delay_min, thunder_delay_max)
	get_tree().create_timer(delay).timeout.connect(func(): thunder.emit(strength))


func _set_level(v: float) -> void:
	_level = v
	_light.enabled = v > 0.01
	_light.energy = light_energy * v
	if rig:
		var cm := rig.get_canvas_modulate()
		cm.color = _base_tint.lerp(flash_color, clampf(v * 0.55, 0.0, 1.0))
	if backdrop:
		backdrop.set_flash(v)
	for t in flash_targets:
		if t and t.material is ShaderMaterial:
			(t.material as ShaderMaterial).set_shader_parameter("flash", v)
