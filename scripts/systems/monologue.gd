extends CanvasLayer
## The cat's inner monologue, shown as subtitles: lower-centre, a soft dark
## plate behind monogram text, fade in and out, a queue of lines. It can sit on
## top of the cinematic letterbox. Registered as the autoload "Monologue".
##
## Where it sits: over a CineZoom close-up, at the bottom of the window (in the
## letterbox bar), whatever the window's aspect, so it never lies on the zoomed
## subject. In normal play, bottom-centre above the HUD strip; when the cat (or
## the crate label) is there it moves to the top band, or sideways.
##
## The words live in res://data/monologue.json, keyed by id. A line is either a
## string or {"text": "...", "hold": seconds}. Edit the file; no code changes.
##   Monologue.play("awakening")        queue every line of a set
##   Monologue.play_once("exit_hint")   same, but only the first time
##   Monologue.say("Hmm.", 2.5)         one ad-hoc line (hold < 0 = by length)
##
## Over a CineZoom close-up the layer is handed to CineZoom's unmagnified overlay
## (CineZoom.attach_overlay), which covers the whole window, so lines show over
## the letterbox too.
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
## The plate's bottom edge sits this far above the bottom of the view in normal play:
## just over the HUD strip (24 px) ...
const BOTTOM := 30.0
## ... and this far from the top edge in the top band, and from the window bottom
## over a close-up.
const TOP := 8.0
const WINDOW_BOTTOM := 6.0
## Sideways shifts tried (after the top band) when the cat or the crate is in the way.
const SHIFT := 120.0
## Clearance kept around the cat and the crate, game px.
const CLEAR := 6.0
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
var _size := Vector2.ZERO    # the plate's size
var _slot := 0               # the slot in SLOTS last chosen (normal play)
var _overlaid := false
var _opaque := {}            # frame texture -> its visible pixel bounds


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


## Queue one line of the set `id` (0-based), e.g. the count-th line of a
## counting set. Out of range plays the last line.
func play_line(id: String, index: int) -> void:
	var lines: Array = _sets.get(id, [])
	if lines.is_empty():
		push_warning("Monologue: no lines for '%s'" % id)
		return
	var i := clampi(index, 0, lines.size() - 1)
	var l: Variant = lines[i]
	var text := str(l.get("text", "")) if l is Dictionary else str(l)
	var hold := float(l.get("hold", -1.0)) if l is Dictionary else -1.0
	_queue.append([id, text, hold, true])
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


func _process(_delta: float) -> void:
	# A line already showing when a close-up starts moves over it too.
	var cz := CineZoom.current()
	if _busy and cz and not cz.is_overlaid(self):
		_attach(cz)
	if _busy:
		_place()


func _attach(cz: CineZoom) -> void:
	cz.attach_overlay(self)
	# Back in the game frame the same frame the pass ends: no stray frame at overlay coordinates.
	if not cz.pass_ended.is_connected(_place):
		cz.pass_ended.connect(_place, CONNECT_ONE_SHOT)


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var cz := CineZoom.current()
	if cz:
		_attach(cz)  # drawn unmagnified over the close-up and the letterbox
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


## Size the plate to the text and put it where it belongs (see _place).
func _layout(text: String) -> void:
	var inner := FONT.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, MAX_WIDTH, SIZE)
	var w := minf(inner.x, MAX_WIDTH) + 6.0
	var h := inner.y + 2.0
	# Width first, then the text: an auto-wrapping Label sizes its minimum height
	# for the width it has when the text arrives (a zero width means a tall box).
	_label.text = ""
	_label.size = Vector2(w, 1.0)
	_label.text = text
	_label.size = Vector2(w, h)
	_size = Vector2(w, h) + PAD * 2.0
	_plate.size = _size
	_slot = 0
	_place()


## The plate's rect in the coordinates of the viewport it is drawn into: the
## overlay while a close-up is live, else the game frame.
func plate_rect() -> Rect2:
	return Rect2(_plate.position, _plate.size)


