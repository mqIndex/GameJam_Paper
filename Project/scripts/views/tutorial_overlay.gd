extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

const AVATAR_PATH: String = "res://assets/baoshu_avatar_UpperHalf.png"
const SCRIM_COLOR: Color = Color(0.0, 0.0, 0.0, 0.58)
const PANEL_COLOR: Color = Color(0.04, 0.07, 0.13, 0.86)
const HIGHLIGHT_PAD: float = 8.0
const DIALOG_H: float = 126.0
const PLAYER_DIALOG_H: float = 70.0
const SHOP_DIALOG_H: float = 140.0
const PROMPT_H: float = 64.0

class TutorialArrow:
	extends Control

	var fill_color: Color = Color(0.04, 0.07, 0.13, 0.86)
	var points_down: bool = true

	func _draw() -> void:
		var pts: PackedVector2Array
		if points_down:
			pts = PackedVector2Array([
				Vector2(0.0, 0.0),
				Vector2(size.x, 0.0),
				Vector2(size.x * 0.5, size.y),
			])
		else:
			pts = PackedVector2Array([
				Vector2(size.x * 0.5, 0.0),
				Vector2(0.0, size.y),
				Vector2(size.x, size.y),
			])
		draw_colored_polygon(pts, fill_color)


var _main: Control = null
var _steps: Array = []
var _step_index: int = -1
var _active: bool = false
var _mode: String = "level"
var _embedded_shop_active: bool = false
var _wait_shares: int = 0
var _wait_bull: int = 0
var _wait_cash: float = 0.0
var _wait_price: float = 0.0
var _pulse_tween: Tween = null
var _highlighted_card: Control = null

var _full_scrim: ColorRect = null
var _scrims: Array = []
var _highlight: Panel = null
var _intro_panel: PanelContainer = null
var _intro_button: Button = null
var _dialog: PanelContainer = null
var _avatar: TextureRect = null
var _name_label: Label = null
var _dialog_text: Label = null
var _player_dialog: PanelContainer = null
var _player_dialog_text: Label = null
var _prompt: PanelContainer = null
var _prompt_text: Label = null
var _arrow: TutorialArrow = null
var _next_button: Button = null


func setup(main_node: Control) -> void:
	_main = main_node


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_steps()
	Game.state_changed.connect(_on_game_changed)
	Game.hand_changed.connect(_on_game_changed)
	resized.connect(_update_layout)


func _process(_delta: float) -> void:
	if _active and visible:
		_update_layout()


func start() -> void:
	if _active:
		return
	_mode = "level"
	_embedded_shop_active = false
	_build_steps()
	if _full_scrim != null:
		_full_scrim.color = SCRIM_COLOR
	_set_scrim_blocks_input(true)
	_active = true
	visible = true
	_step_index = -1
	_go_next()


func start_shop() -> void:
	if _active:
		return
	_mode = "shop"
	_embedded_shop_active = false
	_build_shop_steps()
	_set_scrim_blocks_input(true)
	Game.begin_shop_tutorial()
	_active = true
	visible = true
	_step_index = -1
	_go_next()
	_layout_shop_dialog()


func is_shop_tutorial_active() -> bool:
	return _active and (_mode == "shop" or _embedded_shop_active)


func handle_shop_continue() -> bool:
	if not is_shop_tutorial_active():
		return false
	if _embedded_shop_active and _mode == "level":
		if _step_index < 0 or _step_index >= _steps.size():
			return true
		var step: Dictionary = _steps[_step_index]
		if not _is_step_shop_guide(step):
			return true
		if bool(step.get("dialog_next", false)) or bool(step.get("force_click", false)):
			return true
		var wait_for: String = String(step.get("wait", ""))
		if wait_for != "":
			_check_step_completion()
			return true
		_go_next()
		return true
	if _step_index >= _steps.size() - 1:
		_finish_shop()
		return false
	_go_next()
	return true


func _set_scrim_blocks_input(blocks: bool) -> void:
	var filter := MOUSE_FILTER_STOP if blocks else MOUSE_FILTER_IGNORE
	if _full_scrim != null:
		_full_scrim.mouse_filter = filter
	for scrim in _scrims:
		(scrim as ColorRect).mouse_filter = filter


