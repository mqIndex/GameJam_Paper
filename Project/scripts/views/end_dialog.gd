extends PanelContainer

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_title: Label = $Margin/VBox/LblTitle
@onready var lbl_detail: Label = $Margin/VBox/LblDetail
@onready var btn_restart: Button = $Margin/VBox/BtnRestart


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
	if victory:
		lbl_title.text = "胜  利"
		lbl_title.add_theme_color_override("font_color", UF.COL_UP)
	else:
		lbl_title.text = "失  败"
		lbl_title.add_theme_color_override("font_color", UF.COL_DOWN)
	lbl_detail.text = "最终资产: ¥%s\n胜利目标: ¥%s" % [UF.fmt_money(final_assets), UF.fmt_money(Game.VICTORY_TARGET)]
	visible = true


func _on_restart() -> void:
	visible = false
	Game.new_level()
