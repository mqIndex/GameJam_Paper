extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const Effects = preload("res://scripts/views/effects.gd")

@onready var k_chart: Control = $KChart
@onready var tooltip = $Tooltip
@onready var flash_overlay: ColorRect = $FlashOverlay

# Cached layout from last _draw_intraday for hover detection
var _intraday_layout: Dictionary = {}
var _daily_layout: Dictionary = {}

const RIGHT_AXIS_W: float = 92.0
const CHART_LEFT_PAD: float = 8.0
const SECTION_LABEL_H: float = 22.0
const DAILY_BOTTOM_PAD: float = 20.0
const INTRADAY_BOTTOM_PAD: float = 14.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	k_chart.draw.connect(_on_draw_chart)
	k_chart.mouse_filter = Control.MOUSE_FILTER_PASS
	k_chart.mouse_exited.connect(_on_k_chart_mouse_exited)
	Game.state_changed.connect(_on_state_changed)
	Game.candle_committed.connect(_on_candle_committed)
	Game.intraday_updated.connect(_on_intraday_updated)
	Game.turn_ended.connect(_on_turn_ended)
	Game.danmaku_requested.connect(show_danmaku)


func _on_state_changed() -> void:
	_queue_redraw()


func _on_candle_committed(_turn_global: int) -> void:
	_queue_redraw()


func _on_turn_ended(_day: int, _turn_in_day: int) -> void:
	_queue_redraw()


func _process(_delta: float) -> void:
	if k_chart and k_chart.get_global_rect().has_point(get_global_mouse_position()):
		_update_tooltip(k_chart.get_local_mouse_position())
	elif tooltip and tooltip.visible:
		tooltip.hide_tooltip()


func _on_k_chart_mouse_exited() -> void:
	if tooltip:
		tooltip.hide_tooltip()


func _update_tooltip(local_pos: Vector2) -> void:
	if tooltip == null:
		return
	if not _daily_layout.is_empty():
		var d_area: Rect2 = _daily_layout["area"]
		if d_area.has_point(local_pos):
			_show_daily_tooltip(local_pos)
			return
	if not _intraday_layout.is_empty():
		var i_area: Rect2 = _intraday_layout["area"]
		if i_area.has_point(local_pos):
			_show_intraday_tooltip(local_pos)
			return
	tooltip.hide_tooltip()


func _show_daily_tooltip(local_pos: Vector2) -> void:
	var slot_w: float = _daily_layout["slot_w"]
	var draw_x: float = _daily_layout["draw_x"]
	var slot_idx: int = int((local_pos.x - draw_x) / slot_w)
	var turn: int = slot_idx + 1
	var daily_candles: Array = _daily_layout["candles"]
	var found: Dictionary = {}
	for c in daily_candles:
		if int(c["turn_in_day"]) == turn:
			found = c
			break
	if found.is_empty():
		tooltip.hide_tooltip()
		return
	var pct: float = 0.0
	var op_val: float = float(found["open"])
	if op_val > 0.001:
		pct = (float(found["close"]) / op_val - 1.0) * 100.0
	var cards: Array = found.get("cards", [])
	if found.has("_floating") and cards.is_empty():
		for ic in Game.intraday_candles:
			if ic["kind"] == "play" or ic["kind"] == "opponent":
				cards.append(String(ic["card_name"]))
	var cards_text: String = ""
	if not cards.is_empty():
		cards_text = "出牌: " + ", ".join(cards)
	var candle_data: Dictionary = {
		"card_name": "回合 %d" % turn,
		"price_delta_pct": pct,
		"ohlc": "开%.2f 高%.2f 低%.2f 收%.2f" % [float(found["open"]), float(found["high"]), float(found["low"]), float(found["close"])],
	}
	if cards_text != "":
		candle_data["cards_played"] = cards_text
	var area: Rect2 = _daily_layout["area"]
	var slot_cx: float = draw_x + (float(turn) - 0.5) * slot_w
	var anchor := Vector2(k_chart.position.x + slot_cx + slot_w * 0.5 + 4, k_chart.position.y + area.position.y + 8)
	tooltip.show_at(candle_data, anchor)