func _build_ui() -> void:
	_full_scrim = ColorRect.new()
	_full_scrim.color = SCRIM_COLOR
	_full_scrim.mouse_filter = MOUSE_FILTER_STOP
	add_child(_full_scrim)

	for i in range(4):
		var scrim := ColorRect.new()
		scrim.color = SCRIM_COLOR
		scrim.mouse_filter = MOUSE_FILTER_STOP
		add_child(scrim)
		_scrims.append(scrim)

	_highlight = Panel.new()
	_highlight.mouse_filter = MOUSE_FILTER_IGNORE
	_highlight.z_index = 3
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(1.0, 0.74, 0.24, 0.08)
	hsb.border_color = Color(1.0, 0.74, 0.24, 0.98)
	hsb.border_width_left = 2
	hsb.border_width_top = 2
	hsb.border_width_right = 2
	hsb.border_width_bottom = 2
	hsb.corner_radius_top_left = 5
	hsb.corner_radius_top_right = 5
	hsb.corner_radius_bottom_left = 5
	hsb.corner_radius_bottom_right = 5
	_highlight.add_theme_stylebox_override("panel", hsb)
	add_child(_highlight)

	_intro_panel = PanelContainer.new()
	_intro_panel.visible = false
	_intro_panel.mouse_filter = MOUSE_FILTER_STOP
	_intro_panel.z_index = 8
	_intro_panel.add_theme_stylebox_override("panel", _intro_style())
	add_child(_intro_panel)

	var intro_margin := MarginContainer.new()
	intro_margin.add_theme_constant_override("margin_left", 18)
	intro_margin.add_theme_constant_override("margin_top", 16)
	intro_margin.add_theme_constant_override("margin_right", 18)
	intro_margin.add_theme_constant_override("margin_bottom", 16)
	_intro_panel.add_child(intro_margin)

	var intro_root := HBoxContainer.new()
	intro_root.add_theme_constant_override("separation", 18)
	intro_margin.add_child(intro_root)

	var intro_left := VBoxContainer.new()
	intro_left.custom_minimum_size = Vector2(210.0, 0.0)
	intro_left.add_theme_constant_override("separation", 8)
	intro_root.add_child(intro_left)

	var intro_portrait := TextureRect.new()
	intro_portrait.custom_minimum_size = Vector2(210.0, 280.0)
	intro_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	intro_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	intro_portrait.texture = _load_avatar_texture()
	intro_left.add_child(intro_portrait)

	var intro_name := Label.new()
	intro_name.text = "宝叔"
	intro_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_name.add_theme_font_size_override("font_size", 22)
	intro_name.add_theme_color_override("font_color", UF.COL_GOLD)
	intro_left.add_child(intro_name)

	var intro_text_box := VBoxContainer.new()
	intro_text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro_text_box.add_theme_constant_override("separation", 14)
	intro_root.add_child(intro_text_box)

	var intro_title := Label.new()
	intro_title.text = "人物介绍"
	intro_title.add_theme_font_size_override("font_size", 28)
	intro_title.add_theme_color_override("font_color", UF.COL_GOLD)
	intro_text_box.add_child(intro_title)

	var intro_body := Label.new()
	intro_body.text = "资深操盘手，擅长制造利好、点燃情绪、收割韭菜。\n\n业内人称「宝老师」，散户一般叫他：「狗庄」。\n\n现在，他是你的组长。"
	intro_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	intro_body.add_theme_font_size_override("font_size", 21)
	intro_body.add_theme_color_override("font_color", UF.COL_TEXT)
	intro_text_box.add_child(intro_body)

	_intro_button = UF.button("知道了", UF.COL_HIGHLIGHT, 20)
	_intro_button.custom_minimum_size = Vector2(220.0, 48.0)
	_intro_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_intro_button.pressed.connect(_on_next_pressed)
	intro_text_box.add_child(_intro_button)

	_dialog = PanelContainer.new()
	_dialog.mouse_filter = MOUSE_FILTER_STOP
	_dialog.z_index = 5
	_dialog.add_theme_stylebox_override("panel", _box_style(UF.COL_GOLD, 14.0))
	add_child(_dialog)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_dialog.add_child(row)

	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = Vector2(76.0, 76.0)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := _load_avatar_texture()
	if tex != null:
		_avatar.texture = tex
	row.add_child(_avatar)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 5)
	row.add_child(text_box)

	_name_label = Label.new()
	_name_label.text = "宝叔"
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", UF.COL_GOLD)
	text_box.add_child(_name_label)

	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialog_text.add_theme_font_size_override("font_size", 14)
	_dialog_text.add_theme_color_override("font_color", UF.COL_TEXT)
	text_box.add_child(_dialog_text)

	_next_button = UF.button("下一步", UF.COL_GOLD, 13)
	_next_button.custom_minimum_size = Vector2(96.0, 30.0)
	_next_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_next_button.pressed.connect(_on_next_pressed)
	text_box.add_child(_next_button)

	_player_dialog = PanelContainer.new()
	_player_dialog.visible = false
	_player_dialog.mouse_filter = MOUSE_FILTER_STOP
	_player_dialog.z_index = 5
	_player_dialog.add_theme_stylebox_override("panel", _box_style(UF.COL_BLUE, 12.0))
	add_child(_player_dialog)

	var player_box := VBoxContainer.new()
	player_box.add_theme_constant_override("separation", 4)
	_player_dialog.add_child(player_box)

	var player_name := Label.new()
	player_name.text = "你"
	player_name.add_theme_font_size_override("font_size", 13)
	player_name.add_theme_color_override("font_color", UF.COL_BLUE)
	player_box.add_child(player_name)

	_player_dialog_text = Label.new()
	_player_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_player_dialog_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_dialog_text.add_theme_font_size_override("font_size", 13)
	_player_dialog_text.add_theme_color_override("font_color", UF.COL_TEXT)
	player_box.add_child(_player_dialog_text)

	_prompt = PanelContainer.new()
	_prompt.mouse_filter = MOUSE_FILTER_IGNORE
	_prompt.z_index = 6
	_prompt.add_theme_stylebox_override("panel", _box_style(UF.COL_HIGHLIGHT, 10.0))
	add_child(_prompt)

	_prompt_text = Label.new()
	_prompt_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_text.add_theme_font_size_override("font_size", 13)
	_prompt_text.add_theme_color_override("font_color", UF.COL_TEXT)
	_prompt.add_child(_prompt_text)

	_arrow = TutorialArrow.new()
	_arrow.mouse_filter = MOUSE_FILTER_IGNORE
	_arrow.z_index = 6
	_arrow.custom_minimum_size = Vector2(18.0, 14.0)
	_arrow.size = Vector2(18.0, 14.0)
	add_child(_arrow)

	# 点击空白前进: 把 scrim / 对话框 / intro 面板的 gui_input 全部连到统一 handler
	_full_scrim.gui_input.connect(_on_overlay_input)
	for scrim in _scrims:
		(scrim as ColorRect).gui_input.connect(_on_overlay_input)
	_dialog.gui_input.connect(_on_overlay_input)
	_player_dialog.gui_input.connect(_on_overlay_input)
	_intro_panel.gui_input.connect(_on_overlay_input)


