extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

const AVATAR_PATH: String = "res://assets/baoshu_avatar.png"
const SCRIM_COLOR: Color = Color(0.0, 0.0, 0.0, 0.58)
const PANEL_COLOR: Color = Color(0.04, 0.07, 0.13, 0.86)
const HIGHLIGHT_PAD: float = 8.0
const DIALOG_H: float = 126.0
const SHOP_DIALOG_H: float = 140.0
const PROMPT_H: float = 64.0

class TutorialArrow:
	extends Control

	var fill_color: Color = Color(0.04, 0.07, 0.13, 0.86)
	var points_down: bool = true

	func _draw() -> void:
		var pts: PackedVector2Array
		if points_down:
			pts = PackedVector2Array([
				Vector2(0.0, 0.0),
				Vector2(size.x, 0.0),
				Vector2(size.x * 0.5, size.y),
			])
		else:
			pts = PackedVector2Array([
				Vector2(size.x * 0.5, 0.0),
				Vector2(0.0, size.y),
				Vector2(size.x, size.y),
			])
		draw_colored_polygon(pts, fill_color)


var _main: Control = null
var _steps: Array = []
var _step_index: int = -1
var _active: bool = false
var _mode: String = "level"
var _wait_shares: int = 0
var _wait_bull: int = 0
var _wait_cash: float = 0.0
var _pulse_tween: Tween = null
var _highlighted_card: Control = null

var _full_scrim: ColorRect = null
var _scrims: Array = []
var _highlight: Panel = null
var _dialog: PanelContainer = null
var _avatar: TextureRect = null
var _name_label: Label = null
var _dialog_text: Label = null
var _prompt: PanelContainer = null
var _prompt_text: Label = null
var _arrow: TutorialArrow = null
var _next_button: Button = null


func setup(main_node: Control) -> void:
	_main = main_node


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_steps()
	Game.state_changed.connect(_on_game_changed)
	Game.hand_changed.connect(_on_game_changed)
	resized.connect(_update_layout)


func _process(_delta: float) -> void:
	if _active and visible:
		_update_layout()


func start() -> void:
	if _active:
		return
	_mode = "level"
	_build_steps()
	if _full_scrim != null:
		_full_scrim.color = SCRIM_COLOR
	_set_scrim_blocks_input(true)
	_active = true
	visible = true
	_step_index = -1
	_go_next()


func start_shop() -> void:
	if _active:
		return
	_mode = "shop"
	_build_shop_steps()
	_set_scrim_blocks_input(true)
	Game.begin_shop_tutorial()
	_active = true
	visible = true
	_step_index = -1
	_go_next()
	_layout_shop_dialog()


func is_shop_tutorial_active() -> bool:
	return _active and _mode == "shop"


func handle_shop_continue() -> bool:
	if not is_shop_tutorial_active():
		return false
	if _step_index >= _steps.size() - 1:
		_finish_shop()
		return false
	_go_next()
	return true


func _set_scrim_blocks_input(blocks: bool) -> void:
	var filter := MOUSE_FILTER_STOP if blocks else MOUSE_FILTER_IGNORE
	if _full_scrim != null:
		_full_scrim.mouse_filter = filter
	for scrim in _scrims:
		(scrim as ColorRect).mouse_filter = filter


