class_name Credits
extends Node2D
## The end: the title card, then the credits rolling over the sleeping cat in
## its patch of sun, then "The End" and back to the start.
##
## Steps: TITLE ("Wake Cycle" on warm white, where the Home ending faded to)
## -> REVEAL (the white lifts off the sunlit room) -> ROLL (the lines from
## res://data/credits.json scroll up the right half; holding any movement
## speeds them up) -> END ("The End"; any movement, or a pause, leaves) ->
## LEAVE (fade to black, the game is marked complete, Room 1 starts fresh).
##
## Credits lines: "# Heading", "plain line", "" (a gap). Edit the file.
## The room is 320x180 art shown at 2x (tools/art/home_art.py).
## Web debug hook (tools/audit/web_home.mjs): window.__wake every physics frame.

signal left

enum Step { TITLE, REVEAL, ROLL, END, LEAVE }

const FONT := preload("res://assets/fonts/monogram.ttf")
const DATA := "res://data/credits.json"
const ART := "res://assets/art_hd/home/"
const WARM_WHITE := Color(1.0, 0.96, 0.86)
const TITLE_INK := Color(0.36, 0.22, 0.20)
const HEADING := Color(1.0, 0.86, 0.58)
const BODY := Color(1.0, 0.95, 0.86)
const SHADOW := Color(0.20, 0.10, 0.12, 0.85)
const COLUMN_X := 470.0     # the roll's centre, view px
const COLUMN_W := 300.0
const BODY_SIZE := 16
const HEAD_SIZE := 32
const GAP := 14.0

@export var scroll_speed := 18.0
@export var fast_mult := 5.0
@export var end_hold := 8.0
## Where the game starts again (empty: the project's main scene).
@export_file("*.tscn") var start_scene := ""

var step := Step.TITLE
var roll_done := false

var _ui: CanvasLayer
var _white: ColorRect
var _title: Label
var _roll: Control
var _roll_h := 0.0
var _end: Label
var _black: ColorRect
var _cat: Node2D
var _aug: CatAugments
var _t := 0.0
var _end_t := 0.0


func _ready() -> void:
	_build_room()
	_build_ui()
	AudioDirector.play_music("home")  # the ending theme plays on through the credits
	_play_title()


# ---- the room -------------------------------------------------------------------

func _build_room() -> void:
	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.zoom = Vector2(2, 2)
	cam.position = Vector2(160, 90)
	add_child(cam)
	cam.make_current()
	var rig := LightingRig.new()
	rig.name = "LightingRig"
	rig.night_tint = Color(1, 1, 1)
	rig.moon_enabled = false
	rig.glow_intensity = 0.7
	rig.vignette = 0.22
	add_child(rig)
	var room := Sprite2D.new()
	room.name = "Room"
	room.texture = load(ART + "credits_room.png")
	room.centered = false
	room.light_mask = 0
	add_child(room)
	var patch := Sprite2D.new()
	patch.name = "SunPatch"
	patch.texture = load(ART + "credits_light.png")
	patch.centered = false
	patch.modulate = Color(0.5, 0.37, 0.19)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	patch.material = add
	add_child(patch)
	var shaft := MoonShaft.new()
	shaft.name = "Beam"
	shaft.position = Vector2(64, -8)
	shaft.angle = 26.0
	shaft.length = 182.0
	shaft.top_width = 70.0
	shaft.bottom_width = 110.0
	shaft.color = Color(1.0, 0.82, 0.5)
	shaft.ray_intensity = 0.16
	shaft.floor_glow = 0.0
	shaft.light_energy = 0.35
	shaft.dust_amount = 36
	shaft.dust_color = Color(1.6, 1.4, 1.0)
	add_child(shaft)
	var back := Sprite2D.new()
	back.name = "CushionBack"
	back.texture = load(ART + "cushion_back.png")
	back.position = Vector2(120, 164)
	add_child(back)
	_cat = Node2D.new()
	_cat.name = "SleepyCat"
	_cat.position = Vector2(120, 165)  # sunk into the cushion, as in the house
	add_child(_cat)
	var spr := AnimatedSprite2D.new()
	spr.name = "Sprite"
	spr.sprite_frames = CatFrames.build()
	spr.position = Vector2(0, -15)
	spr.play("sleep1")
	_cat.add_child(spr)
	_aug = CatAugments.attach(_cat, true)
	_aug.follow_game_state = false
	_aug.set_sleeping(true, 0.05)
	var front := Sprite2D.new()
	front.name = "CushionFront"
	front.texture = load(ART + "cushion_front.png")
	front.position = Vector2(120, 164)
	add_child(front)


func _process(delta: float) -> void:
	_t += delta
	# The sleeping cat breathes (the back rises a pixel, feet planted).
	var spr := _cat.get_node("Sprite") as AnimatedSprite2D
	var s := 1.0 + 0.035 * (0.5 + 0.5 * sin(TAU * _t / 4.4))
	spr.scale = Vector2(1.0, s)
	spr.position.y = -15.0 * s
	match step:
		Step.ROLL:
			_roll_step(delta)
		Step.END:
			_end_t += delta
			if _end_t > 1.2 and _any_move_pressed() or _end_t > end_hold:
				_leave()


