# 配置加载器 (autoload: /root/Cfg)
# 启动时读取 data/cards.csv 和 data/balance.json,失败时 push_error 并使用代码内回退默认值。
# 用法:
#   Cfg.get_card_template("buy_basic")  -> Dictionary 或 null
#   Cfg.balance.get("START_CASH", 100000.0)
#   Cfg.starter_deck_defs()  -> Array of {effect_id, count}
#   Cfg.shop_pool_ids()      -> Array[String]
extends Node

const CARDS_CSV_PATH := "res://data/cards.csv"
const BALANCE_JSON_PATH := "res://data/balance.json"
const TALENTS_CSV_PATH := "res://data/talents.csv"

var cards: Dictionary = {}     # effect_id -> {name, kind, cost, description, image_path, upgrade_to, in_starter, starter_count, in_shop}
var balance: Dictionary = {}   # key -> value (从 balance.json 直接读入)
var talents: Dictionary = {}   # talent_id -> {name, description, price, in_first_day, effect_id}

var _csv_load_ok: bool = false
var _balance_load_ok: bool = false
var _talents_load_ok: bool = false


func _ready() -> void:
	_load_balance()
	_load_cards()
	_load_talents()
	if not _csv_load_ok:
		push_error("[Cfg] cards.csv 加载失败,卡牌系统将依赖代码回退")
	if not _balance_load_ok:
		push_error("[Cfg] balance.json 加载失败,数值将依赖 game_state.gd 内置默认")
	if not _talents_load_ok:
		push_warning("[Cfg] talents.csv 未加载, 天赋系统将无可用项")


# ----- 卡牌 -----
func get_card_template(effect_id: String) -> Variant:
	# 返回 Dictionary 或 null。调用方需自行处理 null (回退到 hardcoded)
	if cards.has(effect_id):
		return cards[effect_id]
	return null


# 返回 [{effect_id, count}, ...],供 build_starter_deck 使用
func starter_deck_defs() -> Array:
	var out: Array = []
	for eid in cards.keys():
		var t: Dictionary = cards[eid]
		if t.get("in_starter", false):
			out.append({"effect_id": eid, "count": int(t.get("starter_count", 0))})
	return out


# 返回商店候选 effect_id 列表
func shop_pool_ids() -> Array:
	var out: Array = []
	for eid in cards.keys():
		var t: Dictionary = cards[eid]
		if t.get("in_shop", false):
			out.append(eid)
	return out


# ----- 天赋 -----
func get_talent_template(talent_id: String) -> Variant:
	if talents.has(talent_id):
		return talents[talent_id]
	return null


# 返回第 1 天可购天赋 id 列表
func first_day_talent_ids() -> Array:
	var out: Array = []
	for tid in talents.keys():
		var t: Dictionary = talents[tid]
		if t.get("in_first_day", false):
			out.append(tid)
	return out


# ----- 内部:加载 -----
func _load_balance() -> void:
	if not FileAccess.file_exists(BALANCE_JSON_PATH):
		return
	var f := FileAccess.open(BALANCE_JSON_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Cfg] balance.json 顶层必须是 object")
		return
	balance = parsed
	_balance_load_ok = true


