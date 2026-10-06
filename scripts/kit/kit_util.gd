class_name KitUtil
extends RefCounted
## Small shared helpers for the kit.


## Add `n` under `parent` already standing at global `pos`, so its _ready sees the
## right global_position (add-then-move leaves _ready at the origin).
static func add_at(parent: Node, n: Node2D, pos: Vector2, deferred := false) -> void:
	if parent is CanvasItem:
		n.position = (parent as CanvasItem).get_global_transform().affine_inverse() * pos
	else:
		n.position = pos
	if deferred:
		parent.add_child.call_deferred(n)
	else:
		parent.add_child(n)
