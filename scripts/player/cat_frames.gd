class_name CatFrames
extends RefCounted
## Builds the cat's SpriteFrames from the recoloured Cat-6 sheets (75x75 frames: the
## 1x art at 1.5x plus a 1 px outline, see tools/art/cat_hd.py).

const DIR := "res://assets/sprites/cat/cat_%s.png"
const FRAME := 75
## Game px per pixel of the 1x Cat-6 art.
const SCALE := 1.5
## Where the Sprite sits under the cat's origin (its feet): the frames are drawn
## centred, so this puts the outline under the paws (row 48) on the floor line.
const SPRITE_Y := -12.0

## The sleeping breath (sleep_breath): rest, half in, full in, half out, in
## seconds. One breath is 4.4 s, CatAugments.sleep_period, so the emitters'
## glow can breathe with it (CatAugments.sync_breath(BREATH_PEAK)).
const BREATH := [2.4, 0.3, 1.4, 0.3]
## Seconds from the breath's start to the middle of the full in-breath.
const BREATH_PEAK := 3.4

# name: [sheet, fps, loop, frame indices (empty = all), frame durations (optional)]
const ANIMS := {
	"idle": ["idle", 8.0, true, []],
	"walk": ["walk", 12.0, true, []],
	"run": ["run", 15.0, true, []],
	"jump": ["run", 1.0, false, [3]],
	"fall": ["run", 1.0, false, [5]],
	"crouch": ["laying", 6.0, true, [6, 7]],
	# Derived poses (tools/art/cat_poses.py). Planted paws travel one 1x
	# pixel (SCALE game px) a frame in all three: speed_scale =
	# |vx| / (SCALE * fps) keeps them from sliding.
	"crawl": ["crawl", 16.0, true, []],
	"crouch_idle": ["crouch_idle", 6.0, true, []],
	"push": ["push", 9.0, true, []],
	"sit": ["sitting", 1.0, true, []],
	"sleep1": ["sleeping1", 1.0, true, []],
	"sleep2": ["sleeping2", 1.0, true, []],
	# The ending's sleep: sleeping1 with its flank rising one pixel and
	# falling again (tools/art/cat_poses.py). Whole pixels only: a scaled
	# sprite re-samples its rows and flickers.
	"sleep_breath": ["sleep_breath", 1.0, true, [0, 1, 2, 1], BREATH],
	# Seated, licking a raised front paw. The leg-up groom (licking_2) read
	# as the cat licking its crotch and is left out.
	"lick1": ["licking_1", 6.0, false, []],
	"itch": ["itch", 6.0, true, []],
	"meow": ["meow", 8.0, false, []],
	"stretch": ["stretching", 10.0, false, []],
	# The ending: from sitting down to the loaf (the laying sheet's last frames).
	"lie_down": ["laying", 5.0, false, [2, 3, 4, 5, 6, 7]],
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
		var durations: Array = def[4] if def.size() > 4 else []
		for k in idx.size():
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(idx[k] * FRAME, 0, FRAME, FRAME)
			sf.add_frame(anim, at, durations[k] if k < durations.size() else 1.0)
	return sf
