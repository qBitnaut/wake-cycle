class_name Blast
extends RefCounted
## One explosion's gameplay: damage in a radius to enemies, the cat, walls and
## other explosive things (the chain reaction), plus the visuals.
##
## Receivers (join these groups, implement the method):
##   "enemy"          on_blast(origin, radius)   robots take damage
##   "explosive"      trigger(delay)             barrels go off in turn
##   "blast_receiver" on_blast(origin, radius)   walls break
## The cat is hurt once if its body is inside the radius (a phasing cat is not).

const CHAIN_DELAY := 0.14


static func box_distance(pos: Vector2, centre: Vector2, half: Vector2) -> float:
	var d := (pos - centre).abs() - half
	return d.max(Vector2.ZERO).length()


static func explode(ctx: Node, pos: Vector2, radius: float, source: Node = null, hurts_cat := true, fx := true) -> void:
	var tree := ctx.get_tree()
	if fx:
		ExplosionFX.spawn(ctx.get_parent() if ctx.get_parent() else ctx, pos, radius / 40.0, 0, Color(0.7, 0.55, 0.4))
		KitSfx.play(ctx, "barrel_explode")
	for n in tree.get_nodes_in_group("explosive"):
		if n == source or not n.has_method("trigger"):
			continue
		var c: Vector2 = n.global_position + Vector2(n.get("shock_offset"))
		var d := box_distance(pos, c, Vector2(n.get("shock_half")))
		if d <= radius:
			n.trigger(CHAIN_DELAY + 0.05 * d / maxf(radius, 1.0))
	for grp in ["enemy", "blast_receiver"]:
		for n in tree.get_nodes_in_group(grp):
			if n == source or not n.has_method("on_blast"):
				continue
			var c2: Vector2 = n.global_position + Vector2(n.get("shock_offset"))
			if box_distance(pos, c2, Vector2(n.get("shock_half"))) <= radius:
				n.on_blast(pos, radius)
	if hurts_cat:
		var cat := tree.get_first_node_in_group("player") as Cat
		if cat != null and not cat.dead and not cat.is_phasing():
			var half_h := (Cat.CROUCH_H if cat.crouched else Cat.STAND_H) * 0.5
			if box_distance(pos, cat.global_position + Vector2(0, -half_h), Vector2(Cat.WIDTH * 0.5, half_h)) <= radius:
				cat.hurt(pos)
