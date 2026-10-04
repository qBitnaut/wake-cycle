extends Control
## Secret Agent style status strip: one slim bar along the bottom of the
## 640x360 view. Health pips, SCORE, the active power with its timer, the
## shockwave flag, keys and C-A-T letters. monogram at 16 px (its design size).

const FONT := preload("res://assets/fonts/monogram.ttf")
const SIZE := 16
const STRIP_H := 24
const INK := Color("10121f")
const EDGE := Color("354655")
const EDGE_LIT := Color("536a74")
const TEXT := Color("c3d8cf")
const SHADOW := Color("0a0b14")
## Health is warm (the cat's), spent pips fall back to the rust ink.
const PIP_FULL := Color("e8a25d")
const PIP_HI := Color("fbd9a0")
const PIP_EMPTY := Color("2d163a")
const LETTER_ON := Color("ffd23f")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for sig in [GameState.health_changed, GameState.score_changed, GameState.keys_changed,
			GameState.letters_changed, GameState.power_changed, GameState.shockwave_unlock_changed]:
		sig.connect(func(_a = null, _b = null): queue_redraw())


func _process(_delta: float) -> void:
	if GameState.power != NanoPalette.Power.NONE:
		queue_redraw()


func _text(pos: Vector2, s: String, c := TEXT) -> void:
	draw_string(FONT, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, SHADOW)
	draw_string(FONT, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, c)


func _draw() -> void:
	var w := size.x
	var top := size.y - STRIP_H
	var base := top + 16.0  # text baseline
	# Strip: ink fill, steel rim on top.
	draw_rect(Rect2(0, top, w, STRIP_H), Color(INK, 0.94))
	draw_rect(Rect2(0, top, w, 1), EDGE_LIT)
	draw_rect(Rect2(0, top + 1, w, 1), EDGE)
	# Health pips (3 hits; the 4th is fatal).
	for i in GameState.MAX_HEALTH:
		var r := Rect2(10 + i * 16, top + 7, 12, 10)
		draw_rect(Rect2(r.position - Vector2.ONE, r.size + Vector2(2, 2)), Color.BLACK)
		draw_rect(r, PIP_FULL if i < GameState.health else PIP_EMPTY)
		if i < GameState.health:
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), PIP_HI)
	_text(Vector2(70, base), "SCORE %06d" % GameState.score)
	# Active power, timer bar and the shockwave flag.
	var x := 190.0
	if GameState.power != NanoPalette.Power.NONE:
		var c := NanoPalette.color_of(GameState.power)
		_text(Vector2(x, base), NanoPalette.name_of(GameState.power), c)
		var frac := clampf(GameState.power_time / maxf(GameState.power_duration, 0.01), 0.0, 1.0)
		draw_rect(Rect2(x + 60, top + 8, 62, 9), Color.BLACK)
		draw_rect(Rect2(x + 61, top + 9, 60.0 * frac, 7), c)
		x += 134.0
	if GameState.shockwave_unlocked:
		_text(Vector2(x, base), "SHOCK", NanoPalette.SHOCKWAVE)
	# Keys.
	var kx := w - 190.0
	for k in GameState.KEY_COLORS:
		var held := GameState.keys.has(k)
		var col: Color = GameState.KEY_COLORS[k]
		draw_rect(Rect2(kx, top + 7, 14, 10), Color.BLACK)
		draw_rect(Rect2(kx + 1, top + 8, 12, 8), col if held else Color(col, 0.18))
		kx += 18.0
	# Hidden C-A-T bonus letters: small and dim, and only shown once one is found.
	if GameState.letter_mask != 0:
		for i in 3:
			var found := (GameState.letter_mask >> i) & 1 == 1
			_text(Vector2(w - 56 + i * 14, base), "CAT"[i], Color(LETTER_ON, 0.9) if found else Color(1, 1, 1, 0.14))
