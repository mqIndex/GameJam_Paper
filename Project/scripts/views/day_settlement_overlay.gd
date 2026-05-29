extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const BG_PATH: String = "res://assets/loadingPage.png"

signal continue_requested

var _dim: ColorRect = null
var _bg_texture: TextureRect = null
var _panel: PanelContainer = null
var _lbl_day: Label = null
var _lbl_pnl: Label = null
var _lbl_delta: Label = null
var _lbl_price: Label = null
var _lbl_open_assets: Label = null
var _lbl_total: Label = null
var _lbl_cash: Label = null
var _lbl_holding: Label = null
var _lbl_forced: Label = null
var _btn_continue: Button = null
var _roll_tween: Tween = null
var _pnl_tween: Tween = null

var _summary: Dictionary = {}
var _is_final_day: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 210
	visible = false
	_build()


func _build() -> void:
	if ResourceLoader.exists(BG_PATH):
		_bg_texture = TextureRect.new()
		_bg_texture.texture = load(BG_PATH) as Texture2D
		_bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg_texture.modulate = Color(0.55, 0.62, 0.70, 0.26)
		_bg_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg_texture)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.035, 0.065, 0.78)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UF.texture_panel_stylebox(UF.COL_GOLD))
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -380.0
	_panel.offset_top = -245.0
	_panel.offset_right = 380.0
	_panel.offset_bottom = 245.0
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_lbl_day = _make_label("当日结算", 24, UF.COL_GOLD)
	_lbl_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_lbl_day)

	var funds_title := _make_label("今日资金", 14, UF.COL_TEXT_DIM)
	funds_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(funds_title)

	_lbl_pnl = _make_label("¥0", 44, UF.COL_GOLD)
	_lbl_pnl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_pnl.pivot_offset = Vector2(180.0, 28.0)
	root.add_child(_lbl_pnl)

	_lbl_delta = _make_label("今日盈亏 +¥0", 20, UF.COL_UP)
	_lbl_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_lbl_delta)

	_lbl_price = _make_label("开盘 ¥0.00 → 收盘 ¥0.00", 15, UF.COL_TEXT)
	_lbl_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_lbl_price)

	root.add_child(UF.h_sep())
	root.add_child(_metric_row("开局资金", "_lbl_open_assets"))
	root.add_child(_metric_row("收盘资金", "_lbl_total"))
	root.add_child(_metric_row("现金", "_lbl_cash"))
	root.add_child(_metric_row("持仓市值", "_lbl_holding"))

	_lbl_forced = _make_label("", 14, UF.COL_HIGHLIGHT)
	_lbl_forced.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_forced.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_lbl_forced)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	_btn_continue = UF.button("进入盘后商店", UF.COL_GOLD, 16)
	_btn_continue.custom_minimum_size = Vector2(220, 42)
	_btn_continue.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_continue.pressed.connect(_on_continue_pressed)
	root.add_child(_btn_continue)


