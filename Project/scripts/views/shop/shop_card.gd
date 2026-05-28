extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const Talent = preload("res://scripts/talent.gd")
const CardHoverTooltip = preload("res://scripts/views/card_hover_tooltip.gd")

signal action_pressed
signal card_hovered(is_hovering: bool)

@onready var card_visual: Panel = $CardVisual
@onready var lbl_name: Label = $CardVisual/VBox/LblName
@onready var lbl_cost: Label = $CardVisual/VBox/LblCost
@onready var lbl_desc: Label = $CardVisual/VBox/LblDesc
@onready var lbl_price: Label = $LblPrice
@onready var btn_action: Button = $BtnAction
@onready var icon_slot: CenterContainer = get_node_or_null("CardVisual/VBox/IconSlot")
@onready var icon_tex: TextureRect = get_node_or_null("CardVisual/VBox/IconSlot/Icon")

const HOVER_SCALE: float = 1.22
const TWEEN_DURATION: float = 0.15
const NAME_LINE_UNITS: float = 7.0
const DESC_LINE_UNITS: float = 8.4
const DESC_MAX_LINES: int = 4
const TOOLTIP_DELAY_MSEC: int = 20

var _tween: Tween = null
var _card_tooltip_full_text: String = ""
var _card_tooltip_text: String = ""
var _card_tooltip: PanelContainer = null
var _tooltip_requested: bool = false
var _tooltip_show_at_msec: int = 0
var _tooltip_tween: Tween = null


func _ready() -> void:
	set_process(false)
	# card_visual.z_index = 1
	# lbl_price.z_index = 0
	# btn_action.z_index = 0
	card_visual.pivot_offset = card_visual.size * 0.5
	card_visual.mouse_entered.connect(_on_mouse_entered)
	card_visual.mouse_exited.connect(_on_mouse_exited)
	btn_action.pressed.connect(func(): action_pressed.emit())


func setup(card: Card, price: int, action_text: String, action_color: Color, can_afford: bool, show_action: bool = true) -> void:
	set_meta("effect_id", card.effect_id)
	set_meta("talent_id", "")
	if lbl_name == null:
		card_visual = $CardVisual
		lbl_name = $CardVisual/VBox/LblName
		lbl_cost = $CardVisual/VBox/LblCost
		lbl_desc = $CardVisual/VBox/LblDesc
		lbl_price = $LblPrice
		btn_action = $BtnAction
		icon_slot = get_node_or_null("CardVisual/VBox/IconSlot")
	lbl_name.text = card.name
	var col: Color = UF.kind_color(card.kind)
	_apply_text_clarity(lbl_name, col)
	_apply_text_fit(lbl_name, card.name, 12, 10, NAME_LINE_UNITS, 1)
	lbl_cost.text = "耗 %d" % card.cost
	lbl_cost.add_theme_color_override("font_color", col)
	_apply_text_clarity(lbl_cost, col)
	_apply_text_fit(lbl_cost, lbl_cost.text, 11, 9, NAME_LINE_UNITS, 1)
	lbl_desc.text = card.description
	_apply_text_clarity(lbl_desc, UF.COL_TEXT)
	var desc_capacity: float = DESC_LINE_UNITS * float(DESC_MAX_LINES)
	_apply_text_fit(lbl_desc, card.description, 10, 8, desc_capacity, DESC_MAX_LINES)
	_apply_visual_style(col)
	tooltip_text = ""
	_card_tooltip_full_text = "%s\n%s" % [card.name, card.description]
	_refresh_card_tooltip_clipping(DESC_MAX_LINES)
	call_deferred("_refresh_card_tooltip_clipping", DESC_MAX_LINES)
	lbl_price.text = "¥%d" % price
	btn_action.text = action_text
	btn_action.add_theme_color_override("font_color", action_color)
	var btn_sb := UF.panel_stylebox(action_color)
	btn_action.add_theme_stylebox_override("normal", btn_sb)
	var btn_hover := btn_sb.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(action_color.r, action_color.g, action_color.b, 0.18)
	btn_action.add_theme_stylebox_override("hover", btn_hover)
	btn_action.disabled = not can_afford
	btn_action.visible = show_action
	lbl_price.visible = show_action
	_apply_card_icon(card)


