extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_stock_price: Label = $VBox/TopRow/LblStockPrice
@onready var lbl_stock_change: Label = $VBox/LblStockChange
@onready var lbl_cash: Label = $VBox/StatsGrid/CellCash/LblCash
@onready var lbl_shares: Label = $VBox/StatsGrid/CellShares/LblShares
@onready var lbl_holding_value: Label = $VBox/StatsGrid/CellShares/LblHoldingValue
@onready var lbl_pnl: Label = $VBox/StatsGrid/CellPnl/LblPnl
@onready var lbl_pnl_pct: Label = $VBox/StatsGrid/CellPnl/LblPnlPct
@onready var lbl_total_assets: Label = $VBox/StatsGrid/CellTotal/LblTotalAssets
@onready var lbl_target: Label = $VBox/TargetProgressRow/LblTarget
@onready var lbl_target_title: Label = $VBox/TargetProgressRow/TargetHeader/LblTargetTitle
@onready var bar_border: ColorRect = $VBox/TargetProgressRow/BarBorder
@onready var bar_bg: ColorRect = $VBox/TargetProgressRow/BarBorder/BarBg
@onready var bar_fill: ColorRect = $VBox/TargetProgressRow/BarBorder/BarBg/BarFill
@onready var lbl_bar_value: Label = $VBox/TargetProgressRow/LblBarValue
@onready var lbl_bar_progress: Label = $VBox/TargetProgressRow/TargetHeader/LblBarProgress
@onready var mascot_slot: Panel = $VBox/MascotSlot
@onready var lbl_mascot: Label = $VBox/MascotSlot/MascotVBox/LblMascot
@onready var lbl_mascot_sub: Label = $VBox/MascotSlot/MascotVBox/LblMascotSub


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	# 字号统一: 股价 28(本面板特例) / 网格数值 14 / 标签 10-11
	lbl_stock_price.add_theme_font_size_override("font_size", 28)
	lbl_stock_change.add_theme_font_size_override("font_size", 12)
	# MascotSlot 用霓虹面板样式 (优先贴图; 缺失则 fallback)
	mascot_slot.add_theme_stylebox_override("panel", UF.texture_panel_stylebox(UF.COL_GOLD))
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.state_changed.connect(_refresh)
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

	# 目标进度: 横向 ProgressBar (BarFill 宽度按比例)
	var prog: float = Game.get_total_assets() / Game.VICTORY_TARGET * 100.0
	var ratio_p: float = clamp(prog / 100.0, 0.0, 1.0)
	if bar_bg != null:
		var inner_w: float = max(0.0, bar_bg.size.x)
		var inner_h: float = max(0.0, bar_bg.size.y)
		bar_fill.set_deferred("size", Vector2(inner_w * ratio_p, inner_h))
		bar_fill.set_deferred("position", Vector2.ZERO)
	lbl_bar_progress.text = "%.0f%%" % clamp(prog, 0.0, 999.0)
	lbl_bar_value.text = "目标 ¥%s" % UF.fmt_money(Game.VICTORY_TARGET)
	lbl_target.text = ""

	if prog >= 100.0:
		lbl_bar_progress.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_bar_progress.add_theme_color_override("font_color", UF.COL_TEXT)
