# 事件数据库 (类 CardDatabase 风格)
# - 集中管理 25 条突发事件定义
# - 提供 build_event_pool() / make_by_id()
# - 数据驱动: 事件图片与主题色从 res://data/event/Events_Visual.csv 读取;
#   _EVENT_DEFS 内嵌字段作 fallback (CSV 缺失时仍可跑)
# 依据: docs/20260522_改动总结.md + 参考清单 25 条
extends RefCounted

const Event = preload("res://scripts/event.gd")

# 外部美术表 (UTF-8 + BOM + 逗号分隔)
# 列: 突发事件(name), 解释, 效果, 主题色, 示例(image_path, 可含逗号需引号), 备注, 提示词参考
const VISUAL_CSV_PATH: String = "res://data/event/Events_Visual.csv"

# CSV 事件名 → _EVENT_DEFS.id 重映射 (CSV 的中文名与 _EVENT_DEFS.name 不完全一致, 此表显式对齐)
const _CSV_NAME_TO_ID: Dictionary = {
	"降息": "rate_cut",
	"外盘暴涨": "ext_surge",
	"黄金时代": "golden_age",
	"超预期财报": "good_news_amp",
	"火热预期": "amp_up_card",    # CSV "火热预期" ↔ _EVENT_DEFS "火线预期"
	"信仰充值": "faith_recharge",
	"加息": "rate_hike",
	"外盘暴跌": "ext_crash",
	"战争风险": "war_risk",
	"财务造假": "bad_news_amp",   # CSV "财务造假" ↔ _EVENT_DEFS "财报逆袭"
	"下行预期": "amp_down_card",
	"黑天鹅": "black_swan",
	"信仰崩塌": "faith_collapse",
	"猴市": "leverage_surge",     # CSV "猴市" ↔ _EVENT_DEFS "杠杆涨市"
	"神秘资金": "mystery_money",
	# "偃旗息鼓" 不在 _EVENT_DEFS 中, 跳过
	"限制涨停": "cap_up",
	"限制跌停": "cap_down",
	"账户审查": "freeze_account",
	"重点监控": "key_monitor",
	"混乱之日": "chaos_day",
	"鬼故事": "accident_event",   # CSV "鬼故事" ↔ _EVENT_DEFS "意外事件"
	"风险警示": "risk_warning",
	"市场失真": "market_decouple",
}

# CSV 缓存: id → {theme_color: String, image_path: String}; 懒加载, 仅尝试一次
static var _visual_table_cache: Dictionary = {}
static var _visual_table_loaded: bool = false


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
	# image_path / theme_color: 优先 CSV (Events_Visual.csv), 缺失时回退 _EVENT_DEFS 内嵌字段
	var visual: Dictionary = _get_visual_for(ev.id)
	ev.image_path        = String(visual.get("image_path", def.get("image_path", "")))
	ev.theme_color       = _parse_theme_color(visual.get("theme_color", def.get("theme_color", "")), cat)
	var raw_mods: Variant = def.get("modifiers", {})
	if raw_mods is Dictionary:
		ev.modifiers = (raw_mods as Dictionary).duplicate()
	var raw_ban: Variant = def.get("banned", [])
	if raw_ban is Array:
		ev.banned_effect_ids = (raw_ban as Array).duplicate()
	return ev


# ---- 外部 CSV 数据源 ----
# 懒加载: 第一次调用时尝试读 Events_Visual.csv; 文件缺失/解析失败时静默使用 _EVENT_DEFS fallback
static func _get_visual_for(event_id: String) -> Dictionary:
	if not _visual_table_loaded:
		_load_visual_table()
	return _visual_table_cache.get(event_id, {})


