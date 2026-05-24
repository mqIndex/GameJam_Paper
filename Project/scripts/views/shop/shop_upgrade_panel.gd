extends ScrollContainer

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const CardDatabase = preload("res://scripts/card_database.gd")
const ShopCardScene = preload("res://scenes/ui/shop/shop_card.tscn")

@onready var grid: GridContainer = $Margin/VBox/Grid
@onready var lbl_empty: Label = $Margin/VBox/LblEmpty

const CARD_SLOT_W: float = 100.0

var _tooltip: PanelContainer
var _tooltip_lbl: Label


func _ready() -> void:
	_build_tooltip()
	resized.connect(_update_columns)
	Game.shop_changed.connect(refresh)
	refresh()
	call_deferred("_update_columns")


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.visible = false
	_tooltip.top_level = true
	_tooltip.z_index = 20
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.18, 0.95)
	sb.border_color = UF.COL_HIGHLIGHT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	_tooltip.add_theme_stylebox_override("panel", sb)
	_tooltip_lbl = Label.new()
	_tooltip_lbl.add_theme_font_size_override("font_size", 11)
	_tooltip_lbl.add_theme_color_override("font_color", UF.COL_TEXT)
	_tooltip.add_child(_tooltip_lbl)
	add_child(_tooltip)


func refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	_tooltip.visible = false
	var deck: Array = Game.get_full_deck()
	var any_upgradable: bool = false
	for i in range(deck.size()):
		var card: Card = deck[i]
		var target_eid: String = CardDatabase.upgrade_target(card.effect_id)
		if target_eid == "":
			continue
		any_upgradable = true
		var sc = ShopCardScene.instantiate()
		grid.add_child(sc)
		var can_afford: bool = Game.cash >= Game.SHOP_UPGRADE_PRICE
		sc.setup(card, Game.SHOP_UPGRADE_PRICE, "升级", UF.COL_HIGHLIGHT, can_afford)
		var idx_capture: int = i
		sc.action_pressed.connect(func(): Game.shop_upgrade_card(idx_capture))
		var upgraded: Card = CardDatabase.make_by_effect(target_eid, "_preview_%d" % i)
		var info: String = "升级后: %s\n耗 %d → %d\n%s" % [upgraded.name, card.cost, upgraded.cost, upgraded.description]
		var sc_ref = sc
		var info_ref: String = info
		sc.card_hovered.connect(func(hovering: bool):
			if hovering:
				_show_tooltip(sc_ref, info_ref)
			else:
				_tooltip.visible = false
		)
	lbl_empty.visible = not any_upgradable
	_update_columns()


func _show_tooltip(node: Control, text: String) -> void:
	_tooltip_lbl.text = text
	var r := node.get_global_rect()
	_tooltip.global_position = Vector2(r.position.x + r.size.x + 4, r.position.y)
	_tooltip.visible = true


func _update_columns() -> void:
	if grid == null:
		return
	grid.columns = max(1, int(floor(size.x / CARD_SLOT_W)))
