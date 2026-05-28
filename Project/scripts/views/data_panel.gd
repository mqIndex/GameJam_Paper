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
@onready var lbl_target_title: Label = $VBox/TargetProgressRow/TargetHeader/LblTargetTitle
@onready var bar_border: ColorRect = $VBox/TargetProgressRow/BarBorder
@onready var bar_bg: ColorRect = $VBox/TargetProgressRow/BarBorder/BarBg
@onready var bar_fill: ColorRect = $VBox/TargetProgressRow/BarBorder/BarBg/BarFill
@onready var lbl_bar_progress: Label = $VBox/TargetProgressRow/TargetHeader/LblBarProgress
# 兼容字段: 旧版 .tscn 内有 LblBarValue / LblTarget, 当前已删除 → 用 get_node_or_null 不报错
@onready var lbl_bar_value: Label = get_node_or_null("VBox/TargetProgressRow/LblBarValue")
@onready var lbl_target: Label = get_node_or_null("VBox/TargetProgressRow/LblTarget")
@onready var mascot_slot: Panel = $VBox/MascotSlot
@onready var lbl_mascot: Label = $VBox/MascotSlot/MascotVBox/LblMascot
@onready var lbl_mascot_sub: Label = $VBox/MascotSlot/MascotVBox/LblMascotSub
@onready var mascot_vbox: VBoxContainer = $VBox/MascotSlot/MascotVBox
@onready var event_frame: Panel = $VBox/MascotSlot/EventFrame
@onready var event_image: TextureRect = $VBox/MascotSlot/EventFrame/EventImage
@onready var event_name_strip: Panel = get_node_or_null("VBox/MascotSlot/EventFrame/EventNameStrip")
@onready var lbl_event_name: Label = get_node_or_null("VBox/MascotSlot/EventFrame/EventNameStrip/LblEventName")


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	# 字号统一: 股价 28(本面板特例) / 网格数值 14 / 标签 10-11
	lbl_stock_price.add_theme_font_size_override("font_size", 28)
	lbl_stock_change.add_theme_font_size_override("font_size", 12)
	# MascotSlot 默认用于无事件占位；有事件图时会切成透明背景。
	_set_mascot_slot_event_mode(false)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# EventImage 鼠标交互: 可点击 + 手型光标 (有事件且图可见时才响应, 见 _on_event_image_input)
	if event_image != null:
		event_image.mouse_filter = Control.MOUSE_FILTER_STOP
		event_image.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		event_image.gui_input.connect(_on_event_image_input)
		event_image.mouse_entered.connect(_on_event_image_mouse_entered)
		event_image.mouse_exited.connect(_on_event_image_mouse_exited)
	Game.state_changed.connect(_refresh)
	Game.event_triggered.connect(_on_event_changed)
	_refresh()
	_apply_event_image()


# 点击事件图片: 复用 TopBar 的事件详情弹窗
func _on_event_image_input(event: InputEvent) -> void:
	if event_image == null or not event_image.visible:
		return
	if Game.current_event == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var top_bar: Node = get_node_or_null("/root/Main/TopBar")
			if top_bar != null:
				# 点击时先收起 hover tip, 再弹出详情, 避免重叠
				if top_bar.has_method("hide_event_tip"):
					top_bar.call("hide_event_tip")
				if top_bar.has_method("show_current_event_dialog"):
					top_bar.call("show_current_event_dialog")
			accept_event()


# 鼠标进入事件图: 显示 TopBar 的 hover tip (锚定在事件图下方)
func _on_event_image_mouse_entered() -> void:
	if event_image == null or not event_image.visible:
		return
	if Game.current_event == null:
		return
	var top_bar: Node = get_node_or_null("/root/Main/TopBar")
	if top_bar != null and top_bar.has_method("show_event_tip_for"):
		top_bar.call("show_event_tip_for", event_image)


# 鼠标离开事件图: 始终 hide (兼容守卫失败时手动 enter 的状态)
func _on_event_image_mouse_exited() -> void:
	var top_bar: Node = get_node_or_null("/root/Main/TopBar")
	if top_bar != null and top_bar.has_method("hide_event_tip"):
		top_bar.call("hide_event_tip")


