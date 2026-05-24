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
@onready var bar_fill: ColorRect = $BarFill
@onready var lbl_bar_progress: Label = $LblBarProgress

const BAR_MAX_H: float = 378.0
const BAR_BOTTOM_Y: float = 403.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.state_changed.connect(_refresh)


func _refresh() -> void:
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
	var fill_h: float = BAR_MAX_H * ratio_p
	bar_fill.size.y = fill_h
	bar_fill.position.y = BAR_BOTTOM_Y - fill_h
	lbl_bar_progress.text = "%.0f%%" % clamp(prog, 0.0, 999.0)
	lbl_target.text = "目标 ¥%s  ·  %.0f%%" % [UF.fmt_money(Game.VICTORY_TARGET), clamp(prog, 0.0, 999.0)]

	if prog >= 100.0:
		lbl_target.add_theme_color_override("font_color", UF.COL_UP)
		lbl_bar_progress.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_target.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
		lbl_bar_progress.add_theme_color_override("font_color", UF.COL_TEXT)
