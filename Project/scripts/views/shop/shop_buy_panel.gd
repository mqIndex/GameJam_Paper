extends ScrollContainer

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const ShopCardScene = preload("res://scenes/ui/shop/shop_card.tscn")

@onready var grid: GridContainer = $Margin/VBox/Grid
@onready var lbl_empty: Label = $Margin/VBox/LblEmpty

const MAX_COLUMNS: int = 8
const CARD_SLOT_W: float = 118.0


func _ready() -> void:
	_raise_scrollbars()
	resized.connect(_update_columns)
	Game.shop_changed.connect(refresh)
	refresh()
	call_deferred("_update_columns")


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
	_update_columns()


func _update_columns() -> void:
	if grid == null:
		return
	var available_w: float = max(CARD_SLOT_W, size.x - 48.0)
	grid.columns = min(MAX_COLUMNS, max(1, int(floor(available_w / CARD_SLOT_W))))


func _raise_scrollbars() -> void:
	var vbar := get_v_scroll_bar()
	vbar.z_index = 200
	vbar.mouse_filter = Control.MOUSE_FILTER_STOP
	var hbar := get_h_scroll_bar()
	hbar.z_index = 200
	hbar.mouse_filter = Control.MOUSE_FILTER_STOP
