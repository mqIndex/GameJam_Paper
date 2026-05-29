extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const Event = preload("res://scripts/event.gd")
const CardChoiceDialog = preload("res://scripts/views/card_choice_dialog.gd")
const TutorialOverlayScene = preload("res://scenes/ui/tutorial_overlay.tscn")
const DaySettlementOverlay = preload("res://scripts/views/day_settlement_overlay.gd")
const SaveOverlay = preload("res://scripts/views/save_overlay.gd")
const PauseOverlay = preload("res://scripts/views/pause_overlay.gd")
const TitleOverlay = preload("res://scripts/views/title_overlay.gd")

@onready var log_text: RichTextLabel = $LogText
@onready var bg: ColorRect = $BG
@onready var top_bar: Control = $TopBar
@onready var enemy_hp_bar: Control = $EnemyHpBar
@onready var chart_panel: Control = $ChartPanel
@onready var data_panel: Control = $DataPanel
@onready var player_target_bar: Control = $PlayerTargetBar
@onready var action_bar: Control = $ActionBar
@onready var enemy_panel: Control = $EnemyPanel
@onready var hand_panel: Control = $HandPanel
@onready var turn_panel: Control = $TurnPanel
@onready var player_panel: Control = $PlayerPanel
@onready var end_dialog: Control = $EndDialog
@onready var shop_overlay: Control = $ShopOverlay
@onready var deck_preview_popup: Control = $DeckPreviewPopup

const COL_TEXT_DIM: Color = Color("#9aa7c0")
const COL_HIGHLIGHT: Color = Color("#ffae42")
const COL_GOLD: Color = Color("#ffd166")
const COL_UP: Color = Color("#06d6a0")
const COL_DOWN: Color = Color("#ef476f")
const BAOSHU_AVATAR_PATH: String = "res://assets/baoshu_avatar_UpperHalf.png"
const BAOSHU_TIP_SIZE: Vector2 = Vector2(560.0, 172.0)
const BAOSHU_TIP_TEXT_WIDTH: float = 382.0

var _choice_dialog: CardChoiceDialog = null
var _opponent_popup: PanelContainer = null
var _opponent_popup_title: Label = null
var _opponent_popup_body: Label = null
var _opponent_popup_tween: Tween = null
var _opponent_popup_size: Vector2 = Vector2.ZERO
var _opponent_popup_y_ratio: float = 0.34
var _subtitle_banner: Label = null
var _tutorial_overlay: Control = null
var _day_settlement_overlay: Control = null
var _baoshu_tip_panel: PanelContainer = null
var _baoshu_tip_text: Label = null
var _baoshu_tip_button: Button = null
var _pending_baoshu_tip_text: String = ""
var _pending_day_settlement: bool = false
var _save_overlay: Control = null
var _pause_overlay: Control = null
var _title_overlay: Control = null
var _game_started: bool = false

const MIN_WINDOW_SIZE: Vector2 = Vector2(960.0, 540.0)
const OUTER_PAD: float = 8.0
const GAP: float = 8.0
const TOP_BAR_H: float = 36.0
const SUBTITLE_H: float = 22.0
const MONEY_BAR_W: float = 132.0
const PLAYER_TARGET_BAR_W: float = 132.0
const ACTION_BAR_H: float = 28.0
const BOTTOM_ROW_H: float = 204.0
const BOTTOM_ROW_MIN_H: float = 164.0
const ENEMY_W: float = 168.0
const TURN_W: float = 136.0
const PLAYER_W: float = 184.0
const DATA_PANEL_MIN_W: float = 160.0
const DATA_PANEL_WIDTH_RATIO: float = 0.154
const DATA_PANEL_MAX_W: float = 224.0
const END_DIALOG_SIZE: Vector2 = Vector2(512.0, 280.0)
const OPPONENT_POPUP_SIZE: Vector2 = Vector2(332.0, 126.0)
const OPPONENT_POPUP_DURATION: float = 2.4
const OPPONENT_DEFEAT_POPUP_SIZE: Vector2 = Vector2(430.0, 150.0)
const OPPONENT_DEFEAT_POPUP_DURATION: float = 3.4


