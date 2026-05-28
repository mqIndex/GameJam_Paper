# EnemyHpBar — 对手爆仓距离竖向条 (与 PlayerTargetBar 镜像布局)
# 股价越接近爆仓线, 底部向上的高亮填充越低; 风险越高, 颜色越偏红.
extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_title: Label = $LblTitle
@onready var lbl_value: Label = $LblValue
@onready var icon_slot: Panel = $IconSlot
@onready var lbl_liq_price: Label = $LblLiqPrice
@onready var bar_bg: ColorRect = $BarBg
@onready var bar_fill: ColorRect = $BarFill

const BAR_TOP_PAD: float = 112.0
const BAR_BOTTOM_PAD: float = 12.0
const BAR_X: float = 12.0
const FUND_ICON_SIZE: float = 96.0  # IconSlot 原 48px 的 2 倍

# 旧的三段彩色背景已废弃 (兼容字段, 不再使用)
const SEG_LOW: Color = Color("#321018")
const SEG_MID: Color = Color("#3a2a18")
const SEG_HIGH: Color = Color("#153125")
const BAR_BORDER_COL: Color = Color("#ff5d6c")
const BAR_BORDER_COL_ALPHA: float = 0.2
const MARKER_COL: Color = Color("#f5f5f5")
const FILL_SAFE_COL: Color = Color("#3ddc97")
const FILL_WARN_COL: Color = Color("#ffc857")
const FILL_DANGER_COL: Color = Color("#ff5d6c")
# 刻度: 爆仓距离百分比, 0% = 爆仓, 100% = 相对安全.
const TICK_COUNT: int = 10
const TICK_LABEL_PCTS: Array[int] = [0, 50, 100]
const BAR_INNER_SCALE: float = 0.6  # 红色空心内柱相对面板可用宽的缩放比 (1.0 = 原大, 0.6 = 缩小到 60%)
const BAR_INNER_HEIGHT_SCALE: float = 0.75  # 红色空心内柱相对面板可用高的缩放比 (从顶部向下收缩, 底部对齐保持不变)



var _bar_top: float = BAR_TOP_PAD
var _bar_h: float = 0.0
var _bar_w: float = 28.0

var _seg_low: ColorRect = null
var _seg_mid: ColorRect = null
var _seg_high: ColorRect = null
var _bar_border: ColorRect = null
var _border_t: ColorRect = null
var _border_b: ColorRect = null
var _border_l: ColorRect = null
var _border_r: ColorRect = null
var _ticks: Array[ColorRect] = []
var _tick_text_labels: Array[Label] = []  # 与 TICK_LABEL_PCTS 一一对应的右侧数字标签
var _cash_fill: ColorRect = null
var _target_line: ColorRect = null
var _target_arrow: Polygon2D = null
var _target_label_bg: ColorRect = null
var _lbl_target_k: Label = null
var _marker: ColorRect = null
var _scale_labels: Array[Label] = []



func _ready() -> void:
	if lbl_title != null:
		lbl_title.text = "爆仓线"
	# 内部 panel stylebox 保持原纯色 (内部框线 _border_t/b/l/r 仍然显示)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_decorate_icon()
	_build_bar()
	_apply_outer_frame(UF.PATH_BORDER_ENEMY_FUND)
	resized.connect(_layout_bar)
	Game.opponent_state_changed.connect(_refresh)
	Game.opponent_entered.connect(_on_opponent_entered)
	Game.opponent_defeated.connect(_on_opponent_defeated)
	Game.state_changed.connect(_refresh)
	_layout_bar()
	_refresh()


# 最外层装饰边框: 用 TextureRect 铺满整个面板, 贴图中心透明不遮内部立柱;
# 内部 panel stylebox + _border_t/b/l/r 内部框线照常显示 (用户要求只换外边框)
func _apply_outer_frame(texture_path: String) -> void:
	if has_node("OuterFrame"):
		return
	var tex := UF.try_load_texture(texture_path)
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.name = "OuterFrame"
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 不设 z_index: 让 OuterFrame 跟随 EnemyHpBar 自身渲染层级,
	# 避免 z_index=50 穿透 ShopOverlay/EndDialog 等覆盖层
	tr.anchor_left = 0.0
	tr.anchor_top = 0.0
	tr.anchor_right = 1.0
	tr.anchor_bottom = 1.0
	tr.offset_left = 0.0
	tr.offset_top = 0.0
	tr.offset_right = 0.0
	tr.offset_bottom = 0.0
	add_child(tr)


