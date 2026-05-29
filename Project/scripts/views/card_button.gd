extends Button

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const CardHoverTooltip = preload("res://scripts/views/card_hover_tooltip.gd")

@onready var lbl_name: Label = $VBox/LblName
@onready var lbl_cost: Label = $VBox/LblCost
@onready var lbl_desc: Label = $VBox/LblDesc
@onready var icon_slot: CenterContainer = get_node_or_null("VBox/IconSlot")
@onready var icon_tex: TextureRect = get_node_or_null("VBox/IconSlot/Icon")

const HOVER_SCALE: float = 1.2
const HOVER_DURATION: float = 0.18
const HOVER_Z_INDEX: int = 10
const NAME_LINE_UNITS: float = 5.8
const DESC_LINE_UNITS: float = 7.6
const DESC_MAX_LINES: int = 4
const TOOLTIP_DELAY_MSEC: int = 20

signal play_blocked(reason: String, source: Control)
signal play_block_hint_cleared(source: Control)

var _card_index: int = -1
var _play_block_reason: String = ""
var _current_tween: Tween = null
var _is_hovering: bool = false
var _is_dragging: bool = false
var _tutorial_highlight: Panel = null
var _tutorial_highlight_tween: Tween = null
var _blocked_overlay: Panel = null
var _card_tooltip_full_text: String = ""
var _card_tooltip_text: String = ""
var _card_tooltip: PanelContainer = null
var _tooltip_requested: bool = false
var _tooltip_show_at_msec: int = 0
var _tooltip_tween: Tween = null


func _ready() -> void:
	set_process(false)
	pivot_offset = custom_minimum_size * 0.5
	_ensure_blocked_overlay()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func setup(card: Card, index: int) -> void:
	_card_index = index
	set_meta("effect_id", card.effect_id)
	set_meta("card_name", card.name)
	lbl_name.text = card.name
	var col: Color = UF.kind_color(card.kind)
	lbl_name.add_theme_color_override("font_color", col)
	var name_font_size: int = _fit_font_size(card.name, UF.FS_H1, 13, NAME_LINE_UNITS)
	lbl_name.add_theme_font_size_override("font_size", name_font_size)
	lbl_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_name.add_theme_constant_override("outline_size", 2)
	_constrain_label(lbl_name, 1)
	lbl_cost.text = "耗 %d" % card.cost
	lbl_cost.add_theme_color_override("font_color", UF.COL_GOLD)
	lbl_cost.add_theme_font_size_override("font_size", UF.FS_BODY)
	lbl_cost.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_cost.add_theme_constant_override("outline_size", 2)
	_constrain_label(lbl_cost, 1)
	lbl_desc.text = card.description
	lbl_desc.add_theme_color_override("font_color", UF.COL_TEXT)
	var desc_capacity: float = DESC_LINE_UNITS * float(DESC_MAX_LINES)
	var desc_font_size: int = _fit_font_size(card.description, UF.FS_BODY, 10, desc_capacity)
	lbl_desc.add_theme_font_size_override("font_size", desc_font_size)
	lbl_desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_desc.add_theme_constant_override("outline_size", 2)
	_constrain_label(lbl_desc, DESC_MAX_LINES)
	tooltip_text = ""
	_card_tooltip_full_text = "%s\n%s" % [card.name, card.description]
	_refresh_card_tooltip_clipping()
	call_deferred("_refresh_card_tooltip_clipping")
	# 卡牌框: 数据驱动纯色边框 + 实心暗底，避免窗口缩放或后处理下看起来半透明。
	# 边框颜色优先来自 Cards_Visual.csv "颜色" 列, 缺失时 fallback 到 kind_color
	var border_col: Color = UF.card_color_for(card.name)
	if border_col.a <= 0.0:
		border_col = col
	var normal_bg := Color(0.035, 0.055, 0.095, 0.94)
	var sb := StyleBoxFlat.new()
	sb.bg_color = normal_bg
	sb.border_color = border_col
	sb.border_width_top = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	add_theme_stylebox_override("normal", sb)
	var hover_sb := sb.duplicate() as StyleBoxFlat
	var hover_bg := normal_bg.lerp(border_col, 0.16)
	hover_bg.a = 0.98
	hover_sb.bg_color = hover_bg
	add_theme_stylebox_override("hover", hover_sb)
	var pressed_sb := sb.duplicate() as StyleBoxFlat
	var pressed_bg := normal_bg.lerp(border_col, 0.24)
	pressed_bg.a = 1.0
	pressed_sb.bg_color = pressed_bg
	add_theme_stylebox_override("pressed", pressed_sb)
	var hover_pressed_sb := pressed_sb.duplicate() as StyleBoxFlat
	add_theme_stylebox_override("hover_pressed", hover_pressed_sb)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var disabled_sb := sb.duplicate() as StyleBoxFlat
	disabled_sb.border_color = UF.COL_AP_OFF
	disabled_sb.bg_color = Color(0.035, 0.045, 0.07, 0.9)
	add_theme_stylebox_override("disabled", disabled_sb)
	disabled = false
	refresh_play_block_reason()
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	_apply_icon(card)


