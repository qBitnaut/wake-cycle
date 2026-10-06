class_name KitWall
extends StaticBody2D
## Destructible wall (a stack of `size_tiles` 32 px tiles), three kinds:
##   CRACKED     the shockwave, the ground pound or a blast breaks it
##   REINFORCED  the ground pound only (stomps, the shockwave and blasts just ring off)
##   BLAST       an explosive barrel's blast only
## A wrong hit gives a clank, a flash and sparks, so the player learns what it wants.
## Breaking it: debris, a puff, a shake, and optionally the `reward` item. Origin =
## the middle of the base. `persist` keeps a broken wall gone after a respawn.

enum Kind { CRACKED, REINFORCED, BLAST }

@export var kind: Kind = Kind.CRACKED
@export var size_tiles := Vector2i(1, 2)
@export var persist := true
## Spawn a Collectible when it breaks (-1 none; otherwise a Collectible.Kind).
@export var reward := -1

var broken := false
var shock_offset := Vector2.ZERO
var shock_half := Vector2.ZERO
var _id := ""
var _flash := 0.0
var _aid := ""
var _tex: Texture2D
var _tile := 32.0


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	add_to_group("shock_receiver")
	add_to_group("breakable")
	add_to_group("blast_receiver")
	add_to_group("kit_wall")
	_aid = ["wall_cracked", "wall_reinforced", "wall_blast"][kind]
	_tex = KitArt.frame_texture(_aid, "", "idle")
	var w := size_tiles.x * _tile
	var h := size_tiles.y * _tile
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(w, h)
	cs.shape = sh
	cs.position = Vector2(0, -h * 0.5)
	add_child(cs)
	shock_offset = Vector2(0, -h * 0.5)
	shock_half = Vector2(w, h) * 0.5
	if persist:
		_id = str(get_path())
		if GameState.is_collected(_id):
			queue_free()


## Does a hit from `source` ("shock", "pound", "blast", "stomp") break this wall?
func breaks_with(source: String) -> bool:
	match kind:
		Kind.CRACKED:
			return source in ["shock", "pound", "blast"]
		Kind.REINFORCED:
			return source == "pound"
		Kind.BLAST:
			return source == "blast"
	return false


func on_shockwave(_origin: Vector2, _radius: float, source: String) -> void:
	_hit(source)


func on_blast(_origin: Vector2, _radius: float) -> void:
	_hit("blast")


func _hit(source: String) -> void:
	if broken:
		return
	if breaks_with(source):
		break_it()
	else:
		_flash = 0.2
		KitSfx.play(self, "wall_clank")
		Debris.burst(get_parent(), to_global(shock_offset), Color(1.0, 0.85, 0.5), 3)


func break_it() -> void:
	if broken:
		return
	broken = true
	if persist:
		GameState.mark_collected(_id)
	KitSfx.play(self, "wall_break")
	var c := to_global(shock_offset)
	ExplosionFX.spawn(get_parent(), c, 0.25 * float(size_tiles.y) + 0.35, 0, Color(0.6, 0.45, 0.45), true)
	Debris.burst(get_parent(), c, Color(0.62, 0.38, 0.4), 12)
	if reward >= 0:
		var item := Collectible.new()
		item.kind = reward
		item.persist = false
		KitUtil.add_at(get_parent(), item, global_position + Vector2(0, -16), true)
	queue_free()


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var m := Color(2.0, 2.0, 2.2) if _flash > 0.0 and int(_flash * 40.0) % 2 == 0 else Color.WHITE
	for ty in size_tiles.y:
		for tx in size_tiles.x:
			var p := Vector2(-size_tiles.x * _tile * 0.5 + tx * _tile, -(ty + 1) * _tile)
			draw_texture(_tex, p, m)
