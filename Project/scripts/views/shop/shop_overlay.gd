extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_shop_day: Label = $ShopPanel/Margin/RootVBox/TopBar/LblShopDay
@onready var lbl_shop_cash: Label = $ShopPanel/Margin/RootVBox/TopBar/LblShopCash
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
	summary_panel.visible = false
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