func _box_style(border: Color, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.border_color = Color(border.r, border.g, border.b, 0.74)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = margin
	sb.content_margin_top = margin * 0.72
	sb.content_margin_right = margin
	sb.content_margin_bottom = margin * 0.72
	return sb


func _intro_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.02, 0.95)
	sb.border_color = Color(UF.COL_GOLD.r, UF.COL_GOLD.g, UF.COL_GOLD.b, 0.95)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(UF.COL_GOLD.r, UF.COL_GOLD.g, UF.COL_GOLD.b, 0.28)
	sb.shadow_size = 8
	return sb


func _load_avatar_texture() -> Texture2D:
	if not ResourceLoader.exists(AVATAR_PATH, "Texture2D"):
		push_warning("Tutorial avatar is waiting for Godot import: %s" % AVATAR_PATH)
		return null
	return load(AVATAR_PATH) as Texture2D


func _build_steps() -> void:
	_steps = [
		{
			"intro": true,
			"button": "知道了",
		},
		{
			"dialog": "来得正好，我是你的组长，叫我宝叔就行。",
			"button": "继续",
		},
		{
			"dialog": "下面开始你第一天的交易，我来教你怎么在市场里赚钱。",
			"button": "开始交易",
		},
		{
			"target_path": "PlayerPanel/VBox/LblCash",
			"dialog": "这是你的本金，也是你的命根子。牌打得再漂亮，现金断了就没法继续。",
			"prompt": "资金：当前可直接使用的现金。",
		},
		{
			"target_path": "DataPanel/VBox/StatsGrid/CellShares",
			"dialog": "这是你手里的筹码。手里没货，后面涨得再凶也跟你没关系。",
			"prompt": "筹码：你当前持有的股票数量。",
		},
		{
			"target_paths": ["TopBar/MidBar/HBox/IconEmotion", "TopBar/MidBar/HBox/LblEmotionTitle", "TopBar/MidBar/HBox/EmotionBarSlot", "TopBar/MidBar/HBox/LblEmotionState"],
			"dialog": "这根是市场情绪。情绪越火热，买盘和利好越容易把股价往上推；情绪越冷淡，卖压和坏消息造成的下跌也会更重。",
			"prompt": "市场情绪：火热会放大上涨，冷淡会放大下跌。",
		},
		{
			"dialog": "知道怎么靠股票赚钱吗？",
			"player_dialog": "靠技术分析？",
		},
		{
			"dialog": "不，靠别人犯傻。\n记住，股票本身不值钱。\n有人愿意更贵买，它才值钱。",
		},
		{
			"target_effect": "buy_basic",
			"wait": "buy",
			"dialog": "先买点货，手里没东西，涨了也跟你没关系。",
			"prompt": "点击这张【买入】，用现金买入筹码。",
			"button": "",
		},
		{
			"dialog": "接下来教你市场最核心的东西：情绪。",
			"player_dialog": "基本面呢？",
		},
		{
			"dialog": "那是给套牢的人看的。",
		},
		{
			"target_effect": "hype_basic",
			"wait": "hype",
			"dialog": "光自己买还不够，得让别人也想买。试试造势。",
			"prompt": "打出【大V吹票】，拉升市场热度。",
			"button": "",
		},
		{
			"target_paths": ["TopBar/MidBar/HBox/EmotionBarSlot", "TopBar/MidBar/HBox/LblEmotionState"],
			"dialog": "热度起来了，股价就会自己往上跑，这叫借势。",
			"prompt": "热度上涨后，后续买盘会更有力量。",
		},
		{
			"speaker": "player",
			"dialog": "等等。\n拉升和买入是分开的？",
		},
		{
			"dialog": "废话。\n买入是拿筹码，拉升是做气氛，机构有的是手段。",
		},
		{
			"target_effect": "inflow_capital",
			"wait": "price_up",
			"dialog": "现在给市场一点真金白银的刺激。",
			"prompt": "打出【游资进场】，让股价快速冲一段。",
			"button": "",
		},
		{
			"target_path": "ChartPanel",
			"dialog": "看到没有？情绪铺好了，资金一进场，价格就会被推得更猛。",
			"prompt": "分时图会记录这次拉升。",
		},
		{
			"target_effect": "sell_basic",
			"wait": "sell",
			"dialog": "现在涨得不错了，但账上的都是虚的，卖掉才是你的钱。来，分批出，别一次砸。",
			"prompt": "股价已在高位，打出【卖出】，把筹码换回现金。",
			"button": "",
		},
		{
			"dialog": "利好最大的作用，是方便出货。",
		},
		{
			"dialog": "我们做游资短线，使用的是杠杆资金，重要的是当天进、当天出。如果当天你出不掉货，我们只能八折贱卖。",
			"player_dialog": "为啥啊，我辛辛苦苦拉的股价。",
		},
		{
			"dialog": "速度出货，是交易的法则。",
		},
		{
			"action": "enter_shop",
			"shop_guide": true,
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/买卡",
			"shop_tab": 0,
			"dialog": "这里是盘后市场，在这里可以补充市场手段。",
			"prompt": "购买：花现金把新牌加入卡组。",
			"button": "继续",
		},
		{
			"shop_guide": true,
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/升级",
			"shop_tab": 1,
			"dialog": "升级你的卡牌，可以让关键手段更稳定、更有力。",
			"prompt": "升级：强化常用牌，让核心打法更可靠。",
			"button": "继续",
		},
		{
			"shop_guide": true,
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/删卡",
			"shop_tab": 2,
			"dialog": "如果卡组里有不喜欢的牌，可以删掉。牌太多了，关键牌反而不容易来。",
			"prompt": "删卡：移除拖节奏的牌，压缩卡组。",
			"button": "继续",
		},
		{
			"shop_guide": true,
			"dialog_next": true,
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/天赋",
			"shop_tab": 3,
			"dialog": "虽然市场崇尚交易，但是我们也有内部福利。",
			"button": "下一步",
		},
		{
			"shop_guide": true,
			"dialog_next": true,
			"dialog": "这里是天赋界面。先领免费的【连携效应】，以后连续买卖会更顺。",
			"prompt": "天赋：获得长期生效的规则加成。",
			"button": "下一步",
		},
		{
			"shop_guide": true,
			"force_click": true,
			"target_talent": "cascade_combo",
			"ensure_talent": "cascade_combo",
			"shop_tab": 3,
			"wait": "talent",
			"dialog": "选择免费的【连携效应】。",
			"prompt": "点击【连携效应】，把它加入你的天赋。",
			"button": "",
		},
		{
			"shop_guide": true,
			"dialog_next": true,
			"dialog": "这能让你的买卖节奏更加顺畅。",
			"button": "结束商店",
		},
		{
			"action": "leave_shop_for_event",
			"dialog": "盘后准备完了，第二天市场不会等你。",
			"button": "继续",
		},
		{
			"action": "trigger_event",
			"event_id": "black_swan",
			"target_path": "TopBar/LeftBar/HBox/BtnEvent",
			"dialog": "俗话说，天有不测风云。",
			"prompt": "利空事件会直接改变市场环境。",
			"button": "继续",
		},
		{
			"dialog": "所以今天开盘大跌，一碗大面，昨天跑了吧？",
			"player_dialog": "所以呢？",
		},
		{
			"speaker": "player",
			"dialog": "。。。。",
		},
		{
			"dialog": "今天的思路是先打压股价，低位买入，然后拉高出货，记得尾盘跑路。",
			"button": "继续交易",
			"finish": true,
		},
	]


