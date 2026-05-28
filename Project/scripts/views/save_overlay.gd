# 启动存档页 (槽位列表 + 人格选择 + 全通关重玩选关 三阶段)
# 由 main.gd 实例化, 完成后发出 confirmed(slot_index, persona_id, is_new, start_level_override) 信号
# start_level_override: >=0 = 重玩选关时携带的关卡 index; -1 = 走默认 max_cleared+1
extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

signal confirmed(slot_index: int, persona_id: String, is_new: bool, start_level_override: int)

const SCRIM_COLOR := Color(0.02, 0.04, 0.09, 0.94)
const PANEL_COLOR := Color(0.05, 0.08, 0.14, 0.95)
const SLOT_SIZE := Vector2(260.0, 280.0)
const PERSONA_CARD_SIZE := Vector2(320.0, 460.0)
const REPLAY_CARD_SIZE := Vector2(220.0, 240.0)

enum Stage { SLOTS, PERSONA, REPLAY_LEVEL }

var _stage: int = Stage.SLOTS
var _pending_slot_index: int = -1
var _pending_delete_index: int = -1

var _bg: ColorRect = null
var _title: Label = null
var _hint: Label = null

# 槽位阶段
var _slots_panel: Control = null
var _slot_cards: Array = []   # [{root, title, status, persona_label, time_label, delete_btn}]

# 人格阶段
var _persona_panel: Control = null
var _persona_title: Label = null
var _persona_cards: Array = []  # [{root, btn, persona_id}]
var _back_btn: Button = null

# 重玩选关阶段 (全通关存档)
var _replay_panel: Control = null
var _replay_cards: Array = []   # [{root, btn, level_index}]
var _replay_back_btn: Button = null


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 350
	_build_bg()
	_build_slots_stage()
	_build_persona_stage()
	_build_replay_stage()
	resized.connect(_layout)
	_show_stage(Stage.SLOTS)
	_layout()


func _build_bg() -> void:
	_bg = ColorRect.new()
	_bg.name = "BG"
	_bg.color = SCRIM_COLOR
	_bg.mouse_filter = MOUSE_FILTER_STOP
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "传奇交易员 · 新乡 2000"
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", UF.COL_NEON_ORANGE)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 3)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "选择一个存档开始你的操盘人生"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


func _build_slots_stage() -> void:
	_slots_panel = Control.new()
	_slots_panel.name = "SlotsPanel"
	_slots_panel.mouse_filter = MOUSE_FILTER_IGNORE
	_slots_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_slots_panel)

	var hbox := HBoxContainer.new()
	hbox.name = "SlotsRow"
	hbox.add_theme_constant_override("separation", 24)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	_slots_panel.add_child(hbox)

	for i in range(Saves.SLOT_COUNT):
		var card := _build_slot_card(i)
		hbox.add_child(card["root"])
		_slot_cards.append(card)

	# 居中布局
	hbox.set_anchors_preset(Control.PRESET_CENTER)
	hbox.position = Vector2.ZERO
	hbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)