# 事件切换时同步 MascotSlot 显示: 有图 → 显示 TextureRect; 无图/失败 → 回退到 APE 文字
func _on_event_changed(_ev) -> void:
	_apply_event_image()


func _set_mascot_slot_event_mode(has_event_image: bool) -> void:
	if mascot_slot == null:
		return
	if has_event_image:
		var empty_style := StyleBoxEmpty.new()
		mascot_slot.add_theme_stylebox_override("panel", empty_style)
	else:
		mascot_slot.add_theme_stylebox_override("panel", UF.texture_panel_stylebox(UF.COL_GOLD))


func _make_event_frame_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb


func _get_current_event_theme_color() -> Color:
	# 主题色完全由 Event.theme_color (event_database.gd 的 theme_color 字段) 决定,
	# 此处不再按 category/事件名做兜底; event_database._parse_theme_color 已处理空值兜底.
	var ev = Game.current_event
	if ev != null:
		return ev.theme_color
	return Color("#ffd166")


func _apply_event_image() -> void:
	if event_image == null or mascot_vbox == null:
		return
	var ev = Game.current_event
	var path: String = ""
	if ev != null:
		path = ev.image_path
	if path == "" or not ResourceLoader.exists(path):
		_set_mascot_slot_event_mode(false)
		event_image.texture = null
		event_image.visible = false
		if event_frame != null:
			event_frame.visible = false
		mascot_vbox.visible = true
		if lbl_mascot != null:
			lbl_mascot.visible = true
		if lbl_mascot_sub != null:
			lbl_mascot_sub.visible = true
		_apply_event_name_strip(null)
		return
	var tex = load(path)
	if tex is Texture2D:
		_set_mascot_slot_event_mode(true)
		event_image.texture = tex as Texture2D
		event_image.visible = true
		if event_frame != null:
			event_frame.add_theme_stylebox_override("panel", _make_event_frame_style(_get_current_event_theme_color()))
			event_frame.visible = true
		# 双保险: 同时隐藏 mascot_vbox 和它的子 Label
		mascot_vbox.visible = false
		if lbl_mascot != null:
			lbl_mascot.visible = false
		if lbl_mascot_sub != null:
			lbl_mascot_sub.visible = false
		_apply_event_name_strip(ev)
	else:
		_set_mascot_slot_event_mode(false)
		event_image.texture = null
		event_image.visible = false
		if event_frame != null:
			event_frame.visible = false
		mascot_vbox.visible = true
		if lbl_mascot != null:
			lbl_mascot.visible = true
		if lbl_mascot_sub != null:
			lbl_mascot_sub.visible = true
		_apply_event_name_strip(null)


# 事件名横条: 显示在事件图底部, 文字 = 事件名, 颜色 = 事件主题色;
# 无事件/无图时整条隐藏 (回退到 APE 占位时无此条)
func _apply_event_name_strip(ev) -> void:
	if event_name_strip == null or lbl_event_name == null:
		return
	if ev == null:
		event_name_strip.visible = false
		return
	var name_text: String = String(ev.name)
	if name_text == "":
		event_name_strip.visible = false
		return
	var color: Color = _get_current_event_theme_color()
	# 背景: 半透明黑底, 让事件主题色文字突出
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.78)
	sb.border_color = color
	sb.border_width_top = 1
	event_name_strip.add_theme_stylebox_override("panel", sb)
	lbl_event_name.text = "«  %s  »" % name_text
	lbl_event_name.add_theme_color_override("font_color", color)
	lbl_event_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_event_name.add_theme_constant_override("outline_size", 2)
	event_name_strip.visible = true


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
	if lbl_bar_value != null:
		lbl_bar_value.text = "目标 ¥%s" % UF.fmt_money(Game.VICTORY_TARGET)
	if lbl_target != null:
		lbl_target.text = ""

	if prog >= 100.0:
		lbl_bar_progress.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_bar_progress.add_theme_color_override("font_color", UF.COL_TEXT)
