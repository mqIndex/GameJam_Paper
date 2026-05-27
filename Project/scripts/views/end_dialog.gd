extends PanelContainer

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_title: Label = $Margin/VBox/LblTitle
@onready var lbl_detail: Label = $Margin/VBox/LblDetail
@onready var btn_restart: Button = $Margin/VBox/BtnRestart

var _continue_to_formal: bool = false


func _ready() -> void:
	btn_restart.add_theme_color_override("font_color", UF.COL_UP)
	var sb := UF.panel_stylebox(UF.COL_UP)
	btn_restart.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UF.COL_UP.r, UF.COL_UP.g, UF.COL_UP.b, 0.18)
	btn_restart.add_theme_stylebox_override("hover", hover)
	btn_restart.pressed.connect(_on_restart)
	Game.level_finished.connect(_on_level_finished)


func _on_level_finished(victory: bool, final_assets: float) -> void:
	_continue_to_formal = Game.current_level_index == 0 and victory
	if victory:
		lbl_title.text = "胜  利"
		lbl_title.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_title.text = "失  败"
		lbl_title.add_theme_color_override("font_color", UF.COL_DOWN)
	var extra: String = ""
	if Game.current_level_index == 0:
		extra = "\n\n%s" % ("宝叔：干得不错，年轻人大有前途。" if victory else "宝叔：山高路远，江湖再见。")
	lbl_detail.text = "最终资产: ¥%s\n胜利目标: ¥%s%s" % [UF.fmt_money(final_assets), UF.fmt_money(Game.VICTORY_TARGET), extra]
	btn_restart.text = "进入正式关" if _continue_to_formal else "再来一关"
	visible = true


func _on_restart() -> void:
	visible = false
	if _continue_to_formal and Game.has_method("start_formal_level_from_tutorial"):
		Game.call("start_formal_level_from_tutorial")
	elif Game.current_level_index == 0 and Game.has_method("restart_tutorial_level"):
		Game.call("restart_tutorial_level")
		var tutorial: Control = null
		if get_parent() != null:
			tutorial = get_parent().get_node_or_null("TutorialOverlay") as Control
		if tutorial != null and tutorial.has_method("start"):
			tutorial.call_deferred("start")
	else:
		Game.new_level()
