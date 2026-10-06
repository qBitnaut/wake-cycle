class_name CameraZone
extends Node2D
## A region that takes over the camera while the cat is inside (Secret Agent style
## framing). `position` is the top-left of the trigger and `size` its extent, as
## RoomExit's size; there is no collision shape, the camera driver tests the cat's position. While the cat is in the zone:
##   * the camera limits become `camera_rect()` (default: the trigger rect itself), and
##   * with `lock_framing`, the view centre is held on the middle of that rect, so a
##     rect exactly one screen (640x360) is a fixed single-screen frame (a puzzle).
## Zones overlap freely: the highest `zone_priority` wins, the latest entered among equals.
## Limits and framing ease over a few frames; leaving restores the level's.
## Needs a Level ancestor.

@export var size := Vector2(640, 360)
## World rect for the camera limits (position and size). Zero size: use the trigger rect.
@export var limits_override := Rect2i()
@export var lock_framing := false
@export var zone_priority := 0



func _ready() -> void:
	add_to_group("camera_zone")


## World rect of the trigger.
func trigger_rect() -> Rect2i:
	return Rect2i(Vector2i(global_position.round()), Vector2i(size))


func camera_rect() -> Rect2i:
	return limits_override if limits_override.size != Vector2i.ZERO else trigger_rect()


## True while the cat's body centre is inside the trigger (the driver polls this each physics
## frame: no physics-engine overlap events, so no spurious enter at spawn).
func holds(world_point: Vector2) -> bool:
	return Rect2(trigger_rect()).has_point(world_point)
