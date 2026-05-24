extends ScrollContainer

const UF = preload("res://scripts/views/ui_factory.gd")
const Talent = preload("res://scripts/talent.gd")
const ShopCardScene = preload("res://scenes/ui/shop/shop_card.tscn")

@onready var owned_grid: HBoxContainer = $Margin/VBox/OwnedGrid
@onready var lbl_owned_empty: Label = $Margin/VBox/LblOwnedEmpty
@onready var grid: HBoxContainer = $Margin/VBox/Grid
@onready var lbl_offer_empty: Label = $Margin/VBox/LblOfferEmpty


func _ready() -> void:
	Game.talents_changed.connect(refresh)
	Game.state_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for c in owned_grid.get_children():
		c.queue_free()
	for c in grid.get_children():
		c.queue_free()
	# 已拥有
	if Game.owned_talents.is_empty():
		lbl_owned_empty.visible = true
	else:
		lbl_owned_empty.visible = false
		for t in Game.owned_talents:
			var sc = ShopCardScene.instantiate()
			owned_grid.add_child(sc)
			sc.setup_talent(t, false, "已拥有", true)
	# 可购
	if Game.talent_offers.is_empty():
		lbl_offer_empty.visible = true
		return
	lbl_offer_empty.visible = false
	for i in range(Game.talent_offers.size()):
		var t: Talent = Game.talent_offers[i]
		var sc = ShopCardScene.instantiate()
		grid.add_child(sc)
		var can_afford: bool = Game.cash >= float(t.price)
		sc.setup_talent(t, can_afford)
		var idx_capture: int = i
		sc.action_pressed.connect(_make_buy_handler(idx_capture))


func _make_buy_handler(idx: int) -> Callable:
	return func() -> void:
		Game.shop_buy_talent(idx)
