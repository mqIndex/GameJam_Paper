extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var marker: ColorRect = $Marker

const BAR_TOP_Y: float = 20.0
const BAR_HEIGHT: float = 432.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.state_changed.connect(_refresh)


func _refresh() -> void:
	var ratio: float = clamp(Game.cash / (Game.START_CASH * 2.0), 0.0, 1.0)
	marker.position.y = BAR_TOP_Y + (1.0 - ratio) * BAR_HEIGHT - 1.0
