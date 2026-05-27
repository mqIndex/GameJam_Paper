extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

const SCRIM_COLOR: Color = Color(0.0, 0.0, 0.0, 0.58)
const PANEL_COLOR: Color = Color(0.04, 0.07, 0.13, 0.86)
const HIGHLIGHT_PAD: float = 8.0
const DIALOG_H: float = 126.0
const PLAYER_DIALOG_H: float = 70.0
const SHOP_DIALOG_H: float = 140.0
const PROMPT_H: float = 64.0
const ENTER_SCENE_TEXTURE: Texture2D = preload("res://assets/EnterSecen.png")
const BAOSHU_AVATAR_TEXTURE: Texture2D = preload("res://assets/baoshu_avatar_UpperHalf.png")
const INTRO_TYPEWRITER_CHARS_PER_SECOND: float = 18.0


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
var _intro_portrait: TextureRect = null
var _intro_name_label: Label = null
var _intro_title_label: Label = null
var _intro_body_label: Label = null
var _intro_button: Button = null
var _dialog: PanelContainer = null
var _avatar: TextureRect = null
var _name_label: Label = null
var _dialog_text: Label = null
var _player_dialog: PanelContainer = null
var _player_dialog_text: Label = null
var _prompt: PanelContainer = null
var _prompt_text: Label = null
var _arrow = null
var _next_button: Button = null
var _intro_text_tween: Tween = null
var _intro_typewriter_done: bool = true


func setup(main_node: Control) -> void:
	_main = main_node


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bind_ui()
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


func start_goal_intro() -> void:
	if _active:
		return
	_mode = "goal"
	_embedded_shop_active = false
	_build_goal_steps()
	if Game.has_method("begin_context_tutorial"):
		Game.call("begin_context_tutorial")
	_set_scrim_blocks_input(true)
	_active = true
	visible = true
	_step_index = -1
	_go_next()


func start_formal_intro() -> void:
	if _active:
		return
	_mode = "formal"
	_embedded_shop_active = false
	_build_formal_intro_steps()
	if Game.has_method("begin_context_tutorial"):
		Game.call("begin_context_tutorial")
	_set_scrim_blocks_input(true)
	_active = true
	visible = true
	_step_index = -1
	_go_next()


func start_opponent_intro() -> void:
	if _active:
		return
	_mode = "opponent"
	_embedded_shop_active = false
	_build_opponent_intro_steps()
	if Game.has_method("begin_context_tutorial"):
		Game.call("begin_context_tutorial")
	_set_scrim_blocks_input(true)
	_active = true
	visible = true
	_step_index = -1
	_go_next()


func start_opponent_reward_intro() -> void:
	if _active:
		return
	_mode = "opponent_reward"
	_embedded_shop_active = false
	_build_opponent_reward_steps()
	if Game.has_method("begin_context_tutorial"):
		Game.call("begin_context_tutorial")
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
		if bool(step.get("dialog_next", false)):
			_go_next()
			return true
		if bool(step.get("force_click", false)):
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


