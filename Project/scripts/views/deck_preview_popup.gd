extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const ShopCardScene = preload("res://scenes/ui/shop/shop_card.tscn")

@onready var grid: GridContainer = $Panel/Margin/VBox/ScrollContainer/Grid
@onready var lbl_count: Label = $Panel/Margin/VBox/TopBar/LblCount
@onready var lbl_title: Label = $Panel/Margin/VBox/TopBar/LblTitle
@onready var btn_close: Button = $Panel/Margin/VBox/TopBar/BtnClose
@onready var dim: ColorRect = $Dim


func _ready() -> void:
	btn_close.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	btn_close.add_theme_stylebox_override("normal", UF.panel_stylebox(UF.COL_TEXT_DIM))
	btn_close.pressed.connect(hide_popup)
	dim.gui_input.connect(_on_dim_input)


func show_deck(title: String, cards: Array) -> void:
	lbl_title.text = title
	lbl_count.text = "  共 %d 张" % cards.size()
	for c in grid.get_children():
		c.queue_free()
	for card in cards:
		var sc = ShopCardScene.instantiate()
		grid.add_child(sc)
		sc.setup(card, 0, "", Color.WHITE, false, false)
	visible = true


func hide_popup() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			hide_popup()
			get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_popup()
