extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_shop_day: Label = $ShopPanel/Margin/RootVBox/TopBar/LblShopDay
@onready var lbl_shop_cash: Label = $ShopPanel/Margin/RootVBox/TopBar/LblShopCash
@onready var lbl_summary: Label = $ShopPanel/Margin/RootVBox/SummaryPanel/SumMargin/SumVBox/LblSummary
@onready var btn_leave_shop: Button = $ShopPanel/Margin/RootVBox/BottomBar/BtnLeaveShop
@onready var summary_panel: PanelContainer = $ShopPanel/Margin/RootVBox/SummaryPanel
@onready var tabs: TabContainer = $ShopPanel/Margin/RootVBox/Tabs

var _tutorial_button_override: String = ""


func _ready() -> void:
	btn_leave_shop.add_theme_color_override("font_color", UF.COL_HIGHLIGHT)
	var sb := UF.panel_stylebox(UF.COL_HIGHLIGHT)
	btn_leave_shop.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UF.COL_HIGHLIGHT.r, UF.COL_HIGHLIGHT.g, UF.COL_HIGHLIGHT.b, 0.18)
	btn_leave_shop.add_theme_stylebox_override("hover", hover)
	summary_panel.add_theme_stylebox_override("panel", UF.panel_stylebox())
	btn_leave_shop.pressed.connect(_on_leave_shop_pressed)
	Game.shop_entered.connect(_on_shop_entered)
	Game.shop_changed.connect(_refresh_header)
	Game.phase_changed.connect(_on_phase_changed)


func _on_shop_entered(_d: int) -> void:
	visible = true
	if tabs != null:
		tabs.current_tab = 0
	_refresh_header()


func _on_phase_changed(p: int) -> void:
	if p != Game.Phase.SHOP:
		visible = false


func _on_leave_shop_pressed() -> void:
	var tutorial := _tutorial_overlay()
	if tutorial != null and tutorial.has_method("is_shop_tutorial_active") and tutorial.call("is_shop_tutorial_active"):
		if tutorial.has_method("handle_shop_continue"):
			var consumed: bool = tutorial.call("handle_shop_continue")
			if consumed:
				return
	Game.leave_shop_to_next_day()


func set_tutorial_button_override(text: String) -> void:
	_tutorial_button_override = text
	btn_leave_shop.text = text
	btn_leave_shop.visible = text != ""


func clear_tutorial_button_override() -> void:
	_tutorial_button_override = ""
	btn_leave_shop.visible = true
	_refresh_header()


func _refresh_header() -> void:
	if not visible:
		return
	lbl_shop_day.text = "第 %d / %d 天 结束" % [Game.day, Game.DAYS_PER_LEVEL]
	lbl_shop_cash.text = "¥%s" % UF.fmt_money(Game.cash)

	var s: Dictionary = Game.day_close_summary
	if s.is_empty():
		lbl_summary.text = "(无)"
	else:
		var pnl: float = s["day_pnl"]
		var pnl_str: String = "%s¥%s" % ["+" if pnl >= 0 else "-", UF.fmt_money(abs(pnl))]
		var price_pct: float = s["price_change_pct"]
		lbl_summary.text = (
			"开盘 ¥%.2f → 收盘 ¥%.2f (%+.2f%%)  ·  持仓 %d 股, 市值 ¥%s\n" +
			"现金 ¥%s  ·  总资产 ¥%s  ·  今日盈亏 %s"
		) % [
			s["open_price"], s["close_price"], price_pct,
			int(s["shares"]), UF.fmt_money(s["holding_value"]),
			UF.fmt_money(s["cash"]), UF.fmt_money(s["total_assets"]),
			pnl_str
		]

	if _tutorial_button_override != "":
		btn_leave_shop.text = _tutorial_button_override
	elif Game.day >= Game.DAYS_PER_LEVEL:
		btn_leave_shop.text = "结束本周, 进入最终结算 →"
	else:
		btn_leave_shop.text = "离开商店, 进入下一天 →"


func _tutorial_overlay() -> Control:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("TutorialOverlay") as Control
