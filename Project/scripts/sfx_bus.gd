# 全局 UI 点击音效总线 (autoload 名 SfxBus)
# 监听 SceneTree.node_added: 任何 Button 出现时, 自动接 pressed → _play_click()
# 排除卡牌按钮 (CardButton 脚本) 与显式声明 "no_click_sfx" group 的节点
extends Node

const CLICK_SFX_PATH := "res://assets/bgm/JDSherbert - Ultimate UI SFX Pack - Cursor - 1.mp3"
const CARD_HOVER_SFX_PATH := "res://assets/bgm/SFX_CardGrabSlide06.wav"
const CARD_DEAL_SFX_PATH := "res://assets/bgm/SFX_CardGenericMovesLong03.wav"
const CLICK_SFX_VOLUME_DB := -10.0
const CARD_HOVER_SFX_VOLUME_DB := -10.0
const CARD_DEAL_SFX_VOLUME_DB := -10.0
const CARD_BUTTON_SCRIPT_PATH := "res://scripts/views/card_button.gd"
const NO_CLICK_SFX_GROUP := "no_click_sfx"

var _click_stream: AudioStream = null
var _card_hover_stream: AudioStream = null
var _card_deal_stream: AudioStream = null
var _card_button_script: Script = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(CLICK_SFX_PATH):
		_click_stream = load(CLICK_SFX_PATH) as AudioStream
	if ResourceLoader.exists(CARD_HOVER_SFX_PATH):
		_card_hover_stream = load(CARD_HOVER_SFX_PATH) as AudioStream
	if ResourceLoader.exists(CARD_DEAL_SFX_PATH):
		_card_deal_stream = load(CARD_DEAL_SFX_PATH) as AudioStream
	if ResourceLoader.exists(CARD_BUTTON_SCRIPT_PATH):
		_card_button_script = load(CARD_BUTTON_SCRIPT_PATH) as Script
	get_tree().node_added.connect(_on_node_added)
	# 启动时已经在树里的节点也补一次扫描
	_scan_existing(get_tree().root)


func _scan_existing(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_scan_existing(c)


func _on_node_added(n: Node) -> void:
	if not (n is Button):
		return
	if _should_skip(n as Button):
		return
	var b := n as Button
	if not b.pressed.is_connected(_on_button_pressed):
		b.pressed.connect(_on_button_pressed)


func _should_skip(b: Button) -> bool:
	if b.is_in_group(NO_CLICK_SFX_GROUP):
		return true
	if _card_button_script != null:
		var s: Script = b.get_script() as Script
		while s != null:
			if s == _card_button_script:
				return true
			s = s.get_base_script()
	return false


func _on_button_pressed() -> void:
	play_click()


# 公共 API: 任何想手动触发一次 UI 点击音效的代码可以直接调
func play_click() -> void:
	_play_oneshot(_click_stream, CLICK_SFX_VOLUME_DB)


# 公共 API: 卡牌 hover 进入时调用一次
func play_card_hover() -> void:
	_play_oneshot(_card_hover_stream, CARD_HOVER_SFX_VOLUME_DB)


# 公共 API: 一次发牌动作 (一次/多次抽牌合并为一次播放)
func play_card_deal() -> void:
	_play_oneshot(_card_deal_stream, CARD_DEAL_SFX_VOLUME_DB)


func _play_oneshot(stream: AudioStream, volume_db: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.autoplay = false
	call_deferred("_attach_and_play", p)


func _attach_and_play(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not is_inside_tree():
		player.queue_free()
		return
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