func _build_shop_steps() -> void:
	_steps = [
		{
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/买卡",
			"shop_tab": 0,
			"dialog": "这里可以买新牌。优先挑能补足短板、提高收益的牌，让你的卡组有更多打法。",
			"prompt": "购买：花现金把新牌加入卡组。",
		},
		{
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/升级",
			"shop_tab": 1,
			"dialog": "这里可以升级已有卡牌。少数关键牌变强，往往比单纯堆数量更稳定。",
			"prompt": "升级：强化常用牌，让核心策略更可靠。",
		},
		{
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/删卡",
			"shop_tab": 2,
			"dialog": "这里可以删掉不想要的牌。卡组太厚会稀释关键牌，适当精简，才能更容易抽到真正想打的牌。",
			"prompt": "删卡：移除拖节奏的牌，压缩卡组。",
		},
	]


func _apply_step_action(step: Dictionary) -> void:
	var action: String = String(step.get("action", ""))
	match action:
		"enter_shop":
			_embedded_shop_active = true
			if Game.has_method("tutorial_enter_shop"):
				Game.call("tutorial_enter_shop")
			var shop := _shop_overlay()
			if shop != null and shop.has_method("set_tutorial_button_override"):
				shop.call("set_tutorial_button_override", "继续")
		"leave_shop_for_event":
			_embedded_shop_active = false
			var shop := _shop_overlay()
			if shop != null and shop.has_method("clear_tutorial_button_override"):
				shop.call("clear_tutorial_button_override")
			if Game.has_method("tutorial_leave_shop_for_event"):
				Game.call("tutorial_leave_shop_for_event")
		"trigger_event":
			var event_id: String = String(step.get("event_id", "black_swan"))
			if Game.has_method("tutorial_trigger_event"):
				Game.call("tutorial_trigger_event", event_id)


func _show_intro_step(step: Dictionary) -> void:
	_full_scrim.color = SCRIM_COLOR
	_full_scrim.visible = true
	_full_scrim.mouse_filter = MOUSE_FILTER_STOP
	for scrim in _scrims:
		(scrim as ColorRect).visible = false
	_highlight.visible = false
	_dialog.visible = false
	_player_dialog.visible = false
	_prompt.visible = false
	_arrow.visible = false
	_clear_card_highlight()
	_intro_panel.visible = true
	_intro_button.text = String(step.get("button", "知道了"))
	_intro_button.visible = false
	call_deferred("_update_layout")


func _is_step_shop_guide(step: Dictionary) -> bool:
	return _mode == "shop" or bool(step.get("shop_guide", false))