func _build_ui() -> void:
	_full_scrim = ColorRect.new()
	_full_scrim.color = SCRIM_COLOR
	_full_scrim.mouse_filter = MOUSE_FILTER_STOP
	add_child(_full_scrim)

	for i in range(4):
		var scrim := ColorRect.new()
		scrim.color = SCRIM_COLOR
		scrim.mouse_filter = MOUSE_FILTER_STOP
		add_child(scrim)
		_scrims.append(scrim)

	_highlight = Panel.new()
	_highlight.mouse_filter = MOUSE_FILTER_IGNORE
	_highlight.z_index = 3
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(1.0, 0.74, 0.24, 0.08)
	hsb.border_color = Color(1.0, 0.74, 0.24, 0.98)
	hsb.border_width_left = 2
	hsb.border_width_top = 2
	hsb.border_width_right = 2
	hsb.border_width_bottom = 2
	hsb.corner_radius_top_left = 5
	hsb.corner_radius_top_right = 5
	hsb.corner_radius_bottom_left = 5
	hsb.corner_radius_bottom_right = 5
	_highlight.add_theme_stylebox_override("panel", hsb)
	add_child(_highlight)

	_dialog = PanelContainer.new()
	_dialog.mouse_filter = MOUSE_FILTER_STOP
	_dialog.z_index = 5
	_dialog.add_theme_stylebox_override("panel", _box_style(UF.COL_GOLD, 14.0))
	add_child(_dialog)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_dialog.add_child(row)

	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = Vector2(76.0, 76.0)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := _load_avatar_texture()
	if tex != null:
		_avatar.texture = tex
	row.add_child(_avatar)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 5)
	row.add_child(text_box)

	_name_label = Label.new()
	_name_label.text = "宝叔"
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", UF.COL_GOLD)
	text_box.add_child(_name_label)

	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialog_text.add_theme_font_size_override("font_size", 14)
	_dialog_text.add_theme_color_override("font_color", UF.COL_TEXT)
	text_box.add_child(_dialog_text)

	_next_button = UF.button("下一步", UF.COL_GOLD, 13)
	_next_button.custom_minimum_size = Vector2(96.0, 30.0)
	_next_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_next_button.pressed.connect(_on_next_pressed)
	text_box.add_child(_next_button)

	_prompt = PanelContainer.new()
	_prompt.mouse_filter = MOUSE_FILTER_IGNORE
	_prompt.z_index = 6
	_prompt.add_theme_stylebox_override("panel", _box_style(UF.COL_HIGHLIGHT, 10.0))
	add_child(_prompt)

	_prompt_text = Label.new()
	_prompt_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_text.add_theme_font_size_override("font_size", 13)
	_prompt_text.add_theme_color_override("font_color", UF.COL_TEXT)
	_prompt.add_child(_prompt_text)

	_arrow = TutorialArrow.new()
	_arrow.mouse_filter = MOUSE_FILTER_IGNORE
	_arrow.z_index = 6
	_arrow.custom_minimum_size = Vector2(18.0, 14.0)
	_arrow.size = Vector2(18.0, 14.0)
	add_child(_arrow)


