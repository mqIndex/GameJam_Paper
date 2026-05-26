# EnemyHpBar — 对手平仓危险度竖向条 (与 PlayerTargetBar 镜像布局, 红色调)
# 显示对手的危险度 (当前股价 / 平仓线), 越高越满, 顶端达到 100% 表示触发强平.
# 风格: 标题 + 数值 + 圆形图标占位 + 立柱(3段红色) + 目标线 + 三角箭头 + Marker + 刻度
extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

# 旧 @onready 全部保留 (节点已 visible=false 但仍可被赋值, 防外部调用报错)
@onready var lbl_title: Label = $LblTitle
@onready var lbl_value: Label = $LblValue
@onready var icon_slot: Panel = $IconSlot
@onready var lbl_liq_price: Label = $LblLiqPrice
@onready var bar_bg: ColorRect = $BarBg
@onready var bar_fill: ColorRect = $BarFill

const BAR_TOP_PAD: float = 80.0
const BAR_BOTTOM_PAD: float = 12.0
const BAR_X: float = 12.0

# 立柱底色段 (从下到上: 安全→警戒→致命), 全部红色调
const SEG_LOW: Color = Color("#3a1820")     # 暗红 (0%-50%, 安全)
const SEG_MID: Color = Color("#7a2030")     # 中红 (50%-80%, 警戒)
const SEG_HIGH: Color = Color("#a82838")    # 亮红 (80%-100%, 危险)
const BAR_BORDER_COL: Color = Color("#ff5d6c")
const TARGET_LINE_COL: Color = Color("#ff8c42")  # 强平阈值线 (橙色, 与玩家目标线对称)
const MARKER_COL: Color = Color("#f5f5f5")

var _bar_top: float = BAR_TOP_PAD
var _bar_h: float = 0.0
var _bar_w: float = 28.0

# 运行时构建的视觉节点
var _seg_low: ColorRect = null
var _seg_mid: ColorRect = null
var _seg_high: ColorRect = null
var _bar_border: ColorRect = null
var _target_line: ColorRect = null
var _target_arrow: Polygon2D = null
var _target_label_bg: ColorRect = null
var _lbl_target_k: Label = null
var _marker: ColorRect = null
var _scale_labels: Array[Label] = []


func _ready() -> void:
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
	# 占位装饰: 圆形红底 + "✕" 符号 (与玩家 $ 图标对称, 待美术补对手图标时替换)
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
	# 段背景 (从上到下覆盖: high 在顶, low 在底)
	_seg_high = _new_rect(SEG_HIGH)
	_seg_mid = _new_rect(SEG_MID)
	_seg_low = _new_rect(SEG_LOW)
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
	_marker = _new_rect(MARKER_COL)
	# 刻度: 100% / 80% / 50% / 0%
	for txt in ["100%", "80%", "50%", "0%"]:
		var l := Label.new()
		l.text = txt
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
	# 外框
	_bar_border.position = Vector2(BAR_X - 1.0, _bar_top - 1.0)
	_bar_border.size = Vector2(_bar_w + 2.0, _bar_h + 2.0)
	# 段位 (按 0/50/80/100 比例)
	var v50: float = _pct_to_y(0.5)
	var v80: float = _pct_to_y(0.8)
	var v100: float = _bar_top
	var bar_bottom: float = _bar_top + _bar_h
	# 底段 (0-50% 安全 暗红)
	_seg_low.position = Vector2(BAR_X, v50)
	_seg_low.size = Vector2(_bar_w, bar_bottom - v50)
	# 中段 (50-80% 警戒 中红)
	_seg_mid.position = Vector2(BAR_X, v80)
	_seg_mid.size = Vector2(_bar_w, v50 - v80)
	# 顶段 (80-100% 危险 亮红)
	_seg_high.position = Vector2(BAR_X, v100)
	_seg_high.size = Vector2(_bar_w, v80 - v100)
	# 旧的 80% 静态目标线/标签/箭头 已不再使用 (改为跟随当前危险度由 _refresh 设置)
	# 刻度: 100% / 80% / 50% / 0% 改为显示对应的股价 (= 平仓线 × 比例)
	var scale_pcts: Array[float] = [1.0, 0.8, 0.5, 0.0]
	var label_w: float = 36.0  # 加宽以容纳价格 "¥xxx"
	var label_x: float = BAR_X + _bar_w + 4.0
	if label_x + label_w > size.x - 2.0:
		label_x = max(0.0, size.x - label_w - 2.0)
	# 读取平仓线 (仅对手在场显示, 未入场或已击败均隐藏刻度)
	var liq_price: float = 0.0
	var opp = Game.get_opponent_state()
	if opp != null and opp.present and not opp.defeated_this_level:
		liq_price = float(opp.liquidation_price)
	for i in range(_scale_labels.size()):
		var y: float = _pct_to_y(scale_pcts[i])
		var l: Label = _scale_labels[i]
		if liq_price > 0.0:
			var price: float = liq_price * scale_pcts[i]
			l.text = _format_price(price)
			l.visible = true
		else:
			# 对手未入场, 隐藏刻度
			l.visible = false
		l.size = Vector2(label_w, 10.0)
		l.position = Vector2(label_x, y - 5.0)


# 价格紧凑格式 (适配 28px 标签宽度): <1K 用 "¥123"; ≥1K 用 "¥1.2K"
func _format_price(p: float) -> String:
	if abs(p) < 1000.0:
		return "¥%d" % int(round(p))
	var k: float = p / 1000.0
	if abs(k - round(k)) < 0.05:
		return "¥%dK" % int(round(k))
	return "¥%.1fK" % k


func _pct_to_y(pct: float) -> float:
	var ratio: float = clamp(pct, 0.0, 1.0)
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
		return
	if opp.defeated_this_level:
		lbl_value.text = "击败"
		lbl_value.add_theme_color_override("font_color", UF.COL_UP)
		_hide_current_marks()
		return
	# 在场: 显示危险度 %
	var danger: float = opp.get_danger_pct(Game.price)
	lbl_value.text = "%d%%" % int(danger * 100.0)
	# 颜色随危险度变化
	if danger >= 0.8:
		lbl_value.add_theme_color_override("font_color", UF.COL_DOWN)
	elif danger >= 0.5:
		lbl_value.add_theme_color_override("font_color", UF.COL_YELLOW)
	else:
		lbl_value.add_theme_color_override("font_color", UF.COL_NEON_RED)
	# 当前危险度醒目线 (替代原白色 marker, 现在样式 = 原 80% 目标线: 橙色横线 + 三角箭头 + % 标签)
	if _target_line != null and _bar_h > 0.0:
		_target_line.visible = true
		_target_label_bg.visible = true
		_lbl_target_k.visible = true
		_target_arrow.visible = true
		var y: float = _pct_to_y(danger)
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
		_lbl_target_k.text = "%d%%" % int(danger * 100.0)
	# 旧白色 marker 隐藏 (由橙色线代替)
	if _marker != null:
		_marker.visible = false


func _hide_current_marks() -> void:
	if _target_line != null: _target_line.visible = false
	if _target_label_bg != null: _target_label_bg.visible = false
	if _lbl_target_k != null: _lbl_target_k.visible = false
	if _target_arrow != null: _target_arrow.visible = false
	if _marker != null: _marker.visible = false