func _build_slot_card(index: int) -> Dictionary:
	var root := Panel.new()
	root.name = "Slot%d" % index
	root.custom_minimum_size = SLOT_SIZE
	root.mouse_filter = MOUSE_FILTER_STOP
	root.add_theme_stylebox_override("panel", _slot_stylebox(UF.COL_BORDER))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18.0
	vbox.offset_top = 18.0
	vbox.offset_right = -18.0
	vbox.offset_bottom = -18.0
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	root.add_child(vbox)

	var title_label := Label.new()
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", UF.COL_GOLD)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "存档 %d" % (index + 1)
	vbox.add_child(title_label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(140.0, 140.0)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(portrait)

	var persona_label := Label.new()
	persona_label.add_theme_font_size_override("font_size", 14)
	persona_label.add_theme_color_override("font_color", UF.COL_TEXT)
	persona_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(persona_label)

	var time_label := Label.new()
	time_label.add_theme_font_size_override("font_size", 11)
	time_label.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(time_label)

	var main_btn := Button.new()
	main_btn.add_theme_font_size_override("font_size", 16)
	main_btn.custom_minimum_size = Vector2(0.0, 36.0)
	main_btn.pressed.connect(_on_slot_pressed.bind(index))
	vbox.add_child(main_btn)

	var delete_btn := Button.new()
	delete_btn.text = "删除存档"
	delete_btn.add_theme_font_size_override("font_size", 11)
	delete_btn.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	delete_btn.flat = true
	delete_btn.pressed.connect(_on_delete_pressed.bind(index))
	vbox.add_child(delete_btn)

	return {
		"root": root,
		"portrait": portrait,
		"status": status_label,
		"persona": persona_label,
		"time": time_label,
		"main_btn": main_btn,
		"delete_btn": delete_btn,
	}


func _build_persona_stage() -> void:
	_persona_panel = Control.new()
	_persona_panel.name = "PersonaPanel"
	_persona_panel.mouse_filter = MOUSE_FILTER_IGNORE
	_persona_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_persona_panel.visible = false
	add_child(_persona_panel)

	_persona_title = Label.new()
	_persona_title.text = "选择你的市场人格"
	_persona_title.add_theme_font_size_override("font_size", 24)
	_persona_title.add_theme_color_override("font_color", UF.COL_NEON_ORANGE)
	_persona_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_persona_title.add_theme_constant_override("outline_size", 3)
	_persona_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_persona_panel.add_child(_persona_title)

	var cards_row := HBoxContainer.new()
	cards_row.name = "PersonaRow"
	cards_row.add_theme_constant_override("separation", 36)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.mouse_filter = MOUSE_FILTER_IGNORE
	_persona_panel.add_child(cards_row)

	for persona_id in Saves.get_persona_ids():
		var card := _build_persona_card(String(persona_id))
		cards_row.add_child(card["root"])
		_persona_cards.append(card)

	cards_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)

	_back_btn = Button.new()
	_back_btn.text = "返回"
	_back_btn.add_theme_font_size_override("font_size", 14)
	_back_btn.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	_back_btn.flat = true
	_back_btn.pressed.connect(_on_back_pressed)
	_persona_panel.add_child(_back_btn)


func _build_persona_card(persona_id: String) -> Dictionary:
	var data: Dictionary = Saves.get_persona(persona_id)
	var root := Panel.new()
	root.name = "PersonaCard_%s" % persona_id
	root.custom_minimum_size = PERSONA_CARD_SIZE
	root.mouse_filter = MOUSE_FILTER_STOP
	root.add_theme_stylebox_override("panel", _slot_stylebox(UF.COL_NEON_ORANGE))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20.0
	vbox.offset_top = 20.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -20.0
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	root.add_child(vbox)

	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(240.0, 260.0)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.texture = Saves.get_persona_portrait(persona_id)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(portrait)

	var name_label := Label.new()
	name_label.text = String(data.get("name", persona_id))
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", UF.COL_GOLD)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var btn := Button.new()
	btn.text = "选择 %s" % String(data.get("name", persona_id))
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(0.0, 40.0)
	btn.pressed.connect(_on_persona_pressed.bind(persona_id))
	vbox.add_child(btn)

	return {
		"root": root,
		"persona_id": persona_id,
		"btn": btn,
	}


# ---------- 重玩选关阶段 (全通关存档) ----------
func _build_replay_stage() -> void:
	_replay_panel = Control.new()
	_replay_panel.name = "ReplayPanel"
	_replay_panel.mouse_filter = MOUSE_FILTER_IGNORE
	_replay_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_replay_panel.visible = false
	add_child(_replay_panel)

	var cards_row := HBoxContainer.new()
	cards_row.name = "ReplayRow"
	cards_row.add_theme_constant_override("separation", 28)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.mouse_filter = MOUSE_FILTER_IGNORE
	_replay_panel.add_child(cards_row)

	for level_index in range(Saves.TOTAL_LEVEL_COUNT):
		var card := _build_replay_card(level_index)
		cards_row.add_child(card["root"])
		_replay_cards.append(card)

	cards_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)

	_replay_back_btn = Button.new()
	_replay_back_btn.text = "返回"
	_replay_back_btn.add_theme_font_size_override("font_size", 14)
	_replay_back_btn.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	_replay_back_btn.flat = true
	_replay_back_btn.pressed.connect(_on_replay_back_pressed)
	_replay_panel.add_child(_replay_back_btn)


