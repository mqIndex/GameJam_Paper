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
var _block_hint: PanelContainer = null
var _block_hint_label: Label = null
var _block_hint_tween: Tween = null
var _block_hint_source: WeakRef = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	_build_block_hint()
	Game.hand_changed.connect(_refresh_hand)
	Game.state_changed.connect(_refresh_state)
	Game.phase_changed.connect(_on_phase_changed)
	Game.card_play_blocked.connect(_on_global_card_play_blocked)


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
		if btn.has_signal("play_blocked"):
			btn.play_blocked.connect(_on_card_play_blocked)
		if btn.has_signal("play_block_hint_cleared"):
			btn.play_block_hint_cleared.connect(_on_card_play_hint_cleared)
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
		var btn = children[i] as Control
		if btn == null:
			continue
		if btn.has_method("refresh_play_block_reason"):
			btn.call("refresh_play_block_reason")
		elif btn.has_method("set_play_block_reason"):
			btn.call("set_play_block_reason", Game.get_card_play_block_reason(i))


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("card_index")


func _drop_data(_at_position: Vector2, _data: Variant) -> void:
	pass


func _build_block_hint() -> void:
	_block_hint = PanelContainer.new()
	_block_hint.name = "CardBlockReasonHint"
	_block_hint.top_level = true
	_block_hint.visible = false
	_block_hint.z_index = 245
	_block_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.13, 0.90)
	sb.border_color = Color(UF.COL_HIGHLIGHT.r, UF.COL_HIGHLIGHT.g, UF.COL_HIGHLIGHT.b, 0.82)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 8.0
	_block_hint.add_theme_stylebox_override("panel", sb)
	_block_hint_label = Label.new()
	_block_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_block_hint_label.custom_minimum_size = Vector2(360.0, 0.0)
	_block_hint_label.add_theme_font_size_override("font_size", 13)
	_block_hint_label.add_theme_color_override("font_color", UF.COL_TEXT)
	_block_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	_block_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_block_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_block_hint.add_child(_block_hint_label)
	add_child(_block_hint)


func _on_card_play_blocked(reason: String, source: Control) -> void:
	show_play_block_reason(reason, source)


func _on_card_play_hint_cleared(source: Control) -> void:
	hide_play_block_reason(source)


func _on_global_card_play_blocked(reason: String) -> void:
	show_play_block_reason(reason)


func _on_phase_changed(_phase: int) -> void:
	_refresh_state()


func show_play_block_reason(reason: String, source: Control = null) -> void:
	if reason == "" or _block_hint == null or _block_hint_label == null:
		hide_play_block_reason()
		return
	_block_hint_source = weakref(source) if source != null else null
	_block_hint_label.text = reason
	_block_hint.visible = true
	_block_hint.modulate = Color(1, 1, 1, 0)
	_block_hint.reset_size()
	call_deferred("_position_block_hint", weakref(source) if source != null else null)
	if _block_hint_tween != null and _block_hint_tween.is_valid():
		_block_hint_tween.kill()
	_block_hint_tween = create_tween()
	_block_hint_tween.tween_property(_block_hint, "modulate:a", 1.0, 0.10)
	_block_hint_tween.tween_interval(1.85)
	_block_hint_tween.tween_property(_block_hint, "modulate:a", 0.0, 0.22)
	_block_hint_tween.tween_callback(_hide_block_hint)


func hide_play_block_reason(source: Control = null) -> void:
	if _block_hint == null:
		return
	if source != null and _block_hint_source != null:
		var active_source := _block_hint_source.get_ref() as Control
		if active_source != null and active_source != source:
			return
	if _block_hint_tween != null and _block_hint_tween.is_valid():
		_block_hint_tween.kill()
	_hide_block_hint()


func _position_block_hint(source_ref: WeakRef = null) -> void:
	if _block_hint == null or not _block_hint.visible:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var hand_rect := get_global_rect()
	var hint_size: Vector2 = _block_hint.get_combined_minimum_size()
	hint_size.x = min(max(hint_size.x, 280.0), min(520.0, viewport_size.x - 24.0))
	_block_hint.size = hint_size
	var anchor_x: float = hand_rect.get_center().x
	if source_ref != null:
		var source := source_ref.get_ref() as Control
		if source != null:
			anchor_x = source.get_global_rect().get_center().x
	var x: float = clampf(anchor_x - hint_size.x * 0.5, 12.0, max(12.0, viewport_size.x - hint_size.x - 12.0))
	var y: float = hand_rect.position.y - hint_size.y - 10.0
	if y < 8.0:
		y = hand_rect.position.y + 10.0
	_block_hint.global_position = Vector2(x, y)


func _hide_block_hint() -> void:
	if _block_hint != null:
		_block_hint.visible = false
	_block_hint_source = null


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
		if card.has_method("refresh_play_block_reason"):
			card.call("refresh_play_block_reason")
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
