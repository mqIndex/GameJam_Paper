# 卡牌效果系统 (纯数据驱动)
# 所有效果参数来自 cards.csv 的 5 列: buy_pct, sell_pct, price_pct, emotion_delta, trade_price_pct
# 加新卡只需要在 CSV 填参数, 不需要动这个文件
# 只有全新的效果"类型"(不在这 5 种原子操作之内的)才需要扩展此文件
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

	var buy_pct: float = float(tpl.get("buy_pct", 0.0))
	var sell_pct: float = float(tpl.get("sell_pct", 0.0))
	var price_pct: float = float(tpl.get("price_pct", 0.0))
	var emotion_delta: int = int(tpl.get("emotion_delta", 0))
	var trade_price_pct: float = float(tpl.get("trade_price_pct", 0.0))

	# 情绪先于价格 (panic_basic: 先降情绪再压价, 情绪会影响压价倍率)
	if emotion_delta != 0:
		_gs.apply_emotion_delta_bull(emotion_delta)

	if buy_pct > 0.0:
		_gs._buy_with_cash(_gs.cash * buy_pct, trade_price_pct)
	elif sell_pct > 0.0:
		_gs._sell_shares(int(floor(float(_gs.shares) * sell_pct)), trade_price_pct)

	if price_pct != 0.0:
		_gs.apply_price_change(price_pct)
