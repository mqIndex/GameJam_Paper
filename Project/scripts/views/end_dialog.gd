extends PanelContainer

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_title: Label = $Margin/VBox/LblTitle
@onready var lbl_detail: Label = $Margin/VBox/LblDetail
@onready var btn_restart: Button = $Margin/VBox/BtnRestart

# 存档身份小标签 (动态添加, 放在标题上方)
var _lbl_slot_info: Label = null

var _continue_to_next_level: bool = false


func _ready() -> void:
	btn_restart.add_theme_color_override("font_color", UF.COL_UP)
	var sb := UF.panel_stylebox(UF.COL_UP)
	btn_restart.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UF.COL_UP.r, UF.COL_UP.g, UF.COL_UP.b, 0.18)
	btn_restart.add_theme_stylebox_override("hover", hover)
	btn_restart.pressed.connect(_on_restart)
	_build_slot_info_label()
	Game.level_finished.connect(_on_level_finished)


# 在标题前插一行小字: "存档 N · 人格名 · 累计通关 X / Y"
func _build_slot_info_label() -> void:
	_lbl_slot_info = Label.new()
	_lbl_slot_info.name = "LblSlotInfo"
	_lbl_slot_info.add_theme_font_size_override("font_size", 13)
	_lbl_slot_info.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	_lbl_slot_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(_lbl_slot_info)
	vbox.move_child(_lbl_slot_info, 0)


func _refresh_slot_info() -> void:
	if _lbl_slot_info == null:
		return
	if Saves.active_slot_index < 0:
		_lbl_slot_info.text = "未选档 · 测试模式"
		return
	var persona_name: String = Saves.get_active_persona_name()
	var slot: Dictionary = Saves.get_active_slot()
	var max_cleared: int = int(slot.get("max_cleared_level_index", -1))
	# 累计通关 = max_cleared + 1 (含教学关); 全通关时显示"全通关"
	var cleared_count: int = max(0, max_cleared + 1)
	var progress: String
	if max_cleared >= Saves.TOTAL_LEVEL_COUNT - 1:
		progress = "全通关"
	else:
		progress = "累计通关 %d / %d" % [cleared_count, Saves.TOTAL_LEVEL_COUNT]
	_lbl_slot_info.text = "存档 %d · %s · %s" % [Saves.active_slot_index + 1, persona_name, progress]


func _on_level_finished(victory: bool, final_assets: float) -> void:
	_continue_to_next_level = victory and Game.has_next_level()
	_refresh_slot_info()
	if victory:
		lbl_title.text = "胜  利"
		lbl_title.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_title.text = "失  败"
		lbl_title.add_theme_color_override("font_color", UF.COL_DOWN)
	var extra: String = ""
	if Game.current_level_index == 0:
		extra = "\n\n%s" % ("宝叔：干得不错，年轻人大有前途。" if victory else "宝叔：山高路远，江湖再见。")
	elif victory and _continue_to_next_level:
		extra = "\n\n空头还没彻底认输，下一场会更凶。"
	elif victory:
		extra = "\n\n空头退场，盘面终于稳住了。"
	lbl_detail.text = "最终资产: ¥%s\n胜利目标: ¥%s%s" % [UF.fmt_money(final_assets), UF.fmt_money(Game.VICTORY_TARGET), extra]
	if _continue_to_next_level:
		btn_restart.text = "进入%s" % Game.get_next_level_name()
	else:
		btn_restart.text = "重新挑战" if victory else "再来一关"
	visible = true


func _on_restart() -> void:
	visible = false
	if _continue_to_next_level and Game.has_method("start_next_level_from_result"):
		Game.call("start_next_level_from_result")
	elif Game.current_level_index == 0 and Game.has_method("restart_tutorial_level"):
		Game.call("restart_tutorial_level")
		var tutorial: Control = null
		if get_parent() != null:
			tutorial = get_parent().get_node_or_null("TutorialOverlay") as Control
		if tutorial != null and tutorial.has_method("start"):
			tutorial.call_deferred("start")
	else:
		Game.new_level()
