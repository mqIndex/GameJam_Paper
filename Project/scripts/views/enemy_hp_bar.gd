extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var bar_bg: ColorRect = $BarBg
@onready var bar_fill: ColorRect = $BarFill
@onready var lbl_value: Label = $LblValue
@onready var lbl_liq_price: Label = $LblLiqPrice

const BAR_TOP_PAD: float = 44.0
const BAR_BOTTOM_PAD: float = 28.0
const BAR_X: float = 14.0

var _bar_top_y: float = BAR_TOP_PAD
var _bar_height: float = 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	resized.connect(_layout_bar)
	Game.opponent_state_changed.connect(_refresh)
	Game.opponent_entered.connect(func(_id): _refresh())
	Game.opponent_defeated.connect(func(_id, _r): _refresh())
	Game.state_changed.connect(_refresh)
	_layout_bar()


func _set_bar_color(c: Color) -> void:
	if bar_fill == null:
		return
	bar_fill.color = c


func _layout_bar() -> void:
	_bar_top_y = BAR_TOP_PAD
	_bar_height = max(48.0, size.y - BAR_TOP_PAD - BAR_BOTTOM_PAD)
	var bar_w: float = max(8.0, size.x - BAR_X * 2.0)
	bar_bg.position = Vector2(BAR_X, _bar_top_y)
	bar_bg.size = Vector2(bar_w, _bar_height)
	if lbl_value != null:
		lbl_value.position = Vector2(4.0, _bar_top_y + _bar_height + 2.0)
		lbl_value.size = Vector2(size.x - 8.0, 18.0)
	_refresh()


func _refresh() -> void:
	if bar_fill == null:
		return
	var opp = Game.get_opponent_state()
	if opp == null or (not opp.present and not opp.defeated_this_level):
		_set_bar_visible(false)
		lbl_value.text = "--"
		lbl_liq_price.text = "--"
		return
	if opp.defeated_this_level:
		_set_bar_visible(false)
		lbl_value.text = "击败"
		lbl_liq_price.text = "--"
		return
	# 危险度 = 当前股价 / 平仓线 (0~1, 越高越危险)
	var danger: float = opp.get_danger_pct(Game.price)
	var fill_h: float = _bar_height * danger
	var bar_w: float = max(8.0, size.x - BAR_X * 2.0)
	# 从底部往上填充, 危险度越高填越满
	bar_fill.position = Vector2(BAR_X, _bar_top_y + _bar_height - fill_h)
	bar_fill.size = Vector2(bar_w, fill_h)
	bar_fill.visible = true
	# 上方显示平仓线价格
	lbl_liq_price.text = "¥%.1f" % opp.liquidation_price
	# 下方显示当前危险度百分比
	lbl_value.text = "%d%%" % int(danger * 100.0)
	# 颜色: 危险度越高越红
	var col: Color
	if danger >= 0.8:
		col = UF.COL_DOWN
	elif danger >= 0.6:
		col = UF.COL_YELLOW
	else:
		col = UF.COL_UP
	_set_bar_color(col)


func _set_bar_visible(v: bool) -> void:
	bar_fill.visible = v
