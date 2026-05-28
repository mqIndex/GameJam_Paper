# PlayerTargetBar — 玩家总资产竖向目标条
# 风格已同步 EnemyHpBar 新样式: 空心边框 + 内部水平刻度线 + 实心填充, 颜色 #fbe4b2 (金黄)
# 量程固定 0 → VICTORY_TARGET * 1.25 (即 150K), 资金来源 Game.get_total_assets() / Game.VICTORY_TARGET.
extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const DashedTicks = preload("res://scripts/views/dashed_ticks.gd")

@onready var lbl_title: Label = $LblTitle
@onready var lbl_value: Label = $LblValue
@onready var icon_slot: Panel = $IconSlot

const BAR_TOP_PAD: float = 80.0
const BAR_BOTTOM_PAD: float = 12.0
const BAR_X: float = 12.0
const SCALE_RATIO: float = 1.25  # 量程上限 = VICTORY_TARGET * 1.25 = 150K

# 旧字段保留 (兼容, 不再使用)
const SEG_BLUE: Color = Color("#118ab2")
const SEG_YELLOW: Color = Color("#ffc857")
const SEG_DARK: Color = Color("#1c1320")
const TARGET_LINE_COL: Color = Color("#ffae42")
const MARKER_COL: Color = Color("#f5f5f5")
const FILL_LOW: Color = Color(0.067, 0.541, 0.698, 1.0)
const FILL_HIGH: Color = Color(1.0, 0.784, 0.341, 1.0)
const FILL_LOW_TRANS: Color = Color(0.067, 0.541, 0.698, 0.35)
const FILL_HIGH_TRANS: Color = Color(1.0, 0.784, 0.341, 0.35)

# 新样式 (与 EnemyHpBar 同款, 仅配色不同)
const BAR_BORDER_COL: Color = Color("#fbe4b2")  # 边框 + 内部刻度线 + 实心填充统一金黄色
const FILL_COL: Color = Color("#fbe4b2")
const PROFIT_FILL_COL: Color = Color("#eb9236")  # 盈利段 (现金条上方堆叠)
const TICK_COUNT: int = 7
const BAR_INNER_SCALE: float = 0.6
const BAR_INNER_HEIGHT_SCALE: float = 0.75
const FILL_WIDTH_SCALE: float = 0.8  # 实心填充柱宽相对内框宽的进一步缩放 (柱体居中, 留出左右更宽留白)
const TARGET_MARK_COL: Color = Color("#ffae42")  # 目标资金线: 橙色 (三角 + 虚线 + 标签边框)



var _bar_top: float = BAR_TOP_PAD
var _bar_h: float = 0.0
var _bar_w: float = 28.0

# 旧节点 (保留为隐藏占位, 避免外部引用 NPE)
var _seg_blue: ColorRect = null
var _seg_yellow: ColorRect = null
var _seg_dark: ColorRect = null
var _bar_border: ColorRect = null
var _bar_fill_top: ColorRect = null
var _target_line: ColorRect = null
var _target_arrow: Polygon2D = null
var _target_label_bg: ColorRect = null
var _lbl_target_k: Label = null
var _marker: ColorRect = null
var _target_dashed: Control = null
var _target_dashed_label_bg: ColorRect = null
var _lbl_target_dashed_k: Label = null
var _scale_labels: Array[Label] = []

# 新节点 (空心边框 + 刻度线 + 实心填充)
var _border_t: ColorRect = null
var _border_b: ColorRect = null
var _border_l: ColorRect = null
var _border_r: ColorRect = null
var _ticks: Array[ColorRect] = []
var _bar_fill: ColorRect = null
var _bar_profit_fill: ColorRect = null  # 盈利段, 叠在现金段上方

# 目标资金线: 左三角 + 中间虚线 + 右侧带描边的 "120K" 标签
var _tgt_arrow: Polygon2D = null
var _tgt_dashed: Control = null  # 复用 DashedTicks 在指定 y 上画虚线
var _tgt_label: Panel = null     # 带 StyleBoxFlat 描边
var _tgt_label_text: Label = null