## The plate's rect in window pixels while a close-up overlays it, else an empty rect.
func plate_window_rect() -> Rect2:
	var cz := CineZoom.current()
	if cz and cz.is_overlaid(self):
		return cz.overlay_rect_to_window(plate_rect())
	return Rect2()


## The cat's rect in window pixels while a close-up is live, else an empty rect.
func cat_window_rect() -> Rect2:
	var cz := CineZoom.current()
	var r := cat_screen_rect()
	if cz == null or not r.has_area():
		return Rect2()
	var a := cz.game_to_window(r.position)
	return Rect2(a, cz.game_to_window(r.end) - a).abs()


## Over a close-up: centred on the bottom of the window. In normal play: the
## first of bottom-centre, top-centre, then the bottom and top shifted aside,
## that keeps clear of the cat and the crate label (the one in use is kept while
## it stays clear, so the plate does not dance).
func _place() -> void:
	if _size == Vector2.ZERO:
		return
	var cz := CineZoom.current()
	var view := get_viewport().get_visible_rect().size
	var pos: Vector2
	if cz and cz.is_overlaid(self):
		_overlaid = true
		var ov := cz.overlay_size()
		pos = Vector2(roundf((ov.x - _size.x) / 2.0), ov.y - WINDOW_BOTTOM - _size.y)
	else:
		if _overlaid:
			_overlaid = false
			_slot = 0
		var avoid := _avoid_rects()
		var best := -1
		for k in [_slot, 0, 1, 2, 3, 4, 5]:
			if not _hits(Rect2(_slot_pos(k, view), _size), avoid):
				best = k
				break
		if best >= 0:
			_slot = best
		pos = _slot_pos(_slot, view)
	_plate.position = pos
	_label.position = pos + PAD


## Slot 0 bottom-centre, 1 top-centre, 2/3 bottom left/right, 4/5 top left/right.
func _slot_pos(k: int, view: Vector2) -> Vector2:
	var x := roundf((view.x - _size.x) / 2.0)
	if k >= 2:
		x += SHIFT if k % 2 == 1 else -SHIFT
	x = clampf(x, TOP, view.x - _size.x - TOP)
	var top := k == 1 or k >= 4
	return Vector2(x, TOP if top else view.y - BOTTOM - _size.y)


func _hits(r: Rect2, avoid: Array) -> bool:
	for a: Rect2 in avoid:
		if r.intersects(a.grow(CLEAR)):
			return true
	return false


## What a subtitle must not cover in normal play, in game-frame coordinates:
## the cat, and the crate with its stencilled label.
func _avoid_rects() -> Array:
	var out: Array = []
	var r := cat_screen_rect()
	if r.has_area():
		out.append(r)
	var crate := get_tree().current_scene.get_node_or_null("NanofluidCrate") as Node2D if get_tree().current_scene else null
	if crate:
		out.append(crate.get_global_transform_with_canvas() * Rect2(-66.0, -112.0, 200.0, 112.0))
	return out


## The bounds of the visible pixels of a frame texture, in texture pixels (cached).
func _opaque_rect(tex: Texture2D) -> Rect2:
	if _opaque.has(tex):
		return _opaque[tex]
	var r := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img != null and not img.is_empty():
		var used := img.get_used_rect()
		if used.has_area():
			r = Rect2(used)
	_opaque[tex] = r
	return r


## The cat's sprite rect in the game frame (the 640x360 view), or an empty rect.
func cat_screen_rect() -> Rect2:
	var cat := get_tree().get_first_node_in_group("player") as Node2D
	var spr := cat.get("sprite") as AnimatedSprite2D if cat else null
	if spr == null or spr.sprite_frames == null:
		return Rect2()
	var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
	if tex == null:
		return Rect2()
	var sz := tex.get_size()
	var local := Rect2(spr.offset - sz * 0.5 if spr.centered else spr.offset, sz)
	local.position += _opaque_rect(tex).position  # the frames are padded: use the drawn pixels
	local.size = _opaque_rect(tex).size
	return (spr.get_global_transform_with_canvas() * local).abs()
