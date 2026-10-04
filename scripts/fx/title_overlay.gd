class_name TitleOverlay
extends CanvasLayer
## Opening card: the screen fades up from black, then the title fades in and
## out over the scene. monogram at an integer multiple of its 16 px design size,
## centred, no outline.
##
## Signals: `revealed` when the black is gone, `finished` when the title is out.
## play() runs it (autoplay does on ready); skip() jumps to the end.

signal revealed
signal finished

const FONT := preload("res://assets/fonts/monogram.ttf")

@export var title := "Find Your Way Out"
@export var autoplay := true
## Font size; keep it a multiple of 16 so monogram stays pixel-exact.
## 0 = auto: 32 at 320x180, 64 at 640x360 (16 x 2 x FXScale.whole).
@export_range(0, 128, 16) var font_size := 0
@export var text_color := Color(0.86, 0.91, 1.0)
## Push the title slightly over 1.0 so the 2D glow gives it a faint bloom.
@export_range(1.0, 2.0, 0.05) var text_glow := 1.15
@export var black_hold := 0.6
@export var fade_from_black := 2.2
@export var title_delay := 0.4
@export var title_fade_in := 1.4
@export var title_hold := 2.2
@export var title_fade_out := 1.6

var _black: ColorRect
var _label: Label
var _tween: Tween
var _revealed := false


func _ready() -> void:
	layer = 100
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_label = Label.new()
	_label.text = title
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", font_size if font_size > 0 else 32 * FXScale.whole(self))
	_label.add_theme_color_override("font_color", Color(text_color * text_glow, 1.0))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)
	if autoplay:
		play()


func play() -> void:
	if _tween:
		_tween.kill()
	visible = true
	_revealed = false
	_black.modulate.a = 1.0
	_label.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_interval(black_hold)
	_tween.tween_property(_black, "modulate:a", 0.0, fade_from_black).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_reveal)
	_tween.tween_interval(title_delay)
	_tween.tween_property(_label, "modulate:a", 1.0, title_fade_in).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(title_hold)
	_tween.tween_property(_label, "modulate:a", 0.0, title_fade_out).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_end)


func skip() -> void:
	if _tween:
		_tween.kill()
	_black.modulate.a = 0.0
	_label.modulate.a = 0.0
	_reveal()
	_end()


func _reveal() -> void:
	if not _revealed:
		_revealed = true
		revealed.emit()


func _end() -> void:
	visible = false
	finished.emit()
