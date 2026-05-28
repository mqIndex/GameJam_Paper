# 卡牌效果系统 (纯数据驱动)
# 所有效果参数来自 cards.csv 的列, 加新卡只需要在 CSV 填参数, 不需要动这个文件
# 只有全新的效果"类型"才需要扩展此文件
# 优先级: trade_shares > 0 时按"固定股数"买卖 (新规则); 否则回退到 buy_pct / sell_pct (按比例)
# 突发事件 modifier 落点:
#   card_price_up_mul   → 技能牌 price_pct 正方向倍率
#   card_price_down_mul → 技能牌 price_pct 负方向倍率
#   card_trade_price_mul → 买/卖牌 trade_price_pct 整体倍率
extends RefCounted

var _gs: Node

func _init(game_state: Node) -> void:
	_gs = game_state


func dispatch(effect_id: String) -> void:
	var cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	var tpl: Variant = null if cfg == null else cfg.get_card_template(effect_id)
	if tpl == null:
		push_warning("Unknown effect_id: %s" % effect_id)
		return

	var kind_str: String = String(tpl.get("kind", "SKILL")).strip_edges().to_upper()
	var buy_pct: float = float(tpl.get("buy_pct", 0.0))
	var sell_pct: float = float(tpl.get("sell_pct", 0.0))
	var price_pct: float = float(tpl.get("price_pct", 0.0))
	var emotion_delta: int = int(tpl.get("emotion_delta", 0))
	var trade_price_pct: float = float(tpl.get("trade_price_pct", 0.0))
	var trade_shares: int = int(tpl.get("trade_shares", 0))
	var draw_count: int = int(tpl.get("draw_count", 0))
	# 情绪锚定 / 反转 / 回合倍率 / 事件刷新
	var emotion_set: int = int(tpl.get("emotion_set", -1))
	var emotion_invert: bool = bool(tpl.get("emotion_invert", false))
	var reroll_event: bool = bool(tpl.get("reroll_event", false))
	var emotion_mul_turn: float = float(tpl.get("emotion_mul_turn", 0.0))
	var emotion_mul_duration: int = int(tpl.get("emotion_mul_duration", 1))
	# 选择类机制 (内幕/顺势/计划/流动性/化整)
	var event_preview: bool = bool(tpl.get("event_preview", false))
	var discard_then_draw: bool = bool(tpl.get("discard_then_draw", false))
	var discard_draw_count: int = int(tpl.get("discard_draw_count", 1))
	var topdeck_pick: bool = bool(tpl.get("topdeck_pick", false))
	var liquidity_chance: float = float(tpl.get("liquidity_chance", 0.0))
	var liquidity_reduction: int = int(tpl.get("liquidity_reduction", 1))
	var shatter: bool = bool(tpl.get("shatter", false))
	# 奖励卡 (击败敌人后获得)
	var mob_swing_mul: float = float(tpl.get("mob_swing_mul", 1.0))
	var sell_bonus_mul: float = float(tpl.get("sell_bonus_mul", 0.0))
	var ap_bonus: int = int(tpl.get("ap_bonus", 0))

	# 突发事件 modifier 叠加
	var em: Dictionary = _gs.event_modifiers
	var up_mul: float = float(em.get("card_price_up_mul", 1.0))
	var down_mul: float = float(em.get("card_price_down_mul", 1.0))
	var trade_mul: float = float(em.get("card_trade_price_mul", 1.0))
	if price_pct > 0.0:
		price_pct *= up_mul
	elif price_pct < 0.0:
		price_pct *= down_mul
	trade_price_pct *= trade_mul

	# 情绪先于价格 (panic_basic: 先降情绪再压价, 情绪会影响压价倍率)
	# 锚定 / 反转优先于 delta (稳定人心 / 舆论反转)
	if emotion_invert:
		_gs.invert_emotion()
	if emotion_set >= 0:
		_gs.set_emotion_bull(emotion_set)
	# 水军出动: 给本回合 (及后续 duration-1 回合) 情绪变化设倍率, 不影响本卡自身的 emotion_delta (本卡 delta=0)
	if emotion_mul_turn > 0.0:
		_gs.turn_emotion_mul = emotion_mul_turn
		_gs.turn_emotion_mul_duration = max(1, emotion_mul_duration)
		if _gs.turn_emotion_mul_duration > 1:
			_gs._log("  [情绪倍率] ×%.1f 持续 %d 回合" % [emotion_mul_turn, _gs.turn_emotion_mul_duration])
		else:
			_gs._log("  [情绪倍率] 本回合 ×%.1f" % emotion_mul_turn)
	# 保命之道: 本回合所有卖出收入 × sell_bonus_mul (放在卖出之前, 保证若本卡同时含卖出动作也受益)
	if sell_bonus_mul > 0.0:
		_gs.turn_sell_bonus_mul = sell_bonus_mul
		_gs._log("  [卖出加成] 本回合卖出现金 ×%.2f" % sell_bonus_mul)
	# 超绝手速: 直接给当前回合补行动力 (不抬上限, 仅影响 action_points 余额)
	if ap_bonus > 0:
		_gs.action_points += ap_bonus
		_gs._log("  [行动力] +%d → %d" % [ap_bonus, _gs.action_points])
	if emotion_delta != 0:
		_gs.apply_emotion_delta_bull(emotion_delta)

	# 买/卖: trade_shares > 0 → 按股数; 否则按 buy_pct / sell_pct 比例
	if trade_shares > 0:
		if kind_str == "BUY":
			_gs._buy_shares(trade_shares, trade_price_pct)
		elif kind_str == "SELL":
			_gs._sell_shares(trade_shares, trade_price_pct)
	elif buy_pct > 0.0:
		_gs._buy_with_cash(_gs.cash * buy_pct, trade_price_pct)
	elif sell_pct > 0.0:
		_gs._sell_shares(int(floor(float(_gs.shares) * sell_pct)), trade_price_pct)

	if price_pct != 0.0:
		_gs.apply_price_change(price_pct)

	# 风云变幻: 强制刷新当前突发事件 (排在最后, 避免被本卡其它效果污染)
	if reroll_event:
		_gs._log("  [风云变幻] 刷新当前突发事件")
		_gs._trigger_random_event()

	# 选择类卡: 由 game_state 发 request_* 信号给 UI; UI 收集后回调 apply_*
	if event_preview:
		_gs.request_event_preview()
	if discard_then_draw:
		_gs.pending_discard_draw_count = max(1, discard_draw_count)
		_gs.request_discard_choice()
	if topdeck_pick:
		_gs.request_topdeck_choice()
	if liquidity_chance > 0.0:
		_gs.try_apply_liquidity(liquidity_chance, liquidity_reduction)
	if shatter:
		_gs.request_shatter()
	if bool(tpl.get("discard_hand_redraw", false)):
		_gs.discard_hand_redraw()
	if bool(tpl.get("mob_swing", false)):
		_gs.apply_mob_swing(mob_swing_mul)

	if draw_count > 0:
		_gs.draw_cards(draw_count)
