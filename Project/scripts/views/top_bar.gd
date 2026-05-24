extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const Event = preload("res://scripts/event.gd")

@onready var lbl_day: Label = $HBox/LblDay
@onready var lbl_turn: Label = $HBox/LblTurn
@onready var lbl_price: Label = $HBox/LblPrice
@onready var lbl_bull: Label = $HBox/LblBull
@onready var lbl_bear: Label = $HBox/LblBear
@onready var lbl_emotion_state: Label = $HBox/LblEmotionState
@onready var btn_event: Button = $HBox/BtnEvent

# 突发事件 UI 节点 (运行时创建)
var _event_dialog: AcceptDialog = null
var _event_tip: PanelContainer = null
var _tip_title: RichTextLabel = null
var _tip_desc: RichTextLabel = null
var _tip_effect: RichTextLabel = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.state_changed.connect(_refresh)
	Game.event_triggered.connect(_on_event_triggered)
	_setup_event_dialog()
	_setup_event_tip()
	btn_event.pressed.connect(_on_btn_event_pressed)
	btn_event.mouse_entered.connect(_on_btn_event_mouse_entered)
	btn_event.mouse_exited.connect(_on_btn_event_mouse_exited)
	_refresh_event_button()


func _refresh() -> void:
	lbl_day.text = "第 %d / %d 天 %s" % [max(Game.day, 1), Game.DAYS_PER_LEVEL, UF.weekday_name(Game.day)]
	lbl_turn.text = "第 %d / %d 回合" % [max(Game.turn_in_day, 1), Game.TURNS_PER_DAY]
	lbl_price.text = "¥%.2f" % Game.price
	lbl_bull.text = "上涨 %d" % Game.bull
	lbl_bear.text = "%d 下跌" % Game.bear
	lbl_emotion_state.text = "· " + Game.emotion_state()


# ============== 突发事件 UI ==============
func _setup_event_dialog() -> void:
	_event_dialog = AcceptDialog.new()
	_event_dialog.exclusive = false
	_event_dialog.get_ok_button().text = "知道了"
	_event_dialog.dialog_close_on_escape = true
	_event_dialog.size = Vector2i(420, 220)
	add_child(_event_dialog)


func _setup_event_tip() -> void:
	_event_tip = PanelContainer.new()
	_event_tip.top_level = true
	_event_tip.z_index = 100
	_event_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_tip.visible = false
	_event_tip.custom_minimum_size = Vector2(280, 0)
	var sb := UF.panel_stylebox(UF.COL_GOLD)
	_event_tip.add_theme_stylebox_override("panel", sb)
	add_child(_event_tip)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_event_tip.add_child(vbox)
	_tip_title = _make_rich(16)
	_tip_desc  = _make_rich(12)
	_tip_effect = _make_rich(12)
	vbox.add_child(_tip_title)
	vbox.add_child(_tip_desc)
	vbox.add_child(_tip_effect)


func _make_rich(font_size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(260, 0)
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_color_override("default_color", UF.COL_TEXT)
	return r


func _on_event_triggered(ev) -> void:
	_refresh_event_button()
	if ev == null:
		return
	# 弹窗
	var ev_obj: Event = ev as Event
	var cat_text := "中性"
	var cat_color := UF.COL_GOLD
	match ev_obj.category_str():
		"good":
			cat_text = "利好"
			cat_color = UF.COL_RED
		"bad":
			cat_text = "利空"
			cat_color = UF.COL_GREEN
		_:
			cat_text = "中性"
			cat_color = UF.COL_GOLD
	_event_dialog.title = "突发事件 · %s" % cat_text
	# 染色: 用 RichTextLabel 替换默认 message
	if _event_dialog.has_node("MsgRich"):
		_event_dialog.get_node("MsgRich").queue_free()
	var msg := RichTextLabel.new()
	msg.name = "MsgRich"
	msg.bbcode_enabled = true
	msg.fit_content = true
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(380, 100)
	msg.add_theme_font_size_override("normal_font_size", 14)
	msg.text = "[color=#%s][b]%s[/b][/color]\n\n%s\n\n[color=#ffd166]%s[/color]" % [
		cat_color.to_html(false), ev_obj.name, ev_obj.desc, ev_obj.effect_desc
	]
	_event_dialog.add_child(msg)
	_event_dialog.popup_centered()


func _refresh_event_button() -> void:
	var ev: Event = Game.current_event
	if ev == null:
		btn_event.text = "突发事件"
		btn_event.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
		return
	var col: Color = UF.COL_GOLD
	match ev.category_str():
		"good": col = UF.COL_RED
		"bad":  col = UF.COL_GREEN
		_:      col = UF.COL_GOLD
	btn_event.text = ev.name
	btn_event.add_theme_color_override("font_color", col)


func _on_btn_event_pressed() -> void:
	var ev: Event = Game.current_event
	if ev == null:
		return
	# 不重新弹窗 (避免重复展示), 只在事件刷新瞬间弹一次; 这里改为直接显示当前事件
	_event_dialog.title = "突发事件 · %s" % _category_name(ev)
	if _event_dialog.has_node("MsgRich"):
		_event_dialog.get_node("MsgRich").queue_free()
	var msg := RichTextLabel.new()
	msg.name = "MsgRich"
	msg.bbcode_enabled = true
	msg.fit_content = true
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(380, 100)
	msg.add_theme_font_size_override("normal_font_size", 14)
	var col := _category_color(ev)
	msg.text = "[color=#%s][b]%s[/b][/color]\n\n%s\n\n[color=#ffd166]%s[/color]" % [
		col.to_html(false), ev.name, ev.desc, ev.effect_desc
	]
	_event_dialog.add_child(msg)
	_event_dialog.popup_centered()


func _on_btn_event_mouse_entered() -> void:
	_update_tip_text()
	_event_tip.visible = true
	_position_tip_under(btn_event)


func _on_btn_event_mouse_exited() -> void:
	_event_tip.visible = false


func _update_tip_text() -> void:
	var ev: Event = Game.current_event
	if ev == null:
		_tip_title.text = "[color=#9aa7c0]暂无突发事件[/color]"
		_tip_desc.text = "[color=#9aa7c0]每天第 1 / 第 5 回合刷新[/color]"
		_tip_effect.text = ""
		return
	var col := _category_color(ev)
	var tag := _category_name(ev)
	_tip_title.text = "[color=#%s][b][%s] %s[/b][/color]" % [col.to_html(false), tag, ev.name]
	_tip_desc.text = "[color=#ffffff]%s[/color]" % ev.desc
	_tip_effect.text = "[color=#ffd166]%s[/color]" % ev.effect_desc


func _position_tip_under(target: Control) -> void:
	# 把 tip 显示在按钮下方 (top_level=true 时使用全局坐标)
	var rect := target.get_global_rect()
	# 先让它跑一帧布局, 拿真实 size
	_event_tip.reset_size()
	var tip_w: float = max(_event_tip.size.x, _event_tip.custom_minimum_size.x)
	var pos := Vector2(rect.position.x + rect.size.x - tip_w, rect.position.y + rect.size.y + 4)
	_event_tip.global_position = pos


func _category_color(ev: Event) -> Color:
	match ev.category_str():
		"good": return UF.COL_RED
		"bad":  return UF.COL_GREEN
		_:      return UF.COL_GOLD


func _category_name(ev: Event) -> String:
	match ev.category_str():
		"good": return "利好"
		"bad":  return "利空"
		_:      return "中性"