func _ready() -> void:
	custom_minimum_size = Vector2.ZERO
	var window := get_window()
	window.min_size = Vector2i(int(MIN_WINDOW_SIZE.x), int(MIN_WINDOW_SIZE.y))
	if window.mode == Window.MODE_WINDOWED:
		window.mode = Window.MODE_MAXIMIZED
	resized.connect(_relayout)
	_relayout()
	Game.log_message.connect(_append_log)
	_setup_choice_dialog()
	_build_opponent_popup()
	_build_subtitle_banner()
	_apply_bg_texture()
	_setup_tutorial_overlay()
	_setup_day_settlement_overlay()
	_build_baoshu_tip_dialog()
	_setup_pause_overlay()
	Game.opponent_entered.connect(_on_opponent_entered_popup)
	Game.opponent_defeated.connect(_on_opponent_defeated_popup)
	Game.baoshu_tip_requested.connect(_on_baoshu_tip_requested)
	Game.opponent_defeated.connect(_on_opponent_defeated_for_tutorial)
	Game.day_ended.connect(_on_day_ended_show_settlement)
	Game.shop_entered.connect(_on_shop_entered_for_tutorial)
	Game.day_started.connect(_on_day_started_for_tutorial)
	Game.level_started.connect(_on_level_started_for_tutorial)
	# 自动保存钩子: 通关 / 教学进度变化 都尝试落盘
	Game.level_finished.connect(_on_level_finished_for_save)
	Game.state_changed.connect(_on_state_changed_for_save)
	Saves.active_slot_changed.connect(_on_active_slot_changed)
	$PlayerPanel.pile_clicked.connect(_on_pile_clicked)
	$TurnPanel.pile_clicked.connect(_on_pile_clicked)
	_apply_active_persona_portrait()
	# 隐藏游戏 UI 直到玩家选档完成, 避免空状态闪烁
	_set_gameplay_visible(false)
	# 封面出现的同时就放 BGM (_start_bgm 内部 has_node 幂等, 后续路径再调不会重叠)
	_start_bgm()
	if _has_cmdline_flag("--skip-save"):
		# 直跑模式 (cmdline 测试): 不弹存档页, 走旧的默认教学流程
		_start_gameplay(true)
	else:
		_show_title_overlay()


func _has_cmdline_flag(flag: String) -> bool:
	for arg in OS.get_cmdline_args():
		if String(arg) == flag:
			return true
	for arg in OS.get_cmdline_user_args():
		if String(arg) == flag:
			return true
	return false


# ===========================================================
# 存档启动流程
# ===========================================================
# 玩家可见 UI 仅 BG + 标题横幅 + SaveOverlay; 游戏主面板隐藏, 避免空状态闪烁
const _GAMEPLAY_PANEL_NODE_NAMES: Array = [
	"TopBar", "EnemyHpBar", "ChartPanel", "DataPanel", "PlayerTargetBar",
	"ActionBar", "EnemyPanel", "HandPanel", "TurnPanel", "PlayerPanel", "LogText",
]


func _set_gameplay_visible(visible_state: bool) -> void:
	for node_name in _GAMEPLAY_PANEL_NODE_NAMES:
		var n: Node = get_node_or_null(node_name)
		if n is CanvasItem:
			(n as CanvasItem).visible = visible_state
	if _subtitle_banner != null:
		_subtitle_banner.visible = visible_state
	if _day_settlement_overlay != null and not visible_state:
		_day_settlement_overlay.visible = false
	if _baoshu_tip_panel != null and not visible_state:
		_baoshu_tip_panel.visible = false


func _show_title_overlay() -> void:
	if _title_overlay != null and is_instance_valid(_title_overlay):
		_title_overlay.visible = true
		return
	_title_overlay = TitleOverlay.new()
	_title_overlay.name = "TitleOverlay"
	add_child(_title_overlay)
	_set_full_rect(_title_overlay)
	_title_overlay.start_pressed.connect(_on_title_start_pressed)


func _close_title_overlay() -> void:
	if _title_overlay != null and is_instance_valid(_title_overlay):
		_title_overlay.queue_free()
		_title_overlay = null


func _on_title_start_pressed() -> void:
	_close_title_overlay()
	_show_save_overlay()


func _show_save_overlay() -> void:
	if _save_overlay != null and is_instance_valid(_save_overlay):
		_save_overlay.visible = true
		return
	_save_overlay = SaveOverlay.new()
	_save_overlay.name = "SaveOverlay"
	add_child(_save_overlay)
	_set_full_rect(_save_overlay)
	_save_overlay.confirmed.connect(_on_save_overlay_confirmed)


func _on_save_overlay_confirmed(_slot_index: int, _persona_id: String, _is_new: bool, start_level_override: int) -> void:
	# SaveOverlay 内部已经把 active_slot 写好并落盘; 这里只负责拿进度起游戏
	# start_level_override: >=0 = 全通关存档重玩选关时携带, 覆盖 max_cleared+1 的默认起始关
	Saves.apply_to_game(start_level_override)
	if _save_overlay != null and is_instance_valid(_save_overlay):
		_save_overlay.queue_free()
		_save_overlay = null
	_apply_active_persona_portrait()
	_start_gameplay(false)


func _start_gameplay(allow_default_persona: bool) -> void:
	if _game_started:
		return
	_game_started = true
	_set_gameplay_visible(true)
	var skip_tutorial: bool = _has_cmdline_flag("--skip-tutorial")
	if skip_tutorial:
		Game.finish_tutorial()
	# allow_default_persona: cmdline --skip-save 时, Saves 里没有 active; 给个默认头像以免空白
	if allow_default_persona and Saves.active_persona_id == "":
		Saves.active_persona_id = Saves.DEFAULT_PERSONA_ID
		_apply_active_persona_portrait()
	var tutorial_should_start: bool = (not skip_tutorial) and Game.should_start_tutorial()
	Game.set_tutorial_active(tutorial_should_start)
	_capture_save_snapshot()
	Game.new_level()
	if tutorial_should_start and _tutorial_overlay != null:
		_tutorial_overlay.call_deferred("start")
	_start_bgm()


