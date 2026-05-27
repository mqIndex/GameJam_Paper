# TopBar — 拆分为 3 个独立 Bar
# LeftBar: 第 N/M 天 + 第 X/Y 回合 + 突发事件按钮
# MidBar: 市场情绪 (进度条 + 刻度) + 情绪状态文字
# RightBar: 已获取天赋小图标列表 + 暂停/播放/快进按钮
extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Event = preload("res://scripts/event.gd")
const EmotionMarker = preload("res://scripts/views/emotion_marker.gd")

@onready var left_bar: Panel = $LeftBar
@onready var mid_bar: Panel = $MidBar
@onready var right_bar: Panel = $RightBar

@onready var lbl_day: Label = $LeftBar/HBox/LblDay
@onready var lbl_turn: Label = $LeftBar/HBox/LblTurn
@onready var btn_event: Button = $LeftBar/HBox/BtnEvent

@onready var icon_emotion: Panel = $MidBar/HBox/IconEmotion
@onready var lbl_emotion_state: Label = $MidBar/HBox/LblEmotionState
@onready var emotion_bar_slot: Control = $MidBar/HBox/EmotionBarSlot

@onready var lbl_talent_title: Label = $RightBar/HBox/LblTalentTitle
@onready var talent_icons_slot: HBoxContainer = $RightBar/HBox/TalentIconsSlot

# 兼容旧 @onready (节点已隐藏到 $HBox 下, 保留赋值不报错)
@onready var lbl_price: Label = $HBox/LblPrice
@onready var lbl_bull: Label = $HBox/LblBull
@onready var lbl_bear: Label = $HBox/LblBear

# 突发事件 UI
var _event_dialog: AcceptDialog = null
var _event_msg: RichTextLabel = null
var _event_image: TextureRect = null
var _event_tip: PanelContainer = null
var _tip_title: RichTextLabel = null
var _tip_desc: RichTextLabel = null
var _tip_effect: RichTextLabel = null

# 情绪进度条 (运行时构建)
var _emotion_border: ColorRect = null
var _emotion_bg: ColorRect = null
var _emotion_fill: ColorRect = null
var _emotion_marker: Control = null      # EmotionMarker (Control + _draw)
var _emotion_marker_arrow: Polygon2D = null  # 兼容字段, 已弃用 (由 EmotionMarker 内部画)
var _emotion_segments: Array[ColorRect] = []
var _emotion_tick_labels: Array[Label] = []

# 天赋图标缓存 (slot_id → Panel)
var _talent_icon_nodes: Dictionary = {}

const EMOTION_BAR_HEIGHT: float = 14.0
const EMOTION_TICK_COUNT: int = 11  # 0/10/.../100
# 11 段色阶 (参考图: 左红→中金→右暗灰)
const EMOTION_SEGMENT_COLORS: Array[Color] = [
	Color("#d13434"),  # 0  极度悲观 红
	Color("#d44a2a"),
	Color("#d56a20"),
	Color("#dc8a1c"),
	Color("#e2a51a"),
	Color("#e6b218"),  # 5  中位 金
	Color("#cf9e1c"),
	Color("#a07a2a"),
	Color("#6a5b3a"),
	Color("#4d4742"),
	Color("#3a3540"),  # 10 极度乐观/冷静 暗灰
]


func _ready() -> void:
	left_bar.add_theme_stylebox_override("panel", UF.panel_stylebox())
	mid_bar.add_theme_stylebox_override("panel", UF.panel_stylebox())
	right_bar.add_theme_stylebox_override("panel", UF.panel_stylebox())
	_decorate_emotion_icon()
	_build_emotion_bar()
	Game.state_changed.connect(_refresh)
	Game.event_triggered.connect(_on_event_triggered)
	_setup_event_dialog()
	_setup_event_tip()
	btn_event.pressed.connect(_on_btn_event_pressed)
	btn_event.mouse_entered.connect(_on_btn_event_mouse_entered)
	btn_event.mouse_exited.connect(_on_btn_event_mouse_exited)
	resized.connect(_relayout_bars)
	_relayout_bars()
	_refresh_event_button()
	_refresh()


func _decorate_emotion_icon() -> void:
	if icon_emotion == null or icon_emotion.has_node("LblIcon"):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = UF.COL_NEON_RED
	sb.border_color = UF.COL_BG_DEEP
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	icon_emotion.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.name = "LblIcon"
	l.text = "!"
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UF.COL_BG_DEEP)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.anchor_bottom = 1.0
	icon_emotion.add_child(l)


