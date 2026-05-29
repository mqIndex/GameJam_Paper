extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

const DIM_COLOR: Color = Color(0.0, 0.0, 0.0, 0.64)
const PANEL_COLOR: Color = Color(0.04, 0.07, 0.13, 0.90)
const HIGHLIGHT_INSET: float = 0.0
const TOOLTIP_SIZE: Vector2 = Vector2(360.0, 118.0)

const HELP_ITEMS: Array[Dictionary] = [
	{
		"path": "TopBar/LeftBar",
		"title": "日期回合",
		"summary": "当前天数和回合",
		"detail": "每天有固定回合数。回合用完后会进入当日结算，没清掉的持仓会按尾盘规则处理。",
	},
	{
		"path": "TopBar/MidBar",
		"title": "市场情绪",
		"summary": "影响后续涨跌倾向",
		"detail": "情绪越热，买盘越容易推动上涨；情绪越冷，下跌压力越明显。部分卡牌会直接改变这里。",
	},
	{
		"path": "TopBar/RightBar",
		"title": "天赋与设置",
		"summary": "查看天赋、帮助和音乐",
		"detail": "这里会显示已获得的天赋图标。右侧按钮可以打开本帮助或调节背景音乐音量。",
	},
	{
		"path": "EnemyHpBar",
		"title": "空头资金",
		"summary": "对手压力和爆仓进度",
		"detail": "空头会通过做空获利。把价格推到关键位置，可以迫使对手爆仓退场。",
	},
	{
		"path": "ChartPanel",
		"title": "行情图",
		"summary": "观察价格走势",
		"detail": "这里记录本日股价变化、事件影响和你的出牌造成的走势变化，是判断操作节奏的核心区域。",
	},
	{
		"path": "DataPanel",
		"title": "股票数据",
		"summary": "股价、持仓和事件",
		"detail": "显示当前股价、涨跌、持仓、市值和当日事件。事件图可悬浮查看详情，点击可打开说明。",
	},
	{
		"path": "PlayerTargetBar",
		"title": "周目标",
		"summary": "本周绩效进度",
		"detail": "你的总资产需要在周五结算时达到目标线。资金、持仓市值都会计入总资产。",
	},
	{
		"path": "ActionBar",
		"title": "行动栏",
		"summary": "现金和行动点",
		"detail": "每张牌会消耗行动点。行动点用完后通常需要结束回合，现金不足时买入类操作会受限。",
	},
	{
		"path": "EnemyPanel",
		"title": "空头席位",
		"summary": "查看对手状态",
		"detail": "这里展示对手名称、仓位和行动反馈。对手入场或退场时，也会有额外提示。",
	},
	{
		"path": "HandPanel",
		"title": "手牌区",
		"summary": "选择并打出卡牌",
		"detail": "你的主要操作都从这里开始。买入、卖出、造势、技能牌会改变资产、股价或牌堆。",
	},
	{
		"path": "TurnPanel",
		"title": "回合控制",
		"summary": "结束回合和查看牌堆",
		"detail": "这里可以结束回合、撤回本回合操作，并查看抽牌堆或弃牌堆。",
	},
	{
		"path": "PlayerPanel",
		"title": "你的账户",
		"summary": "玩家资产和头像",
		"detail": "这里展示玩家信息和关键账户数据。现金用于买入和商店消费，持仓会随股价波动计入资产。",
	},
]

var _main: Control = null
var _dim: ColorRect = null
var _title: Label = null
var _close_button: Button = null
var _items_layer: Control = null
var _tooltip: PanelContainer = null
var _tooltip_title: Label = null
var _tooltip_body: Label = null
var _item_boxes: Dictionary = {}
var _hover_key: String = ""
var _hover_tween: Tween = null


func setup(main_node: Control) -> void:
	_main = main_node


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	resized.connect(_refresh_layout)
	set_process(false)


func open() -> void:
	visible = true
	set_process(true)
	_refresh_layout()


func close() -> void:
	visible = false
	set_process(false)
	_hover_key = ""
	_hide_tooltip()


func _process(_delta: float) -> void:
	if visible:
		_refresh_layout()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_items_layer = Control.new()
	_items_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_items_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_items_layer)

	_title = Label.new()
	_title.text = "玩法介绍帮助"
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", UF.COL_GOLD)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 2)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_close_button = UF.button("关闭", UF.COL_GOLD, 14)
	_close_button.custom_minimum_size = Vector2(86.0, 32.0)
	_close_button.pressed.connect(close)
	add_child(_close_button)

	_tooltip = PanelContainer.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.custom_minimum_size = TOOLTIP_SIZE
	_tooltip.add_theme_stylebox_override("panel", UF.neon_panel_stylebox(UF.COL_HIGHLIGHT))
	add_child(_tooltip)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_tooltip.add_child(box)
	_tooltip_title = Label.new()
	_tooltip_title.add_theme_font_size_override("font_size", 17)
	_tooltip_title.add_theme_color_override("font_color", UF.COL_HIGHLIGHT)
	box.add_child(_tooltip_title)
	_tooltip_body = Label.new()
	_tooltip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_body.add_theme_font_size_override("font_size", 13)
	_tooltip_body.add_theme_color_override("font_color", UF.COL_TEXT)
	box.add_child(_tooltip_body)

	for item in HELP_ITEMS:
		_create_item_box(item)


