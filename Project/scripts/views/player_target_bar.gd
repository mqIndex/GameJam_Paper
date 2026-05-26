# PlayerTargetBar — 玩家总资产竖向目标条
# 风格类似 EnemyHpBar, 立柱位于 DataPanel 右侧.
# 量程固定 0 → VICTORY_TARGET * 1.25 (即 150K), 目标位置在 100/125 比例 (120K).
# 资源来源: Game.get_total_assets() / Game.VICTORY_TARGET.
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

# 立柱底色段 (兼容字段, 不再使用)
const SEG_BLUE: Color = Color("#118ab2")
const SEG_YELLOW: Color = Color("#ffc857")
const SEG_DARK: Color = Color("#1c1320")
const BAR_BORDER_COL: Color = Color("#ffc857")
const TARGET_LINE_COL: Color = Color("#ffae42")
const MARKER_COL: Color = Color("#f5f5f5")
# 进度填充: 底部→当前资金 不透明; 当前资金→顶部 半透明
const FILL_LOW: Color = Color(0.067, 0.541, 0.698, 1.0)
const FILL_HIGH: Color = Color(1.0, 0.784, 0.341, 1.0)
const FILL_LOW_TRANS: Color = Color(0.067, 0.541, 0.698, 0.35)
const FILL_HIGH_TRANS: Color = Color(1.0, 0.784, 0.341, 0.35)

var _bar_top: float = BAR_TOP_PAD
var _bar_h: float = 0.0
var _bar_w: float = 28.0

# 运行时创建节点 (避免改 .tscn 复杂层级, 集中代码控制)
var _seg_blue: ColorRect = null
var _seg_yellow: ColorRect = null
var _seg_dark: ColorRect = null
var _bar_border: ColorRect = null
var _bar_fill: ColorRect = null
var _bar_fill_top: ColorRect = null
var _border_t: ColorRect = null
var _border_b: ColorRect = null
var _border_l: ColorRect = null
var _border_r: ColorRect = null
var _target_line: ColorRect = null
var _target_arrow: Polygon2D = null
var _target_label_bg: ColorRect = null
var _lbl_target_k: Label = null
var _marker: ColorRect = null
var _target_dashed: Control = null  # 120K 目标位置的橙色虚线
var _target_dashed_label_bg: ColorRect = null  # 120K 标签底框
var _lbl_target_dashed_k: Label = null         # 120K 标签
var _scale_labels: Array[Label] = []  # 已弃用 (兼容字段, 永远空)


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox(UF.COL_GOLD))
	_decorate_icon()
	_build_bar()
	resized.connect(_layout_bar)
	Game.state_changed.connect(_refresh)
	_layout_bar()
	_refresh()


func _decorate_icon() -> void:
	# 占位装饰: 圆形金底 + "$" 符号 (待美术补 player_icon.png 时替换)
	if icon_slot == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = UF.COL_GOLD
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
		l.text = "$"
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
	# 外框: 4 条边线拼成空心框 (替代实心 ColorRect, 让立柱内透明)
	_bar_border = _new_rect(Color(0, 0, 0, 0))
	_bar_border.visible = false
	_border_t = _new_rect(BAR_BORDER_COL)
	_border_b = _new_rect(BAR_BORDER_COL)
	_border_l = _new_rect(BAR_BORDER_COL)
	_border_r = _new_rect(BAR_BORDER_COL)
	# 旧 3 段背景 (兼容字段, 隐藏)
	_seg_dark = _new_rect(SEG_DARK)
	_seg_dark.visible = false
	_seg_yellow = _new_rect(SEG_YELLOW)
	_seg_yellow.visible = false
	_seg_blue = _new_rect(SEG_BLUE)
	_seg_blue.visible = false
	# 实体填充 (从底部到当前资金位置, 不透明)
	_bar_fill = _new_rect(FILL_LOW)
	# 半透明填充 (当前资金到顶部)
	_bar_fill_top = _new_rect(FILL_LOW_TRANS)
	# 120K 目标虚线 (静态, 橙色)
	_target_dashed = DashedTicks.new()
	add_child(_target_dashed)
	# 120K 目标数字标签 (静态, 跟在虚线右侧)
	_target_dashed_label_bg = _new_rect(UF.COL_BG_DEEP)
	_lbl_target_dashed_k = Label.new()
	_lbl_target_dashed_k.add_theme_font_size_override("font_size", 9)
	_lbl_target_dashed_k.add_theme_color_override("font_color", TARGET_LINE_COL)
	_lbl_target_dashed_k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_target_dashed_k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_lbl_target_dashed_k)
	# 当前资金醒目线 (跟随 Game.get_total_assets, 样式=橙色实线+三角+K标签)
	_target_line = _new_rect(TARGET_LINE_COL)
	_target_label_bg = _new_rect(UF.COL_BG_DEEP)
	_lbl_target_k = Label.new()
	_lbl_target_k.add_theme_font_size_override("font_size", 9)
	_lbl_target_k.add_theme_color_override("font_color", TARGET_LINE_COL)
	_lbl_target_k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_target_k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_lbl_target_k)
	_target_arrow = Polygon2D.new()
	_target_arrow.color = TARGET_LINE_COL
	add_child(_target_arrow)
	# 旧白色 marker 隐藏 (由橙色当前值线代替)
	_marker = _new_rect(MARKER_COL)
	_marker.visible = false
	# 旧 0/50K/100K/150K 灰色刻度文字已删除, 不再创建标签


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
	# 外框: 4 条边线 (在内框外 1px 形成空心)
	var ox: float = BAR_X - 1.0
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
	# 旧 3 段背景已隐藏, 不再布局
	# 120K 目标位置橙色虚线 (静态)
	var v120: float = _value_to_y(Game.VICTORY_TARGET)
	if _target_dashed != null:
		var dash_x: float = BAR_X - 4.0
		var dash_w: float = _bar_w + 8.0
		_target_dashed.position = Vector2(dash_x, v120 - 1.0)
		_target_dashed.size = Vector2(dash_w, 2.0)
		_target_dashed.set_ticks([0.5], TARGET_LINE_COL, 2.0)
	# 120K 目标数字标签 (静态, 跟在虚线右侧)
	if _lbl_target_dashed_k != null:
		var label_w: float = 28.0
		var label_h: float = 12.0
		var label_x: float = BAR_X + _bar_w + 4.0
		if label_x + label_w > size.x - 2.0:
			label_x = max(0.0, size.x - label_w - 2.0)
		var bar_bottom_y: float = _bar_top + _bar_h
		var label_y: float = clamp(v120 - label_h * 0.5, _bar_top - label_h * 0.5, bar_bottom_y - label_h * 0.5)
		_target_dashed_label_bg.position = Vector2(label_x - 1.0, label_y - 1.0)
		_target_dashed_label_bg.size = Vector2(label_w + 2.0, label_h + 2.0)
		_lbl_target_dashed_k.position = Vector2(label_x, label_y)
		_lbl_target_dashed_k.size = Vector2(label_w, label_h)
		_lbl_target_dashed_k.text = "%dK" % int(Game.VICTORY_TARGET / 1000.0)
	# 0/50K/100K/150K 灰色刻度文字已删除, 不再布局


