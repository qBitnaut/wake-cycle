class_name Birds
extends Node2D
## Sparrows for the morning street. Perched birds sit on fences and wires,
## hop and look about, and take off with a chirp when the cat comes close
## (flying up and away from it). Now and then a few birds cross high over
## the street. Frames from assets/art_hd/home/birds.png (9x7: perched,
## wings up, wings down).
##
## Put the node at the world origin; perches are world px (a bird's feet).

const SHEET := preload("res://assets/art_hd/home/birds.png")
const FRAME := Vector2(9, 7)
const CHIRPS := [
	preload("res://assets/audio/sfx/bird_chirp_1.ogg"),
	preload("res://assets/audio/sfx/bird_chirp_2.ogg"),
]

@export var perches: Array[Vector2] = []
@export var cat_path: NodePath = ^"../Cat"
@export var flee_distance := 96.0
## Seconds between birds crossing the sky (0 = never).
@export var flyover_interval := Vector2(9.0, 16.0)
## The band of world y the flyovers use.
@export var flyover_y := Vector2(60.0, 130.0)

var flown := 0

var _birds: Array = []   # {pos, vel, state, t, flip, hop}
var _cat: Node2D
var _next_flyover := 4.0
var _chirp: AudioStreamPlayer


func _ready() -> void:
	_cat = get_node_or_null(cat_path) as Node2D
	_chirp = AudioStreamPlayer.new()
	_chirp.volume_db = -14.0
	_chirp.bus = &"SFX"
	add_child(_chirp)
	for p in perches:
		_birds.append({"pos": p, "vel": Vector2.ZERO, "state": 0, "t": randf() * 3.0,
			"flip": randf() < 0.5, "hop": 0.0, "far": false})
	_next_flyover = randf_range(2.0, flyover_interval.x)


func _view() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	var size := get_viewport_rect().size
	var c := cam.get_screen_center_position() if cam else size * 0.5
	return Rect2(c - size * 0.5, size)


func _process(delta: float) -> void:
	var view := _view()
	if flyover_interval.x > 0.0:
		_next_flyover -= delta
		if _next_flyover <= 0.0:
			_next_flyover = randf_range(flyover_interval.x, flyover_interval.y)
			_flyover(view)
	var scared := false
	var i := 0
	while i < _birds.size():
		var b: Dictionary = _birds[i]
		b.t += delta
		if b.state == 0:
			_idle(b, delta)
			if _cat and absf(_cat.global_position.x - b.pos.x) < flee_distance and absf(_cat.global_position.y - b.pos.y) < 140.0:
				b.state = 1
				var away := signf(b.pos.x - _cat.global_position.x)
				if away == 0.0:
					away = 1.0
				b.vel = Vector2(away * randf_range(55.0, 85.0), randf_range(-120.0, -80.0))
				b.flip = away < 0.0
				b.t = randf() * 0.2
				scared = true
				flown += 1
		else:
			b.vel.y += 30.0 * delta
			b.vel.x *= 1.0 + 0.6 * delta
			b.pos += b.vel * delta
			if not view.grow(80.0).has_point(b.pos):
				_birds.remove_at(i)
				continue
		i += 1
	if scared and not _chirp.playing:
		_chirp.stream = CHIRPS[randi() % CHIRPS.size()]
		_chirp.pitch_scale = randf_range(0.95, 1.15)
		_chirp.play()
	queue_redraw()


func _idle(b: Dictionary, delta: float) -> void:
	b.hop = maxf(b.hop - delta, 0.0)
	if b.t > 1.6 and randf() < delta * 0.8:
		b.t = 0.0
		if randf() < 0.5:
			b.flip = not b.flip
		else:
			b.hop = 0.12


func _flyover(view: Rect2) -> void:
	var from_right := randf() < 0.5
	var n := randi_range(2, 4)
	var y := randf_range(flyover_y.x, flyover_y.y)
	for k in n:
		var x := view.end.x + 20.0 + k * randf_range(10.0, 18.0) if from_right else view.position.x - 20.0 - k * randf_range(10.0, 18.0)
		_birds.append({"pos": Vector2(x, y + k * randf_range(-6.0, 6.0)),
			"vel": Vector2((-1.0 if from_right else 1.0) * randf_range(70.0, 90.0), randf_range(-6.0, 4.0)),
			"state": 1, "t": randf(), "flip": from_right, "hop": 0.0, "far": true})


func _draw() -> void:
	for b in _birds:
		var frame := 0
		if b.state == 1:
			frame = 1 if fmod(b.t * 11.0, 1.0) < 0.5 else 2
		var src := Rect2(Vector2(frame * FRAME.x, 0), FRAME)
		var p: Vector2 = (b.pos - Vector2(FRAME.x * 0.5, FRAME.y)).floor()
		if b.state == 0 and b.hop > 0.0:
			p.y -= 2.0
		var dst := Rect2(p, FRAME)
		if b.flip:
			dst = Rect2(p + Vector2(FRAME.x, 0), Vector2(-FRAME.x, FRAME.y))
		var tint := Color(0.75, 0.78, 0.9, 0.85) if b.far else Color.WHITE
		draw_texture_rect_region(SHEET, dst, src, tint)