func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox(UF.COL_GOLD))
	_decorate_icon()
	_build_bar()
	resized.connect(_layout_bar)
	Game.state_changed.connect(_refresh)
	_layout_bar()
	_refresh()


func _decorate_icon() -> void:
	# 新样式不再显示圆形 "$" 图标
	if icon_slot == null:
		return
	icon_slot.visible = false


func _build_bar() -> void:
	if _bar_border != null:
		return
	# 旧实心边框占位 (隐藏)
	_bar_border = _new_rect(Color(0, 0, 0, 0))
	_bar_border.visible = false
	# 4 边线空心框
	_border_t = _new_rect(BAR_BORDER_COL)
	_border_b = _new_rect(BAR_BORDER_COL)
	_border_l = _new_rect(BAR_BORDER_COL)
	_border_r = _new_rect(BAR_BORDER_COL)
	# 旧 3 段彩色背景 (隐藏)
	_seg_dark = _new_rect(SEG_DARK)
	_seg_dark.visible = false
	_seg_yellow = _new_rect(SEG_YELLOW)
	_seg_yellow.visible = false
	_seg_blue = _new_rect(SEG_BLUE)
	_seg_blue.visible = false
	# 内部水平刻度线
	for i in range(TICK_COUNT - 1):
		_ticks.append(_new_rect(BAR_BORDER_COL))
	# 实心填充 (从底部向上, 颜色 #fbe4b2)
	_bar_fill = _new_rect(FILL_COL)
	# 盈利段填充 (叠在现金段上方, 颜色 #eb9236)
	_bar_profit_fill = _new_rect(PROFIT_FILL_COL)
	# 旧顶部半透明渐变 (隐藏)
	_bar_fill_top = _new_rect(FILL_LOW_TRANS)
	_bar_fill_top.visible = false
	# 旧 120K 目标虚线 + 标签 (隐藏)
	_target_dashed = DashedTicks.new()
	add_child(_target_dashed)
	_target_dashed.visible = false
	_target_dashed_label_bg = _new_rect(UF.COL_BG_DEEP)
	_target_dashed_label_bg.visible = false
	_lbl_target_dashed_k = Label.new()
	_lbl_target_dashed_k.add_theme_font_size_override("font_size", 9)
	_lbl_target_dashed_k.add_theme_color_override("font_color", TARGET_LINE_COL)
	_lbl_target_dashed_k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_target_dashed_k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_target_dashed_k.visible = false
	add_child(_lbl_target_dashed_k)
	# 旧当前资金醒目线 + 标签 + 三角 (隐藏)
	_target_line = _new_rect(TARGET_LINE_COL)
	_target_line.visible = false
	_target_label_bg = _new_rect(UF.COL_BG_DEEP)
	_target_label_bg.visible = false
	_lbl_target_k = Label.new()
	_lbl_target_k.add_theme_font_size_override("font_size", 9)
	_lbl_target_k.add_theme_color_override("font_color", TARGET_LINE_COL)
	_lbl_target_k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_target_k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_target_k.visible = false
	add_child(_lbl_target_k)
	_target_arrow = Polygon2D.new()
	_target_arrow.color = TARGET_LINE_COL
	_target_arrow.visible = false
	add_child(_target_arrow)
	_marker = _new_rect(MARKER_COL)
	_marker.visible = false

	# === 新目标资金线 (120K): 左侧实心三角 + 中段橙色虚线 + 右侧带描边的 "120K" 标签 ===
	_tgt_arrow = Polygon2D.new()
	_tgt_arrow.color = TARGET_MARK_COL
	add_child(_tgt_arrow)
	_tgt_dashed = DashedTicks.new()
	add_child(_tgt_dashed)
	_tgt_dashed.set_ticks([0.5], TARGET_MARK_COL, 2.0)
	# 带描边的标签 (圆角矩形, 边框 = 橙色, 内部透明)
	_tgt_label = Panel.new()
	_tgt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = UF.COL_BG_DEEP
	sb.border_color = TARGET_MARK_COL
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_tgt_label.add_theme_stylebox_override("panel", sb)
	add_child(_tgt_label)
	_tgt_label_text = Label.new()
	_tgt_label_text.add_theme_font_size_override("font_size", 10)
	_tgt_label_text.add_theme_color_override("font_color", TARGET_MARK_COL)
	_tgt_label_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tgt_label_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tgt_label_text.anchor_right = 1.0
	_tgt_label_text.anchor_bottom = 1.0
	_tgt_label_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tgt_label.add_child(_tgt_label_text)