func _enter_step() -> void:
	if _step_index < 0 or _step_index >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_step_index]
	_apply_step_action(step)
	visible = true
	_dialog.visible = true
	_set_scrim_blocks_input(true)
	if step.has("shop_tab"):
		_select_shop_tab(int(step["shop_tab"]))
	if bool(step.get("intro", false)):
		_show_intro_step(step)
		return
	_intro_panel.visible = false
	var effect_id: String = String(step.get("target_effect", ""))
	if effect_id != "":
		Game.tutorial_ensure_card_in_hand(effect_id)
		Game.tutorial_set_min_action_points(1)
	var talent_id: String = String(step.get("ensure_talent", ""))
	if talent_id != "" and Game.has_method("tutorial_ensure_talent_offer"):
		Game.call("tutorial_ensure_talent_offer", talent_id)
	_wait_shares = Game.shares
	_wait_bull = Game.bull
	_wait_cash = Game.cash
	_wait_price = Game.price

	var speaker: String = String(step.get("speaker", "baoshu"))
	var is_player_speaker: bool = speaker == "player"
	_dialog.add_theme_stylebox_override("panel", _box_style(UF.COL_BLUE if is_player_speaker else UF.COL_GOLD, 14.0))
	_name_label.text = "你" if is_player_speaker else "宝叔"
	_name_label.add_theme_color_override("font_color", UF.COL_BLUE if is_player_speaker else UF.COL_GOLD)
	_avatar.visible = not is_player_speaker
	_dialog.visible = true
	_dialog_text.text = String(step.get("dialog", ""))
	var player_text: String = String(step.get("player_dialog", ""))
	_player_dialog.visible = player_text != ""
	_player_dialog_text.text = player_text
	_prompt_text.text = String(step.get("prompt", ""))
	var button_text: String = String(step.get("button", "下一步"))
	if _is_step_shop_guide(step):
		_next_button.visible = false
		_next_button.text = button_text
		_prompt.visible = false
		_arrow.visible = false
		_clear_card_highlight()
		_update_shop_button_text()
	else:
		_next_button.visible = false
		_next_button.text = button_text
		_prompt.visible = String(step.get("prompt", "")) != ""
		_arrow.visible = _prompt.visible
	call_deferred("_update_layout")
	if _mode != "shop":
		_restart_highlight_pulse()


func _on_overlay_input(event: InputEvent) -> void:
	if not _active:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_try_advance_by_click()


func _try_advance_by_click() -> void:
	if _step_index < 0 or _step_index >= _steps.size():
		return
	var step: Dictionary = _steps[_step_index]
	if String(step.get("wait", "")) != "":
		return
	if bool(step.get("force_click", false)):
		return
	_on_next_pressed()


func _on_next_pressed() -> void:
	if not _active:
		return
	var step: Dictionary = _steps[_step_index]
	if bool(step.get("finish", false)):
		_finish()
	else:
		_go_next()


func _go_next() -> void:
	_step_index += 1
	_enter_step()


func _finish() -> void:
	if _mode == "shop":
		_finish_shop()
		return
	_active = false
	visible = false
	_clear_card_highlight()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var shop := _shop_overlay()
	if shop != null and shop.has_method("clear_tutorial_button_override"):
		shop.call("clear_tutorial_button_override")
	if Game.has_method("tutorial_finish_and_continue_level"):
		Game.call("tutorial_finish_and_continue_level")
	else:
		Game.finish_tutorial()


func _finish_shop() -> void:
	_active = false
	visible = false
	_clear_card_highlight()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var shop := _shop_overlay()
	if shop != null and shop.has_method("clear_tutorial_button_override"):
		shop.call("clear_tutorial_button_override")
	Game.finish_shop_tutorial()


func close_shop_tutorial() -> void:
	if is_shop_tutorial_active():
		_finish_shop()


func _close_shop_dialog() -> void:
	if not is_shop_tutorial_active():
		return
	visible = false
	_dialog.visible = false
	_player_dialog.visible = false
	_full_scrim.visible = false
	for scrim in _scrims:
		(scrim as ColorRect).visible = false
	_highlight.visible = false
	_prompt.visible = false
	_arrow.visible = false
	_clear_card_highlight()
	_set_scrim_blocks_input(false)


func _select_shop_tab(tab_index: int) -> void:
	var tabs: TabContainer = null
	if _main != null:
		tabs = _main.get_node_or_null("ShopOverlay/ShopPanel/Margin/RootVBox/Tabs") as TabContainer
	if tabs == null:
		return
	tabs.current_tab = clampi(tab_index, 0, max(0, tabs.get_tab_count() - 1))


func _update_shop_button_text() -> void:
	var shop := _shop_overlay()
	if shop == null or not shop.has_method("set_tutorial_button_override"):
		return
	var text := "继续"
	if _step_index >= 0 and _step_index < _steps.size():
		var step: Dictionary = _steps[_step_index]
		var step_button: String = String(step.get("button", ""))
		if step_button != "":
			text = step_button
	if _step_index >= _steps.size() - 1:
		text = "关闭商店，进入下一天 →"
	shop.call("set_tutorial_button_override", text)


func _shop_overlay() -> Control:
	if _main == null:
		return null
	return _main.get_node_or_null("ShopOverlay") as Control


func _on_game_changed() -> void:
	if not _active:
		return
	if _check_step_completion():
		return
	if not visible:
		return
	call_deferred("_update_layout")


func _check_step_completion() -> bool:
	if _step_index < 0 or _step_index >= _steps.size():
		return false
	var step: Dictionary = _steps[_step_index]
	var wait_for: String = String(step.get("wait", ""))
	var done: bool = false
	match wait_for:
		"buy":
			done = Game.shares > _wait_shares
		"hype":
			done = Game.bull > _wait_bull
		"price_up":
			done = Game.price > _wait_price + 0.001
		"sell":
			done = Game.shares < _wait_shares and Game.cash > _wait_cash
		"talent":
			done = Game.has_talent("cascade_combo")
		_:
			done = false
	if done:
		_go_next()
	return done


