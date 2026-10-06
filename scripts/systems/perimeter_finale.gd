class_name PerimeterFinale
extends Node
## The Master Gate sequence of Room 4. Watches the three PowerRelays; each one
## that lights speaks its count, flashes the scanner's lamp and holds the camera
## on the gatehouse for a moment (a short pan there and back). With all three
## lit, walking into the SecurityScanner starts the scan: a beam over the cat,
## the augments flare, "SUPERVISOR CREDENTIAL ACCEPTED", the gate grinds open
## and the sunrise spills out, then the exit road is free. Sibling nodes by
## name: Relay1..3, Scanner, MasterGate, RoomExit, SkyProgress, Cat.
##
## Fail-safes: the cat is only locked for the (short) cutscenes, always handed
## back; relay and gate state are saved with the checkpoint snapshot; the scan
## can be walked into again if the cat leaves the beam before it starts.

signal relay_lit(count: int)
signal scan_started
signal credential_accepted
signal gate_opened

const GATE_ID := "r4_gate"
## The camera's view centre on the street is this far above the gate's base (the ground sits near
## the bottom of the view and the 7-tile gate fits under the lintel).
const STREET_VIEW_UP := 140.0

var relays: Array[PowerRelay] = []
var scanner: SecurityScanner
var gate: MasterGate
var exit_door: Area2D
var sky: SkyProgress
var cat: Cat

var count := 0
var scanning := false
var accepted := false
var panning := false
## Audit hooks.
var pans := 0
var events: Array[String] = []

## The level's camera driver (made in Level._ready, after this node's).
var _rig: LevelCamera:
	get:
		return (get_parent() as Level).camera_rig


func _ready() -> void:
	var room := get_parent()
	cat = room.get_node("Cat")
	scanner = room.get_node("Scanner")
	gate = room.get_node("MasterGate")
	exit_door = room.get_node_or_null("RoomExit")
	sky = room.get_node_or_null("SkyProgress") as SkyProgress
	for i in 3:
		var r := room.get_node("Relay%d" % (i + 1)) as PowerRelay
		relays.append(r)
		if r.lit:
			count += 1
		else:
			r.activated.connect(_on_relay)
	scanner.set_relays(count)
	scanner.cat_entered.connect(_on_scanner_entered)
	if GameState.is_collected(GATE_ID):
		accepted = true
		gate.set_open_instant()
		scanner.set_accepted()
		if sky:
			sky.dawn = 1.0
	elif exit_door:
		exit_door.set("enabled", false)
	if accepted and exit_door:
		exit_door.set("enabled", true)


# ---- relays ---------------------------------------------------------------

func _on_relay(_index: int) -> void:
	count = 0
	for r in relays:
		if r.lit:
			count += 1
	events.append("relay %d" % count)
	scanner.set_relays(count)
	relay_lit.emit(count)
	Monologue.play_line("relay_done", count - 1)
	_pan_to_gate(2.6 if count >= 3 else 1.6)


## The camera centre that shows the scanner and the gate together, on the street line,
## wherever the cat is: up a tower or down a vault.
func gate_view() -> Vector2:
	return Vector2((scanner.global_position.x + gate.global_position.x) * 0.5, gate.global_position.y - STREET_VIEW_UP)


## Tween the level camera's pan blend (0 follows the cat, 1 sits on `pan_to`).
func _blend(to: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(_rig, "pan_blend", to, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## Pan the camera to the gatehouse, hold, and come back. The cat is held still
## (and handed back at the end, whatever happens).
func _pan_to_gate(hold: float) -> void:
	if panning:
		return
	panning = true
	pans += 1
	var was_free := cat.can_move
	cat.set_can_move(false)
	cat.velocity.x = 0.0
	var target := gate_view()
	var from := cat.camera.get_screen_center_position()
	var secs := clampf(from.distance_to(target) / 1800.0, 0.6, 1.5)
	_rig.pan_to = target
	await _blend(1.0, secs)
	await get_tree().create_timer(hold).timeout
	await _blend(0.0, secs)
	panning = false
	if was_free and not scanning:
		cat.set_can_move(true)


# ---- the scan ----------------------------------------------------------------

func _on_scanner_entered() -> void:
	if count < 3 or scanning or accepted or panning:
		return
	_scan()


func _scan() -> void:
	scanning = true
	scan_started.emit()
	events.append("scan")
	cat.set_can_move(false)
	cat.velocity.x = 0.0
	Monologue.play_once("scanner")
	var aug := cat.get_node_or_null("Sprite/Augments") as CatAugments
	for t in [0.4, 1.4, 2.5]:
		get_tree().create_timer(t).timeout.connect(func():
			if aug and is_instance_valid(aug):
				aug.flare(1.0))
	await scanner.begin_scan(3.2)
	accepted = true
	events.append("credential")
	credential_accepted.emit()
	GameState.mark_collected(GATE_ID)
	Monologue.play_once("credential")
	await get_tree().create_timer(1.8).timeout
	events.append("gate")
	gate.open_gate()
	if sky:
		sky.set_dawn(1.0, 6.0)
	_rig.pan_to = Vector2(gate.global_position.x - 50.0, gate.global_position.y - STREET_VIEW_UP)
	_blend(1.0, 1.0)
	await gate.opened
	await get_tree().create_timer(0.8).timeout
	await _blend(0.0, 1.0)
	if exit_door:
		exit_door.set("enabled", true)
	scanning = false
	cat.set_can_move(true)
	gate_opened.emit()
