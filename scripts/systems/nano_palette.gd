class_name NanoPalette
extends RefCounted
## Ids and names for the timed nano-enhancement powers. The colours live in
## FXPalette (the single source of truth); these constants point at them so
## gameplay, HUD and FX can never drift apart.

enum Power { NONE = 0, SURGE = 1, SPRING = 2, PHASE = 3, IMPACT = 4 }

const SURGE := FXPalette.SURGE
const SPRING := FXPalette.SPRING
const PHASE := FXPalette.PHASE
const IMPACT := FXPalette.IMPACT
const SHOCKWAVE := FXPalette.SHOCKWAVE


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