func _update_layout() -> void:
	if not _active or not visible:
		return
	var view := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		size = view
	if _intro_panel != null and _intro_panel.visible:
		_layout_intro()
		return
	if _mode == "shop":
		_layout_shop_dialog()
		return
	if _step_index >= 0 and _step_index < _steps.size() and _is_step_shop_guide(_steps[_step_index]):
		_layout_embedded_shop_guide()
		return
	_full_scrim.position = Vector2.ZERO
	_full_scrim.size = size

	var target_ctrl := _current_target_control()
	var target_rect := _current_target_rect(target_ctrl)
	if target_rect.size.x <= 0.0 or target_rect.size.y <= 0.0:
		_layout_scrim_without_target()
		var dialog_rect := _position_dialog(Rect2())
		_position_player_dialog(dialog_rect)
		_prompt.visible = false
		_arrow.visible = false
		_clear_card_highlight()
		return

	target_rect = target_rect.grow(HIGHLIGHT_PAD)
	target_rect.position.x = clampf(target_rect.position.x, 0.0, max(0.0, size.x - 1.0))
	target_rect.position.y = clampf(target_rect.position.y, 0.0, max(0.0, size.y - 1.0))
	target_rect.size.x = min(target_rect.size.x, max(1.0, size.x - target_rect.position.x))
	target_rect.size.y = min(target_rect.size.y, max(1.0, size.y - target_rect.position.y))

	var should_show_prompt: bool = String((_steps[_step_index] as Dictionary).get("prompt", "")) != ""
	_prompt.visible = should_show_prompt
	_arrow.visible = should_show_prompt
	_layout_scrim_around(target_rect)
	if _is_card_step() and target_ctrl != null:
		_highlight.visible = false
		_set_card_highlight(target_ctrl)
	else:
		_clear_card_highlight()
		_highlight.visible = true
		_highlight.position = target_rect.position
		_highlight.size = target_rect.size
	var prompt_rect := _position_prompt(target_rect)
	var dialog_rect := _position_dialog(target_rect, prompt_rect)
	_position_player_dialog(dialog_rect)


func _layout_shop_dialog() -> void:
	_full_scrim.color = Color(0.0, 0.0, 0.0, 0.0)
	_full_scrim.position = Vector2.ZERO
	_full_scrim.size = size
	_full_scrim.visible = true
	_full_scrim.mouse_filter = MOUSE_FILTER_STOP
	for scrim in _scrims:
		(scrim as ColorRect).visible = false
	_highlight.visible = false
	_prompt.visible = false
	_arrow.visible = false
	_player_dialog.visible = false
	_intro_panel.visible = false
	_clear_card_highlight()
	_dialog.visible = true
	var w: float = min(620.0, max(360.0, size.x - 72.0))
	_dialog.size = Vector2(w, SHOP_DIALOG_H)
	_dialog.position = Vector2(
		(size.x - w) * 0.5,
		clampf(size.y * 0.58 - SHOP_DIALOG_H * 0.5, 56.0, max(56.0, size.y - SHOP_DIALOG_H - 56.0))
	)


func _layout_embedded_shop_guide() -> void:
	var step: Dictionary = {}
	if _step_index >= 0 and _step_index < _steps.size():
		step = _steps[_step_index]
	var force_click: bool = bool(step.get("force_click", false))
	var dialog_next: bool = bool(step.get("dialog_next", false))

	_full_scrim.color = Color(0.0, 0.0, 0.0, 0.08)
	_full_scrim.position = Vector2.ZERO
	_full_scrim.size = size
	_full_scrim.mouse_filter = MOUSE_FILTER_STOP
	for scrim in _scrims:
		(scrim as ColorRect).visible = false
	_prompt.visible = false
	_arrow.visible = false
	_player_dialog.visible = false
	_intro_panel.visible = false
	_dialog.visible = true
	_next_button.visible = false
	var button_text: String = String(step.get("button", "知道了"))
	_next_button.text = button_text

	var target_ctrl := _current_target_control()
	var target_rect := _current_target_rect(target_ctrl)
	if target_rect.size.x > 0.0 and target_rect.size.y > 0.0:
		target_rect = target_rect.grow(HIGHLIGHT_PAD)
		target_rect.position.x = clampf(target_rect.position.x, 0.0, max(0.0, size.x - 1.0))
		target_rect.position.y = clampf(target_rect.position.y, 0.0, max(0.0, size.y - 1.0))
		target_rect.size.x = min(target_rect.size.x, max(1.0, size.x - target_rect.position.x))
		target_rect.size.y = min(target_rect.size.y, max(1.0, size.y - target_rect.position.y))
		if force_click:
			_layout_scrim_around(target_rect)
		else:
			_full_scrim.visible = true
			for scrim in _scrims:
				(scrim as ColorRect).visible = false
		_clear_card_highlight()
		_highlight.visible = true
		_highlight.position = target_rect.position
		_highlight.size = target_rect.size
	else:
		_full_scrim.visible = true
		_clear_card_highlight()
		_highlight.visible = false

	var w: float = min(620.0, max(360.0, size.x - 72.0))
	var h: float = SHOP_DIALOG_H
	_dialog.size = Vector2(w, h)
	if force_click and target_rect.size.x > 0.0 and target_rect.size.y > 0.0:
		var x: float = clampf(target_rect.get_center().x - w * 0.5, 36.0, max(36.0, size.x - w - 36.0))
		var below_y: float = target_rect.end.y + 16.0
		var above_y: float = target_rect.position.y - h - 16.0
		var y: float = below_y if below_y + h <= size.y - 48.0 else above_y
		y = clampf(y, 48.0, max(48.0, size.y - h - 48.0))
		_dialog.position = Vector2(x, y)
	else:
		_dialog.position = Vector2(
			(size.x - w) * 0.5,
			clampf(size.y * 0.60 - h * 0.5, 56.0, max(56.0, size.y - h - 56.0))
		)


