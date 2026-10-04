class_name CatFrames
extends RefCounted
## Builds the cat's SpriteFrames from the recoloured Cat-6 sheets (50x50 frames).

const DIR := "res://assets/sprites/cat/cat_%s.png"
const FRAME := 50

# name: [sheet, fps, loop, frame indices (empty = all)]
const ANIMS := {
	"idle": ["idle", 8.0, true, []],
	"walk": ["walk", 12.0, true, []],
	"run": ["run", 15.0, true, []],
	"jump": ["run", 1.0, false, [3]],
	"fall": ["run", 1.0, false, [5]],
	"crouch": ["laying", 6.0, true, [6, 7]],
	"sit": ["sitting", 1.0, true, []],
	"sleep1": ["sleeping1", 1.0, true, []],
	"sleep2": ["sleeping2", 1.0, true, []],
	"lick1": ["licking_1", 6.0, false, []],
	"lick2": ["licking_2", 6.0, false, []],
	"itch": ["itch", 6.0, true, []],
	"meow": ["meow", 8.0, false, []],
	"stretch": ["stretching", 10.0, false, []],
}


static func build() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in ANIMS:
		var def: Array = ANIMS[anim]
		var tex: Texture2D = load(DIR % def[0])
		sf.add_animation(anim)
		sf.set_animation_speed(anim, def[1])
		sf.set_animation_loop(anim, def[2])
		var idx: Array = def[3].duplicate()
		if idx.is_empty():
			for i in int(tex.get_width() / FRAME):
				idx.append(i)
		for i in idx:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * FRAME, 0, FRAME, FRAME)
			sf.add_frame(anim, at)
	return sf
