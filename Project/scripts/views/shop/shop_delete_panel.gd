extends ScrollContainer

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const ShopCardScene = preload("res://scenes/ui/shop/shop_card.tscn")

@onready var grid: GridContainer = $Margin/VBox/Grid
@onready var lbl_price: Label = $Margin/VBox/LblPrice


func _ready() -> void:
	Game.shop_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	var deck: Array = Game.get_full_deck()
	var del_price: int = Game.current_delete_price()
	lbl_price.text = "当前删卡价: ¥%d" % del_price
	for i in range(deck.size()):
		var card: Card = deck[i]
		var sc = ShopCardScene.instantiate()
		grid.add_child(sc)
		var can_afford: bool = (Game.cash >= del_price) and (deck.size() > 1)
		sc.setup(card, del_price, "删除", UF.COL_DOWN, can_afford)
		var idx_capture: int = i
		sc.action_pressed.connect(func(): Game.shop_delete_card(idx_capture))