func _layout_intro() -> void:
	_full_scrim.color = SCRIM_COLOR
	_full_scrim.position = Vector2.ZERO
	_full_scrim.size = size
	_full_scrim.visible = true
	for scrim in _scrims:
		(scrim as ColorRect).visible = false
	_highlight.visible = false
	_prompt.visible = false
	_arrow.visible = false
	_dialog.visible = false
	_player_dialog.visible = false
	var w: float = min(780.0, max(360.0, size.x - 88.0))
	var h: float = min(430.0, max(320.0, size.y - 76.0))
	_intro_panel.size = Vector2(w, h)
	_intro_panel.position = Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)


func _layout_scrim_without_target() -> void:
	_full_scrim.color = SCRIM_COLOR
	_full_scrim.visible = true
	for scrim in _scrims:
		(scrim as ColorRect).visible = false
	_highlight.visible = false


func _layout_scrim_around(rect: Rect2) -> void:
	_full_scrim.visible = false
	var top := _scrims[0] as ColorRect
	var bottom := _scrims[1] as ColorRect
	var left := _scrims[2] as ColorRect
	var right := _scrims[3] as ColorRect
	top.visible = true
	top.position = Vector2.ZERO
	top.size = Vector2(size.x, rect.position.y)
	bottom.visible = true
	bottom.position = Vector2(0.0, rect.end.y)
	bottom.size = Vector2(size.x, max(0.0, size.y - rect.end.y))
	left.visible = true
	left.position = Vector2(0.0, rect.position.y)
	left.size = Vector2(rect.position.x, rect.size.y)
	right.visible = true
	right.position = Vector2(rect.end.x, rect.position.y)
	right.size = Vector2(max(0.0, size.x - rect.end.x), rect.size.y)


func _position_dialog(target_rect: Rect2, prompt_rect: Rect2 = Rect2()) -> Rect2:
	var w: float = min(580.0, max(320.0, size.x - 32.0))
	_dialog.size = Vector2(w, DIALOG_H)
	var dialog_size := Vector2(w, DIALOG_H)
	var candidates: Array = []
	var center_x: float = (size.x - dialog_size.x) * 0.5
	var near_prompt_x: float = center_x
	if prompt_rect.size.x > 0.0:
		near_prompt_x = prompt_rect.get_center().x - dialog_size.x * 0.5
	for raw_x in [center_x, near_prompt_x]:
		var x: float = clampf(float(raw_x), 18.0, max(18.0, size.x - dialog_size.x - 18.0))
		if prompt_rect.size.y > 0.0:
			candidates.append(Rect2(Vector2(x, prompt_rect.end.y + 14.0), dialog_size))
			candidates.append(Rect2(Vector2(x, prompt_rect.position.y - dialog_size.y - 14.0), dialog_size))
		else:
			candidates.append(Rect2(Vector2(x, size.y * 0.52 - dialog_size.y * 0.5), dialog_size))
	if candidates.is_empty():
		candidates.append(Rect2(Vector2(center_x, size.y * 0.52 - dialog_size.y * 0.5), dialog_size))

	var best: Rect2 = candidates[0]
	var best_score: float = INF
	for c in candidates:
		var r: Rect2 = c
		r.position.y = clampf(r.position.y, 16.0, max(16.0, size.y - r.size.y - 16.0))
		var score: float = 0.0
		if target_rect.size.x > 0.0:
			score += _overlap_area(r, target_rect) * 14.0
		if prompt_rect.size.x > 0.0:
			score += _overlap_area(r, prompt_rect) * 20.0
			score += r.get_center().distance_to(prompt_rect.get_center()) * 0.22
		score += abs(r.get_center().x - size.x * 0.5) * 0.36
		score += abs(r.get_center().y - size.y * 0.52) * 0.08
		if score < best_score:
			best_score = score
			best = r
	_dialog.position = best.position
	return best


func _position_player_dialog(dialog_rect: Rect2) -> void:
	if _player_dialog == null or not _player_dialog.visible:
		return
	var w: float = min(500.0, max(280.0, dialog_rect.size.x - 36.0))
	_player_dialog.size = Vector2(w, PLAYER_DIALOG_H)
	var x: float = clampf(dialog_rect.position.x + dialog_rect.size.x - w - 22.0, 16.0, max(16.0, size.x - w - 16.0))
	var y: float = dialog_rect.end.y + 8.0
	if y + PLAYER_DIALOG_H > size.y - 16.0:
		y = dialog_rect.position.y - PLAYER_DIALOG_H - 8.0
	y = clampf(y, 16.0, max(16.0, size.y - PLAYER_DIALOG_H - 16.0))
	_player_dialog.position = Vector2(x, y)


func _position_prompt(target_rect: Rect2) -> Rect2:
	if not _prompt.visible:
		return Rect2()
	var w: float = min(320.0, max(220.0, size.x - 32.0))
	_prompt.size = Vector2(w, PROMPT_H)
	var picked := _pick_prompt_rect(target_rect, Vector2(w, PROMPT_H))
	_prompt.position = picked["rect"].position
	_arrow.points_down = bool(picked["above"])
	_arrow.size = Vector2(18.0, 14.0)
	var prompt_rect: Rect2 = picked["rect"]
	var arrow_x: float = clampf(target_rect.get_center().x - _arrow.size.x * 0.5, prompt_rect.position.x + 8.0, prompt_rect.end.x - _arrow.size.x - 8.0)
	var arrow_y: float = prompt_rect.end.y - 1.0 if _arrow.points_down else prompt_rect.position.y - _arrow.size.y + 1.0
	_arrow.position = Vector2(arrow_x, arrow_y)
	_arrow.queue_redraw()
	return prompt_rect