func _load_cards() -> void:
	if not FileAccess.file_exists(CARDS_CSV_PATH):
		return
	var f := FileAccess.open(CARDS_CSV_PATH, FileAccess.READ)
	if f == null:
		return
	# 第一行:列头
	var headers: PackedStringArray = f.get_csv_line()
	if headers.size() == 0:
		f.close()
		return
	var col: Dictionary = {}
	for i in range(headers.size()):
		col[headers[i].strip_edges()] = i
	# 必填列
	for required in ["effect_id", "name", "kind", "cost"]:
		if not col.has(required):
			push_error("[Cfg] cards.csv 缺列: %s" % required)
			f.close()
			return
	# 数据行
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() == 0:
			continue
		var eid: String = _cell(row, col, "effect_id").strip_edges()
		if eid == "":
			continue
		var entry: Dictionary = {
			"name":          _cell(row, col, "name"),
			"kind":          _cell(row, col, "kind"),
			"cost":          int(_cell_or(row, col, "cost", "1")),
			"description":   _cell(row, col, "description"),
			"image_path":    _cell(row, col, "image_path"),
			"upgrade_to":    _cell(row, col, "upgrade_to").strip_edges(),
			"in_starter":    _bool(_cell(row, col, "in_starter")),
			"starter_count": int(_cell_or(row, col, "starter_count", "0")),
			"in_shop":       _bool(_cell(row, col, "in_shop")),
			# 效果参数 (数据驱动, 替代 card_effect_system 里的 match 硬编码)
			"buy_pct":         _float(_cell(row, col, "buy_pct")),
			"sell_pct":        _float(_cell(row, col, "sell_pct")),
			"price_pct":       _float(_cell(row, col, "price_pct")),
			"emotion_delta":   int(_cell_or(row, col, "emotion_delta", "0")),
			"trade_price_pct": _float(_cell(row, col, "trade_price_pct")),
			"trade_shares":    int(_cell_or(row, col, "trade_shares", "0")),
			# 新机制 (2026-05-23): 情绪锚定 / 反转 / 回合倍率 / 事件刷新
			"emotion_set":      int(_cell_or(row, col, "emotion_set", "-1")),
			"emotion_invert":   _bool(_cell(row, col, "emotion_invert")),
			"reroll_event":     _bool(_cell(row, col, "reroll_event")),
			"emotion_mul_turn": _float(_cell(row, col, "emotion_mul_turn")),
			# 选择类机制 (2026-05-23 第二批): 信号驱动, UI 弹窗 → 回调 game_state apply_*
			"event_preview":     _bool(_cell(row, col, "event_preview")),
			"discard_then_draw": _bool(_cell(row, col, "discard_then_draw")),
			"topdeck_pick":      _bool(_cell(row, col, "topdeck_pick")),
			"liquidity_chance":  _float(_cell(row, col, "liquidity_chance")),
			"shatter":           _bool(_cell(row, col, "shatter")),
			# 商店/牌组约束 (2026-05-23 平衡): 唯一卡 / 个性化售价 / 每日使用上限 / 当日封存
			"shop_unique":  _bool(_cell(row, col, "shop_unique")),
			"shop_price":   int(_cell_or(row, col, "shop_price", "0")),
			"daily_limit":  int(_cell_or(row, col, "daily_limit", "0")),
			"daily_exile":  _bool(_cell(row, col, "daily_exile")),
			# 自动效果: 弃光手牌再抽等量 (快速换手)
			"discard_hand_redraw": _bool(_cell(row, col, "discard_hand_redraw")),
			# 动态效果: 孤注一掷 — ±X% (50/50, X = 卡组中 BUY+SELL 数)
			"mob_swing":           _bool(_cell(row, col, "mob_swing")),
		}
		cards[eid] = entry
	f.close()
	_csv_load_ok = true


func _load_talents() -> void:
	if not FileAccess.file_exists(TALENTS_CSV_PATH):
		return
	var f := FileAccess.open(TALENTS_CSV_PATH, FileAccess.READ)
	if f == null:
		return
	var headers: PackedStringArray = f.get_csv_line()
	if headers.size() == 0:
		f.close()
		return
	var col: Dictionary = {}
	for i in range(headers.size()):
		col[headers[i].strip_edges()] = i
	for required in ["id", "name"]:
		if not col.has(required):
			push_error("[Cfg] talents.csv 缺列: %s" % required)
			f.close()
			return
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() == 0:
			continue
		var tid: String = _cell(row, col, "id").strip_edges()
		if tid == "":
			continue
		talents[tid] = {
			"name":          _cell(row, col, "name"),
			"description":   _cell(row, col, "description"),
			"price":         int(_cell_or(row, col, "price", "0")),
			"in_first_day":  _bool(_cell(row, col, "in_first_day")),
			"effect_id":     _cell_or(row, col, "effect_id", tid),
		}
	f.close()
	_talents_load_ok = true


func _cell(row: PackedStringArray, col: Dictionary, key: String) -> String:
	if not col.has(key):
		return ""
	var idx: int = col[key]
	if idx >= row.size():
		return ""
	return row[idx]


func _cell_or(row: PackedStringArray, col: Dictionary, key: String, fallback: String) -> String:
	var v: String = _cell(row, col, key).strip_edges()
	return fallback if v == "" else v


func _bool(s: String) -> bool:
	var v: String = s.strip_edges().to_lower()
	return v == "true" or v == "1" or v == "yes"


func _float(s: String) -> float:
	var v: String = s.strip_edges()
	if v == "":
		return 0.0
	return float(v)