# 给卡牌 Icon 加载对应图标 (路径由 UF.card_icon_path_for 数据驱动解析);
# 找不到时隐藏 Icon TextureRect, 不报错也不显示占位
func _apply_icon(card: Card) -> void:
	if icon_tex == null:
		return
	var path: String = UF.card_icon_path_for(card.name, card.image_path)
	if path == "":
		icon_tex.texture = null
		icon_tex.visible = false
		if icon_slot != null:
			icon_slot.visible = false
		return
	var tex = load(path)
	if tex is Texture2D:
		icon_tex.texture = tex as Texture2D
		icon_tex.visible = true
		if icon_slot != null:
			icon_slot.visible = true
	else:
		icon_tex.texture = null
		icon_tex.visible = false
		if icon_slot != null:
			icon_slot.visible = false


func _constrain_label(label: Label, max_lines: int) -> void:
	if label == null:
		return
	label.clip_text = true
	label.max_lines_visible = max_lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _fit_font_size(text: String, base_size: int, min_size: int, capacity_units: float) -> int:
	var units: float = _text_units(text)
	if units <= capacity_units:
		return base_size
	var scaled: int = int(floor(float(base_size) * capacity_units / max(1.0, units)))
	return clampi(scaled, min_size, base_size)


func _set_card_tooltip_enabled(is_clipped: bool) -> void:
	if is_clipped:
		_card_tooltip_text = _card_tooltip_full_text
	else:
		_card_tooltip_text = ""
		_hide_card_tooltip()


func _refresh_card_tooltip_clipping() -> void:
	var name_clipped: bool = _label_is_clipped(lbl_name, 1, NAME_LINE_UNITS)
	var desc_capacity: float = DESC_LINE_UNITS * float(DESC_MAX_LINES)
	var desc_clipped: bool = _label_is_clipped(lbl_desc, DESC_MAX_LINES, desc_capacity)
	var desc_dense: bool = _label_needs_readability_tooltip(lbl_desc, DESC_MAX_LINES)
	_set_card_tooltip_enabled(name_clipped or desc_clipped or desc_dense)


func _label_is_clipped(label: Label, max_lines: int, capacity_units: float) -> bool:
	if label == null or label.text.strip_edges() == "":
		return false
	if max_lines > 0:
		var line_count: int = label.get_line_count()
		if label.size.x > 1.0 and line_count > max_lines:
			return true
		if label.size.y > 1.0:
			var visible_lines: int = mini(maxi(line_count, 1), max_lines)
			var font_size: int = label.get_theme_font_size("font_size")
			var required_height: float = float(maxi(font_size, 10)) * 1.18 * float(visible_lines)
			if label.size.y + 1.0 < required_height:
				return true
	return _text_is_clipped(label.text, capacity_units)


func _label_needs_readability_tooltip(label: Label, max_lines: int) -> bool:
	if label == null or label.text.strip_edges() == "" or max_lines <= 1:
		return false
	var line_count: int = label.get_line_count()
	var dense_line_threshold: int = maxi(2, max_lines - 1)
	return line_count >= dense_line_threshold and _text_units(label.text) > DESC_LINE_UNITS * 1.8


