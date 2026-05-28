# TopBar — 拆分为 3 个独立 Bar
# LeftBar: 第 N/M 天 + 第 X/Y 回合
# MidBar: 市场情绪 (图标 + 进度条 + 状态文字)
# RightBar: 已获取天赋小图标列表 + 暂停/播放/快进按钮
extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Event = preload("res://scripts/event.gd")
const EmotionMarker = preload("res://scripts/views/emotion_marker.gd")
const CardHoverTooltip = preload("res://scripts/views/card_hover_tooltip.gd")

# 天赋 ID → logo 图片路径
const TALENT_ICON_MAP: Dictionary = {
	"cascade_combo": "res://data/talent/连携效应.png",
	"influence":     "res://data/talent/影响力.png",
}

# 市场情绪图标: 5 级 (bull 0-24→00, 25-49→25, 50-74→50, 75-99→75, 100→100)
const EMOTION_ICON_PATHS: Array[String] = [
	"res://assets/ui/enemy_hp_bar/00.png",
	"res://assets/ui/enemy_hp_bar/25.png",
	"res://assets/ui/enemy_hp_bar/50.png",
	"res://assets/ui/enemy_hp_bar/75.png",
	"res://assets/ui/enemy_hp_bar/100.png",
]
var _emotion_icons: Array[CompressedTexture2D] = []
var _last_emotion_icon_idx: int = -1

@onready var left_bar: Panel = $LeftBar
@onready var mid_bar: Panel = $MidBar
@onready var right_bar: Panel = $RightBar

@onready var lbl_day: Label = $LeftBar/HBox/LblDay
@onready var lbl_turn: Label = $LeftBar/HBox/LblTurn

@onready var icon_emotion: TextureRect = $MidBar/HBox/IconEmotion
@onready var lbl_emotion_state: Label = $MidBar/HBox/LblEmotionState
@onready var emotion_bar_slot: Control = $MidBar/HBox/EmotionBarSlot

@onready var lbl_talent_title: Label = $RightBar/HBox/LblTalentTitle
@onready var talent_icons_slot: HBoxContainer = $RightBar/HBox/TalentIconsSlot

# 兼容旧 @onready (节点已隐藏到 $HBox 下, 保留赋值不报错)
@onready var lbl_price: Label = $HBox/LblPrice
@onready var lbl_bull: Label = $HBox/LblBull
@onready var lbl_bear: Label = $HBox/LblBear

# 突发事件 tip / dialog (由 DataPanel 卡牌悬浮/点击调用)
var _event_dialog: AcceptDialog = null
var _event_msg: RichTextLabel = null
var _event_tip: PanelContainer = null
var _tip_title: RichTextLabel = null
var _tip_desc: RichTextLabel = null
var _tip_effect: RichTextLabel = null

# 市场情绪 hover tip (悬浮 MidBar 时展示)
var _emotion_tip: PanelContainer = null
var _emotion_tip_title: RichTextLabel = null
var _emotion_tip_value: RichTextLabel = null
var _emotion_tip_effect: RichTextLabel = null

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
var _talent_tooltip: PanelContainer = null
var _talent_tooltip_text: String = ""
var _talent_tooltip_tween: Tween = null

const EMOTION_BAR_HEIGHT: float = 14.0
const EMOTION_TICK_COUNT: int = 11  # 0/10/.../100
# 11 段色阶 (左暗灰→中金→右红, 与 marker ratio = bull/total 同向)
const EMOTION_SEGMENT_COLORS: Array[Color] = [
	Color("#3a3540"),  # 0  极度冷静/空头 暗灰
	Color("#4d4742"),
	Color("#6a5b3a"),
	Color("#a07a2a"),
	Color("#cf9e1c"),
	Color("#e6b218"),  # 5  中位 金
	Color("#e2a51a"),
	Color("#dc8a1c"),
	Color("#d56a20"),
	Color("#d44a2a"),
	Color("#d13434"),  # 10 极度狂热/多头 红
]


func _ready() -> void:
	set_process(false)
	left_bar.add_theme_stylebox_override("panel", UF.panel_stylebox())
	mid_bar.add_theme_stylebox_override("panel", UF.panel_stylebox())
	right_bar.add_theme_stylebox_override("panel", UF.panel_stylebox())
	_load_emotion_icons()
	_build_emotion_bar()
	_setup_event_dialog()
	_setup_event_tip()
	_setup_emotion_tip()
	mid_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	mid_bar.mouse_entered.connect(_on_emotion_mouse_entered)
	mid_bar.mouse_exited.connect(_on_emotion_mouse_exited)
	Game.state_changed.connect(_refresh)
	Game.event_triggered.connect(_on_event_triggered)
	resized.connect(_relayout_bars)
	# 插槽真正拿到宽度 (HBoxContainer 排版完成 / TopBar 由隐藏切回可见) 时, 重新摆 11 段色块
	emotion_bar_slot.resized.connect(_layout_emotion_bar)
	_relayout_bars()
	_refresh()


