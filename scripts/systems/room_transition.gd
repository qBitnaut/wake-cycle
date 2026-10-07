class_name RoomTransition
extends RefCounted
## Room to room: fade to black, load the next scene, fade up from black.
## The new Level sees `arriving` and auto-saves at its start (Level._ready).

const FADE := 0.7

## True between leaving one room and the next Level finishing its _ready.
static var arriving := false
static var _busy := false
## Set by continue_to: the next Level's fade_in shows this room-name title card.
static var pending_title := ""
static var pending_label := ""

const FONT := preload("res://assets/fonts/monogram.ttf")
const TITLE_HOLD := 1.0


## Fade `from` to black, then load `scene_path`. Safe to call twice.
static func go(from: Node, scene_path: String, fade := FADE) -> void:
	if _busy:
		return
	_busy = true
	var tree := from.get_tree()
	var layer := _black_layer(from)
	var rect: ColorRect = layer.get_child(0)
	var tw := layer.create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, fade)
	await tw.finished
	arriving = true
	_busy = false
	tree.change_scene_to_file(scene_path)


## Continue: fade to black, load the saved room (NOT `arriving`: the save must not be
## overwritten with the room start) and show its name while it fades back up.
static func continue_to(from: Node, scene_path: String, title: String, label := "") -> void:
	if _busy:
		return
	_busy = true
	var tree := from.get_tree()
	var layer := _black_layer(from)
	var rect: ColorRect = layer.get_child(0)
	var tw := layer.create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, FADE)
	await tw.finished
	pending_title = title
	pending_label = label
	_busy = false
	tree.change_scene_to_file(scene_path)


## Fade up from black over `level` (call on arrival). After a Continue the black holds
## for a beat with the room's name on it.
static func fade_in(level: Node, fade := FADE) -> void:
	var layer := _black_layer(level)
	var rect: ColorRect = layer.get_child(0)
	rect.modulate.a = 1.0
	var tw := layer.create_tween()
	if pending_title != "":
		var card := _title_card(layer, pending_title, pending_label)
		pending_title = ""
		pending_label = ""
		card.modulate.a = 0.0
		tw.tween_property(card, "modulate:a", 1.0, 0.25)
		tw.tween_interval(TITLE_HOLD)
		tw.tween_property(card, "modulate:a", 0.0, 0.25)
	tw.tween_property(rect, "modulate:a", 0.0, fade)
	tw.tween_callback(layer.queue_free)


static func _title_card(layer: CanvasLayer, title: String, label: String) -> Control:
	var box := VBoxContainer.new()
	box.name = "TitleCard"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line in [[label, 16], [title, 32]]:
		if line[0] == "":
			continue
		var l := Label.new()
		l.text = line[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", FONT)
		l.add_theme_font_size_override("font_size", line[1])
		l.add_theme_color_override("font_color", FXPalette.SODIUM)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	layer.add_child(box)
	return box


static func _black_layer(host: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "RoomFade"
	layer.layer = 110
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.modulate.a = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	host.add_child(layer)
	return layer