func _build_emotion_bar() -> void:
	if _emotion_border != null:
		return
	# 外框 (兼容字段, 隐藏; 参考图无金色外框)
	_emotion_border = _new_rect(Color(0, 0, 0, 0), emotion_bar_slot)
	_emotion_border.visible = false
	# 内底深色
	_emotion_bg = _new_rect(Color("#1a1320"), emotion_bar_slot)
	# 11 段静态色块 (左红→中金→右暗灰)
	for i in range(EMOTION_SEGMENT_COLORS.size()):
		var seg := ColorRect.new()
		seg.color = EMOTION_SEGMENT_COLORS[i]
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		emotion_bar_slot.add_child(seg)
		_emotion_segments.append(seg)
	# 旧 fill 字段保留隐藏 (不再用大块彩色覆盖底部色阶)
	_emotion_fill = _new_rect(UF.COL_UP, emotion_bar_slot)
	_emotion_fill.visible = false
	# Marker (Control + _draw 画 1px 白竖线 + 顶部小三角)
	_emotion_marker = EmotionMarker.new()
	emotion_bar_slot.add_child(_emotion_marker)
	# 旧 11 段细竖线刻度已删除 (用 11 段色块底色替代)


func _label_tick(_tick: ColorRect) -> Label:
	# 占位: 没有文字刻度, 只有竖线; 返回空 Label 不挂避免污染
	var l := Label.new()
	l.visible = false
	return l


func _new_rect(c: Color, parent: Node) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _relayout_bars() -> void:
	# 3 个 bar 平分宽度: Left 24% / Mid 36% / Right 40% (右侧含天赋图标+控制按钮)
	var total_w: float = size.x
	var gap: float = 8.0
	var left_w: float = max(220.0, total_w * 0.24)
	var right_w: float = max(280.0, total_w * 0.40)
	var mid_w: float = max(220.0, total_w - left_w - right_w - gap * 2.0)
	left_bar.position = Vector2(0, 0)
	left_bar.size = Vector2(left_w, size.y)
	mid_bar.position = Vector2(left_w + gap, 0)
	mid_bar.size = Vector2(mid_w, size.y)
	right_bar.position = Vector2(left_w + gap + mid_w + gap, 0)
	right_bar.size = Vector2(right_w, size.y)
	_layout_emotion_bar()


func _layout_emotion_bar() -> void:
	if _emotion_border == null:
		return
	# 等下一帧 EmotionBarSlot 拿到真实 size (HBox 布局完成)
	await get_tree().process_frame
	if _emotion_border == null:
		return
	var slot_size: Vector2 = emotion_bar_slot.size
	if slot_size.x <= 0.0:
		return
	var bar_h: float = EMOTION_BAR_HEIGHT
	var bar_y: float = max(0.0, (slot_size.y - bar_h) * 0.5)
	# 内底 (深色)
	_emotion_bg.position = Vector2(0, bar_y)
	_emotion_bg.size = Vector2(slot_size.x, bar_h)
	# 11 段静态色块: 等分宽度, 段间留 1px 间隙 (像素感)
	var seg_gap: float = 1.0
	var total_gap: float = seg_gap * float(_emotion_segments.size() - 1)
	var seg_w: float = max(2.0, (slot_size.x - total_gap) / float(_emotion_segments.size()))
	for i in range(_emotion_segments.size()):
		var sx: float = float(i) * (seg_w + seg_gap)
		_emotion_segments[i].position = Vector2(sx, bar_y + 1.0)
		_emotion_segments[i].size = Vector2(seg_w, bar_h - 2.0)
	_refresh_emotion_bar()


func _refresh_emotion_bar() -> void:
	if _emotion_bg == null:
		return
	var bull: int = max(int(Game.bull), 0)
	var bear: int = max(int(Game.bear), 0)
	var total: int = max(1, bull + bear)
	var ratio: float = float(bull) / float(total)  # 0..1
	var bg_pos: Vector2 = _emotion_bg.position
	var bg_size: Vector2 = _emotion_bg.size
	# Marker (Control 自绘竖线 + 三角)
	if _emotion_marker != null:
		var mx: float = bg_pos.x + bg_size.x * ratio
		_emotion_marker.update_marker(mx, bg_pos.y, bg_size.y)


func _refresh() -> void:
	lbl_day.text = "第 %d / %d 天 %s" % [max(Game.day, 1), Game.DAYS_PER_LEVEL, UF.weekday_name(Game.day)]
	lbl_turn.text = "第 %d / %d 回合" % [max(Game.turn_in_day, 1), Game.TURNS_PER_DAY]
	# 兼容旧字段
	if lbl_price != null:
		lbl_price.text = "¥%.2f" % Game.price
	if lbl_bull != null:
		lbl_bull.text = "上涨 %d" % Game.bull
	if lbl_bear != null:
		lbl_bear.text = "%d 下跌" % Game.bear
	lbl_emotion_state.text = Game.emotion_state()
	_refresh_emotion_bar()
	_refresh_talent_icons()