func _box_style(border: Color, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.border_color = Color(border.r, border.g, border.b, 0.74)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = margin
	sb.content_margin_top = margin * 0.72
	sb.content_margin_right = margin
	sb.content_margin_bottom = margin * 0.72
	return sb


func _load_avatar_texture() -> Texture2D:
	if not ResourceLoader.exists(AVATAR_PATH, "Texture2D"):
		push_warning("Tutorial avatar is waiting for Godot import: %s" % AVATAR_PATH)
		return null
	return load(AVATAR_PATH) as Texture2D


func _build_steps() -> void:
	_steps = [
		{
			"dialog": "小子，想赚钱，先看懂这三样东西：你的钱、你手里的货、还有市场的脸色。",
			"prompt": "",
			"button": "开始",
		},
		{
			"target_path": "PlayerPanel/VBox/LblCash",
			"dialog": "这是你的本金，也是你的命根子。牌打得再漂亮，现金断了就没法继续。",
			"prompt": "资金：当前可直接使用的现金。",
		},
		{
			"target_path": "DataPanel/VBox/StatsGrid/CellShares",
			"dialog": "这是你手里的筹码。手里没货，后面涨得再凶也跟你没关系。",
			"prompt": "筹码：你当前持有的股票数量。",
		},
		{
			"target_paths": ["TopBar/MidBar/HBox/IconEmotion", "TopBar/MidBar/HBox/LblEmotionTitle", "TopBar/MidBar/HBox/EmotionBarSlot", "TopBar/MidBar/HBox/LblEmotionState"],
			"dialog": "这根是市场情绪。情绪越火热，买盘和利好越容易把股价往上推；情绪越冷淡，卖压和坏消息造成的下跌也会更重。",
			"prompt": "市场情绪：火热会放大上涨，冷淡会放大下跌。",
		},
		{
			"target_effect": "buy_basic",
			"wait": "buy",
			"dialog": "先买点货。手里没东西，涨了也赚不到。",
			"prompt": "点击这张【买入】，用现金买入筹码。",
			"button": "",
		},
		{
			"target_path": "ChartPanel",
			"dialog": "看到了吗？你一买，价格和弹幕都会在图上反馈出来。买和卖的数量尽量别失衡。",
			"prompt": "K 线图会记录你的出牌效果。",
		},
		{
			"target_effect": "hype_basic",
			"wait": "hype",
			"dialog": "光自己买还不够，得让别人也想买。试试造势。",
			"prompt": "打出【大V吹票】，拉升市场热度。",
			"button": "",
		},
		{
			"target_paths": ["TopBar/MidBar/HBox/EmotionBarSlot", "TopBar/MidBar/HBox/LblEmotionState"],
			"dialog": "热度起来了，价格就更容易自己往上跑，这叫借势。",
			"prompt": "热度上涨后，后续买盘会更有力量。",
		},
		{
			"target_effect": "sell_basic",
			"wait": "sell",
			"dialog": "涨得不错了，但账面上的都是虚的。卖掉，钱回到账上，才算落袋。",
			"prompt": "打出【卖出】，把一部分筹码换回现金。",
			"button": "",
		},
		{
			"target_paths": ["PlayerTargetBar/LblTitle", "PlayerTargetBar/LblValue", "PlayerTargetBar/IconSlot"],
			"dialog": "记住这个闭环：低位买入，借势拉升，高位分批卖出。贪心的人，最后常常只剩故事。",
			"prompt": "教学完成。",
			"button": "开始正式游戏",
			"finish": true,
		},
	]


func _build_shop_steps() -> void:
	_steps = [
		{
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/买卡",
			"shop_tab": 0,
			"dialog": "这里可以买新牌。优先挑能补足短板、提高收益的牌，让你的卡组有更多打法。",
			"prompt": "购买：花现金把新牌加入卡组。",
		},
		{
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/升级",
			"shop_tab": 1,
			"dialog": "这里可以升级已有卡牌。少数关键牌变强，往往比单纯堆数量更稳定。",
			"prompt": "升级：强化常用牌，让核心策略更可靠。",
		},
		{
			"target_path": "ShopOverlay/ShopPanel/Margin/RootVBox/Tabs/删卡",
			"shop_tab": 2,
			"dialog": "这里可以删掉不想要的牌。卡组太厚会稀释关键牌，适当精简，才能更容易抽到真正想打的牌。",
			"prompt": "删卡：移除拖节奏的牌，压缩卡组。",
		},
	]


func _enter_step() -> void:
	if _step_index < 0 or _step_index >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_step_index]
	if step.has("shop_tab"):
		_select_shop_tab(int(step["shop_tab"]))
	if _mode == "shop":
		visible = true
		_dialog.visible = true
		_set_scrim_blocks_input(true)
	var effect_id: String = String(step.get("target_effect", ""))
	if effect_id != "":
		Game.tutorial_ensure_card_in_hand(effect_id)
		Game.tutorial_set_min_action_points(1)
	_wait_shares = Game.shares
	_wait_bull = Game.bull
	_wait_cash = Game.cash

	_dialog_text.text = String(step.get("dialog", ""))
	_prompt_text.text = String(step.get("prompt", ""))
	var button_text: String = String(step.get("button", "下一步"))
	if _mode == "shop":
		_next_button.visible = true
		_next_button.text = "知道了"
		_prompt.visible = false
		_arrow.visible = false
		_clear_card_highlight()
		_update_shop_button_text()
	else:
		_next_button.visible = button_text != ""
		_next_button.text = button_text
		_prompt.visible = String(step.get("prompt", "")) != ""
		_arrow.visible = _prompt.visible
	call_deferred("_update_layout")
	if _mode != "shop":
		_restart_highlight_pulse()


func _on_next_pressed() -> void:
	if not _active:
		return
	if _mode == "shop":
		_close_shop_dialog()
		return
	var step: Dictionary = _steps[_step_index]
	if bool(step.get("finish", false)):
		_finish()
	else:
		_go_next()


func _go_next() -> void:
	_step_index += 1
	_enter_step()


func _finish() -> void:
	if _mode == "shop":
		_finish_shop()
		return
	_active = false
	visible = false
	_clear_card_highlight()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	Game.finish_tutorial()
	Game.new_level()


func _finish_shop() -> void:
	_active = false
	visible = false
	_clear_card_highlight()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var shop := _shop_overlay()
	if shop != null and shop.has_method("clear_tutorial_button_override"):
		shop.call("clear_tutorial_button_override")
	Game.finish_shop_tutorial()


func close_shop_tutorial() -> void:
	if is_shop_tutorial_active():
		_finish_shop()


