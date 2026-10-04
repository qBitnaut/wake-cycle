class_name Hazard
extends Area2D
## Damage zone for the cat. kill = instant death (spikes); otherwise one hit.
## A dashing (PHASE) cat passes through when phase_through is set (lasers).

@export var kill := true
@export var phase_through := false
@export var active := true


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2


func _physics_process(_delta: float) -> void:
	if not active:
		return
	for b in get_overlapping_bodies():
		if b is Cat:
			if phase_through and b.is_phasing():
				continue
			if kill:
				b.kill()
			else:
				b.hurt(global_position)
