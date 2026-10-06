class_name KitShutter
extends Shutter
## A roller shutter that starts OPEN and rolls shut for a while when an alarm calls
## `close_for(seconds)` (a SecurityCamera does), then rolls back up. Origin = the
## middle of the base, like Shutter.

var closed_left := 0.0


func _ready() -> void:
	super()
	open = true
	add_to_group("alarm_shutter")


func close_for(seconds: float) -> void:
	closed_left = maxf(closed_left, seconds)
	if open:
		open = false
		KitSfx.play(self, "wall_clank", -4.0, 0.8)
		state_changed.emit(open)


func _on_controller(_active: bool) -> void:
	pass


func _physics_process(delta: float) -> void:
	if closed_left > 0.0:
		closed_left -= delta
		if closed_left <= 0.0:
			open = true
			state_changed.emit(open)
	super(delta)
