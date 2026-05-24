# 卡牌数据库
# 重构后: 卡牌定义全部从 ConfigLoader (Cfg, autoload /root/Cfg) 读取
# 不再硬编码任何卡牌字段; 加新卡只需改 data/cards.csv
# 仅当 Cfg 缺失某 effect_id 时, 才回退到一张占位 "未知" 卡 (并 push_warning)
extends RefCounted

const Card = preload("res://scripts/card.gd")


# 初始牌组: 遍历 cards.csv 里 in_starter=true 的卡, 按 starter_count 数量生成
static func build_starter_deck() -> Array:
	var deck: Array = []
	var cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	if cfg == null:
		push_error("[CardDatabase] /root/Cfg 未挂载, 起始牌组为空")
		return deck
	for d in cfg.starter_deck_defs():
		var eid: String = d["effect_id"]
		var n: int = int(d["count"])
		for i in range(n):
			deck.append(make_by_effect(eid, "%s_%d" % [eid, i]))
	return deck


# ---- 工厂: 按 effect_id 造一张新卡 (用 unique_id 区分实例) ----
static func make_by_effect(effect_id: String, unique_id: String, transient: bool = false) -> Card:
	var cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	var t: Variant = null if cfg == null else cfg.get_card_template(effect_id)
	if t == null:
		push_warning("Unknown effect_id in factory: %s" % effect_id)
		return Card.new(unique_id, "未知", Card.Kind.SKILL, 1, "?", effect_id, "", transient)
	var card := Card.new(
		unique_id,
		String(t.get("name", "?")),
		Card.kind_from_string(String(t.get("kind", "SKILL"))),
		int(t.get("cost", 1)),
		String(t.get("description", "")),
		effect_id,
		String(t.get("image_path", "")),
		transient,
	)
	card.shop_price  = int(t.get("shop_price", 0))
	card.daily_limit = int(t.get("daily_limit", 0))
	card.daily_exile = bool(t.get("daily_exile", false))
	return card


# ---- 升级映射: effect_id → 升级版 effect_id; "" = 不能升级 ----
static func upgrade_target(effect_id: String) -> String:
	var cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	if cfg == null:
		return ""
	var t: Variant = cfg.get_card_template(effect_id)
	if t == null:
		return ""
	return String(t.get("upgrade_to", ""))


# ---- 商店占位卡池: 每天展示 6 张; 用 seed 轮选, 保持测试可重复 ----
# owned_effect_ids: 玩家当前牌组里的所有 effect_id, 用来过滤 shop_unique=TRUE 且已拥有的卡
static func build_shop_offers(seed_index: int, owned_effect_ids: Array = []) -> Array:
	var offers: Array = []
	var cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	if cfg == null:
		return offers
	var raw_pool: Array = cfg.shop_pool_ids()
	if raw_pool.is_empty():
		return offers
	# 1) 过滤 shop_unique 已拥有的
	var pool: Array = []
	for eid in raw_pool:
		var t: Variant = cfg.get_card_template(eid)
		var unique: bool = t != null and bool(t.get("shop_unique", false))
		if unique and owned_effect_ids.has(eid):
			continue
		pool.append(eid)
	if pool.is_empty():
		return offers
	# 2) 按 seed 轮选, 同一天 6 张内 effect_id 不重复; 池小于 6 时直接展示全部
	var picked_ids: Dictionary = {}
	var step: int = 0
	while offers.size() < 6 and step < pool.size() * 2:
		var eid: String = pool[(seed_index + step) % pool.size()]
		step += 1
		if picked_ids.has(eid):
			continue
		picked_ids[eid] = true
		offers.append(make_by_effect(eid, "shop_%d_%s" % [seed_index, eid]))
	return offers
