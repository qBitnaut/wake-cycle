class_name FXPalette
extends RefCounted
## One source of truth for the atmosphere and power colours. Every FX piece
## reads from here, so a palette change is one edit.
##
## Values are sRGB and pass straight through the Compatibility renderer (no
## linear conversion, even with hdr_2d). Anything above 1.0 is HDR and feeds
## the 2D glow, so emissive colours are multiplied up, never clamped.

## Enhancement pad kinds. CHECKPOINT is not a power, but shares the pad visual.
enum Pad { SURGE, SPRING, PHASE, IMPACT, CHECKPOINT }

# Night.
const NIGHT_TINT := Color(0.17, 0.20, 0.32)   ## CanvasModulate: the unlit world.
const MOON := Color(0.70, 0.80, 1.0)          ## Moonlight: silver-blue, less saturated than nanotech.
const MOON_RAY := Color(0.55, 0.68, 1.0)      ## Additive god-ray haze.
const FOG := Color(0.42, 0.50, 0.70)          ## Fog body, lit by the night tint.
const RAIN := Color(0.70, 0.80, 0.95)
const LIGHTNING := Color(0.85, 0.90, 1.0)

# Hostile (red means hostile): laser beams, enemy eyes. Matches palette.md.
const LASER := Color(1.0, 0.29, 0.23)          ## #ff4a3a beam body.
const LASER_CORE := Color(1.0, 0.94, 0.88)     ## #fff0e0 beam centre line.

# Back-wall status lights (muted aqua, never a power hue).
const INDICATOR := Color(0.255, 0.71, 0.753)   ## #41b5c0, drawn unshaded at 0.8.

# Warm accents.
const SODIUM := Color(1.0, 0.55, 0.16)        ## Flickering warning light.
const SPARK := Color(1.0, 0.78, 0.40)

# Nanotech.
const NANO_BLUE := Color(0.12, 0.42, 1.0)
const NANO_GREEN := Color(0.15, 1.0, 0.55)

# Powers (same values as the 3D NanoPalette, so the look carries over).
const SURGE := Color(0.16, 0.42, 1.0)         ## Blue: speed.
const SPRING := Color(0.2, 1.0, 0.5)          ## Green: high jump.
const PHASE := Color(0.18, 0.92, 1.0)         ## Cyan: dash.
const IMPACT := Color(0.62, 0.34, 1.0)        ## Violet: ground pound.
const SHOCKWAVE := Color(1.0, 0.79, 0.29)     ## Gold: the double-jump burst (warm: it is the cat's).
const CHECKPOINT := Color(0.55, 1.0, 0.86)    ## Pale teal: safe, not a power. Also the Continue pad.
const START_OVER := Color(1.0, 0.33, 0.20)    ## Warm red-orange: the Start Over pad (never a power hue).


static func pad_color(kind: Pad) -> Color:
	match kind:
		Pad.SPRING:
			return SPRING
		Pad.PHASE:
			return PHASE
		Pad.IMPACT:
			return IMPACT
		Pad.CHECKPOINT:
			return CHECKPOINT
	return SURGE
