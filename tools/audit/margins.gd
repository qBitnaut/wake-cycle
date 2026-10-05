## The human-margin audit for every required climb and long jump of Rooms 1-4
## and the test room (spot lists: tools/audit/spots.gd; method: human_sweep.gd).
##   godot --headless --path . --fixed-fps 60 --script res://tools/audit/margins.gd
##   ROOMS=room3,room4 godot ... (a subset)
## Each intended move must land in >= 90% of the realistic input sweep, each
## unintended way (no power, the wrong power, a skip) in 0%. Exit code 1 on a
## failure. Prints every measured rate so a tuning change can be compared.
extends SceneTree

const HumanSweep := preload("res://tools/audit/human_sweep.gd")

var results: Array = []


func _initialize() -> void:
	_main.call_deferred()


func note(name: String, ok: bool, detail := "") -> void:
	results.append([name, ok, detail])
	print("%s  %-72s %s" % ["PASS" if ok else "FAIL", name, detail])


func _main() -> void:
	var ss := root.get_node("SaveSystem")
	var want := OS.get_environment("ROOMS")
	var ids := ["room1", "room2", "room3", "room4", "test_room"]
	for id in ids:
		if want != "" and not want.split(",").has(id):
			continue
		var only := OS.get_environment("SPOTS")
		# FULL=1: run every trial of every move and print the rates (before/after reports).
		await HumanSweep.lab(self, id, note, "", OS.get_environment("FULL") == "1", only)
	var ok_all := results.all(func(r): return r[1])
	print("== %d checks, %s" % [results.size(), "ALL PASS" if ok_all else "FAILURES"])
	ss.delete_save()
	quit(0 if ok_all else 1)
