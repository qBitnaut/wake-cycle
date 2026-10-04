class_name Pickup
extends Area2D
## Key, C-A-T letter, fish (health refill) or gem (score).

const FONT := preload("res://assets/fonts/monogram.ttf")
enum Kind { KEY, LETTER, FISH, GEM }

@export var kind: Kind = Kind.GEM
@export var key_color := "brass"
@export_range(0, 2) var letter_index := 0
@export var persist := true  # false for drops spawned at runtime

var _t := randf() * 6.0
var _id := ""
var _nope := 0.0


func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	body_entered.connect(_on_body)
	_id = str(get_path())
	if persist and GameState.is_collected(_id):
		queue_free()


func _on_body(body: Node) -> void:
	if not body is Cat:
		return
	match kind:
		Kind.KEY:
			GameState.add_key(key_color)
			Sfx.play(self, "pickup", -4.0, 0.8)
		Kind.LETTER:
			if not GameState.collect_letter(letter_index):
				_nope = 0.4
				return
			Sfx.play(self, "power_up", -6.0)
		Kind.FISH:
			GameState.set_health(GameState.MAX_HEALTH)
			GameState.add_score(100)
			Sfx.play(self, "pickup", -4.0, 1.3)
		Kind.GEM:
			GameState.add_score(100)
			Sfx.play(self, "pickup")
	if persist:
		GameState.mark_collected(_id)
	Debris.burst(get_parent(), global_position, _color(), 6)
	queue_free()


func _color() -> Color:
	match kind:
		Kind.KEY:
			return GameState.KEY_COLORS.get(key_color, Color.WHITE)
		Kind.LETTER:
			return Color("ffd23f")  # gold: the cat's
		Kind.FISH:
			return Color("e89a7a")  # salmon
	return Color("c3d8cf")  # gem: cool steel crystal (no power hue)


func _process(delta: float) -> void:
	_t += delta
	_nope = maxf(_nope - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var c := _color()
	var bob := Vector2(0, -16.0 + roundf(sin(_t * 3.0) * 3.0))
	draw_set_transform(bob, 0.0, Vector2(2, 2))  # 2x: placeholder art stays pixel-exact
	match kind:
		Kind.KEY:
			draw_circle(Vector2(-3, 0), 3.5, c)
			draw_circle(Vector2(-3, 0), 1.2, Color("161630"))
			draw_rect(Rect2(0, -1, 7, 2), c)
			draw_rect(Rect2(4, 1, 2, 3), c)
		Kind.LETTER:
			var col := Color("ff4a3a") if _nope > 0.0 else c
			draw_circle(Vector2.ZERO, 7.0, Color(col, 0.2))
			draw_string(FONT, Vector2(-8, 5), "CAT"[letter_index], HORIZONTAL_ALIGNMENT_CENTER, 16.0, 16, col)
		Kind.FISH:
			draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(0, -3), Vector2(5, 0), Vector2(0, 3)]), c)
			draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(9, -3), Vector2(9, 3)]), c.darkened(0.2))
			draw_rect(Rect2(-4, -1, 1, 1), Color.BLACK)
		Kind.GEM:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -5), Vector2(4, 0), Vector2(0, 5), Vector2(-4, 0)]), c)
			draw_rect(Rect2(-1, -3, 1, 2), Color(1, 1, 1, 0.8))
