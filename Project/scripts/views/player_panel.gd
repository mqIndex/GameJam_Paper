extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_cash: Label = $VBox/LblCash
@onready var draw_pile_button: Button = $VBox/BottomRow/DrawPileButton
@onready var btn_deck: Button = $VBox/BottomRow/BtnDeck

signal pile_clicked(pile_name: String)


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	draw_pile_button.pressed.connect(_on_draw_pressed)
	Game.state_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	lbl_cash.text = "¥%s" % UF.fmt_money(Game.cash)
	draw_pile_button.set_count(Game.draw_pile.size())


func _on_draw_pressed() -> void:
	pile_clicked.emit("draw")
