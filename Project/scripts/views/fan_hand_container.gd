extends Control

const CARD_WIDTH: float = 108.0
const CARD_HEIGHT: float = 164.0
const NORMAL_SEP: float = 6.0
const HOVER_LIFT: float = 16.0
const HOVER_SCALE: float = 1.1
const TWEEN_DURATION: float = 0.12
const HOVER_Z: int = 100

var _hover_tweens: Dictionary = {}
var _baseline_y: float = 0.0


func _ready() -> void:
	resized.connect(_on_resized)
	child_entered_tree.connect(_on_child_changed)
	child_exiting_tree.connect(_on_child_changed)
	_recalc_baseline()
	relayout_cards()


func _on_resized() -> void:
	_recalc_baseline()
	relayout_cards()


func _recalc_baseline() -> void:
	_baseline_y = max(0.0, (size.y - CARD_HEIGHT) * 0.5)


func _on_child_changed(_node: Node) -> void:
	call_deferred("_after_child_change")


func _after_child_change() -> void:
	for child in get_children():
		var btn := child as Button
		if btn == null:
			continue
		if not btn.has_meta("_fan_hover_wired"):
			btn.mouse_entered.connect(Callable(self, "_on_card_hover_enter").bind(btn))
			btn.mouse_exited.connect(Callable(self, "_on_card_hover_exit").bind(btn))
			btn.set_meta("_fan_hover_wired", true)
	relayout_cards()


func relayout_cards() -> void:
	_recalc_baseline()
	var cards: Array = []
	for child in get_children():
		var btn := child as Button
		if btn != null:
			cards.append(btn)
	var n: int = cards.size()
	if n == 0:
		return
	var avail_w: float = size.x
	var natural_total: float = float(n) * CARD_WIDTH + float(max(0, n - 1)) * NORMAL_SEP
	var sep: float = NORMAL_SEP
	var start_x: float = 0.0
	if natural_total <= avail_w:
		sep = NORMAL_SEP
		start_x = (avail_w - natural_total) * 0.5
	else:
		if n > 1:
			sep = (avail_w - float(n) * CARD_WIDTH) / float(n - 1)
		start_x = 0.0
	for i in range(n):
		var btn: Button = cards[i]
		# 只重置不在 hover 状态的卡牌,避免打断动画
		if btn.has_meta("_fan_hovering") or btn.has_meta("_hand_animating"):
			continue
		btn.position = Vector2(start_x + float(i) * (CARD_WIDTH + sep), _baseline_y)
		btn.scale = Vector2(1.0, 1.0)
		btn.z_index = 0


func _on_card_hover_enter(card: Button) -> void:
	if not is_instance_valid(card) or card.get_parent() != self:
		return
	_kill_tween_for(card)
	card.set_meta("_fan_hovering", true)
	card.z_index = HOVER_Z
	var target_y: float = _baseline_y - HOVER_LIFT
	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(card, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), TWEEN_DURATION)
	t.tween_property(card, "position:y", target_y, TWEEN_DURATION)
	_hover_tweens[card] = t


func _on_card_hover_exit(card: Button) -> void:
	if not is_instance_valid(card) or card.get_parent() != self:
		return
	_kill_tween_for(card)
	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(card, "scale", Vector2(1.0, 1.0), TWEEN_DURATION)
	t.tween_property(card, "position:y", _baseline_y, TWEEN_DURATION)
	var card_ref: WeakRef = weakref(card)
	t.chain().tween_callback(func():
		var card_node := card_ref.get_ref() as Button
		if card_node == null or card_node.get_parent() != self:
			return
		card_node.z_index = 0
		card_node.remove_meta("_fan_hovering")
	)
	_hover_tweens[card] = t


func _kill_tween_for(card: Button) -> void:
	if _hover_tweens.has(card):
		var prev = _hover_tweens[card]
		if prev != null and prev.is_valid():
			prev.kill()
		_hover_tweens.erase(card)
