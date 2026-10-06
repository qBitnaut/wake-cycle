class_name KitArt
extends RefCounted
## Art lookup for the actor kit. Everything visual comes from
## assets/sprites/kit/kit_manifest.json (written by tools/art/kit_art.py), so an
## art pass replaces PNGs and edits the manifest; no script changes.
##
## Manifest actor: {scale, main, pivot, bounds, parts: {name: {file, cell, pivot,
## offset, anims: {name: {frames, fps, loop}}, bounds}}}. `pivot` is the origin
## inside a cell (the feet for walkers, the centre for flyers); `bounds` is the
## union of opaque pixels relative to the origin: colliders come from it, times
## the actor's `sprite_scale`.

const MANIFEST := "res://assets/sprites/kit/kit_manifest.json"

static var _m := {}
static var _frames := {}


static func manifest() -> Dictionary:
	if _m.is_empty():
		var f := FileAccess.open(MANIFEST, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_m = parsed
	return _m


static func has_actor(id: String) -> bool:
	return manifest().get("actors", {}).has(id)


static func actor(id: String) -> Dictionary:
	return manifest().get("actors", {}).get(id, {})


static func default_scale(id: String) -> float:
	return float(actor(id).get("scale", 1.0))


static func part(id: String, part_name := "") -> Dictionary:
	var a := actor(id)
	if a.is_empty():
		return {}
	return a.parts.get(part_name if part_name != "" else a.main, {})


## Unscaled box of the actor's art, relative to its origin.
static func bounds(id: String) -> Rect2:
	var b: Array = actor(id).get("bounds", [-8, -16, 16, 16])
	return Rect2(b[0], b[1], b[2], b[3])


static func part_bounds(id: String, part_name: String) -> Rect2:
	var b: Array = part(id, part_name).get("bounds", [-8, -16, 16, 16])
	return Rect2(b[0], b[1], b[2], b[3])


static func cell(id: String, part_name := "") -> Vector2:
	var c: Array = part(id, part_name).get("cell", [32, 32])
	return Vector2(c[0], c[1])


static func frames(id: String, part_name := "") -> SpriteFrames:
	var key := "%s/%s" % [id, part_name]
	if _frames.has(key):
		return _frames[key]
	var p := part(id, part_name)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	if not p.is_empty():
		var tex: Texture2D = load("res://" + str(p.file))
		var cl: Array = p.cell
		for an: String in p.anims:
			var d: Dictionary = p.anims[an]
			sf.add_animation(an)
			sf.set_animation_speed(an, float(d.fps))
			sf.set_animation_loop(an, bool(d.loop))
			for i: int in d.frames:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * cl[0], 0, cl[0], cl[1])
				sf.add_frame(an, at)
	_frames[key] = sf
	return sf


## An AnimatedSprite2D for one part, scaled and placed so the node's origin is
## the part's pivot (plus the part's offset, scaled).
static func make_sprite(id: String, part_name := "", scale_ := 1.0) -> AnimatedSprite2D:
	var p := part(id, part_name)
	var s := AnimatedSprite2D.new()
	s.name = part_name.capitalize() if part_name != "" else "Sprite"
	s.sprite_frames = frames(id, part_name)
	s.centered = false
	if not p.is_empty():
		s.offset = -Vector2(p.pivot[0], p.pivot[1])
		s.position = Vector2(p.offset[0], p.offset[1]) * scale_
	s.scale = Vector2(scale_, scale_)
	if s.sprite_frames.has_animation(&"idle"):
		s.play(&"idle")
	elif s.sprite_frames.get_animation_names().size() > 0:
		s.play(s.sprite_frames.get_animation_names()[0])
	return s


static func frame_texture(id: String, part_name: String, anim: String, index := 0) -> Texture2D:
	var sf := frames(id, part_name)
	if sf.has_animation(anim) and sf.get_frame_count(anim) > index:
		return sf.get_frame_texture(anim, index)
	return null


static func fx(name: String) -> Dictionary:
	return manifest().get("fx", {}).get(name, {})