func _create_item_box(item: Dictionary) -> void:
	var key: String = String(item.get("path", ""))
	if key == "":
		return
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _highlight_style(false))
	panel.set_meta("help_item", item)
	panel.mouse_entered.connect(_on_item_entered.bind(key))
	panel.mouse_exited.connect(_on_item_exited.bind(key))
	_items_layer.add_child(panel)

	var label := Label.new()
	label.name = "LblSummary"
	label.text = "%s · %s" % [String(item.get("title", "")), String(item.get("summary", ""))]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UF.COL_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	label.add_theme_constant_override("outline_size", 1)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	_item_boxes[key] = panel


func _highlight_style(hovered: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UF.COL_GOLD.r, UF.COL_GOLD.g, UF.COL_GOLD.b, 0.10 if hovered else 0.035)
	sb.border_color = Color(UF.COL_GOLD.r, UF.COL_GOLD.g, UF.COL_GOLD.b, 1.0 if hovered else 0.86)
	sb.border_width_left = 3 if hovered else 2
	sb.border_width_top = 3 if hovered else 2
	sb.border_width_right = 3 if hovered else 2
	sb.border_width_bottom = 3 if hovered else 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(UF.COL_GOLD.r, UF.COL_GOLD.g, UF.COL_GOLD.b, 0.26 if hovered else 0.14)
	sb.shadow_size = 7 if hovered else 4
	return sb


func _refresh_layout() -> void:
	if _dim == null:
		return
	_dim.size = size
	_items_layer.size = size
	_title.position = Vector2(18.0, 14.0).round()
	_title.size = Vector2(max(280.0, size.x - 140.0), 34.0)
	_close_button.position = Vector2(max(18.0, size.x - 104.0), 14.0).round()
	_close_button.size = Vector2(86.0, 32.0)

	for item in HELP_ITEMS:
		var key: String = String(item.get("path", ""))
		var panel := _item_boxes.get(key, null) as Panel
		if panel == null:
			continue
		var target := _main.get_node_or_null(key) as Control if _main != null else null
		if target == null or not target.is_visible_in_tree():
			panel.visible = false
			continue
		var rect := _inset_rect(target.get_global_rect(), HIGHLIGHT_INSET)
		rect.position = get_global_transform().affine_inverse() * rect.position
		if rect.size.x <= 2.0 or rect.size.y <= 2.0:
			panel.visible = false
			continue
		panel.visible = true
		panel.position = rect.position.round()
		panel.size = rect.size.round()
		panel.pivot_offset = panel.size * 0.5
		var label := panel.get_node_or_null("LblSummary") as Label
		if label != null:
			label.position = Vector2(7.0, 5.0)
			label.size = Vector2(max(24.0, panel.size.x - 14.0), 18.0)
	if _hover_key != "":
		_position_tooltip_for_key(_hover_key)


func _on_item_entered(key: String) -> void:
	_hover_key = key
	var panel := _item_boxes.get(key, null) as Panel
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _highlight_style(true))
	_start_hover_tween(panel, Vector2.ONE)
	var item: Dictionary = panel.get_meta("help_item") as Dictionary
	_tooltip_title.text = String(item.get("title", ""))
	_tooltip_body.text = String(item.get("detail", ""))
	_tooltip.visible = true
	_position_tooltip_for_key(key)


func _on_item_exited(key: String) -> void:
	if _hover_key == key:
		_hover_key = ""
		_hide_tooltip()
	var panel := _item_boxes.get(key, null) as Panel
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", _highlight_style(false))
	_start_hover_tween(panel, Vector2.ONE)


func _start_hover_tween(panel: Panel, target_scale: Vector2) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(panel, "scale", target_scale, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _inset_rect(rect: Rect2, inset: float) -> Rect2:
	if rect.size.x > inset * 2.0 + 12.0 and rect.size.y > inset * 2.0 + 12.0:
		return rect.grow(-inset)
	return rect


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


func _position_tooltip_for_key(key: String) -> void:
	var panel := _item_boxes.get(key, null) as Panel
	if panel == null or _tooltip == null:
		return
	var rect := Rect2(panel.position, panel.size)
	_tooltip.reset_size()
	var tip_size := Vector2(
		max(_tooltip.custom_minimum_size.x, _tooltip.size.x),
		max(_tooltip.custom_minimum_size.y, _tooltip.size.y)
	)
	var pos := Vector2(rect.end.x + 12.0, rect.position.y)
	if pos.x + tip_size.x > size.x - 14.0:
		pos.x = rect.position.x - tip_size.x - 12.0
	if pos.x < 14.0:
		pos.x = 14.0
	if pos.y + tip_size.y > size.y - 14.0:
		pos.y = size.y - tip_size.y - 14.0
	pos.y = max(56.0, pos.y)
	_tooltip.position = pos.round()
	_tooltip.size = tip_size.round()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close()