func _show_intraday_tooltip(local_pos: Vector2) -> void:
	var slot_w: float = _intraday_layout["slot_w"]
	var draw_x: float = _intraday_layout["draw_x"]
	var idx: int = int((local_pos.x - draw_x) / slot_w)
	var candles_arr: Array = Game.intraday_candles
	if idx < 0 or idx >= candles_arr.size():
		tooltip.hide_tooltip()
		return
	var candle: Dictionary = candles_arr[idx]
	var kind := String(candle.get("kind", ""))
	var source: String
	match kind:
		"play":
			source = "玩家出牌"
		"opponent":
			source = "对手行动"
		_:
			source = "市场波动"
	var data: Dictionary = candle.duplicate()
	data["source"] = source
	var area: Rect2 = _intraday_layout["area"]
	var slot_cx: float = draw_x + (float(idx) + 0.5) * slot_w
	var anchor := Vector2(k_chart.position.x + slot_cx + slot_w * 0.5 + 4, k_chart.position.y + area.position.y + 8)
	tooltip.show_at(data, anchor)


func _on_intraday_updated() -> void:
	_queue_redraw()
	var candles: Array = Game.intraday_candles
	if candles.is_empty():
		return
	var last: Dictionary = candles[candles.size() - 1]
	var price_pct: float = float(last.get("price_delta_pct", 0.0))
	if abs(price_pct) >= 1.5:
		Effects.shake_node(get_tree().root.get_node_or_null("Main"), 4.0, 0.18)
		var flash_color: Color = UF.COL_UP if price_pct > 0.0 else UF.COL_DOWN
		Effects.flash_rect(flash_overlay, flash_color, 0.30)


func _queue_redraw() -> void:
	if k_chart:
		k_chart.queue_redraw()


func show_danmaku(messages: Array, intensity: int = 1) -> void:
	if k_chart == null or messages.is_empty():
		return
	var count: int = clampi(messages.size() * max(1, intensity), 1, 10)
	var chart_rect := Rect2(Vector2.ZERO, k_chart.size)
	for i in range(count):
		var text: String = String(messages[i % messages.size()])
		var label := Label.new()
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_as_relative = false
		label.z_index = 340
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.84))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.78))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		k_chart.add_child(label)
		var lane_h: float = max(22.0, chart_rect.size.y * 0.12)
		var min_y: float = chart_rect.size.y * 0.14
		var max_y: float = max(min_y, chart_rect.size.y * 0.78)
		var y: float = min_y + fmod(float(i) * lane_h + randf() * 18.0, max_y - min_y + 1.0)
		var start_x: float = chart_rect.size.x + 24.0 + float(i) * 18.0
		label.position = Vector2(start_x, y)
		var travel: float = chart_rect.size.x + max(140.0, float(text.length()) * 18.0)
		var duration: float = 5.2 + randf() * 1.1
		var tw := label.create_tween()
		tw.tween_property(label, "position:x", start_x - travel, duration).set_trans(Tween.TRANS_LINEAR)
		tw.parallel().tween_property(label, "modulate:a", 0.0, 0.35).set_delay(max(0.1, duration - 0.35))
		tw.tween_callback(Callable(self, "_free_danmaku_label").bind(weakref(label)))


func _free_danmaku_label(label_ref: WeakRef) -> void:
	var label := label_ref.get_ref() as Node
	if label != null:
		label.queue_free()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("card_index")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	Game.play_card(int(data["card_index"]))


func _on_draw_chart() -> void:
	if k_chart == null:
		return
	var w: float = k_chart.size.x
	var h: float = k_chart.size.y
	var split: float = h * 0.62 - 4.0
	var top := Rect2(0, 0, w, split)
	var bot := Rect2(0, split + 8, w, h - split - 8)
	_draw_section_label(top, "回合 K (本天蜡烛)", UF.COL_GOLD)
	_draw_section_label(bot, "分时折线 (本回合)", UF.COL_HIGHLIGHT)
	_draw_daily_candles(top)
	_draw_intraday(bot)


func _draw_section_label(r: Rect2, txt: String, col: Color) -> void:
	k_chart.draw_rect(r, UF.COL_BORDER, false, 1.0)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(r.position.x + 6, r.position.y + 14),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _price_to_y(price_value: float, p_min: float, p_max: float, draw_y: float, draw_h: float) -> float:
	return draw_y + draw_h - (price_value - p_min) / (p_max - p_min) * draw_h


func _price_to_y_clamped(price_value: float, p_min: float, p_max: float, draw_y: float, draw_h: float) -> float:
	return clampf(_price_to_y(price_value, p_min, p_max, draw_y, draw_h), draw_y, draw_y + draw_h)