func _load_emotion_icons() -> void:
	for path in EMOTION_ICON_PATHS:
		var tex := load(path) as CompressedTexture2D
		if tex != null:
			_emotion_icons.append(tex)
		else:
			push_warning("TopBar: 无法加载情绪图标 %s" % path)
	# 设定初始图标
	if _emotion_icons.size() > 0:
		icon_emotion.texture = _emotion_icons[0]


func _refresh_emotion_icon() -> void:
	if _emotion_icons.is_empty():
		return
	var bull: int = max(int(Game.bull), 0)
	var idx: int
	if bull >= 100:
		idx = 4
	elif bull >= 75:
		idx = 3
	elif bull >= 50:
		idx = 2
	elif bull >= 25:
		idx = 1
	else:
		idx = 0
	if idx != _last_emotion_icon_idx:
		_last_emotion_icon_idx = idx
		icon_emotion.texture = _emotion_icons[idx]


func _build_emotion_bar() -> void:
	if _emotion_border != null:
		return
	# 外框 (兼容字段, 隐藏; 参考图无金色外框)
	_emotion_border = _new_rect(Color(0, 0, 0, 0), emotion_bar_slot)
	_emotion_border.visible = false
	# 内底深色
	_emotion_bg = _new_rect(Color("#1a1320"), emotion_bar_slot)
	# 11 段静态色块 (左暗灰→中金→右红)
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
	_refresh_emotion_icon()
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
			_hide_talent_tooltip()
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


func _make_talent_icon(t) -> TextureRect:
	var icon_path: String = TALENT_ICON_MAP.get(t.id, "")
	var p := TextureRect.new()
	p.custom_minimum_size = Vector2(24, 24)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.tooltip_text = ""
	p.set_meta("talent_id", t.id)
	p.set_meta("talent_tooltip", "天赋：%s\n%s" % [t.name, t.description])
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.mouse_entered.connect(_on_talent_icon_mouse_entered.bind(p))
	p.mouse_exited.connect(_on_talent_icon_mouse_exited)
	if icon_path != "":
		var tex = load(icon_path)
		if tex is Texture2D:
			p.texture = tex as Texture2D
		else:
			push_warning("TopBar: 无法加载天赋 logo %s" % icon_path)
	else:
		# 无 logo 的天赋: 仍然用文字首字 fallback
		var placeholder := Panel.new()
		placeholder.custom_minimum_size = Vector2(24, 24)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
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
		placeholder.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = (t.name as String).substr(0, 1) if t.name != "" else "?"
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", UF.COL_TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.anchor_right = 1.0
		l.anchor_bottom = 1.0
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		placeholder.add_child(l)
		p.add_child(placeholder)
	return p


func _on_talent_icon_mouse_entered(anchor: Control) -> void:
	if anchor == null:
		return
	_talent_tooltip_text = String(anchor.get_meta("talent_tooltip", ""))
	if _talent_tooltip_text == "":
		return
	_show_talent_tooltip()


func _on_talent_icon_mouse_exited() -> void:
	_hide_talent_tooltip()


func _show_talent_tooltip() -> void:
	if _talent_tooltip_text == "":
		return
	if _talent_tooltip == null:
		_talent_tooltip = CardHoverTooltip.create(_talent_tooltip_text)
		get_tree().root.add_child(_talent_tooltip)
	else:
		CardHoverTooltip.set_text(_talent_tooltip, _talent_tooltip_text)
	CardHoverTooltip.position_near_mouse(_talent_tooltip, get_viewport())
	_talent_tooltip.visible = true
	_talent_tooltip.modulate = Color(1, 1, 1, 0)
	if _talent_tooltip_tween != null and _talent_tooltip_tween.is_valid():
		_talent_tooltip_tween.kill()
	_talent_tooltip_tween = create_tween()
	_talent_tooltip_tween.tween_property(_talent_tooltip, "modulate:a", 1.0, 0.05)
	set_process(true)


func _hide_talent_tooltip() -> void:
	_talent_tooltip_text = ""
	set_process(false)
	if _talent_tooltip_tween != null and _talent_tooltip_tween.is_valid():
		_talent_tooltip_tween.kill()
	if _talent_tooltip != null:
		_talent_tooltip.visible = false