func _metric_row(title: String, label_var: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var title_label := _make_label(title, 14, UF.COL_TEXT_DIM)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var value_label := _make_label("¥0", 19, UF.COL_TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(240.0, 0.0)
	row.add_child(value_label)
	match label_var:
		"_lbl_total":
			_lbl_total = value_label
		"_lbl_open_assets":
			_lbl_open_assets = value_label
		"_lbl_cash":
			_lbl_cash = value_label
		"_lbl_holding":
			_lbl_holding = value_label
	return row


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	label.add_theme_constant_override("outline_size", 2)
	return label


func show_summary(summary: Dictionary, is_final_day: bool) -> void:
	_summary = summary.duplicate(true)
	_is_final_day = is_final_day
	visible = true
	modulate = Color(1, 1, 1, 1)
	_btn_continue.disabled = true
	_btn_continue.text = "查看最终结算" if _is_final_day else "进入盘后商店"
	_lbl_day.text = "第 %d 天收盘" % int(_summary.get("day", 0))
	var open_assets: float = _open_assets()
	_set_funds_roll(open_assets)
	_set_delta_roll(0.0)
	_set_price_roll(float(_summary.get("open_price", 0.0)))
	_set_open_assets_roll(open_assets)
	_set_total_roll(open_assets)
	_set_cash_roll(0.0)
	_set_holding_roll(0.0)
	_set_forced_text()
	_play_roll()


func _play_roll() -> void:
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	if _pnl_tween != null and _pnl_tween.is_valid():
		_pnl_tween.kill()
	_lbl_pnl.scale = Vector2.ONE

	var pnl: float = float(_summary.get("day_pnl", 0.0))
	var open_assets: float = _open_assets()
	var total: float = float(_summary.get("total_assets", 0.0))
	var cash: float = float(_summary.get("cash", 0.0))
	var holding: float = float(_summary.get("holding_value", 0.0))
	var close_price: float = float(_summary.get("close_price", 0.0))
	var open_price: float = float(_summary.get("open_price", close_price))

	_roll_tween = create_tween()
	_roll_tween.set_parallel(true)
	_roll_tween.tween_method(Callable(self, "_set_funds_roll"), open_assets, total, 0.90).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_roll_tween.tween_method(Callable(self, "_set_delta_roll"), 0.0, pnl, 0.90).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_roll_tween.tween_method(Callable(self, "_set_total_roll"), open_assets, total, 0.90).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_roll_tween.tween_method(Callable(self, "_set_cash_roll"), 0.0, cash, 0.78).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_roll_tween.tween_method(Callable(self, "_set_holding_roll"), 0.0, holding, 0.78).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_roll_tween.tween_method(Callable(self, "_set_price_roll"), open_price, close_price, 0.78).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_roll_tween.chain().tween_callback(_on_roll_finished)

	_pnl_tween = create_tween()
	_pnl_tween.tween_property(_lbl_pnl, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pnl_tween.tween_property(_lbl_pnl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _open_assets() -> float:
	if _summary.has("open_assets"):
		return float(_summary.get("open_assets", 0.0))
	return float(_summary.get("total_assets", 0.0)) - float(_summary.get("day_pnl", 0.0))


func _set_funds_roll(value: float) -> void:
	var open_assets: float = _open_assets()
	_lbl_pnl.text = "¥%s" % UF.fmt_money(value)
	_lbl_pnl.add_theme_color_override("font_color", UF.COL_UP if value >= open_assets else UF.COL_DOWN)


func _set_delta_roll(value: float) -> void:
	var positive: bool = value >= 0.0
	_lbl_delta.text = "今日盈亏 %s¥%s" % ["+" if positive else "-", UF.fmt_money(abs(value))]
	_lbl_delta.add_theme_color_override("font_color", UF.COL_UP if positive else UF.COL_DOWN)


func _set_price_roll(close_value: float) -> void:
	var open_price: float = float(_summary.get("open_price", close_value))
	var pct: float = (close_value / open_price - 1.0) * 100.0 if open_price > 0.0 else 0.0
	_lbl_price.text = "开盘 ¥%.2f → 收盘 ¥%.2f  (%+.2f%%)" % [open_price, close_value, pct]


func _set_total_roll(value: float) -> void:
	_lbl_total.text = "¥%s" % UF.fmt_money(value)


func _set_open_assets_roll(value: float) -> void:
	_lbl_open_assets.text = "¥%s" % UF.fmt_money(value)


func _set_cash_roll(value: float) -> void:
	_lbl_cash.text = "¥%s" % UF.fmt_money(value)


func _set_holding_roll(value: float) -> void:
	_lbl_holding.text = "¥%s" % UF.fmt_money(value)


func _set_forced_text() -> void:
	var forced_shares: int = int(_summary.get("forced_liquidation_shares", 0))
	if forced_shares <= 0:
		_lbl_forced.text = "尾盘持仓已清空"
		_lbl_forced.add_theme_color_override("font_color", UF.COL_TEXT_DIM)
		return
	var discount: float = float(_summary.get("forced_discount", 0.8))
	var proceeds: float = float(_summary.get("forced_liquidation_proceeds", 0.0))
	_lbl_forced.text = "尾盘强制清仓: %d 股 × %.0f%% = ¥%s" % [
		forced_shares,
		discount * 100.0,
		UF.fmt_money(proceeds)
	]
	_lbl_forced.add_theme_color_override("font_color", UF.COL_HIGHLIGHT)


func _on_roll_finished() -> void:
	_btn_continue.disabled = false


func _on_continue_pressed() -> void:
	visible = false
	continue_requested.emit()
