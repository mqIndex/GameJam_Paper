extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_action_points: Label = $HBox/LblActionPoints


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.state_changed.connect(_refresh)


func _refresh() -> void:
	lbl_action_points.text = "行动力 %d / %d   %s" % [Game.action_points, Game.ACTION_POINTS_PER_TURN, UF.ap_dots(Game.action_points, Game.ACTION_POINTS_PER_TURN)]
	var cap: int = max(Game.ACTION_POINTS_PER_TURN, 1)
	var ratio: float = float(Game.action_points) / float(cap)
	if ratio >= 0.75:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_AP_ON)
	elif ratio >= 0.50:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_GOLD)
	elif ratio > 0.0:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_DOWN)
	else:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_TEXT_DIM)