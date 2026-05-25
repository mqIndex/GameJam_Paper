extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_stock_price: Label = $VBox/LblStockPrice
@onready var lbl_stock_change: Label = $VBox/LblStockChange
@onready var lbl_cash: Label = $VBox/LblCash
@onready var lbl_shares: Label = $VBox/LblShares
@onready var lbl_holding_value: Label = $VBox/LblHoldingValue
@onready var lbl_pnl: Label = $VBox/LblPnl
@onready var lbl_pnl_pct: Label = $VBox/LblPnlPct
@onready var lbl_total_assets: Label = $VBox/LblTotalAssets
@onready var lbl_target: Label = $VBox/LblTarget
@onready var vbox: VBoxContainer = $VBox
@onready var lbl_target_title: Label = $LblTargetTitle
@onready var bar_border: ColorRect = $BarBorder
@onready var bar_bg: ColorRect = $BarBg
@onready var bar_fill: ColorRect = $BarFill
@onready var lbl_bar_value: Label = $LblBarValue
@onready var lbl_bar_progress: Label = $LblBarProgress

const TEXT_MARGIN: float = 12.0
const TARGET_AREA_W: float = 44.0
const TARGET_LABEL_W: float = 36.0
const BAR_W: float = 26.0
const BAR_TOP_Y: float = 24.0
const BAR_VALUE_GAP: float = 4.0
const BAR_VALUE_H: float = 14.0
const BAR_PROGRESS_H: float = 16.0
const BOTTOM_PAD: float = 14.0

var _bar_max_h: float = 378.0
var _bar_bottom_y: float = 403.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	resized.connect(_on_resized)
	Game.state_changed.connect(_refresh)
	_layout_progress_bar()


func _on_resized() -> void:
	_layout_progress_bar()
	_refresh()


func _refresh() -> void:
	if lbl_stock_price == null:
		return
	lbl_stock_price.text = "¥%.2f" % Game.price
	var pct: float = (Game.price / Game.INITIAL_PRICE - 1.0) * 100.0
	var arrow := "▲" if pct >= 0 else "▼"
	lbl_stock_change.text = "%s %+.2f%%" % [arrow, pct]
	var price_color := UF.COL_UP if pct >= 0 else UF.COL_DOWN
	lbl_stock_price.add_theme_color_override("font_color", price_color)
	lbl_stock_change.add_theme_color_override("font_color", price_color)

	lbl_cash.text = "¥%s" % UF.fmt_money(Game.cash)
	lbl_shares.text = "%d 股" % Game.shares
	lbl_holding_value.text = "市值 ¥%s" % UF.fmt_money(Game.get_holding_value())

	var pnl: float = Game.get_total_assets() - Game.START_CASH
	var pnl_pct: float = pnl / Game.START_CASH * 100.0
	lbl_pnl.text = "%s¥%s" % ["+" if pnl >= 0 else "-", UF.fmt_money(abs(pnl))]
	lbl_pnl_pct.text = "%+.1f%%" % pnl_pct
	var pnl_color := UF.COL_UP if pnl >= 0 else UF.COL_DOWN
	lbl_pnl.add_theme_color_override("font_color", pnl_color)
	lbl_pnl_pct.add_theme_color_override("font_color", pnl_color)

	lbl_total_assets.text = "¥%s" % UF.fmt_money(Game.get_total_assets())

	var prog: float = Game.get_total_assets() / Game.VICTORY_TARGET * 100.0
	var ratio_p: float = clamp(prog / 100.0, 0.0, 1.0)
	var fill_h: float = _bar_max_h * ratio_p
	bar_fill.size.y = fill_h
	bar_fill.position.y = _bar_bottom_y - fill_h
	lbl_bar_progress.text = "%.0f%%" % clamp(prog, 0.0, 999.0)
	lbl_target.text = "目标 ¥%s  ·  %.0f%%" % [UF.fmt_money(Game.VICTORY_TARGET), clamp(prog, 0.0, 999.0)]

	if prog >= 100.0:
		lbl_target.add_theme_color_override("font_color", UF.COL_UP)
		lbl_bar_progress.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_target.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
		lbl_bar_progress.add_theme_color_override("font_color", UF.COL_TEXT)


func _layout_progress_bar() -> void:
	if vbox == null:
		return
	var target_x: float = max(0.0, size.x - TARGET_AREA_W)
	vbox.position = Vector2(TEXT_MARGIN, 8.0)
	vbox.size = Vector2(max(120.0, target_x - TEXT_MARGIN * 2.0), max(80.0, size.y - 16.0))

	var label_x: float = target_x + (TARGET_AREA_W - TARGET_LABEL_W) * 0.5
	lbl_target_title.position = Vector2(label_x, 8.0)
	lbl_target_title.size = Vector2(TARGET_LABEL_W, 14.0)

	var value_y: float = max(BAR_TOP_Y + 80.0 + BAR_VALUE_GAP, size.y - BOTTOM_PAD - BAR_PROGRESS_H - BAR_VALUE_H)
	var bar_bottom_y: float = value_y - BAR_VALUE_GAP
	_bar_max_h = max(48.0, bar_bottom_y - BAR_TOP_Y)
	_bar_bottom_y = BAR_TOP_Y + _bar_max_h

	var bar_x: float = target_x + (TARGET_AREA_W - BAR_W) * 0.5
	bar_border.position = Vector2(bar_x, BAR_TOP_Y)
	bar_border.size = Vector2(BAR_W, _bar_max_h + 2.0)
	bar_bg.position = Vector2(bar_x + 1.0, BAR_TOP_Y + 1.0)
	bar_bg.size = Vector2(BAR_W - 2.0, _bar_max_h)
	bar_fill.position.x = bar_x + 1.0
	bar_fill.size.x = BAR_W - 2.0

	lbl_bar_value.position = Vector2(label_x, value_y)
	lbl_bar_value.size = Vector2(TARGET_LABEL_W, BAR_VALUE_H)
	lbl_bar_progress.position = Vector2(label_x, value_y + BAR_VALUE_H + 2.0)
	lbl_bar_progress.size = Vector2(TARGET_LABEL_W, BAR_PROGRESS_H)
