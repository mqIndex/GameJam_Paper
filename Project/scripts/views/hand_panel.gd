extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const CardButtonScene = preload("res://scenes/ui/card_button.tscn")

@onready var fan_container: Control = $FanHandContainer

const ENTER_DURATION: float = 0.34
const DISCARD_DURATION: float = 0.28
const ENTER_STAGGER: float = 0.045
const CARD_ANIM_Z: int = 260

var _last_hand_keys: Array = []
var _pending_enter_keys: Dictionary = {}


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.hand_changed.connect(_refresh_hand)
	Game.state_changed.connect(_refresh_state)


func _refresh_hand() -> void:
	var next_keys: Array = _make_hand_keys()
	var removed_indices: Array = _find_removed_card_indices(next_keys)
	var enter_indices: Array = _find_enter_card_indices(next_keys)
	var enter_specs: Array = _make_enter_specs(enter_indices, next_keys)
	for spec in enter_specs:
		_pending_enter_keys[String(spec["key"])] = true
	_play_discard_animations(removed_indices)
	for c in fan_container.get_children():
		fan_container.remove_child(c)
		c.queue_free()
	for i in range(Game.hand.size()):
		var card: Card = Game.hand[i]
		var btn = CardButtonScene.instantiate()
		fan_container.add_child(btn)
		btn.setup(card, i)
		if _pending_enter_keys.has(String(next_keys[i])):
			btn.visible = false
	if fan_container.has_method("relayout_cards"):
		fan_container.relayout_cards()
	_last_hand_keys = next_keys
	if not enter_specs.is_empty():
		call_deferred("_play_enter_animations", enter_specs)


func _refresh_state() -> void:
	if fan_container == null:
		return
	var children: Array = fan_container.get_children()
	for i in range(min(children.size(), Game.hand.size())):
		var btn = children[i] as Button
		if btn == null:
			continue
		var c: Card = Game.hand[i]
		btn.disabled = (Game.action_points < c.cost) or (Game.phase != Game.Phase.PLAY) or Game.is_level_over


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("card_index")


func _drop_data(_at_position: Vector2, _data: Variant) -> void:
	pass


func _make_hand_keys() -> Array:
	var keys: Array = []
	for card in Game.hand:
		keys.append(_card_key(card))
	return keys


func _card_key(card: Card) -> String:
	if card == null:
		return ""
	if card.id != "":
		return card.id
	return "%s:%s" % [card.effect_id, card.name]


func _find_enter_card_indices(next_keys: Array) -> Array:
	var old_counts: Dictionary = {}
	for key in _last_hand_keys:
		old_counts[key] = int(old_counts.get(key, 0)) + 1
	var seen_counts: Dictionary = {}
	var indices: Array = []
	for i in range(next_keys.size()):
		var key: String = String(next_keys[i])
		seen_counts[key] = int(seen_counts.get(key, 0)) + 1
		if int(seen_counts[key]) > int(old_counts.get(key, 0)):
			indices.append(i)
	return indices


func _find_removed_card_indices(next_keys: Array) -> Array:
	var next_counts: Dictionary = {}
	for key in next_keys:
		next_counts[key] = int(next_counts.get(key, 0)) + 1
	var indices: Array = []
	for i in range(_last_hand_keys.size()):
		var key: String = String(_last_hand_keys[i])
		var keep_count: int = int(next_counts.get(key, 0))
		if keep_count > 0:
			next_counts[key] = keep_count - 1
		else:
			indices.append(i)
	return indices


func _make_enter_specs(indices: Array, next_keys: Array) -> Array:
	var specs: Array = []
	for idx in indices:
		var i: int = int(idx)
		if i < 0 or i >= next_keys.size():
			continue
		specs.append({
			"index": i,
			"key": String(next_keys[i]),
			"order": specs.size(),
		})
	return specs


func _play_enter_animations(specs: Array) -> void:
	if fan_container == null:
		return
	var children: Array = fan_container.get_children()
	var current_keys: Array = _make_hand_keys()
	var source_global := fan_container.get_global_rect().position + Vector2(
		max(0.0, fan_container.size.x - 34.0),
		-78.0
	)
	for spec in specs:
		var key: String = String(spec["key"])
		var i: int = int(spec["index"])
		if i < 0 or i >= children.size() or i >= current_keys.size():
			_pending_enter_keys.erase(key)
			continue
		if String(current_keys[i]) != key:
			_pending_enter_keys.erase(key)
			continue
		var card := children[i] as Control
		if card == null:
			_pending_enter_keys.erase(key)
			continue
		_play_single_enter(card, key, source_global, float(int(spec["order"])) * ENTER_STAGGER, -1.0 if i % 2 == 0 else 1.0)


