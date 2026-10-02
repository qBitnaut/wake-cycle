extends Node
## Loops the nanotech infusion on the lab's test body, cycling the four pad
## colours: goo rises and veins grow, the goo clears, then it resets.

@export var infusion: NanotechInfusion
@export var start_delay := 2.5

const COLORS := [NanoPalette.SURGE, NanoPalette.SPRING, NanoPalette.PHASE, NanoPalette.IMPACT]


func _ready() -> void:
	_loop.call_deferred()


func _loop() -> void:
	await get_tree().create_timer(start_delay).timeout
	var i := 0
	while is_inside_tree():
		infusion.reset()
		infusion.set_color(COLORS[i % COLORS.size()])
		await infusion.infuse(5.0).finished
		await get_tree().create_timer(2.0).timeout
		await infusion.clear_goo(1.6).finished
		await get_tree().create_timer(2.2).timeout
		await infusion.drain(1.4).finished
		await get_tree().create_timer(0.6).timeout
		i += 1
