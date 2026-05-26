# EnemyHpBar — 对手剩余资金竖向条 (与 PlayerTargetBar 镜像布局)
# 剩余资金越多, 底部向上的高亮填充越多; 资金越少, 颜色越偏红.
extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_title: Label = $LblTitle
@onready var lbl_value: Label = $LblValue
@onready var icon_slot: Panel = $IconSlot
@onready var lbl_liq_price: Label = $LblLiqPrice
@onready var bar_bg: ColorRect = $BarBg
@onready var bar_fill: ColorRect = $BarFill

const BAR_TOP_PAD: float = 80.0
const BAR_BOTTOM_PAD: float = 12.0
const BAR_X: float = 12.0

const SEG_LOW: Color = Color("#321018")
const SEG_MID: Color = Color("#3a2a18")
const SEG_HIGH: Color = Color("#153125")
const BAR_BORDER_COL: Color = Color("#ff5d6c")
const MARKER_COL: Color = Color("#f5f5f5")

var _bar_top: float = BAR_TOP_PAD
var _bar_h: float = 0.0
var _bar_w: float = 28.0

var _seg_low: ColorRect = null
var _seg_mid: ColorRect = null
var _seg_high: ColorRect = null
var _bar_border: ColorRect = null
var _cash_fill: ColorRect = null
var _target_line: ColorRect = null
var _target_arrow: Polygon2D = null
var _target_label_bg: ColorRect = null
var _lbl_target_k: Label = null
var _marker: ColorRect = null
var _scale_labels: Array[Label] = []


func _ready() -> void:
	if lbl_title != null:
		lbl_title.text = "剩余资金"
	add_theme_stylebox_override("panel", UF.panel_stylebox(UF.COL_NEON_RED))
	_decorate_icon()
	_build_bar()
	resized.connect(_layout_bar)
	Game.opponent_state_changed.connect(_refresh)
	Game.opponent_entered.connect(_on_opponent_entered)
	Game.opponent_defeated.connect(_on_opponent_defeated)
	Game.state_changed.connect(_refresh)
	_layout_bar()
	_refresh()


func _decorate_icon() -> void:
	if icon_slot == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = UF.COL_NEON_RED
	sb.border_color = UF.COL_BG_DEEP
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	icon_slot.add_theme_stylebox_override("panel", sb)
	if not icon_slot.has_node("LblIcon"):
		var l := Label.new()
		l.name = "LblIcon"
		l.text = "X"
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", UF.COL_BG_DEEP)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.anchor_right = 1.0
		l.anchor_bottom = 1.0
		icon_slot.add_child(l)


func _build_bar() -> void:
	if _bar_border != null:
		return
	_bar_border = _new_rect(BAR_BORDER_COL)
	_seg_high = _new_rect(SEG_HIGH)
	_seg_mid = _new_rect(SEG_MID)
	_seg_low = _new_rect(SEG_LOW)
	_cash_fill = _new_rect(UF.COL_UP)
	_target_line = _new_rect(UF.COL_GOLD)
	_target_label_bg = _new_rect(UF.COL_BG_DEEP)
	_lbl_target_k = Label.new()
	_lbl_target_k.add_theme_font_size_override("font_size", 9)
	_lbl_target_k.add_theme_color_override("font_color", UF.COL_GOLD)
	_lbl_target_k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_target_k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_lbl_target_k)
	_target_arrow = Polygon2D.new()
	_target_arrow.color = UF.COL_GOLD
	add_child(_target_arrow)
	_marker = _new_rect(MARKER_COL)
	for _txt in ["100%", "50%", "25%", "0%"]:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 8)
		l.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(l)
		_scale_labels.append(l)


func _new_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _layout_bar() -> void:
	_bar_top = BAR_TOP_PAD
	_bar_h = max(60.0, size.y - BAR_TOP_PAD - BAR_BOTTOM_PAD)
	_bar_w = max(8.0, size.x - BAR_X * 2.0)
	_bar_border.position = Vector2(BAR_X - 1.0, _bar_top - 1.0)
	_bar_border.size = Vector2(_bar_w + 2.0, _bar_h + 2.0)

	var v25: float = _pct_to_y(0.25)
	var v55: float = _pct_to_y(0.55)
	var bar_bottom: float = _bar_top + _bar_h
	_seg_low.position = Vector2(BAR_X, v25)
	_seg_low.size = Vector2(_bar_w, bar_bottom - v25)
	_seg_mid.position = Vector2(BAR_X, v55)
	_seg_mid.size = Vector2(_bar_w, v25 - v55)
	_seg_high.position = Vector2(BAR_X, _bar_top)
	_seg_high.size = Vector2(_bar_w, v55 - _bar_top)

	_layout_scale_labels()
	_refresh()


