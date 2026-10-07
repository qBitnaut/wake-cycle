extends Area2D
## Only exists when a valid save does (SaveSystem.has_save: a save from another build
## is discarded, so a stale one never gets a pad). Warm gold PadFX plate (nothing here
## is a power) under a sign naming the saved room.
##
## The rules, so a new game stays frictionless:
##  * It sits BEHIND the cat, left of the wake spot. Walking right (the way everyone
##    goes first) can never reach it: right always means "new game".
##  * It needs a deliberate stand: CHARGE_TIME seconds standing still on the plate (a
##    ring fills). Brushing past, or running through, only drains the ring again.
##  * It is not offered once the run is under way (a checkpoint of this session is set).
##  * Starting fresh drops the old save for good the moment the new run reaches its first
##    checkpoint: SaveSystem.save_checkpoint overwrites the file, so the pad never nags.

const FONT := preload("res://assets/fonts/monogram.ttf")
const CHARGE_TIME := 0.6
## The cat is "standing" below this speed (px/s).
const STAND_SPEED := 24.0
## The tease plays when the cat comes this close (px along x).
const TEASE_RANGE := 48.0
## Monologue set (data/monologue.json, voiced) played when the cat comes near.
const TEASE_SET := "continue_tease"

var charge := 0.0
var sign_text := ""
var _t := 0.0
var _used := false
var _teased := false
var _save := {}


func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	# The sign is HUD-like: unshaded, so the room's dark tint (CanvasModulate) does not dim it.
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	var scene := ""
	if get_parent() and get_parent().scene_file_path != "":
		scene = get_parent().scene_file_path
	_save = SaveSystem.read_save() if SaveSystem.session_checkpoint == "" else {}
	# Nothing to continue to: no save, or it is just this room's own start.
	if _save.get("scene", "") == scene and String(_save.get("checkpoint", "")) == "":
		_save = {}
	var has := not _save.is_empty()
	visible = has
	monitoring = has
	set_physics_process(has)
	if has:
		sign_text = SaveSystem.saved_room_name(_save, true)
		var fx := PadFX.new()
		fx.use_custom_color = true
		fx.custom_color = FXPalette.SODIUM
		add_child(fx)


func _physics_process(delta: float) -> void:
	if _used:
		return
	var cat := _cat()
	if cat == null:
		return
	if not _teased and cat.can_move and absf(cat.global_position.x - global_position.x) < TEASE_RANGE:
		_teased = true
		Monologue.play(TEASE_SET)
	if _standing_on(cat):
		charge = minf(charge + delta / CHARGE_TIME, 1.0)
		if charge >= 1.0:
			_used = true
			Sfx.play(self, "checkpoint")
			SaveSystem.continue_game.call_deferred(self)
	else:
		charge = maxf(charge - delta * 4.0 / CHARGE_TIME, 0.0)


func _cat() -> Cat:
	for b in get_overlapping_bodies():
		if b is Cat:
			return b
	for b in get_tree().get_nodes_in_group("player"):
		if b is Cat:
			return b
	return null


func _standing_on(cat: Cat) -> bool:
	return overlaps_body(cat) and cat.is_on_floor() and absf(cat.velocity.x) < STAND_SPEED and cat.can_move


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := FXPalette.SODIUM
	# The sign: an arrow back toward the pad and the saved room.
	var y := -86.0 - 2.0 * sin(_t * 3.0)
	var bright := c.lerp(Color.WHITE, 0.35)
	var lines := [["CONTINUE", y - 18.0, bright], [sign_text, y, Color(bright, 0.92)]]
	for l in lines:
		# A subtle glow: a faint halo of offset copies under the crisp text.
		for o in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
			draw_string(FONT, Vector2(-80, l[1]) + o, l[0], HORIZONTAL_ALIGNMENT_CENTER, 160.0, 16, Color(c, 0.22))
		draw_string(FONT, Vector2(-80, l[1]), l[0], HORIZONTAL_ALIGNMENT_CENTER, 160.0, 16, l[2])
	draw_colored_polygon(PackedVector2Array([Vector2(-6, y + 10), Vector2(6, y + 4), Vector2(6, y + 16)]), c)
	# The charge ring above the plate.
	var centre := Vector2(0, -26)
	draw_arc(centre, 12.0, 0.0, TAU, 32, Color(c, 0.25), 2.0)
	if charge > 0.0:
		draw_arc(centre, 12.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 32, c, 3.0)