func _text_is_clipped(text: String, capacity_units: float) -> bool:
	if text.strip_edges() == "":
		return false
	return _text_units(text) > capacity_units + 0.1


func _text_units(text: String) -> float:
	var units: float = 0.0
	for i in range(text.length()):
		var code := text.unicode_at(i)
		if code <= 32:
			units += 0.35
		elif code < 128:
			units += 0.58
		else:
			units += 1.0
	return units


func refresh_play_block_reason() -> String:
	var reason := Game.get_card_play_block_reason(_card_index)
	set_play_block_reason(reason)
	return reason


func set_play_block_reason(reason: String) -> void:
	_play_block_reason = reason
	disabled = false
	if _is_dragging:
		return
	if _play_block_reason == "":
		_set_blocked_overlay_visible(false)
		modulate = Color.WHITE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		_set_blocked_overlay_visible(true)
		modulate = Color(0.82, 0.86, 0.94, 1.0)
		mouse_default_cursor_shape = Control.CURSOR_HELP


func _ensure_blocked_overlay() -> void:
	if _blocked_overlay != null:
		return
	_blocked_overlay = Panel.new()
	_blocked_overlay.name = "BlockedOverlay"
	_blocked_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocked_overlay.z_index = 0
	_blocked_overlay.visible = false
	_blocked_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocked_overlay.offset_left = 0.0
	_blocked_overlay.offset_top = 0.0
	_blocked_overlay.offset_right = 0.0
	_blocked_overlay.offset_bottom = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.48)
	sb.border_color = Color(UF.COL_AP_OFF.r, UF.COL_AP_OFF.g, UF.COL_AP_OFF.b, 0.92)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_blocked_overlay.add_theme_stylebox_override("panel", sb)
	add_child(_blocked_overlay)


func _set_blocked_overlay_visible(is_visible: bool) -> void:
	_ensure_blocked_overlay()
	_blocked_overlay.visible = is_visible


