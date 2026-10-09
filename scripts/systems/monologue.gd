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
## string or {"text": "...", "hold": seconds, "after": seconds}; "after" is a
## silence held once the line has faded, before the next one. Edit the file;
## no code changes.
##   Monologue.play("awakening")        queue every line of a set
##   Monologue.play_once("exit_hint")   same, but only the first time
##   Monologue.say("Hmm.", 2.5)         one ad-hoc line (hold < 0 = by length)
##   Monologue.play_memory("memory_yard")  a memory fragment: the set, with the music and
##                                      ambience ducked deep and a faint warm glow pulse
##
## No inner voice before the goo: while GameState.intelligence is false every entry point
## (play, play_once, play_line, say, play_memory) shows nothing and speaks nothing; the cat just
## meows (meow(), a variant by context, and the cat's meow pose when it is standing). A memory
## fragment found then is kept in GameState.pending_memory and played by play_pending_memory()
## (the world map calls it) once the mind is awake.
##
## Over a CineZoom close-up the layer is handed to CineZoom's unmagnified overlay
## (CineZoom.attach_overlay), which covers the whole window, so lines show over
## the letterbox too.
##
## Voice: a line of a set is spoken when it has a clip,
## res://assets/audio/voice/<id>_<index>.ogg (ElevenLabs, see voice.json). The subtitle
## stays up for max(its timing, clip length + VOICE_TAIL), so a line is never cut off. A
## line without a clip (or an ad-hoc say()) is text only. The clip plays on the "Voice"
## bus; AudioDirector ducks the music and ambience while `voice_active`.
##
## Pacing (priorities, queue rules): every set in the json has a "priority" (critical, story,
## memory, filler; the default for a set without one is filler). A set is {"priority": "...",
## "lines": [...]}.
##   CRITICAL  how-to, power teaching, direction and objective hints. Starts within about a second
##             of its trigger: it cuts a FILLER line that is speaking (a 0.25 s fade of voice and
##             subtitle), and jumps ahead of every queued non-critical set.
##   STORY     key narrative beats. Cut FILLER, queue ahead of FILLER, never cut CRITICAL.
##   MEMORY    memory fragments the player collected. Same as STORY for ordering; never discarded.
##   FILLER    flavour and ambient commentary. Never waits behind anything: if a line is speaking
##             or queued, or one was spoken in the last FILLER_COOLDOWN seconds, it is dropped (a
##             MonologueTrigger leaves it armed while the cat stands in it, so a lingering player
##             still hears it). A queued FILLER that cannot start FILLER_EXPIRY seconds after its
##             trigger is dropped. A multi-line FILLER set is cut after any line during which the
##             cat travelled more than FILLER_CUT_DIST.
## Sections: a line belongs to the room and checkpoint it was triggered in. When the cat reaches
## a new checkpoint or leaves the room, queued FILLER of the old section is discarded, and a
## queued STORY only stays if it is within STORY_STALE_DIST of the cat (never across a room
## change). A queued FILLER or STORY further behind the cat than STALE_DIST is dropped. Anything
## dropped is listed in drop_log, every line started in play_log (for the pacing audit).
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
const VOICE_DIR := "res://assets/audio/voice/%s_%d.ogg"
const VOICE_TAIL := 0.45  ## seconds the subtitle outlives its clip

