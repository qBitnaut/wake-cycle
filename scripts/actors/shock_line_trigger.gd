class_name ShockLineTrigger
extends MonologueTrigger
## A MonologueTrigger that stays dormant until the shockwave is unlocked: the
## words after the conduit, which only the cat that has just been charged says.


func _physics_process(delta: float) -> void:
	if not GameState.shockwave_unlocked:
		return
	super(delta)
