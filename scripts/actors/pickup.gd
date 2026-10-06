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
## Hidden letters twinkle so a player scanning the room can spot them.
const GLINT_PERIOD := 2.6
const GLINT_TIME := 0.7


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
	if kind == Kind.GEM or kind == Kind.FISH:
		# The kit's art: the old diamond is now a ball of yarn (still 100), the fish a fish.
		var tex := KitArt.frame_texture("pickup_yarn" if kind == Kind.GEM else "pickup_fish", "body", "idle")
		if tex != null:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(bob, 12.0, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.12))
			draw_texture(tex, bob - tex.get_size() * 0.5)
			return
	draw_set_transform(bob, 0.0, Vector2(2, 2))  # 2x: placeholder art stays pixel-exact
	match kind:
		Kind.KEY:
			draw_circle(Vector2(-3, 0), 3.5, c)
			draw_circle(Vector2(-3, 0), 1.2, Color("161630"))
			draw_rect(Rect2(0, -1, 7, 2), c)
			draw_rect(Rect2(4, 1, 2, 3), c)
		Kind.LETTER:
			var col := Color("ff4a3a") if _nope > 0.0 else c
			var breath := 0.5 + 0.5 * sin(_t * 2.2)
			# Emissive (HDR) so the night tint cannot bury it: a hidden letter must be findable.
			draw_circle(Vector2.ZERO, 7.0 + breath, Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, 0.22 + 0.12 * breath))
			draw_string(FONT, Vector2(-8, 5), "CAT"[letter_index], HORIZONTAL_ALIGNMENT_CENTER, 16.0, 16, Color(col.r * 1.9, col.g * 1.9, col.b * 1.9))
			_glint(Vector2(5, -6), _t, 1.0)
			_glint(Vector2(-6, 2), _t + GLINT_PERIOD * 0.5, 0.6)
		Kind.FISH:
			draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(0, -3), Vector2(5, 0), Vector2(0, 3)]), c)
			draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(9, -3), Vector2(9, 3)]), c.darkened(0.2))
			draw_rect(Rect2(-4, -1, 1, 1), Color.BLACK)
		Kind.GEM:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -5), Vector2(4, 0), Vector2(0, 5), Vector2(-4, 0)]), c)
			draw_rect(Rect2(-1, -3, 1, 2), Color(1, 1, 1, 0.8))


## A four-point twinkle that swells and fades once per GLINT_PERIOD.
func _glint(at: Vector2, t: float, strength: float) -> void:
	var ph := fmod(t, GLINT_PERIOD) / GLINT_TIME
	if ph >= 1.0:
		return
	var k := sin(ph * PI) * strength
	var r := 2.0 + 5.0 * k
	var c := Color(1.0, 0.97, 0.78, minf(k * 1.4, 1.0))
	draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), c, 1.0)
	draw_line(at + Vector2(0, -r), at + Vector2(0, r), c, 1.0)
	draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, c.a))