func _close_shop_dialog() -> void:
	if not is_shop_tutorial_active():
		return
	visible = false
	_dialog.visible = false
	_full_scrim.visible = false
	_set_scrim_blocks_input(false)


func _select_shop_tab(tab_index: int) -> void:
	var tabs: TabContainer = null
	if _main != null:
		tabs = _main.get_node_or_null("ShopOverlay/ShopPanel/Margin/RootVBox/Tabs") as TabContainer
	if tabs == null:
		return
	tabs.current_tab = clampi(tab_index, 0, max(0, tabs.get_tab_count() - 1))


func _update_shop_button_text() -> void:
	var shop := _shop_overlay()
	if shop == null or not shop.has_method("set_tutorial_button_override"):
		return
	var text := "关闭商店，进入下一天 →" if _step_index >= _steps.size() - 1 else "继续"
	shop.call("set_tutorial_button_override", text)


func _shop_overlay() -> Control:
	if _main == null:
		return null
	return _main.get_node_or_null("ShopOverlay") as Control


func _on_game_changed() -> void:
	if not _active or not visible:
		return
	if _check_step_completion():
		return
	call_deferred("_update_layout")


func _check_step_completion() -> bool:
	if _step_index < 0 or _step_index >= _steps.size():
		return false
	var step: Dictionary = _steps[_step_index]
	var wait_for: String = String(step.get("wait", ""))
	var done: bool = false
	match wait_for:
		"buy":
			done = Game.shares > _wait_shares
		"hype":
			done = Game.bull > _wait_bull
		"sell":
			done = Game.shares < _wait_shares and Game.cash > _wait_cash
		_:
			done = false
	if done:
		_go_next()
	return done


func _update_layout() -> void:
	if not _active or not visible:
		return
	var view := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		size = view
	if _mode == "shop":
		_layout_shop_dialog()
		return
	_full_scrim.position = Vector2.ZERO
	_full_scrim.size = size

	var target_ctrl := _current_target_control()
	var target_rect := _current_target_rect(target_ctrl)
	if target_rect.size.x <= 0.0 or target_rect.size.y <= 0.0:
		_layout_scrim_without_target()
		_position_dialog(Rect2())
		_prompt.visible = false
		_arrow.visible = false
		_clear_card_highlight()
		return

	target_rect = target_rect.grow(HIGHLIGHT_PAD)
	target_rect.position.x = clampf(target_rect.position.x, 0.0, max(0.0, size.x - 1.0))
	target_rect.position.y = clampf(target_rect.position.y, 0.0, max(0.0, size.y - 1.0))
	target_rect.size.x = min(target_rect.size.x, max(1.0, size.x - target_rect.position.x))
	target_rect.size.y = min(target_rect.size.y, max(1.0, size.y - target_rect.position.y))

	var should_show_prompt: bool = String((_steps[_step_index] as Dictionary).get("prompt", "")) != ""
	_prompt.visible = should_show_prompt
	_arrow.visible = should_show_prompt
	_layout_scrim_around(target_rect)
	if _is_card_step() and target_ctrl != null:
		_highlight.visible = false
		_set_card_highlight(target_ctrl)
	else:
		_clear_card_highlight()
		_highlight.visible = true
		_highlight.position = target_rect.position
		_highlight.size = target_rect.size
	var prompt_rect := _position_prompt(target_rect)
	_position_dialog(target_rect, prompt_rect)


func _layout_shop_dialog() -> void:
	_full_scrim.color = Color(0.0, 0.0, 0.0, 0.0)
	_full_scrim.position = Vector2.ZERO
	_full_scrim.size = size
	_full_scrim.visible = true
	_full_scrim.mouse_filter = MOUSE_FILTER_STOP
	for scrim in _scrims:
		(scrim as ColorRect).visible = false
	_highlight.visible = false
	_prompt.visible = false
	_arrow.visible = false
	_clear_card_highlight()
	_dialog.visible = true
	var w: float = min(620.0, max(360.0, size.x - 72.0))
	_dialog.size = Vector2(w, SHOP_DIALOG_H)
	_dialog.position = Vector2(
		(size.x - w) * 0.5,
		clampf(size.y * 0.58 - SHOP_DIALOG_H * 0.5, 56.0, max(56.0, size.y - SHOP_DIALOG_H - 56.0))
	)


