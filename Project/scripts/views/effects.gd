extends RefCounted


static func shake_node(node: Node, magnitude: float, duration: float) -> void:
	if node == null:
		return
	if not (node is Control or node is Node2D):
		return
	var orig_pos: Vector2 = node.position
	var tw := node.create_tween()
	var step: float = duration / 5.0
	tw.tween_property(node, "position", orig_pos + Vector2(magnitude, 0), step)
	tw.tween_property(node, "position", orig_pos + Vector2(-magnitude, magnitude * 0.5), step)
	tw.tween_property(node, "position", orig_pos + Vector2(magnitude * 0.5, -magnitude * 0.5), step)
	tw.tween_property(node, "position", orig_pos + Vector2(-magnitude * 0.5, 0), step)
	tw.tween_property(node, "position", orig_pos, step)


static func flash_rect(rect: ColorRect, color: Color, duration: float) -> void:
	if rect == null:
		return
	rect.color = Color(color.r, color.g, color.b, 0.35)
	rect.visible = true
	var tw := rect.create_tween()
	tw.tween_property(rect, "color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): rect.visible = false)
