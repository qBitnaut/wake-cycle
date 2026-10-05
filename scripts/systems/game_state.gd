extends Node
## Runtime game state shared by the cat, pickups, HUD and the save system.
## Registered as the autoload "GameState".

signal health_changed(hp: int)
signal score_changed(score: int)
signal keys_changed
signal letters_changed
## The goo's gift (Room 1): the cat's mind wakes. Hook for the inner monologue.
signal mind_awakened
signal power_changed(power: int, duration: float)
signal shockwave_unlock_changed(unlocked: bool)
## Room 1: the cat has stepped into the nanotech pool and the transformation begins.
signal nanotech_absorbed_started

const MAX_HEALTH := 3  # a hit at 0 hp is the fatal 4th hit
const LETTER_BONUS := 5000
## Key colours avoid the reserved hues: no glowing blue, green, cyan, violet
## (nano powers) and no red (hostile). Brass is the default test-room key.
const KEY_COLORS := {
	"brass": Color("e0c840"),
	"bone": Color("d9dede"),
	"rose": Color("c98068"),
}

var health := MAX_HEALTH
var score := 0
var keys: Array[String] = []
## Hidden C-A-T bonus letters, found in any order: bit 0 = C, 1 = A, 2 = T.
var letter_mask := 0
var letters: int:  # how many are found (0..3)
	get:
		return (letter_mask & 1) + ((letter_mask >> 1) & 1) + ((letter_mask >> 2) & 1)
## True once the pool in Room 1 has awakened the cat's mind (saved).
var intelligence := false
var collected: Array[String] = []  # ids of one-off pickups and opened doors
var shockwave_unlocked := false:
	set(v):
		shockwave_unlocked = v
		shockwave_unlock_changed.emit(v)
var power := NanoPalette.Power.NONE
var power_time := 0.0
var power_duration := 0.0
## World map progress (WorldMap, LevelRegistry): level ids finished, level ids
## unlocked, and the node the cat stands on. Saved under "map".
var map_completed: Array[String] = []
var map_unlocked: Array[String] = []
var map_node := ""


func _process(delta: float) -> void:
	if power != NanoPalette.Power.NONE:
		power_time -= delta
		if power_time <= 0.0:
			clear_power()


## A fresh game: nothing unlocked, nothing held, full health.
func new_game() -> void:
	health = MAX_HEALTH
	score = 0
	keys.clear()
	letter_mask = 0
	intelligence = false
	collected.clear()
	shockwave_unlocked = false
	map_completed.clear()
	map_unlocked.clear()
	map_node = ""
	clear_power()
	health_changed.emit(health)
	score_changed.emit(score)
	keys_changed.emit()
	letters_changed.emit()


## The cat's mind wakes (the goo's gift). Emits mind_awakened once.
func awaken_mind() -> void:
	if intelligence:
		return
	intelligence = true
	mind_awakened.emit()


## Unlocks the double jump's shockwave. Not used in Room 1: a later room grants it.
func unlock_shockwave() -> void:
	shockwave_unlocked = true


func grant_power(p: int, duration: float) -> void:
	power = p
	power_duration = duration
	power_time = duration
	power_changed.emit(power, duration)


func clear_power() -> void:
	power = NanoPalette.Power.NONE
	power_time = 0.0
	power_changed.emit(power, 0.0)


func set_health(hp: int) -> void:
	health = clampi(hp, 0, MAX_HEALTH)
	health_changed.emit(health)


func add_score(n: int) -> void:
	score += n
	score_changed.emit(score)


func add_key(color: String) -> void:
	if not keys.has(color):
		keys.append(color)
		keys_changed.emit()


func use_key(color: String) -> bool:
	if keys.has(color):
		keys.erase(color)
		keys_changed.emit()
		return true
	return false


## Returns true when the letter was newly found (any order). All three: bonus.
func collect_letter(index: int) -> bool:
	var bit := 1 << index
	if letter_mask & bit:
		return false
	letter_mask |= bit
	letters_changed.emit()
	if letters == 3:
		add_score(LETTER_BONUS)
	return true


func is_collected(id: String) -> bool:
	return collected.has(id)


func mark_collected(id: String) -> void:
	if not collected.has(id):
		collected.append(id)


func snapshot() -> Dictionary:
	return {
		"health": health,
		"score": score,
		"keys": keys.duplicate(),
		"letter_mask": letter_mask,
		"mind": intelligence,
		"collected": collected.duplicate(),
		"shockwave": shockwave_unlocked,
		"map": map_snapshot(),
	}


## The world map's progress as saved: {"completed", "unlocked", "node"}.
func map_snapshot() -> Dictionary:
	return {"completed": map_completed.duplicate(), "unlocked": map_unlocked.duplicate(), "node": map_node}


## Restores map progress from map_snapshot()'s shape (missing keys: empty).
func restore_map(m: Dictionary) -> void:
	map_completed.clear()
	for c in m.get("completed", []):
		map_completed.append(String(c))
	map_unlocked.clear()
	for u in m.get("unlocked", []):
		map_unlocked.append(String(u))
	map_node = String(m.get("node", ""))


func restore(data: Dictionary) -> void:
	health = int(data.get("health", MAX_HEALTH))
	score = int(data.get("score", 0))
	keys.clear()
	for k in data.get("keys", []):
		keys.append(String(k))
	letter_mask = int(data.get("letter_mask", 0))
	intelligence = bool(data.get("mind", false))
	collected.clear()
	for c in data.get("collected", []):
		collected.append(String(c))
	shockwave_unlocked = bool(data.get("shockwave", false))
	# Snapshots from before the world map have no "map": keep what is held.
	if data.has("map"):
		restore_map(data["map"])
	clear_power()
	health_changed.emit(health)
	score_changed.emit(score)
	keys_changed.emit()
	letters_changed.emit()
