class_name MirrorBot
extends CharacterBody2D
## A dormant loader bot that takes the augmented cat for its supervisor. It
## wakes when the cat comes within `wake_range` (and the mind is awake), then
## mirrors the cat's horizontal movement: it copies the cat's horizontal
## velocity (so it walks the same way at the same speed, and stops when the cat
## stops). It ignores jumps and never hurts. Movement-input-only: the cat's own
## walking is the whole interface.
##
## It lives on its own platform or track: world walls (or a wall of the track)
## stop it, so a bot pinned against the end of its track keeps its place while
## the cat walks on. Walking the other way always brings it back, so a puzzle
## built from it cannot soft-lock. It counts as a weight for FloorPlate (group
## "pushable"; its physics layer is 2 so the plate's mask sees it, and the cat,
## whose mask is 1 and 5, walks through it). Origin = the floor under its feet.
##
## API
##   wake_range, wake_dy  distances (px) at which the augmented cat wakes it
##   follow_scale         1.0 = same speed as the cat; negative = mirror image
##   mirror_cat           false freezes it (a puzzle can lock it)
##   awake, woke          state, and the signal when it wakes
##   reset()              back to its start, dormant

signal woke

const SHEET := preload("res://assets/art_hd/robots/mech.png")
const FRAME := Vector2i(96, 80)
const FRAMES := 10
const HALO := preload("res://assets/fx/halo.png")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const ASLEEP := Color(0.34, 0.37, 0.52)
const AWAKE := Color(0.62, 0.66, 0.84)
const STRIDE := 10.0   ## px travelled per animation frame

@export var wake_range := 150.0
@export var wake_dy := 300.0
@export var follow_scale := 1.0
@export var accel := 2600.0
@export var mirror_cat := true

var awake := false
var wake := 0.0          ## 0 asleep .. 1 awake (audit / look)
var eye_color := Color(FXPalette.LASER)

var _cat: Cat
var _home := Vector2.ZERO
var _sprite: Sprite2D
var _atlas: AtlasTexture
var _halo: Sprite2D
var _light: PointLight2D
var _walk := 0.0
var _flicker := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	add_to_group("pushable")
	add_to_group("mirror_bot")
	_home = global_position
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(40, 66)
	cs.shape = r
	cs.position = Vector2(0, -33)
	add_child(cs)
	_atlas = AtlasTexture.new()
	_atlas.atlas = SHEET
	_atlas.region = Rect2(0, 0, FRAME.x, FRAME.y)
	_sprite = Sprite2D.new()
	_sprite.texture = _atlas
	_sprite.centered = false
	_sprite.position = Vector2(-FRAME.x / 2.0, -FRAME.y)
	_sprite.self_modulate = ASLEEP
	z_index = 1
	add_child(_sprite)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_halo = Sprite2D.new()
	_halo.texture = HALO
	_halo.scale = Vector2(0.7, 0.7)
	_halo.position = Vector2(0, -55)
	_halo.material = add
	add_child(_halo)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 1.0
	_light.position = Vector2(0, -52)
	_light.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(_light)
	_apply(0.0)


func reset() -> void:
	global_position = _home
	velocity = Vector2.ZERO
	awake = false
	wake = 0.0
	_apply(0.0)


func _emitter_color() -> Color:
	var aug := _cat.get_node_or_null("Sprite/Augments") as CatAugments
	return aug.emitter_color() if aug else FXPalette.INDICATOR


func _physics_process(delta: float) -> void:
	_t += delta
	if _cat == null:
		_cat = get_tree().get_first_node_in_group("player") as Cat
		return
	if not awake:
		var d := _cat.global_position - global_position
		if GameState.intelligence and not _cat.dead and absf(d.x) < wake_range and absf(d.y) < wake_dy:
			awake = true
			_flicker = 0.9
			Sfx.play(self, "power_up", -12.0, 2.0)
			woke.emit()
	var want := 0.0
	if awake:
		wake = move_toward(wake, 1.0, delta * 2.5)
		if mirror_cat and not _cat.dead:
			want = _cat.velocity.x * follow_scale
	velocity.x = move_toward(velocity.x, want, accel * delta)
	velocity.y = minf(velocity.y + 1600.0 * delta, 533.0)
	var x0 := global_position.x
	move_and_slide()
	if global_position.y > _home.y + 800.0:
		reset()  # fail-safe: never lost off its track
	_walk += absf(global_position.x - x0)
	if absf(velocity.x) > 8.0:
		_sprite.flip_h = velocity.x < 0.0
	_atlas.region = Rect2((int(_walk / STRIDE) % FRAMES) * FRAME.x if absf(velocity.x) > 8.0 else 0, 0, FRAME.x, FRAME.y)
	_apply(delta)


func _apply(delta: float) -> void:
	eye_color = FXPalette.LASER.lerp(_emitter_color(), clampf(wake * 1.4, 0.0, 1.0)) if _cat else FXPalette.LASER
	var level := lerpf(0.12, 1.0, wake)
	if _flicker > 0.0:
		_flicker = maxf(_flicker - delta, 0.0)
		level *= 0.1 if fmod(_flicker * 14.0, 1.0) < 0.5 else 1.0
	elif not awake:
		level *= 0.8 + 0.2 * sin(_t * 1.7)
	_halo.modulate = Color(eye_color * 0.9 * level, 1.0)
	_light.color = eye_color
	_light.energy = 0.9 * level
	_sprite.self_modulate = ASLEEP.lerp(AWAKE, wake)
