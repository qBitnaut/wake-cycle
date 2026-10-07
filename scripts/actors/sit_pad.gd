class_name SitPad
extends Area2D
## Base of the two pads in Room 1's opening that exist only for a returning player: the
## Continue pad (teal) and the Start Over pad (warm red-orange, on a ledge above it).
## Neither exists unless a resumable save does (SaveSystem.has_save: a save from another
## build is discarded, so a stale one never gets a pad; a save that is just this room's own
## start is not resumable either), and neither exists once the run is under way (a
## checkpoint of this session is set) or after the game is completed (that clears the save).
##
## The shared rules, so a new game stays frictionless and neither pad fires by accident:
##  * The cat must SIT AND WAIT: stand still on the plate for CHARGE_TIME (1.0 s). The
##    moment it stands still it auto-plays its sit animation and a ring fills over the
##    second. Moving off, jumping or running through only drains the ring (4x faster than
##    it fills), so a brush-past or a short stand never triggers.
##  * Walking right (the way everyone goes first) never reaches either pad: both sit left
##    of / above the wake spot, and walking right always means "new game" (the first
##    checkpoint of the new run overwrites the old save).
##  * Before the mind wakes the cat cannot talk, so a pad's tease is a meow, never a
##    monologue line. The signs are world text and stay.
## Subclasses give the colour, the sign and what happens (`_activate`).

const FONT := preload("res://assets/fonts/monogram.ttf")
const CHARGE_TIME := 1.0
## The cat is "standing" below this speed (px/s).
const STAND_SPEED := 24.0
## The tease plays when the cat comes this close (px along x).
const TEASE_RANGE := 48.0

var charge := 0.0
var sign_text := ""
## The sign's text is shifted this far sideways (px); the arrow stays over the pad.
var sign_dx := 0.0
var _t := 0.0
var _used := false
var _teased := false
var _save := {}


## The colour of the plate, the sign and the ring.
func accent() -> Color:
	return FXPalette.CHECKPOINT


## [[text, y offset, is_title]]: the sign's lines above the pad.
func sign_lines() -> Array:
	return []


## The cat sat and waited: do it.
func _activate() -> void:
	pass


## The cat came near: a meow or a line.
func _tease() -> void:
	pass


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
		var fx := PadFX.new()
		fx.use_custom_color = true
		fx.custom_color = accent()
		add_child(fx)


func _exit_tree() -> void:
	var cat := get_tree().get_first_node_in_group("player") as Cat if is_inside_tree() else null
	if cat != null:
		cat.hold_sit(self, false)


func _physics_process(delta: float) -> void:
	if _used:
		return
	var cat := _cat()
	if cat == null:
		return
	if not _teased and cat.can_move and absf(cat.global_position.x - global_position.x) < TEASE_RANGE \
			and absf(cat.global_position.y - global_position.y) < 80.0:
		_teased = true
		_tease()
	var stand := _standing_on(cat)
	cat.hold_sit(self, stand)
	if stand:
		charge = minf(charge + delta / CHARGE_TIME, 1.0)
		if charge >= 1.0:
			_used = true
			cat.hold_sit(self, false)
			_activate()
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
	var c := accent()
	var y := -86.0 - 2.0 * sin(_t * 3.0)
	var bright := c.lerp(Color.WHITE, 0.35)
	var lines := sign_lines()
	for i in lines.size():
		var ly := y - 18.0 * (lines.size() - 1 - i)
		var col := bright if i == 0 else Color(bright, 0.92)
		# A subtle glow: a faint halo of offset copies under the crisp text.
		for o in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
			draw_string(FONT, Vector2(-80 + sign_dx, ly) + o, lines[i], HORIZONTAL_ALIGNMENT_CENTER, 160.0, 16, Color(c, 0.22))
		draw_string(FONT, Vector2(-80 + sign_dx, ly), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 160.0, 16, col)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, y + 10), Vector2(6, y + 4), Vector2(6, y + 16)]), c)
	# The charge ring above the plate.
	var centre := Vector2(0, -26)
	draw_arc(centre, 12.0, 0.0, TAU, 32, Color(c, 0.25), 2.0)
	if charge > 0.0:
		draw_arc(centre, 12.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 32, c, 3.0)
