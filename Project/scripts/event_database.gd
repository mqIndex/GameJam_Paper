# 事件数据库 (类 CardDatabase 风格)
# - 集中管理 25 条突发事件定义
# - 提供 build_event_pool() / make_by_id()
# 依据: docs/20260522_改动总结.md + 参考清单 25 条
extends RefCounted

const Event = preload("res://scripts/event.gd")


# ---- 公开 API ----

# 整池: 25 个 Event 实例 (每次调用新建一份, 不共享状态)
static func build_event_pool() -> Array:
	var pool: Array = []
	for def in _EVENT_DEFS:
		pool.append(_from_dict(def))
	return pool


# 按 id 单条构造
static func make_by_id(event_id: String) -> Event:
	for def in _EVENT_DEFS:
		if String(def.get("id", "")) == event_id:
			return _from_dict(def)
	push_warning("Unknown event_id: %s" % event_id)
	return null


# 全部事件 id (UI/调试用)
static func all_event_ids() -> Array:
	var ids: Array = []
	for def in _EVENT_DEFS:
		ids.append(String(def.get("id", "")))
	return ids


# ---- 内部: dict → Event ----
static func _from_dict(def: Dictionary) -> Event:
	var cat: int = Event.Category.NEUTRAL
	match String(def.get("category", "neutral")):
		"good": cat = Event.Category.GOOD
		"bad":  cat = Event.Category.BAD
		_:      cat = Event.Category.NEUTRAL
	var ev: Event = Event.new(
		String(def.get("id", "")),
		String(def.get("name", "")),
		cat,
		String(def.get("desc", "")),
		String(def.get("effect_desc", "")))
	ev.delta_bull        = int(def.get("delta_bull", 0))
	ev.delta_bull_random = int(def.get("delta_bull_random", 0))
	ev.price_rate        = float(def.get("price_rate", 0.0))
	ev.emotion_floor     = int(def.get("emotion_floor", -1))
	ev.emotion_ceiling   = int(def.get("emotion_ceiling", -1))
	ev.ap_chaos          = bool(def.get("ap_chaos", false))
	ev.dur_turns         = int(def.get("dur_turns", -1))
	var raw_mods: Variant = def.get("modifiers", {})
	if raw_mods is Dictionary:
		ev.modifiers = (raw_mods as Dictionary).duplicate()
	var raw_ban: Variant = def.get("banned", [])
	if raw_ban is Array:
		ev.banned_effect_ids = (raw_ban as Array).duplicate()
	return ev


