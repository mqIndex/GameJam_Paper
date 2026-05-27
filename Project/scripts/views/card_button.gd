extends Button

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")

@onready var lbl_name: Label = $VBox/LblName
@onready var lbl_cost: Label = $VBox/LblCost
@onready var lbl_desc: Label = $VBox/LblDesc
@onready var icon_slot: CenterContainer = get_node_or_null("VBox/IconSlot")
@onready var icon_tex: TextureRect = get_node_or_null("VBox/IconSlot/Icon")

const HOVER_SCALE: float = 1.2
const HOVER_DURATION: float = 0.18
const HOVER_Z_INDEX: int = 10

signal play_blocked(reason: String, source: Control)
signal play_block_hint_cleared(source: Control)

var _card_index: int = -1
var _play_block_reason: String = ""
var _current_tween: Tween = null
var _is_hovering: bool = false
var _is_dragging: bool = false
var _tutorial_highlight: Panel = null
var _tutorial_highlight_tween: Tween = null


func _ready() -> void:
	pivot_offset = custom_minimum_size * 0.5
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func setup(card: Card, index: int) -> void:
	_card_index = index
	set_meta("effect_id", card.effect_id)
	set_meta("card_name", card.name)
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
	# 卡牌框: 数据驱动纯色边框 (无底图, 透明底)
	# 边框颜色优先来自 Cards_Visual.csv "颜色" 列, 缺失时 fallback 到 kind_color
	var border_col: Color = UF.card_color_for(card.name)
	if border_col.a <= 0.0:
		border_col = col
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)  # 透明底, 不画底图
	sb.border_color = border_col
	sb.border_width_top = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	add_theme_stylebox_override("normal", sb)
	var hover_sb := sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(border_col.r, border_col.g, border_col.b, 0.10)
	add_theme_stylebox_override("hover", hover_sb)
	var pressed_sb := sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = Color(border_col.r, border_col.g, border_col.b, 0.18)
	add_theme_stylebox_override("pressed", pressed_sb)
	var hover_pressed_sb := pressed_sb.duplicate() as StyleBoxFlat
	add_theme_stylebox_override("hover_pressed", hover_pressed_sb)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var disabled_sb := sb.duplicate() as StyleBoxFlat
	disabled_sb.border_color = UF.COL_AP_OFF
	disabled_sb.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("disabled", disabled_sb)
	disabled = false
	refresh_play_block_reason()
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	_apply_icon(card)


# 给卡牌 Icon 加载对应图标 (路径由 UF.card_icon_path_for 数据驱动解析);
# 找不到时隐藏 Icon TextureRect, 不报错也不显示占位
func _apply_icon(card: Card) -> void:
	if icon_tex == null:
		return
	var path: String = UF.card_icon_path_for(card.name, card.image_path)
	if path == "":
		icon_tex.texture = null
		icon_tex.visible = false
		return
	var tex = load(path)
	if tex is Texture2D:
		icon_tex.texture = tex as Texture2D
		icon_tex.visible = true
	else:
		icon_tex.texture = null
		icon_tex.visible = false


func refresh_play_block_reason() -> String:
	var reason := Game.get_card_play_block_reason(_card_index)
	set_play_block_reason(reason)
	return reason


func set_play_block_reason(reason: String) -> void:
	_play_block_reason = reason
	disabled = false
	if _is_dragging:
		return
	if _play_block_reason == "":
		modulate = Color.WHITE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		modulate = Color(1.0, 1.0, 1.0, 0.58)
		mouse_default_cursor_shape = Control.CURSOR_HELP


func set_tutorial_highlight(enabled: bool) -> void:
	if enabled:
		_ensure_tutorial_highlight()
		_tutorial_highlight.visible = true
		if _tutorial_highlight_tween == null or not _tutorial_highlight_tween.is_valid():
			_tutorial_highlight.modulate = Color(1, 1, 1, 1)
			_tutorial_highlight_tween = create_tween()
			_tutorial_highlight_tween.set_loops()
			_tutorial_highlight_tween.tween_property(_tutorial_highlight, "modulate:a", 0.35, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tutorial_highlight_tween.tween_property(_tutorial_highlight, "modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		if _tutorial_highlight_tween != null and _tutorial_highlight_tween.is_valid():
			_tutorial_highlight_tween.kill()
		_tutorial_highlight_tween = null
		if _tutorial_highlight != null:
			_tutorial_highlight.visible = false
			_tutorial_highlight.modulate = Color(1, 1, 1, 1)


func _ensure_tutorial_highlight() -> void:
	if _tutorial_highlight != null:
		return
	_tutorial_highlight = Panel.new()
	_tutorial_highlight.name = "TutorialCardHighlight"
	_tutorial_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_highlight.z_index = 80
	_tutorial_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tutorial_highlight.offset_left = -5.0
	_tutorial_highlight.offset_top = -5.0
	_tutorial_highlight.offset_right = 5.0
	_tutorial_highlight.offset_bottom = 5.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.74, 0.24, 0.09)
	sb.border_color = Color(1.0, 0.74, 0.24, 1.0)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	_tutorial_highlight.add_theme_stylebox_override("panel", sb)
	add_child(_tutorial_highlight)


func _on_pressed() -> void:
	if _is_dragging:
		return
	if refresh_play_block_reason() != "":
		_emit_play_blocked()
	else:
		Game.play_card(_card_index)


func _on_mouse_entered() -> void:
	if refresh_play_block_reason() != "":
		_emit_play_blocked()
		return
	play_block_hint_cleared.emit(null)
	_is_hovering = true
	_tween_scale(Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DURATION)
	z_index = HOVER_Z_INDEX


func _on_mouse_exited() -> void:
	_is_hovering = false
	play_block_hint_cleared.emit(self)
	if _is_dragging:
		return
	_tween_scale(Vector2.ONE, HOVER_DURATION)
	z_index = 0


func _on_button_down() -> void:
	if refresh_play_block_reason() != "":
		_emit_play_blocked()
		return
	_tween_scale(Vector2(0.95, 0.95), 0.06)


func _on_button_up() -> void:
	if refresh_play_block_reason() != "":
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
	if refresh_play_block_reason() != "":
		_emit_play_blocked()
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
		refresh_play_block_reason()
		if not _is_hovering:
			_tween_scale(Vector2.ONE, HOVER_DURATION)
			z_index = 0


func _emit_play_blocked() -> void:
	var reason := refresh_play_block_reason()
	if reason == "":
		return
	play_blocked.emit(reason, self)
