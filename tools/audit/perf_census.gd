## Perf census: counts what each level puts on screen (lights, shadows, occluders, particles,
## screen-texture shaders). godot --headless --path . --script res://tools/audit/perf_census.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for lv in ["room1", "room2", "room3", "room4", "home"]:
		root.get_node("GameState").intelligence = true
		var room: Node = load("res://scenes/levels/%s.tscn" % lv).instantiate()
		root.add_child(room)
		await process_frame
		await process_frame
		var c := {}
		var parts := 0
		var lights: Array = []
		var shaders := {}
		var stack: Array = [room]
		var total := 0
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			total += 1
			var k := n.get_class()
			if n.get_script() != null and n.get_script().get_global_name() != "":
				k = n.get_script().get_global_name()
			c[k] = int(c.get(k, 0)) + 1
			if n is CPUParticles2D:
				parts += n.amount
				print("  particles ", n.get_path(), " amount=", n.amount, " lifetime=", n.lifetime, " emitting=", n.emitting, " lit=", n.light_mask)
			if n is ColorRect and not (n is Puddle):
				var cr := n as ColorRect
				print("  rect ", n.get_path(), " size=", cr.size, " mat=", (cr.material.shader.resource_path.get_file() if cr.material is ShaderMaterial else "-"), " lm=", cr.light_mask, " vis=", cr.visible)
			if n is Light2D:
				var e: float = n.energy
				lights.append("%s %s shadow=%s e=%.2f scale=%s" % [n.get_path(), n.get_class(), n.shadow_enabled, e, n.get("texture_scale")])
			if n is CanvasItem and (n as CanvasItem).material is ShaderMaterial:
				var sh: Shader = ((n as CanvasItem).material as ShaderMaterial).shader
				if sh:
					var p := sh.resource_path.get_file()
					shaders[p] = int(shaders.get(p, 0)) + 1
					if sh.code.contains("hint_screen_texture"):
						shaders[p + " [SCREEN]"] = int(shaders.get(p + " [SCREEN]", 0)) + 1
		print("==== ", lv, " nodes=", total, " cpu_particles_total=", parts)
		print("  classes: ", c)
		print("  shaders: ", shaders)
		for l in lights:
			print("  light ", l)
		room.queue_free()
		await process_frame
	quit()
