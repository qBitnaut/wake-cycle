class_name CatOverlay
extends AnimatedSprite2D
## A sprite that mirrors the cat's AnimatedSprite2D frame for frame, drawing
## a parallel sheet (same 100x100 frame grid) through its own material. Used
## by CatNanotech (goo and veins) and CatAugments (metal and emitters).
##
## Add it as a child of the source sprite so it inherits the sprite's
## position, squash and spin; it copies the animation, frame, flip, offset
## and light mask every time they change. Animations whose sheet is missing
## from the parallel set simply hide the overlay.

var source: AnimatedSprite2D
## Off hides the overlay regardless of the animation (the owner's switch).
var active := true:
	set(v):
		active = v
		sync()

static var _cache := {}


## SpriteFrames for every CatFrames animation, read from `pattern` (e.g.
## "res://assets/fx/cat_nano/nano_%s.png"). `rows` > 1 means the sheet
## stacks extra data under the frames (augment sheets have 2); regions cover
## the top row only. Cached per pattern.
static func frames_from(pattern: String, rows := 1) -> SpriteFrames:
	if _cache.has(pattern):
		return _cache[pattern]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in CatFrames.ANIMS:
		var def: Array = CatFrames.ANIMS[anim]
		var path := pattern % def[0]
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex.get_height() != CatFrames.FRAME * rows:
			continue
		sf.add_animation(anim)
		sf.set_animation_speed(anim, def[1])
		sf.set_animation_loop(anim, def[2])
		var idx: Array = def[3].duplicate()
		if idx.is_empty():
			for i in int(tex.get_width() / CatFrames.FRAME):
				idx.append(i)
		for i in idx:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * CatFrames.FRAME, 0, CatFrames.FRAME, CatFrames.FRAME)
			sf.add_frame(anim, at)
	_cache[pattern] = sf
	return sf


## [sheet name, frame index in that sheet] for what `spr` shows now, or []
## if the animation is not one of CatFrames'.
static func sheet_frame(spr: AnimatedSprite2D) -> Array:
	if not CatFrames.ANIMS.has(spr.animation):
		return []
	var def: Array = CatFrames.ANIMS[spr.animation]
	var idx: Array = def[3]
	return [def[0], idx[spr.frame] if spr.frame < idx.size() else spr.frame]


## A point in frame pixels (100x100, top-left origin) to `spr`'s local
## space, honouring offset and flip.
static func frame_to_local(spr: AnimatedSprite2D, p: Vector2) -> Vector2:
	var half := CatFrames.FRAME * 0.5
	var l := p - Vector2(half, half)
	if spr.flip_h:
		l.x = -l.x
	if spr.flip_v:
		l.y = -l.y
	return l + spr.offset


static func make(src: AnimatedSprite2D, frames: SpriteFrames, mat: Material, node_name: String) -> CatOverlay:
	var o := CatOverlay.new()
	o.name = node_name
	o.source = src
	o.sprite_frames = frames
	o.material = mat
	return o


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if source:
		source.frame_changed.connect(sync)
		source.animation_changed.connect(sync)
	sync()


func _process(_delta: float) -> void:
	# Flip and offset change without a signal; frames are synced by signal.
	if source and (flip_h != source.flip_h or offset != source.offset):
		sync()


func sync() -> void:
	if source == null or sprite_frames == null:
		return
	flip_h = source.flip_h
	flip_v = source.flip_v
	offset = source.offset
	centered = source.centered
	light_mask = source.light_mask
	var anim := source.animation
	visible = active and sprite_frames.has_animation(anim)
	if not visible:
		return
	if animation != anim:
		animation = anim
	frame = mini(source.frame, sprite_frames.get_frame_count(anim) - 1)
