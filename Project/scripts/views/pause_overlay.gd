# ESC 暂停菜单 (overlay)
# 由 main.gd 实例化, 主循环外层覆盖; 按 ESC 切显隐
# 信号:
#   resume_requested      - 玩家点"继续游戏"
#   switch_slot_requested - 玩家点"返回标题/切换存档"
#   quit_requested        - 玩家点"退出游戏"
extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

signal resume_requested
signal switch_slot_requested
signal quit_requested

const SCRIM_COLOR := Color(0.02, 0.04, 0.09, 0.78)
const PANEL_COLOR := Color(0.05, 0.08, 0.14, 0.96)
const PANEL_SIZE := Vector2(360.0, 320.0)

var _bg: ColorRect = null
var _panel: Panel = null
var _title: Label = null
var _slot_info: Label = null
var _btn_resume: Button = null
var _btn_switch: Button = null
var _btn_switch_confirm_pending: bool = false
var _btn_quit: Button = null


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 400
	_build_bg()
	_build_panel()
	resized.connect(_layout)
	visible = false
	_layout()


func open_menu() -> void:
	_btn_switch_confirm_pending = false
	_set_switch_btn_state(false)
	_refresh_slot_info()
	visible = true
	_layout()


func close_menu() -> void:
	visible = false
	_btn_switch_confirm_pending = false
	_set_switch_btn_state(false)


func _build_bg() -> void:
	_bg = ColorRect.new()
	_bg.name = "BG"
	_bg.color = SCRIM_COLOR
	_bg.mouse_filter = MOUSE_FILTER_STOP
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)


func _build_panel() -> void:
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.mouse_filter = MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 28.0
	vbox.offset_top = 28.0
	vbox.offset_right = -28.0
	vbox.offset_bottom = -28.0
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_title = Label.new()
	_title.text = "暂停"
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", UF.COL_NEON_ORANGE)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 3)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	_slot_info = Label.new()
	_slot_info.add_theme_font_size_override("font_size", 13)
	_slot_info.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	_slot_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_slot_info)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 12.0)
	vbox.add_child(spacer)

	_btn_resume = Button.new()
	_btn_resume.text = "继续游戏 (ESC)"
	_btn_resume.add_theme_font_size_override("font_size", 16)
	_btn_resume.custom_minimum_size = Vector2(0.0, 40.0)
	_btn_resume.pressed.connect(_on_resume_pressed)
	vbox.add_child(_btn_resume)

	_btn_switch = Button.new()
	_btn_switch.add_theme_font_size_override("font_size", 16)
	_btn_switch.custom_minimum_size = Vector2(0.0, 40.0)
	_btn_switch.pressed.connect(_on_switch_pressed)
	vbox.add_child(_btn_switch)
	_set_switch_btn_state(false)

	_btn_quit = Button.new()
	_btn_quit.text = "退出游戏"
	_btn_quit.add_theme_font_size_override("font_size", 14)
	_btn_quit.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	_btn_quit.flat = true
	_btn_quit.custom_minimum_size = Vector2(0.0, 32.0)
	_btn_quit.pressed.connect(_on_quit_pressed)
	vbox.add_child(_btn_quit)


func _refresh_slot_info() -> void:
	if _slot_info == null:
		return
	if Saves.active_slot_index < 0:
		_slot_info.text = "未选档 · 测试模式"
		return
	var persona_name: String = Saves.get_active_persona_name()
	var slot: Dictionary = Saves.get_active_slot()
	var max_cleared: int = int(slot.get("max_cleared_level_index", -1))
	var progress: String
	if max_cleared >= Saves.TOTAL_LEVEL_COUNT - 1:
		progress = "全通关"
	else:
		progress = "累计通关 %d / %d" % [max(0, max_cleared + 1), Saves.TOTAL_LEVEL_COUNT]
	_slot_info.text = "存档 %d · %s · %s" % [Saves.active_slot_index + 1, persona_name, progress]


func _set_switch_btn_state(pending: bool) -> void:
	if _btn_switch == null:
		return
	if pending:
		_btn_switch.text = "再点一次确认 · 当前关进度会丢失"
		_btn_switch.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
	else:
		_btn_switch.text = "返回标题 / 切换存档"
		_btn_switch.add_theme_color_override("font_color", UF.COL_TEXT)


func _on_resume_pressed() -> void:
	close_menu()
	resume_requested.emit()


func _on_switch_pressed() -> void:
	# 二次确认: 第一次变红色提示, 第二次才真正切档 (避免误点丢进度)
	if not _btn_switch_confirm_pending:
		_btn_switch_confirm_pending = true
		_set_switch_btn_state(true)
		return
	_btn_switch_confirm_pending = false
	_set_switch_btn_state(false)
	switch_slot_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.border_color = UF.COL_NEON_ORANGE
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_color = Color(UF.COL_NEON_ORANGE.r, UF.COL_NEON_ORANGE.g, UF.COL_NEON_ORANGE.b, 0.32)
	sb.shadow_size = 12
	return sb


func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = get_viewport_rect().size
	_bg.position = Vector2.ZERO
	_bg.size = view
	if _panel != null:
		_panel.size = PANEL_SIZE
		_panel.position = (view - PANEL_SIZE) * 0.5