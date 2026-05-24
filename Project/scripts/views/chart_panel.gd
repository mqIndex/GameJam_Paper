extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const Effects = preload("res://scripts/views/effects.gd")

@onready var k_chart: Control = $KChart
@onready var tooltip = $Tooltip
@onready var flash_overlay: ColorRect = $FlashOverlay

# Cached layout from last _draw_intraday for hover detection
var _intraday_layout: Dictionary = {}
var _daily_layout: Dictionary = {}


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	k_chart.draw.connect(_on_draw_chart)
	k_chart.mouse_filter = Control.MOUSE_FILTER_PASS
	k_chart.mouse_exited.connect(_on_k_chart_mouse_exited)
	Game.state_changed.connect(func(): _queue_redraw())
	Game.candle_committed.connect(func(_t): _queue_redraw())
	Game.intraday_updated.connect(_on_intraday_updated)
	Game.turn_ended.connect(func(_d, _t): _queue_redraw())


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
			if ic["kind"] == "play":
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
	var source: String = "玩家出牌" if candle.get("kind", "") == "play" else "市场波动"
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


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("card_index")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	Game.play_card(int(data["card_index"]))


func _on_draw_chart() -> void:
	if k_chart == null:
		return
	var w: float = k_chart.size.x
	var h: float = k_chart.size.y
	var split: float = h * 0.55 - 4.0
	var top := Rect2(0, 0, w, split)
	var bot := Rect2(0, split + 8, w, h - split - 8)
	_draw_section_label(top, "小时 K (本天蜡烛)", UF.COL_GOLD)
	_draw_section_label(bot, "分钟 K (本回合)", UF.COL_HIGHLIGHT)
	_draw_daily_candles(top)
	_draw_intraday(bot)


