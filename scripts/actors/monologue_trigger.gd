class_name MonologueTrigger
extends Area2D
## Plays a monologue set (res://data/monologue.json) the first time the cat
## walks in. Movement only: stepping into it is the whole interface.
## `require_mind` keeps it dormant until the mind has awakened (GameState
## .intelligence); a cat already standing inside when the mind awakens fires it.
## Before the mind awakens the cat has no inner voice: a trigger without `require_mind` that
## is walked into then makes the cat meow (Monologue.meow, a variant by line_id) and shows no
## text; it is spent, and does not tell its line later.
## Pacing: a FILLER set (see Monologue, "Pacing") is held back while the narrator is busy or in
## its cooldown, and the trigger stays armed while the cat stands in it, so a player who lingers
## still hears it and one who runs past does not (counted as dropped when the cat leaves).
## Origin = bottom-centre (the floor line), like the other actors.

signal triggered(id: String)

@export var line_id := ""
@export var require_mind := false
## Stay dormant until this other set has played (a hint that follows a reading).
@export var requires_played := ""
@export var size := Vector2(64, 96)

var _done := false
var _held := false  # a FILLER line was held back while the cat stood in here


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	cs.position = Vector2(0, -size.y / 2.0)
	add_child(cs)


func _physics_process(_delta: float) -> void:
	if _done or (require_mind and not GameState.intelligence):
		return
	if requires_played != "" and not Monologue.has_played(requires_played):
		return
	var inside := false
	for b in get_overlapping_bodies():
		if b is Cat and not (b as Cat).dead:
			inside = true
			if GameState.intelligence and not Monologue.has_played(line_id) and Monologue.priority_of(line_id) == Monologue.Prio.FILLER and Monologue.filler_blocked():
				_held = true
				break
			_held = false
			_done = true
			if not GameState.intelligence:
				Monologue.meow(line_id)
				triggered.emit(line_id)
			elif Monologue.play_once(line_id):
				triggered.emit(line_id)
			set_physics_process(false)
			return
	if _held and not inside:
		_held = false
		Monologue.note_filler_drop(line_id)
