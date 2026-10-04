extends Control
## Minimal Apogee-style HUD: health pips, active power + timer, keys, C-A-T, score.

const FONT := preload("res://assets/fonts/m5x7.ttf")
const SIZE := 16
const SHADOW := Color(0, 0, 0, 0.8)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for sig in [GameState.health_changed, GameState.score_changed, GameState.keys_changed,
			GameState.letters_changed, GameState.power_changed, GameState.shockwave_unlock_changed]:
		sig.connect(func(_a = null, _b = null): queue_redraw())


func _process(_delta: float) -> void:
	if GameState.power != NanoPalette.Power.NONE:
		queue_redraw()


func _text(pos: Vector2, s: String, c := Color.WHITE) -> void:
	draw_string(FONT, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, SHADOW)
	draw_string(FONT, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, c)


func _draw() -> void:
	# Health pips (3 hits; the 4th is fatal).
	for i in GameState.MAX_HEALTH:
		var r := Rect2(4 + i * 11, 4, 9, 7)
		draw_rect(Rect2(r.position - Vector2.ONE, r.size + Vector2(2, 2)), Color.BLACK)
		draw_rect(r, Color("e8403a") if i < GameState.health else Color("401a1a"))
		if i < GameState.health:
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color("ff8a80"))
	# Active power and timer.
	if GameState.power != NanoPalette.Power.NONE:
		var c := NanoPalette.color_of(GameState.power)
		_text(Vector2(4, 24), NanoPalette.name_of(GameState.power), c)
		var frac := clampf(GameState.power_time / maxf(GameState.power_duration, 0.01), 0.0, 1.0)
		draw_rect(Rect2(3, 27, 42, 5), Color.BLACK)
		draw_rect(Rect2(4, 28, 40.0 * frac, 3), c)
	if GameState.shockwave_unlocked:
		_text(Vector2(4, 44 if GameState.power != NanoPalette.Power.NONE else 24), "SHOCK", NanoPalette.SHOCKWAVE)
	# Score.
	_text(Vector2(118, 11), "SCORE %06d" % GameState.score)
	# Keys.
	var x := 254.0
	for k in GameState.KEY_COLORS:
		var held := GameState.keys.has(k)
		var col: Color = GameState.KEY_COLORS[k]
		draw_rect(Rect2(x, 5, 8, 6), Color.BLACK)
		draw_rect(Rect2(x + 1, 6, 6, 4), col if held else Color(col, 0.18))
		x += 11.0
	# C-A-T letters.
	for i in 3:
		_text(Vector2(292 + i * 9, 11), "CAT"[i], Color("ffd23f") if i < GameState.letters else Color(1, 1, 1, 0.25))