# ===========================================================
# 自动保存钩子
# ===========================================================
# 上次写入 Saves 的快照 hash, 用来对比是否需要落盘 (避免每次 state_changed 都写文件)
# hash 由 Saves.compute_capture_hash() 计算, 涵盖 tutorial flag + Dict 字段 (opponent_intro_seen 等)
var _last_save_hash: int = 0


func _capture_save_snapshot() -> void:
	_last_save_hash = Saves.compute_capture_hash()


func _on_state_changed_for_save() -> void:
	if not _game_started:
		return
	if Saves.active_slot_index < 0:
		return
	var cur: int = Saves.compute_capture_hash()
	if cur == _last_save_hash:
		return
	_last_save_hash = cur
	Saves.capture_from_game()


func _on_level_finished_for_save(victory: bool, _final_assets: float) -> void:
	if not _game_started:
		return
	if Saves.active_slot_index < 0:
		return
	if victory:
		Saves.record_level_cleared(Game.current_level_index)
	# 不论胜负都同步 tutorial flag (失败时 finish_tutorial 也可能被触发)
	Saves.capture_from_game()
	_capture_save_snapshot()


func _on_active_slot_changed(_slot_index: int, _persona_id: String) -> void:
	_apply_active_persona_portrait()


func _apply_active_persona_portrait() -> void:
	var avatar: Node = get_node_or_null("PlayerPanel/VBox/AvatarSlot/Avatar")
	if avatar == null or not avatar.has_method("set_portrait"):
		return
	avatar.call("set_portrait", Saves.get_active_portrait())


# 选择类卡 UI: 接 game_state 4 个 request_* 信号 → 弹 dialog → 回调 game_state apply_*
func _setup_choice_dialog() -> void:
	_choice_dialog = CardChoiceDialog.new()
	add_child(_choice_dialog)
	Game.event_preview_requested.connect(_on_event_preview_requested)
	Game.discard_choice_requested.connect(_on_discard_choice_requested)
	Game.topdeck_choice_requested.connect(_on_topdeck_choice_requested)
	Game.shatter_choice_requested.connect(_on_shatter_choice_requested)


func _on_event_preview_requested(events: Array) -> void:
	_choice_dialog.show_event_single(
		"内幕消息 · 三选一",
		"选择一个事件作为下一次突发事件触发的内容。",
		events,
		func(picked):
			Game.set_pending_event((picked as Event).id)
	)


func _on_discard_choice_requested(hand_cards: Array) -> void:
	var draw_n: int = max(1, Game.pending_discard_draw_count)
	_choice_dialog.show_card_single(
		"顺势而为",
		"选择 1 张要弃掉的手牌, 之后会抽 %d 张。" % draw_n,
		hand_cards,
		func(picked):
			var idx: int = Game.hand.find(picked)
			if idx >= 0:
				Game.discard_one_then_draw(idx)
	)


func _on_topdeck_choice_requested(draw_pile_cards: Array) -> void:
	_choice_dialog.show_card_single(
		"计划得当",
		"从抽牌堆选 1 张, 放到牌堆顶 (下次必抽)。",
		draw_pile_cards,
		func(picked):
			var idx: int = Game.draw_pile.find(picked)
			if idx >= 0:
				Game.place_on_top_of_draw(idx)
	)


func _on_shatter_choice_requested(buy_sell_cards: Array) -> void:
	_choice_dialog.show_card_multi(
		"化整为零",
		"选择任意张 BUY/SELL 牌进入弃牌堆, 每张换为 2 张本回合限定的小买/小卖。",
		buy_sell_cards,
		func(picked):
			Game.shatter_cards(picked)
	)


# 主背景贴图: 在 BG ColorRect 之上叠一个 TextureRect, 纹理缺失则不挂, 保留 ColorRect 颜色作 fallback
func _apply_bg_texture() -> void:
	if has_node("BgTexture"):
		return
	if not ResourceLoader.exists(UF.PATH_BG_MAIN):
		return
	var tex = load(UF.PATH_BG_MAIN) as Texture2D
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.name = "BgTexture"
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(1, 1, 1, 0.55)  # 半透明叠加, 避免抢 UI 视觉
	tr.anchor_right = 1.0
	tr.anchor_bottom = 1.0
	tr.offset_left = 0.0
	tr.offset_top = 0.0
	tr.offset_right = 0.0
	tr.offset_bottom = 0.0
	tr.z_index = -10
	add_child(tr)
	move_child(tr, 1)  # BG 是 index 0, BgTexture index 1


