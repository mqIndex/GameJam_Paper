extends RefCounted

const SHAKE_BASE_POS_META: String = "_effects_shake_base_position"
const SHAKE_TWEEN_META: String = "_effects_shake_tween"
const SHAKE_TOKEN_META: String = "_effects_shake_token"


static func shake_node(node: Node, magnitude: float, duration: float) -> void:
	if node == null:
		return
	if not (node is Control or node is Node2D):
		return
	var orig_pos: Vector2 = _prepare_shake_base(node)
	var token: int = int(node.get_meta(SHAKE_TOKEN_META, 0)) + 1
	node.set_meta(SHAKE_TOKEN_META, token)
	var tw := node.create_tween()
	node.set_meta(SHAKE_TWEEN_META, tw)
	var step: float = duration / 5.0
	tw.tween_property(node, "position", orig_pos + Vector2(magnitude, 0), step)
	tw.tween_property(node, "position", orig_pos + Vector2(-magnitude, magnitude * 0.5), step)
	tw.tween_property(node, "position", orig_pos + Vector2(magnitude * 0.5, -magnitude * 0.5), step)
	tw.tween_property(node, "position", orig_pos + Vector2(-magnitude * 0.5, 0), step)
	tw.tween_property(node, "position", orig_pos, step)
	var node_ref: WeakRef = weakref(node)
	tw.tween_callback(func():
		var target := node_ref.get_ref() as Node
		if target == null or not is_instance_valid(target):
			return
		if int(target.get_meta(SHAKE_TOKEN_META, -1)) != token:
			return
		_set_node_position(target, orig_pos)
		target.remove_meta(SHAKE_BASE_POS_META)
		target.remove_meta(SHAKE_TWEEN_META)
		target.remove_meta(SHAKE_TOKEN_META)
	)


static func _prepare_shake_base(node: Node) -> Vector2:
	var base_pos: Vector2 = _get_node_position(node)
	if node.has_meta(SHAKE_BASE_POS_META):
		base_pos = node.get_meta(SHAKE_BASE_POS_META) as Vector2
		var prev = node.get_meta(SHAKE_TWEEN_META, null)
		if prev != null and prev.is_valid():
			prev.kill()
		_set_node_position(node, base_pos)
	else:
		node.set_meta(SHAKE_BASE_POS_META, base_pos)
	return base_pos


static func _get_node_position(node: Node) -> Vector2:
	if node is Control:
		return (node as Control).position
	if node is Node2D:
		return (node as Node2D).position
	return Vector2.ZERO


static func _set_node_position(node: Node, value: Vector2) -> void:
	if node is Control:
		(node as Control).position = value
	elif node is Node2D:
		(node as Node2D).position = value


static func flash_rect(rect: ColorRect, color: Color, duration: float) -> void:
	if rect == null:
		return
	rect.color = Color(color.r, color.g, color.b, 0.35)
	rect.visible = true
	var tw := rect.create_tween()
	var rect_ref: WeakRef = weakref(rect)
	tw.tween_property(rect, "color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		var node := rect_ref.get_ref() as ColorRect
		if node != null:
			node.visible = false
	)