func _process(_delta: float) -> void:
	if _talent_tooltip != null and _talent_tooltip.visible:
		CardHoverTooltip.position_near_mouse(_talent_tooltip, get_viewport())
	else:
		set_process(false)


func _exit_tree() -> void:
	if _talent_tooltip != null:
		_talent_tooltip.queue_free()
		_talent_tooltip = null


# ============== 突发事件 tip / dialog (由 DataPanel 调用) ==============

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
	_event_msg.text = "[color=#%s][b]%s[/b][/color]\n\n%s\n\n[color=#ffd166]%s[/color]" % [
		cat_color.to_html(false), ev_obj.name, ev_obj.desc, ev_obj.effect_desc
	]
	_event_dialog.popup_centered()


# 公开方法: DataPanel 卡牌点击 → 弹出事件详情弹窗
func show_current_event_dialog() -> void:
	var ev: Event = Game.current_event
	if ev == null:
		return
	_event_dialog.title = "突发事件 · %s" % _category_name(ev)
	var col := _category_color(ev)
	_event_msg.text = "[color=#%s][b]%s[/b][/color]\n\n%s\n\n[color=#ffd166]%s[/color]" % [
		col.to_html(false), ev.name, ev.desc, ev.effect_desc
	]
	_event_dialog.popup_centered()


# 公开方法: DataPanel 卡牌悬浮 → 显示事件 tip
func show_event_tip_for(anchor: Control) -> void:
	if _event_tip == null or anchor == null:
		return
	_update_tip_text()
	_event_tip.visible = true
	_position_tip_under(anchor)


# 公开方法: DataPanel 卡牌离开 → 隐藏事件 tip
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


# ============== 市场情绪 hover tip ==============

func _setup_emotion_tip() -> void:
	_emotion_tip = PanelContainer.new()
	_emotion_tip.top_level = true
	_emotion_tip.z_index = 100
	_emotion_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emotion_tip.visible = false
	_emotion_tip.custom_minimum_size = Vector2(260, 0)
	_emotion_tip.add_theme_stylebox_override("panel", UF.panel_stylebox(UF.COL_GOLD))
	add_child(_emotion_tip)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_emotion_tip.add_child(vbox)
	_emotion_tip_title  = _make_rich(16)
	_emotion_tip_value  = _make_rich(12)
	_emotion_tip_effect = _make_rich(12)
	vbox.add_child(_emotion_tip_title)
	vbox.add_child(_emotion_tip_value)
	vbox.add_child(_emotion_tip_effect)


func _on_emotion_mouse_entered() -> void:
	if _emotion_tip == null:
		return
	_update_emotion_tip_text()
	_emotion_tip.visible = true
	_position_emotion_tip()


func _on_emotion_mouse_exited() -> void:
	if _emotion_tip != null:
		_emotion_tip.visible = false


func _update_emotion_tip_text() -> void:
	var bull: int = clampi(int(Game.bull), 0, 100)
	var bear: int = max(0, 100 - bull)
	var state_text: String = Game.emotion_state()
	var trend_text: String = ""
	var trend_col: Color = UF.COL_GOLD
	# 容易涨 / 容易跌 / 平稳: 与 _emotion_modifier_for_price 的阈值对齐
	if bull >= 70:
		trend_text = "容易上涨"
		trend_col = UF.COL_RED
	elif bull >= 50:
		trend_text = "略易上涨"
		trend_col = UF.COL_RED
	elif bull >= 30:
		trend_text = "略易下跌"
		trend_col = UF.COL_GREEN
	else:
		trend_text = "容易下跌"
		trend_col = UF.COL_GREEN
	if bull >= 45 and bull <= 55:
		trend_text = "走势平稳"
		trend_col = UF.COL_GOLD
	_emotion_tip_title.text = "[color=#%s][b]市场情绪 · %s[/b][/color]" % [
		UF.COL_GOLD.to_html(false), state_text
	]
	_emotion_tip_value.text = "[color=#ffffff]上涨 %d   ·   下跌 %d[/color]" % [bull, bear]
	_emotion_tip_effect.text = "[color=#%s]%s[/color]" % [trend_col.to_html(false), trend_text]


func _position_emotion_tip() -> void:
	if _emotion_tip == null or mid_bar == null:
		return
	var rect := mid_bar.get_global_rect()
	_emotion_tip.reset_size()
	var tip_w: float = max(_emotion_tip.size.x, _emotion_tip.custom_minimum_size.x)
	var pos := Vector2(rect.position.x + (rect.size.x - tip_w) * 0.5, rect.position.y + rect.size.y + 4)
	_emotion_tip.global_position = pos