# 天赋卡: 复用同一张视觉, 但 cost 行显示「天赋」标签, 颜色统一用 highlight 金色
func setup_talent(talent: Talent, can_afford: bool, action_text: String = "购买", show_action: bool = true) -> void:
	set_meta("effect_id", "")
	set_meta("talent_id", talent.id)
	if lbl_name == null:
		card_visual = $CardVisual
		lbl_name = $CardVisual/VBox/LblName
		lbl_cost = $CardVisual/VBox/LblCost
		lbl_desc = $CardVisual/VBox/LblDesc
		lbl_price = $LblPrice
		btn_action = $BtnAction
		icon_slot = get_node_or_null("CardVisual/VBox/IconSlot")
	lbl_name.text = talent.name
	var col: Color = UF.COL_HIGHLIGHT
	_apply_text_clarity(lbl_name, col)
	_apply_text_fit(lbl_name, talent.name, 12, 10, NAME_LINE_UNITS, 1)
	lbl_cost.text = "天赋"
	lbl_cost.add_theme_color_override("font_color", col)
	_apply_text_clarity(lbl_cost, col)
	_apply_text_fit(lbl_cost, lbl_cost.text, 11, 9, NAME_LINE_UNITS, 1)
	lbl_desc.text = talent.description
	_apply_text_clarity(lbl_desc, UF.COL_TEXT)
	var desc_capacity: float = DESC_LINE_UNITS * 5.0
	_apply_text_fit(lbl_desc, talent.description, 10, 8, desc_capacity, 5)
	_apply_visual_style(col)
	tooltip_text = ""
	_card_tooltip_full_text = "%s\n%s" % [talent.name, talent.description]
	_refresh_card_tooltip_clipping(5)
	call_deferred("_refresh_card_tooltip_clipping", 5)
	lbl_price.text = "¥%d" % talent.price if talent.price > 0 else "免费"
	btn_action.text = action_text
	btn_action.add_theme_color_override("font_color", col)
	var btn_sb := UF.panel_stylebox(col)
	btn_action.add_theme_stylebox_override("normal", btn_sb)
	var btn_hover := btn_sb.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(col.r, col.g, col.b, 0.18)
	btn_action.add_theme_stylebox_override("hover", btn_hover)
	btn_action.disabled = not can_afford
	btn_action.visible = show_action
	lbl_price.visible = show_action
	_clear_icon()


func _apply_visual_style(col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UF.COL_PANEL
	sb.border_color = col
	sb.border_width_top = 5
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	card_visual.add_theme_stylebox_override("panel", sb)


func _apply_text_clarity(label: Label, color: Color) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.86))
	label.add_theme_constant_override("outline_size", 2)


func _apply_text_fit(label: Label, text: String, base_size: int, min_size: int, capacity_units: float, max_lines: int) -> int:
	if label == null:
		return base_size
	var fitted_size: int = _fit_font_size(text, base_size, min_size, capacity_units)
	label.add_theme_font_size_override("font_size", fitted_size)
	label.clip_text = true
	label.max_lines_visible = max_lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return fitted_size


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


func _refresh_card_tooltip_clipping(desc_max_lines: int = DESC_MAX_LINES) -> void:
	var name_clipped: bool = _label_is_clipped(lbl_name, 1, NAME_LINE_UNITS)
	var desc_capacity: float = DESC_LINE_UNITS * float(desc_max_lines)
	var desc_clipped: bool = _label_is_clipped(lbl_desc, desc_max_lines, desc_capacity)
	var desc_dense: bool = _label_needs_readability_tooltip(lbl_desc, desc_max_lines)
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


func _on_mouse_entered() -> void:
	_tween_scale(Vector2(HOVER_SCALE, HOVER_SCALE))
	z_index = 5
	_schedule_card_tooltip()
	card_hovered.emit(true)


func _on_mouse_exited() -> void:
	_tween_scale(Vector2.ONE)
	z_index = 0
	_hide_card_tooltip()
	card_hovered.emit(false)


func _tween_scale(target: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(card_visual, "scale", target, TWEEN_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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


# 加载卡牌图标 (复用手牌的 UF.card_icon_path_for 解析); 找不到时隐藏 Icon
func _apply_card_icon(card: Card) -> void:
	if icon_tex == null:
		icon_tex = get_node_or_null("CardVisual/VBox/IconSlot/Icon")
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


func _clear_icon() -> void:
	if icon_tex == null:
		icon_tex = get_node_or_null("CardVisual/VBox/IconSlot/Icon")
	if icon_tex != null:
		icon_tex.texture = null
		icon_tex.visible = false
	if icon_slot == null:
		icon_slot = get_node_or_null("CardVisual/VBox/IconSlot")
	if icon_slot != null:
		icon_slot.visible = false
