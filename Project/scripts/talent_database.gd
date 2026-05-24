# 天赋数据库
# 模板从 ConfigLoader (Cfg, autoload /root/Cfg) 读取
# 加新天赋只需要改 data/talents.csv
extends RefCounted

const Talent = preload("res://scripts/talent.gd")


# ---- 工厂: 按 id 造一个天赋实例 ----
static func make_by_id(talent_id: String) -> Talent:
	var cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	var t: Variant = null if cfg == null else cfg.get_talent_template(talent_id)
	if t == null:
		push_warning("Unknown talent_id in factory: %s" % talent_id)
		return Talent.new(talent_id, "未知天赋", "?", 0, talent_id, false)
	return Talent.new(
		talent_id,
		String(t.get("name", "?")),
		String(t.get("description", "")),
		int(t.get("price", 0)),
		String(t.get("effect_id", talent_id)),
		bool(t.get("in_first_day", false)),
	)


# ---- 第一天可购天赋: 排除玩家已拥有的 ----
static func build_first_day_offers(owned_talent_ids: Array = []) -> Array:
	var offers: Array = []
	var cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	if cfg == null:
		return offers
	for tid in cfg.first_day_talent_ids():
		if owned_talent_ids.has(tid):
			continue
		offers.append(make_by_id(tid))
	return offers