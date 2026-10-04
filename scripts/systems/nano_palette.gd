class_name NanoPalette
extends RefCounted
## Shared colours and ids for the timed nano-enhancement powers.

enum Power { NONE = 0, SURGE = 1, SPRING = 2, PHASE = 3, IMPACT = 4 }

const SURGE := Color("3a8dff")
const SPRING := Color("46e06b")
const PHASE := Color("3de8e8")
const IMPACT := Color("a35cff")
const SHOCKWAVE := Color("ffc94a")


static func color_of(power: int) -> Color:
	match power:
		Power.SURGE:
			return SURGE
		Power.SPRING:
			return SPRING
		Power.PHASE:
			return PHASE
		Power.IMPACT:
			return IMPACT
	return Color.WHITE


static func name_of(power: int) -> String:
	match power:
		Power.SURGE:
			return "SURGE"
		Power.SPRING:
			return "SPRING"
		Power.PHASE:
			return "PHASE"
		Power.IMPACT:
			return "IMPACT"
	return ""
