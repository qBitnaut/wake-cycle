class_name NanoPalette
extends RefCounted
## One source of truth for the nanotech power colours, shared by enhancement
## pads, the vein overlay and anything else that signals a power.

enum Power { SURGE, SPRING, PHASE, IMPACT }

const SURGE := Color(0.16, 0.42, 1.0)   ## Blue: speed.
const SPRING := Color(0.2, 1.0, 0.5)    ## Green: high jump.
const PHASE := Color(0.18, 0.92, 1.0)   ## Cyan: dash.
const IMPACT := Color(0.62, 0.34, 1.0)  ## Violet: ground pound.
const POOL_A := Color(0.12, 0.42, 1.0)  ## Nanotech pool trace blue.
const POOL_B := Color(0.15, 1.0, 0.55)  ## Nanotech pool trace green.


static func color_of(power: Power) -> Color:
	match power:
		Power.SPRING:
			return SPRING
		Power.PHASE:
			return PHASE
		Power.IMPACT:
			return IMPACT
	return SURGE
