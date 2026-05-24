extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const CardButtonScene = preload("res://scenes/ui/card_button.tscn")

@onready var fan_container: Control = $FanHandContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.hand_changed.connect(_refresh_hand)
	Game.state_changed.connect(_refresh_state)


func _refresh_hand() -> void:
	for c in fan_container.get_children():
		c.queue_free()
	for i in range(Game.hand.size()):
		var card: Card = Game.hand[i]
		var btn = CardButtonScene.instantiate()
		fan_container.add_child(btn)
		btn.setup(card, i)
	if fan_container.has_method("relayout_cards"):
		fan_container.relayout_cards()


func _refresh_state() -> void:
	if fan_container == null:
		return
	var children: Array = fan_container.get_children()
	for i in range(min(children.size(), Game.hand.size())):
		var btn = children[i] as Button
		if btn == null:
			continue
		var c: Card = Game.hand[i]
		btn.disabled = (Game.action_points < c.cost) or (Game.phase != Game.Phase.PLAY) or Game.is_level_over


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("card_index")


func _drop_data(_at_position: Vector2, _data: Variant) -> void:
	pass
