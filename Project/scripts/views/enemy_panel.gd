extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const Effects = preload("res://scripts/views/effects.gd")
const SpeechArrow = preload("res://scripts/views/speech_arrow.gd")

@onready var lbl_name: Label = $VBox/LblName
@onready var lbl_status: Label = $VBox/LblStatus
@onready var stats_grid: GridContainer = $VBox/StatsGrid
@onready var lbl_position: Label = $VBox/StatsGrid/LblPosition
@onready var lbl_avg_price: Label = $VBox/StatsGrid/LblAvgPrice
@onready var lbl_cash: Label = $VBox/StatsGrid/LblCash
@onready var lbl_margin: Label = $VBox/StatsGrid/LblMargin
@onready var separator: HSeparator = $VBox/HSeparator
@onready var bubble_label: Label = $VBox/BubbleLabel
@onready var avatar: Control = $VBox/AvatarSlot/Avatar

const BUBBLE_DURATION: float = 3.4
const BUBBLE_W: float = 286.0
const BUBBLE_MIN_H: float = 58.0
const BUBBLE_LEFT_SHIFT: float = 38.0
const BUBBLE_ARROW_SIZE: Vector2 = Vector2(24.0, 13.0)
const BUBBLE_COLOR: Color = Color(0.03, 0.0, 0.02, 0.94)
const BUBBLE_BORDER_COLOR: Color = Color(1.0, 0.22, 0.34, 0.92)

# opponent_id → 商战对手面板的小头像
const PORTRAIT_BY_ID: Dictionary = {
	"boss_six": preload("res://assets/chev/ememy/DR1_GS_1024.png"),
	"boss_blade": preload("res://assets/chev/ememy/DR2_BL_1024.png"),
}

var _bubble_timer: float = 0.0
var _bubble_panel: PanelContainer = null
var _bubble_text: Label = null
var _bubble_arrow: Control = null
var _bubble_tween: Tween = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox(UF.COL_BORDER))
	_decorate_avatar_slot(UF.COL_NEON_RED)
	_build_bubble_overlay()
	Game.opponent_state_changed.connect(_refresh)
	Game.opponent_entered.connect(_on_opponent_entered)
	Game.opponent_defeated.connect(_on_opponent_defeated)
	Game.opponent_bubble.connect(_show_bubble)
	Game.opponent_action_played.connect(_on_action_played)
	Game.state_changed.connect(_refresh)
	_refresh()


# 在 AvatarSlot 周围加一个霓虹描边 (后续可替换为头像 PNG 框)
func _decorate_avatar_slot(border: Color) -> void:
	var slot: CenterContainer = $VBox/AvatarSlot
	if slot == null or slot.has_node("AvatarDeco"):
		return
	var deco := Panel.new()
	deco.name = "AvatarDeco"
	deco.show_behind_parent = true
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.add_theme_stylebox_override("panel", UF.neon_panel_stylebox(border))
	slot.add_child(deco)
	slot.move_child(deco, 0)
	deco.anchor_right = 1.0
	deco.anchor_bottom = 1.0
	deco.offset_left = -2.0
	deco.offset_top = -2.0
	deco.offset_right = 2.0
	deco.offset_bottom = 2.0


func _on_opponent_entered(_opponent_id: String) -> void:
	_refresh()


func _on_opponent_defeated(_opponent_id: String, _reward_card_id: String) -> void:
	_refresh()


func _process(delta: float) -> void:
	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			_hide_bubble()
		else:
			_position_bubble()


