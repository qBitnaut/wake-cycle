extends Node
## Runtime game state shared by the cat, pickups, HUD and the save system.
## Registered as the autoload "GameState".

signal health_changed(hp: int)
signal score_changed(score: int)
signal keys_changed
signal letters_changed
signal power_changed(power: int, duration: float)
signal shockwave_unlock_changed(unlocked: bool)

const MAX_HEALTH := 3  # a hit at 0 hp is the fatal 4th hit
const LETTER_BONUS := 5000
const KEY_COLORS := {
	"red": Color("ff4a4a"),
	"blue": Color("5a9bff"),
	"yellow": Color("ffd23f"),
}

var health := MAX_HEALTH
var score := 0
var keys: Array[String] = []
var letters := 0  # next C-A-T letter expected (0..3)
var collected: Array[String] = []  # ids of one-off pickups and opened doors
var shockwave_unlocked := false:
	set(v):
		shockwave_unlocked = v
		shockwave_unlock_changed.emit(v)
var power := NanoPalette.Power.NONE
var power_time := 0.0
var power_duration := 0.0


func _process(delta: float) -> void:
	if power != NanoPalette.Power.NONE:
		power_time -= delta
		if power_time <= 0.0:
			clear_power()


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


## Returns true when the letter was the expected one.
func collect_letter(index: int) -> bool:
	if index != letters:
		return false
	letters += 1
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
		"letters": letters,
		"collected": collected.duplicate(),
		"shockwave": shockwave_unlocked,
	}


func restore(data: Dictionary) -> void:
	health = int(data.get("health", MAX_HEALTH))
	score = int(data.get("score", 0))
	keys.clear()
	for k in data.get("keys", []):
		keys.append(String(k))
	letters = int(data.get("letters", 0))
	collected.clear()
	for c in data.get("collected", []):
		collected.append(String(c))
	shockwave_unlocked = bool(data.get("shockwave", false))
	clear_power()
	health_changed.emit(health)
	score_changed.emit(score)
	keys_changed.emit()
	letters_changed.emit()
