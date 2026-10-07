extends SitPad
## The Continue pad: teal PadFX plate under a sign naming the saved room, on the floor left
## of the wake spot in Room 1. Only exists for a resumable save (see SitPad for the shared
## rules: sit and wait 1 s, a brush-past or a short stand does nothing, walking right is
## always a new game, the first checkpoint of that new run overwrites the old save).
##
## Sitting on it for the full second loads the saved room at its checkpoint. Above it, on a
## ledge a plain jump reaches, is the Start Over pad (start_over_pad.gd). Its tease is a meow
## (the cat cannot talk before the goo wakes its mind): the voiced set below is muted by
## Monologue until then.

## Monologue set (data/monologue.json, voiced) played when the cat comes near.
const TEASE_SET := "continue_tease"


func _ready() -> void:
	super()
	sign_dx = 50.0  # clear of the Start Over pad's ring above-left
	if visible:
		sign_text = SaveSystem.saved_room_name(_save, true)


func accent() -> Color:
	return FXPalette.CHECKPOINT


func sign_lines() -> Array:
	return ["CONTINUE", sign_text]


func _tease() -> void:
	Monologue.play(TEASE_SET)


func _activate() -> void:
	Sfx.play(self, "checkpoint")
	SaveSystem.continue_game.call_deferred(self)
