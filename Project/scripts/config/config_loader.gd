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

var cards: Dictionary = {}     # effect_id -> {name, kind, cost, description, image_path, upgrade_to, in_starter, starter_count, in_shop}
var balance: Dictionary = {}   # key -> value (从 balance.json 直接读入)

var _csv_load_ok: bool = false
var _balance_load_ok: bool = false


func _ready() -> void:
	_load_balance()
	_load_cards()
	if not _csv_load_ok:
		push_error("[Cfg] cards.csv 加载失败,卡牌系统将依赖代码回退")
	if not _balance_load_ok:
		push_error("[Cfg] balance.json 加载失败,数值将依赖 game_state.gd 内置默认")


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
		}
		cards[eid] = entry
	f.close()
	_csv_load_ok = true


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