func _new_rect(c: Color) -> ColorRect:

	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _layout_bar() -> void:
	# 立柱总高 = 可用高 * 0.75, 在 (BAR_TOP_PAD..底部) 之间垂直居中
	var avail_h: float = max(60.0, size.y - BAR_TOP_PAD - BAR_BOTTOM_PAD)
	_bar_h = max(60.0, avail_h * BAR_INNER_HEIGHT_SCALE)
	_bar_top = BAR_TOP_PAD + (avail_h - _bar_h) * 0.5
	# 立柱总宽 = 可用宽 * 0.6, 水平居中
	var avail_w: float = max(8.0, size.x - BAR_X * 2.0)
	_bar_w = max(8.0, avail_w * BAR_INNER_SCALE)
	var bar_left: float = (size.x - _bar_w) * 0.5

	# 4 条边线空心框
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
	# 内部水平刻度线
	for i in range(_ticks.size()):
		var idx: int = i + 1
		var ty: float = _bar_top + _bar_h * (float(idx) / float(TICK_COUNT))
		_ticks[i].position = Vector2(bar_left, ty - 0.5)
		_ticks[i].size = Vector2(_bar_w, 1.0)

	_layout_target_mark(bar_left)


func _layout_target_mark(bar_left: float) -> void:
	# 在 VICTORY_TARGET 对应的 y 上绘制 "目标资金线": 三角 → 虚线 → 标签
	if _tgt_arrow == null or _tgt_dashed == null or _tgt_label == null:
		return
	var y: float = _value_to_y(Game.VICTORY_TARGET)
	# 让标记在面板可用宽度内布局: 起点紧贴 bar 左边外, 终点贴 bar 右边外+ label
	var bar_right: float = bar_left + _bar_w
	# 标签 (右侧): "120K"
	var label_w: float = 32.0
	var label_h: float = 14.0
	var max_right: float = size.x - 2.0  # 面板右内边距
	var label_x: float = bar_right + 4.0
	if label_x + label_w > max_right:
		label_x = max(0.0, max_right - label_w)
	var label_y: float = clampf(y - label_h * 0.5, _bar_top - label_h * 0.5, _bar_top + _bar_h - label_h * 0.5)
	_tgt_label.position = Vector2(label_x, label_y)
	_tgt_label.size = Vector2(label_w, label_h)
	_tgt_label_text.text = "%dK" % int(Game.VICTORY_TARGET / 1000.0)
	_tgt_label.visible = true
	# 三角 (左侧, 朝右)
	var tri_size: float = 5.0
	var tri_right_x: float = max(2.0, bar_left - 4.0)
	var tri_left_x: float = max(0.0, tri_right_x - tri_size * 1.6)
	_tgt_arrow.polygon = PackedVector2Array([
		Vector2(tri_left_x, y - tri_size),
		Vector2(tri_right_x, y),
		Vector2(tri_left_x, y + tri_size)
	])
	_tgt_arrow.visible = true
	# 中段虚线: 从三角右边到 标签左边, 横跨 bar
	var dash_x: float = tri_right_x + 1.0
	var dash_w: float = max(4.0, label_x - 2.0 - dash_x)
	_tgt_dashed.position = Vector2(dash_x, y - 1.0)
	_tgt_dashed.size = Vector2(dash_w, 2.0)
	_tgt_dashed.set_ticks([0.5], TARGET_MARK_COL, 1.5)
	_tgt_dashed.queue_redraw()
	_tgt_dashed.visible = true



