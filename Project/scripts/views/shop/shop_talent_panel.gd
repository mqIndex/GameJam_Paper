extends ScrollContainer

const UF = preload("res://scripts/views/ui_factory.gd")
const Talent = preload("res://scripts/talent.gd")

# 天赋 ID → logo 图片路径
const TALENT_ICON_MAP: Dictionary = {
	"cascade_combo": "res://data/talent/连携效应.png",
	"influence":     "res://data/talent/影响力.png",
}

@onready var owned_grid: HBoxContainer = $Margin/VBox/OwnedGrid
@onready var lbl_owned_empty: Label = $Margin/VBox/LblOwnedEmpty
@onready var grid: HBoxContainer = $Margin/VBox/Grid
@onready var lbl_offer_empty: Label = $Margin/VBox/LblOfferEmpty

# 悬浮 tip 容器 (运行时构建)
var _tip: PanelContainer = null
var _tip_title: RichTextLabel = null
var _tip_desc: RichTextLabel = null
var _tip_anchor: Control = null

const TALENT_CARD_SIZE: Vector2 = Vector2(116.0, 158.0)
const TALENT_ICON_SIZE: Vector2 = Vector2(82.0, 82.0)
const TALENT_BUTTON_SIZE: Vector2 = Vector2(86.0, 30.0)


func _ready() -> void:
	Game.talents_changed.connect(refresh)
	Game.state_changed.connect(refresh)
	_build_tip()
	refresh()


func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.top_level = true
	_tip.z_index = 100
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.custom_minimum_size = Vector2(340, 0)
	var sb := UF.panel_stylebox(UF.COL_HIGHLIGHT)
	_tip.add_theme_stylebox_override("panel", sb)
	add_child(_tip)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_tip.add_child(vbox)
	_tip_title = _make_rich(16)
	_tip_desc  = _make_rich(14)
	vbox.add_child(_tip_title)
	vbox.add_child(_tip_desc)


func _make_rich(font_size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(320, 0)
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_color_override("default_color", UF.COL_TEXT)
	return r


func refresh() -> void:
	_hide_tip()
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
			owned_grid.add_child(_make_talent_logo(t, false))
	# 可购
	if Game.talent_offers.is_empty():
		lbl_offer_empty.visible = true
		return
	lbl_offer_empty.visible = false
	for i in range(Game.talent_offers.size()):
		var t: Talent = Game.talent_offers[i]
		var can_afford: bool = Game.cash >= float(t.price)
		var logo := _make_talent_logo(t, can_afford)
		grid.add_child(logo)
		var idx_capture: int = i
		var btn: Button = logo.get_node("BtnBuy")
		btn.pressed.connect(_make_buy_handler(idx_capture))


# 构建天赋 logo 组件: TextureRect + 价格/标签 + 购买按钮
func _make_talent_logo(t: Talent, can_afford: bool) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = TALENT_CARD_SIZE
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS

	# logo 图片
	var tex := TextureRect.new()
	tex.custom_minimum_size = TALENT_ICON_SIZE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon_path: String = TALENT_ICON_MAP.get(t.id, "")
	if icon_path != "":
		var loaded = load(icon_path)
		if loaded is Texture2D:
			tex.texture = loaded as Texture2D
		else:
			push_warning("ShopTalent: 无法加载天赋 logo %s" % icon_path)
	vbox.add_child(tex)

	var lbl_name := Label.new()
	lbl_name.text = t.name
	lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_name.add_theme_font_size_override("font_size", 14)
	lbl_name.add_theme_color_override("font_color", UF.COL_TEXT)
	lbl_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	lbl_name.add_theme_constant_override("outline_size", 2)
	lbl_name.clip_text = true
	vbox.add_child(lbl_name)

	# 价格 / 状态标签
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	if not can_afford and t.price > 0:
		# 已拥有 → 显示 "已拥有"
		lbl.text = "已拥有"
		lbl.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
	elif t.price > 0:
		lbl.text = "¥%d" % t.price
		lbl.add_theme_color_override("font_color", UF.COL_HIGHLIGHT)
	else:
		lbl.text = "免费"
		lbl.add_theme_color_override("font_color", UF.COL_HIGHLIGHT)
	vbox.add_child(lbl)

	# 购买按钮
	var btn := Button.new()
	btn.name = "BtnBuy"
	btn.text = "购买" if can_afford else "已拥有"
	btn.custom_minimum_size = TALENT_BUTTON_SIZE
	btn.add_theme_font_size_override("font_size", 13)
	var btn_col: Color = UF.COL_HIGHLIGHT if can_afford else UF.COL_TEXT_DIM
	btn.add_theme_color_override("font_color", btn_col)
	var btn_sb := UF.panel_stylebox(btn_col)
	btn.add_theme_stylebox_override("normal", btn_sb)
	var btn_hover := btn_sb.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(btn_col.r, btn_col.g, btn_col.b, 0.18)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.disabled = not can_afford
	if not can_afford and t.price > 0:
		btn.visible = false
	else:
		btn.visible = true
	vbox.add_child(btn)

	# tooltip: 用自定义 tip 面板 (不依赖 Godot 内置 tooltip)
	vbox.set_meta("talent_data", t)
	vbox.set_meta("talent_id", t.id)
	tex.set_meta("talent_id", t.id)
	btn.set_meta("talent_id", t.id)
	tex.mouse_entered.connect(_on_logo_mouse_entered.bind(vbox))
	tex.mouse_exited.connect(_on_logo_mouse_exited)
	vbox.mouse_entered.connect(_on_logo_mouse_entered.bind(vbox))
	vbox.mouse_exited.connect(_on_logo_mouse_exited)

	return vbox


func _on_logo_mouse_entered(anchor: VBoxContainer) -> void:
	var t: Talent = anchor.get_meta("talent_data") as Talent
	if t == null:
		return
	_tip_title.text = "[color=#%s][b]%s[/b][/color]" % [UF.COL_HIGHLIGHT.to_html(false), t.name]
	_tip_desc.text = "[color=#ffffff]%s[/color]" % t.description
	_tip.visible = true
	_tip_anchor = anchor
	_position_tip(anchor)


func _on_logo_mouse_exited() -> void:
	_hide_tip()


func _hide_tip() -> void:
	if _tip != null:
		_tip.visible = false
	_tip_anchor = null


func _position_tip(anchor: Control) -> void:
	var rect := anchor.get_global_rect()
	_tip.reset_size()
	var tip_w: float = max(_tip.size.x, _tip.custom_minimum_size.x)
	var pos := Vector2(rect.position.x + rect.size.x + 8, rect.position.y)
	_tip.global_position = pos


func _make_buy_handler(idx: int) -> Callable:
	return func() -> void:
		Game.shop_buy_talent(idx)