func _refresh() -> void:
	var opp = Game.get_opponent_state()
	if opp == null or (not opp.present and not opp.defeated_this_level):
		# 未出现: 只显示"(未出现)", 隐藏统计行
		_apply_portrait("")
		lbl_name.text = "对手"
		lbl_name.add_theme_color_override("font_color", UF.COL_GOLD)
		lbl_status.text = "(未出现)"
		lbl_status.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
		lbl_status.visible = true
		separator.visible = false
		stats_grid.visible = false
		return

	# 出现 (在场或已击败): 隐藏状态行, 显示统计
	_apply_portrait(opp.opponent_id)
	lbl_status.visible = false
	separator.visible = true
	stats_grid.visible = true

	if opp.defeated_this_level:
		lbl_name.text = opp.display_name
		lbl_name.add_theme_color_override("font_color", UF.COL_UP)
		lbl_position.text = "仓位 0"
		lbl_avg_price.text = "均价 --"
		lbl_cash.text = "现金 ¥0"
		lbl_margin.text = "保证金 ¥0"
		return

	# 在场
	lbl_name.text = opp.display_name
	lbl_name.add_theme_color_override("font_color", UF.COL_GOLD)
	lbl_position.text = "仓位 %d 股" % opp.short_position
	lbl_avg_price.text = "均价 ¥%.1f" % opp.entry_avg_price
	lbl_cash.text = "现金 ¥%s" % UF.fmt_money(opp.cash)
	lbl_margin.text = "保证金 ¥%s" % UF.fmt_money(opp.safety_pool)


func _show_bubble(text: String) -> void:
	if _bubble_panel == null:
		return
	_bubble_text.text = text
	_set_bubble_visible(true)
	_bubble_timer = BUBBLE_DURATION
	_position_bubble()
	_play_bubble_enter()


