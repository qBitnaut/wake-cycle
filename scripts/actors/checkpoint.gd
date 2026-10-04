class_name Checkpoint
extends Area2D
## Step on it to save (user://save.json) and set the respawn point. Drawn by a
## PadFX in its checkpoint kind (the kit's pale-teal "safe" plate): dim until
## it is the active checkpoint, and it flares when it saves.

const FONT := preload("res://assets/fonts/monogram.ttf")

@export var checkpoint_id := "cp1"

var _active := false
var _pulse := 0.0
var _fx: PadFX


func _ready() -> void:
	add_to_group("checkpoint")
	collision_layer = 32
	collision_mask = 2
	body_entered.connect(_on_body)
	# Level._enter_tree has already registered this scene with SaveSystem.
	_active = SaveSystem.session_checkpoint == checkpoint_id
	_fx = PadFX.new()
	_fx.kind = FXPalette.Pad.CHECKPOINT
	add_child(_fx)
	_fx.set_enabled(_active)


func spawn_position() -> Vector2:
	return global_position


func _on_body(body: Node) -> void:
	if not body is Cat or _active:
		return
	for cp in get_tree().get_nodes_in_group("checkpoint"):
		cp._deactivate()
	_active = true
	_pulse = 1.0
	_fx.set_enabled(true)
	_fx.pulse()
	SaveSystem.save_checkpoint(checkpoint_id, SaveSystem.session_scene)
	Sfx.play(self, "checkpoint")
	queue_redraw()


func _deactivate() -> void:
	_active = false
	if _fx:
		_fx.set_enabled(false)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 0.9, 0.0)
		queue_redraw()


func _draw() -> void:
	if _pulse > 0.0:
		var c := FXPalette.CHECKPOINT
		draw_string(FONT, Vector2(-40, -92 - 12.0 * (1.0 - _pulse)), "SAVED", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 32, Color(c, minf(_pulse * 2.0, 1.0)))