func _layout_scrim_without_target() -> void:
	_full_scrim.visible = true
	for scrim in _scrims:
		(scrim as ColorRect).visible = false
	_highlight.visible = false


func _layout_scrim_around(rect: Rect2) -> void:
	_full_scrim.visible = false
	var top := _scrims[0] as ColorRect
	var bottom := _scrims[1] as ColorRect
	var left := _scrims[2] as ColorRect
	var right := _scrims[3] as ColorRect
	top.visible = true
	top.position = Vector2.ZERO
	top.size = Vector2(size.x, rect.position.y)
	bottom.visible = true
	bottom.position = Vector2(0.0, rect.end.y)
	bottom.size = Vector2(size.x, max(0.0, size.y - rect.end.y))
	left.visible = true
	left.position = Vector2(0.0, rect.position.y)
	left.size = Vector2(rect.position.x, rect.size.y)
	right.visible = true
	right.position = Vector2(rect.end.x, rect.position.y)
	right.size = Vector2(max(0.0, size.x - rect.end.x), rect.size.y)


func _position_dialog(target_rect: Rect2, prompt_rect: Rect2 = Rect2()) -> void:
	var w: float = min(580.0, max(320.0, size.x - 32.0))
	_dialog.size = Vector2(w, DIALOG_H)
	var dialog_size := Vector2(w, DIALOG_H)
	var candidates: Array = []
	var center_x: float = (size.x - dialog_size.x) * 0.5
	var near_prompt_x: float = center_x
	if prompt_rect.size.x > 0.0:
		near_prompt_x = prompt_rect.get_center().x - dialog_size.x * 0.5
	for raw_x in [center_x, near_prompt_x]:
		var x: float = clampf(float(raw_x), 18.0, max(18.0, size.x - dialog_size.x - 18.0))
		if prompt_rect.size.y > 0.0:
			candidates.append(Rect2(Vector2(x, prompt_rect.end.y + 14.0), dialog_size))
			candidates.append(Rect2(Vector2(x, prompt_rect.position.y - dialog_size.y - 14.0), dialog_size))
		else:
			candidates.append(Rect2(Vector2(x, size.y * 0.52 - dialog_size.y * 0.5), dialog_size))
	if candidates.is_empty():
		candidates.append(Rect2(Vector2(center_x, size.y * 0.52 - dialog_size.y * 0.5), dialog_size))

	var best: Rect2 = candidates[0]
	var best_score: float = INF
	for c in candidates:
		var r: Rect2 = c
		r.position.y = clampf(r.position.y, 16.0, max(16.0, size.y - r.size.y - 16.0))
		var score: float = 0.0
		if target_rect.size.x > 0.0:
			score += _overlap_area(r, target_rect) * 14.0
		if prompt_rect.size.x > 0.0:
			score += _overlap_area(r, prompt_rect) * 20.0
			score += r.get_center().distance_to(prompt_rect.get_center()) * 0.22
		score += abs(r.get_center().x - size.x * 0.5) * 0.36
		score += abs(r.get_center().y - size.y * 0.52) * 0.08
		if score < best_score:
			best_score = score
			best = r
	_dialog.position = best.position


func _position_prompt(target_rect: Rect2) -> Rect2:
	if not _prompt.visible:
		return Rect2()
	var w: float = min(320.0, max(220.0, size.x - 32.0))
	_prompt.size = Vector2(w, PROMPT_H)
	var picked := _pick_prompt_rect(target_rect, Vector2(w, PROMPT_H))
	_prompt.position = picked["rect"].position
	_arrow.points_down = bool(picked["above"])
	_arrow.size = Vector2(18.0, 14.0)
	var prompt_rect: Rect2 = picked["rect"]
	var arrow_x: float = clampf(target_rect.get_center().x - _arrow.size.x * 0.5, prompt_rect.position.x + 8.0, prompt_rect.end.x - _arrow.size.x - 8.0)
	var arrow_y: float = prompt_rect.end.y - 1.0 if _arrow.points_down else prompt_rect.position.y - _arrow.size.y + 1.0
	_arrow.position = Vector2(arrow_x, arrow_y)
	_arrow.queue_redraw()
	return prompt_rect


