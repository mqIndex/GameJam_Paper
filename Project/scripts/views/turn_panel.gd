extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var btn_end_turn: Button = $VBox/BtnEndTurn
@onready var discard_pile_button: Button = $VBox/DiscardPileSlot/DiscardPileButton
@onready var btn_undo_turn: Button = $VBox/BtnUndoTurn

signal pile_clicked(pile_name: String)


func _ready() -> void:
	# 面板背景: 用默认 StyleBoxFlat 纯色; 不接入 panel_neon_default.png
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	# 结束回合按钮: 用纯色 StyleBoxFlat (霓虹橙), 不接入 btn_end_turn.png
	var sb := UF.neon_button_stylebox(UF.COL_NEON_ORANGE)
	btn_end_turn.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UF.COL_NEON_ORANGE.r * 0.95, UF.COL_NEON_ORANGE.g * 0.65, UF.COL_NEON_ORANGE.b * 0.35, 1.0)
	btn_end_turn.add_theme_stylebox_override("hover", hover)
	var pressed_sb := sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = Color(UF.COL_NEON_ORANGE.r * 0.7, UF.COL_NEON_ORANGE.g * 0.4, UF.COL_NEON_ORANGE.b * 0.2, 1.0)
	btn_end_turn.add_theme_stylebox_override("pressed", pressed_sb)
	var disabled_sb := UF.panel_stylebox(UF.COL_AP_OFF)
	btn_end_turn.add_theme_stylebox_override("disabled", disabled_sb)
	btn_end_turn.add_theme_color_override("font_color", UF.COL_TEXT)
	btn_end_turn.add_theme_font_size_override("font_size", UF.FS_H1)
	btn_end_turn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	btn_end_turn.add_theme_constant_override("outline_size", 2)
	_style_undo_button()
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	btn_undo_turn.pressed.connect(_on_undo_turn_pressed)
	discard_pile_button.pressed.connect(_on_discard_pressed)
	Game.state_changed.connect(_refresh)
	_refresh()


func _on_end_turn_pressed() -> void:
	Game.end_turn()


func _on_undo_turn_pressed() -> void:
	Game.undo_current_turn()


func _on_discard_pressed() -> void:
	pile_clicked.emit("discard")


func _refresh() -> void:
	btn_end_turn.disabled = Game.is_level_over or Game.phase != Game.Phase.PLAY
	btn_undo_turn.disabled = not Game.can_undo_current_turn()
	btn_undo_turn.text = "已撤回" if Game.is_turn_undo_used() else "撤回本回合"
	discard_pile_button.set_count(Game.discard_pile.size())


func _style_undo_button() -> void:
	var sb := UF.neon_button_stylebox(UF.COL_NEON_CYAN)
	btn_undo_turn.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UF.COL_NEON_CYAN.r * 0.7, UF.COL_NEON_CYAN.g * 0.5, UF.COL_NEON_CYAN.b * 0.45, 1.0)
	btn_undo_turn.add_theme_stylebox_override("hover", hover)
	var pressed_sb := sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = Color(UF.COL_NEON_CYAN.r * 0.45, UF.COL_NEON_CYAN.g * 0.34, UF.COL_NEON_CYAN.b * 0.35, 1.0)
	btn_undo_turn.add_theme_stylebox_override("pressed", pressed_sb)
	var disabled_sb := UF.panel_stylebox(UF.COL_AP_OFF)
	btn_undo_turn.add_theme_stylebox_override("disabled", disabled_sb)
	btn_undo_turn.add_theme_color_override("font_color", UF.COL_TEXT)
	btn_undo_turn.add_theme_font_size_override("font_size", UF.FS_BODY)
