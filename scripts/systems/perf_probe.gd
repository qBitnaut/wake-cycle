class_name PerfProbe
extends Node
## PERF HARNESS (investigation only, never shipped): publishes Godot's own Performance monitors to
## window.__perf twice a second and exposes window.wakeAblate(name, on) to switch one cost off at
## runtime. `pub` is the window.__pub flag: the rooms' per-frame _publish() runs only when it is set.

static var pub := false

var _cbs: Array = []
var _t := 0.0
var _win: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_win = JavaScriptBridge.get_interface("window")
	var cb := JavaScriptBridge.create_callback(func(a): _ablate(String(a[0]), bool(a[1])))
	_cbs.append(cb)
	_win["wakeAblate"] = cb


func _process(d: float) -> void:
	if _win == null:
		return
	pub = bool(JavaScriptBridge.eval("!!window.__pub"))
	_t += d
	if _t < 0.5:
		return
	_t = 0.0
	var p := {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"phys": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"mem": Performance.get_monitor(Performance.MEMORY_STATIC),
	}
	_win["__perf"] = JSON.stringify(p)


func _all(cls: String) -> Array:
	var out: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.is_class(cls) or (n.get_script() != null and n.get_script().get_global_name() == cls):
			out.append(n)
	return out


func _off(nodes: Array, on: bool) -> void:
	for n in nodes:
		n.visible = on
		n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _ablate(what: String, on: bool) -> void:
	match what:
		"rain": _off(_all("RainFX"), on)
		"splash": _off(_all("RainSplash"), on)
		"puddles": _off(_all("Puddle"), on)
		"godrays": _off(_all("MoonShaft"), on)
		"windowrain": _off(_all("WindowRain"), on)
		"fog": _off(_all("FogLayer"), on)
		"particles": _off(_all("CPUParticles2D"), on)
		"lights":
			for l in _all("PointLight2D"):
				l.visible = on
		"shadows":
			for l in _all("Light2D"):
				l.shadow_enabled = on
		"occluders":
			for o in _all("LightOccluder2D"):
				o.visible = on
		"glow":
			var we := _all("WorldEnvironment")
			for w in we:
				w.environment.glow_enabled = on
		"vignette":
			for c in _all("ColorRect"):
				if c.material is ShaderMaterial and c.material.shader.resource_path.ends_with("vignette.gdshader"):
					c.visible = on
		"audio":
			AudioServer.set_bus_mute(0, not on)