# ---- 数据: 25 条事件定义 ----
# schema:
#   id / name / category("good"|"bad"|"neutral")
#   desc / effect_desc
#   一次性: delta_bull / delta_bull_random / price_rate / emotion_floor / emotion_ceiling / ap_chaos
#   持续:   modifiers (Dictionary) / dur_turns (>0=短期) / banned (Array of effect_id)
const _EVENT_DEFS: Array = [
	# --- 利好情绪 ---
	{"id": "rate_cut",   "name": "降息",     "category": "good",
		"desc": "央行降低基准利率, 市场资金流动性高, 投资氛围浓厚",
		"effect_desc": "市场情绪 +10",
		"delta_bull": 10},
	{"id": "ext_surge",  "name": "外盘暴涨", "category": "good",
		"desc": "隔夜海外市场大涨, 乐观情绪迅速蔓延至本地市场",
		"effect_desc": "市场情绪 +20",
		"delta_bull": 20},
	{"id": "golden_age", "name": "黄金时代", "category": "good",
		"desc": "牛市预期形成, 所有人都相信「这次不一样」",
		"effect_desc": "市场情绪 +30",
		"delta_bull": 30},

	# --- 利空情绪 ---
	{"id": "rate_hike",  "name": "加息",     "category": "bad",
		"desc": "资金成本上升, 市场冷静下来",
		"effect_desc": "市场情绪 -10",
		"delta_bull": -10},
	{"id": "ext_crash",  "name": "外盘暴跌", "category": "bad",
		"desc": "海外市场跌停, 引发人心动荡",
		"effect_desc": "市场情绪 -20",
		"delta_bull": -20},
	{"id": "war_risk",   "name": "战争风险", "category": "bad",
		"desc": "全球避险情绪升温, 投资者信心动摇",
		"effect_desc": "市场情绪 -30",
		"delta_bull": -30},

	# --- 股价直接冲击 ---
	{"id": "double_up",  "name": "盈利双击", "category": "good",
		"desc": "业绩超出估值预期同时发生, 股价进入加速上涨阶段",
		"effect_desc": "当前股价 +20%",
		"price_rate": 0.20},
	{"id": "black_swan", "name": "黑天鹅",   "category": "bad",
		"desc": "无法预测的重大危机出现, 市场陷入恐慌",
		"effect_desc": "股价立刻 -20%",
		"price_rate": -0.20},

	# --- 情绪锚定 ---
	{"id": "faith_recharge", "name": "信仰充值", "category": "good",
		"desc": "用户进入「长期持有」状态, 即使下跌也坚定持仓信心",
		"effect_desc": "本时段情绪不会低于 50 (低于会被拉回 50)",
		"emotion_floor": 50},
	{"id": "faith_collapse", "name": "信仰崩塌", "category": "bad",
		"desc": "市场未来一片不好, 投资者信心丢失",
		"effect_desc": "本时段情绪不会高于 50 (高于会被压回 50)",
		"emotion_ceiling": 50},

	# --- 持续 3 回合修饰 ---
	{"id": "good_news_amp", "name": "超预期财报", "category": "good",
		"desc": "公司发布远超市场预期, 资金开始抢入流通",
		"effect_desc": "情绪 +5, 接下来 3 回合卡牌上涨效果 +20%",
		"delta_bull": 5,
		"modifiers": {"card_price_up_mul": 1.2},
		"dur_turns": 3},
	{"id": "bad_news_amp", "name": "财报逆袭", "category": "bad",
		"desc": "企业被传出违规风波, 信任度受到挑战",
		"effect_desc": "情绪 -5, 接下来 3 回合卡牌下跌效果 +20%",
		"delta_bull": -5,
		"modifiers": {"card_price_down_mul": 1.2},
		"dur_turns": 3},

	# --- 长期修饰 ---
	{"id": "amp_up_card",   "name": "火线预期", "category": "good",
		"desc": "市场热度突破阈值, 任何利好情绪都被放大",
		"effect_desc": "卡牌使用上涨效果 +20%",
		"modifiers": {"card_price_up_mul": 1.2}},
	{"id": "amp_down_card", "name": "下行预期", "category": "bad",
		"desc": "市场一致认为未来更差, 悲观情绪开始扩散",
		"effect_desc": "卡牌使用下跌效果 +20%",
		"modifiers": {"card_price_down_mul": 1.2}},
	{"id": "leverage_surge", "name": "杠杆涨市", "category": "neutral",
		"desc": "杠杆资金涌入, 多空双方都在加码, 波动放大",
		"effect_desc": "买入/卖出造成的价格影响 ×1.5",
		"modifiers": {"card_trade_price_mul": 1.5}},
	{"id": "risk_warning",  "name": "风险警示", "category": "neutral",
		"desc": "监管部门发出风险提示, 投资者开始倾向谨慎",
		"effect_desc": "情绪对价格的影响减半",
		"modifiers": {"emotion_modifier_mul": 0.5}},
	{"id": "market_decouple", "name": "市场失真", "category": "neutral",
		"desc": "情绪与价格极度脱钩, 市场进入非理性状态",
		"effect_desc": "价格与情绪暂时脱钩 (情绪倍率 = 1.0)",
		"modifiers": {"decouple": true}},

	# --- 涨跌停 ---
	{"id": "cap_up",   "name": "限制涨停", "category": "neutral",
		"desc": "监管层担忧市场过热, 限制单日上涨涨幅",
		"effect_desc": "单回合最大涨幅 ≤ 5%",
		"modifiers": {"cap_drift_up": 0.05}},
	{"id": "cap_down", "name": "限制跌停", "category": "neutral",
		"desc": "为防止恐慌扩散, 监管层限制单日下跌跌幅",
		"effect_desc": "单回合最大跌幅 ≤ 5%",
		"modifiers": {"cap_drift_down": 0.05}},

	# --- 牌库 / 行动力干扰 ---
	{"id": "freeze_account", "name": "账户审查", "category": "bad",
		"desc": "监管机构对涉嫌违规交易进行管控",
		"effect_desc": "每回合自动冻结一张手牌 (随机入弃牌堆)",
		"modifiers": {"freeze_per_turn": 1}},
	{"id": "key_monitor",    "name": "重点监控", "category": "bad",
		"desc": "高频交易者投机行为被监控严打",
		"effect_desc": "每回合最多使用 2 张技能牌",
		"modifiers": {"skill_cap_per_turn": 2}},
	{"id": "chaos_day",      "name": "混乱之日", "category": "neutral",
		"desc": "市场系统陷入危机, 交易行为可能失常",
		"effect_desc": "每回合 50% 行动力 +1, 50% 行动力 -1",
		"ap_chaos": true},

	# --- 神秘资金 / 意外事件 ---
	{"id": "mystery_money",  "name": "神秘资金", "category": "neutral",
		"desc": "一股莫名的资金悄然进场, 市场波动幅度加大",
		"effect_desc": "本时段回合末有 30% 概率额外 ±5%",
		"modifiers": {"mystery_active": true}},
	{"id": "accident_event", "name": "意外事件", "category": "neutral",
		"desc": "各种真假难辨的离奇事件涌现, 市场情绪被牵动",
		"effect_desc": "情绪当回合随机变化 ±10",
		"delta_bull_random": 10},
]