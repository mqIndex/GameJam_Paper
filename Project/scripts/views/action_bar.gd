extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const ApIndicator = preload("res://scripts/views/ap_indicator.gd")

@onready var lbl_action_points: Label = $HBox/LblActionPoints

var _ap_indicator: HBoxContainer = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	_setup_ap_indicator()
	Game.state_changed.connect(_refresh)


func _setup_ap_indicator() -> void:
	var hbox: HBoxContainer = $HBox
	if hbox.has_node("ApIndicator"):
		_ap_indicator = hbox.get_node("ApIndicator") as HBoxContainer
	else:
		_ap_indicator = ApIndicator.new()
		_ap_indicator.name = "ApIndicator"
		hbox.add_child(_ap_indicator)
		hbox.move_child(_ap_indicator, lbl_action_points.get_index() + 1)
	_ap_indicator.set_max(Game.ACTION_POINTS_PER_TURN)
	_ap_indicator.set_active(Game.action_points)


func _refresh() -> void:
	lbl_action_points.text = "行动力 %d / %d" % [Game.action_points, Game.ACTION_POINTS_PER_TURN]
	lbl_action_points.add_theme_font_size_override("font_size", UF.FS_H2)
	if _ap_indicator != null:
		_ap_indicator.set_max(Game.ACTION_POINTS_PER_TURN)
		_ap_indicator.set_active(Game.action_points)
	var cap: int = max(Game.ACTION_POINTS_PER_TURN, 1)
	var ratio: float = float(Game.action_points) / float(cap)
	if ratio >= 0.75:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_NEON_ORANGE)
	elif ratio >= 0.50:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_GOLD)
	elif ratio > 0.0:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_DOWN)
	else:
		lbl_action_points.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
