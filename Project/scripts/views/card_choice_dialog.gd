# 通用卡牌/事件选择面板
# 模式:
#   single_card: 玩家点击一张卡 → on_confirm.call(picked_card)
#   multi_card:  玩家点击切换选中, 底部"确定" → on_confirm.call(Array of Card)
#   single_event: 玩家点击一个事件 → on_confirm.call(picked_event)
# 用法 (main.gd 中):
#   dialog.show_card_single("顺势而为", "选择 1 张要弃掉的手牌", hand_cards, callable)
#   dialog.show_card_multi("化整为零", "选择要碎掉的 BUY/SELL 牌", buy_sell_cards, callable)
#   dialog.show_event_single("内幕消息", "提前选定下一次突发事件", events, callable)
extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const Event = preload("res://scripts/event.gd")
const CardButtonScene = preload("res://scenes/ui/card_button.tscn")

enum Mode { SINGLE_CARD, MULTI_CARD, SINGLE_EVENT }

const GRID_OFFSET: Vector2 = Vector2(28.0, 18.0)
const EVENT_BUTTON_SIZE: Vector2 = Vector2(220.0, 196.0)
const EVENT_IMAGE_HEIGHT: float = 118.0
const HOVER_SCALE: float = 1.12
const HOVER_LIFT: float = 8.0
const HOVER_DURATION: float = 0.16

var _mode: int = Mode.SINGLE_CARD
var _on_confirm: Callable = Callable()
var _items: Array = []                    # Card 或 Event 数组
var _selected: Array = []                 # multi 模式: bool 数组, 与 _items 同长
var _hover_tweens: Dictionary = {}

var _dim: ColorRect
var _panel: PanelContainer
var _lbl_title: Label
var _lbl_prompt: Label
var _grid: GridContainer
var _btn_confirm: Button
var _btn_cancel: Button
var _hint: Label


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.04, 0.07, 0.13, 0.85)
	_dim.anchor_right = 1.0
	_dim.anchor_bottom = 1.0
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UF.panel_stylebox(UF.COL_GOLD))
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -420
	_panel.offset_top = -260
	_panel.offset_right = 420
	_panel.offset_bottom = 260
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_lbl_title = Label.new()
	_lbl_title.add_theme_font_size_override("font_size", 22)
	_lbl_title.add_theme_color_override("font_color", UF.COL_GOLD)
	vbox.add_child(_lbl_title)

	_lbl_prompt = Label.new()
	_lbl_prompt.add_theme_font_size_override("font_size", 14)
	_lbl_prompt.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	_lbl_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_lbl_prompt)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid_margin := MarginContainer.new()
	grid_margin.add_theme_constant_override("margin_left", int(GRID_OFFSET.x))
	grid_margin.add_theme_constant_override("margin_top", int(GRID_OFFSET.y))
	grid_margin.add_theme_constant_override("margin_right", 8)
	grid_margin.add_theme_constant_override("margin_bottom", 8)
	grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_margin)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_margin.add_child(_grid)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	vbox.add_child(bottom)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_hint)

	_btn_cancel = UF.button("取消", UF.COL_TEXT_DIM, 14)
	_btn_cancel.custom_minimum_size = Vector2(96, 32)
	_btn_cancel.pressed.connect(_on_cancel)
	bottom.add_child(_btn_cancel)

	_btn_confirm = UF.button("确定", UF.COL_GOLD, 14)
	_btn_confirm.custom_minimum_size = Vector2(96, 32)
	_btn_confirm.pressed.connect(_on_confirm_pressed)
	bottom.add_child(_btn_confirm)


# ---- 公开入口 ----

func show_card_single(title: String, prompt: String, cards: Array, on_pick: Callable) -> void:
	_open(Mode.SINGLE_CARD, title, prompt, cards, on_pick)


func show_card_multi(title: String, prompt: String, cards: Array, on_confirm: Callable) -> void:
	_open(Mode.MULTI_CARD, title, prompt, cards, on_confirm)


func show_event_single(title: String, prompt: String, events: Array, on_pick: Callable) -> void:
	_open(Mode.SINGLE_EVENT, title, prompt, events, on_pick)


# ---- 内部 ----

func _open(mode: int, title: String, prompt: String, items: Array, on_confirm: Callable) -> void:
	_mode = mode
	_items = items
	_on_confirm = on_confirm
	_selected.clear()
	for i in range(items.size()):
		_selected.append(false)
	_lbl_title.text = title
	_lbl_prompt.text = prompt
	_btn_confirm.visible = mode == Mode.MULTI_CARD
	_btn_cancel.visible = mode == Mode.MULTI_CARD          # single/event: 必选, 不允许取消
	_hint.visible = mode == Mode.MULTI_CARD
	_render_grid()
	visible = true


func _render_grid() -> void:
	_clear_hover_tweens()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_grid.columns = 3 if _mode == Mode.SINGLE_EVENT else 5
	for i in range(_items.size()):
		_grid.add_child(_make_item_button(i))
	_update_hint()


func _make_item_button(idx: int) -> Control:
	var item: Variant = _items[idx]
	if _mode != Mode.SINGLE_EVENT:
		var card: Card = item as Card
		var card_btn = CardButtonScene.instantiate()
		card_btn.custom_minimum_size = Vector2(116, 176)
		card_btn.setup(card, idx, true)
		card_btn.set_choice_selected(_selected[idx])
		card_btn.selection_pressed.connect(func(_source): _on_item_pressed(idx))
		return card_btn
	return _make_event_button(item as Event, idx)


