extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const Event = preload("res://scripts/event.gd")
const CardChoiceDialog = preload("res://scripts/views/card_choice_dialog.gd")

@onready var log_text: RichTextLabel = $LogText

const COL_TEXT_DIM: Color = Color("#9aa7c0")
const COL_HIGHLIGHT: Color = Color("#ffae42")
const COL_GOLD: Color = Color("#ffd166")
const COL_UP: Color = Color("#06d6a0")
const COL_DOWN: Color = Color("#ef476f")

var _choice_dialog: CardChoiceDialog = null


func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)
	Game.log_message.connect(_append_log)
	$HandPanel.pile_clicked.connect(_on_pile_clicked)
	_setup_choice_dialog()
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
	log_text.push_color(color)
	log_text.add_text(msg)
	log_text.pop()
	log_text.newline()
