extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const Talent = preload("res://scripts/talent.gd")

signal action_pressed
signal card_hovered(is_hovering: bool)

@onready var card_visual: Panel = $CardVisual
@onready var lbl_name: Label = $CardVisual/VBox/LblName
@onready var lbl_cost: Label = $CardVisual/VBox/LblCost
@onready var lbl_desc: Label = $CardVisual/VBox/LblDesc
@onready var lbl_price: Label = $LblPrice
@onready var btn_action: Button = $BtnAction

const HOVER_SCALE: float = 1.22
const TWEEN_DURATION: float = 0.15

var _tween: Tween = null


func _ready() -> void:
	# card_visual.z_index = 1
	# lbl_price.z_index = 0
	# btn_action.z_index = 0
	card_visual.pivot_offset = card_visual.size * 0.5
	card_visual.mouse_entered.connect(_on_mouse_entered)
	card_visual.mouse_exited.connect(_on_mouse_exited)
	btn_action.pressed.connect(func(): action_pressed.emit())


func setup(card: Card, price: int, action_text: String, action_color: Color, can_afford: bool, show_action: bool = true) -> void:
	set_meta("effect_id", card.effect_id)
	set_meta("talent_id", "")
	if lbl_name == null:
		card_visual = $CardVisual
		lbl_name = $CardVisual/VBox/LblName
		lbl_cost = $CardVisual/VBox/LblCost
		lbl_desc = $CardVisual/VBox/LblDesc
		lbl_price = $LblPrice
		btn_action = $BtnAction
	lbl_name.text = card.name
	var col: Color = UF.kind_color(card.kind)
	lbl_cost.text = "耗 %d" % card.cost
	lbl_cost.add_theme_color_override("font_color", col)
	lbl_desc.text = card.description
	_apply_visual_style(col)
	lbl_price.text = "¥%d" % price
	btn_action.text = action_text
	btn_action.add_theme_color_override("font_color", action_color)
	var btn_sb := UF.panel_stylebox(action_color)
	btn_action.add_theme_stylebox_override("normal", btn_sb)
	var btn_hover := btn_sb.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(action_color.r, action_color.g, action_color.b, 0.18)
	btn_action.add_theme_stylebox_override("hover", btn_hover)
	btn_action.disabled = not can_afford
	btn_action.visible = show_action
	lbl_price.visible = show_action


# 天赋卡: 复用同一张视觉, 但 cost 行显示「天赋」标签, 颜色统一用 highlight 金色
func setup_talent(talent: Talent, can_afford: bool, action_text: String = "购买", show_action: bool = true) -> void:
	set_meta("effect_id", "")
	set_meta("talent_id", talent.id)
	if lbl_name == null:
		card_visual = $CardVisual
		lbl_name = $CardVisual/VBox/LblName
		lbl_cost = $CardVisual/VBox/LblCost
		lbl_desc = $CardVisual/VBox/LblDesc
		lbl_price = $LblPrice
		btn_action = $BtnAction
	lbl_name.text = talent.name
	var col: Color = UF.COL_HIGHLIGHT
	lbl_cost.text = "天赋"
	lbl_cost.add_theme_color_override("font_color", col)
	lbl_desc.text = talent.description
	_apply_visual_style(col)
	lbl_price.text = "¥%d" % talent.price if talent.price > 0 else "免费"
	btn_action.text = action_text
	btn_action.add_theme_color_override("font_color", col)
	var btn_sb := UF.panel_stylebox(col)
	btn_action.add_theme_stylebox_override("normal", btn_sb)
	var btn_hover := btn_sb.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(col.r, col.g, col.b, 0.18)
	btn_action.add_theme_stylebox_override("hover", btn_hover)
	btn_action.disabled = not can_afford
	btn_action.visible = show_action
	lbl_price.visible = show_action


func _apply_visual_style(col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UF.COL_PANEL
	sb.border_color = col
	sb.border_width_top = 5
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	card_visual.add_theme_stylebox_override("panel", sb)


func _on_mouse_entered() -> void:
	_tween_scale(Vector2(HOVER_SCALE, HOVER_SCALE))
	z_index = 5
	card_hovered.emit(true)


func _on_mouse_exited() -> void:
	_tween_scale(Vector2.ONE)
	z_index = 0
	card_hovered.emit(false)


func _tween_scale(target: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(card_visual, "scale", target, TWEEN_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
