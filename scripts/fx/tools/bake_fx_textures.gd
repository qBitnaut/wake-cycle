## Bakes the FX textures in res://assets/fx/ so nothing is generated at load
## time on the web (a runtime NoiseTexture2D causes a first-frame hitch).
## Run: godot --headless --path . --script res://scripts/fx/tools/bake_fx_textures.gd
extends SceneTree

const OUT := "res://assets/fx/"


func _initialize() -> void:
	_noise("fog_noise.png", 256, 128, 0.018, 4, 11)
	_noise("noise_small.png", 64, 64, 0.06, 3, 23)
	_radial("light_soft.png", 128, 1.6)
	_radial("halo.png", 64, 2.4)
	_puff_sheet("puff_sheet.png", 16, [2.5, 4.0, 5.5, 7.0, 7.5])
	_cone("light_cone.png", 96, 256)
	_streak("rain_streak.png", 7)
	print("baked FX textures")
	quit()


func _save(img: Image, file: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("%s -> %s" % [file, error_string(err)])


## Tileable fractal noise, greyscale.
func _noise(file: String, w: int, h: int, freq: float, octaves: int, seed_: int) -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var img := n.get_seamless_image(w, h, false, false, 0.15, true)
	img.convert(Image.FORMAT_L8)
	_save(img, file)


## Radial falloff in RGB (alpha 1): centre 1, edge 0. `power` shapes the
## curve. RGB-encoded so it works both as a Light2D texture and additively.
func _radial(file: String, size: int, power: float) -> void:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / (size * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), power)
			img.set_pixel(x, y, Color(a, a, a, 1.0))
	_save(img, file)


## Puff animation strip: one frame per radius, same pixel size throughout, so
## particles grow by swapping frames instead of scaling (no mixels).
func _puff_sheet(file: String, frame: int, radii: Array) -> void:
	var img := Image.create_empty(frame * radii.size(), frame, false, Image.FORMAT_RGBA8)
	var c := (frame - 1) * 0.5
	for i in radii.size():
		var r: float = radii[i]
		for y in frame:
			for x in frame:
				var d := Vector2(x - c, y - c).length() / r
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = floorf(a * 3.0 + 0.6) / 3.0
				img.set_pixel(i * frame + x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_save(img, file)


## Downward light cone for shafts. Apex row is 0.6 of the bottom width (moon
## rays are nearly parallel), full on in the middle 70%, soft at the edges, and
## a gentle fall-off so the floor still gets a lit patch.
## Used as a PointLight2D texture offset so the top centre sits on the light.
func _cone(file: String, w: int, h: int) -> void:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var half := lerpf(0.3, 0.5, t) * w
		for x in w:
			var dx := absf(x - (w - 1) * 0.5) / maxf(half, 1.0)
			var edge := 1.0 - smoothstep(0.7, 1.0, dx)
			var fall := pow(1.0 - t * 0.75, 1.5) * smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.9, 1.0, t))
			var v := edge * fall
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_save(img, file)


## 1 px wide rain streak, bright head at the bottom.
func _streak(file: String, length: int) -> void:
	var img := Image.create_empty(1, length, false, Image.FORMAT_RGBA8)
	for y in length:
		var a := float(y + 1) / float(length)
		img.set_pixel(0, y, Color(1, 1, 1, a * a))
	_save(img, file)