# 根据 Game.owned_talents 同步显示天赋小图标; 新增的会自动 add_child, 已有的复用
func _refresh_talent_icons() -> void:
	if talent_icons_slot == null:
		return
	var current_ids: Dictionary = {}
	for t in Game.owned_talents:
		current_ids[t.id] = t
	# 移除已不存在的图标
	var to_remove: Array = []
	for tid in _talent_icon_nodes.keys():
		if not current_ids.has(tid):
			to_remove.append(tid)
	for tid in to_remove:
		var n: Node = _talent_icon_nodes[tid]
		if n != null and is_instance_valid(n):
			n.queue_free()
		_talent_icon_nodes.erase(tid)
	# 新增图标
	for tid in current_ids.keys():
		if _talent_icon_nodes.has(tid):
			continue
		var t = current_ids[tid]
		var icon := _make_talent_icon(t)
		talent_icons_slot.add_child(icon)
		_talent_icon_nodes[tid] = icon


func _make_talent_icon(t) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(24, 24)
	p.tooltip_text = "%s\n%s" % [t.name, t.description]
	var sb := StyleBoxFlat.new()
	# 按 effect_id hash 出一个颜色; 暂时统一霓虹紫 + 边
	sb.bg_color = Color(UF.COL_NEON_PURPLE.r * 0.4, UF.COL_NEON_PURPLE.g * 0.4, UF.COL_NEON_PURPLE.b * 0.55, 1.0)
	sb.border_color = UF.COL_NEON_PURPLE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	p.add_theme_stylebox_override("panel", sb)
	# 中央显示天赋名首字 (待美术补图标时换 TextureRect)
	var l := Label.new()
	l.text = (t.name as String).substr(0, 1) if t.name != "" else "?"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UF.COL_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.anchor_bottom = 1.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


# ============== 突发事件 UI ==============
# 事件配图已迁移到 DataPanel.MascotSlot 显示, 此弹窗只保留文字描述
func _setup_event_dialog() -> void:
	_event_dialog = AcceptDialog.new()
	_event_dialog.exclusive = false
	_event_dialog.get_ok_button().text = "知道了"
	_event_dialog.dialog_close_on_escape = true
	_event_dialog.size = Vector2i(420, 220)
	add_child(_event_dialog)
	_event_msg = RichTextLabel.new()
	_event_msg.name = "MsgRich"
	_event_msg.bbcode_enabled = true
	_event_msg.fit_content = true
	_event_msg.scroll_active = false
	_event_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_msg.custom_minimum_size = Vector2(380, 100)
	_event_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_msg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_msg.add_theme_font_size_override("normal_font_size", 14)
	_event_dialog.add_child(_event_msg)


# 兼容空实现: 图片显示已迁移到 DataPanel.MascotSlot, 此处保留方法防外部调用报错
func _apply_event_image(_image_path: String) -> void:
	pass


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
	if Game.tutorial_active:
		return
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
	_apply_event_image(ev_obj.image_path)
	_event_msg.text = "[color=#%s][b]%s[/b][/color]\n\n%s\n\n[color=#ffd166]%s[/color]" % [
		cat_color.to_html(false), ev_obj.name, ev_obj.desc, ev_obj.effect_desc
	]
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
	if Game.tutorial_active:
		return
	show_current_event_dialog()


# 公开方法: 外部 (如 DataPanel 的事件图片点击) 复用此弹窗显示当前事件详情
func show_current_event_dialog() -> void:
	var ev: Event = Game.current_event
	if ev == null:
		return
	_event_dialog.title = "突发事件 · %s" % _category_name(ev)
	var col := _category_color(ev)
	_apply_event_image(ev.image_path)
	_event_msg.text = "[color=#%s][b]%s[/b][/color]\n\n%s\n\n[color=#ffd166]%s[/color]" % [
		col.to_html(false), ev.name, ev.desc, ev.effect_desc
	]
	_event_dialog.popup_centered()


func _on_btn_event_mouse_entered() -> void:
	if Game.tutorial_active:
		return
	show_event_tip_for(btn_event)


func _on_btn_event_mouse_exited() -> void:
	hide_event_tip()


# 公开方法: 让外部 (如 DataPanel 的事件图片) 复用此 tip
func show_event_tip_for(anchor: Control) -> void:
	if _event_tip == null or anchor == null:
		return
	_update_tip_text()
	_event_tip.visible = true
	_position_tip_under(anchor)


func hide_event_tip() -> void:
	if _event_tip != null:
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
	var rect := target.get_global_rect()
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
