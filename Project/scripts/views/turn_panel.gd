extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var btn_end_turn: Button = $VBox/BtnEndTurn


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	var sb := UF.panel_stylebox(UF.COL_HIGHLIGHT)
	btn_end_turn.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UF.COL_HIGHLIGHT.r, UF.COL_HIGHLIGHT.g, UF.COL_HIGHLIGHT.b, 0.18)
	btn_end_turn.add_theme_stylebox_override("hover", hover)
	btn_end_turn.add_theme_color_override("font_color", UF.COL_HIGHLIGHT)
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	Game.state_changed.connect(_refresh)


func _on_end_turn_pressed() -> void:
	Game.end_turn()


func _refresh() -> void:
	btn_end_turn.disabled = Game.is_level_over or Game.phase != Game.Phase.PLAY
