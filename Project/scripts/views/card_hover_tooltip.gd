extends RefCounted

const UF = preload("res://scripts/views/ui_factory.gd")

const MAX_W: float = 380.0
const MIN_W: float = 260.0
const PAD: float = 10.0
const MOUSE_OFFSET: Vector2 = Vector2(18.0, -14.0)


static func create(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "CardHoverTooltip"
	panel.top_level = true
	panel.visible = false
	panel.z_index = 1000
	panel.z_as_relative = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.025, 0.04, 0.075, 0.98)
	sb.border_color = Color(UF.COL_HIGHLIGHT.r, UF.COL_HIGHLIGHT.g, UF.COL_HIGHLIGHT.b, 0.9)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = PAD
	sb.content_margin_top = PAD
	sb.content_margin_right = PAD
	sb.content_margin_bottom = PAD
	panel.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(320.0, 0.0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UF.COL_TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(label)
	return panel


static func set_text(panel: PanelContainer, text: String) -> void:
	if panel == null:
		return
	var label := panel.get_node_or_null("Text") as Label
	if label != null:
		label.text = text


static func position_near_mouse(panel: PanelContainer, viewport: Viewport) -> void:
	if panel == null or viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var label := panel.get_node_or_null("Text") as Label
	if label != null:
		label.custom_minimum_size.x = min(MAX_W, max(MIN_W, viewport_size.x - 24.0))
	panel.reset_size()
	var tip_size := panel.get_combined_minimum_size()
	tip_size.x = min(MAX_W, max(MIN_W, min(tip_size.x, viewport_size.x - 24.0)))
	panel.size = tip_size

	var mouse := viewport.get_mouse_position()
	var pos := Vector2(mouse.x + MOUSE_OFFSET.x, mouse.y - tip_size.y + MOUSE_OFFSET.y)
	pos.x = clampf(pos.x, 8.0, max(8.0, viewport_size.x - tip_size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, max(8.0, viewport_size.y - tip_size.y - 8.0))
	panel.global_position = pos