func _bind_ui() -> void:
	_full_scrim = $FullScrim
	_scrims = [$ScrimTop, $ScrimBottom, $ScrimLeft, $ScrimRight]
	_highlight = $Highlight
	_intro_panel = $IntroPanel
	_intro_portrait = $IntroPanel/Margin/Root/Left/Portrait
	_intro_name_label = $IntroPanel/Margin/Root/Left/LblIntroName
	_intro_title_label = $IntroPanel/Margin/Root/TextBox/LblIntroTitle
	_intro_body_label = $IntroPanel/Margin/Root/TextBox/LblIntroBody
	_intro_button = $IntroPanel/Margin/Root/TextBox/BtnIntro
	_dialog = $Dialog
	_avatar = $Dialog/Row/Avatar
	_name_label = $Dialog/Row/TextBox/LblName
	_dialog_text = $Dialog/Row/TextBox/LblDialog
	_next_button = $Dialog/Row/TextBox/BtnNext
	_player_dialog = $PlayerDialog
	_player_dialog_text = $PlayerDialog/VBox/LblPlayerDialog
	_prompt = $Prompt
	_prompt_text = $Prompt/LblPrompt
	_arrow = $Arrow

	_full_scrim.color = SCRIM_COLOR
	_dialog.add_theme_stylebox_override("panel", _box_style(UF.COL_GOLD, 14.0))
	_player_dialog.add_theme_stylebox_override("panel", _box_style(UF.COL_BLUE, 12.0))
	_prompt.add_theme_stylebox_override("panel", _box_style(UF.COL_HIGHLIGHT, 10.0))
	_style_button(_intro_button, UF.COL_HIGHLIGHT, 20)
	_style_button(_next_button, UF.COL_GOLD, 13)

	if not _intro_button.pressed.is_connected(_on_next_pressed):
		_intro_button.pressed.connect(_on_next_pressed)
	if not _next_button.pressed.is_connected(_on_next_pressed):
		_next_button.pressed.connect(_on_next_pressed)
	_connect_overlay_input()


func _connect_overlay_input() -> void:
	var input_nodes: Array = [_full_scrim, _dialog, _player_dialog, _intro_panel]
	for scrim in _scrims:
		input_nodes.append(scrim)
	for node in input_nodes:
		var ctrl := node as Control
		if ctrl == null:
			continue
		if not ctrl.gui_input.is_connected(_on_overlay_input):
			ctrl.gui_input.connect(_on_overlay_input)


func _style_button(button: Button, color: Color, font_size: int) -> void:
	if button == null:
		return
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", color)
	var normal := StyleBoxFlat.new()
	normal.bg_color = UF.COL_PANEL
	normal.border_color = color
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.corner_radius_top_left = 2
	normal.corner_radius_top_right = 2
	normal.corner_radius_bottom_left = 2
	normal.corner_radius_bottom_right = 2
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(color.r, color.g, color.b, 0.18)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(color.r, color.g, color.b, 0.32)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.border_color = UF.COL_AP_OFF
	button.add_theme_stylebox_override("disabled", disabled)


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


