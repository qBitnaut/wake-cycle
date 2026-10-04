extends CanvasLayer
## The cat's inner monologue: a hook only. Monologue.say("...", 3.0) shows one
## line of monogram text near the bottom, above the HUD strip, with a soft
## fade; lines queue. It does nothing until called, and carries no story.
## Registered as the autoload "Monologue".

const FONT := preload("res://assets/fonts/monogram.ttf")
const SIZE := 32
const FADE_IN := 0.5
const FADE_OUT := 0.8
const TINT := Color(0.80, 0.88, 1.0)

var _label: Label
var _queue: Array = []
var _busy := false


func _ready() -> void:
	layer = 20
	_label = Label.new()
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", SIZE)
	_label.add_theme_color_override("font_color", TINT)
	_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.1, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 40.0
	_label.offset_right = -40.0
	_label.offset_bottom = -34.0  # above the 24 px HUD strip
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)


## Show `text` for `duration` seconds (plus the fades). Queued behind a line on screen.
func say(text: String, duration := 3.0) -> void:
	_queue.append([text, duration])
	if not _busy:
		_next()


func is_speaking() -> bool:
	return _busy


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var line: Array = _queue.pop_front()
	_label.text = line[0]
	var tw := create_tween()
	tw.tween_property(_label, "modulate:a", 0.92, FADE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(line[1])
	tw.tween_property(_label, "modulate:a", 0.0, FADE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_next)