func _build_replay_card(level_index: int) -> Dictionary:
	var root := Panel.new()
	root.name = "ReplayCard_%d" % level_index
	root.custom_minimum_size = REPLAY_CARD_SIZE
	root.mouse_filter = MOUSE_FILTER_STOP
	root.add_theme_stylebox_override("panel", _slot_stylebox(UF.COL_GOLD))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18.0
	vbox.offset_top = 18.0
	vbox.offset_right = -18.0
	vbox.offset_bottom = -18.0
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	root.add_child(vbox)

	var idx_label := Label.new()
	idx_label.text = "第 %d 关" % (level_index + 1)
	idx_label.add_theme_font_size_override("font_size", 14)
	idx_label.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(idx_label)

	var name_label := Label.new()
	name_label.text = Saves.get_level_name(level_index)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", UF.COL_GOLD)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = "重玩"
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(0.0, 40.0)
	btn.pressed.connect(_on_replay_level_pressed.bind(level_index))
	vbox.add_child(btn)

	return {
		"root": root,
		"btn": btn,
		"level_index": level_index,
	}


func _slot_stylebox(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(border.r, border.g, border.b, 0.32)
	sb.shadow_size = 8
	return sb


func _show_stage(stage: int) -> void:
	_stage = stage
	match stage:
		Stage.SLOTS:
			_title.text = "传奇交易员 · 新乡 2000"
			_hint.text = "选择一个存档开始你的操盘人生"
			_slots_panel.visible = true
			_persona_panel.visible = false
			_replay_panel.visible = false
			_refresh_slots()
		Stage.PERSONA:
			_title.text = "新人入职"
			_hint.text = "新手第一课: 决定你在市场上的人格"
			_slots_panel.visible = false
			_persona_panel.visible = true
			_replay_panel.visible = false
		Stage.REPLAY_LEVEL:
			_title.text = "再玩一次"
			_hint.text = "全通关存档 · 选一关重新挑战 (通关进度保留)"
			_slots_panel.visible = false
			_persona_panel.visible = false
			_replay_panel.visible = true
	_layout()


func _refresh_slots() -> void:
	for i in range(_slot_cards.size()):
		var card: Dictionary = _slot_cards[i]
		var empty: bool = Saves.is_slot_empty(i)
		var delete_btn: Button = card["delete_btn"] as Button
		if empty:
			card["status"].text = "空槽位"
			card["persona"].text = "——"
			card["time"].text = ""
			(card["portrait"] as TextureRect).texture = null
			(card["main_btn"] as Button).text = "新存档"
			delete_btn.visible = false
			_set_delete_btn_state(delete_btn, false)
		else:
			var slot: Dictionary = Saves.get_slot(i)
			var persona_id: String = String(slot.get("persona_id", ""))
			var persona_data: Dictionary = Saves.get_persona(persona_id)
			var progress: String = Saves.describe_slot_progress(i)
			card["status"].text = ("继续 · %s" % progress) if progress != "" else "继续游戏"
			card["persona"].text = String(persona_data.get("name", persona_id))
			card["time"].text = "上次 %s" % String(slot.get("played_at", ""))
			(card["portrait"] as TextureRect).texture = Saves.get_persona_portrait(persona_id)
			(card["main_btn"] as Button).text = _slot_main_btn_text(slot)
			delete_btn.visible = true
			_set_delete_btn_state(delete_btn, i == _pending_delete_index)


func _slot_main_btn_text(slot: Dictionary) -> String:
	var max_cleared: int = int(slot.get("max_cleared_level_index", -1))
	if max_cleared >= Saves.TOTAL_LEVEL_COUNT - 1:
		return "再玩一次"
	var next_level: int = max_cleared + 1
	return "进入 %s" % Saves.get_level_name(next_level)


func _set_delete_btn_state(btn: Button, pending: bool) -> void:
	if pending:
		btn.text = "再点一次确认删除"
		btn.add_theme_color_override("font_color", Color(0.95, 0.32, 0.32))
	else:
		btn.text = "删除存档"
		btn.add_theme_color_override("font_color", UF.COL_TEXT_DIM)


func _on_slot_pressed(index: int) -> void:
	# 进任何槽位前清掉别处的删除确认态
	if _pending_delete_index != -1 and _pending_delete_index != index:
		_pending_delete_index = -1
		_refresh_slots()
	if Saves.is_slot_empty(index):
		_pending_slot_index = index
		_show_stage(Stage.PERSONA)
		return
	var slot: Dictionary = Saves.get_slot(index)
	var max_cleared: int = int(slot.get("max_cleared_level_index", -1))
	if max_cleared >= Saves.TOTAL_LEVEL_COUNT - 1:
		# 全通关存档 → 进入"重玩选关"阶段, 不直接续档
		_pending_slot_index = index
		_show_stage(Stage.REPLAY_LEVEL)
		return
	Saves.touch_slot(index)
	_finish(index, String(slot.get("persona_id", "")), false, -1)


func _on_delete_pressed(index: int) -> void:
	if _pending_delete_index != index:
		_pending_delete_index = index
		_refresh_slots()
		return
	_pending_delete_index = -1
	Saves.delete_slot(index)
	_refresh_slots()


func _on_persona_pressed(persona_id: String) -> void:
	if _pending_slot_index < 0:
		return
	var idx: int = _pending_slot_index
	Saves.create_slot(idx, persona_id)
	_finish(idx, persona_id, true, -1)


func _on_back_pressed() -> void:
	_pending_slot_index = -1
	_show_stage(Stage.SLOTS)


func _on_replay_level_pressed(level_index: int) -> void:
	if _pending_slot_index < 0:
		return
	var idx: int = _pending_slot_index
	Saves.touch_slot(idx)
	var persona_id: String = String(Saves.get_slot(idx).get("persona_id", ""))
	_finish(idx, persona_id, false, level_index)


func _on_replay_back_pressed() -> void:
	_pending_slot_index = -1
	_show_stage(Stage.SLOTS)


func _finish(slot_index: int, persona_id: String, is_new: bool, start_level_override: int = -1) -> void:
	visible = false
	confirmed.emit(slot_index, persona_id, is_new, start_level_override)


func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = get_viewport_rect().size
	_bg.position = Vector2.ZERO
	_bg.size = view

	var title_h: float = 40.0
	var hint_h: float = 22.0
	_title.size = Vector2(view.x, title_h)
	_title.position = Vector2(0.0, max(48.0, view.y * 0.12))
	_hint.size = Vector2(view.x, hint_h)
	_hint.position = Vector2(0.0, _title.position.y + title_h + 4.0)

	if _slots_panel.visible:
		var row: HBoxContainer = _slots_panel.get_node("SlotsRow") as HBoxContainer
		var row_size: Vector2 = row.size
		if row_size == Vector2.ZERO:
			row_size = Vector2(SLOT_SIZE.x * 3.0 + 48.0, SLOT_SIZE.y)
		row.position = Vector2(
			(view.x - row_size.x) * 0.5,
			max(140.0, (view.y - row_size.y) * 0.5)
		)

	if _persona_panel.visible:
		var prow: HBoxContainer = _persona_panel.get_node("PersonaRow") as HBoxContainer
		var prow_size: Vector2 = prow.size
		if prow_size == Vector2.ZERO:
			prow_size = Vector2(PERSONA_CARD_SIZE.x * Saves.get_persona_ids().size() + 36.0, PERSONA_CARD_SIZE.y)
		prow.position = Vector2(
			(view.x - prow_size.x) * 0.5,
			max(120.0, (view.y - prow_size.y) * 0.5)
		)
		if _back_btn != null:
			_back_btn.size = Vector2(120.0, 32.0)
			_back_btn.position = Vector2(view.x - 140.0, view.y - 56.0)

	if _replay_panel.visible:
		var rrow: HBoxContainer = _replay_panel.get_node("ReplayRow") as HBoxContainer
		var rrow_size: Vector2 = rrow.size
		if rrow_size == Vector2.ZERO:
			var gap_total: float = 28.0 * float(max(0, Saves.TOTAL_LEVEL_COUNT - 1))
			rrow_size = Vector2(REPLAY_CARD_SIZE.x * float(Saves.TOTAL_LEVEL_COUNT) + gap_total, REPLAY_CARD_SIZE.y)
		rrow.position = Vector2(
			(view.x - rrow_size.x) * 0.5,
			max(140.0, (view.y - rrow_size.y) * 0.5)
		)
		if _replay_back_btn != null:
			_replay_back_btn.size = Vector2(120.0, 32.0)
			_replay_back_btn.position = Vector2(view.x - 140.0, view.y - 56.0)