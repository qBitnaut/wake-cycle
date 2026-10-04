extends StaticBody2D
## Two-tile door. Walk into it holding the matching key and it opens (key is used up).

@export var key_color := "brass"

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
	r.size = Vector2(40, 60)
	cs.shape = r
	cs.position = Vector2(0, -32)
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
		tw.tween_property(self, "_lift", 68.0, 0.5)
		tw.tween_callback(queue_free)
	else:
		_nope = 0.4
		Sfx.play(self, "hurt", -16.0, 0.6)


func _process(delta: float) -> void:
	_nope = maxf(_nope - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	# A 2-tile bulkhead door (32x64): ink frame, bulkhead face, key-colour bands
	# and a lock with the key colour (red only flashes on a wrong key).
	var c: Color = GameState.KEY_COLORS.get(key_color, Color.WHITE)
	var top := -64.0 - _lift
	draw_rect(Rect2(-16, top, 32, 64), Color("10121f"))
	draw_rect(Rect2(-14, top + 2, 28, 60), Color("354655"))
	draw_rect(Rect2(-14, top + 2, 28, 2), Color("536a74"))
	draw_rect(Rect2(-14, top + 2, 2, 60), Color("536a74"))
	draw_rect(Rect2(10, top + 2, 4, 60), Color("1c2c3b"))
	draw_rect(Rect2(-14, top + 8, 28, 4), c.darkened(0.3))
	draw_rect(Rect2(-14, top + 52, 28, 4), c.darkened(0.3))
	var ly := top + 32.0
	var lc := Color("ff4a3a") if _nope > 0.0 else c
	draw_rect(Rect2(-6, ly - 6, 12, 12), Color("141a2c"))
	draw_circle(Vector2(0, ly - 1), 4.0, lc)
	draw_rect(Rect2(-1, ly, 2, 5), lc)
