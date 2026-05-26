extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const ApIndicator = preload("res://scripts/views/ap_indicator.gd")

@onready var lbl_action_points: Label = $HBox/LblActionPoints

var _ap_indicator: HBoxContainer = null
var _lbl_cash: Label = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	_setup_ap_indicator()
	_setup_cash_label()
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


func _setup_cash_label() -> void:
	# 在行动力圆点右侧挂一个现金 Label, 显示 "现金 ¥xxx"
	var hbox: HBoxContainer = $HBox
	if hbox.has_node("LblCash"):
		_lbl_cash = hbox.get_node("LblCash") as Label
	else:
		_lbl_cash = Label.new()
		_lbl_cash.name = "LblCash"
		_lbl_cash.add_theme_font_size_override("font_size", UF.FS_H2)
		_lbl_cash.add_theme_color_override("font_color", UF.COL_GOLD)
		hbox.add_child(_lbl_cash)
		# 紧挨 ApIndicator 之后
		if _ap_indicator != null:
			hbox.move_child(_lbl_cash, _ap_indicator.get_index() + 1)


func _refresh() -> void:
	lbl_action_points.text = "行动力 %d / %d" % [Game.action_points, Game.ACTION_POINTS_PER_TURN]
	lbl_action_points.add_theme_font_size_override("font_size", UF.FS_H2)
	if _ap_indicator != null:
		_ap_indicator.set_max(Game.ACTION_POINTS_PER_TURN)
		_ap_indicator.set_active(Game.action_points)
	if _lbl_cash != null:
		_lbl_cash.text = "现金 ¥%s" % UF.fmt_money(Game.cash)
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
