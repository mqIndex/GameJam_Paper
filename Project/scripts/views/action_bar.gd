extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_action_points: Label = $HBox/LblActionPoints


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.state_changed.connect(_refresh)


func _refresh() -> void:
	lbl_action_points.text = "行动力 %d / %d   %s" % [Game.action_points, Game.ACTION_POINTS_PER_TURN, UF.ap_dots(Game.action_points, Game.ACTION_POINTS_PER_TURN)]
	if Game.action_points == Game.ACTION_POINTS_PER_TURN:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_AP_ON)
	elif Game.action_points == 0:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_DOWN)
	else:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_GOLD)