func _draw_section_label(r: Rect2, txt: String, col: Color) -> void:
	k_chart.draw_rect(r, UF.COL_BORDER, false, 1.0)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(r.position.x + 6, r.position.y + 14),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_daily_candles(r: Rect2) -> void:
	var draw_x: float = r.position.x + 8
	var draw_y: float = r.position.y + 22
	var draw_w: float = r.size.x - 70
	var draw_h: float = r.size.y - 36

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

	var p_min: float = todays[0]["low"]
	var p_max: float = todays[0]["high"]
	for c in todays:
		if c["low"] < p_min:
			p_min = c["low"]
		if c["high"] > p_max:
			p_max = c["high"]
	p_min = min(p_min, Game.INITIAL_PRICE)
	p_max = max(p_max, Game.INITIAL_PRICE)
	if p_max - p_min < 1.0:
		p_max += 1.0
		p_min -= 1.0
	var pad: float = (p_max - p_min) * 0.1
	p_min -= pad
	p_max += pad

	var base_y: float = draw_y + draw_h - (Game.INITIAL_PRICE - p_min) / (p_max - p_min) * draw_h
	k_chart.draw_dashed_line(
		Vector2(draw_x, base_y), Vector2(draw_x + draw_w, base_y),
		UF.COL_TEXT_DIM, 1.0, 4.0, true)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(draw_x + 2, base_y - 2),
		"¥%.0f" % Game.INITIAL_PRICE, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UF.COL_TEXT_DIM)

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
		var hi_y: float = draw_y + draw_h - (hi - p_min) / (p_max - p_min) * draw_h
		var lo_y: float = draw_y + draw_h - (lo - p_min) / (p_max - p_min) * draw_h
		k_chart.draw_line(Vector2(slot_x, hi_y), Vector2(slot_x, lo_y), col, 1.0)
		var op_y: float = draw_y + draw_h - (op - p_min) / (p_max - p_min) * draw_h
		var cl_y: float = draw_y + draw_h - (cl - p_min) / (p_max - p_min) * draw_h
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
	var draw_x: float = r.position.x + 8
	var draw_y: float = r.position.y + 22
	var draw_w: float = r.size.x - 70
	var draw_h: float = r.size.y - 30

	var candles: Array = Game.intraday_candles
	var slot_count: int = 10
	var slot: float = draw_w / float(slot_count)
	var body_w: float = max(slot * 0.55, 3.0)

	# Cache layout for hover detection in _update_tooltip
	_intraday_layout = {
		"area": Rect2(draw_x, draw_y, draw_w, draw_h),
		"draw_x": draw_x,
		"slot_w": slot,
	}

	if candles.is_empty():
		var y: float = draw_y + draw_h * 0.5
		var cx: float = draw_x + slot * 0.5
		k_chart.draw_line(Vector2(cx - 4, y), Vector2(cx + 4, y), UF.COL_TEXT_DIM, 1.0)
		k_chart.draw_line(Vector2(cx, y - 3), Vector2(cx, y + 3), UF.COL_TEXT_DIM, 1.0)
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(cx + 8, y - 4),
			"¥%.2f (回合开始)" % Game.cur_open, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UF.COL_TEXT_DIM)
		var min_span_e: float = max(Game.cur_open * 0.10, 2.0)
		var p_min_e: float = Game.cur_open - min_span_e * 0.5
		var p_max_e: float = Game.cur_open + min_span_e * 0.5
		for i in range(3):
			var ratio: float = float(i) / 2.0
			var yy: float = draw_y + draw_h - ratio * draw_h
			var pp: float = p_min_e + ratio * (p_max_e - p_min_e)
			k_chart.draw_string(
				ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, yy + 4),
				"¥%.1f" % pp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UF.COL_TEXT_DIM)
		return

	var p_min: float = float(candles[0]["low"])
	var p_max: float = float(candles[0]["high"])
	for c in candles:
		if float(c["low"]) < p_min:
			p_min = float(c["low"])
		if float(c["high"]) > p_max:
			p_max = float(c["high"])
	if Game.cur_open < p_min:
		p_min = Game.cur_open
	if Game.cur_open > p_max:
		p_max = Game.cur_open
	var min_span: float = max(Game.cur_open * 0.10, 2.0)
	if p_max - p_min < min_span:
		var mid: float = (p_max + p_min) * 0.5
		p_min = mid - min_span * 0.5
		p_max = mid + min_span * 0.5
	var pad: float = (p_max - p_min) * 0.15
	p_min -= pad
	p_max += pad

	var base_y: float = draw_y + draw_h - (Game.cur_open - p_min) / (p_max - p_min) * draw_h
	k_chart.draw_dashed_line(
		Vector2(draw_x, base_y), Vector2(draw_x + draw_w, base_y),
		UF.COL_TEXT_DIM, 1.0, 4.0, true)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(draw_x + 2, base_y - 2),
		"开 ¥%.2f" % Game.cur_open, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UF.COL_TEXT_DIM)

	for i in range(candles.size()):
		var c2: Dictionary = candles[i]
		var op: float = float(c2["open"])
		var cl: float = float(c2["close"])
		var hi: float = float(c2["high"])
		var lo: float = float(c2["low"])
		var slot_cx: float = draw_x + (float(i) + 0.5) * slot
		var col: Color
		if cl > op:
			col = UF.COL_UP
		elif cl < op:
			col = UF.COL_DOWN
		else:
			col = UF.COL_TEXT_DIM
		var hi_y: float = draw_y + draw_h - (hi - p_min) / (p_max - p_min) * draw_h
		var lo_y: float = draw_y + draw_h - (lo - p_min) / (p_max - p_min) * draw_h
		k_chart.draw_line(Vector2(slot_cx, hi_y), Vector2(slot_cx, lo_y), col, 1.0)
		var op_y: float = draw_y + draw_h - (op - p_min) / (p_max - p_min) * draw_h
		var cl_y: float = draw_y + draw_h - (cl - p_min) / (p_max - p_min) * draw_h
		var top_y: float = min(op_y, cl_y)
		var body_h: float = max(abs(op_y - cl_y), 1.0)
		if abs(op - cl) < 0.01:
			k_chart.draw_line(
				Vector2(slot_cx - body_w * 0.5, op_y),
				Vector2(slot_cx + body_w * 0.5, op_y),
				col, 2.0)
		else:
			k_chart.draw_rect(
				Rect2(slot_cx - body_w * 0.5, top_y, body_w, body_h),
				col, true)
		if c2.has("kind") and c2["kind"] == "settle":
			k_chart.draw_rect(
				Rect2(slot_cx - body_w * 0.5 - 1, top_y - 1, body_w + 2, body_h + 2),
				UF.COL_GOLD, false, 1.0)

	var last_price: float = float(candles[candles.size() - 1]["close"])
	var last_y: float = draw_y + draw_h - (last_price - p_min) / (p_max - p_min) * draw_h
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, last_y - 2),
		"¥%.2f" % last_price, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UF.COL_HIGHLIGHT)

	for i in range(3):
		var ratio: float = float(i) / 2.0
		var y: float = draw_y + draw_h - ratio * draw_h
		var p: float = p_min + ratio * (p_max - p_min)
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, y + 4),
			"¥%.1f" % p, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UF.COL_TEXT_DIM)