func _bottom_anchored_range(base_price: float, observed_min: float, observed_max: float, min_span: float) -> Dictionary:
	var base: float = max(base_price, 0.01)
	var p_min: float = min(base, observed_min)
	var upward_span: float = max(observed_max - base, min_span)
	var downward_span: float = max(base - p_min, 0.0)
	var p_max: float = base + max(upward_span, downward_span * 3.0, min_span)
	if downward_span > 0.0:
		p_min -= max(downward_span * 0.08, min_span * 0.02)
	p_max += max((p_max - base) * 0.10, min_span * 0.04)
	if p_max - p_min < 0.01:
		p_max = p_min + 1.0
	return {"min": p_min, "max": p_max}


func _draw_right_axis_label(draw_x: float, draw_y: float, draw_w: float, draw_h: float, y: float, label: String, col: Color, font_size: int = 11) -> void:
	var label_x: float = draw_x + draw_w + 5.0
	var label_y: float = clampf(y + 4.0, draw_y + 11.0, draw_y + draw_h - 2.0)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(label_x, label_y),
		label, HORIZONTAL_ALIGNMENT_LEFT, RIGHT_AXIS_W - 6.0, font_size, col)


func _draw_horizontal_price_line(draw_x: float, draw_y: float, draw_w: float, draw_h: float, p_min: float, p_max: float, price_value: float, label: String, col: Color) -> void:
	if price_value <= 0.0 or p_max <= p_min:
		return
	var y: float = _price_to_y_clamped(price_value, p_min, p_max, draw_y, draw_h)
	k_chart.draw_dashed_line(
		Vector2(draw_x, y), Vector2(draw_x + draw_w, y),
		Color(col.r, col.g, col.b, 0.82), 1.2, 5.0, true)
	_draw_right_axis_label(draw_x, draw_y, draw_w, draw_h, y, label, col, 11)


func _opponent_liquidation_line() -> float:
	var opp = Game.get_opponent_state()
	if opp == null or not opp.present or opp.defeated_this_level:
		return 0.0
	return opp.liquidation_price