# 标题横幅 (中上方红橙强调字, 仅显示氛围标语, 不影响游戏逻辑)
func _build_subtitle_banner() -> void:
	if has_node("SubtitleBanner"):
		_subtitle_banner = get_node("SubtitleBanner") as Label
		return
	_subtitle_banner = Label.new()
	_subtitle_banner.name = "SubtitleBanner"
	_subtitle_banner.text = "不要怕，是技术性调整！"
	_subtitle_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_banner.z_index = 5
	_subtitle_banner.add_theme_font_size_override("font_size", 16)
	_subtitle_banner.add_theme_color_override("font_color", UF.COL_NEON_RED)
	_subtitle_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_subtitle_banner.add_theme_constant_override("outline_size", 3)
	add_child(_subtitle_banner)
	_position_subtitle_banner()


func _position_subtitle_banner() -> void:
	if _subtitle_banner == null:
		return
	var view_size: Vector2 = size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = get_viewport_rect().size
	var w: float = max(420.0, view_size.x * 0.5)
	_subtitle_banner.size = Vector2(w, SUBTITLE_H)
	_subtitle_banner.position = Vector2(
		(view_size.x - w) * 0.5,
		OUTER_PAD + TOP_BAR_H + 2.0
	)


func _build_opponent_popup() -> void:
	_opponent_popup = PanelContainer.new()
	_opponent_popup.name = "OpponentEntryPopup"
	_opponent_popup.visible = false
	_opponent_popup.z_index = 220
	_opponent_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opponent_popup.custom_minimum_size = OPPONENT_POPUP_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.13, 0.84)
	sb.border_color = Color(COL_DOWN.r, COL_DOWN.g, COL_DOWN.b, 0.78)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	_opponent_popup.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_opponent_popup.add_child(vbox)

	_opponent_popup_title = Label.new()
	_opponent_popup_title.add_theme_font_size_override("font_size", 15)
	_opponent_popup_title.add_theme_color_override("font_color", COL_DOWN)
	_opponent_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_opponent_popup_title)

	_opponent_popup_body = Label.new()
	_opponent_popup_body.add_theme_font_size_override("font_size", 12)
	_opponent_popup_body.add_theme_color_override("font_color", COL_TEXT_DIM)
	_opponent_popup_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_opponent_popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_opponent_popup_body.custom_minimum_size = Vector2(OPPONENT_POPUP_SIZE.x - 28.0, 0.0)
	vbox.add_child(_opponent_popup_body)
	add_child(_opponent_popup)
	_opponent_popup_size = OPPONENT_POPUP_SIZE
	_position_opponent_popup()


func _on_opponent_entered_popup(_opponent_id: String) -> void:
	if _opponent_popup == null:
		return
	var opp = Game.get_opponent_state()
	if opp == null:
		return
	var body: String = "做空 %d 股 @ ¥%.2f\n爆仓线 ¥%.2f  现金 ¥%s" % [
		opp.short_position,
		opp.entry_avg_price,
		opp.liquidation_price,
		UF.fmt_money(opp.cash)
	]
	_show_opponent_popup(
		"庄家入场 · %s" % opp.display_name,
		body,
		COL_DOWN,
		COL_DOWN,
		OPPONENT_POPUP_SIZE,
		OPPONENT_POPUP_DURATION,
		0.34
	)
	if Game.current_level_index > 0 and _tutorial_overlay != null:
		var opp_id: String = ""
		if opp != null:
			opp_id = opp.opponent_id
		var need_intro: bool = not Game.opponent_tutorial_completed or not Game.opponent_intro_seen(opp_id)
		if need_intro and _tutorial_overlay.has_method("start_opponent_intro"):
			_tutorial_overlay.call_deferred("start_opponent_intro")


func _on_opponent_defeated_popup(_opponent_id: String, reward_card_id: String) -> void:
	if _opponent_popup == null:
		return
	var opp = Game.get_opponent_state()
	var opponent_name: String = "空头"
	if opp != null and opp.display_name != "":
		opponent_name = opp.display_name
	var reward_text: String = "\n奖励牌已加入抽牌堆" if reward_card_id != "" else ""
	var body: String = "%s被迫离场，空头撤了。\n场内情绪明显回暖：上涨情绪 +%d%s" % [
		opponent_name,
		Game.OPPONENT_DEFEAT_EMOTION_BONUS,
		reward_text
	]
	_show_opponent_popup(
		"空头退场 · 情绪回暖",
		body,
		COL_UP,
		COL_UP,
		OPPONENT_DEFEAT_POPUP_SIZE,
		OPPONENT_DEFEAT_POPUP_DURATION,
		0.42
	)