func _decorate_icon() -> void:
	# 在 IconSlot (LblValue 下方, 立柱上方) 内挂载 enemy_fund_Icon.png 作为资金图标
	if icon_slot == null:
		return
	if icon_slot.has_node("FundIcon"):
		icon_slot.visible = true
		return
	var tex := UF.try_load_texture(UF.PATH_ICON_ENEMY_FUND)
	if tex == null:
		icon_slot.visible = false
		return
	# IconSlot 自身透明 (不要 panel stylebox), 只作为定位容器
	icon_slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	icon_slot.visible = true
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.name = "FundIcon"
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon_slot.add_child(icon)



func _build_bar() -> void:
	if _bar_border != null:
		return
	# 外框: 旧实心 ColorRect 保留为隐藏占位 (避免老代码 NPE), 新样式用 4 条边线拼空心框
	_bar_border = _new_rect(Color(0, 0, 0, 0))
	_bar_border.visible = false
	_border_t = _new_rect(BAR_BORDER_COL)
	_border_b = _new_rect(BAR_BORDER_COL)
	_border_l = _new_rect(BAR_BORDER_COL)
	_border_r = _new_rect(BAR_BORDER_COL)
	# 4 边线半透明 (用户要求, 让外框 PNG 风格更突出)
	var border_a: Color = Color(BAR_BORDER_COL.r, BAR_BORDER_COL.g, BAR_BORDER_COL.b, BAR_BORDER_COL_ALPHA)
	_border_t.color = border_a
	_border_b.color = border_a
	_border_l.color = border_a
	_border_r.color = border_a
	# 旧三段彩色背景: 隐藏 (新样式立柱内透明)
	_seg_high = _new_rect(SEG_HIGH)
	_seg_high.visible = false
	_seg_mid = _new_rect(SEG_MID)
	_seg_mid.visible = false
	_seg_low = _new_rect(SEG_LOW)
	_seg_low.visible = false
	# 内部水平刻度线 (TICK_COUNT-1 条)
	for i in range(TICK_COUNT - 1):
		_ticks.append(_new_rect(Color(BAR_BORDER_COL.r, BAR_BORDER_COL.g, BAR_BORDER_COL.b, BAR_BORDER_COL_ALPHA)))
	# 右侧数字标签: 0% / 50% / 100%
	for pct in TICK_LABEL_PCTS:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(BAR_BORDER_COL.r, BAR_BORDER_COL.g, BAR_BORDER_COL.b, 0.85))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.text = "%d%%" % pct
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)
		_tick_text_labels.append(lbl)
	# 爆仓距离填充
	_cash_fill = _new_rect(FILL_SAFE_COL)
	# 旧的金色目标值刻度/三角/标签已废弃 (新样式无此元素), 创建后立即隐藏
	_target_line = _new_rect(UF.COL_GOLD)
	_target_line.visible = false
	_target_label_bg = _new_rect(UF.COL_BG_DEEP)
	_target_label_bg.visible = false
	_lbl_target_k = Label.new()
	_lbl_target_k.add_theme_font_size_override("font_size", 9)
	_lbl_target_k.add_theme_color_override("font_color", UF.COL_GOLD)
	_lbl_target_k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_target_k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_target_k.visible = false
	add_child(_lbl_target_k)
	_target_arrow = Polygon2D.new()
	_target_arrow.color = UF.COL_GOLD
	_target_arrow.visible = false
	add_child(_target_arrow)
	_marker = _new_rect(MARKER_COL)
	_marker.visible = false
	# 旧 100%/50%/25%/0% 灰色刻度文字标签已废弃 (新样式不显示)