# ---- Pacing: tuning (see "Pacing" in the header) ----
enum Prio { CRITICAL, STORY, MEMORY, FILLER }  ## lower = more important; also the queue order
const PRIO_NAMES := {"critical": Prio.CRITICAL, "story": Prio.STORY, "memory": Prio.MEMORY, "filler": Prio.FILLER}
const DEFAULT_PRIO := Prio.FILLER  ## a set (or an ad-hoc line) with no priority of its own
## A CRITICAL line is meant to start within about this long of its trigger (only another CRITICAL
## or a STORY line mid-sentence can delay it); the pacing audit asserts it with some slack.
const CRITICAL_START_TARGET := 1.0
const PREEMPT_FADE := 0.25  ## seconds a cut line takes to fade its voice and subtitle
const MIN_GAP := 0.4  ## least silence between two lines of a queue, for readability
const FILLER_COOLDOWN := 9.0  ## no FILLER starts within this long of the end of any line
const FILLER_EXPIRY := 4.0  ## a queued FILLER that has not started this long after its trigger is dropped
const STALE_DIST := 800.0  ## a queued FILLER or STORY this far behind the cat (px) is dropped
const STORY_STALE_DIST := 600.0  ## after a new checkpoint, a queued STORY further than this (px) is dropped
const FILLER_CUT_DIST := 300.0  ## a FILLER set stops after a line during which the cat moved this far (px)
const QUEUE_MAX := 2  ## sets waiting; past this a queued FILLER is shed (the rest is never dropped for room)
const TINT := Color(0.82, 0.90, 1.0)
const GLOW_PEAK := 0.55  ## the memory vignette's strongest alpha factor
const GLOW_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.25, 0.75, length(d * vec2(1.0, 1.2)));
	COLOR = vec4(1.0, 0.78, 0.45, v * amount * 0.5);
}
"""
const FOLD := {
	"…": "...", "—": "-", "–": "-", "‘": "'", "’": "'",
	"“": "\"", "”": "\"", " ": " ",
}

## Every line that has been shown, in order: [id, text]. For audits and a log.
var history: Array = []
## One entry per line that had a voice clip: [id, index, clip seconds, hold seconds]. For audits.
var voice_log: Array = []
## True while a clip is playing.
var voice_active := false
## True from a memory fragment's first line to a moment after its last: AudioDirector ducks
## deeper and the glow holds.
var memory_active := false

## One Dictionary per line started: id, idx, prio, trigger_t (when it was asked for), start_t,
## scene/section at the trigger and at the start, dx (px the cat moved while it spoke), end_t,
## cut/preempted flags. For the pacing audit.
var play_log: Array = []
## One entry per set that never (fully) played: [id, reason, prio, trigger_t, clock].
var drop_log: Array = []
## Counters for the pacing audit and a log: preempted, filler_cut, queue_max (the most sets waiting) and queue_ids.
var stats := {"preempted": 0, "filler_cut": 0, "queue_max": 0, "queue_ids": []}

## Every meow made in place of a line, in order: [set id ("" for say), variant]. For audits.
var meow_log: Array = []
## How many of those meows actually started a sound (an SFX player was created). For audits.
var meow_sounds := 0

var _sets := {}
var _last_meow := -1
var _played := {}
var _prio := {}  # set id -> Prio
## Sets waiting to start, in order: {id, lines [[text, hold, after, index]], pos, prio, t, at, scene,
## section, expires, uid}. The set being spoken is _active (its remaining lines are lines[pos:]).
var _queue: Array = []
var _active: Dictionary = {}
var _cur: Dictionary = {}  # the line being spoken (a play_log entry) while _speaking
var _busy := false  # a line is up, or the silence between lines is running
var _speaking := false  # a line is up (not yet fading out)
var _preempting := false
var _clock := 0.0  # game seconds since boot; every pacing time is on this clock
var _last_end := -1000.0  # _clock when the last line ended
var _last_section := ""
var _uid := 0  # numbers the sets, to tell one from another
var _root: Control
var _glow: ColorRect
var _glow_mat: ShaderMaterial
var _glow_tween: Tween
var _memory_id := ""
var _plate: Panel
var _label: Label
var _tween: Tween
var _voice: AudioStreamPlayer
var _size := Vector2.ZERO    # the plate's size
var _slot := 0               # the slot in SLOTS last chosen (normal play)
var _overlaid := false
var _opaque := {}            # frame texture -> its visible pixel bounds


func _ready() -> void:
	layer = 90  # above the HUD and the cinematic letterbox, below the title and the room fades
	_load()
	_glow = ColorRect.new()
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = GLOW_SHADER
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = sh
	_glow.material = _glow_mat
	_glow_mat.set_shader_parameter("amount", 0.0)
	add_child(_glow)
	set_finished.connect(_on_set_finished)
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
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = &"Voice"
	_voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM  # web: samples drop the Voice bus; stream like the beds
	add_child(_voice)
	_voice.finished.connect(func(): voice_active = false)


func _load() -> void:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		push_warning("Monologue: %s missing" % DATA)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for id in parsed:
			var e: Variant = parsed[id]
			if e is Dictionary:
				_sets[id] = e.get("lines", [])
				_prio[id] = PRIO_NAMES.get(str(e.get("priority", "")).to_lower(), DEFAULT_PRIO)
			else:
				_sets[id] = e  # a bare array of lines: default priority
				_prio[id] = DEFAULT_PRIO
	else:
		push_warning("Monologue: %s is not a JSON object" % DATA)


## Which meow (index into the "meow" sfx variants: 0 curious, 1 questioning mrrp, 2 trill,
## 3 uneasy low, 4 small determined mew) goes with which set. Anything else: random, never
## the same twice running.
const MEOW_FOR := {
	"warehouse_climb": 1, "warehouse_roof": 0, "warehouse_shaft": 4, "warehouse_lab": 3,
	"continue_tease": 0, "memory_warehouse": 2, "startover_tease": 4, "startover": 3,
}
const MEOW_VARIANTS := 5


## The cat has no inner voice until the goo wakes its mind: true (and a meow instead) while
## GameState.intelligence is false.
func mute_for_mind(id := "") -> bool:
	if GameState.intelligence:
		return false
	meow(id)
	return true


## The cat's own vocalisation, in place of a line: a meow on the SFX bus at full level (it is
## the cat's own sound) and the meow pose when the cat is idle or standing. `id` picks the
## variant by context (MEOW_FOR).
func meow(id := "") -> void:
	var v: int = MEOW_FOR.get(id, -1)
	if v < 0:
		v = randi() % MEOW_VARIANTS
		if v == _last_meow:
			v = (v + 1 + randi() % (MEOW_VARIANTS - 1)) % MEOW_VARIANTS
	_last_meow = v
	meow_log.append([id, v])
	var cat := get_tree().get_first_node_in_group("player") as Cat
	if Sfx.play(cat if cat else self, "meow", 0.0, 1.0, v) != null:
		meow_sounds += 1
	if cat:
		cat.meow_pose()


## Queue every line of the set `id` by its priority (see "Pacing"). Returns false when the set
## was dropped at once (a FILLER while something spoke or in the cooldown). `patient` lets a
## FILLER queue behind what is speaking and ignore the cooldown (the world map's place lines).
func play(id: String, patient := false) -> bool:
	if mute_for_mind(id):
		return false
	var lines: Array = _sets.get(id, [])
	if lines.is_empty():
		push_warning("Monologue: no lines for '%s'" % id)
		return false
	return _submit(_make_set(id, range(lines.size()), priority_of(id)), patient)


## A memory fragment: play(id) with the music and ambience ducked deeper than for the
## voice alone, and a faint warm glow that swells in and eases out after the last line.
func play_memory(id: String) -> void:
	if not has_set(id):
		push_warning("Monologue: no lines for '%s'" % id)
		return
	if not GameState.intelligence:
		# No words yet: a soft meow and the warm glow, and the memory waits for the mind.
		GameState.pending_memory = id
		meow(id)
		_glow_pulse()
		return
	_memory_id = id
	memory_active = true
	_glow_to(GLOW_PEAK, 1.2)
	play(id)


## The memory kept by play_memory() before the mind woke, played now. False when none waits
## (or the mind is still asleep).
func play_pending_memory() -> bool:
	var id := GameState.pending_memory
	if id == "" or not GameState.intelligence:
		return false
	GameState.pending_memory = ""
	play_memory(id)
	return true


## The memory glow and the deeper duck, with no words: swells, holds a moment, eases out.
func _glow_pulse() -> void:
	memory_active = true
	_glow_to(GLOW_PEAK, 1.0)
	get_tree().create_timer(1.6).timeout.connect(func():
		if _memory_id == "":
			_glow_to(0.0, 2.0)
			get_tree().create_timer(2.4).timeout.connect(func():
				if _memory_id == "":
					memory_active = false))


func _on_set_finished(id: String) -> void:
	if id != _memory_id or not memory_active:
		return
	_memory_id = ""
	_glow_to(0.0, 2.0)
	# The duck is released a beat after the last line so the music returns gently.
	get_tree().create_timer(0.8).timeout.connect(func():
		if _memory_id == "":
			memory_active = false)


func _glow_to(v: float, secs: float) -> void:
	if _glow_tween:
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_property(_glow_mat, "shader_parameter/amount", v, secs).set_trans(Tween.TRANS_SINE)


## Queue one line of the set `id` (0-based), e.g. the count-th line of a
## counting set. Out of range plays the last line.
func play_line(id: String, index: int) -> void:
	if mute_for_mind(id):
		return
	var lines: Array = _sets.get(id, [])
	if lines.is_empty():
		push_warning("Monologue: no lines for '%s'" % id)
		return
	_submit(_make_set(id, [clampi(index, 0, lines.size() - 1)], priority_of(id)))


## play(), but only the first time `id` is asked for (until reset()).
## Returns false when it had already played.
func play_once(id: String, patient := false) -> bool:
	if _played.has(id):
		return false
	if mute_for_mind(id):
		return false  # not marked as played: it can still be told once the mind is awake
	_played[id] = true
	play(id, patient)
	return true


## One ad-hoc line. hold < 0 times it by its length. Treated as a MEMORY line (the one caller is a
## memory fragment without a set).
func say(text: String, hold := -1.0) -> void:
	if mute_for_mind():
		return
	_submit(_make_set("", [], Prio.MEMORY, [[text, hold, 0.0, -1]]))


## The priority (Prio) of the set `id`.
func priority_of(id: String) -> int:
	return _prio.get(id, DEFAULT_PRIO)


## How many lines the set `id` has.
func line_count(id: String) -> int:
	return (_sets.get(id, []) as Array).size()


## True when a new FILLER would be dropped now: a line is speaking or waiting, or the last one
## ended less than FILLER_COOLDOWN ago.
func filler_blocked() -> bool:
	return _busy or not _queue.is_empty() or _clock < _last_end + FILLER_COOLDOWN


## A FILLER trigger the cat walked through while it was blocked, and left again: counted as dropped.
func note_filler_drop(id: String) -> void:
	drop_log.append([id, "blocked", Prio.FILLER, _clock, _clock])


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
	voice_log.clear()
	meow_log.clear()
	meow_sounds = 0
	play_log.clear()
	drop_log.clear()
	stats = {"preempted": 0, "filler_cut": 0, "queue_max": 0, "queue_ids": []}
	_active = {}
	_cur = {}
	_speaking = false
	_preempting = false
	_last_end = -1000.0
	_stop_voice()
	_busy = false
	_memory_id = ""
	memory_active = false
	if _glow_mat:
		_glow_mat.set_shader_parameter("amount", 0.0)
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
	_clock += delta
	var section := _section()
	if section != _last_section:
		_last_section = section
		_prune()  # a new checkpoint or room: the old section's waiting lines go
	elif not _queue.is_empty():
		_prune()  # expiry and distance
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


## The game scene (room) and the section: the room plus its last checkpoint.
func _scene() -> String:
	var sc := get_tree().current_scene
	return sc.scene_file_path if sc else ""


func _section() -> String:
	return _scene() + "#" + SaveSystem.session_checkpoint


## Pixels from `from` to the cat; 0 when either is unknown (the map has no cat).
func _dist(from: Vector2) -> float:
	var cat := get_tree().get_first_node_in_group("player") as Node2D
	if cat == null or from == Vector2.INF:
		return 0.0
	return cat.global_position.distance_to(from)


func _make_set(id: String, indices: Array, prio: int, adhoc := []) -> Dictionary:
	var lines: Array = adhoc.duplicate()
	var src: Array = _sets.get(id, [])
	for i in indices:
		var l: Variant = src[i]
		var text := str(l.get("text", "")) if l is Dictionary else str(l)
		var hold := float(l.get("hold", -1.0)) if l is Dictionary else -1.0
		var after := float(l.get("after", 0.0)) if l is Dictionary else 0.0
		lines.append([text, hold, after, i])
	var cat := get_tree().get_first_node_in_group("player") as Node2D
	_uid += 1
	return {
		"id": id, "lines": lines, "pos": 0, "prio": prio, "t": _clock,
		"at": cat.global_position if cat else Vector2.INF,
		"scene": _scene(), "section": _section(),
		"expires": _clock + FILLER_EXPIRY if prio == Prio.FILLER else INF,
		"uid": _uid,
	}


## Admit a set by its priority: drop it, or queue it in rank order and, if it outranks the FILLER
## line that is speaking, cut that line.
func _submit(s: Dictionary, patient := false) -> bool:
	var p: int = s.prio
	if p == Prio.FILLER and not patient and filler_blocked():
		_drop(s, "busy" if (_busy or not _queue.is_empty()) else "cooldown")
		return false
	_insert(s)
	var kept := true
	while _queue.size() > QUEUE_MAX:
		var victim := -1
		for i in range(_queue.size() - 1, -1, -1):  # the latest FILLER; nothing else is ever shed
			if _queue[i].prio == Prio.FILLER:
				victim = i
				break
		if victim < 0:
			break
		_drop(_queue[victim], "queue_full")
		kept = kept and _queue[victim].uid != s.uid
		_queue.remove_at(victim)
	if not _busy:
		_next()
	elif p < Prio.FILLER and _speaking and not _preempting and int(_cur.get("prio", -1)) == Prio.FILLER:
		_preempt()
	if _queue.size() > stats.queue_max:
		stats.queue_max = _queue.size()
		stats.queue_ids = _queue.map(func(q): return q.id)
	return kept


## Queue a set in rank order (FIFO within a rank).
func _insert(s: Dictionary) -> void:
	var at := _queue.size()
	for i in _queue.size():
		if _queue[i].prio > s.prio:
			at = i
			break
	_queue.insert(at, s)


func _drop(s: Dictionary, why: String) -> void:
	drop_log.append([s.id, why, s.prio, s.t, _clock])


## Why a waiting set is no use any more ("" when it still is).
func _stale(s: Dictionary) -> String:
	var p: int = s.prio
	if p == Prio.CRITICAL or p == Prio.MEMORY:
		return ""
	if p == Prio.FILLER and _clock > s.expires:
		return "expired"
	if s.scene != _scene():
		return "left_room"
	var d := _dist(s.at)
	if s.section != _section():
		if p == Prio.FILLER:
			return "section"
		if d > STORY_STALE_DIST:
			return "section_far"
	if d > STALE_DIST:
		return "far"
	return ""


func _prune() -> void:
	for i in range(_queue.size() - 1, -1, -1):
		var why := _stale(_queue[i])
		if why != "":
			_drop(_queue[i], why)
			_queue.remove_at(i)


## The set to take the next line from: the rest of the set being spoken, unless something more
## important is waiting (the rest of a FILLER set is then dropped, of a STORY set kept for later).
func _pick() -> Dictionary:
	if not _active.is_empty() and _active.pos < _active.lines.size() and _active.prio == Prio.FILLER \
			and (_active.scene != _scene() or _active.section != _section()):
		_drop(_active, "section")  # the cat has moved on to another checkpoint or room
		_active = {}
	if not _active.is_empty() and _active.pos < _active.lines.size():
		if _queue.is_empty() or _queue[0].prio >= _active.prio:
			return _active
		if _active.prio == Prio.FILLER:
			_drop(_active, "preempted")
		else:
			_insert(_active)
	_active = {}
	if _queue.is_empty():
		return {}
	_active = _queue.pop_front()
	return _active


func _next() -> void:
	_speaking = false
	_prune()
	var s := _pick()
	if s.is_empty():
		_busy = false
		return
	_busy = true
	var cz := CineZoom.current()
	if cz:
		_attach(cz)  # drawn unmagnified over the close-up and the letterbox
	var line: Array = s.lines[s.pos]
	s.pos += 1
	var is_last: bool = s.pos >= s.lines.size()
	var id: String = s.id
	var idx: int = line[3]
	var text := clean(line[0])
	var hold: float = line[1] if line[1] >= 0.0 else hold_for(text)
	var after: float = line[2]
	var clip := _clip(id, idx)
	_voice.volume_db = 0.0
	if clip:
		hold = maxf(hold, clip.get_length() + VOICE_TAIL)
		voice_log.append([id, idx, clip.get_length(), hold])
		_voice.stream = clip
		voice_active = true
		_voice.play()
	else:
		_stop_voice()
	_layout(text)
	history.append([id, text])
	var cat := get_tree().get_first_node_in_group("player") as Node2D
	var entry := {
		"id": id, "idx": idx, "prio": s.prio, "trigger_t": s.t, "start_t": _clock,
		"scene_t": s.scene, "section_t": s.section, "section_s": _section(),
		"x0": cat.global_position if cat else Vector2.INF, "dx": 0.0, "end_t": -1.0,
		"cut": false, "preempted": false, "text": text, "fade_t": -1.0,
	}
	play_log.append(entry)
	_cur = entry
	_speaking = true
	line_started.emit(id, text)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(hold)
	_tween.tween_callback(func():
		_speaking = false
		entry.fade_t = _clock)
	# Back-to-back lines cross-fade through a shorter dip instead of a full fade out.
	var more := not is_last or not _queue.is_empty()
	var out := FADE_OUT if not more or after > 0.0 else FADE_OUT * 0.5
	_tween.tween_property(_root, "modulate:a", 0.0, out).set_trans(Tween.TRANS_SINE)
	var gap := maxf(after, MIN_GAP) if more else after
	if gap > 0.0:
		_tween.tween_interval(gap)
	_tween.tween_callback(func(): _line_done(s, entry, is_last))


func _line_done(s: Dictionary, entry: Dictionary, is_last: bool) -> void:
	_speaking = false
	_last_end = _clock
	entry.end_t = _clock
	entry.dx = _dist(entry.x0)
	line_finished.emit(entry.id, entry.text)
	# A FILLER set only goes on while the player is not running past it.
	if s.prio == Prio.FILLER and not is_last and entry.dx > FILLER_CUT_DIST:
		s.pos = s.lines.size()
		is_last = true
		entry.cut = true
		stats.filler_cut += 1
	if is_last:
		set_finished.emit(entry.id)
	_next()


## Cut the FILLER line that is speaking: its voice and subtitle fade over PREEMPT_FADE, the rest of
## its set is dropped, and the queue moves on.
func _preempt() -> void:
	_preempting = true
	_speaking = false
	var entry := _cur
	var s := _active
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_root, "modulate:a", 0.0, PREEMPT_FADE).set_trans(Tween.TRANS_SINE)
	if voice_active:
		_tween.tween_property(_voice, "volume_db", -40.0, PREEMPT_FADE)
	_tween.chain().tween_callback(func():
		_preempting = false
		_stop_voice()
		_last_end = _clock
		entry.end_t = _clock
		entry.dx = _dist(entry.x0)
		entry.preempted = true
		stats.preempted += 1
		line_finished.emit(entry.id, entry.text)
		s.pos = s.lines.size()
		set_finished.emit(entry.id)
		_next())


## The voice clip of line `index` of set `id`, or null (text only).
func _clip(id: String, index: int) -> AudioStream:
	if id == "" or index < 0:
		return null
	var path := VOICE_DIR % [id, index]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _stop_voice() -> void:
	if _voice:
		_voice.stop()
		_voice.volume_db = 0.0
	voice_active = false


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
	var corner := spr.offset - sz * 0.5 if spr.centered else spr.offset
	if spr.centered and spr.get_viewport().snap_2d_transforms_to_pixel:
		corner = (corner + Vector2(0.5, 0.5)).floor()  # as Godot draws it (75 px frames start at -37)
	var used := _opaque_rect(tex)  # the frames are padded: use the drawn pixels
	if spr.flip_h:
		used.position.x = sz.x - used.end.x
	if spr.flip_v:
		used.position.y = sz.y - used.end.y
	return (spr.get_global_transform_with_canvas() * Rect2(corner + used.position, used.size)).abs()