# 解析 Events_Visual.csv (UTF-8 + BOM + 逗号分隔, 支持双引号包裹的含逗号字段)
# 列顺序: 突发事件, 解释, 效果, 主题色, 示例, 备注, 提示词参考
# "示例" 列可能是单文件名或 "a.png,b.png,c.png" (用引号包裹), 取第一个非空作为 image_path
static func _load_visual_table() -> void:
	_visual_table_loaded = true
	if not FileAccess.file_exists(VISUAL_CSV_PATH):
		return
	var f := FileAccess.open(VISUAL_CSV_PATH, FileAccess.READ)
	if f == null:
		return
	# 读取全文并剥 UTF-8 BOM
	var text: String = f.get_as_text()
	f.close()
	if text.length() >= 1 and text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	var lines: PackedStringArray = text.split("\n")
	var first: bool = true
	for raw_line in lines:
		var line: String = String(raw_line).strip_edges()
		if line == "":
			continue
		if first:
			first = false  # 跳过表头
			continue
		var cols: Array = _parse_csv_line(line)
		if cols.size() < 5:
			continue
		var csv_name: String = String(cols[0]).strip_edges()
		var theme_color: String = String(cols[3]).strip_edges()
		var image_field: String = String(cols[4]).strip_edges()
		var image_file: String = _pick_first_image(image_field)
		var id: String = String(_CSV_NAME_TO_ID.get(csv_name, ""))
		if id == "":
			continue  # CSV 行无对应事件 id (如 "偃旗息鼓"), 跳过
		var image_path: String = ""
		if image_file != "":
			image_path = "res://data/event/" + image_file
		_visual_table_cache[id] = {
			"theme_color": theme_color,
			"image_path": image_path,
		}


# 解析单行 CSV: 支持双引号包裹字段 (含字段内逗号) 与转义 ""
static func _parse_csv_line(line: String) -> Array:
	var out: Array = []
	var cur: String = ""
	var in_quote: bool = false
	var i: int = 0
	while i < line.length():
		var ch: String = line.substr(i, 1)
		if in_quote:
			if ch == "\"":
				# 检查转义双引号 ""
				if i + 1 < line.length() and line.substr(i + 1, 1) == "\"":
					cur += "\""
					i += 2
					continue
				in_quote = false
				i += 1
				continue
			cur += ch
			i += 1
		else:
			if ch == ",":
				out.append(cur)
				cur = ""
				i += 1
			elif ch == "\"":
				in_quote = true
				i += 1
			else:
				cur += ch
				i += 1
	out.append(cur)
	return out


# "示例" 列可能是 "a.png" 或 "a.png,b.png,c.png" — 取第一个非空文件名
static func _pick_first_image(field: String) -> String:
	var parts: PackedStringArray = field.split(",")
	for p in parts:
		var s: String = String(p).strip_edges()
		if s != "":
			return s
	return ""


# 主题色解析: 接受表格主题色名 (金/紫/蓝/灰/红/绿/橙/青/粉) 或 "#RRGGBB" 十六进制
# 留空时按事件 category 兜底 (good=红, bad=绿, neutral=金)
static func _parse_theme_color(raw: Variant, cat: int) -> Color:
	var text: String = String(raw).strip_edges()
	if text.begins_with("#"):
		return Color.html(text)
	match text:
		"红", "红色", "赤", "利好红": return Color("#ff5a4f")
		"橙", "橙色", "金橙": return Color("#ff9f2e")
		"黄", "黄色", "金", "金色": return Color("#ffd166")
		"绿", "绿色": return Color("#30d158")
		"青", "青色", "蓝绿": return Color("#38d9ff")
		"蓝", "蓝色": return Color("#4aa3ff")
		"紫", "紫色": return Color("#b06cff")
		"灰", "灰色": return Color("#9aa4b2")
		"粉", "粉色", "玫红": return Color("#ff5ac8")
		_:
			if cat == Event.Category.GOOD:
				return Color("#ff5a4f")
			if cat == Event.Category.BAD:
				return Color("#30d158")
			return Color("#ffd166")


