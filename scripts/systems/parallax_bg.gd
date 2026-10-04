extends CanvasLayer
## Screen-space parallax for the industrial night skyline. Layers repeat
## horizontally, are bottom aligned and pixel snapped.

# [texture, horizontal scroll factor, vertical factor]
const LAYERS := [
	["res://assets/backgrounds/sky.png", 0.05, 0.0],
	["res://assets/backgrounds/far_buildings.png", 0.15, 0.04],
	["res://assets/backgrounds/buildings.png", 0.30, 0.08],
]

var _tex: Array = []
var _canvas := Node2D.new()
var _sky := Color("0b1a14")


func _ready() -> void:
	layer = -10
	for l in LAYERS:
		_tex.append(load(l[0]))
	_sky = (_tex[0] as Texture2D).get_image().get_pixel(0, 0)
	_canvas.draw.connect(_draw_layers)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw_layers() -> void:
	var cam := get_viewport().get_camera_2d()
	var c := cam.get_screen_center_position() if cam else Vector2.ZERO
	_canvas.draw_rect(Rect2(0, 0, 320, 180), _sky)
	for i in LAYERS.size():
		var t: Texture2D = _tex[i]
		var w := t.get_width()
		var x := -fposmod(c.x * LAYERS[i][1], w)
		var y := 180.0 - t.get_height() + 18.0 - fposmod(c.y * LAYERS[i][2], 40.0) + 20.0
		while x < 320.0:
			_canvas.draw_texture(t, Vector2(roundf(x), roundf(y)))
			x += w