func _pick_prompt_rect(target_rect: Rect2, prompt_size: Vector2) -> Dictionary:
	var x: float = clampf(target_rect.get_center().x - prompt_size.x * 0.5, 14.0, max(14.0, size.x - prompt_size.x - 14.0))
	var above_rect := Rect2(Vector2(x, target_rect.position.y - prompt_size.y - 18.0), prompt_size)
	var below_rect := Rect2(Vector2(x, target_rect.end.y + 18.0), prompt_size)
	above_rect.position.y = clampf(above_rect.position.y, 12.0, max(12.0, size.y - prompt_size.y - 12.0))
	below_rect.position.y = clampf(below_rect.position.y, 12.0, max(12.0, size.y - prompt_size.y - 12.0))
	var prefer_above: bool = target_rect.position.y > size.y * 0.42
	var candidates: Array = [
		{"rect": above_rect, "above": true},
		{"rect": below_rect, "above": false},
	]
	if not prefer_above:
		candidates.reverse()
	var best: Dictionary = candidates[0]
	var best_score: float = INF
	for candidate in candidates:
		var r: Rect2 = candidate["rect"]
		var score: float = _overlap_area(r, target_rect) * 12.0
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _overlap_area(a: Rect2, b: Rect2) -> float:
	var inter := a.intersection(b)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return 0.0
	return inter.size.x * inter.size.y


func _current_target_control() -> Control:
	if _step_index < 0 or _step_index >= _steps.size() or _main == null:
		return null
	var step: Dictionary = _steps[_step_index]
	var effect_id: String = String(step.get("target_effect", ""))
	if effect_id != "":
		return _find_card_by_effect(effect_id)
	var talent_id: String = String(step.get("target_talent", ""))
	if talent_id != "":
		return _find_control_by_meta(_shop_overlay(), "talent_id", talent_id)
	var path: String = String(step.get("target_path", ""))
	if path != "":
		return _main.get_node_or_null(path) as Control
	return null


func _current_target_rect(target_ctrl: Control) -> Rect2:
	if _step_index < 0 or _step_index >= _steps.size() or _main == null:
		return Rect2()
	var step: Dictionary = _steps[_step_index]
	if step.has("target_paths"):
		return _rect_for_paths(step["target_paths"])
	if target_ctrl == null or not is_instance_valid(target_ctrl):
		return Rect2()
	if not target_ctrl.is_visible_in_tree():
		return Rect2()
	return _control_global_rect(target_ctrl)


func _rect_for_paths(paths: Array) -> Rect2:
	var out := Rect2()
	var found: bool = false
	for path in paths:
		var ctrl := _main.get_node_or_null(String(path)) as Control
		if ctrl == null or not is_instance_valid(ctrl):
			continue
		if not ctrl.is_visible_in_tree():
			continue
		var r := _control_global_rect(ctrl)
		if not found:
			out = r
			found = true
		else:
			out = out.merge(r)
	return out if found else Rect2()


func _control_global_rect(ctrl: Control) -> Rect2:
	var xf := ctrl.get_global_transform()
	var corners := [
		xf * Vector2.ZERO,
		xf * Vector2(ctrl.size.x, 0.0),
		xf * Vector2(0.0, ctrl.size.y),
		xf * ctrl.size,
	]
	var min_p: Vector2 = corners[0]
	var max_p: Vector2 = corners[0]
	for p in corners:
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
	return Rect2(min_p, max_p - min_p)


func _is_card_step() -> bool:
	if _step_index < 0 or _step_index >= _steps.size():
		return false
	return String((_steps[_step_index] as Dictionary).get("target_effect", "")) != ""


func _set_card_highlight(card: Control) -> void:
	if _highlighted_card == card:
		return
	_clear_card_highlight()
	_highlighted_card = card
	if _highlighted_card.has_method("set_tutorial_highlight"):
		_highlighted_card.call("set_tutorial_highlight", true)


func _clear_card_highlight() -> void:
	if _highlighted_card != null and is_instance_valid(_highlighted_card) and _highlighted_card.has_method("set_tutorial_highlight"):
		_highlighted_card.call("set_tutorial_highlight", false)
	_highlighted_card = null


func _find_card_by_effect(effect_id: String) -> Control:
	if _main == null:
		return null
	var fan := _main.get_node_or_null("HandPanel/FanHandContainer")
	if fan == null:
		return null
	for child in fan.get_children():
		var ctrl := child as Control
		if ctrl != null and String(ctrl.get_meta("effect_id", "")) == effect_id:
			return ctrl
	return null


func _find_control_by_meta(root: Node, key: String, value: String) -> Control:
	if root == null:
		return null
	var ctrl := root as Control
	if ctrl != null and String(ctrl.get_meta(key, "")) == value:
		return ctrl
	for child in root.get_children():
		var found := _find_control_by_meta(child, key, value)
		if found != null:
			return found
	return null


func _restart_highlight_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_highlight.modulate = Color(1, 1, 1, 1)
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(_highlight, "modulate:a", 0.42, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_highlight, "modulate:a", 1.0, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
