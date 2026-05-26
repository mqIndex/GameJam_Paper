extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_cash: Label = $VBox/LblCash
@onready var draw_pile_button: Button = $VBox/BottomRow/DrawPileButton
@onready var btn_deck: Button = $VBox/BottomRow/BtnDeck

signal pile_clicked(pile_name: String)


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox(UF.COL_NEON_ORANGE))
	_decorate_avatar_slot(UF.COL_NEON_ORANGE)
	lbl_cash.add_theme_font_size_override("font_size", UF.FS_H1)
	lbl_cash.add_theme_color_override("font_color", UF.COL_GOLD)
	draw_pile_button.pressed.connect(_on_draw_pressed)
	Game.state_changed.connect(_refresh)
	_refresh()


func _decorate_avatar_slot(border: Color) -> void:
	var slot: CenterContainer = $VBox/AvatarSlot
	if slot == null or slot.has_node("AvatarDeco"):
		return
	var deco := Panel.new()
	deco.name = "AvatarDeco"
	deco.show_behind_parent = true
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.add_theme_stylebox_override("panel", UF.neon_panel_stylebox(border))
	slot.add_child(deco)
	slot.move_child(deco, 0)
	deco.anchor_right = 1.0
	deco.anchor_bottom = 1.0
	deco.offset_left = -2.0
	deco.offset_top = -2.0
	deco.offset_right = 2.0
	deco.offset_bottom = 2.0


func _refresh() -> void:
	lbl_cash.text = "¥%s" % UF.fmt_money(Game.cash)
	draw_pile_button.set_count(Game.draw_pile.size())


func _on_draw_pressed() -> void:
	pile_clicked.emit("draw")
