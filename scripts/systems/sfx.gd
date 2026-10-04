class_name Sfx
extends RefCounted
## One-shot 8-bit sound effects: Sfx.play(self, "jump").

const DIR := "res://assets/audio/sfx8bit/%s.ogg"
static var _cache := {}


## `sound` is a name in sfx8bit, or a full res:// path to any stream.
static func play(ctx: Node, sound: String, volume_db := -6.0, pitch := 1.0) -> void:
	if not _cache.has(sound):
		_cache[sound] = load(sound if sound.begins_with("res://") else DIR % sound)
	var p := AudioStreamPlayer.new()
	p.stream = _cache[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	ctx.get_tree().root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
