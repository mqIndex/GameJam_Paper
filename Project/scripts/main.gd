extends Control

@onready var log_text: RichTextLabel = $LogText

const COL_TEXT_DIM: Color = Color("#9aa7c0")
const COL_HIGHLIGHT: Color = Color("#ffae42")
const COL_GOLD: Color = Color("#ffd166")
const COL_UP: Color = Color("#06d6a0")
const COL_DOWN: Color = Color("#ef476f")


func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)
	Game.log_message.connect(_append_log)
	$HandPanel.pile_clicked.connect(_on_pile_clicked)
	Game.new_level()
	_start_bgm()


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
