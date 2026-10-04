extends StaticBody2D
## Two-tile door. Walk into it holding the matching key and it opens (key is used up).

@export var key_color := "red"

var _open := false
var _lift := 0.0
var _nope := 0.0
var _id := ""


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_id = str(get_path())
	if GameState.is_collected(_id):
		queue_free()
		return
	var s := Area2D.new()
	s.collision_layer = 0
	s.collision_mask = 2
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(22, 32)
	cs.shape = r
	cs.position = Vector2(0, -18)
	s.add_child(cs)
	add_child(s)
	s.body_entered.connect(_on_body)


func _on_body(body: Node) -> void:
	if _open or not body is Cat:
		return
	if GameState.use_key(key_color):
		_open = true
		GameState.mark_collected(_id)
		Sfx.play(self, "door")
		$Shape.set_deferred("disabled", true)
		var tw := create_tween()
		tw.tween_property(self, "_lift", 38.0, 0.5)
		tw.tween_callback(queue_free)
	else:
		_nope = 0.4
		Sfx.play(self, "hurt", -16.0, 0.6)


func _process(delta: float) -> void:
	_nope = maxf(_nope - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var c: Color = GameState.KEY_COLORS.get(key_color, Color.WHITE)
	var top := -36.0 - _lift
	draw_rect(Rect2(-8, top, 16, 36), Color("2a3340"))
	draw_rect(Rect2(-8, top, 16, 2), c)
	draw_rect(Rect2(-8, top + 34, 16, 2), c)
	draw_rect(Rect2(-8, top, 2, 36), c.darkened(0.3))
	draw_rect(Rect2(6, top, 2, 36), c.darkened(0.3))
	var ly := top + 18.0
	var lc := Color("ff5a5a") if _nope > 0.0 else c
	draw_circle(Vector2(0, ly), 3.0, lc)
	draw_rect(Rect2(-1, ly, 2, 5), lc)