func _build_bubble_overlay() -> void:
	bubble_label.visible = false
	_bubble_panel = PanelContainer.new()
	_bubble_panel.name = "SpeechBubble"
	_bubble_panel.top_level = true
	_bubble_panel.visible = false
	_bubble_panel.z_index = 80
	_bubble_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_panel.custom_minimum_size = Vector2(BUBBLE_W, 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BUBBLE_COLOR
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = BUBBLE_BORDER_COLOR
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 16.0
	sb.content_margin_top = 12.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 12.0
	sb.shadow_color = Color(BUBBLE_BORDER_COLOR.r, BUBBLE_BORDER_COLOR.g, BUBBLE_BORDER_COLOR.b, 0.34)
	sb.shadow_size = 8
	_bubble_panel.add_theme_stylebox_override("panel", sb)
	_bubble_text = Label.new()
	_bubble_text.custom_minimum_size = Vector2(BUBBLE_W - 32.0, BUBBLE_MIN_H - 24.0)
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble_text.add_theme_font_size_override("font_size", 16)
	_bubble_text.add_theme_color_override("font_color", Color.WHITE)
	_bubble_panel.add_child(_bubble_text)
	add_child(_bubble_panel)

	_bubble_arrow = SpeechArrow.new()
	_bubble_arrow.name = "SpeechBubbleArrow"
	_bubble_arrow.top_level = true
	_bubble_arrow.visible = false
	_bubble_arrow.z_index = 79
	_bubble_arrow.custom_minimum_size = BUBBLE_ARROW_SIZE
	_bubble_arrow.size = BUBBLE_ARROW_SIZE
	_bubble_arrow.fill_color = BUBBLE_COLOR
	_bubble_arrow.modulate = Color(1, 1, 1, 0)
	add_child(_bubble_arrow)


func _position_bubble() -> void:
	if _bubble_panel == null or not _bubble_panel.visible or avatar == null:
		return
	var avatar_rect := avatar.get_global_rect()
	var panel_min := _bubble_panel.get_combined_minimum_size()
	_bubble_panel.size = Vector2(BUBBLE_W, max(BUBBLE_MIN_H, panel_min.y))
	_bubble_panel.pivot_offset = _bubble_panel.size * 0.5
	var viewport_rect := get_viewport_rect()
	var x: float = avatar_rect.get_center().x - _bubble_panel.size.x * 0.5 - BUBBLE_LEFT_SHIFT
	x = clamp(x, 8.0, max(8.0, viewport_rect.size.x - _bubble_panel.size.x - 8.0))
	var y: float = avatar_rect.position.y - _bubble_panel.size.y - BUBBLE_ARROW_SIZE.y - 9.0
	y = max(8.0, y)
	_bubble_panel.global_position = Vector2(x, y)
	var arrow_x: float = avatar_rect.get_center().x - BUBBLE_ARROW_SIZE.x * 0.5
	arrow_x = clamp(arrow_x, x + 8.0, x + _bubble_panel.size.x - BUBBLE_ARROW_SIZE.x - 8.0)
	_bubble_arrow.size = BUBBLE_ARROW_SIZE
	_bubble_arrow.global_position = Vector2(arrow_x, y + _bubble_panel.size.y - 1.0)
	_bubble_arrow.queue_redraw()


func _play_bubble_enter() -> void:
	if _bubble_tween != null and _bubble_tween.is_valid():
		_bubble_tween.kill()
	_bubble_panel.modulate = Color(1, 1, 1, 0)
	_bubble_panel.scale = Vector2(0.86, 0.86)
	_bubble_arrow.modulate = Color(1, 1, 1, 0)
	_bubble_tween = create_tween()
	_bubble_tween.set_parallel(true)
	_bubble_tween.tween_property(_bubble_panel, "modulate", Color(1, 1, 1, 1), 0.12)
	_bubble_tween.tween_property(_bubble_panel, "scale", Vector2(1.08, 1.08), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_property(_bubble_arrow, "modulate", Color(1, 1, 1, 1), 0.12)
	_bubble_tween.chain().tween_property(_bubble_panel, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _hide_bubble() -> void:
	if _bubble_panel == null or not _bubble_panel.visible:
		return
	if _bubble_tween != null and _bubble_tween.is_valid():
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.set_parallel(true)
	_bubble_tween.tween_property(_bubble_panel, "modulate", Color(1, 1, 1, 0), 0.18)
	_bubble_tween.tween_property(_bubble_arrow, "modulate", Color(1, 1, 1, 0), 0.18)
	_bubble_tween.chain().tween_callback(func(): _set_bubble_visible(false))


func _set_bubble_visible(v: bool) -> void:
	if _bubble_panel != null:
		_bubble_panel.visible = v
	if _bubble_arrow != null:
		_bubble_arrow.visible = v


# 对手出牌特效 (依次播放, 由 game_state 的 await 间隔保证)
func _on_action_played(action_name: String, params: Dictionary) -> void:
	match action_name:
		"add_short":
			Effects.shake_node(self, 6.0, 0.2)
			_show_bubble("+%d 空单" % int(params.get("N", 0)))
		"bad_news":
			var flash := get_node_or_null("/root/Main/ChartPanel/FlashOverlay") as ColorRect
			if flash != null:
				Effects.flash_rect(flash, UF.COL_DOWN, 0.30)
			_show_bubble("情绪 -%d" % int(params.get("K", 0)))
		"cover":
			_flash_avatar(UF.COL_UP)
			_show_bubble("-%d 平仓" % int(params.get("M", 0)))
		"pump_trap":
			var flash := get_node_or_null("/root/Main/ChartPanel/FlashOverlay") as ColorRect
			if flash != null:
				Effects.flash_rect(flash, UF.COL_UP, 0.30)
			_show_bubble("拉抬 +%.1f%%" % (float(params.get("Y", 0.0)) * 100.0))
		"idle":
			pass


func _flash_avatar(color: Color) -> void:
	if avatar == null:
		return
	var t := create_tween()
	t.tween_property(avatar, "modulate", color, 0.12)
	t.tween_property(avatar, "modulate", Color.WHITE, 0.12)


func _apply_portrait(opponent_id: String) -> void:
	if avatar == null or not avatar.has_method("set_portrait"):
		return
	var tex: Texture2D = PORTRAIT_BY_ID.get(opponent_id, null)
	avatar.call("set_portrait", tex)
