## Day-1 check: does WorldEnvironment glow (background mode Canvas) work with
## hdr_2d on this renderer? Measures the halo around an HDR-bright square with
## glow on, then off, and prints one GLOW_TEST line for the console.
extends Node2D

@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _hdr: ColorRect = $HDRSquare
@onready var _sdr: ColorRect = $SDRSquare
@onready var _label: Label = $Label

var _frame := 0
var _on := {}


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 20:
		_on = _measure()
		_env.environment.glow_enabled = false
	elif _frame == 40:
		var off := _measure()
		_env.environment.glow_enabled = true
		var gain: float = _on["hdr_halo"] - off["hdr_halo"]
		var works := gain > 0.02
		var line := "GLOW_TEST renderer=%s hdr_2d=%s halo_on=%.3f halo_off=%.3f gain=%.3f sdr_halo_on=%.3f grey50=%.3f result=%s" % [
			RenderingServer.get_current_rendering_method(),
			get_viewport().use_hdr_2d, _on["hdr_halo"], off["hdr_halo"], gain,
			_on["sdr_halo"], _on["grey"], "GLOW_WORKS" if works else "GLOW_MISSING"]
		print(line)
		_label.text = "GLOW %s" % ("WORKS" if works else "MISSING")


func _measure() -> Dictionary:
	var img := get_viewport().get_texture().get_image()
	var hdr_c := Vector2i(_hdr.position + _hdr.size * 0.5)
	var sdr_c := Vector2i(_sdr.position + _sdr.size * 0.5)
	return {
		"hdr_halo": _ring(img, hdr_c, int(_hdr.size.x * 0.5) + 4),
		"sdr_halo": _ring(img, sdr_c, int(_sdr.size.x * 0.5) + 4),
		"grey": img.get_pixelv(Vector2i($Grey.position) + Vector2i(2, 2)).r,
	}


func _ring(img: Image, c: Vector2i, r: int) -> float:
	var s := 0.0
	for p in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
		s += img.get_pixelv(c + p).get_luminance()
	return s / 4.0
