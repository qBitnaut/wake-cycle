## Scale study harness (scratch, not a test). Renders the same Room 1 slice
## under a scale variant and grabs what the WINDOW presents (ImageMagick
## `import -window root`, so the integer or fractional blit is in the shot).
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --fixed-fps 30 --resolution 1920x1080 --position 0,0 \
##     --script res://tools/scale/mock.gd -- --skip-intro <A|B|C|D> <out_prefix> [still|strip]
## A as is (640x360 integer). B tighter sprites (cat 1.5x, robots and props 2/3,
## from tools/scale/repixel.py). C 800x450 fractional, current sprites. D = B + C.
## SCALE_LIMITS=asis keeps the room's camera limits (one 360 px screen tall).
extends SceneTree

const ART := "res://tools/scale/art/"
const CAT_X := 1520.0
const BOT_X := 1626.0
const MECH_X := 1784.0
const DRONE := Vector2(1690, 206)

var _variant := "A"
var _prefix := ""
var _mode := "still"
var _room: Node
var _cat: Node2D
var _n := 0
var _shots: Array = []


func _initialize() -> void:
	var rest: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			rest.append(a)
	_variant = rest[0]
	_prefix = rest[1]
	_mode = rest[2] if rest.size() > 2 else "still"
	var wide := _variant in ["C", "D"]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(800, 450) if wide else Vector2i(640, 360)
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL if wide else Window.CONTENT_SCALE_STRETCH_INTEGER
	_shots = [60] if _mode == "still" else range(50, 74)
	_start.call_deferred()


func _start() -> void:
	root.get_node("SaveSystem").delete_save()
	_room = load("res://scenes/levels/room1.tscn").instantiate()
	root.add_child(_room)
	current_scene = _room
	_cat = _room.get_node("Cat")


func _setup() -> void:
	var tight := _variant in ["B", "D"]
	_cat.global_position = Vector2(CAT_X, 320)
	_cat.velocity = Vector2.ZERO
	var bot = _room.get_node("Bot")
	bot.global_position = Vector2(BOT_X, 320)
	bot.set("speed", 0.0)
	bot.set("dir", -1)
	var mech := AnimatedSprite2D.new()
	mech.z_index = 3
	mech.flip_h = true
	_room.add_child(mech)
	var drone := Sprite2D.new()
	drone.z_index = 3
	_room.add_child(drone)
	if tight:
		_cat_frames(_cat.get_node("Sprite"))
		var bs: AnimatedSprite2D = bot.get_node("Sprite")
		bs.sprite_frames = _frames(ART + "bipedal_23.png", Vector2i(53, 42), 9.0)
		bs.play("default")
		bs.centered = false
		bs.position = Vector2.ZERO
		bs.offset = Vector2(-26, -42)
		mech.sprite_frames = _frames(ART + "mech_23.png", Vector2i(64, 53), 8.0)
		mech.offset = Vector2(-32, -53)
		drone.texture = _tex(ART + "drone_1_23.png")
		_tight_props()
	else:
		mech.sprite_frames = _frames("res://assets/art_hd/robots/mech.png", Vector2i(96, 80), 8.0)
		mech.offset = Vector2(-48, -80)
		drone.texture = load("res://assets/art_hd/robots/drone_1.png")
	mech.centered = false
	mech.position = Vector2(MECH_X, 320)
	mech.play("default")
	drone.centered = false
	drone.position = DRONE - (drone.texture.get_size() * 0.5).floor()
	if OS.get_environment("SCALE_LIMITS") != "asis" and root.content_scale_size.y > 360:
		# A taller view than the room: centre the room's 360 px band in it.
		var cam: Camera2D = _cat.get_node("Camera")
		var extra := (root.content_scale_size.y - 360) / 2
		cam.limit_top -= extra
		cam.limit_bottom += extra
	if _mode == "strip":
		bot.global_position = Vector2(2400, 320)  # out of the cat's way: a clean, steady pan
		Input.action_press("move_right")


func _cat_frames(sprite: AnimatedSprite2D) -> void:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in CatFrames.ANIMS:
		var def: Array = CatFrames.ANIMS[anim]
		var tex := _tex(ART + "cat15_%s.png" % def[0])
		sf.add_animation(anim)
		sf.set_animation_speed(anim, def[1])
		sf.set_animation_loop(anim, def[2])
		var idx: Array = def[3].duplicate()
		if idx.is_empty():
			for i in int(tex.get_width() / 75):
				idx.append(i)
		for i in idx:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 75, 0, 75, 75)
			sf.add_frame(anim, at)
	var anim_now := sprite.animation
	sprite.sprite_frames = sf
	sprite.play(anim_now)
	# 75 px frame, feet on row 48 (the 100 px frame had them on row 64).
	sprite.centered = false
	sprite.position = Vector2.ZERO
	sprite.offset = Vector2(-38, -49)


func _tight_props() -> void:
	for p: Variant in _room.get_node("Props").get_children():
		if not (p is Sprite2D) or p.texture == null:
			continue
		var stem: String = p.texture.resource_path.get_file().get_basename()
		var path := ART + stem + "_23.png"
		if not FileAccess.file_exists(path):
			continue
		var old: Vector2 = p.texture.get_size()
		var t := _tex(path)
		var nw: Vector2 = t.get_size()
		p.texture = t
		p.position += Vector2(roundf((old.x - nw.x) * 0.5), old.y - nw.y)


func _frames(path: String, cell: Vector2i, fps: float) -> SpriteFrames:
	var tex: Texture2D = _tex(path) if path.begins_with(ART) else load(path)
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", fps)
	for i in int(tex.get_width() / cell.x):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * cell.x, 0, cell.x, cell.y)
		sf.add_frame("default", at)
	return sf


func _tex(path: String) -> Texture2D:
	return ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path)))


func _process(_d: float) -> bool:
	if _room == null:
		return false
	_n += 1
	if _n == 20:
		_setup()
	if _n in _shots:
		var tag := "%s_%04d" % [_prefix, _n] if _mode == "strip" else _prefix
		root.get_texture().get_image().save_png(tag + "_internal.png")
		OS.execute("import", ["-window", "root", tag + "_window.png"])
		print("SHOT ", tag)
	if _n >= _shots.max():
		quit()
	return false
