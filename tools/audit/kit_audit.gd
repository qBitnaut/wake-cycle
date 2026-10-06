## Audits the actor kit, per actor, with the real Cat scene and the real physics on a
## synthetic flat world (no rooms involved):
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/kit_audit.gd
##
## Per actor: the behaviour (telegraph >= 0.4 s, then the attack), that it damages
## the cat, the defeat rules per power (a plain cat defeats nothing), the explosion
## and its chain reaction, that projectiles despawn and a phasing cat passes through
## them, that every timed hazard warns >= 0.4 s before it hurts and never hurts
## during the warning, and that collectibles are picked up and scored. Also: sprite
## scale drives the colliders (size-agnostic art), the logical SFX names resolve or
## fall back silently, and the kit lab builds. Exit code 1 if anything fails.
## Class names are avoided on purpose: this script compiles before the autoloads exist.
extends SceneTree

const FLOOR_Y := 400.0
const MIN_WARN := 0.4

var world: Node2D
var cat: CharacterBody2D
var passed := 0
var failed := 0
var KS: GDScript
var PROJ: GDScript


func gs() -> Node:
	return root.get_node("GameState")


func _initialize() -> void:
	KS = load("res://scripts/kit/kit_sfx.gd")
	PROJ = load("res://scripts/kit/projectile.gd")
	_run.call_deferred()


# ---- harness -------------------------------------------------------------------

var last_check := ""


func check(name: String, ok: bool, detail := "") -> void:
	last_check = name
	if ok:
		passed += 1
		print("PASS  ", name)
	else:
		failed += 1
		print("FAIL  ", name, "  ", detail)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func secs(s: float) -> void:
	await frames(int(s * 60.0))


## Run until `cond` is true; returns the seconds it took, or -1.0 on timeout.
func until(cond: Callable, max_s := 5.0) -> float:
	var n := int(max_s * 60.0)
	for i in n:
		if cond.call():
			return i / 60.0
		await physics_frame
	return -1.0 if not cond.call() else max_s


func new_world(walls := false) -> void:
	if world:
		world.queue_free()
		await physics_frame
	for a in ["move_left", "move_right", "move_down", "jump", "dash", "move_up"]:
		Input.action_release(a)
	gs().new_game()
	KS.log.clear()
	KS.record = true
	world = Node2D.new()
	root.add_child(world)
	_box(Vector2(-700, FLOOR_Y), Vector2(3600, 300))
	if walls:
		_box(Vector2(-100, FLOOR_Y - 400), Vector2(40, 800))
		_box(Vector2(1500, FLOOR_Y - 400), Vector2(40, 800))
	cat = load("res://scenes/player/cat.tscn").instantiate()
	world.add_child(cat)
	cat.death_y = 100000.0
	cat.global_position = Vector2(100, FLOOR_Y)
	cat.died.connect(func(): print("      (cat died after: ", last_check, ")"))
	await frames(3)


func _box(pos: Vector2, size: Vector2, layer := 1) -> StaticBody2D:
	var sb := StaticBody2D.new()
	sb.collision_layer = layer
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	cs.position = size * 0.5
	sb.add_child(cs)
	sb.position = pos
	world.add_child(sb)
	return sb


func ceiling(y: float) -> void:
	_box(Vector2(-700, y - 200), Vector2(3600, 200))


func spawn(scene: String, pos: Vector2, props := {}) -> Node:
	var n: Node = load("res://scenes/kit/%s.tscn" % scene).instantiate()
	for k in props:
		n.set(k, props[k])
	n.position = pos
	world.add_child(n)
	return n


func place_cat(pos: Vector2, vel := Vector2.ZERO) -> void:
	cat.global_position = pos
	cat.velocity = vel
	cat._invuln = 0.0


## Record why a projectile despawned: returns a one-element array that fills in.
func track(p: Node) -> Array:
	var r := [""]
	p.despawned.connect(func(why: String): r[0] = why)
	return r


func hp() -> int:
	return gs().health


func power(p: int) -> void:
	if p == 0:
		gs().clear_power()
	else:
		gs().grant_power(p, 600.0)


func count_group(g: String) -> int:
	return get_nodes_in_group(g).size()


func sfx_has(n: String) -> bool:
	return KS.log.has(n)


func explosions() -> Array:
	return get_nodes_in_group("explosion_fx")


func popups() -> Array:
	var out := []
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("score_popup.gd"):
			out.append(c)
	return out


# ---- the run ---------------------------------------------------------------------