func _on_baoshu_tip_requested(text: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_pending_baoshu_tip_text = text


func _show_opponent_popup(
	title: String,
	body: String,
	title_color: Color,
	border_color: Color,
	popup_size: Vector2,
	duration: float,
	y_ratio: float
) -> void:
	if _opponent_popup == null:
		return
	_opponent_popup_size = popup_size
	_opponent_popup_y_ratio = y_ratio
	_set_opponent_popup_style(border_color)
	_opponent_popup_title.text = title
	_opponent_popup_title.add_theme_color_override("font_color", title_color)
	_opponent_popup_title.add_theme_font_size_override("font_size", 18 if popup_size.x > OPPONENT_POPUP_SIZE.x else 15)
	_opponent_popup_body.text = body
	_opponent_popup_body.add_theme_font_size_override("font_size", 14 if popup_size.x > OPPONENT_POPUP_SIZE.x else 12)
	_opponent_popup_body.add_theme_color_override(
		"font_color",
		Color("#dce7df") if popup_size.x > OPPONENT_POPUP_SIZE.x else COL_TEXT_DIM
	)
	_opponent_popup_body.custom_minimum_size = Vector2(max(0.0, popup_size.x - 28.0), 0.0)
	_position_opponent_popup()
	_opponent_popup.visible = true
	if _opponent_popup_tween != null and _opponent_popup_tween.is_valid():
		_opponent_popup_tween.kill()
	_opponent_popup.modulate = Color(1, 1, 1, 0)
	_opponent_popup_tween = create_tween()
	_opponent_popup_tween.tween_property(_opponent_popup, "modulate", Color(1, 1, 1, 1), 0.14)
	_opponent_popup_tween.tween_interval(duration)
	_opponent_popup_tween.tween_property(_opponent_popup, "modulate", Color(1, 1, 1, 0), 0.28)
	_opponent_popup_tween.tween_callback(_hide_opponent_popup)


func _set_opponent_popup_style(border_color: Color) -> void:
	if _opponent_popup == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.13, 0.9)
	sb.border_color = Color(border_color.r, border_color.g, border_color.b, 0.86)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 16.0
	sb.content_margin_top = 12.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 12.0
	_opponent_popup.add_theme_stylebox_override("panel", sb)


func _hide_opponent_popup() -> void:
	if _opponent_popup != null:
		_opponent_popup.visible = false


func _position_opponent_popup() -> void:
	if _opponent_popup == null:
		return
	var view_size: Vector2 = size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = get_viewport_rect().size
	view_size.x = max(view_size.x, MIN_WINDOW_SIZE.x)
	view_size.y = max(view_size.y, MIN_WINDOW_SIZE.y)
	var popup_size: Vector2 = _opponent_popup_size
	if popup_size == Vector2.ZERO:
		popup_size = OPPONENT_POPUP_SIZE
	_opponent_popup.size = popup_size
	_opponent_popup.position = Vector2(
		(view_size.x - popup_size.x) * 0.5,
		max(64.0, (view_size.y - popup_size.y) * _opponent_popup_y_ratio)
	)


func _setup_tutorial_overlay() -> void:
	_tutorial_overlay = get_node_or_null("TutorialOverlay") as Control
	if _tutorial_overlay == null:
		_tutorial_overlay = TutorialOverlayScene.instantiate() as Control
		_tutorial_overlay.name = "TutorialOverlay"
		add_child(_tutorial_overlay)
	_tutorial_overlay.z_index = 260
	_tutorial_overlay.visible = false
	_set_full_rect(_tutorial_overlay)
	if _tutorial_overlay.has_method("setup"):
		_tutorial_overlay.setup(self)


func _setup_day_settlement_overlay() -> void:
	if _day_settlement_overlay != null and is_instance_valid(_day_settlement_overlay):
		return
	_day_settlement_overlay = DaySettlementOverlay.new()
	_day_settlement_overlay.name = "DaySettlementOverlay"
	add_child(_day_settlement_overlay)
	_set_full_rect(_day_settlement_overlay)
	_day_settlement_overlay.continue_requested.connect(_on_day_settlement_continue)


