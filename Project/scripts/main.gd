extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const Event = preload("res://scripts/event.gd")
const CardChoiceDialog = preload("res://scripts/views/card_choice_dialog.gd")

@onready var log_text: RichTextLabel = $LogText
@onready var bg: ColorRect = $BG
@onready var top_bar: Control = $TopBar
@onready var enemy_hp_bar: Control = $EnemyHpBar
@onready var chart_panel: Control = $ChartPanel
@onready var data_panel: Control = $DataPanel
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

const MIN_WINDOW_SIZE: Vector2 = Vector2(960.0, 540.0)
const OUTER_PAD: float = 8.0
const GAP: float = 8.0
const TOP_BAR_H: float = 36.0
const MONEY_BAR_W: float = 56.0
const ACTION_BAR_H: float = 28.0
const BOTTOM_ROW_H: float = 204.0
const BOTTOM_ROW_MIN_H: float = 164.0
const ENEMY_W: float = 168.0
const TURN_W: float = 136.0
const PLAYER_W: float = 184.0
const DATA_PANEL_MIN_W: float = 300.0
const DATA_PANEL_WIDTH_RATIO: float = 0.29
const DATA_PANEL_MAX_W: float = 420.0
const END_DIALOG_SIZE: Vector2 = Vector2(512.0, 280.0)


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
	$PlayerPanel.pile_clicked.connect(_on_pile_clicked)
	$TurnPanel.pile_clicked.connect(_on_pile_clicked)
	Game.new_level()
	_start_bgm()


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

	var content_w: float = view_size.x - OUTER_PAD * 2.0
	var top_y: float = OUTER_PAD
	var middle_y: float = top_y + TOP_BAR_H + GAP
	var bottom_h: float = clamp(view_size.y * 0.283, BOTTOM_ROW_MIN_H, BOTTOM_ROW_H)
	var bottom_y: float = view_size.y - OUTER_PAD - bottom_h
	var action_y: float = bottom_y - GAP - ACTION_BAR_H
	var chart_h: float = max(160.0, action_y - GAP - middle_y)
	var side_h: float = max(200.0, bottom_y + 4.0 - middle_y)

	var data_w: float = clamp(view_size.x * DATA_PANEL_WIDTH_RATIO, DATA_PANEL_MIN_W, DATA_PANEL_MAX_W)
	var chart_x: float = OUTER_PAD + MONEY_BAR_W + GAP
	var data_x: float = view_size.x - OUTER_PAD - data_w
	var chart_w: float = max(300.0, data_x - GAP - chart_x)

	_set_rect(top_bar, Rect2(OUTER_PAD, top_y, content_w, TOP_BAR_H))
	_set_rect(enemy_hp_bar, Rect2(OUTER_PAD, middle_y, MONEY_BAR_W, side_h))
	_set_rect(chart_panel, Rect2(chart_x, middle_y, chart_w, chart_h))
	_set_rect(data_panel, Rect2(data_x, middle_y, data_w, side_h))
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