func _play_single_enter(card: Control, key: String, source_global: Vector2, delay: float, direction: float) -> void:
	var ghost := card.duplicate() as Control
	if ghost == null:
		card.visible = true
		_pending_enter_keys.erase(key)
		return
	var overlay_parent: Node = get_tree().root.get_node_or_null("Main")
	if overlay_parent == null:
		overlay_parent = get_tree().root
	overlay_parent.add_child(ghost)
	ghost.top_level = true
	ghost.visible = true
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ghost is Button:
		(ghost as Button).disabled = false
	ghost.pivot_offset = card.pivot_offset
	ghost.global_position = source_global
	var target_rotation: float = card.rotation_degrees
	var target_global: Vector2 = card.global_position
	ghost.z_index = CARD_ANIM_Z
	ghost.modulate = Color(1.0, 0.95, 0.72, 0.92)
	ghost.scale = Vector2(0.14, 0.14)
	ghost.rotation_degrees = 15.0 * direction
	card.set_meta("_hand_animating", true)
	card.visible = false
	var tw := ghost.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(ghost, "global_position", target_global, ENTER_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", Vector2(1.08, 1.08), ENTER_DURATION * 0.78).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "rotation_degrees", target_rotation, ENTER_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "modulate", Color.WHITE, ENTER_DURATION * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(ghost, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(Callable(self, "_finish_enter_animation").bind(weakref(card), weakref(ghost), key))


func _finish_enter_animation(card_ref: WeakRef, ghost_ref: WeakRef, key: String) -> void:
	var card := card_ref.get_ref() as Control
	if card != null:
		card.visible = true
		card.remove_meta("_hand_animating")
		card.scale = Vector2.ONE
		card.modulate = Color.WHITE
		card.z_index = 0
	var ghost := ghost_ref.get_ref() as Node
	if ghost != null:
		ghost.queue_free()
	_pending_enter_keys.erase(key)


func _play_discard_animations(indices: Array) -> void:
	if indices.is_empty() or fan_container == null:
		return
	var children: Array = fan_container.get_children()
	var target: Vector2 = _discard_target_global_position()
	for idx in indices:
		var i: int = int(idx)
		if i < 0 or i >= children.size():
			continue
		var card := children[i] as Control
		if card == null:
			continue
		_spawn_discard_ghost(card, target, -1.0 if i % 2 == 0 else 1.0)


func _spawn_discard_ghost(card: Control, target_global: Vector2, direction: float) -> void:
	var ghost := card.duplicate() as Control
	if ghost == null:
		return
	var overlay_parent: Node = get_tree().root.get_node_or_null("Main")
	if overlay_parent == null:
		overlay_parent = get_tree().root
	overlay_parent.add_child(ghost)
	ghost.top_level = true
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.pivot_offset = card.pivot_offset
	ghost.global_position = card.global_position
	ghost.rotation_degrees = card.rotation_degrees
	ghost.scale = card.scale
	ghost.modulate = Color.WHITE
	ghost.z_index = CARD_ANIM_Z + 1
	var target_pos: Vector2 = target_global - ghost.pivot_offset
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "global_position", target_pos, DISCARD_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "scale", Vector2(0.18, 0.18), DISCARD_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "rotation_degrees", 24.0 * direction, DISCARD_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "modulate", Color(1.0, 0.72, 0.88, 0.0), DISCARD_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(Callable(self, "_free_discard_ghost").bind(weakref(ghost)))


func _free_discard_ghost(ghost_ref: WeakRef) -> void:
	var ghost := ghost_ref.get_ref() as Node
	if ghost != null:
		ghost.queue_free()


func _discard_target_global_position() -> Vector2:
	var target_node := get_tree().root.find_child("DiscardPileButton", true, false) as Control
	if target_node != null:
		var r := target_node.get_global_rect()
		return r.position + r.size * 0.5
	var self_rect := get_global_rect()
	return Vector2(self_rect.end.x + 80.0, self_rect.position.y + self_rect.size.y * 0.45)