func _draw_daily_candles(r: Rect2) -> void:
	var draw_x: float = r.position.x + CHART_LEFT_PAD
	var draw_y: float = r.position.y + SECTION_LABEL_H
	var draw_w: float = max(40.0, r.size.x - CHART_LEFT_PAD - RIGHT_AXIS_W)
	var draw_h: float = max(24.0, r.size.y - SECTION_LABEL_H - DAILY_BOTTOM_PAD)

	var current_day: int = max(Game.day, 1)
	var todays: Array = []
	for c in Game.candles:
		if c["day"] == current_day:
			todays.append(c)

	if not Game.is_level_over and Game.intraday_ticks.size() > 0:
		todays.append({
			"day": current_day,
			"turn_in_day": Game.turn_in_day,
			"open": Game.cur_open,
			"high": Game.cur_high,
			"low": Game.cur_low,
			"close": Game.price,
			"_floating": true,
		})

	if todays.is_empty():
		_daily_layout = {}
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(r.position.x + 8, r.position.y + r.size.y * 0.55),
			"等待回合结算后生成小时 K...", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UF.COL_TEXT_DIM)
		return

	var day_base: float = max(Game.day_open_price, 0.01)
	var observed_min: float = todays[0]["low"]
	var observed_max: float = todays[0]["high"]
	for c in todays:
		observed_min = min(observed_min, float(c["low"]))
		observed_max = max(observed_max, float(c["high"]))
	var range := _bottom_anchored_range(day_base, observed_min, observed_max, max(day_base * 0.08, 2.0))
	var p_min: float = float(range["min"])
	var p_max: float = float(range["max"])
	var avg_cost_line: float = Game.get_average_cost_price()
	var liquidation_line: float = _opponent_liquidation_line()

	var base_y: float = _price_to_y_clamped(day_base, p_min, p_max, draw_y, draw_h)
	k_chart.draw_dashed_line(
		Vector2(draw_x, base_y), Vector2(draw_x + draw_w, base_y),
		UF.COL_TEXT_DIM, 1.0, 4.0, true)
	_draw_right_axis_label(draw_x, draw_y, draw_w, draw_h, base_y, "开 ¥%.2f" % day_base, UF.COL_TEXT_DIM, 11)
	if avg_cost_line > 0.0:
		_draw_horizontal_price_line(draw_x, draw_y, draw_w, draw_h, p_min, p_max, avg_cost_line, "成本 ¥%.2f" % avg_cost_line, UF.COL_BLUE)
	if liquidation_line > 0.0:
		_draw_horizontal_price_line(draw_x, draw_y, draw_w, draw_h, p_min, p_max, liquidation_line, "爆仓 ¥%.1f" % liquidation_line, UF.COL_DOWN)

	var slot_w: float = draw_w / float(Game.TURNS_PER_DAY)
	var body_w: float = max(slot_w * 0.65, 6.0)
	_daily_layout = {
		"area": Rect2(draw_x, draw_y, draw_w, draw_h),
		"draw_x": draw_x,
		"slot_w": slot_w,
		"candles": todays,
	}
	for c in todays:
		var t: int = int(c["turn_in_day"])
		var slot_x: float = draw_x + (float(t) - 0.5) * slot_w
		var op: float = float(c["open"])
		var cl: float = float(c["close"])
		var hi: float = float(c["high"])
		var lo: float = float(c["low"])
		var up: bool = cl >= op
		var col := UF.COL_UP if up else UF.COL_DOWN
		var hi_y: float = _price_to_y_clamped(hi, p_min, p_max, draw_y, draw_h)
		var lo_y: float = _price_to_y_clamped(lo, p_min, p_max, draw_y, draw_h)
		k_chart.draw_line(Vector2(slot_x, hi_y), Vector2(slot_x, lo_y), col, 1.0)
		var op_y: float = _price_to_y_clamped(op, p_min, p_max, draw_y, draw_h)
		var cl_y: float = _price_to_y_clamped(cl, p_min, p_max, draw_y, draw_h)
		var top_y: float = min(op_y, cl_y)
		var body_h: float = max(abs(op_y - cl_y), 1.0)
		var rect2: Rect2 = Rect2(slot_x - body_w * 0.5, top_y, body_w, body_h)
		if c.has("_floating") and c["_floating"]:
			var fade: Color = Color(col.r, col.g, col.b, 0.4)
			k_chart.draw_rect(rect2, fade, true)
			k_chart.draw_rect(rect2, col, false, 1.0)
		else:
			k_chart.draw_rect(rect2, col, true)

	for i in range(3):
		var ratio: float = float(i) / 2.0
		var y: float = draw_y + draw_h - ratio * draw_h
		var p: float = p_min + ratio * (p_max - p_min)
		if i == 0 and abs(p - day_base) < 0.01:
			continue
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, y + 4),
			"¥%.0f" % p, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UF.COL_TEXT_DIM)
	for tt in range(1, Game.TURNS_PER_DAY + 1):
		var x: float = draw_x + (float(tt) - 0.5) * slot_w
		var lc: Color = UF.COL_HIGHLIGHT if tt == Game.turn_in_day else UF.COL_TEXT_DIM
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(x - 4, r.position.y + r.size.y - 2),
			"%d" % tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)


