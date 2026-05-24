extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_cash: Label = $VBox/LblCash


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.state_changed.connect(_refresh)


func _refresh() -> void:
	lbl_cash.text = "¥%s" % UF.fmt_money(Game.cash)