func _build_baoshu_tip_dialog() -> void:
	if _baoshu_tip_panel != null and is_instance_valid(_baoshu_tip_panel):
		return
	_baoshu_tip_panel = PanelContainer.new()
	_baoshu_tip_panel.name = "BaoshuTipDialog"
	_baoshu_tip_panel.visible = false
	_baoshu_tip_panel.z_index = 230
	_baoshu_tip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_baoshu_tip_panel.custom_minimum_size = BAOSHU_TIP_SIZE
	_baoshu_tip_panel.add_theme_stylebox_override("panel", UF.neon_panel_stylebox(UF.COL_GOLD))
	add_child(_baoshu_tip_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_baoshu_tip_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(108.0, 126.0)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(BAOSHU_AVATAR_PATH):
		avatar.texture = load(BAOSHU_AVATAR_PATH) as Texture2D
	row.add_child(avatar)

	var text_box := VBoxContainer.new()
	text_box.custom_minimum_size = Vector2(BAOSHU_TIP_TEXT_WIDTH, 0.0)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 8)
	row.add_child(text_box)

	var name_label := Label.new()
	name_label.text = "宝叔"
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", UF.COL_GOLD)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 2)
	text_box.add_child(name_label)

	_baoshu_tip_text = Label.new()
	_baoshu_tip_text.text = ""
	_baoshu_tip_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_baoshu_tip_text.custom_minimum_size = Vector2(BAOSHU_TIP_TEXT_WIDTH, 58.0)
	_baoshu_tip_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_baoshu_tip_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_baoshu_tip_text.add_theme_font_size_override("font_size", 17)
	_baoshu_tip_text.add_theme_color_override("font_color", UF.COL_TEXT)
	_baoshu_tip_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_baoshu_tip_text.add_theme_constant_override("outline_size", 2)
	text_box.add_child(_baoshu_tip_text)

	_baoshu_tip_button = UF.button("知道了", UF.COL_GOLD, 15)
	_baoshu_tip_button.custom_minimum_size = Vector2(112.0, 34.0)
	_baoshu_tip_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_baoshu_tip_button.pressed.connect(_on_baoshu_tip_continue)
	text_box.add_child(_baoshu_tip_button)
	_position_baoshu_tip_dialog()


func _position_baoshu_tip_dialog() -> void:
	if _baoshu_tip_panel == null:
		return
	var view_size: Vector2 = size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = get_viewport_rect().size
	view_size.x = max(view_size.x, MIN_WINDOW_SIZE.x)
	view_size.y = max(view_size.y, MIN_WINDOW_SIZE.y)
	_baoshu_tip_panel.custom_minimum_size = BAOSHU_TIP_SIZE
	_baoshu_tip_panel.size = BAOSHU_TIP_SIZE
	_baoshu_tip_panel.position = Vector2(
		(view_size.x - BAOSHU_TIP_SIZE.x) * 0.5,
		max(64.0, (view_size.y - BAOSHU_TIP_SIZE.y) * 0.42)
	)


func _show_baoshu_tip_dialog() -> void:
	if _baoshu_tip_panel == null or _pending_baoshu_tip_text == "":
		return
	_baoshu_tip_text.text = _pending_baoshu_tip_text
	_baoshu_tip_text.custom_minimum_size = Vector2(BAOSHU_TIP_TEXT_WIDTH, 58.0)
	_baoshu_tip_panel.visible = false
	_baoshu_tip_panel.modulate = Color(1, 1, 1, 0)
	_position_baoshu_tip_dialog()
	call_deferred("_show_baoshu_tip_dialog_after_layout")


func _show_baoshu_tip_dialog_after_layout() -> void:
	if _baoshu_tip_panel == null or _pending_baoshu_tip_text == "":
		return
	_position_baoshu_tip_dialog()
	_baoshu_tip_panel.visible = true
	_baoshu_tip_panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_baoshu_tip_panel, "modulate", Color(1, 1, 1, 1), 0.12)


func _on_baoshu_tip_continue() -> void:
	if _baoshu_tip_panel != null:
		_baoshu_tip_panel.visible = false
	_pending_baoshu_tip_text = ""
	_show_day_settlement_now()


func _on_day_ended_show_settlement(_day: int) -> void:
	if _day_settlement_overlay == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	_pending_day_settlement = true
	if _pending_baoshu_tip_text != "":
		_show_baoshu_tip_dialog()
		return
	_show_day_settlement_now()


func _show_day_settlement_now() -> void:
	if not _pending_day_settlement or _day_settlement_overlay == null:
		return
	_day_settlement_overlay.show_summary(Game.day_close_summary, Game.day >= Game.DAYS_PER_LEVEL)


func _on_day_settlement_continue() -> void:
	_pending_day_settlement = false
	Game.continue_after_day_settlement()


# ESC 暂停菜单: 含"继续游戏 / 返回标题切换存档 / 退出游戏"
# 仅在 _game_started 之后才响应 ESC; SaveOverlay/EndDialog/ShopOverlay/Tutorial 显示时不弹
func _setup_pause_overlay() -> void:
	if _pause_overlay != null and is_instance_valid(_pause_overlay):
		return
	_pause_overlay = PauseOverlay.new()
	_pause_overlay.name = "PauseOverlay"
	add_child(_pause_overlay)
	_set_full_rect(_pause_overlay)
	_pause_overlay.resume_requested.connect(_on_pause_resume)
	_pause_overlay.switch_slot_requested.connect(_on_pause_switch_slot)
	_pause_overlay.quit_requested.connect(_on_pause_quit)


func _can_open_pause_menu() -> bool:
	if not _game_started:
		return false
	if _save_overlay != null and is_instance_valid(_save_overlay) and _save_overlay.visible:
		return false
	if _pause_overlay != null and is_instance_valid(_pause_overlay) and _pause_overlay.visible:
		return false
	if $EndDialog != null and $EndDialog.visible:
		return false
	if $ShopOverlay != null and $ShopOverlay.visible:
		return false
	if _day_settlement_overlay != null and _day_settlement_overlay.visible:
		return false
	if _baoshu_tip_panel != null and _baoshu_tip_panel.visible:
		return false
	if Game.tutorial_active:
		return false
	return true