func set_tutorial_highlight(enabled: bool) -> void:
	if enabled:
		_ensure_tutorial_highlight()
		_tutorial_highlight.visible = true
		if _tutorial_highlight_tween == null or not _tutorial_highlight_tween.is_valid():
			_tutorial_highlight.modulate = Color(1, 1, 1, 1)
			_tutorial_highlight_tween = create_tween()
			_tutorial_highlight_tween.set_loops()
			_tutorial_highlight_tween.tween_property(_tutorial_highlight, "modulate:a", 0.35, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tutorial_highlight_tween.tween_property(_tutorial_highlight, "modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		if _tutorial_highlight_tween != null and _tutorial_highlight_tween.is_valid():
			_tutorial_highlight_tween.kill()
		_tutorial_highlight_tween = null
		if _tutorial_highlight != null:
			_tutorial_highlight.visible = false
			_tutorial_highlight.modulate = Color(1, 1, 1, 1)


func _ensure_tutorial_highlight() -> void:
	if _tutorial_highlight != null:
		return
	_tutorial_highlight = Panel.new()
	_tutorial_highlight.name = "TutorialCardHighlight"
	_tutorial_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_highlight.z_index = 80
	_tutorial_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tutorial_highlight.offset_left = -5.0
	_tutorial_highlight.offset_top = -5.0
	_tutorial_highlight.offset_right = 5.0
	_tutorial_highlight.offset_bottom = 5.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.74, 0.24, 0.09)
	sb.border_color = Color(1.0, 0.74, 0.24, 1.0)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	_tutorial_highlight.add_theme_stylebox_override("panel", sb)
	add_child(_tutorial_highlight)


func _on_pressed() -> void:
	if _is_dragging:
		return
	if refresh_play_block_reason() != "":
		_emit_play_blocked()
	else:
		Game.play_card(_card_index)


func _on_mouse_entered() -> void:
	var blocked: bool = refresh_play_block_reason() != ""
	if not blocked:
		play_block_hint_cleared.emit(null)
	_is_hovering = true
	SfxBus.play_card_hover()
	_tween_scale(Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DURATION)
	z_index = HOVER_Z_INDEX
	_schedule_card_tooltip()
	if blocked:
		_emit_play_blocked()


func _on_mouse_exited() -> void:
	_is_hovering = false
	_hide_card_tooltip()
	play_block_hint_cleared.emit(self)
	if _is_dragging:
		return
	_tween_scale(Vector2.ONE, HOVER_DURATION)
	z_index = 0


func _on_button_down() -> void:
	if refresh_play_block_reason() != "":
		_emit_play_blocked()
		return
	_tween_scale(Vector2(0.95, 0.95), 0.06)


func _on_button_up() -> void:
	if refresh_play_block_reason() != "":
		return
	if _is_hovering:
		_cancel_current_tween()
		var t := create_tween()
		_current_tween = t
		t.tween_property(self, "scale", Vector2(HOVER_SCALE * 1.05, HOVER_SCALE * 1.05), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(self, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_tween_scale(Vector2.ONE, HOVER_DURATION)


func _tween_scale(target: Vector2, duration: float) -> void:
	_cancel_current_tween()
	_current_tween = create_tween()
	_current_tween.tween_property(self, "scale", target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _cancel_current_tween() -> void:
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()


func _process(_delta: float) -> void:
	if not _tooltip_requested:
		set_process(false)
		return
	if _card_tooltip != null and _card_tooltip.visible:
		CardHoverTooltip.position_near_mouse(_card_tooltip, get_viewport())
		return
	if Time.get_ticks_msec() >= _tooltip_show_at_msec:
		_show_card_tooltip()


func _schedule_card_tooltip() -> void:
	_refresh_card_tooltip_clipping()
	if _card_tooltip_text == "":
		return
	_tooltip_requested = true
	_tooltip_show_at_msec = Time.get_ticks_msec() + TOOLTIP_DELAY_MSEC
	if TOOLTIP_DELAY_MSEC <= 0:
		_show_card_tooltip()
		return
	set_process(true)


func _show_card_tooltip() -> void:
	if not _tooltip_requested or _card_tooltip_text == "":
		return
	if _card_tooltip == null:
		_card_tooltip = CardHoverTooltip.create(_card_tooltip_text)
		get_tree().root.add_child(_card_tooltip)
	else:
		CardHoverTooltip.set_text(_card_tooltip, _card_tooltip_text)
	CardHoverTooltip.position_near_mouse(_card_tooltip, get_viewport())
	_card_tooltip.visible = true
	_card_tooltip.modulate = Color(1, 1, 1, 0)
	if _tooltip_tween != null and _tooltip_tween.is_valid():
		_tooltip_tween.kill()
	_tooltip_tween = create_tween()
	_tooltip_tween.tween_property(_card_tooltip, "modulate:a", 1.0, 0.04)


func _hide_card_tooltip() -> void:
	_tooltip_requested = false
	set_process(false)
	if _tooltip_tween != null and _tooltip_tween.is_valid():
		_tooltip_tween.kill()
	if _card_tooltip != null:
		_card_tooltip.visible = false


func _exit_tree() -> void:
	if _card_tooltip != null:
		_card_tooltip.queue_free()
		_card_tooltip = null


func _get_drag_data(_at_position: Vector2) -> Variant:
	if refresh_play_block_reason() != "":
		_emit_play_blocked()
		return null
	_is_dragging = true
	var preview := Control.new()
	var card_view := duplicate() as Control
	card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_view.scale = Vector2(HOVER_SCALE, HOVER_SCALE)
	card_view.position = -card_view.custom_minimum_size * 0.5
	card_view.modulate = Color(1, 1, 1, 0.92)
	preview.add_child(card_view)
	set_drag_preview(preview)
	# Make the original semi-transparent during drag
	modulate = Color(1, 1, 1, 0.55)
	return {"card_index": _card_index}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_is_dragging = false
		refresh_play_block_reason()
		if not _is_hovering:
			_tween_scale(Vector2.ONE, HOVER_DURATION)
			z_index = 0


func _emit_play_blocked() -> void:
	var reason := refresh_play_block_reason()
	if reason == "":
		return
	play_blocked.emit(reason, self)
