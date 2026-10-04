class_name Breakable
extends StaticBody2D
## Weak crate / cracked floor. breaks_on: "any" (shockwave or ground pound) or
## "pound" (ground pound only). Optionally drops a pickup.

const DROPS := [null, "res://scenes/actors/fish.tscn", "res://scenes/actors/gem.tscn"]

@export_enum("Any:any", "Ground pound only:pound") var breaks_on := "any"
@export_enum("None", "Fish", "Gem") var drop := 0
@export var debris_color := Color("b87a3a")

var _id := ""


## Box centre (offset from origin) and half size, used for shockwave range checks.
var shock_offset := Vector2(0, -9)
var shock_half := Vector2(9, 9)


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
	Debris.burst(get_parent(), global_position, debris_color, 10)
	if drop > 0:
		var item: Node2D = load(DROPS[drop]).instantiate()
		item.persist = false
		item.position = position
		get_parent().add_child.call_deferred(item)
	queue_free()