func _layout_scale_labels() -> void:
	var opp = Game.get_opponent_state()
	var max_cash: float = 0.0
	if opp != null and opp.present and not opp.defeated_this_level:
		max_cash = max(1.0, opp.initial_cash)
	var scale_pcts: Array[float] = [1.0, 0.5, 0.25, 0.0]
	var label_w: float = 36.0
	var label_x: float = BAR_X + _bar_w + 4.0
	if label_x + label_w > size.x - 2.0:
		label_x = max(0.0, size.x - label_w - 2.0)
	for i in range(_scale_labels.size()):
		var pct: float = scale_pcts[i]
		var l: Label = _scale_labels[i]
		l.visible = max_cash > 0.0
		if max_cash > 0.0:
			l.text = _fmt_compact_cash(max_cash * pct, false)
		l.size = Vector2(label_w, 10.0)
		l.position = Vector2(label_x, _pct_to_y(pct) - 5.0)


func _pct_to_y(pct: float) -> float:
	var ratio: float = clampf(pct, 0.0, 1.0)
	return _bar_top + (1.0 - ratio) * _bar_h


func _on_opponent_entered(_opponent_id: String) -> void:
	_layout_bar()
	_refresh()


func _on_opponent_defeated(_opponent_id: String, _reward_card_id: String) -> void:
	_layout_bar()
	_refresh()


func _refresh() -> void:
	if lbl_value == null:
		return
	var opp = Game.get_opponent_state()
	if opp == null or (not opp.present and not opp.defeated_this_level):
		lbl_value.text = "--"
		lbl_value.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
		_hide_current_marks()
		_layout_scale_labels()
		return
	if opp.defeated_this_level:
		lbl_value.text = "击败"
		lbl_value.add_theme_color_override("font_color", UF.COL_UP)
		_hide_current_marks()
		_layout_scale_labels()
		return

	var ratio: float = clampf(opp.cash / max(1.0, opp.initial_cash), 0.0, 1.0)
	lbl_value.text = _fmt_compact_cash(opp.cash)
	var col: Color
	if ratio <= 0.25:
		col = UF.COL_DOWN
	elif ratio <= 0.55:
		col = UF.COL_YELLOW
	else:
		col = UF.COL_UP
	lbl_value.add_theme_color_override("font_color", col)
	_cash_fill.color = Color(col.r, col.g, col.b, 0.86)
	var fill_h: float = _bar_h * ratio
	_cash_fill.visible = true
	_cash_fill.position = Vector2(BAR_X, _bar_top + _bar_h - fill_h)
	_cash_fill.size = Vector2(_bar_w, fill_h)
	_show_cash_marker(ratio)
	_layout_scale_labels()


func _show_cash_marker(ratio: float) -> void:
	if _target_line == null or _bar_h <= 0.0:
		return
	_target_line.visible = true
	_target_label_bg.visible = true
	_lbl_target_k.visible = true
	_target_arrow.visible = true
	var y: float = _pct_to_y(ratio)
	_target_line.position = Vector2(BAR_X - 4.0, y - 1.0)
	_target_line.size = Vector2(_bar_w + 8.0, 2.0)
	_target_arrow.polygon = PackedVector2Array([
		Vector2(BAR_X - 12.0, y - 4.0),
		Vector2(BAR_X - 6.0, y),
		Vector2(BAR_X - 12.0, y + 4.0)
	])
	var label_w: float = 28.0
	var label_h: float = 12.0
	var label_x: float = BAR_X + _bar_w + 4.0
	if label_x + label_w > size.x - 2.0:
		label_x = max(0.0, size.x - label_w - 2.0)
	var bar_bottom_y: float = _bar_top + _bar_h
	var label_y: float = clampf(y - label_h * 0.5, _bar_top - label_h * 0.5, bar_bottom_y - label_h * 0.5)
	_target_label_bg.position = Vector2(label_x - 1.0, label_y - 1.0)
	_target_label_bg.size = Vector2(label_w + 2.0, label_h + 2.0)
	_lbl_target_k.position = Vector2(label_x, label_y)
	_lbl_target_k.size = Vector2(label_w, label_h)
	_lbl_target_k.text = "%d%%" % int(ratio * 100.0)
	if _marker != null:
		_marker.visible = false


func _hide_current_marks() -> void:
	if _cash_fill != null: _cash_fill.visible = false
	if _target_line != null: _target_line.visible = false
	if _target_label_bg != null: _target_label_bg.visible = false
	if _lbl_target_k != null: _lbl_target_k.visible = false
	if _target_arrow != null: _target_arrow.visible = false
	if _marker != null: _marker.visible = false


func _fmt_compact_cash(v: float, with_currency: bool = true) -> String:
	var prefix: String = "¥" if with_currency else ""
	var abs_v: float = abs(v)
	if abs_v >= 1000000.0:
		return "%s%.1fM" % [prefix, v / 1000000.0]
	if abs_v >= 10000.0:
		return "%s%dK" % [prefix, int(round(v / 1000.0))]
	return "%s%s" % [prefix, UF.fmt_money(v)]