func _value_to_y(v: float) -> float:
	# 把 0..MAX 数值映射到 bar y 坐标 (底=0, 顶=MAX)
	var max_v: float = max(1.0, Game.VICTORY_TARGET * SCALE_RATIO)
	var ratio: float = clamp(v / max_v, 0.0, 1.0)
	return _bar_top + (1.0 - ratio) * _bar_h


func _refresh() -> void:
	if lbl_value == null:
		return
	var total: float = Game.get_total_assets()
	# 紧凑金额格式
	lbl_value.text = _format_money_compact(total)
	if total >= Game.VICTORY_TARGET:
		lbl_value.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_value.add_theme_color_override("font_color", UF.COL_GOLD)

	# 实心填充: 底部=现金, 上方=盈利(持仓市值)
	if _bar_fill != null and _bar_h > 0.0:
		var max_v: float = max(1.0, Game.VICTORY_TARGET * SCALE_RATIO)
		var cash_v: float = clamp(Game.cash, 0.0, max_v)
		var profit_v: float = clamp(Game.get_holding_value(), 0.0, max_v)
		var cash_ratio: float = cash_v / max_v
		var profit_ratio: float = profit_v / max_v
		# 总高不超过 bar
		var combined: float = min(cash_ratio + profit_ratio, 1.0)
		var actual_profit_ratio: float = combined - cash_ratio
		# 填充柱宽 = 内框宽 * FILL_WIDTH_SCALE (0.8), 留出左右更宽空白; 在内框内水平居中
		var fill_w: float = max(2.0, _bar_w * FILL_WIDTH_SCALE)
		var fill_x: float = (size.x - fill_w) * 0.5
		# 现金段 (底部)
		var cash_h: float = _bar_h * cash_ratio
		_bar_fill.color = FILL_COL
		_bar_fill.visible = cash_h > 0.5
		_bar_fill.position = Vector2(fill_x, _bar_top + _bar_h - cash_h)
		_bar_fill.size = Vector2(fill_w, cash_h)
		# 盈利段 (紧贴现金段上方)
		if _bar_profit_fill != null:
			var profit_h: float = _bar_h * actual_profit_ratio
			_bar_profit_fill.color = PROFIT_FILL_COL
			_bar_profit_fill.visible = profit_h > 0.5
			_bar_profit_fill.position = Vector2(fill_x, _bar_top + _bar_h - cash_h - profit_h)
			_bar_profit_fill.size = Vector2(fill_w, profit_h)



# 数值转 K 单位字符串 (旧函数, 已不在 UI 中显示, 保留为工具函数)
func _format_k(v: float) -> String:
	var k_val: float = v / 1000.0
	if abs(k_val) >= 1000.0:
		return "%.0fM" % (k_val / 1000.0)
	if abs(k_val - round(k_val)) < 0.05:
		return "%dK" % int(round(k_val))
	return "%.0fK" % k_val


# 紧凑金额格式: <100K 显示完整数字带千分位, ≥100K 显示 "¥xx.xK" 或 "¥xxK"
func _format_money_compact(v: float) -> String:
	var n: int = int(round(v))
	if abs(n) < 100000:
		return "¥%s" % UF.fmt_money(v)
	var k_val: float = float(n) / 1000.0
	if abs(k_val) >= 1000.0:
		return "¥%.1fM" % (k_val / 1000.0)
	if abs(k_val - round(k_val)) < 0.05:
		return "¥%dK" % int(round(k_val))
	return "¥%.1fK" % k_val
