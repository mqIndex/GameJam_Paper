extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const Event = preload("res://scripts/event.gd")
const CardChoiceDialog = preload("res://scripts/views/card_choice_dialog.gd")
const TutorialOverlayScene = preload("res://scenes/ui/tutorial_overlay.tscn")

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

var _choice_dialog: CardChoiceDialog = null
var _opponent_popup: PanelContainer = null
var _opponent_popup_title: Label = null
var _opponent_popup_body: Label = null
var _opponent_popup_tween: Tween = null
var _subtitle_banner: Label = null
var _tutorial_overlay: Control = null

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
	Game.opponent_entered.connect(_on_opponent_entered_popup)
	Game.opponent_defeated.connect(_on_opponent_defeated_for_tutorial)
	Game.shop_entered.connect(_on_shop_entered_for_tutorial)
	Game.day_started.connect(_on_day_started_for_tutorial)
	Game.level_started.connect(_on_level_started_for_tutorial)
	$PlayerPanel.pile_clicked.connect(_on_pile_clicked)
	$TurnPanel.pile_clicked.connect(_on_pile_clicked)
	var skip_tutorial: bool = _has_cmdline_flag("--skip-tutorial")
	if skip_tutorial:
		Game.finish_tutorial()
	var tutorial_should_start: bool = (not skip_tutorial) and Game.should_start_tutorial()
	Game.set_tutorial_active(tutorial_should_start)
	Game.new_level()
	if tutorial_should_start and _tutorial_overlay != null:
		_tutorial_overlay.call_deferred("start")
	_start_bgm()


func _has_cmdline_flag(flag: String) -> bool:
	for arg in OS.get_cmdline_args():
		if String(arg) == flag:
			return true
	for arg in OS.get_cmdline_user_args():
		if String(arg) == flag:
			return true
	return false


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
	_choice_dialog.show_card_single(
		"顺势而为",
		"选择 1 张要弃掉的手牌, 之后会抽 1 张。",
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
	_position_opponent_popup()


func _on_opponent_entered_popup(_opponent_id: String) -> void:
	if _opponent_popup == null:
		return
	var opp = Game.get_opponent_state()
	if opp == null:
		return
	_opponent_popup_title.text = "庄家入场 · %s" % opp.display_name
	_opponent_popup_body.text = "做空 %d 股 @ ¥%.2f\n爆仓线 ¥%.2f  现金 ¥%s" % [
		opp.short_position,
		opp.entry_avg_price,
		opp.liquidation_price,
		UF.fmt_money(opp.cash)
	]
	_position_opponent_popup()
	_opponent_popup.visible = true
	if _opponent_popup_tween != null and _opponent_popup_tween.is_valid():
		_opponent_popup_tween.kill()
	_opponent_popup.modulate = Color(1, 1, 1, 0)
	_opponent_popup_tween = create_tween()
	_opponent_popup_tween.tween_property(_opponent_popup, "modulate", Color(1, 1, 1, 1), 0.14)
	_opponent_popup_tween.tween_interval(OPPONENT_POPUP_DURATION)
	_opponent_popup_tween.tween_property(_opponent_popup, "modulate", Color(1, 1, 1, 0), 0.28)
	_opponent_popup_tween.tween_callback(_hide_opponent_popup)
	if Game.current_level_index > 0 and not Game.opponent_tutorial_completed and _tutorial_overlay != null:
		if _tutorial_overlay.has_method("start_opponent_intro"):
			_tutorial_overlay.call_deferred("start_opponent_intro")


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
	_opponent_popup.size = OPPONENT_POPUP_SIZE
	_opponent_popup.position = Vector2(
		(view_size.x - OPPONENT_POPUP_SIZE.x) * 0.5,
		max(64.0, (view_size.y - OPPONENT_POPUP_SIZE.y) * 0.34)
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
		if _tutorial_overlay.has_method("start_opponent_reward_intro"):
			_tutorial_overlay.call_deferred("start_opponent_reward_intro")


# 启动 BGM (循环, -6dB)
func _start_bgm() -> void:
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
		if (event as InputEventKey).keycode == KEY_SPACE:
			if $ShopOverlay != null and $ShopOverlay.visible:
				return
			if $EndDialog != null and $EndDialog.visible:
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
	_set_rect(enemy_hp_bar, Rect2(OUTER_PAD, middle_y, MONEY_BAR_W, side_h))
	_set_rect(chart_panel, Rect2(chart_x, middle_y, chart_w, chart_h))
	# DataPanel 下边缘 = ActionBar 下边缘 (action_y + ACTION_BAR_H)
	var data_h: float = action_y + ACTION_BAR_H - middle_y
	_set_rect(data_panel, Rect2(data_x, middle_y, data_w, data_h))
	_set_rect(player_target_bar, Rect2(player_target_x, middle_y, PLAYER_TARGET_BAR_W, side_h))
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