func _draw_intraday(r: Rect2) -> void:
	var draw_x: float = r.position.x + CHART_LEFT_PAD
	var draw_y: float = r.position.y + SECTION_LABEL_H
	var draw_w: float = max(40.0, r.size.x - CHART_LEFT_PAD - RIGHT_AXIS_W)
	var draw_h: float = max(22.0, r.size.y - SECTION_LABEL_H - INTRADAY_BOTTOM_PAD)

	var candles: Array = Game.intraday_candles
	var slot_count: int = max(10, candles.size())
	var slot: float = draw_w / float(slot_count)

	# Cache layout for hover detection in _update_tooltip
	_intraday_layout = {
		"area": Rect2(draw_x, draw_y, draw_w, draw_h),
		"draw_x": draw_x,
		"slot_w": slot,
	}

	var turn_base: float = max(Game.cur_open, 0.01)
	var observed_min: float = turn_base
	var observed_max: float = turn_base
	for c in candles:
		observed_min = min(observed_min, float(c.get("low", c.get("close", turn_base))))
		observed_max = max(observed_max, float(c.get("high", c.get("close", turn_base))))
	var range := _bottom_anchored_range(turn_base, observed_min, observed_max, max(turn_base * 0.06, 1.2))
	var p_min: float = float(range["min"])
	var p_max: float = float(range["max"])

	var base_y: float = _price_to_y_clamped(turn_base, p_min, p_max, draw_y, draw_h)
	k_chart.draw_dashed_line(
		Vector2(draw_x, base_y), Vector2(draw_x + draw_w, base_y),
		UF.COL_TEXT_DIM, 1.0, 4.0, true)
	_draw_right_axis_label(draw_x, draw_y, draw_w, draw_h, base_y, "开 ¥%.2f" % turn_base, UF.COL_TEXT_DIM, 11)

	if candles.is_empty():
		var y: float = base_y
		var cx: float = draw_x + slot * 0.5
		k_chart.draw_line(Vector2(cx - 4, y), Vector2(cx + 4, y), UF.COL_TEXT_DIM, 1.0)
		k_chart.draw_line(Vector2(cx, y - 3), Vector2(cx, y + 3), UF.COL_TEXT_DIM, 1.0)
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(cx + 8, y - 4),
			"¥%.2f (回合开始)" % turn_base, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UF.COL_TEXT_DIM)
		for i in range(3):
			var ratio: float = float(i) / 2.0
			var yy: float = draw_y + draw_h - ratio * draw_h
			var pp: float = p_min + ratio * (p_max - p_min)
			if i == 0 and abs(pp - turn_base) < 0.01:
				continue
			k_chart.draw_string(
				ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, yy + 4),
				"¥%.1f" % pp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UF.COL_TEXT_DIM)
		return

	var prev_price: float = turn_base
	var prev_point := Vector2(draw_x, _price_to_y_clamped(prev_price, p_min, p_max, draw_y, draw_h))
	for i in range(candles.size()):
		var c2: Dictionary = candles[i]
		var cl: float = float(c2["close"])
		var slot_cx: float = draw_x + (float(i) + 0.5) * slot
		var col: Color
		if cl > prev_price:
			col = UF.COL_UP
		elif cl < prev_price:
			col = UF.COL_DOWN
		else:
			col = UF.COL_TEXT_DIM
		var point := Vector2(slot_cx, _price_to_y_clamped(cl, p_min, p_max, draw_y, draw_h))
		k_chart.draw_line(prev_point, point, Color(col.r, col.g, col.b, 0.85), 2.0)
		k_chart.draw_circle(point, 3.5, col)
		if c2.has("kind") and c2["kind"] == "settle":
			k_chart.draw_arc(point, 6.0, 0.0, TAU, 18, UF.COL_GOLD, 1.2)
		elif c2.has("kind") and c2["kind"] == "opponent":
			_draw_opponent_marker(c2, slot_cx, Rect2(point.x - 4.0, point.y - 4.0, 8.0, 8.0), r)
		prev_price = cl
		prev_point = point

	var last_price: float = float(candles[candles.size() - 1]["close"])
	var last_y: float = _price_to_y_clamped(last_price, p_min, p_max, draw_y, draw_h)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, last_y - 2),
		"¥%.2f" % last_price, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UF.COL_HIGHLIGHT)

	for i in range(3):
		var ratio: float = float(i) / 2.0
		var y: float = draw_y + draw_h - ratio * draw_h
		var p: float = p_min + ratio * (p_max - p_min)
		if i == 0 and abs(p - turn_base) < 0.01:
			continue
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, y + 4),
			"¥%.1f" % p, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UF.COL_TEXT_DIM)


func _draw_opponent_marker(candle: Dictionary, slot_cx: float, candle_rect: Rect2, section: Rect2) -> void:
	var pct: float = float(candle.get("price_delta_pct", 0.0))
	var marker_color: Color
	if pct > 0.0:
		marker_color = UF.COL_UP
	elif pct < 0.0:
		marker_color = UF.COL_DOWN
	else:
		marker_color = UF.COL_GOLD
	k_chart.draw_rect(candle_rect.grow(1.0), marker_color, false, 1.5)
	var marker_center_y: float = clampf(candle_rect.position.y - 11.0, section.position.y + 16.0, section.position.y + section.size.y - 18.0)
	var marker_center := Vector2(slot_cx, marker_center_y)
	k_chart.draw_dashed_line(
		Vector2(slot_cx, marker_center_y + 8.0),
		Vector2(slot_cx, candle_rect.position.y),
		Color(marker_color.r, marker_color.g, marker_color.b, 0.45),
		1.0, 3.0, true)
	k_chart.draw_circle(marker_center, 7.0, Color(0.0, 0.0, 0.0, 0.72))
	k_chart.draw_arc(marker_center, 7.0, 0.0, TAU, 18, marker_color, 1.2)
	k_chart.draw_string(
		ThemeDB.fallback_font, marker_center + Vector2(-5.0, 4.0),
		"庄", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, marker_color)
	var label: String = String(candle.get("effect_label", ""))
	if label != "":
		k_chart.draw_string(
			ThemeDB.fallback_font, marker_center + Vector2(10.0, 4.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, marker_color)
