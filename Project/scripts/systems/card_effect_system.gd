# 卡牌效果系统 (纯数据驱动)
# 所有效果参数来自 cards.csv 的 6 列: buy_pct, sell_pct, price_pct, emotion_delta, trade_price_pct, trade_shares
# 加新卡只需要在 CSV 填参数, 不需要动这个文件
# 只有全新的效果"类型"(不在这 6 种原子操作之内的)才需要扩展此文件
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