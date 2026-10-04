class_name FXScale
extends RefCounted
## Resolution independence for the FX kit.
##
## The kit was tuned at a 320x180 internal resolution. "Feel" constants
## (speeds, gravity, shake, line widths, font size, noise feature size) are
## written in those reference pixels and multiplied by factor(), so the same
## scene reads the same at 640x360 (factor 2) or any other internal size.
##
## Geometry exports (widths, lengths, radii, floor_y, positions) are world
## pixels and are never scaled: they come from the level.
##
## The factor is the internal viewport height / 180. Set `override` (> 0) to
## pin it, e.g. if the game renders 640x360 but wants the 320x180 feel.

const REFERENCE_HEIGHT := 180.0

static var override := 0.0


## Scale factor for `node`'s viewport (1.0 at 320x180, 2.0 at 640x360).
static func factor(node: Node) -> float:
	if override > 0.0:
		return override
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height", REFERENCE_HEIGHT))
	# In the editor the viewport is the editor's own, so trust the project size.
	if node != null and node.is_inside_tree() and not Engine.is_editor_hint():
		h = node.get_viewport().get_visible_rect().size.y
	return maxf(h / REFERENCE_HEIGHT, 0.25)


## The factor rounded to a whole number (at least 1), for things that must
## stay on the pixel grid: particle pixel size, line width, font multiple,
## and the default scale of the kit's own baked reference-resolution art.
static func whole(node: Node) -> int:
	return maxi(roundi(factor(node)), 1)