func _on_pause_resume() -> void:
	pass  # close_menu 已经在 PauseOverlay 内部处理


func _on_pause_switch_slot() -> void:
	# 切换存档: 当前局进度 (cash/shares/手牌/事件) 不持久化, 直接重载场景
	# autoload Game/Saves 会保留, 但 Game 需要被重置为干净状态以便走选档流程
	# 简单做法: 重载主场景; Saves 已经把进度落盘 (tutorial flag / max_cleared / opponent_intro_seen)
	# Saves 的 active_slot 也清掉, 让重载后的 main.gd 弹出 SaveOverlay
	Saves.active_slot_index = -1
	Saves.active_persona_id = ""
	Saves.emit_signal("active_slot_changed", -1, "")
	get_tree().reload_current_scene()


func _on_pause_quit() -> void:
	get_tree().quit()


func _on_shop_entered_for_tutorial(_day: int) -> void:
	if _tutorial_overlay == null:
		return
	if Game.should_start_shop_tutorial() and _tutorial_overlay.has_method("start_shop"):
		_tutorial_overlay.call_deferred("start_shop")


func _on_day_started_for_tutorial(day_index: int) -> void:
	if _tutorial_overlay == null:
		return
	if Game.current_level_index == 0 and day_index == 3 and not Game.tutorial_goal_intro_completed:
		if _tutorial_overlay.has_method("start_goal_intro"):
			_tutorial_overlay.call_deferred("start_goal_intro")


func _on_level_started_for_tutorial(level_index: int) -> void:
	if _tutorial_overlay == null:
		return
	if level_index > 0 and not Game.formal_intro_completed:
		if _tutorial_overlay.has_method("start_formal_intro"):
			_tutorial_overlay.call_deferred("start_formal_intro")


func _on_opponent_defeated_for_tutorial(_opponent_id: String, _reward_card_id: String) -> void:
	if _tutorial_overlay == null:
		return
	if Game.current_level_index > 0 and not Game.opponent_reward_tutorial_completed:
		var defeated_level_index: int = Game.current_level_index
		await get_tree().create_timer(OPPONENT_DEFEAT_POPUP_DURATION + 0.2).timeout
		if _tutorial_overlay == null or Game.opponent_reward_tutorial_completed:
			return
		if Game.is_level_over or Game.current_level_index != defeated_level_index:
			return
		if _tutorial_overlay.has_method("start_opponent_reward_intro"):
			_tutorial_overlay.call_deferred("start_opponent_reward_intro")


# 启动 BGM (循环, -8dB); 玩家点封面 / --skip-save 路径都会调到, 用 has_node 防重
func _start_bgm() -> void:
	if has_node("Bgm"):
		return
	var stream: AudioStream = load("res://assets/bgm/Measured Inflection.mp3") as AudioStream
	if stream == null:
		push_warning("BGM not loaded: res://assets/bgm/Measured Inflection.mp3")
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	var p := AudioStreamPlayer.new()
	p.name = "Bgm"
	p.stream = stream
	p.volume_db = -6.0
	p.autoplay = false
	add_child(p)
	p.play()


func _on_pile_clicked(pile_name: String) -> void:
	var popup = $DeckPreviewPopup
	if pile_name == "draw":
		popup.show_deck("抽牌堆", Game.draw_pile.duplicate())
	elif pile_name == "discard":
		popup.show_deck("弃牌堆", Game.discard_pile.duplicate())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			# ESC: 暂停菜单显隐切换 (打开时仅在合法状态下生效, 关闭时无条件允许)
			if _pause_overlay != null and is_instance_valid(_pause_overlay) and _pause_overlay.visible:
				_pause_overlay.close_menu()
				get_viewport().set_input_as_handled()
				return
			if _can_open_pause_menu():
				_pause_overlay.open_menu()
				get_viewport().set_input_as_handled()
				return
		if key == KEY_SPACE:
			if $ShopOverlay != null and $ShopOverlay.visible:
				return
			if $EndDialog != null and $EndDialog.visible:
				return
			if _pause_overlay != null and is_instance_valid(_pause_overlay) and _pause_overlay.visible:
				return
			if Game.tutorial_active:
				return
			if Game.is_level_over:
				return
			if Game.phase != Game.Phase.PLAY:
				return
			Game.end_turn()
			get_viewport().set_input_as_handled()


func _append_log(msg: String) -> void:
	if log_text == null:
		return
	var color := COL_TEXT_DIM
	if msg.begins_with("===="):
		color = COL_HIGHLIGHT
	elif msg.begins_with("---"):
		color = COL_GOLD
	elif msg.begins_with("[胜利]"):
		color = COL_UP
	elif msg.begins_with("[失败]"):
		color = COL_DOWN
	elif msg.begins_with("[庄家]"):
		color = COL_DOWN
	elif msg.begins_with("[强平]"):
		color = COL_UP
	log_text.push_color(color)
	log_text.add_text(msg)
	log_text.pop()
	log_text.newline()