# ---- 数据: 25 条事件定义 ----
# schema:
#   id / name / category("good"|"bad"|"neutral")
#   desc / effect_desc
#   image_path: 事件配图 res:// 路径 (空 = 无图, MascotSlot 回退占位)
#   theme_color: 事件主题色 (来自 data/event/事件美术资源_市场突发事件影响表_表格.csv 的「主题色」列;
#                可填名称 "金/紫/蓝/灰/红/绿/橙/青/粉" 或 "#RRGGBB"; 留空时按 category 兜底)
#   一次性: delta_bull / delta_bull_random / price_rate / emotion_floor / emotion_ceiling / ap_chaos
#   持续:   modifiers (Dictionary) / dur_turns (>0=短期) / banned (Array of effect_id)
const _EVENT_DEFS: Array = [
	# --- 利好情绪 ---
	{"id": "rate_cut",   "name": "降息",     "category": "good",
		"desc": "央行降低基准利率, 市场资金流动性高, 投资氛围浓厚",
		"effect_desc": "市场情绪 +10",
		"image_path": "res://data/event/image2image_1779612117.png",
		"theme_color": "金",
		"delta_bull": 10},
	{"id": "ext_surge",  "name": "外盘暴涨", "category": "good",
		"desc": "隔夜海外市场大涨, 乐观情绪迅速蔓延至本地市场",
		"effect_desc": "市场情绪 +20",
		"image_path": "res://data/event/image2image_1779611936.png",
		"theme_color": "金",
		"delta_bull": 20},
	{"id": "golden_age", "name": "黄金时代", "category": "good",
		"desc": "牛市预期形成, 所有人都相信「这次不一样」",
		"effect_desc": "市场情绪 +30",
		"image_path": "res://data/event/Gold age_.png",
		"theme_color": "金",
		"delta_bull": 30},

	# --- 利空情绪 ---
	{"id": "rate_hike",  "name": "加息",     "category": "bad",
		"desc": "资金成本上升, 市场冷静下来",
		"effect_desc": "市场情绪 -10",
		"image_path": "res://data/event/image2image_1779615043.png",
		"theme_color": "紫",
		"delta_bull": -10},
	{"id": "ext_crash",  "name": "外盘暴跌", "category": "bad",
		"desc": "海外市场跌停, 引发人心动荡",
		"effect_desc": "市场情绪 -20",
		"image_path": "res://data/event/image2image_1779624932.png",
		"theme_color": "紫",
		"delta_bull": -20},
	{"id": "war_risk",   "name": "战争风险", "category": "bad",
		"desc": "全球避险情绪升温, 投资者信心动摇",
		"effect_desc": "市场情绪 -30",
		"image_path": "res://data/event/image2image_1779620175.png",
		"theme_color": "紫",
		"delta_bull": -30},

	# --- 股价直接冲击 ---
	{"id": "double_up",  "name": "盈利双击", "category": "good",
		"desc": "业绩超出估值预期同时发生, 股价进入加速上涨阶段",
		"effect_desc": "当前股价 +20%",
		"image_path": "",
		"theme_color": "金",
		"price_rate": 0.20},
	{"id": "black_swan", "name": "黑天鹅",   "category": "bad",
		"desc": "无法预测的重大危机出现, 市场陷入恐慌",
		"effect_desc": "股价立刻 -20%",
		"image_path": "res://data/event/image2image_1779596118.png",
		"theme_color": "紫",
		"price_rate": -0.20},

	# --- 情绪锚定 ---
	{"id": "faith_recharge", "name": "信仰充值", "category": "good",
		"desc": "用户进入「长期持有」状态, 即使下跌也坚定持仓信心",
		"effect_desc": "本时段情绪不会低于 50 (低于会被拉回 50)",
		"image_path": "res://data/event/image2image_1779619670.png",
		"theme_color": "金",
		"emotion_floor": 50},
	{"id": "faith_collapse", "name": "信仰崩塌", "category": "bad",
		"desc": "市场未来一片不好, 投资者信心丢失",
		"effect_desc": "本时段情绪不会高于 50 (高于会被压回 50)",
		"image_path": "res://data/event/image2image_1779616252.png",
		"theme_color": "紫",
		"emotion_ceiling": 50},

	# --- 持续 3 回合修饰 ---
	{"id": "good_news_amp", "name": "超预期财报", "category": "good",
		"desc": "公司发布远超市场预期, 资金开始抢入流通",
		"effect_desc": "情绪 +5, 接下来 3 回合卡牌上涨效果 +20%",
		"image_path": "res://data/event/image2image_1779612905.png",
		"theme_color": "金",
		"delta_bull": 5,
		"modifiers": {"card_price_up_mul": 1.2},
		"dur_turns": 3},
	{"id": "bad_news_amp", "name": "财务造假", "category": "bad",
		"desc": "企业被传出违规风波, 信任度受到挑战",
		"effect_desc": "情绪 -5, 接下来 3 回合卡牌下跌效果 +20%",
		"image_path": "res://data/event/image2image_1779621527.png",
		"theme_color": "紫",
		"delta_bull": -5,
		"modifiers": {"card_price_down_mul": 1.2},
		"dur_turns": 3},

	# --- 长期修饰 ---
	{"id": "amp_up_card",   "name": "火热预期", "category": "good",
		"desc": "市场热度突破阈值, 任何利好情绪都被放大",
		"effect_desc": "卡牌使用上涨效果 +20%",
		"image_path": "res://data/event/image2image_1779613052.png",
		"theme_color": "金",
		"modifiers": {"card_price_up_mul": 1.2}},
	{"id": "amp_down_card", "name": "下行预期", "category": "bad",
		"desc": "市场一致认为未来更差, 悲观情绪开始扩散",
		"effect_desc": "卡牌使用下跌效果 +20%",
		"image_path": "res://data/event/image2image_1779616252.png",
		"theme_color": "紫",
		"modifiers": {"card_price_down_mul": 1.2}},
	{"id": "leverage_surge", "name": "猴市", "category": "neutral",
		"desc": "杠杆资金涌入, 多空双方都在加码, 波动放大",
		"effect_desc": "买入/卖出造成的价格影响 ×1.5",
		"image_path": "res://data/event/image2image_1779616518.png",
		"theme_color": "蓝",
		"modifiers": {"card_trade_price_mul": 1.5}},
	{"id": "risk_warning",  "name": "风险警示", "category": "neutral",
		"desc": "监管部门发出风险提示, 投资者开始倾向谨慎",
		"effect_desc": "情绪对价格的影响减半",
		"image_path": "res://data/event/image2image_1779618668.png",
		"theme_color": "灰",
		"modifiers": {"emotion_modifier_mul": 0.5}},
	{"id": "market_decouple", "name": "市场失真", "category": "neutral",
		"desc": "情绪与价格极度脱钩, 市场进入非理性状态",
		"effect_desc": "价格与情绪暂时脱钩 (情绪倍率 = 1.0)",
		"image_path": "res://data/event/image2image_1779618983.png",
		"theme_color": "灰",
		"modifiers": {"decouple": true}},

	# --- 涨跌停 ---
	{"id": "cap_up",   "name": "限制涨停", "category": "neutral",
		"desc": "监管层担忧市场过热, 限制单日上涨涨幅",
		"effect_desc": "单回合最大涨幅 ≤ 5%",
		"image_path": "res://data/event/image2image_1779617263.png",
		"theme_color": "蓝",
		"modifiers": {"cap_drift_up": 0.05}},
	{"id": "cap_down", "name": "限制跌停", "category": "neutral",
		"desc": "为防止恐慌扩散, 监管层限制单日下跌跌幅",
		"effect_desc": "单回合最大跌幅 ≤ 5%",
		"image_path": "res://data/event/image2image_1779617700.png",
		"theme_color": "蓝",
		"modifiers": {"cap_drift_down": 0.05}},

	# --- 牌库 / 行动力干扰 ---
	{"id": "freeze_account", "name": "账户审查", "category": "bad",
		"desc": "监管机构对涉嫌违规交易进行管控",
		"effect_desc": "每回合自动冻结一张手牌 (随机入弃牌堆)",
		"image_path": "res://data/event/image2image_1779619348.png",
		"theme_color": "蓝",
		"modifiers": {"freeze_per_turn": 1}},
	{"id": "key_monitor",    "name": "重点监控", "category": "bad",
		"desc": "高频交易者投机行为被监控严打",
		"effect_desc": "每回合最多使用 2 张技能牌",
		"image_path": "res://data/event/image2image_1779617998.png",
		"theme_color": "蓝",
		"modifiers": {"skill_cap_per_turn": 2}},
	{"id": "chaos_day",      "name": "混乱之日", "category": "neutral",
		"desc": "市场系统陷入危机, 交易行为可能失常",
		"effect_desc": "每回合 50% 行动力 +1, 50% 行动力 -1",
		"image_path": "res://data/event/image2image_1779618374.png",
		"theme_color": "灰",
		"ap_chaos": true},

	# --- 神秘资金 / 意外事件 ---
	{"id": "mystery_money",  "name": "神秘资金", "category": "neutral",
		"desc": "一股莫名的资金悄然进场, 市场波动幅度加大",
		"effect_desc": "本时段回合末有 30% 概率额外 ±5%",
		"image_path": "res://data/event/image2image_1779616754.png",
		"theme_color": "蓝",
		"modifiers": {"mystery_active": true}},
	{"id": "accident_event", "name": "鬼故事", "category": "neutral",
		"desc": "各种真假难辨的离奇事件涌现, 市场情绪被牵动",
		"effect_desc": "情绪当回合随机变化 ±10",
		"image_path": "res://data/event/image2image_1779618545.png",
		"theme_color": "灰",
		"delta_bull_random": 10},
]