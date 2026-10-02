class_name TitleOverlay
extends CanvasLayer
## Opening card: black fades away to reveal the scene, then a line of text
## fades in, holds and fades out. Starts on ready unless autoplay is off.

signal revealed  ## Black has faded out; the scene is visible.
signal finished  ## Title has faded out; the overlay is idle.

@export_multiline var text := "Find Your Way Out"
@export var autoplay := true
@export var black_hold := 0.6
@export var reveal_time := 3.2
@export var title_delay := 0.5
@export var title_in := 2.2
@export var title_hold := 2.6
@export var title_out := 2.4
## Title cap height as a fraction of the viewport height.
@export_range(0.02, 0.2) var size_ratio := 0.062
## Extra letter spacing as a fraction of the font size.
@export_range(0.0, 0.5) var tracking := 0.12

@onready var _black: ColorRect = $Black
@onready var _title: Label = $Title

var _font: FontVariation


func _ready() -> void:
	_title.text = text
	_title.modulate.a = 0.0
	_black.modulate.a = 1.0
	_font = (_title.get_theme_font("font") as FontVariation).duplicate()
	_title.add_theme_font_override("font", _font)
	get_viewport().size_changed.connect(_fit)
	_fit()
	if autoplay:
		play()


## Runs the full sequence; await play() or listen to finished.
func play() -> void:
	_black.modulate.a = 1.0
	_title.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(black_hold)
	tw.tween_property(_black, "modulate:a", 0.0, reveal_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(revealed.emit)
	tw.tween_interval(title_delay)
	tw.tween_property(_title, "modulate:a", 1.0, title_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(title_hold)
	tw.tween_property(_title, "modulate:a", 0.0, title_out).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(finished.emit)
	await tw.finished


func _fit() -> void:
	var h := get_viewport().get_visible_rect().size.y
	var size := maxi(int(h * size_ratio), 18)
	_title.add_theme_font_size_override("font_size", size)
	_font.spacing_glyph = int(size * tracking)
