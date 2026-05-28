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
	_force_full_rect(self)
	_force_full_rect(get_node_or_null("Dim") as Control)
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


func _force_full_rect(ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	ctrl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ctrl.grow_vertical = Control.GROW_DIRECTION_BOTH


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
		var forced_shares: int = int(s.get("forced_liquidation_shares", 0))
		var summary: String = (
			"开盘 ¥%.2f → 收盘 ¥%.2f (%+.2f%%)  ·  持仓 %d 股, 市值 ¥%s\n" +
			"现金 ¥%s  ·  总资产 ¥%s  ·  今日盈亏 %s"
		) % [
			s["open_price"], s["close_price"], price_pct,
			int(s["shares"]), UF.fmt_money(s["holding_value"]),
			UF.fmt_money(s["cash"]), UF.fmt_money(s["total_assets"]),
			pnl_str
		]
		if forced_shares > 0:
			var discount: float = float(s.get("forced_discount", 0.8))
			var proceeds: float = float(s.get("forced_liquidation_proceeds", 0.0))
			summary += "\n尾盘强制清仓: %d 股 × ¥%.2f × %.0f%% = ¥%s" % [
				forced_shares, float(s["close_price"]), discount * 100.0,
				UF.fmt_money(proceeds)
			]
		lbl_summary.text = summary

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