func _relayout() -> void:
	var view_size: Vector2 = size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = get_viewport_rect().size
	view_size.x = max(view_size.x, MIN_WINDOW_SIZE.x)
	view_size.y = max(view_size.y, MIN_WINDOW_SIZE.y)

	_set_full_rect(bg)
	_set_full_rect(shop_overlay)
	_set_full_rect(deck_preview_popup)
	_set_full_rect(_tutorial_overlay)
	_set_full_rect(_day_settlement_overlay)
	_set_full_rect(_pause_overlay)
	_position_baoshu_tip_dialog()

	var content_w: float = view_size.x - OUTER_PAD * 2.0
	var top_y: float = OUTER_PAD
	# 在 TopBar 与中间内容之间为 SubtitleBanner 预留行高, 防止覆盖图表
	var middle_y: float = top_y + TOP_BAR_H + GAP + SUBTITLE_H
	var bottom_h: float = clamp(view_size.y * 0.283, BOTTOM_ROW_MIN_H, BOTTOM_ROW_H)
	var bottom_y: float = view_size.y - OUTER_PAD - bottom_h
	var action_y: float = bottom_y - GAP - ACTION_BAR_H
	var chart_h: float = max(140.0, action_y - GAP - middle_y)
	var side_h: float = max(180.0, bottom_y + 4.0 - middle_y)

	var data_w: float = clamp(view_size.x * DATA_PANEL_WIDTH_RATIO, DATA_PANEL_MIN_W, DATA_PANEL_MAX_W)
	var chart_x: float = OUTER_PAD + MONEY_BAR_W + GAP
	# PlayerTargetBar 贴右边, DataPanel 紧靠 PlayerTargetBar 左侧
	var player_target_x: float = view_size.x - OUTER_PAD - PLAYER_TARGET_BAR_W
	var data_x: float = player_target_x - GAP - data_w
	var chart_w: float = max(300.0, data_x - GAP - chart_x)

	_set_rect(top_bar, Rect2(OUTER_PAD, top_y, content_w, TOP_BAR_H))
	# EnemyHpBar / PlayerTargetBar / DataPanel 三者下边缘统一对齐 ActionBar 下沿 (= bottom_y - GAP).
	# 高度 bar_h = action_y + ACTION_BAR_H - middle_y, 与 DataPanel 同公式;
	# 这样资金条与下方 EnemyPanel/PlayerPanel 之间留出 GAP 间距, 视觉上头像与资金条自然分离.
	var bar_h: float = action_y + ACTION_BAR_H - middle_y
	_set_rect(enemy_hp_bar, Rect2(OUTER_PAD, middle_y, MONEY_BAR_W, bar_h))
	_set_rect(chart_panel, Rect2(chart_x, middle_y, chart_w, chart_h))
	# DataPanel 下边缘 = ActionBar 下边缘 (action_y + ACTION_BAR_H)
	var data_h: float = action_y + ACTION_BAR_H - middle_y
	_set_rect(data_panel, Rect2(data_x, middle_y, data_w, data_h))
	_set_rect(player_target_bar, Rect2(player_target_x, middle_y, PLAYER_TARGET_BAR_W, bar_h))
	_set_rect(action_bar, Rect2(chart_x, action_y, chart_w, ACTION_BAR_H))

	var fixed_bottom_w: float = ENEMY_W + TURN_W + PLAYER_W + GAP * 3.0
	var hand_w: float = max(300.0, content_w - fixed_bottom_w)
	var hand_x: float = OUTER_PAD + ENEMY_W + GAP
	var turn_x: float = hand_x + hand_w + GAP
	var player_x: float = turn_x + TURN_W + GAP

	_set_rect(enemy_panel, Rect2(OUTER_PAD, bottom_y, ENEMY_W, bottom_h))
	_set_rect(hand_panel, Rect2(hand_x, bottom_y, hand_w, bottom_h))
	_set_rect(turn_panel, Rect2(turn_x, bottom_y, TURN_W, bottom_h))
	_set_rect(player_panel, Rect2(player_x, bottom_y, PLAYER_W, bottom_h))

	var dialog_size: Vector2 = Vector2(
		min(END_DIALOG_SIZE.x, view_size.x - 96.0),
		min(END_DIALOG_SIZE.y, view_size.y - 96.0)
	)
	var dialog_pos: Vector2 = (view_size - dialog_size) * 0.5
	_set_rect(end_dialog, Rect2(dialog_pos, dialog_size))
	_position_opponent_popup()
	_position_subtitle_banner()


func _set_rect(ctrl: Control, rect: Rect2) -> void:
	if ctrl == null:
		return
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.position = rect.position
	ctrl.size = rect.size


func _set_full_rect(ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