func _make_event_button(ev: Event, idx: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = EVENT_BUTTON_SIZE
	btn.pivot_offset = EVENT_BUTTON_SIZE * 0.5
	btn.clip_text = false
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "%s\n%s\n%s" % [ev.name, ev.desc, ev.effect_desc]

	var col: Color = ev.theme_color
	if col.a <= 0.0:
		col = _event_color(ev)
	btn.add_theme_color_override("font_color", col)
	_apply_button_style(btn, col, false)

	var margin := MarginContainer.new()
	margin.name = "EventMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	btn.add_child(margin)

	var root := VBoxContainer.new()
	root.name = "EventRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var image := TextureRect.new()
	image.name = "EventImage"
	image.custom_minimum_size = Vector2(0.0, EVENT_IMAGE_HEIGHT)
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_event_texture(image, ev)
	root.add_child(image)

	var name_label := Label.new()
	name_label.name = "LblEventName"
	name_label.text = ev.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", col)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_label)

	var effect_label := Label.new()
	effect_label.name = "LblEventEffect"
	effect_label.text = ev.effect_desc
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	effect_label.add_theme_font_size_override("font_size", 12)
	effect_label.add_theme_color_override("font_color", UF.COL_TEXT)
	effect_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	effect_label.add_theme_constant_override("outline_size", 2)
	effect_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(effect_label)

	btn.pressed.connect(_on_item_pressed.bind(idx))
	btn.mouse_entered.connect(_on_choice_hover_enter.bind(btn))
	btn.mouse_exited.connect(_on_choice_hover_exit.bind(btn))
	return btn


func _load_event_texture(image: TextureRect, ev: Event) -> void:
	if ev == null or ev.image_path == "" or not ResourceLoader.exists(ev.image_path):
		image.visible = false
		return
	var tex = load(ev.image_path)
	if tex is Texture2D:
		image.texture = tex as Texture2D
		image.visible = true
	else:
		image.visible = false


func _apply_button_style(btn: Button, col: Color, picked: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.32 if picked else 0.08)
	sb.border_color = col
	sb.border_width_left = 3 if picked else 1
	sb.border_width_right = 3 if picked else 1
	sb.border_width_top = 3 if picked else 1
	sb.border_width_bottom = 3 if picked else 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", sb)
	var hov: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(col.r, col.g, col.b, 0.45 if picked else 0.18)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)


func _on_choice_hover_enter(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	_kill_hover_tween(btn)
	if not btn.has_meta("_choice_base_y"):
		btn.set_meta("_choice_base_y", btn.position.y)
	btn.z_index = 40
	SfxBus.play_card_hover()
	var target_y: float = float(btn.get_meta("_choice_base_y")) - HOVER_LIFT
	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DURATION)
	t.tween_property(btn, "position:y", target_y, HOVER_DURATION)
	_hover_tweens[btn] = t


func _on_choice_hover_exit(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	_kill_hover_tween(btn)
	var base_y: float = float(btn.get_meta("_choice_base_y", btn.position.y))
	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(btn, "scale", Vector2.ONE, HOVER_DURATION)
	t.tween_property(btn, "position:y", base_y, HOVER_DURATION)
	var btn_ref: WeakRef = weakref(btn)
	t.chain().tween_callback(func():
		var node := btn_ref.get_ref() as Button
		if node == null:
			return
		node.z_index = 0
		node.remove_meta("_choice_base_y")
	)
	_hover_tweens[btn] = t


func _kill_hover_tween(btn: Button) -> void:
	if not _hover_tweens.has(btn):
		return
	var prev = _hover_tweens[btn]
	if prev != null and prev.is_valid():
		prev.kill()
	_hover_tweens.erase(btn)


func _clear_hover_tweens() -> void:
	for btn in _hover_tweens.keys():
		var tween = _hover_tweens[btn]
		if tween != null and tween.is_valid():
			tween.kill()
	_hover_tweens.clear()


func _on_item_pressed(idx: int) -> void:
	match _mode:
		Mode.SINGLE_CARD, Mode.SINGLE_EVENT:
			var item: Variant = _items[idx]
			visible = false
			if _on_confirm.is_valid():
				_on_confirm.call(item)
		Mode.MULTI_CARD:
			_selected[idx] = not _selected[idx]
			# 局部刷新: 仅这一张按钮的样式
			var card_view: Control = _grid.get_child(idx) as Control
			if card_view != null and card_view.has_method("set_choice_selected"):
				card_view.call("set_choice_selected", _selected[idx])
			_update_hint()


func _on_confirm_pressed() -> void:
	if _mode != Mode.MULTI_CARD:
		return
	var picked: Array = []
	for i in range(_items.size()):
		if _selected[i]:
			picked.append(_items[i])
	visible = false
	if _on_confirm.is_valid():
		_on_confirm.call(picked)


func _on_cancel() -> void:
	if _mode != Mode.MULTI_CARD:
		return
	visible = false
	if _on_confirm.is_valid():
		_on_confirm.call([])


func _update_hint() -> void:
	if _mode != Mode.MULTI_CARD:
		_hint.text = ""
		return
	var n: int = 0
	for s in _selected:
		if s: n += 1
	_hint.text = "已选 %d / %d" % [n, _items.size()]


func _event_color(ev: Event) -> Color:
	match ev.category_str():
		"good": return UF.COL_RED
		"bad":  return UF.COL_GREEN
	return UF.COL_GOLD


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 多选模式 ESC = 取消; 单选模式不允许 ESC 关闭 (玩家必须做出选择)
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE and _mode == Mode.MULTI_CARD:
			_on_cancel()
			get_viewport().set_input_as_handled()
