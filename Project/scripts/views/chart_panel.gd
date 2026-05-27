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

# 分时折线: 视觉滚动 trail (纯渲染, 不进 game_state)
const TRAIL_PX_PER_SEC: float = 60.0          # 向左滚动速度
const TRAIL_SAMPLE_HZ: float = 60.0           # 采样频率
const TRAIL_JITTER_PCT: float = 0.006         # 待机抖动幅度 (相对当前价的百分比)
const TRAIL_SHOCK_DURATION: float = 0.2       # 突涨/突跌动画时长
const BASE_Y_SPAN_PCT: float = 0.05           # 半高基础值 (±5%); 实际半高根据本回合极值自适应放大
const Y_SPAN_PADDING: float = 1.15            # 极值之外再保留 15% 余量
const Y_SPAN_LERP_RATE: float = 4.0           # span 自适应平滑速率 (每秒收敛比例; 越大越快)
const TRAIL_SAMPLE_MAX: int = 900             # ring buffer 上限 (~15s @ 60Hz)

var _trail_samples: PackedFloat32Array = PackedFloat32Array()
var _trail_sample_accum: float = 0.0
var _trail_render_anchor: float = -1.0        # 渲染层当前价 (突变期间 tween 到 Game.price)
var _shock_t: float = 0.0                     # 剩余 shock 动画时间
var _shock_from_anchor: float = 0.0           # shock 起点 anchor 值
var _shock_dir: int = 0                       # +1 涨 / -1 跌 / 0 无
var _jitter_t: float = 0.0                    # jitter 相位累计
var _y_span_pct: float = BASE_Y_SPAN_PCT      # 当前渲染半高 (每帧向目标值 lerp)
var _y_center_price: float = -1.0             # 渲染中线对应的价格 (向本回合 hi/lo 中点 lerp)


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
	_y_span_pct = BASE_Y_SPAN_PCT
	_y_center_price = -1.0
	_queue_redraw()


func _process(delta: float) -> void:
	_tick_trail(delta)
	if k_chart and k_chart.get_global_rect().has_point(get_global_mouse_position()):
		_update_tooltip(k_chart.get_local_mouse_position())
	elif tooltip and tooltip.visible:
		tooltip.hide_tooltip()