func _pick_prompt_rect(target_rect: Rect2, prompt_size: Vector2) -> Dictionary:
	var x: float = clampf(target_rect.get_center().x - prompt_size.x * 0.5, 14.0, max(14.0, size.x - prompt_size.x - 14.0))
	var above_rect := Rect2(Vector2(x, target_rect.position.y - prompt_size.y - 18.0), prompt_size)
	var below_rect := Rect2(Vector2(x, target_rect.end.y + 18.0), prompt_size)
	above_rect.position.y = clampf(above_rect.position.y, 12.0, max(12.0, size.y - prompt_size.y - 12.0))
	below_rect.position.y = clampf(below_rect.position.y, 12.0, max(12.0, size.y - prompt_size.y - 12.0))
	var prefer_above: bool = target_rect.position.y > size.y * 0.42
	var candidates: Array = [
		{"rect": above_rect, "above": true},
		{"rect": below_rect, "above": false},
	]
	if not prefer_above:
		candidates.reverse()
	var best: Dictionary = candidates[0]
	var best_score: float = INF
	for candidate in candidates:
		var r: Rect2 = candidate["rect"]
		var score: float = _overlap_area(r, target_rect) * 12.0
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _overlap_area(a: Rect2, b: Rect2) -> float:
	var inter := a.intersection(b)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return 0.0
	return inter.size.x * inter.size.y


func _current_target_control() -> Control:
	if _step_index < 0 or _step_index >= _steps.size() or _main == null:
		return null
	var step: Dictionary = _steps[_step_index]
	var effect_id: String = String(step.get("target_effect", ""))
	if effect_id != "":
		return _find_card_by_effect(effect_id)
	var path: String = String(step.get("target_path", ""))
	if path != "":
		return _main.get_node_or_null(path) as Control
	return null


func _current_target_rect(target_ctrl: Control) -> Rect2:
	if _step_index < 0 or _step_index >= _steps.size() or _main == null:
		return Rect2()
	var step: Dictionary = _steps[_step_index]
	if step.has("target_paths"):
		return _rect_for_paths(step["target_paths"])
	if target_ctrl == null or not is_instance_valid(target_ctrl):
		return Rect2()
	if not target_ctrl.is_visible_in_tree():
		return Rect2()
	return _control_global_rect(target_ctrl)


func _rect_for_paths(paths: Array) -> Rect2:
	var out := Rect2()
	var found: bool = false
	for path in paths:
		var ctrl := _main.get_node_or_null(String(path)) as Control
		if ctrl == null or not is_instance_valid(ctrl):
			continue
		if not ctrl.is_visible_in_tree():
			continue
		var r := _control_global_rect(ctrl)
		if not found:
			out = r
			found = true
		else:
			out = out.merge(r)
	return out if found else Rect2()


func _control_global_rect(ctrl: Control) -> Rect2:
	var xf := ctrl.get_global_transform()
	var corners := [
		xf * Vector2.ZERO,
		xf * Vector2(ctrl.size.x, 0.0),
		xf * Vector2(0.0, ctrl.size.y),
		xf * ctrl.size,
	]
	var min_p: Vector2 = corners[0]
	var max_p: Vector2 = corners[0]
	for p in corners:
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
	return Rect2(min_p, max_p - min_p)


func _is_card_step() -> bool:
	if _step_index < 0 or _step_index >= _steps.size():
		return false
	return String((_steps[_step_index] as Dictionary).get("target_effect", "")) != ""


func _set_card_highlight(card: Control) -> void:
	if _highlighted_card == card:
		return
	_clear_card_highlight()
	_highlighted_card = card
	if _highlighted_card.has_method("set_tutorial_highlight"):
		_highlighted_card.call("set_tutorial_highlight", true)


func _clear_card_highlight() -> void:
	if _highlighted_card != null and is_instance_valid(_highlighted_card) and _highlighted_card.has_method("set_tutorial_highlight"):
		_highlighted_card.call("set_tutorial_highlight", false)
	_highlighted_card = null


func _find_card_by_effect(effect_id: String) -> Control:
	if _main == null:
		return null
	var fan := _main.get_node_or_null("HandPanel/FanHandContainer")
	if fan == null:
		return null
	for child in fan.get_children():
		var ctrl := child as Control
		if ctrl != null and String(ctrl.get_meta("effect_id", "")) == effect_id:
			return ctrl
	return null


func _restart_highlight_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_highlight.modulate = Color(1, 1, 1, 1)
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(_highlight, "modulate:a", 0.42, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_highlight, "modulate:a", 1.0, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