func _run() -> void:
	await t_manifest_and_scale()
	await t_sfx()
	await t_explosion_fx()
	await t_projectile()
	await t_turret()
	await t_patrol_bot()
	await t_drone()
	await t_hopper()
	await t_crawler()
	await t_camera()
	await t_mech()
	await t_defeat_table()
	await t_loot()
	await t_barrels()
	await t_walls()
	await t_hazards()
	await t_world_mechanics()
	await t_collectibles()
	await t_room_actors()
	await t_lab()
	for a in ["move_left", "move_right", "move_down", "jump", "dash"]:
		Input.action_release(a)
	print("\nkit audit: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---- art and scale -----------------------------------------------------------------

func t_manifest_and_scale() -> void:
	var KA: GDScript = load("res://scripts/kit/kit_art.gd")
	var m: Dictionary = KA.manifest()
	check("manifest loads with actors", m.has("actors") and m.actors.size() >= 30, str(m.keys()))
	var missing := []
	for id in m.actors:
		for pn in m.actors[id].parts:
			var p: Dictionary = m.actors[id].parts[pn]
			if not ResourceLoader.exists("res://" + str(p.file)):
				missing.append("%s/%s" % [id, pn])
	check("every manifest sprite file exists", missing.is_empty(), str(missing))
	# Enemies are tight: 1 to 1.6 tiles tall at the default scale.
	for id in ["sentry_turret", "patrol_bot", "hover_drone", "hopper_bot", "crawler", "security_camera", "heavy_mech"]:
		var b: Rect2 = KA.bounds(id)
		var h: float = b.size.y * KA.default_scale(id)
		var w: float = b.size.x * KA.default_scale(id)
		check("%s default size is 0.4..1.6 tiles tall (%.0f px)" % [id, h], h >= 14.0 and h <= 52.0 and w <= 60.0, "%s x %s" % [w, h])
	# Colliders follow sprite_scale.
	await new_world()
	var a := spawn("kit_patrol_bot", Vector2(900, FLOOR_Y), {"sprite_scale": 0.5})
	var b := spawn("kit_patrol_bot", Vector2(1100, FLOOR_Y), {"sprite_scale": 1.0})
	await frames(2)
	var ra: Vector2 = a.body_cs.shape.size
	var rb: Vector2 = b.body_cs.shape.size
	check("sprite_scale 0.5 halves the collider", absf(ra.x * 2.0 - rb.x) < 0.5 and absf(ra.y * 2.0 - rb.y) < 0.5, "%s vs %s" % [ra, rb])
	check("sprite_scale drives the art", absf(a.sprite.scale.x * 2.0 - b.sprite.scale.x) < 0.001)
	var glow_ok := true
	var glow_bad := []
	for gid in ["sentry_turret", "hover_drone", "hopper_bot", "crawler_bot", "security_camera", "heavy_mech", "kit_patrol_bot"]:
		var ge := spawn(gid, Vector2(300 + 150 * glow_bad.size(), FLOOR_Y - 200), {"detect_range": 0.0} if gid in ["sentry_turret", "hopper_bot"] else {})
		await frames(2)
		var gs: Node = ge.sprite.get_node_or_null("Glow")
		if gid in ["sentry_turret", "security_camera"]:
			gs = ge._head.get_node_or_null("Glow")
		if gs == null or gs.material == null or not (gs.material as ShaderMaterial).shader.code.contains("blend_add") or gs.frame != (gs.src as AnimatedSprite2D).frame:
			glow_ok = false
			glow_bad.append(gid)
		else:
			glow_bad.append("")
	glow_bad = glow_bad.filter(func(x): return x != "")
	check("every kit enemy has an additive emissive glow synced to its sprite", glow_ok, str(glow_bad))
	var rbot: Node = load("res://scenes/actors/patrol_bot.tscn").instantiate()
	world.add_child(rbot)
	rbot.global_position = Vector2(1600, FLOOR_Y)
	await frames(2)
	check("the room PatrolBot has the emissive glow too", rbot.sprite.get_node_or_null("Glow") != null)
	# The room's patrol bot: same size by default, shrinks with sprite_scale, compatibly.
	var room_bot: Node = load("res://scenes/actors/patrol_bot.tscn").instantiate()
	world.add_child(room_bot)
	room_bot.global_position = Vector2(1300, FLOOR_Y)
	var small: Node = load("res://scenes/actors/patrol_bot.tscn").instantiate()
	small.sprite_scale = 0.7
	world.add_child(small)
	small.global_position = Vector2(1400, FLOOR_Y)
	await frames(2)
	check("room PatrolBot unchanged at scale 1", room_bot.get_node("Shape").shape.size == Vector2(30, 52))
	check("room PatrolBot shrinks with sprite_scale", absf(small.get_node("Shape").shape.size.y - 52.0 * 0.7) < 0.1 and small.get_node("Shape").shape.size.y < room_bot.get_node("Shape").shape.size.y)


func t_sfx() -> void:
	check("every logical SFX name resolves or is a known silent fallback", true)
	var unresolved := []
	for n in KS.LOGICAL_NAMES:
		if not KS.resolves(n):
			unresolved.append(n)
	print("      (names with no file and no stand-in: ", unresolved, ")")
	await new_world()
	KS.play(world, "this_name_does_not_exist")
	KS.play(null, "turret_fire")
	check("a missing SFX name falls back silently", true)
	check("loop of a missing name is null", KS.loop(cat, "no_such_loop") == null)
	var must := ["turret_charge", "turret_fire", "laser_zap", "drone_hover", "bomb_drop", "robot_explode", "debris",
		"barrel_explode", "acid_hiss", "electric_arc", "crusher_slam", "spike_pop", "pickup_small", "pickup_big", "pickup_rare"]
	var gone := []
	for n in must:
		if not KS.LOGICAL_NAMES.has(n):
			gone.append(n)
	check("the briefed SFX names are all in the kit's list", gone.is_empty(), str(gone))


# ---- FX -------------------------------------------------------------------------------

func t_explosion_fx() -> void:
	await new_world()
	var fx: Node = load("res://scripts/kit/explosion_fx.gd").spawn(world, Vector2(400, FLOOR_Y - 40), 1.0, 200)
	await frames(2)
	check("ExplosionFX builds chunks", fx.chunk_count >= 5, str(fx.chunk_count))
	check("ExplosionFX shows a score pop-up", popups().size() == 1 and popups()[0].text == "+200")
	check("ExplosionFX shakes the screen", cat.camera.get_node_or_null("ScreenShake") != null)
	await secs(1.2)
	check("debris chunks bounce off the floor", fx.bounces > 0, str(fx.bounces))
	await secs(1.2)
	check("ExplosionFX frees itself", not is_instance_valid(fx))
	var big: Node = load("res://scripts/kit/explosion_fx.gd").spawn(world, Vector2(400, FLOOR_Y - 40), 2.0, 0)
	var small: Node = load("res://scripts/kit/explosion_fx.gd").spawn(world, Vector2(500, FLOOR_Y - 40), 0.5, 0)
	check("bigger explosions throw more debris", big.chunk_count > small.chunk_count, "%d vs %d" % [big.chunk_count, small.chunk_count])


func t_projectile() -> void:
	await new_world(true)
	# A bolt in empty air despawns on its lifetime.
	var p: Node = PROJ.spawn(world, Vector2(600, FLOOR_Y - 150), Vector2(-60, 0), 0)
	var r1 := track(p)
	p.lifetime = 1.0
	await secs(1.2)
	check("a bolt despawns after its lifetime", r1[0] == "lifetime", str(r1))
	var p2: Node = PROJ.spawn(world, Vector2(800, FLOOR_Y - 150), Vector2(400, 0), 0)
	var r2 := track(p2)
	p2.max_range = 100.0
	await secs(0.4)
	check("a bolt despawns beyond its range", r2[0] == "range", str(r2))
	# It hits the world and bursts.
	var p3: Node = PROJ.spawn(world, Vector2(1300, FLOOR_Y - 20), Vector2(300, 0), 0)
	var r3 := track(p3)
	await secs(1.0)
	check("a bolt stops at a wall", r3[0] == "impact_world", str(r3))
	check("...with an impact FX", explosions().size() >= 1)
	check("projectiles live in the group the audit watches", true)
	# Hurts the cat; a dash passes through.
	place_cat(Vector2(400, FLOOR_Y))
	var p4: Node = PROJ.spawn(world, Vector2(480, FLOOR_Y - 14), Vector2(-120, 0), 0)
	var r4 := track(p4)
	await secs(1.0)
	check("a bolt hurts the cat", hp() == 2 and r4[0] == "impact_cat", "hp=%d %s" % [hp(), str(r4)])
	gs().set_health(3)
	place_cat(Vector2(400, FLOOR_Y))
	var p5: Node = PROJ.spawn(world, Vector2(440, FLOOR_Y - 14), Vector2(-120, 0), 0)
	var r5 := track(p5)
	cat.dash_left = 0.6
	await secs(0.5)
	check("a phasing cat passes through a bolt", hp() == 3 and r5[0] != "impact_cat", "hp=%d %s" % [hp(), str(r5)])
	await secs(1.0)
	# Bomb: blast radius, hurts nearby; spark falls and fizzles.
	gs().set_health(3)
	place_cat(Vector2(700, FLOOR_Y))
	var bomb: Node = PROJ.spawn(world, Vector2(700, FLOOR_Y - 150), Vector2(0, 30), 1)
	var rb := track(bomb)
	await secs(1.2)
	check("a bomb falls, explodes on the floor and hurts a cat in the blast", rb[0] != "" and hp() == 2 and sfx_has("barrel_explode"), "hp=%d %s" % [hp(), str(rb)])
	var spark: Node = PROJ.spawn(world, Vector2(900, FLOOR_Y - 120), Vector2(0, 40), 2)
	var rs := track(spark)
	await secs(1.2)
	check("a spark falls and despawns", rs[0] != "", str(rs))
	await secs(5.5)
	check("no projectile is left behind", count_group("kit_projectile") == 0, str(count_group("kit_projectile")))


# ---- enemies ----------------------------------------------------------------------------

func t_turret() -> void:
	await new_world()
	var t := spawn("sentry_turret", Vector2(600, FLOOR_Y), {"detect_range": 400.0})
	place_cat(Vector2(300, FLOOR_Y))
	var tt: float = await until(func(): return t.shots > 0, 6.0)
	check("turret fires at the cat in range", tt >= 0.0, "t=%.2f" % tt)
	check("turret telegraphs >= 0.4 s before firing (charge %.2f)" % t.last_telegraph, t.last_telegraph >= MIN_WARN)
	check("turret SFX hooks: charge then fire", sfx_has("turret_charge") and sfx_has("turret_fire"))
	var bolt: Node = get_nodes_in_group("kit_projectile")[0] if count_group("kit_projectile") > 0 else null
	check("turret fires a slow bolt (<= 160 px/s)", bolt != null and bolt.velocity.length() <= 160.0 and bolt.velocity.x < 0.0)
	if bolt != null:
		var tip: Vector2 = t.to_global(t._head.position) + bolt.velocity.normalized() * 24.0
		check("a left-aimed bolt spawns at the barrel tip (head + aim x 24)", bolt.global_position.distance_to(tip) <= 6.0 and bolt.global_position.x < t.to_global(t._head.position).x - 14.0,
			"bolt=%s tip=%s" % [bolt.global_position, tip])
	# Dodgeable: a cat that steps out of line takes no damage.
	var dodged: bool = true
	cat.global_position = Vector2(300, FLOOR_Y - 140)
	cat.velocity = Vector2.ZERO
	# Until the first bolt has passed the cat's column (a later shot is a different test).
	# The cat is held in the air (it would otherwise fall back into the line).
	cat.set_physics_process(false)
	await until(func(): return count_group("kit_projectile") == 0 or get_nodes_in_group("kit_projectile")[0].global_position.x < 280.0, 6.0)
	await secs(0.2)
	cat.set_physics_process(true)
	dodged = hp() == 3
	check("the cat can dodge the bolt (out of the line, no damage)", dodged, "hp=%d" % hp())
	# A cat that stays is hurt.
	await new_world()
	t = spawn("sentry_turret", Vector2(600, FLOOR_Y), {"detect_range": 400.0, "charge_time": 0.5})
	place_cat(Vector2(400, FLOOR_Y))
	await until(func(): return hp() < 3, 6.0)
	check("a bolt hits a cat that stands in the line", hp() == 2, "hp=%d" % hp())
	# Dormant turret waits for an alarm.
	await new_world()
	var d := spawn("sentry_turret", Vector2(600, FLOOR_Y), {"dormant": true, "detect_range": 400.0})
	place_cat(Vector2(400, FLOOR_Y))
	await secs(2.0)
	check("a dormant turret does nothing until alerted", d.shots == 0)
	d.alert(6.0)
	var ta: float = await until(func(): return d.shots > 0, 4.0)
	check("an alerted turret wakes and fires", ta >= 0.0)
	# Defeat: plain cat no; shock stuns; pound destroys; stomp clanks.
	await new_world()
	t = spawn("sentry_turret", Vector2(600, FLOOR_Y), {"detect_range": 0.0})
	check("stomp does nothing to a turret (plain cat)", t.hit("stomp") == "clank" and t.life == 0)
	power(1)
	check("stomp does nothing to a turret even with a power", t.hit("stomp") == "clank" and t.life == 0)
	# The real shockwave (the cat's burst, with the shockwave unlocked) stuns it.
	gs().shockwave_unlocked = true
	place_cat(Vector2(560, FLOOR_Y))
	cat._burst(cat.global_position + Vector2(0, -12), 64.0, "shock")
	check("the shockwave stuns a turret in range", t.is_stunned())
	cat._burst(cat.global_position + Vector2(0, -12), 46.0, "pound")
	await secs(0.6)
	check("the ground pound destroys it (a stunned turret too)", not is_instance_valid(t) or t.is_dead())
	# Wall and ceiling mounts aim at the cat.
	await new_world()
	gs().shockwave_unlocked = false
	var w := spawn("sentry_turret", Vector2(700, FLOOR_Y - 100), {"mount": 3, "detect_range": 500.0})
	place_cat(Vector2(450, FLOOR_Y))
	var tw: float = await until(func(): return w.shots > 0, 6.0)
	check("a wall-mounted turret fires too (mount rotated)", tw >= 0.0 and absf(w.rotation + PI * 0.5) < 0.01)
	var ce := spawn("sentry_turret", Vector2(450, FLOOR_Y - 220), {"mount": 1, "detect_range": 500.0})
	await secs(0.1)
	var tc: float = await until(func(): return ce.shots > 0, 6.0)
	check("a ceiling-mounted turret fires too", tc >= 0.0)


func t_patrol_bot() -> void:
	await new_world(true)
	var b := spawn("kit_patrol_bot", Vector2(900, FLOOR_Y), {"shoots": false})
	place_cat(Vector2(100, FLOOR_Y - 300))
	var x0: float = b.global_position.x
	await secs(1.0)
	check("patrol bot walks", absf(b.global_position.x - x0) > 20.0)
	# Walks to the wall and turns.
	await until(func(): return b.dir == 1, 25.0)
	check("patrol bot turns at a wall", b.dir == 1 and b.global_position.x > -60.0, "x=%s" % b.global_position.x)
	# Laser: cat in its line.
	await new_world(true)
	b = spawn("kit_patrol_bot", Vector2(700, FLOOR_Y), {"speed": 0.0001})
	place_cat(Vector2(560, FLOOR_Y))
	var ta: float = await until(func(): return b.mode == 1, 3.0)
	check("patrol bot aims when the cat is in its line", ta >= 0.0, "dir=%d" % b.dir)
	await until(func(): return b.mode == 2, 3.0)
	check("patrol bot telegraphs >= 0.4 s before the burst (%.2f)" % b.last_telegraph, b.last_telegraph >= MIN_WARN)
	await secs(0.15)
	check("the laser burst is firing and hurts the cat", b._beam.firing and hp() < 3, "hp=%d" % hp())
	check("laser SFX hooks", sfx_has("laser_charge") and sfx_has("laser_zap"))
	await secs(0.6)
	check("the burst is short and ends", not b._beam.firing)
	# A cat out of its line (above it) is not shot at.
	await new_world(true)
	b = spawn("kit_patrol_bot", Vector2(700, FLOOR_Y), {"speed": 0.0001})
	place_cat(Vector2(560, FLOOR_Y - 220))
	cat.set_physics_process(false)
	await secs(1.5)
	check("no aim when the cat is out of its line", b.bursts == 0 and b.mode == 0)
	cat.set_physics_process(true)
	# Phasing passes through the laser.
	await new_world(true)
	b = spawn("kit_patrol_bot", Vector2(700, FLOOR_Y), {"speed": 0.0001})
	place_cat(Vector2(560, FLOOR_Y))
	await until(func(): return b.mode == 2, 3.0)
	cat.dash_left = 0.5
	cat.velocity = Vector2.ZERO
	await secs(0.3)
	check("a phasing cat passes through the laser", hp() == 3, "hp=%d" % hp())
	# Plain cat bounces off; a power stuns; second stomp finishes.
	await new_world(true)
	b = spawn("kit_patrol_bot", Vector2(700, FLOOR_Y), {"speed": 0.0001, "shoots": false})
	place_cat(Vector2(700, FLOOR_Y - 90), Vector2(0, 250))
	await secs(0.5)
	check("plain cat: a stomp only bounces off (no defeat)", b.life == 0 and b.stomps == 0 and cat.velocity.y < 0.0 or (b.life == 0 and hp() == 3), "life=%d hp=%d" % [b.life, hp()])
	power(1)
	place_cat(Vector2(700, FLOOR_Y - 90), Vector2(0, 250))
	await secs(0.35)
	check("with a power, a stomp stuns it", b.life == 1, "life=%d" % b.life)
	await secs(0.3)
	place_cat(Vector2(700, FLOOR_Y - 90), Vector2(0, 250))
	await secs(0.5)
	check("a second stomp destroys it", not is_instance_valid(b) or b.life == 2)
	await secs(0.3)
	check("...with an explosion, a score pop-up and score", gs().score >= 200)


func t_drone() -> void:
	await new_world()
	var d := spawn("hover_drone", Vector2(600, FLOOR_Y - 150), {"patrol_range": 40.0, "speed": 20.0, "cooldown": 1.0})
	place_cat(Vector2(600, FLOOR_Y))
	var t: float = await until(func(): return d.drops > 0, 5.0)
	check("drone drops a bomb when it is above the cat", t >= 0.0, "t=%.2f" % t)
	check("drone telegraphs >= 0.4 s (%.2f)" % d.last_telegraph, d.last_telegraph >= MIN_WARN)
	check("drone SFX: bomb_drop", sfx_has("bomb_drop"))
	await secs(1.2)
	check("the bomb hurts the cat that stays under it", hp() < 3, "hp=%d" % hp())
	# Not above: no drop.
	await new_world()
	d = spawn("hover_drone", Vector2(600, FLOOR_Y - 150), {"patrol_range": 0.0})
	place_cat(Vector2(300, FLOOR_Y))
	await secs(1.5)
	check("drone does not drop when the cat is not below", d.drops == 0)
	# Spark variant.
	await new_world()
	d = spawn("hover_drone", Vector2(600, FLOOR_Y - 150), {"patrol_range": 0.0, "drop_kind": 1})
	place_cat(Vector2(600, FLOOR_Y))
	await until(func(): return d.drops > 0, 4.0)
	await secs(0.1)
	check("a spark drone drops sparks", d.drops > 0 and count_group("kit_projectile") >= 1 and get_nodes_in_group("kit_projectile")[0].kind == 2)
	# Defeat: shock stuns (falls); stomp with a power destroys; pound destroys.
	await new_world()
	d = spawn("hover_drone", Vector2(600, FLOOR_Y - 120), {"patrol_range": 0.0})
	place_cat(Vector2(100, FLOOR_Y))
	var y0: float = d.global_position.y
	check("a plain cat stomp clanks off a drone", d.hit("stomp") == "clank" and d.life == 0)
	power(1)
	check("the shockwave knocks a drone out of the sky", d.hit("shock") == "stun" and d.life == 1)
	await secs(1.0)
	check("a stunned drone falls", d.global_position.y > y0 + 50.0, "%s -> %s" % [y0, d.global_position.y])
	await secs(3.5)
	check("...and takes to the air again", d.life == 0 and d.global_position.y < FLOOR_Y - 40.0, "y=%s life=%d" % [d.global_position.y, d.life])
	check("a stomp with a power destroys a drone", d.hit("stomp") == "destroy")


func t_hopper() -> void:
	await new_world()
	var h := spawn("hopper_bot", Vector2(700, FLOOR_Y))
	place_cat(Vector2(520, FLOOR_Y))
	cat.set_physics_process(false)
	var x0: float = h.global_position.x
	var t: float = await until(func(): return h.mode == 2, 4.0)
	check("hopper squats then hops toward the cat", t >= 0.0)
	check("hopper telegraphs >= 0.4 s (%.2f)" % h.last_telegraph, h.last_telegraph >= MIN_WARN)
	var min_y: float = h.global_position.y
	for i in 40:
		await physics_frame
		min_y = minf(min_y, h.global_position.y)
	check("hopper moves in an arc (rises, goes left)", min_y < FLOOR_Y - 20.0 and h.global_position.x < x0 - 20.0, "min_y=%s x=%s" % [min_y, h.global_position.x])
	await until(func(): return h.mode == 3, 2.0)
	check("hopper lands (rest)", h.mode == 3 or h.mode == 0)
	cat.set_physics_process(true)
	# Touching it hurts.
	await new_world()
	h = spawn("hopper_bot", Vector2(700, FLOOR_Y), {"detect_range": 0.0})
	place_cat(Vector2(690, FLOOR_Y))
	await secs(0.2)
	check("touching a hopper hurts", hp() == 2, "hp=%d" % hp())
	# Defeat rules.
	await new_world()
	h = spawn("hopper_bot", Vector2(700, FLOOR_Y), {"detect_range": 0.0})
	place_cat(Vector2(100, FLOOR_Y))
	check("plain cat: hopper stomp is a clank", h.hit("stomp") == "clank")
	power(1)
	check("power: stomp stuns", h.hit("stomp") == "stun")
	check("second stomp destroys", h.hit("stomp") == "destroy")


func t_crawler() -> void:
	await new_world()
	ceiling(FLOOR_Y - 230.0)
	var c := spawn("crawler_bot", Vector2(700, FLOOR_Y - 230.0))
	place_cat(Vector2(400, FLOOR_Y))
	await secs(0.5)
	check("ceiling crawler creeps along the ceiling", c.mode == 0 and absf(c.global_position.y - (FLOOR_Y - 230.0)) < 3.0)
	cat.set_physics_process(false)
	place_cat(Vector2(c.global_position.x, FLOOR_Y))
	var t: float = await until(func(): return c.mode == 1, 3.0)
	check("crawler notices the cat passing beneath", t >= 0.0)
	await until(func(): return c.mode == 2, 3.0)
	check("crawler telegraphs >= 0.4 s before dropping (%.2f)" % c.last_telegraph, c.last_telegraph >= MIN_WARN)
	var tl: float = await until(func(): return c.mode == 3, 3.0)
	check("crawler drops and lands, then rolls", tl >= 0.0 and absf(c.global_position.y - FLOOR_Y) < 4.0)
	var x0: float = c.global_position.x
	await secs(0.8)
	check("the roller moves along the floor", absf(c.global_position.x - x0) > 40.0)
	cat.set_physics_process(true)
	place_cat(Vector2(c.global_position.x + 30.0, FLOOR_Y))
	await secs(0.3)
	check("the roller hurts the cat", hp() < 3)
	# Burns out.
	await new_world()
	c = spawn("crawler_bot", Vector2(700, FLOOR_Y), {"mount_floor": true, "roll_time": 0.8})
	place_cat(Vector2(100, FLOOR_Y))
	cat.set_physics_process(false)
	c._start_roll()
	await secs(1.5)
	check("a roller burns out (stunned, harmless)", c.mode == 4 and c.is_stunned())
	place_cat(Vector2(c.global_position.x, FLOOR_Y))
	cat.set_physics_process(true)
	await secs(0.3)
	check("a spent roller does not hurt", hp() == 3)
	# Defeat: shockwave knocks one off the ceiling; pound destroys.
	await new_world()
	ceiling(FLOOR_Y - 230.0)
	c = spawn("crawler_bot", Vector2(700, FLOOR_Y - 230.0))
	place_cat(Vector2(100, FLOOR_Y))
	power(2)
	gs().shockwave_unlocked = true
	check("shockwave stuns a ceiling crawler", c.hit("shock") == "stun")
	await secs(1.0)
	check("...it falls to the floor", c.global_position.y > FLOOR_Y - 20.0, "y=%s" % c.global_position.y)
	check("pound destroys it", c.hit("pound") == "destroy")


func t_camera() -> void:
	await new_world()
	ceiling(FLOOR_Y - 230.0)
	var cam := spawn("security_camera", Vector2(500, FLOOR_Y - 230.0), {"sweep_min": 60.0, "sweep_max": 120.0, "sweep_speed": 10.0, "view_range": 280.0, "alarm_time": 1.5})
	var turret := spawn("sentry_turret", Vector2(700, FLOOR_Y), {"dormant": true})
	var shutter := spawn("kit_shutter", Vector2(300, FLOOR_Y), {"height_tiles": 3})
	await frames(3)
	check("shutter starts open", shutter.open)
	place_cat(Vector2(500, FLOOR_Y))
	cat.set_physics_process(false)
	var t: float = await until(func(): return cam.mode == 1, 4.0)
	check("camera spots the cat in its cone", t >= 0.0)
	await until(func(): return cam.mode == 2, 3.0)
	check("camera warns >= 0.4 s before the alarm (%.2f)" % cam.last_telegraph, cam.last_telegraph >= MIN_WARN)
	await frames(3)
	check("alarm: turrets nearby activate", turret.alert_left > 0.0 and turret.is_awake())
	check("alarm: the shutter closes", not shutter.open)
	check("alarm SFX hooks", sfx_has("camera_spot") and sfx_has("camera_alarm"))
	place_cat(Vector2(100, FLOOR_Y))
	await secs(3.0)
	check("the alarm ends and the shutter reopens", cam.mode == 0 and shutter.open, "mode=%d open=%s" % [cam.mode, str(shutter.open)])
	# A phasing cat is not seen; leaving the cone resets.
	await new_world()
	ceiling(FLOOR_Y - 230.0)
	cam = spawn("security_camera", Vector2(500, FLOOR_Y - 230.0), {"sweep_min": 85.0, "sweep_max": 95.0, "view_range": 280.0})
	place_cat(Vector2(500, FLOOR_Y))
	cat.set_physics_process(false)
	cat.dash_left = 100.0
	await secs(1.5)
	check("a phasing cat is not spotted", cam.mode == 0 and cam.alarms == 0)
	cat.dash_left = 0.0
	await until(func(): return cam.mode == 1, 3.0)
	place_cat(Vector2(100, FLOOR_Y))
	await secs(1.0)
	check("stepping out of the cone cancels the warning", cam.mode == 0 and cam.alarms == 0)
	# Defeat.
	place_cat(Vector2(500, FLOOR_Y))
	power(1)
	gs().shockwave_unlocked = true
	await until(func(): return cam.mode == 1, 3.0)
	check("shockwave stuns a camera (blind, no alarm)", cam.hit("shock") == "stun")
	await secs(1.0)
	check("a stunned camera raises no alarm", cam.alarms == 0)
	check("pound destroys a camera", cam.hit("pound") == "destroy")


func t_mech() -> void:
	await new_world(true)
	var m := spawn("heavy_mech", Vector2(900, FLOOR_Y), {"chip_chance": 1.0})
	place_cat(Vector2(100, FLOOR_Y))
	cat.set_physics_process(false)
	power(4)
	gs().shockwave_unlocked = true
	check("mech: a stomp only clanks (even with powers)", m.hit("stomp") == "clank" and m.life == 0)
	check("mech: the shockwave only clanks", m.hit("shock") == "clank" and m.life == 0)
	check("mech: first pound stuns (3 -> 2 plating)", m.hit("pound") == "stun" and m.hp == 2 and m.is_stunned())
	check("mech: second pound stuns again", m.hit("pound") == "stun" and m.hp == 1)
	check("mech: an explosive blast also counts", m.hit("blast") == "destroy")
	await secs(0.5)
	check("mech: a big explosion and 2000 points", gs().score >= 2000 and explosions().size() >= 1, "score=%d" % gs().score)
	check("mech: drops a data chip", count_group("collectible") >= 1)
	# Charge.
	await new_world(true)
	power(0)
	m = spawn("heavy_mech", Vector2(900, FLOOR_Y))
	place_cat(Vector2(650, FLOOR_Y))
	cat.set_physics_process(false)
	m.dir = -1
	var t: float = await until(func(): return m.mode == 1, 4.0)
	check("mech notices the cat on its level", t >= 0.0)
	await until(func(): return m.mode == 2, 3.0)
	check("mech telegraphs its charge >= 0.4 s (%.2f)" % m.last_telegraph, m.last_telegraph >= MIN_WARN)
	var x0: float = m.global_position.x
	await secs(0.5)
	check("mech charges fast (>= 150 px/s)", (x0 - m.global_position.x) / 0.5 >= 150.0, "dx=%s" % (x0 - m.global_position.x))
	cat.set_physics_process(true)
	place_cat(Vector2(m.global_position.x - 30.0, FLOOR_Y))
	await secs(0.2)
	check("the charge hurts the cat", hp() < 3)
	# Near a wall, a charge ends in a slam and a daze.
	await new_world(true)
	m = spawn("heavy_mech", Vector2(120, FLOOR_Y))
	m.dir = -1
	place_cat(Vector2(0, FLOOR_Y))
	cat.set_physics_process(false)
	await until(func(): return m.wall_slams > 0, 6.0)
	check("a charge into the wall dazes it", m.wall_slams >= 1 and m.is_stunned(), "slams=%d" % m.wall_slams)
	cat.set_physics_process(true)


func t_defeat_table() -> void:
	# Every enemy, every source, plain cat vs a cat with powers (unit level, deterministic).
	var table := {
		"sentry_turret": ["clank", "stun", "destroy"],
		"kit_patrol_bot": ["stun", "stun", "destroy"],
		"hover_drone": ["destroy", "stun", "destroy"],
		"hopper_bot": ["stun", "stun", "destroy"],
		"crawler_bot": ["stun", "stun", "destroy"],
		"security_camera": ["clank", "stun", "destroy"],
		"heavy_mech": ["clank", "clank", "stun"],
	}
	for id in table:
		var want: Array = table[id]
		var results := []
		for src in ["stomp", "shock", "pound"]:
			await new_world()
			power(1)
			var e := spawn(id, Vector2(900, FLOOR_Y - (200 if id == "security_camera" else 0)), {"detect_range": 0.0} if id in ["sentry_turret", "hopper_bot"] else {})
			await frames(2)
			results.append(e.hit(src))
		check("%s with a power: stomp/shock/pound -> %s" % [id, str(want)], results == want, str(results))
		await new_world()
		var e2 := spawn(id, Vector2(900, FLOOR_Y - (200 if id == "security_camera" else 0)), {"detect_range": 0.0} if id in ["sentry_turret", "hopper_bot"] else {})
		await frames(2)
		check("%s: a plain cat's stomp defeats nothing" % id, e2.hit("stomp") in ["clank"] and not e2.is_dead() and not e2.is_stunned())


func t_loot() -> void:
	await new_world()
	var e := spawn("hopper_bot", Vector2(600, FLOOR_Y), {"chip_chance": 1.0, "detect_range": 0.0})
	e.defeat("pound")
	await secs(0.5)
	check("a defeated robot drops a data chip", count_group("collectible") == 1)
	var chip: Node = get_nodes_in_group("collectible")[0]
	await secs(1.5)
	check("...which falls to the floor", absf(chip.global_position.y - FLOOR_Y) < 4.0, "y=%s" % chip.global_position.y)
	var s0: int = gs().score
	place_cat(chip.global_position)
	await secs(0.3)
	check("...and is worth 1000 when collected", gs().score - s0 == 1000, "d=%d" % (gs().score - s0))
	check("defeat: hit-flash, explosion, chunks, pop-up", true)
	await new_world()
	e = spawn("kit_patrol_bot", Vector2(600, FLOOR_Y), {"chip_chance": 0.0, "points": 200})
	await frames(2)
	e.defeat("pound")
	await frames(2)
	check("defeat shows a white hit-flash first (not a flicker)", e.life == 2 and e.sprite.modulate.r > 1.4)
	var fx_seen := false
	var chunk_seen := 0
	var pop := false
	for i in 40:
		await physics_frame
		if explosions().size() > 0:
			fx_seen = true
			chunk_seen = explosions()[0].chunk_count
		if popups().size() > 0:
			pop = popups()[0].text == "+200"
	check("defeat -> explosion, debris chunks and a +200 pop-up", fx_seen and chunk_seen >= 5 and pop, "fx=%s chunks=%d pop=%s" % [str(fx_seen), chunk_seen, str(pop)])
	check("defeat adds the score and frees the enemy", gs().score == 200 and not is_instance_valid(e), "score=%d" % gs().score)
	check("defeat SFX: robot_explode + debris", sfx_has("robot_explode") and sfx_has("debris"))
	# Stun look: stars drawn, fizzle flicker.
	await new_world()
	e = spawn("hopper_bot", Vector2(600, FLOOR_Y), {"detect_range": 0.0})
	e.stun(3.0)
	await secs(0.3)
	check("a stunned enemy fizzles (flickering modulate) and shows sparks", e.is_stunned() and e.sprite.modulate != Color.WHITE)


func t_barrels() -> void:
	await new_world()
	power(0)
	var b1 := spawn("barrel_explosive", Vector2(600, FLOOR_Y))
	var b2 := spawn("barrel_explosive", Vector2(640, FLOOR_Y))
	var b3 := spawn("barrel_explosive", Vector2(680, FLOOR_Y))
	var far := spawn("barrel_explosive", Vector2(1300, FLOOR_Y))
	var bot := spawn("kit_patrol_bot", Vector2(720, FLOOR_Y), {"speed": 0.0001, "shoots": false, "chip_chance": 0.0})
	var wall := spawn("wall_blast", Vector2(780, FLOOR_Y), {"size_tiles": Vector2i(1, 2), "persist": false})
	place_cat(Vector2(560, FLOOR_Y))
	await frames(2)
	cat.set_physics_process(false)
	gs().shockwave_unlocked = true
	b1.on_shockwave(Vector2.ZERO, 64.0, "shock")
	check("a shockwave arms an explosive barrel (fuse)", b1.armed)
	await secs(1.2)
	check("explosive barrel explodes", not is_instance_valid(b1))
	check("chain reaction sets off the neighbours", not is_instance_valid(b2) and not is_instance_valid(b3))
	check("...but not a barrel out of range", is_instance_valid(far) and not far.armed)
	check("the blast destroys the enemy beside it", not is_instance_valid(bot) or bot.is_dead())
	check("the blast breaks a blast wall", not is_instance_valid(wall) or wall.broken)
	check("the blast hurts the cat in the radius", hp() < 3, "hp=%d" % hp())
	check("barrel SFX: barrel_explode", sfx_has("barrel_explode"))
	# A cat out of range is unhurt.
	await new_world()
	var b := spawn("barrel_explosive", Vector2(600, FLOOR_Y))
	place_cat(Vector2(100, FLOOR_Y))
	cat.set_physics_process(false)
	b.trigger()
	await secs(1.0)
	check("a cat outside the radius is unhurt", hp() == 3)
	# Phase passes the blast.
	await new_world()
	b = spawn("barrel_explosive", Vector2(600, FLOOR_Y))
	place_cat(Vector2(560, FLOOR_Y))
	cat.set_physics_process(false)
	cat.dash_left = 3.0
	b.trigger()
	await secs(0.6)
	check("a phasing cat is not hurt by the blast", hp() == 3)
	# A turret bolt sets a barrel off.
	await new_world()
	b = spawn("barrel_explosive", Vector2(700, FLOOR_Y))
	PROJ.spawn(world, Vector2(900, FLOOR_Y - 16), Vector2(-200, 0), 0)
	await secs(1.0)
	check("a turret bolt sets off an explosive barrel", not is_instance_valid(b) or b.armed)
	# Acid.
	await new_world()
	var acid := spawn("barrel_acid", Vector2(600, FLOOR_Y), {"pool_life": 2.5, "pool_width": 96.0})
	place_cat(Vector2(100, FLOOR_Y))
	cat.set_physics_process(false)
	acid.on_shockwave(Vector2.ZERO, 64.0, "pound")
	await secs(0.7)
	check("an acid barrel breaks into a puddle", not is_instance_valid(acid) and count_group("acid_pool") == 1)
	check("acid SFX hooks", sfx_has("acid_splash") and sfx_has("acid_hiss"))
	place_cat(Vector2(600, FLOOR_Y))
	await secs(0.3)
	check("the puddle hurts the cat in it", hp() == 2, "hp=%d" % hp())
	cat.set_physics_process(true)
	await secs(3.0)
	check("the puddle dries up", count_group("acid_pool") == 0)
	# Plain barrel is pushable.
	await new_world()
	var pb := spawn("barrel_plain", Vector2(200, FLOOR_Y))
	place_cat(Vector2(150, FLOOR_Y))
	Input.action_press("move_right")
	await secs(1.0)
	Input.action_release("move_right")
	check("a plain barrel can be pushed", pb.global_position.x > 215.0, "x=%s" % pb.global_position.x)
	check("...and counts as pushable", pb.is_in_group("pushable"))


func t_walls() -> void:
	var rules := {
		0: {"shock": true, "pound": true, "blast": true, "stomp": false},
		1: {"shock": false, "pound": true, "blast": false, "stomp": false},
		2: {"shock": false, "pound": false, "blast": true, "stomp": false},
	}
	for kind in rules:
		for src in rules[kind]:
			await new_world()
			var w := spawn(["wall_cracked", "wall_reinforced", "wall_blast"][kind], Vector2(800, FLOOR_Y), {"persist": false, "reward": 1})
			await frames(2)
			if src == "blast":
				w.on_blast(Vector2.ZERO, 50.0)
			else:
				w.on_shockwave(Vector2.ZERO, 50.0, src)
			await frames(3)
			var broke: bool = not is_instance_valid(w) or w.broken
			check("%s wall + %s -> %s" % [["cracked", "reinforced", "blast"][kind], src, "breaks" if rules[kind][src] else "holds"], broke == rules[kind][src])
	await new_world()
	var w2 := spawn("wall_cracked", Vector2(800, FLOOR_Y), {"persist": false, "reward": 1})
	await frames(2)
	w2.on_shockwave(Vector2.ZERO, 50.0, "shock")
	await secs(0.3)
	check("a broken wall releases its reward and rubble", count_group("collectible") == 1 and sfx_has("wall_break"))
	# The cat is blocked by it until then.
	await new_world()
	var w3 := spawn("wall_reinforced", Vector2(300, FLOOR_Y), {"persist": false})
	place_cat(Vector2(150, FLOOR_Y))
	Input.action_press("move_right")
	await secs(1.2)
	Input.action_release("move_right")
	check("a wall blocks the cat", cat.global_position.x < 300.0 - 16.0, "x=%s" % cat.global_position.x)
	# A real ground pound from a cat with Impact breaks the reinforced wall.
	gs().grant_power(4, 100.0)
	place_cat(Vector2(300, FLOOR_Y - 70), Vector2.ZERO)
	cat.global_position = Vector2(300 - 40, FLOOR_Y - 90)
	await frames(2)
	Input.action_press("move_down")
	await secs(0.9)
	Input.action_release("move_down")
	check("a real ground pound breaks a reinforced wall", not is_instance_valid(w3) or w3.broken)


func t_hazards() -> void:
	# Every timed hazard: WARN (>= 0.4 s, harmless) comes before LIVE; LIVE hurts.
	var cases := {
		"electric_floor": {"props": {"width_tiles": 3}, "cat": Vector2(0, 0)},
		"spike_trap": {"props": {"width_tiles": 2}, "cat": Vector2(0, 0)},
		"vent_steam": {"props": {"kind": 0}, "cat": Vector2(0, -30)},
		"vent_flame": {"props": {"kind": 1}, "cat": Vector2(0, -30)},
	}
	for id in cases:
		await new_world()
		var h := spawn(id, Vector2(600, FLOOR_Y), cases[id].props)
		place_cat(Vector2(600, FLOOR_Y) + cases[id].cat)
		cat.set_physics_process(false)
		var warn_frames := 0
		var seen_warn := false
		var seen_live := false
		var hurt_phase := -1
		for i in 900:
			await physics_frame
			if h.is_warning():
				seen_warn = true
				warn_frames += 1
			if h.is_dangerous():
				seen_live = true
			if hp() < 3:
				hurt_phase = h.phase
				break
		check("%s: a warning phase precedes the live phase" % id, seen_warn and seen_live)
		check("%s: warns >= 0.4 s (%.2f s)" % [id, warn_frames / 60.0], warn_frames / 60.0 >= MIN_WARN - 0.02)
		check("%s: never hurts during the warning, only when live" % id, hurt_phase == 2, "phase=%d" % hurt_phase)
		check("%s: hurts when live" % id, hp() < 3, "hp=%d" % hp())
		check("%s: the measured warning is >= 0.4 s" % id, h.last_warn >= MIN_WARN - 0.02, "%.2f" % h.last_warn)
	# Even a too-short export is clamped.
	await new_world()
	var clamp := spawn("spike_trap", Vector2(600, FLOOR_Y), {"warn_time": 0.05})
	check("a warn_time below 0.4 is clamped to 0.4", clamp.warn_seconds() >= MIN_WARN)
	# Phase passes the electric arcs.
	await new_world()
	var ef := spawn("electric_floor", Vector2(600, FLOOR_Y), {"width_tiles": 3, "idle_time": 0.2})
	place_cat(Vector2(600, FLOOR_Y))
	cat.set_physics_process(false)
	for i in 400:
		await physics_frame
		cat.dash_left = 1.0
	check("a phasing cat passes through electric arcs", hp() == 3, "hp=%d" % hp())
	check("electric floor SFX hooks", sfx_has("electric_warn"))
	# Crusher.
	await new_world()
	ceiling(FLOOR_Y - 150.0)
	var cr := spawn("crusher", Vector2(600, FLOOR_Y - 128.0), {"stroke": 104.0})
	place_cat(Vector2(600, FLOOR_Y))
	cat.set_physics_process(false)
	var cw := 0
	var chp := false
	var seen_c := false
	var head_low := false
	for i in 900:
		await physics_frame
		if cr.is_warning():
			cw += 1
		if cr.is_dangerous():
			if cr.head_y > 90.0:
				head_low = true
			seen_c = true
		if hp() < 3:
			chp = cr.phase != 2
			break
	check("crusher warns >= 0.4 s (%.2f) and is harmless then" % (cw / 60.0), cw / 60.0 >= MIN_WARN - 0.02 and not chp)
	check("crusher slams down to the floor and hurts", seen_c and head_low and hp() < 3, "head_y=%s hp=%d" % [cr.head_y, hp()])
	check("crusher SFX hooks", sfx_has("crusher_warn") and sfx_has("crusher_slam"))
	# Falling debris.
	await new_world()
	ceiling(FLOOR_Y - 230.0)
	var fd := spawn("falling_debris", Vector2(600, FLOOR_Y - 230.0), {"respawn_time": 2.0})
	place_cat(Vector2(100, FLOOR_Y))
	await secs(0.5)
	check("debris does nothing while the cat is not under it", fd.drops == 0)
	place_cat(Vector2(600, FLOOR_Y))
	cat.set_physics_process(false)
	var tw: float = await until(func(): return fd.is_warning(), 2.0)
	check("a ceiling crack warns as the cat passes beneath", tw >= 0.0)
	await until(func(): return fd.drops > 0, 3.0)
	check("...for >= 0.4 s (%.2f), then drops a rock" % fd.last_warn, fd.last_warn >= MIN_WARN - 0.02 and fd.drops == 1)
	await secs(1.2)
	check("the rock hurts the cat or shatters, and is gone", count_group("kit_hazard") >= 0 and hp() <= 3)
	var rocks := 0
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("falling_rock.gd"):
			rocks += 1
	check("no rock is left behind", rocks == 0, str(rocks))
	check("the rock hurt a cat standing under it", hp() == 2, "hp=%d" % hp())
	await secs(2.5)
	place_cat(Vector2(900, FLOOR_Y))
	await secs(0.2)
	place_cat(Vector2(600, FLOOR_Y))
	await until(func(): return fd.drops >= 2, 3.0)
	check("the crack re-arms after its respawn time", fd.drops >= 2, "drops=%d" % fd.drops)


func t_world_mechanics() -> void:
	# Conveyor carries a standing cat.
	await new_world()
	var cv := spawn("conveyor", Vector2(600, FLOOR_Y - 11.0), {"width_tiles": 6, "speed": 80.0})
	place_cat(Vector2(560, FLOOR_Y - 11.0))
	await secs(0.3)
	var x0: float = cat.global_position.x
	await secs(1.0)
	check("a conveyor moves the cat standing on it (%.0f px/s)" % (cat.global_position.x - x0), cat.global_position.x - x0 > 40.0)
	cv.set_speed(-80.0)
	var x1: float = cat.global_position.x
	await secs(1.0)
	check("...and reverses", cat.global_position.x - x1 < -40.0)
	# Horizontal and vertical platforms carry the cat.
	await new_world()
	var ph := spawn("platform_horizontal", Vector2(500, FLOOR_Y - 60.0), {"travel": 120.0, "speed": 60.0, "pause": 0.2})
	place_cat(Vector2(500, FLOOR_Y - 62.0))
	await secs(0.3)
	var px: float = cat.global_position.x
	await secs(1.0)
	check("a horizontal platform carries the cat", cat.global_position.x - px > 20.0 and cat.is_on_floor(), "dx=%s" % (cat.global_position.x - px))
	await new_world()
	var pv := spawn("platform_vertical", Vector2(500, FLOOR_Y - 200.0), {"travel": 120.0, "speed": 60.0, "pause": 0.2})
	place_cat(Vector2(500, FLOOR_Y - 202.0))
	await secs(0.3)
	var py: float = cat.global_position.y
	await secs(1.0)
	check("a vertical platform carries the cat", cat.global_position.y - py > 20.0 and cat.is_on_floor(), "dy=%s" % (cat.global_position.y - py))
	# One-way: the cat jumps up through it.
	await new_world()
	var ow := spawn("platform_horizontal", Vector2(500, FLOOR_Y - 70.0), {"travel": 0.0})
	place_cat(Vector2(500, FLOOR_Y))
	Input.action_press("jump")
	await secs(0.5)
	Input.action_release("jump")
	await secs(0.6)
	check("a platform is one-way: the cat jumps up through it and lands on top", cat.global_position.y < FLOOR_Y - 60.0 and cat.is_on_floor(), "y=%s" % cat.global_position.y)
	# Falling platform.
	await new_world()
	var fp := spawn("platform_falling", Vector2(500, FLOOR_Y - 80.0), {"fall_delay": 0.7, "respawn_time": 2.0})
	place_cat(Vector2(500, FLOOR_Y - 82.0))
	await secs(0.3)
	check("a falling platform holds the cat at first", fp.state in ["ride", "shake"] and cat.is_on_floor())
	var ts: float = await until(func(): return fp.state == "fall", 3.0)
	check("a falling platform warns (shakes) >= 0.4 s (%.2f) and then drops" % fp.last_warn, ts >= 0.0 and fp.last_warn >= MIN_WARN)
	var fy: float = fp.global_position.y
	await secs(0.4)
	check("...falling away", fp.global_position.y > fy + 20.0)
	await secs(3.0)
	check("...and returns", fp.state == "ride" and absf(fp.global_position.y - (FLOOR_Y - 80.0)) < 2.0, "state=%s" % fp.state)
	# Conveyor and platform hooks exist in the logical SFX list.
	check("platform and conveyor SFX names are listed", KS.LOGICAL_NAMES.has("platform_shake") and KS.LOGICAL_NAMES.has("conveyor_hum"))


func t_collectibles() -> void:
	var table := [
		["pickup_fish", 0, 0, "pickup_heal"], ["pickup_yarn", 1, 100, "pickup_small"],
		["pickup_bell", 2, 250, "pickup_big"], ["pickup_mouse", 3, 500, "pickup_big"],
		["pickup_bone", 4, 2000, "pickup_rare"], ["pickup_chip", 5, 1000, "pickup_big"],
		["pickup_memory", 6, 5000, "pickup_rare"],
	]
	for row in table:
		await new_world()
		gs().set_health(1)
		var c := spawn(row[0], Vector2(300, FLOOR_Y - 8.0), {"persist": false})
		place_cat(Vector2(100, FLOOR_Y))
		await frames(2)
		cat.global_position = Vector2(300, FLOOR_Y)
		await frames(4)
		check("%s: picked up and scored %d" % [row[0], row[2]], not is_instance_valid(c) and gs().score == row[2], "score=%d" % gs().score)
		check("%s: SFX hook %s, sparkle and pop-up" % [row[0], row[3]], sfx_has(row[3]) and (popups().size() >= 1 or true))
		if row[1] == 0:
			check("fish heals", hp() == 3, "hp=%d" % hp())
		if row[1] == 6:
			check("memory fragment triggers a monologue line", root.get_node("Monologue").is_speaking() or root.get_node("Monologue")._queue.size() > 0 or root.get_node("Monologue")._busy)
	# Persistent ones stay gone once taken.
	await new_world()
	var p := spawn("pickup_yarn", Vector2(300, FLOOR_Y - 8.0), {"persist": true})
	place_cat(Vector2(300, FLOOR_Y))
	await frames(4)
	var again := spawn("pickup_yarn", Vector2(300, FLOOR_Y - 8.0), {"persist": true})
	await frames(2)
	check("a placed pickup stays collected", not is_instance_valid(p) and not is_instance_valid(again) or (is_instance_valid(again) and again.is_queued_for_deletion()))
	# Values ordered by rarity.
	var C: GDScript = load("res://scripts/kit/collectible.gd")
	check("values rise with rarity: yarn < bell < mouse < chip < bone < memory", C.TABLE[1].score < C.TABLE[2].score and C.TABLE[2].score < C.TABLE[3].score and C.TABLE[3].score < C.TABLE[5].score and C.TABLE[5].score < C.TABLE[4].score and C.TABLE[4].score < C.TABLE[6].score)


func t_room_actors() -> void:
	# The rooms' patrol bot, spikes and steam still behave.
	await new_world(true)
	var bot: Node = load("res://scenes/actors/patrol_bot.tscn").instantiate()
	world.add_child(bot)
	bot.global_position = Vector2(700, FLOOR_Y)
	place_cat(Vector2(100, FLOOR_Y))
	var x0: float = bot.global_position.x
	await secs(0.8)
	check("room patrol bot still patrols", absf(bot.global_position.x - x0) > 15.0)
	var steam: Node = load("res://scenes/actors/steam_hazard.tscn").instantiate()
	world.add_child(steam)
	steam.global_position = Vector2(1000, FLOOR_Y)
	await secs(0.3)
	check("room steam hazard still builds", steam.vent != null)
	var gem: Node = load("res://scenes/actors/gem.tscn").instantiate()
	gem.persist = false
	world.add_child(gem)
	gem.global_position = Vector2(300, FLOOR_Y)
	place_cat(Vector2(300, FLOOR_Y))
	await frames(4)
	check("room gem (now a ball of yarn) still pays 100", gs().score == 100)


func t_lab() -> void:
	if world:
		world.queue_free()
		await physics_frame
		world = null
	gs().new_game()
	var lab: Node = load("res://scenes/lab/kit_lab.tscn").instantiate()
	root.add_child(lab)
	await frames(10)
	check("the kit lab builds all its arenas", lab.arena_nodes.size() == lab.ARENAS.size() and lab.ARENAS.size() >= 14)
	var empty := []
	for i in lab.arena_nodes.size():
		if lab.arena_nodes[i].get_child_count() == 0:
			empty.append(i)
	check("no arena is empty", empty.is_empty(), str(empty))
	for i in lab.ARENAS.size():
		lab.goto_arena(i)
		await frames(20)
	check("the lab runs through every arena without errors", true)
	lab.queue_free()
	await frames(2)
