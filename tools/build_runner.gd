## Runs a scene builder with the project's autoloads live, then quits with an exit
## code (0 ok, 1 build or save errors, 2 bad arguments). Usage:
##   godot --headless --path . res://tools/build_runner.tscn -- --builder=res://tools/build_room3.gd
## (--script mode does not register autoloads, so builders cannot compile there.)
##
## A builder is a script with `extends RefCounted`, `func build()` and `var errors`.
##
## Determinism: Godot assigns random unique_ids to nodes and random ids to
## ext_resources and sub_resources on every save. After the builder saves, the runner
## re-reads each scene it wrote and restores the ids of the previous version of the
## same file (nodes by path, ext_resources by path, sub_resources by type and order),
## so a rebuild of unchanged content gives an unchanged file.
extends Node

var _scenes_before := {}


func _ready() -> void:
	var builder := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--builder="):
			builder = a.substr(10)
	if builder == "" or not ResourceLoader.exists(builder):
		printerr("build_runner: pass --builder=res://tools/build_X.gd")
		get_tree().quit(2)
		return
	var snap := _snapshot()
	var script := load(builder) as GDScript
	var b = script.new() if script != null and script.can_instantiate() else null
	if b == null or not b.has_method("build"):
		printerr("build_runner: ", builder, " does not compile or has no build()")
		get_tree().quit(2)
		return
	b.build()
	var restored := _restore_ids(snap)
	print("build_runner: ", builder, ", errors ", b.get("errors"), ", scenes with ids restored ", restored)
	get_tree().quit(1 if int(b.get("errors")) > 0 else 0)


## Text of every .tscn under scenes/ before the build.
func _snapshot() -> Dictionary:
	var out := {}
	_walk("res://scenes", out)
	return out


func _walk(dir: String, out: Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out[dir + "/" + f] = FileAccess.get_file_as_string(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_walk(dir + "/" + d, out)


func _restore_ids(before: Dictionary) -> int:
	var after := {}
	_walk("res://scenes", after)
	var n := 0
	for path in after:
		if not before.has(path) or before[path] == after[path]:
			continue
		var fixed := _remap(before[path], after[path])
		if fixed != after[path]:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(fixed)
			f.close()
			n += 1
	return n


# Header lines look like: [node name="X" type="Y" parent="." unique_id=123]
var _re_name := RegEx.create_from_string("^\\[node name=\"([^\"]*)\"")
var _re_parent := RegEx.create_from_string(" parent=\"([^\"]*)\"")
var _re_uid := RegEx.create_from_string(" unique_id=(\\d+)")
var _re_ext := RegEx.create_from_string("^\\[ext_resource [^\\]]*?path=\"([^\"]*)\"[^\\]]* id=\"([^\"]*)\"")
var _re_sub := RegEx.create_from_string("^\\[sub_resource type=\"([^\"]*)\" id=\"([^\"]*)\"")


## Maps a scene's ids onto the ids of its older text, keyed by structure.
func _keys(text: String) -> Dictionary:
	var node_ids := {}   # node path -> unique_id
	var ext_ids := {}    # resource path -> id
	var sub_ids := {}    # "Type#n" -> id
	var sub_count := {}
	for line in text.split("\n"):
		if line.begins_with("[node "):
			var key := _node_key(line)
			var u := _re_uid.search(line)
			if u:
				node_ids[key] = u.get_string(1)
		elif line.begins_with("[ext_resource"):
			var m := _re_ext.search(line)
			if m:
				ext_ids[m.get_string(1)] = m.get_string(2)
		elif line.begins_with("[sub_resource"):
			var m := _re_sub.search(line)
			if m:
				var t := m.get_string(1)
				sub_count[t] = int(sub_count.get(t, 0)) + 1
				sub_ids["%s#%d" % [t, sub_count[t]]] = m.get_string(2)
	return {"node": node_ids, "ext": ext_ids, "sub": sub_ids}


func _node_key(line: String) -> String:
	var name := _re_name.search(line).get_string(1)
	var p := _re_parent.search(line)
	return name if p == null else p.get_string(1) + "/" + name


func _remap(old_text: String, new_text: String) -> String:
	var old := _keys(old_text)
	var cur := _keys(new_text)
	var used := {}
	# Resource ids first, as whole-token replacements via a two-step placeholder swap.
	var swaps := {}   # current id -> old id
	for k in cur["ext"]:
		if old["ext"].has(k) and not used.has(old["ext"][k]):
			swaps[cur["ext"][k]] = old["ext"][k]
			used[old["ext"][k]] = true
	for k in cur["sub"]:
		if old["sub"].has(k) and not used.has(old["sub"][k]):
			swaps[cur["sub"][k]] = old["sub"][k]
			used[old["sub"][k]] = true
	var out := PackedStringArray()
	for line in new_text.split("\n"):
		if line.begins_with("[node "):
			var u := _re_uid.search(line)
			var key := _node_key(line)
			if u and old["node"].has(key):
				line = line.replace(" unique_id=" + u.get_string(1), " unique_id=" + old["node"][key])
		if not swaps.is_empty():
			for cid in swaps:
				if swaps[cid] == cid:
					continue
				line = line.replace("id=\"" + cid + "\"", "id=\"\u0001" + swaps[cid] + "\"")
				line = line.replace("Resource(\"" + cid + "\")", "Resource(\"\u0001" + swaps[cid] + "\")")
			line = line.replace("\u0001", "")
		out.append(line)
	return "\n".join(out)