func _new_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _layout_bar() -> void:
	# 按面板可用高度的 BAR_INNER_HEIGHT_SCALE 比例缩小立柱总高 (顶部 BAR_TOP_PAD 不变,
	# 即从底部向上收缩, 使顶部留更多空间)
	var avail_h: float = max(60.0, size.y - BAR_TOP_PAD - BAR_BOTTOM_PAD)
	_bar_h = max(60.0, avail_h * BAR_INNER_HEIGHT_SCALE)
	# 让立柱在 (BAR_TOP_PAD .. size.y - BAR_BOTTOM_PAD) 之间垂直居中 (顶部多余空间留白)
	_bar_top = BAR_TOP_PAD + (avail_h - _bar_h) * 0.5
	# 整柱按面板可用宽度的 BAR_INNER_SCALE 比例缩小并水平居中
	var avail_w: float = max(8.0, size.x - BAR_X * 2.0)
	_bar_w = max(8.0, avail_w * BAR_INNER_SCALE)

	var bar_left: float = (size.x - _bar_w) * 0.5  # 居中后的左侧 X
	# 外框: 4 条边线拼空心框 (内框外 1px)
	var ox: float = bar_left - 1.0
	var oy: float = _bar_top - 1.0
	var ow: float = _bar_w + 2.0
	var oh: float = _bar_h + 2.0
	if _border_t != null:
		_border_t.position = Vector2(ox, oy)
		_border_t.size = Vector2(ow, 1.0)
	if _border_b != null:
		_border_b.position = Vector2(ox, oy + oh - 1.0)
		_border_b.size = Vector2(ow, 1.0)
	if _border_l != null:
		_border_l.position = Vector2(ox, oy)
		_border_l.size = Vector2(1.0, oh)
	if _border_r != null:
		_border_r.position = Vector2(ox + ow - 1.0, oy)
		_border_r.size = Vector2(1.0, oh)
	# 内部水平刻度线: 把柱平均分为 TICK_COUNT 段, 在中间各分隔位绘制一条横线
	var tick_count: int = TICK_COUNT
	# 内部水平刻度线: 量程 0%..100%, 从底向上 idx=1..TICK_COUNT-1.
	for i in range(_ticks.size()):
		var idx: int = i + 1
		var ty: float = _bar_top + _bar_h * (float(idx) / float(tick_count))
		_ticks[i].position = Vector2(bar_left, ty - 0.5)
		_ticks[i].size = Vector2(_bar_w, 1.0)
	# 右侧数字标签 (0% / 50% / 100%)
	var label_x: float = bar_left + _bar_w + 4.0
	var label_w: float = 32.0
	var label_h: float = 11.0
	for i in range(_tick_text_labels.size()):
		var pct: int = TICK_LABEL_PCTS[i]
		var k_ratio: float = clampf(float(pct) / 100.0, 0.0, 1.0)
		var ly: float = _bar_top + _bar_h * (1.0 - k_ratio) - label_h * 0.5
		_tick_text_labels[i].position = Vector2(label_x, ly)
		_tick_text_labels[i].size = Vector2(label_w, label_h)
	_layout_scale_labels()
	_refresh()




func _layout_scale_labels() -> void:
	# 新样式不再显示右侧 100%/50%/25%/0% 灰色刻度文字
	for i in range(_scale_labels.size()):
		var l: Label = _scale_labels[i]
		l.visible = false



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

	var safe_ratio: float = _opponent_safe_ratio(opp)
	var danger_ratio: float = 1.0 - safe_ratio
	var risk_col: Color = _risk_color(danger_ratio)
	lbl_value.text = "¥%.1f" % opp.liquidation_price
	lbl_value.add_theme_color_override("font_color", risk_col)
	if lbl_liq_price != null:
		lbl_liq_price.visible = true
		lbl_liq_price.text = "现价 ¥%.2f" % Game.price
		lbl_liq_price.add_theme_color_override("font_color", Color(risk_col.r, risk_col.g, risk_col.b, 0.9))
	# 立柱填充: 爆仓距离越小, 填充越低; 风险越高, 颜色越红.
	var bar_left: float = (size.x - _bar_w) * 0.5
	var fill_inset: float = 2.0
	var fill_w: float = max(2.0, _bar_w - fill_inset * 2.0)
	var fill_h: float = _bar_h * safe_ratio
	_cash_fill.color = risk_col
	_cash_fill.visible = true
	_cash_fill.position = Vector2(bar_left + fill_inset, _bar_top + _bar_h - fill_h)
	_cash_fill.size = Vector2(fill_w, fill_h)

	# 新样式: 不再显示金色目标线/三角/百分比标签
	if _target_line != null: _target_line.visible = false
	if _target_label_bg != null: _target_label_bg.visible = false
	if _lbl_target_k != null: _lbl_target_k.visible = false
	if _target_arrow != null: _target_arrow.visible = false
	if _marker != null: _marker.visible = false
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
	if lbl_liq_price != null: lbl_liq_price.visible = false
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


func _opponent_safe_ratio(opp) -> float:
	if opp == null or opp.liquidation_price <= 0.0:
		return 0.0
	var safe_base: float = max(1.0, opp.liquidation_price - opp.entry_avg_price)
	return clampf((opp.liquidation_price - Game.price) / safe_base, 0.0, 1.0)


func _risk_color(danger_ratio: float) -> Color:
	var d: float = clampf(danger_ratio, 0.0, 1.0)
	if d < 0.55:
		return FILL_SAFE_COL.lerp(FILL_WARN_COL, d / 0.55)
	return FILL_WARN_COL.lerp(FILL_DANGER_COL, (d - 0.55) / 0.45)