func _physics_process(_delta: float) -> void:
	if OS.has_feature("web"):
		var d := {
			"f": Engine.get_physics_frames(), "scene": scene_file_path, "step": int(step),
			"title": _title.modulate.a, "white": _white.modulate.a, "end": _end.modulate.a,
			"roll": _roll.position.y, "rollDone": roll_done, "black": _black.modulate.a,
			"augE": _aug.emitter_energy() if _aug else 0.0,
			"music": AudioDirector.music_db(),
		}
		d["loops"] = LoopSfx.census_cached(get_tree())
		d["audio"] = AudioDirector.web_state()
		JavaScriptBridge.eval("window.__wake=" + JSON.stringify(d))


static func _any_move_pressed() -> bool:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "dash"]:
		if Input.is_action_just_pressed(a):
			return true
	return false


static func _any_move_held() -> bool:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "dash"]:
		if Input.is_action_pressed(a):
			return true
	return false


# ---- the text ----------------------------------------------------------------------

func _label(text: String, size: int, color: Color, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", SHADOW)
		l.add_theme_constant_override("shadow_offset_x", size / 16)
		l.add_theme_constant_override("shadow_offset_y", size / 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "Ui"
	_ui.layer = 100  # over the vignette (90): the white and the title stay clean
	add_child(_ui)
	_roll = Control.new()
	_roll.name = "Roll"
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_roll)
	var y := 0.0
	for line in _lines():
		var t := String(line)
		if t.strip_edges() == "":
			y += GAP
			continue
		var head := t.begins_with("#")
		var size := HEAD_SIZE if head else BODY_SIZE
		var l := _label(t.trim_prefix("#").strip_edges(), size, HEADING if head else BODY)
		var h := float(size) * (1.05 if head else 1.15)
		l.position = Vector2(COLUMN_X - COLUMN_W * 0.5, y)
		l.size = Vector2(COLUMN_W, h)
		_roll.add_child(l)
		y += h
	_roll_h = y
	_roll.position = Vector2(0, 360.0 + 8.0)
	_roll.visible = false
	_end = _label("The End", HEAD_SIZE, HEADING)
	_end.position = Vector2(COLUMN_X - COLUMN_W * 0.5, 180.0 - HEAD_SIZE * 0.5)
	_end.size = Vector2(COLUMN_W, HEAD_SIZE)
	_end.modulate.a = 0.0
	_ui.add_child(_end)
	_white = ColorRect.new()
	_white.name = "WarmWhite"
	_white.color = WARM_WHITE
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_white)
	_title = _label("Wake Cycle", 64, TITLE_INK, false)
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.modulate.a = 0.0
	_ui.add_child(_title)
	_black = ColorRect.new()
	_black.name = "Black"
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	_ui.add_child(_black)


func _lines() -> Array:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		push_warning("Credits: %s missing" % DATA)
		return ["# Wake Cycle", "", "# Thanks for playing."]
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.get("lines") is Array:
		return parsed["lines"]
	push_warning("Credits: %s has no lines" % DATA)
	return []


# ---- the steps -----------------------------------------------------------------------

func _play_title() -> void:
	step = Step.TITLE
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(_title, "modulate:a", 1.0, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(3.6)
	tw.tween_property(_title, "modulate:a", 0.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.4)
	tw.tween_callback(func(): step = Step.REVEAL)
	tw.tween_property(_white, "modulate:a", 0.0, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		_roll.visible = true
		step = Step.ROLL)


func _roll_step(delta: float) -> void:
	var speed := scroll_speed * (fast_mult if _any_move_held() else 1.0)
	_roll.position.y -= speed * delta
	# The last line ("Thanks for playing.") stops in the middle of the view.
	var stop_y := 180.0 - (_roll_h - HEAD_SIZE * 0.5)
	if _roll.position.y <= stop_y:
		_roll.position.y = stop_y
		_finish_roll()


func _finish_roll() -> void:
	if roll_done:
		return
	roll_done = true
	step = Step.LEAVE  # nothing to do while the last line holds
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(_roll, "modulate:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_end, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_end_t = 0.0
		step = Step.END)


func _leave() -> void:
	step = Step.LEAVE
	SaveSystem.mark_complete()
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 1.0, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	AudioDirector.stop_music(2.2)
	tw.tween_interval(0.5)
	tw.tween_callback(_restart)


## Back to the beginning: a fresh game, the intro (the cat asleep in the dark).
func _restart() -> void:
	left.emit()
	AudioDirector.stop_music(0.0)
	GameState.new_game()
	Monologue.reset()
	Room1.intro_done = false
	RoomTransition.arriving = false
	var path := start_scene if start_scene != "" else String(ProjectSettings.get_setting("application/run/main_scene"))
	get_tree().change_scene_to_file(path)
