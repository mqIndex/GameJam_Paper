extends ScrollContainer

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const ShopCardScene = preload("res://scenes/ui/shop/shop_card.tscn")

@onready var grid: GridContainer = $Margin/VBox/Grid
@onready var lbl_price: Label = $Margin/VBox/LblPrice

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
	var deck: Array = Game.get_full_deck()
	var del_price: int = Game.current_delete_price()
	var deletes_left: int = Game.MAX_SHOP_DELETES - Game.shop_deletes_this_visit
	if deletes_left > 0:
		lbl_price.text = "当前删卡价: ¥%d | 本回合可删 %d/%d 张" % [del_price, deletes_left, Game.MAX_SHOP_DELETES]
	else:
		lbl_price.text = "本回合删卡次数已达上限 (%d/%d)" % [Game.MAX_SHOP_DELETES, Game.MAX_SHOP_DELETES]
	for i in range(deck.size()):
		var card: Card = deck[i]
		var sc = ShopCardScene.instantiate()
		grid.add_child(sc)
		var can_afford: bool = (Game.cash >= del_price) and (deck.size() > 1) and (deletes_left > 0)
		sc.setup(card, del_price, "删除", UF.COL_DOWN, can_afford)
		var idx_capture: int = i
		sc.action_pressed.connect(func(): Game.shop_delete_card(idx_capture))
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
