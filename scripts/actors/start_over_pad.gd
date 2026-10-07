extends SitPad
## The Start Over pad: a warm red-orange plate on a small ledge ABOVE the Continue pad
## (a plain jump from the wake spot; the cat has no powers yet). Only exists for a
## resumable save, like the Continue pad (see SitPad for the shared rules: sit and wait
## 1 s, a brush-past or a short stand does nothing).
##
## Sitting on it for the full second wipes the save completely (SaveSystem.start_over: no
## abilities, no map progress, score 0, nothing collected, no pending memory), the cat
## meows (it cannot talk yet, so never a monologue line), a warm flash fades over the room
## and Room 1 reloads as a new game from the wake spot (no second intro: the player just
## watched it). Both pads are gone afterwards, since there is no save.


func accent() -> Color:
	return FXPalette.START_OVER


func sign_lines() -> Array:
	return ["START OVER", "forget this save"]


func _tease() -> void:
	Monologue.meow("startover_tease")


func _activate() -> void:
	Sfx.play(self, "checkpoint")
	SaveSystem.start_over()  # resets the Monologue, so the meow comes after it
	Monologue.meow("startover")
	RoomTransition.restart(self)