func _value_to_y(v: float) -> float:
	# 把 0..MAX 的数值映射到 bar y 坐标 (底 = 0, 顶 = MAX)
	var max_v: float = max(1.0, Game.VICTORY_TARGET * SCALE_RATIO)
	var ratio: float = clamp(v / max_v, 0.0, 1.0)
	return _bar_top + (1.0 - ratio) * _bar_h


func _refresh() -> void:
	if lbl_value == null:
		return
	var total: float = Game.get_total_assets()
	# 自适应紧凑格式: 6 位以上数字用 K 缩写, 防止 18px 字号下溢出 88px 宽面板
	lbl_value.text = _format_money_compact(total)
	# 颜色随是否过目标线变化
	if total >= Game.VICTORY_TARGET:
		lbl_value.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_value.add_theme_color_override("font_color", UF.COL_GOLD)
	# 实体填充: 从底部到当前资金位置 (不透明) + 顶部半透明段
	if _bar_fill != null and _bar_h > 0.0:
		var max_v: float = max(1.0, Game.VICTORY_TARGET * SCALE_RATIO)
		var ratio: float = clamp(total / max_v, 0.0, 1.0)
		var fill_h: float = _bar_h * ratio
		var y_split: float = _bar_top + _bar_h - fill_h
		_bar_fill.position = Vector2(BAR_X, y_split)
		_bar_fill.size = Vector2(_bar_w, fill_h)
		_bar_fill.color = FILL_HIGH if total >= Game.VICTORY_TARGET else FILL_LOW
		if _bar_fill_top != null:
			var top_h: float = max(0.0, y_split - _bar_top)
			_bar_fill_top.position = Vector2(BAR_X, _bar_top)
			_bar_fill_top.size = Vector2(_bar_w, top_h)
			_bar_fill_top.color = FILL_HIGH_TRANS if total >= Game.VICTORY_TARGET else FILL_LOW_TRANS
	# 当前资金醒目线 (跟随 total, 样式=橙色实线+三角+K标签)
	if _target_line != null and _bar_h > 0.0:
		_target_line.visible = true
		_target_label_bg.visible = true
		_lbl_target_k.visible = true
		_target_arrow.visible = true
		var y: float = _value_to_y(total)
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
		var label_y: float = clamp(y - label_h * 0.5, _bar_top - label_h * 0.5, bar_bottom_y - label_h * 0.5)
		_target_label_bg.position = Vector2(label_x - 1.0, label_y - 1.0)
		_target_label_bg.size = Vector2(label_w + 2.0, label_h + 2.0)
		_lbl_target_k.position = Vector2(label_x, label_y)
		_lbl_target_k.size = Vector2(label_w, label_h)
		_lbl_target_k.text = _format_k(total)
	# 旧白色 marker 隐藏 (由橙色当前值线代替)
	if _marker != null:
		_marker.visible = false


# 数值转 K 单位字符串
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
