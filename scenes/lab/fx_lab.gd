## FX lab showcase. Keys:
##   1 / 2      camera to the hero corner / the machinery corner
##   Left/Right pan the camera (watch the parallax through the windows)
##   L          lightning now          K  shockwave now      P  pulse the pads
##   G          2D glow on/off
##   T          replay the title card
## On the web, URL parameters set the start state for screenshots:
##   ?station=2&notitle=1&strike=1
extends Node2D

const STATIONS := [Vector2(160, 90), Vector2(488, 90)]
const PAN_SPEED := 90.0

@export var shockwave_every := 3.2
@export var shockwave_pos := Vector2(462, 162)
@export var shockwave_radius := 44.0

@onready var _cam: Camera2D = $Camera
@onready var _cat: Sprite2D = $Cat
@onready var _rig: LightingRig = $LightingRig
@onready var _title: TitleOverlay = $TitleOverlay
@onready var _pads: Node2D = $Pads

var _t := 0.0
var _cat_t := 0.0
var _shock_t := 0.0
var _pad_i := 0
var _fps_t := 0.0
var _cam_target := Vector2.ZERO
var _cam_pos := Vector2.ZERO   # unrounded; the camera itself sits on whole pixels


func _ready() -> void:
	_cam_target = STATIONS[0]
	_cam_pos = _cam_target
	_cam.position = _cam_target
	var params := _url_params()
	if params.has("station"):
		go_station(int(params["station"]) - 1)
	if params.get("notitle", "") == "1":
		_title.skip()
	if params.get("strike", "") == "1":
		get_tree().create_timer(1.0).timeout.connect(func(): $Lightning.strike())
	$Lightning.thunder.connect(func(s: float): print("LAB thunder %.2f" % s))
	_title.revealed.connect(func(): print("LAB title revealed"))
	_title.finished.connect(func(): print("LAB title finished"))
	print("LAB_READY renderer=%s" % RenderingServer.get_current_rendering_method())


func _url_params() -> Dictionary:
	var out := {}
	if not OS.has_feature("web"):
		return out
	var q: Variant = JavaScriptBridge.eval("window.location.search", true)
	if typeof(q) != TYPE_STRING:
		return out
	for pair in String(q).trim_prefix("?").split("&", false):
		var kv := pair.split("=")
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _process(delta: float) -> void:
	_t += delta
	# Cat idle: 10 frames at 8 fps.
	_cat_t += delta
	_cat.frame = int(_cat_t * 8.0) % _cat.hframes
	# Shockwave every few seconds by the pads; pads answer one after another.
	_shock_t += delta
	if _shock_t >= shockwave_every:
		_shock_t = 0.0
		ShockwaveFX.spawn(self, shockwave_pos, shockwave_radius, FXPalette.IMPACT, 0.35)
		_pad_i = 0
		_pulse_next_pad()
	# Camera.
	var pan := Input.get_axis("ui_left", "ui_right")
	if pan != 0.0:
		_cam_target.x = clampf(_cam_target.x + pan * PAN_SPEED * delta, 160.0, 488.0)
	_cam_pos = _cam_pos.lerp(_cam_target, 1.0 - exp(-delta * 6.0))
	_cam.position = _cam_pos.round()
	_fps_t += delta
	if _fps_t >= 2.0:
		_fps_t = 0.0
		print("LAB_FPS %d" % Engine.get_frames_per_second())


## Jump the camera to station i (0 hero, 1 machinery). For scripted shots.
func go_station(i: int) -> void:
	_cam_target = STATIONS[clampi(i, 0, STATIONS.size() - 1)]
	_cam_pos = _cam_target
	_cam.position = _cam_target


func _pulse_next_pad() -> void:
	if _pad_i >= _pads.get_child_count():
		return
	(_pads.get_child(_pad_i) as PadFX).pulse()
	_pad_i += 1
	get_tree().create_timer(0.09).timeout.connect(_pulse_next_pad)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_1:
			_cam_target = STATIONS[0]
		KEY_2:
			_cam_target = STATIONS[1]
		KEY_L:
			$Lightning.strike()
		KEY_K:
			ShockwaveFX.spawn(self, shockwave_pos, shockwave_radius, FXPalette.IMPACT, 0.35)
		KEY_P:
			_pad_i = 0
			_pulse_next_pad()
		KEY_G:
			_rig.glow_enabled = not _rig.glow_enabled
			print("LAB glow=%s" % _rig.glow_enabled)
		KEY_T:
			_title.play()
