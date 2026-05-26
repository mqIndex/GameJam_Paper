extends Button

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")

@onready var lbl_name: Label = $VBox/LblName
@onready var lbl_cost: Label = $VBox/LblCost
@onready var lbl_desc: Label = $VBox/LblDesc

const HOVER_SCALE: float = 1.2
const HOVER_DURATION: float = 0.18
const HOVER_Z_INDEX: int = 10

var _card_index: int = -1
var _current_tween: Tween = null
var _is_hovering: bool = false
var _is_dragging: bool = false


func _ready() -> void:
	pivot_offset = custom_minimum_size * 0.5
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func setup(card: Card, index: int) -> void:
	_card_index = index
	lbl_name.text = card.name
	var col: Color = UF.kind_color(card.kind)
	lbl_name.add_theme_color_override("font_color", col)
	lbl_name.add_theme_font_size_override("font_size", UF.FS_H1)
	lbl_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_name.add_theme_constant_override("outline_size", 2)
	lbl_cost.text = "耗 %d" % card.cost
	lbl_cost.add_theme_color_override("font_color", UF.COL_GOLD)
	lbl_cost.add_theme_font_size_override("font_size", UF.FS_BODY)
	lbl_cost.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_cost.add_theme_constant_override("outline_size", 2)
	lbl_desc.text = card.description
	lbl_desc.add_theme_color_override("font_color", UF.COL_TEXT)
	lbl_desc.add_theme_font_size_override("font_size", UF.FS_BODY)
	lbl_desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_desc.add_theme_constant_override("outline_size", 2)
	# 卡牌框: 优先贴图版 StyleBoxTexture; 缺失则 fallback 到彩色描边
	var tex_sb := UF.texture_card_stylebox(card.kind)
	if tex_sb != null:
		add_theme_stylebox_override("normal", tex_sb)
		var hover_sb := (tex_sb as StyleBoxTexture).duplicate() as StyleBoxTexture
		hover_sb.modulate_color = Color(1.15, 1.15, 1.15, 1.0)
		add_theme_stylebox_override("hover", hover_sb)
		var pressed_sb := (tex_sb as StyleBoxTexture).duplicate() as StyleBoxTexture
		pressed_sb.modulate_color = Color(0.85, 0.85, 0.85, 1.0)
		add_theme_stylebox_override("pressed", pressed_sb)
		add_theme_stylebox_override("hover_pressed", pressed_sb.duplicate())
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var disabled_sb := (tex_sb as StyleBoxTexture).duplicate() as StyleBoxTexture
		disabled_sb.modulate_color = Color(0.45, 0.45, 0.45, 0.85)
		add_theme_stylebox_override("disabled", disabled_sb)
	else:
		# fallback: 整圈彩边 StyleBoxFlat
		var sb := StyleBoxFlat.new()
		sb.bg_color = UF.COL_BG_DEEP
		sb.border_color = col
		sb.border_width_top = 3
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_width_bottom = 3
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_left = 2
		sb.corner_radius_bottom_right = 2
		sb.shadow_color = Color(col.r, col.g, col.b, 0.30)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2.ZERO
		add_theme_stylebox_override("normal", sb)
		var hover_sb := sb.duplicate() as StyleBoxFlat
		hover_sb.bg_color = UF.COL_PANEL_LIGHT
		hover_sb.shadow_size = 5
		add_theme_stylebox_override("hover", hover_sb)
		var pressed_sb := sb.duplicate() as StyleBoxFlat
		pressed_sb.bg_color = UF.COL_PANEL_LIGHT.lerp(col, 0.2)
		add_theme_stylebox_override("pressed", pressed_sb)
		var hover_pressed_sb := pressed_sb.duplicate() as StyleBoxFlat
		hover_pressed_sb.bg_color = UF.COL_PANEL_LIGHT.lerp(col, 0.28)
		add_theme_stylebox_override("hover_pressed", hover_pressed_sb)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var disabled_sb := sb.duplicate() as StyleBoxFlat
		disabled_sb.border_color = UF.COL_AP_OFF
		disabled_sb.bg_color = Color("#05070b")
		disabled_sb.shadow_size = 0
		add_theme_stylebox_override("disabled", disabled_sb)
	disabled = (Game.action_points < card.cost) or (Game.phase != Game.Phase.PLAY) or Game.is_level_over
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func _on_pressed() -> void:
	if not _is_dragging:
		Game.play_card(_card_index)


func _on_mouse_entered() -> void:
	if disabled:
		return
	_is_hovering = true
	_tween_scale(Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DURATION)
	z_index = HOVER_Z_INDEX


func _on_mouse_exited() -> void:
	_is_hovering = false
	if _is_dragging:
		return
	_tween_scale(Vector2.ONE, HOVER_DURATION)
	z_index = 0


func _on_button_down() -> void:
	if disabled:
		return
	_tween_scale(Vector2(0.95, 0.95), 0.06)


func _on_button_up() -> void:
	if disabled:
		return
	if _is_hovering:
		_cancel_current_tween()
		var t := create_tween()
		_current_tween = t
		t.tween_property(self, "scale", Vector2(HOVER_SCALE * 1.05, HOVER_SCALE * 1.05), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(self, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_tween_scale(Vector2.ONE, HOVER_DURATION)


func _tween_scale(target: Vector2, duration: float) -> void:
	_cancel_current_tween()
	_current_tween = create_tween()
	_current_tween.tween_property(self, "scale", target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _cancel_current_tween() -> void:
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled:
		return null
	_is_dragging = true
	var preview := Control.new()
	var card_view := duplicate() as Control
	card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_view.scale = Vector2(HOVER_SCALE, HOVER_SCALE)
	card_view.position = -card_view.custom_minimum_size * 0.5
	card_view.modulate = Color(1, 1, 1, 0.92)
	preview.add_child(card_view)
	set_drag_preview(preview)
	# Make the original semi-transparent during drag
	modulate = Color(1, 1, 1, 0.55)
	return {"card_index": _card_index}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_is_dragging = false
		modulate = Color(1, 1, 1, 1)
		if not _is_hovering:
			_tween_scale(Vector2.ONE, HOVER_DURATION)
			z_index = 0
