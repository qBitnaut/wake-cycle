## Farm-proofing: every collectible type is taken, then the player tries to take it again across a
## death + respawn, a Continue from disk, a world-map revisit and a full reload. Asserts that the
## score never exceeds the level's maximum, never changes on re-entry, and that collected items
## never reappear (robots stay defeated, their chips are paid at most once and never lost).
##   XDG_DATA_HOME=<dir> godot --headless --path . --fixed-fps 60 --script res://tools/audit/collect_audit.gd -- --skip-intro
## Writes user://save.json, so run it with XDG_DATA_HOME set. Exit code 1 on any FAIL.
extends SceneTree

const ROOMS := [
	"res://scenes/levels/room1.tscn", "res://scenes/levels/room2.tscn",
	"res://scenes/levels/room3.tscn", "res://scenes/levels/room4.tscn",
]
const TEST_ROOM := "res://scenes/levels/test_room.tscn"
var fails := 0
var checks := 0
var room: Node2D
var cat: CharacterBody2D
var COLL: GDScript
var RT: GDScript
var counts := {}


func gs() -> Node:
	return root.get_node("GameState")


func ss() -> Node:
	return root.get_node("SaveSystem")


func note(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok or OS.get_cmdline_user_args().has("--verbose"):
		print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	_main.call_deferred()


func settle(path: String) -> void:
	await ticks(8)
	room = current_scene
	cat = room.get_node("Cat")
	cat.set("_invuln", 100000.0)
	note("loaded " + path.get_file(), room.scene_file_path == path)


## A new game in `path`, saved at the room start (what arriving through a RoomExit does).
func begin(path: String) -> void:
	gs().new_game()
	root.get_node("Monologue").reset()
	ss().clear_run()
	change_scene_to_file(path)
	await settle(path)
	ss().save_checkpoint("", path)


# ---- what is in a room ----------------------------------------------------------------------

## Every placed, persistent collectible: {key, rel (path under the room), score, color/index}.
func scan() -> Dictionary:
	var items: Array = []
	for n in room.find_children("*", "Area2D", true, false):
		var sp: String = n.get_script().resource_path if n.get_script() else ""
		if sp.ends_with("/pickup.gd") and n.persist:
			var key: String = ["pickup_key", "pickup_letter", "pickup_fish", "pickup_gem"][n.kind]
			items.append({"key": key, "rel": str(room.get_path_to(n)), "score": 100 if n.kind >= 2 else 0,
				"key_color": n.key_color, "letter": n.letter_index})
		elif sp.ends_with("/collectible.gd") and n.persist:
			var nm: String = COLL.TABLE[n.kind].name.to_lower()
			items.append({"key": "coll_" + nm, "rel": str(room.get_path_to(n)), "score": n.score_value()})
	var bots: Array = []
	for e in get_nodes_in_group("kit_enemy"):
		if room.is_ancestor_of(e):
			bots.append({"rel": str(room.get_path_to(e)), "points": e.points, "chip": e.drops_chip()})
	return {"items": items, "bots": bots}


func level_max(sc: Dictionary) -> int:
	var m := 0
	var letters := 0
	for i in sc.items:
		m += int(i.score)
		if i.key == "pickup_letter":
			letters += 1
	if letters >= 3:
		m += int(gs().LETTER_BONUS)
	for b in sc.bots:
		m += int(b.points) + (1000 if b.chip else 0)
	return m


# ---- taking things ---------------------------------------------------------------------------

func take(it: Dictionary) -> void:
	var n := room.get_node_or_null(it.rel)
	if n == null:
		return
	if n.has_method("_on_body") and not n.has_method("pick"):
		n._on_body(cat)
	else:
		n._grace = 0.0
		n.pick(cat)
	await ticks(2)


func kill(b: Dictionary) -> void:
	var e := room.get_node_or_null(b.rel)
	if e == null:
		return
	e.defeat("blast")
	await ticks(14)


## The chips lying in the room (dropped by robots), picked up.
func take_chips() -> int:
	await ticks(90)  # let them land
	var n := 0
	for col in get_nodes_in_group("collectible"):
		if room.is_ancestor_of(col) and col.kind == 5 and not col.picked and not col.is_queued_for_deletion():
			col._grace = 0.0
			col.pick(cat)
			n += 1
	await ticks(2)
	return n


func chips_lying() -> int:
	var n := 0
	for c in get_nodes_in_group("collectible"):
		if room.is_ancestor_of(c) and c.kind == 5 and not c.picked and not c.is_queued_for_deletion():
			n += 1
	return n


# ---- re-entry paths --------------------------------------------------------------------------

func reenter(how: String, path: String) -> void:
	match how:
		"death":
			cat.kill()
			await ticks(70)  # the 0.9 s death beat, then the respawn
		"continue":
			ss().session_scene = ""
			ss().session_checkpoint = ""
			ss().session_snapshot = {}
			ss().continue_game()
		"reload":
			# A new process: nothing in memory but the file.
			gs().new_game()
			root.get_node("Monologue").reset()
			ss().session_scene = ""
			ss().session_checkpoint = ""
			ss().session_snapshot = {}
			RT.pending_title = ""
			ss().continue_game()
		"revisit":
			var other: String = ROOMS[(ROOMS.find(path) + 1) % ROOMS.size()]
			change_scene_to_file(other)
			await ticks(8)
			RT.arriving = true
			change_scene_to_file(path)
	await ticks(10)
	room = current_scene
	cat = room.get_node("Cat")
	cat.set("_invuln", 100000.0)


## After a re-entry: the score is exactly `score`, the ids in `gone` have no live node, the
## key / letters survive, and walking over where they were changes nothing.
func check_state(tag: String, path: String, score: int, taken: Array, sc: Dictionary, chips_owed: int, keys: Array, mask: int) -> void:
	note(tag + " same room", room.scene_file_path == path, room.scene_file_path)
	note(tag + " score is exactly %d" % score, gs().score == score, str(gs().score))
	note(tag + " score never exceeds the level maximum", gs().score <= level_max(sc), "%d > %d" % [gs().score, level_max(sc)])
	for it in taken:
		var n := room.get_node_or_null(it.rel)
		note(tag + " " + it.rel.get_file() + " (" + it.key + ") did not reappear", n == null or n.is_queued_for_deletion())
		if it.key == "pickup_key":
			note(tag + " the key is still held", gs().keys.has(it.key_color), str(gs().keys))
	note(tag + " keys held", gs().keys.size() == keys.size(), str(gs().keys))
	note(tag + " letters held", gs().letter_mask == mask, str(gs().letter_mask))
	note(tag + " chips waiting = %d" % chips_owed, chips_lying() == chips_owed, str(chips_lying()))
	# The farm attempt: stand where the collected items were.
	var before: int = gs().score
	for it in taken:
		var pos: Vector2 = it.get("pos", Vector2.ZERO)
		if pos != Vector2.ZERO:
			cat.global_position = pos
			cat.velocity = Vector2.ZERO
			await ticks(3)
	note(tag + " standing where they were adds nothing", gs().score == before and not cat.dead, "%d -> %d" % [before, gs().score])
	var d: Dictionary = ss().read_save()
	if not d.is_empty() and String(d.get("scene", "")) == path:
		note(tag + " the save on disk agrees (score)", int(d.get("score", -1)) == gs().score, "%s vs %d" % [str(d.get("score")), gs().score])


func all_paths(tag: String, path: String, score: int, taken: Array, sc: Dictionary, chips_owed: int) -> void:
	var keys: Array = gs().keys.duplicate()
	var mask: int = gs().letter_mask
	for how in ["death", "continue", "revisit", "reload"]:
		await reenter(how, path)
		await check_state("%s/%s:" % [tag, how], path, score, taken, sc, chips_owed, keys, mask)


# ---- the tests -----------------------------------------------------------------------------

func with_pos(sc: Dictionary) -> void:
	for it in sc.items:
		var n := room.get_node_or_null(it.rel) as Node2D
		if n != null:
			it["pos"] = n.global_position


func sweep(path: String) -> void:
	await begin(path)
	var sc := scan()
	with_pos(sc)
	var mx := level_max(sc)
	for it in sc.items:
		await take(it)
	for b in sc.bots:
		await kill(b)
	var chips := await take_chips()
	var expect_chips := 0
	for b in sc.bots:
		if b.chip:
			expect_chips += 1
	note(path.get_file() + " sweep: every chip taken", chips == expect_chips, "%d/%d" % [chips, expect_chips])
	counts[path.get_file()] = [sc.items.size(), sc.bots.size(), gs().score, mx]
	note(path.get_file() + " sweep: the score is the level maximum (%d)" % mx, gs().score == mx, "%d vs %d" % [gs().score, mx])
	await all_paths(path.get_file() + " sweep", path, gs().score, sc.items, sc, 0)
	var id: String = LevelRegistry.id_for_scene(path)
	if id != "":
		var found := 0
		for c in gs().collected:
			if String(c).begins_with("/root/%s/" % room.name) and String(c).get_file().begins_with("Gem"):
				found += 1
		note(path.get_file() + " map totals: gems found match the collected list", LevelRegistry.gems_found(id) == found and found <= LevelRegistry.gems_total(id) or LevelRegistry.gems_total(id) == 0, "%d / %d" % [LevelRegistry.gems_found(id), LevelRegistry.gems_total(id)])


## One of each type on its own: take it, then try to farm it.
func single(key: String, path: String, sc: Dictionary, it: Dictionary) -> void:
	await begin(path)
	var sc2 := scan()
	with_pos(sc2)
	var item: Dictionary = {}
	for i in sc2.items:
		if i.rel == it.rel:
			item = i
	await take(item)
	var s1: int = gs().score
	note("%s %s: taking it banks %d" % [key, path.get_file(), item.score], s1 == int(item.score), str(s1))
	await all_paths(key + " " + path.get_file(), path, s1, [item], sc2, 0)
	counts["type " + key] = counts.get("type " + key, 0) + 1


func robots(path: String, with_chip: bool) -> void:
	await begin(path)
	var sc := scan()
	var bot: Dictionary = {}
	for b in sc.bots:
		if b.chip == with_chip:
			bot = b
			break
	if bot.is_empty():
		return
	var key := "robot+chip" if with_chip else "robot"
	var base: int = gs().score
	await kill(bot)
	var s1: int = gs().score
	note("%s %s: defeat banks %d" % [key, path.get_file(), bot.points], s1 - base == int(bot.points), str(s1))
	# Die before picking the chip up: the robot stays dead, the chip waits where it fell, once.
	await all_paths(key + " " + path.get_file() + " (chip left)", path, s1, [], sc, 1 if with_chip else 0)
	if with_chip:
		var n := await take_chips()
		note("%s: the owed chip is taken once" % path.get_file(), n == 1 and gs().score == s1 + 1000, "%d %d" % [n, gs().score])
		await all_paths(key + " " + path.get_file() + " (chip taken)", path, s1 + 1000, [], sc, 0)
	var e := room.get_node_or_null(bot.rel)
	note("%s %s: the defeated robot is still gone" % [key, path.get_file()], e == null or e.is_queued_for_deletion())
	counts["type " + key] = counts.get("type " + key, 0) + 1


func _main() -> void:
	COLL = load("res://scripts/kit/collectible.gd")
	RT = load("res://scripts/systems/room_transition.gd")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	# Which types exist where: the first room holding each.
	var first := {}
	var all_sc := {}
	# (The test room holds the plain gem / fish pickups the story rooms no longer use.)
	for path in ROOMS + [TEST_ROOM]:
		await begin(path)
		var sc := scan()
		all_sc[path] = sc
		for it in sc.items:
			if not first.has(it.key):
				first[it.key] = [path, it]
	for path in ROOMS:
		await sweep(path)
	for key in first:
		await single(key, first[key][0], all_sc[first[key][0]], first[key][1])
	for path in ROOMS:
		var has_chip := false
		var has_plain := false
		for b in all_sc[path].bots:
			has_chip = has_chip or b.chip
			has_plain = has_plain or not b.chip
		if has_chip:
			await robots(path, true)
		if has_plain:
			await robots(path, false)
	print("types exercised: ", counts)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	print("%s (%d checks)" % ["COLLECT AUDIT PASS" if fails == 0 else "COLLECT AUDIT FAIL (%d)" % fails, checks])
	quit(0 if fails == 0 else 1)
