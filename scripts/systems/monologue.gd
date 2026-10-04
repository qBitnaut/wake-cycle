extends CanvasLayer
## The cat's inner monologue, shown as subtitles: lower-centre, a soft dark
## plate behind monogram text, fade in and out, a queue of lines. It can sit on
## top of the cinematic letterbox. Registered as the autoload "Monologue".
##
## The words live in res://data/monologue.json, keyed by id. A line is either a
## string or {"text": "...", "hold": seconds}. Edit the file; no code changes.
##   Monologue.play("awakening")        queue every line of a set
##   Monologue.play_once("exit_hint")   same, but only the first time
##   Monologue.say("Hmm.", 2.5)         one ad-hoc line (hold < 0 = by length)
##
## CineZoom magnifies every CanvasLayer with the frame (it has no unmagnified
## overlay yet), so a line cannot be drawn legibly during the close-up: queued
## lines wait until the cinematic pass ends, then start (a second or so).
##
## Timing: hold = max(MIN_HOLD, CHARS_PER_SEC_COST * length + BASE_HOLD), plus
## the fades. Monogram has only ASCII: typographic characters are folded to
## their ASCII look and anything else it lacks is dropped (see _clean).

signal line_started(id: String, text: String)
signal line_finished(id: String, text: String)
signal set_finished(id: String)

const FONT := preload("res://assets/fonts/monogram.ttf")
const DATA := "res://data/monologue.json"
const SIZE := 32
const MAX_WIDTH := 380.0  # narrow: keeps the thoughts clear of whatever sits at the screen edge (the crate label)
const PAD := Vector2(14.0, 5.0)
## The plate's bottom edge sits this far above the screen bottom: just over the cat's head
## (the floor line is 40 px up) and over the floor under the zoomed cat in the cinematic,
## clear of the HUD strip.
const BOTTOM := 76.0
const FADE_IN := 0.45
const FADE_OUT := 0.6
const PER_CHAR := 0.06
const BASE_HOLD := 1.2
const MIN_HOLD := 2.0
const TINT := Color(0.82, 0.90, 1.0)
const FOLD := {
	"…": "...", "—": "-", "–": "-", "‘": "'", "’": "'",
	"“": "\"", "”": "\"", " ": " ",
}

## Every line that has been shown, in order: [id, text]. For audits and a log.
var history: Array = []

var _sets := {}
var _played := {}
var _queue: Array = []  # [id, text, hold, last_of_set]
var _busy := false
var _root: Control
var _plate: Panel
var _label: Label
var _tween: Tween
var _cine: Node
var _waiting := false
var _scan_t := 0.0


func _ready() -> void:
	layer = 90  # above the HUD and the cinematic letterbox, below the title and the room fades
	_load()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	add_child(_root)
	_plate = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.07, 0.70)
	sb.set_corner_radius_all(3)
	_plate.add_theme_stylebox_override("panel", sb)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_plate)
	_label = Label.new()
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", SIZE)
	_label.add_theme_color_override("font_color", TINT)
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.04, 0.95))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)


func _load() -> void:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		push_warning("Monologue: %s missing" % DATA)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_sets = parsed
	else:
		push_warning("Monologue: %s is not a JSON object" % DATA)


## Queue every line of the set `id` behind whatever is on screen.
func play(id: String) -> void:
	var lines: Array = _sets.get(id, [])
	if lines.is_empty():
		push_warning("Monologue: no lines for '%s'" % id)
		return
	for i in lines.size():
		var l: Variant = lines[i]
		var text := str(l.get("text", "")) if l is Dictionary else str(l)
		var hold := float(l.get("hold", -1.0)) if l is Dictionary else -1.0
		_queue.append([id, text, hold, i == lines.size() - 1])
	if not _busy:
		_next()


## play(), but only the first time `id` is asked for (until reset()).
## Returns false when it had already played.
func play_once(id: String) -> bool:
	if _played.has(id):
		return false
	_played[id] = true
	play(id)
	return true


## One ad-hoc line. hold < 0 times it by its length.
func say(text: String, hold := -1.0) -> void:
	_queue.append(["", text, hold, false])
	if not _busy:
		_next()


func has_set(id: String) -> bool:
	return _sets.has(id)


func has_played(id: String) -> bool:
	return _played.has(id)


func is_speaking() -> bool:
	return _busy


## Forget what has played (a new game) and clear the screen.
func reset() -> void:
	_played.clear()
	history.clear()
	_queue.clear()
	_busy = false
	_waiting = false
	if _tween:
		_tween.kill()
	if _root:
		_root.modulate.a = 0.0


## Seconds a line of this text stays up, fades excluded.
static func hold_for(text: String) -> float:
	return maxf(MIN_HOLD, PER_CHAR * text.length() + BASE_HOLD)


## Fold typographic characters to ASCII; drop whatever Monogram cannot draw.
static func clean(text: String) -> String:
	var out := ""
	for c in text:
		if FOLD.has(c):
			out += FOLD[c]
		elif c == "\n" or FONT.has_char(c.unicode_at(0)):
			out += c
	return out


func _process(delta: float) -> void:
	if _busy and _waiting:
		if not _cine_active(delta):
			_waiting = false
			_next()


## True while a CineZoom pass is magnifying the frame.
func _cine_active(delta: float) -> bool:
	if not is_instance_valid(_cine):
		_cine = null
		_scan_t -= delta
		if _scan_t > 0.0:
			return false
		_scan_t = 0.25
		_cine = _find_cine(get_tree().root)
	return _cine != null and _cine.call("has_fx")


func _find_cine(n: Node) -> Node:
	var sc: Script = n.get_script()
	if sc and sc.get_global_name() == &"CineZoom":
		return n
	for c in n.get_children():
		var f := _find_cine(c)
		if f:
			return f
	return null


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	if _cine_active(0.25):
		_waiting = true
		return
	var line: Array = _queue.pop_front()
	var text := clean(line[1])
	var hold: float = line[2] if line[2] >= 0.0 else hold_for(text)
	_layout(text)
	history.append([line[0], text])
	line_started.emit(line[0], text)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(hold)
	# Back-to-back lines cross-fade through a shorter dip instead of a full fade out.
	var out := FADE_OUT if _queue.is_empty() else FADE_OUT * 0.5
	_tween.tween_property(_root, "modulate:a", 0.0, out).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func():
		line_finished.emit(line[0], text)
		if line[3]:
			set_finished.emit(line[0])
		_next())


## Size the plate to the text and sit it bottom-centre of the 640x360 view.
func _layout(text: String) -> void:
	var view := get_viewport().get_visible_rect().size
	var inner := FONT.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, MAX_WIDTH, SIZE)
	var w := minf(inner.x, MAX_WIDTH) + 6.0
	var h := inner.y + 2.0
	# Width first, then the text: an auto-wrapping Label sizes its minimum height
	# for the width it has when the text arrives (a zero width means a tall box).
	_label.text = ""
	_label.size = Vector2(w, 1.0)
	_label.text = text
	_label.size = Vector2(w, h)
	_label.position = Vector2((view.x - w) / 2.0, view.y - BOTTOM - h - PAD.y)
	_plate.size = Vector2(w, h) + PAD * 2.0
	_plate.position = _label.position - PAD
