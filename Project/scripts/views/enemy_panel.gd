extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
