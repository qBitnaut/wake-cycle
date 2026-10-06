class_name KitGlow
extends AnimatedSprite2D
## Emissive overlay for a kit sprite: a child copy that shares the sprite's frames, follows
## its animation and frame, and draws only the red sensor pixels unshaded and additive
## (shaders/kit_emissive.gdshader), so eyes and lenses glow in the night ambient.
##
##     KitGlow.attach(sprite)
##
## It is a child of the sprite, so it inherits position, scale, rotation, visibility and
## modulate (a hit flash or fade dims the glow too).

const SHADER := preload("res://shaders/kit_emissive.gdshader")
static var _mat: ShaderMaterial

var src: AnimatedSprite2D


static func attach(sprite: AnimatedSprite2D, energy := -1.0) -> KitGlow:
	if sprite == null or sprite.get_node_or_null("Glow") != null:
		return null
	var g := KitGlow.new()
	g.name = "Glow"
	g.src = sprite
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	if energy > 0.0:
		g.material = _mat.duplicate()
		(g.material as ShaderMaterial).set_shader_parameter("energy", energy)
	else:
		g.material = _mat
	sprite.add_child(g)
	g.sync_to_source()
	return g


func _process(_delta: float) -> void:
	sync_to_source()


func sync_to_source() -> void:
	if src == null:
		return
	if sprite_frames != src.sprite_frames:
		sprite_frames = src.sprite_frames
	if animation != src.animation:
		animation = src.animation
	pause()
	if frame != src.frame:
		frame = src.frame
	centered = src.centered
	offset = src.offset
	flip_h = src.flip_h
	flip_v = src.flip_v
