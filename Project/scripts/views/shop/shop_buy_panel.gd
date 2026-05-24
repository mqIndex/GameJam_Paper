extends ScrollContainer

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const ShopCardScene = preload("res://scenes/ui/shop/shop_card.tscn")

@onready var grid: HBoxContainer = $Margin/VBox/Grid
@onready var lbl_empty: Label = $Margin/VBox/LblEmpty


func _ready() -> void:
	Game.shop_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	if Game.shop_offers.is_empty():
		lbl_empty.visible = true
		return
	lbl_empty.visible = false
	for i in range(Game.shop_offers.size()):
		var card: Card = Game.shop_offers[i]
		var sc = ShopCardScene.instantiate()
		grid.add_child(sc)
		var price_due: int = card.shop_price if card.shop_price > 0 else Game.SHOP_BUY_PRICE
		var can_afford: bool = Game.cash >= price_due
		sc.setup(card, price_due, "购买", UF.COL_UP, can_afford)
		var idx_capture: int = i
		sc.action_pressed.connect(func(): Game.shop_buy_card(idx_capture))