func _build_steps() -> void:
	_steps = [
		{
			"intro": true,
			"intro_texture": ENTER_SCENE_TEXTURE,
			"intro_name": "",
			"intro_title": "",
			"intro_body": "一个平凡无奇的交易日\n刚刚毕业的你加入了一家神秘的“短线席位”金融机构",
			"typewriter": true,
			"button": "继续",
		},
		{
			"intro": true,
			"intro_texture": BAOSHU_AVATAR_TEXTURE,
			"intro_name": "宝叔",
			"intro_title": "人物介绍",
			"intro_body": "资深操盘手，擅长制造利好、点燃情绪、收割韭菜。\n\n业内人称「宝老师」，散户一般叫他：「狗庄」。\n\n现在，他是你的组长。",
			"typewriter": true,
			"button": "知道了",
		},
		{
			"dialog": "来得正好，我是你的组长，叫我宝叔就行。",
			"button": "继续",
		},
		{
			"dialog": "下面开始你第一天的交易，我来教你怎么在市场里赚钱。",
			"button": "继续",
		},
		{
			"dialog": "目前先做这只股票，盈维达，公司蒸蒸日上，有无限的想象空间。",
			"button": "开始交易",
		},
		{
			"target_path": "PlayerPanel/VBox/LblCash",
			"dialog": "这是你的本金，牌打得再漂亮，现金没了，你就没钱继续操作了。",
			"prompt": "资金：当前可直接使用的现金。",
		},
		{
			"target_path": "DataPanel/VBox/StatsGrid/CellShares",
			"dialog": "这是你手里的筹码，你可以把它理解成你买到的货。手里没货，后面价格涨飞了，也跟你没关系。",
			"prompt": "筹码：你当前持有的股票数量。",
		},
		{
			"target_paths": ["TopBar/MidBar/HBox/IconEmotion", "TopBar/MidBar/HBox/LblEmotionTitle", "TopBar/MidBar/HBox/EmotionBarSlot", "TopBar/MidBar/HBox/LblEmotionState"],
			"dialog": "这是市场情绪。简单说，就是大家现在想不想买。情绪热的时候，大家都想冲，价格更容易涨。情绪冷的时候，大家都想跑，价格更容易跌。",
			"prompt": "市场热度：火热会放大上涨，冷淡会放大下跌。",
		},
		{
			"target_path": "TurnPanel/VBox/BtnUndoTurn",
			"dialog": "如果这一回合点错牌，可以点这里撤回本回合已经打出的牌。\n每回合只能用一次，回合结束后就不能撤回了。",
			"prompt": "撤回：回到本回合出牌前的状态。",
			"button": "继续",
		},
		{
			"dialog": "知道怎么靠股票赚钱吗？",
			"player_dialog": "看价格图猜涨跌？",
		},
		{
			"dialog": "不，靠别人犯傻。价格图本质只是成交价格的记录表。\n记住，股票本身不值钱。\n有人愿意更贵买，它才值钱。",
		},
		{
			"target_effect": "buy_basic",
			"wait": "buy",
			"dialog": "先买点货。手里没有筹码，后面涨了你也赚不到。",
			"prompt": "点击这张【买入】，用现金买入筹码。",
			"button": "",
		},
		{
			"dialog": "接下来教你市场最核心的东西：情绪。",
			"player_dialog": "不看公司好不好吗？",
		},
		{
			"dialog": "那是被套住以后，用来安慰自己的。",
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
			"dialog": "等等。\n买入和把价格炒上去，不是一回事？",
		},
		{
			"dialog": "当然不是。\n买入，是你自己先拿货。\n拉升，是让市场觉得这东西要涨。\n你有货，别人也想买，价格才推得动。",
		},
		{
			"target_effect": "inflow_capital",
			"wait": "price_up",
			"dialog": "现在给市场一点真金白银的刺激。\n打出【游资进场】，让价格冲一段。",
			"prompt": "打出【游资进场】，让股价快速冲一段。",
			"button": "",
		},
		{
			"target_path": "ChartPanel",
			"dialog": "看见没？先把气氛炒热，再让资金进场。这样价格就更容易冲上去。",
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
			"dialog": "好消息最大的作用，就是让更多人愿意接你的货。",
		},
		{
			"dialog": "我们今天用的是公司的钱。\n公司的钱不能拖太久，拖得越久，风险越大。\n所以今天买的货，最好今天卖掉。\n如果当天你出不掉货，我们只能 8 折贱卖。",
			"player_dialog": "为啥啊，我辛辛苦苦拉的股价。",
		},
		{
			"dialog": "市场不等人。\n涨上去的时候不卖，跌下来就只能说：不要怕，是技术性调整。",
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
			"button": "进入第二天",
		},
		{
			"action": "leave_shop_for_event",
			"dialog": "准备好了就走。第二天开盘，市场可不会等你。",
			"button": "继续",
		},
		{
			"action": "trigger_event",
			"event_id": "black_swan",
			"target_path": "TopBar",
			"dialog": "俗话说，天有不测风云。",
			"prompt": "利空事件会直接改变市场环境。",
			"button": "继续",
		},
		{
			"dialog": "所以今天开盘大跌，昨天跑的对吧？",
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


func _build_goal_steps() -> void:
	_steps = [
		{
			"dialog": "公司是有绩效要求的。",
			"button": "继续",
		},
		{
			"target_path": "PlayerTargetBar",
			"dialog": "开局你的账户有 10 万元，本周你刚入职，新人标准，周五需要达到 12 万元的目标。",
			"prompt": "新人目标：周五收盘总资产达到 ¥120,000。",
			"button": "继续",
		},
		{
			"dialog": "那我们只能，江湖再见。",
			"player_dialog": "如果达不到呢？",
			"button": "继续交易",
			"finish": true,
		},
	]


func _build_formal_intro_steps() -> void:
	_steps = [
		{
			"dialog": "年轻人，上周是不是很轻松？",
			"player_dialog": "还，还行。",
			"button": "继续",
		},
		{
			"target_path": "PlayerTargetBar",
			"dialog": "这周你的账户有 20 万元，周五 25 万指标。",
			"prompt": "正式关目标：周五收盘总资产达到 ¥250,000。",
			"button": "继续",
		},
		{
			"dialog": "本次你要做的品种是消费公司 PP 玛特，这个票不止我们一家机构。",
			"button": "继续",
		},
		{
			"dialog": "如果出现其他对手，希望你做好心理准备。",
			"button": "开始正式交易",
			"finish": true,
		},
	]


func _build_opponent_intro_steps() -> void:
	_steps = [
		{
			"target_path": "EnemyPanel",
			"dialog": "做空对手出现了。他们主要靠砸低股价来获利，这是把双刃剑。",
			"prompt": "对手会干预股价，也可能帮你把价格砸到低位。",
			"button": "继续",
		},
		{
			"dialog": "他们既会干预我们拉升股价的节奏，也可以被我们利用：等他们砸低股价，你买点便宜股票，然后拉升卖出。",
			"player_dialog": "那现在怎么办？",
			"button": "继续",
		},
		{
			"target_path": "EnemyHpBar",
			"dialog": "如果你看不惯他们，可以看他们的平仓线。把股价拉升到平仓线，他们受不了亏损就走了。",
			"prompt": "平仓线：股价越接近这里，对手越危险。",
			"button": "知道了",
			"finish": true,
		},
	]


func _build_opponent_reward_steps() -> void:
	_steps = [
		{
			"dialog": "表现不错，我果然没看错你。",
			"button": "继续",
		},
		{
			"dialog": "盘后市场有一张稀有卡，作为你打败对手的奖励，记得去看看。",
			"button": "知道了",
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
	_stop_intro_typewriter()
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
	_configure_intro_panel(step)
	_intro_panel.visible = true
	_intro_button.text = String(step.get("button", "知道了"))
	_intro_button.visible = not bool(step.get("typewriter", false))
	if bool(step.get("typewriter", false)):
		_start_intro_typewriter(String(step.get("intro_body", "")))
	call_deferred("_update_layout")


func _configure_intro_panel(step: Dictionary) -> void:
	var intro_texture := step.get("intro_texture", BAOSHU_AVATAR_TEXTURE) as Texture2D
	if intro_texture != null:
		_intro_portrait.texture = intro_texture
	var intro_name: String = String(step.get("intro_name", "宝叔"))
	_intro_name_label.text = intro_name
	_intro_name_label.visible = intro_name != ""
	var intro_title: String = String(step.get("intro_title", "人物介绍"))
	_intro_title_label.text = intro_title
	_intro_title_label.visible = intro_title != ""
	_intro_body_label.text = String(step.get("intro_body", ""))
	_intro_body_label.visible_characters = -1


func _start_intro_typewriter(full_text: String) -> void:
	_intro_typewriter_done = false
	_intro_body_label.visible_characters = 0
	var duration: float = max(0.6, float(full_text.length()) / INTRO_TYPEWRITER_CHARS_PER_SECOND)
	_intro_text_tween = create_tween()
	_intro_text_tween.tween_property(_intro_body_label, "visible_characters", full_text.length(), duration)
	_intro_text_tween.finished.connect(_on_intro_typewriter_finished)


func _on_intro_typewriter_finished() -> void:
	_intro_text_tween = null
	_complete_intro_typewriter(false)


func _complete_intro_typewriter(cancel_tween: bool = true) -> void:
	if cancel_tween:
		_stop_intro_typewriter()
	_intro_typewriter_done = true
	if _intro_body_label != null:
		_intro_body_label.visible_characters = -1
	if _intro_button != null:
		_intro_button.visible = true


func _stop_intro_typewriter() -> void:
	if _intro_text_tween != null and _intro_text_tween.is_valid():
		_intro_text_tween.kill()
	_intro_text_tween = null
	_intro_typewriter_done = true


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
		_next_button.text = button_text
		_next_button.visible = _should_show_shop_dialog_button(step)
		_prompt.visible = false
		_arrow.visible = false
		_clear_card_highlight()
		_update_shop_button_text()
	else:
		_next_button.text = button_text
		_next_button.visible = _should_show_next_button(step)
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
	if _try_complete_intro_typewriter(step):
		return
	if _should_dismiss_shop_guide_on_blank_click(step):
		_close_shop_dialog()
		return


func _should_show_next_button(step: Dictionary) -> bool:
	if String(step.get("wait", "")) != "":
		return false
	if bool(step.get("force_click", false)):
		return false
	return String(step.get("button", "下一步")) != ""


func _should_show_shop_dialog_button(step: Dictionary) -> bool:
	if not bool(step.get("dialog_next", false)):
		return false
	if String(step.get("wait", "")) != "":
		return false
	if bool(step.get("force_click", false)):
		return false
	return String(step.get("button", "下一步")) != ""


func _try_complete_intro_typewriter(step: Dictionary) -> bool:
	if not bool(step.get("intro", false)):
		return false
	if not bool(step.get("typewriter", false)):
		return false
	if _intro_typewriter_done:
		return false
	_complete_intro_typewriter()
	return true


func _should_dismiss_shop_guide_on_blank_click(step: Dictionary) -> bool:
	if not _is_step_shop_guide(step):
		return false
	if bool(step.get("dialog_next", false)):
		return false
	if bool(step.get("force_click", false)):
		return false
	if String(step.get("wait", "")) != "":
		return false
	return true


func _on_next_pressed() -> void:
	if not _active:
		return
	var step: Dictionary = _steps[_step_index]
	if _try_complete_intro_typewriter(step):
		return
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
	var finished_mode: String = _mode
	_active = false
	visible = false
	_clear_card_highlight()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var shop := _shop_overlay()
	if shop != null and shop.has_method("clear_tutorial_button_override"):
		shop.call("clear_tutorial_button_override")
	match finished_mode:
		"level":
			if Game.has_method("tutorial_finish_guidance"):
				Game.call("tutorial_finish_guidance")
			else:
				Game.set_tutorial_active(false)
		"goal":
			if Game.has_method("finish_goal_intro"):
				Game.call("finish_goal_intro")
		"formal":
			if Game.has_method("finish_formal_intro"):
				Game.call("finish_formal_intro")
		"opponent":
			if Game.has_method("finish_opponent_tutorial"):
				Game.call("finish_opponent_tutorial")
		"opponent_reward":
			if Game.has_method("finish_opponent_reward_tutorial"):
				Game.call("finish_opponent_reward_tutorial")
		_:
			if Game.has_method("finish_context_tutorial"):
				Game.call("finish_context_tutorial")


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
		if bool(step.get("force_click", false)) or String(step.get("wait", "")) != "":
			shop.call("set_tutorial_button_override", "")
			return
		if bool(step.get("dialog_next", false)):
			shop.call("set_tutorial_button_override", "")
			return
		var step_button: String = String(step.get("button", ""))
		if step_button != "":
			text = step_button
	if _step_index >= _steps.size() - 1:
		text = "进入第二天"
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
	_position_player_dialog(dialog_rect, target_rect, prompt_rect)


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
	var button_text: String = String(step.get("button", "知道了"))
	_next_button.text = button_text
	_next_button.visible = _should_show_shop_dialog_button(step)

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
	_dialog.position = _pick_shop_dialog_rect(target_rect, Vector2(w, h), force_click).position


func _pick_shop_dialog_rect(target_rect: Rect2, dialog_size: Vector2, force_near_target: bool) -> Rect2:
	var center_x: float = (size.x - dialog_size.x) * 0.5
	var center_y: float = size.y * 0.60 - dialog_size.y * 0.5
	var candidates: Array = []
	var preferred_center := Vector2(size.x * 0.5, size.y * 0.60)
	if target_rect.size.x > 0.0 and target_rect.size.y > 0.0:
		var near_x: float = clampf(
			target_rect.get_center().x - dialog_size.x * 0.5,
			16.0,
			max(16.0, size.x - dialog_size.x - 16.0)
		)
		var below := Rect2(Vector2(near_x, target_rect.end.y + 16.0), dialog_size)
		var above := Rect2(Vector2(near_x, target_rect.position.y - dialog_size.y - 16.0), dialog_size)
		if force_near_target:
			candidates.append(below)
			candidates.append(above)
			candidates.append(Rect2(Vector2(center_x, size.y - dialog_size.y - 56.0), dialog_size))
			candidates.append(Rect2(Vector2(center_x, 56.0), dialog_size))
			preferred_center = Vector2(target_rect.get_center().x, target_rect.end.y + 16.0 + dialog_size.y * 0.5)
		else:
			candidates.append(Rect2(Vector2(center_x, center_y), dialog_size))
			candidates.append(Rect2(Vector2(center_x, 56.0), dialog_size))
			candidates.append(Rect2(Vector2(center_x, size.y - dialog_size.y - 56.0), dialog_size))
			candidates.append(below)
			candidates.append(above)
	else:
		candidates.append(Rect2(Vector2(center_x, center_y), dialog_size))
		candidates.append(Rect2(Vector2(center_x, 56.0), dialog_size))
		candidates.append(Rect2(Vector2(center_x, size.y - dialog_size.y - 56.0), dialog_size))
	var avoid: Array = []
	if target_rect.size.x > 0.0 and target_rect.size.y > 0.0:
		avoid.append(target_rect)
	return _pick_best_rect(candidates, avoid, preferred_center)


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


func _position_player_dialog(dialog_rect: Rect2, target_rect: Rect2 = Rect2(), prompt_rect: Rect2 = Rect2()) -> void:
	if _player_dialog == null or not _player_dialog.visible:
		return
	var w: float = min(500.0, max(280.0, dialog_rect.size.x - 36.0))
	var player_size := Vector2(w, PLAYER_DIALOG_H)
	_player_dialog.size = player_size
	var right_x: float = dialog_rect.position.x + dialog_rect.size.x - w - 22.0
	var left_x: float = dialog_rect.position.x + 22.0
	var candidates: Array = [
		Rect2(Vector2(right_x, dialog_rect.end.y + 8.0), player_size),
		Rect2(Vector2(right_x, dialog_rect.position.y - PLAYER_DIALOG_H - 8.0), player_size),
		Rect2(Vector2(left_x, dialog_rect.end.y + 8.0), player_size),
		Rect2(Vector2(left_x, dialog_rect.position.y - PLAYER_DIALOG_H - 8.0), player_size),
	]
	var avoid: Array = [dialog_rect]
	if target_rect.size.x > 0.0 and target_rect.size.y > 0.0:
		avoid.append(target_rect)
	if prompt_rect.size.x > 0.0 and prompt_rect.size.y > 0.0:
		avoid.append(prompt_rect)
	var best: Rect2 = _pick_best_rect(candidates, avoid, size * 0.5)
	_player_dialog.position = best.position


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


func _pick_best_rect(candidates: Array, avoid_rects: Array, preferred_center: Vector2) -> Rect2:
	var best: Rect2 = Rect2()
	var best_score: float = INF
	for candidate in candidates:
		var r: Rect2 = candidate
		r.position.x = clampf(r.position.x, 12.0, max(12.0, size.x - r.size.x - 12.0))
		r.position.y = clampf(r.position.y, 12.0, max(12.0, size.y - r.size.y - 12.0))
		var score: float = r.get_center().distance_to(preferred_center) * 0.12
		for avoid in avoid_rects:
			var ar: Rect2 = avoid
			if ar.size.x <= 0.0 or ar.size.y <= 0.0:
				continue
			score += _overlap_area(r, ar) * 18.0
		if score < best_score:
			best_score = score
			best = r
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