# 分时滚动 trail: 每帧把 Game.price + 待机抖动/shock 过渡 push 进环形 buffer; 突变时 0.2s ease_out 过渡
func _tick_trail(delta: float) -> void:
	if k_chart == null:
		return
	var target_price: float = max(Game.price, 0.01)
	# 初次进入: 锚点对齐当前价, 填一段平直线 (相当于"从左侧直线连接到原点")
	if _trail_render_anchor <= 0.0:
		_trail_render_anchor = target_price
		_trail_samples.clear()
		for i in range(TRAIL_SAMPLE_MAX):
			_trail_samples.append(target_price)
		_trail_sample_accum = 0.0
		_jitter_t = 0.0
		_shock_t = 0.0
		_shock_dir = 0
	# Shock 阶段: 用 ease_out 从 shock_from 过渡到目标价; 完成后再回落到 jitter 待机
	if _shock_t > 0.0:
		_shock_t = max(_shock_t - delta, 0.0)
		var alpha: float = 1.0 - (_shock_t / TRAIL_SHOCK_DURATION)
		var eased: float = 1.0 - pow(1.0 - alpha, 3.0)
		_trail_render_anchor = lerp(_shock_from_anchor, target_price, eased)
	else:
		_trail_render_anchor = target_price
	# 抖动: 给 anchor 叠加正弦+随机 (纯视觉; 不影响 push 的 anchor 主轴)
	_jitter_t += delta
	var jitter_amp: float = target_price * TRAIL_JITTER_PCT
	var jitter: float = sin(_jitter_t * 6.7) * jitter_amp * 0.55 + (randf() - 0.5) * jitter_amp * 0.9
	var sample_value: float = _trail_render_anchor + jitter
	# 以固定频率向 buffer push, 形成稳定向左的滚动节奏
	_trail_sample_accum += delta * TRAIL_SAMPLE_HZ
	var push_n: int = int(_trail_sample_accum)
	if push_n > 0:
		_trail_sample_accum -= float(push_n)
		for i in range(push_n):
			_trail_samples.append(sample_value)
		var overflow: int = _trail_samples.size() - TRAIL_SAMPLE_MAX
		if overflow > 0:
			# PackedFloat32Array 没有 pop_front; 用 slice 重建
			_trail_samples = _trail_samples.slice(overflow)
	# 自适应 Y 中线 + 半高: 仿股票分时图; 中线向本回合 hi/lo 中点漂移, 半高围绕中线扩大
	var base_for_span: float = max(Game.cur_open, 0.01)
	var hi_p: float = max(max(Game.cur_high, Game.price), base_for_span)
	var lo_p: float = Game.cur_low if Game.cur_low > 0.0 else base_for_span
	lo_p = min(min(lo_p, Game.price), base_for_span)
	var mid_p: float = (hi_p + lo_p) * 0.5
	if _y_center_price <= 0.0:
		_y_center_price = base_for_span
	var lerp_t: float = clampf(delta * Y_SPAN_LERP_RATE, 0.0, 1.0)
	_y_center_price = lerp(_y_center_price, mid_p, lerp_t)
	var center_for_span: float = max(_y_center_price, 0.01)
	var dev_up: float = (hi_p - center_for_span) / center_for_span
	var dev_dn: float = (center_for_span - lo_p) / center_for_span
	var target_span: float = max(BASE_Y_SPAN_PCT, max(dev_up, dev_dn) * Y_SPAN_PADDING)
	_y_span_pct = lerp(_y_span_pct, target_span, lerp_t)
	_queue_redraw()


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
	# 触发 0.2s shock 动画 (所有 apply_price_change 通路都会让 intraday_candles 末尾 price_delta_pct != 0)
	if abs(price_pct) > 0.001:
		_shock_from_anchor = _trail_render_anchor if _trail_render_anchor > 0.0 else max(Game.price, 0.01)
		_shock_t = TRAIL_SHOCK_DURATION
		_shock_dir = 1 if price_pct > 0.0 else -1
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
		_draw_horizontal_price_line(draw_x, draw_y, draw_w, draw_h, p_min, p_max, avg_cost_line, "成本 ¥%.2f" % avg_cost_line, Color("#fae1b9"))
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

	# 新分时机制: 原点 (当前价点) X 固定在中央; Y 围绕 "开盘价基准线 = 垂直中线" 起伏
	# 滚动 trail 由 _tick_trail 维护, 这里只负责把 buffer 渲染成左 → 中央 的折线
	_intraday_layout = {}   # 关闭旧的 per-slot hover tooltip

	var turn_base: float = max(Game.cur_open, 0.01)
	var center_price: float = _y_center_price if _y_center_price > 0.0 else turn_base
	var anchor_x: float = draw_x + draw_w * 0.5
	var base_y: float = draw_y + draw_h * 0.5
	var y_scale: float = (draw_h * 0.5) / max(_y_span_pct, 0.0001)

	# 开盘价基准虚线: 位置根据 cur_open 相对动态中线浮动
	var open_y: float = _sample_to_y(turn_base, center_price, base_y, y_scale, draw_y, draw_h)
	k_chart.draw_dashed_line(
		Vector2(draw_x, open_y), Vector2(draw_x + draw_w, open_y),
		UF.COL_TEXT_DIM, 1.0, 4.0, true)
	_draw_right_axis_label(draw_x, draw_y, draw_w, draw_h, open_y, "开 ¥%.2f" % turn_base, UF.COL_TEXT_DIM, 11)

	# 中央 X 垂直参考线 (淡)
	k_chart.draw_line(
		Vector2(anchor_x, draw_y), Vector2(anchor_x, draw_y + draw_h),
		Color(UF.COL_TEXT_DIM.r, UF.COL_TEXT_DIM.g, UF.COL_TEXT_DIM.b, 0.25), 1.0)

	# 折线颜色: 当前价相对开盘价
	var current_price: float = max(Game.price, 0.01)
	var trend_col: Color = UF.COL_UP if current_price >= turn_base else (UF.COL_DOWN if current_price < turn_base else UF.COL_TEXT_DIM)

	# 把 trail buffer 从右端 (中央) 向左铺
	var n: int = _trail_samples.size()
	if n >= 2:
		var px_per_sample: float = TRAIL_PX_PER_SEC / TRAIL_SAMPLE_HZ
		var prev_x: float = anchor_x
		var prev_y: float = _sample_to_y(_trail_samples[n - 1], center_price, base_y, y_scale, draw_y, draw_h)
		for k in range(1, n):
			var i: int = n - 1 - k
			var x: float = anchor_x - float(k) * px_per_sample
			if x < draw_x:
				break
			var y: float = _sample_to_y(_trail_samples[i], center_price, base_y, y_scale, draw_y, draw_h)
			k_chart.draw_line(Vector2(prev_x, prev_y), Vector2(x, y), Color(trend_col.r, trend_col.g, trend_col.b, 0.85), 2.0)
			prev_x = x
			prev_y = y

	# 原点 (当前价锚点) - 黄底菱形 + 淡色光晕; 叠加低频呼吸偏移让静态不锁死中线
	var anchor_breath: float = sin(_jitter_t * 0.95) * 0.6 + sin(_jitter_t * 1.7 + 1.3) * 0.4
	var anchor_breath_amp: float = center_price * 0.0035
	var anchor_base_price: float = _trail_render_anchor if _trail_render_anchor > 0.0 else current_price
	var anchor_y: float = _sample_to_y(anchor_base_price + anchor_breath * anchor_breath_amp, center_price, base_y, y_scale, draw_y, draw_h)
	var diamond_r: float = 6.0
	var dpts := PackedVector2Array([
		Vector2(anchor_x, anchor_y - diamond_r),
		Vector2(anchor_x + diamond_r, anchor_y),
		Vector2(anchor_x, anchor_y + diamond_r),
		Vector2(anchor_x - diamond_r, anchor_y),
	])
	k_chart.draw_colored_polygon(dpts, UF.COL_GOLD)
	var halo_r: float = diamond_r + 2.5
	var halo_pts := PackedVector2Array([
		Vector2(anchor_x, anchor_y - halo_r),
		Vector2(anchor_x + halo_r, anchor_y),
		Vector2(anchor_x, anchor_y + halo_r),
		Vector2(anchor_x - halo_r, anchor_y),
		Vector2(anchor_x, anchor_y - halo_r),
	])
	k_chart.draw_polyline(halo_pts, Color(UF.COL_GOLD.r, UF.COL_GOLD.g, UF.COL_GOLD.b, 0.55), 1.2)

	# Shock 期间叠加上 / 下 箭头闪光
	if _shock_t > 0.0 and _shock_dir != 0:
		var alpha: float = clampf(_shock_t / TRAIL_SHOCK_DURATION, 0.0, 1.0)
		var arrow_col: Color = UF.COL_UP if _shock_dir > 0 else UF.COL_DOWN
		arrow_col.a = alpha
		var dy: float = -14.0 if _shock_dir > 0 else 14.0
		var tip := Vector2(anchor_x, anchor_y + dy)
		var base_pt := Vector2(anchor_x, anchor_y)
		k_chart.draw_line(base_pt, tip, arrow_col, 2.5)
		k_chart.draw_line(tip, tip + Vector2(-5.0, -sign(dy) * 6.0), arrow_col, 2.5)
		k_chart.draw_line(tip, tip + Vector2( 5.0, -sign(dy) * 6.0), arrow_col, 2.5)

	# 右侧实时价文字
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, anchor_y - 2),
		"¥%.2f" % current_price, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UF.COL_HIGHLIGHT)


# 价格 → Y; 以 base_price (运行时中线价) 为中央, ±_y_span_pct 映射到 ±draw_h/2 (中线+半高均自适应)
func _sample_to_y(sample_price: float, base_price: float, base_y: float, y_scale: float, draw_y: float, draw_h: float) -> float:
	var rel: float = (sample_price - base_price) / max(base_price, 0.01)
	var y: float = base_y - rel * y_scale
	return clampf(y, draw_y + 2.0, draw_y + draw_h - 2.0)


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
