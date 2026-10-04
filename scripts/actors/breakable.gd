class_name Breakable
extends StaticBody2D
## Weak crate / cracked floor. breaks_on: "any" (shockwave or ground pound) or
## "pound" (ground pound only). Optionally drops a pickup.

const DROPS := [null, "res://scenes/actors/fish.tscn", "res://scenes/actors/gem.tscn"]

@export_enum("Any:any", "Ground pound only:pound") var breaks_on := "any"
@export_enum("None", "Fish", "Gem") var drop := 0
@export var debris_color := Color("9e5658")

var _id := ""


## Box centre (offset from origin) and half size, used for shockwave range checks.
var shock_offset := Vector2(0, -16)
var shock_half := Vector2(16, 16)


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	add_to_group("shock_receiver")
	add_to_group("breakable")
	_id = str(get_path())
	if GameState.is_collected(_id):
		queue_free()


func on_shockwave(_origin: Vector2, _radius: float, source: String) -> void:
	if breaks_on == "pound" and source != "pound":
		return
	break_it()


func break_it() -> void:
	GameState.mark_collected(_id)
	Sfx.play(self, "crate_break")
	Debris.burst(get_parent(), global_position + Vector2(0, -16), debris_color, 10)
	if drop > 0:
		var item: Node2D = load(DROPS[drop]).instantiate()
		item.persist = false
		item.position = get_parent().to_local(_floor_point())
		get_parent().add_child.call_deferred(item)
	queue_free()


## Where a drop lands: straight down from the crate to the first solid floor
## (world layer only, so the rest of a crate stack does not catch it), so a
## drop is never left floating above a cleared stack.
func _floor_point() -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -16), global_position + Vector2(0, 640))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else global_position


func _draw() -> void:
	# Cracks over the tile for a ground-pound-only floor.
	if breaks_on == "pound":
		var ink := Color("2d163a")
		draw_polyline(PackedVector2Array([Vector2(-14, -30), Vector2(-6, -22), Vector2(-9, -15), Vector2(1, -8), Vector2(-2, -2)]), ink, 2.0)
		draw_polyline(PackedVector2Array([Vector2(12, -30), Vector2(7, -21), Vector2(13, -14), Vector2(6, -6)]), ink, 2.0)
		draw_polyline(PackedVector2Array([Vector2(-6, -22), Vector2(6, -19)]), ink, 1.0)
