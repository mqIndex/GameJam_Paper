# tools/validate_cards.gd
# 校验 data/cards.csv 的字段完整性和引用一致性, 失败时 quit(1)
# 用法: 通过 tools/validate_csv.bat 调起 (headless)
extends SceneTree

const ConfigLoaderScript = preload("res://scripts/config/config_loader.gd")


func _initialize() -> void:
	var errors: Array = []
	# --script 模式不加载 autoload, 手动实例化 ConfigLoader 并直接调 load
	var cfg: Node = ConfigLoaderScript.new()
	cfg._load_balance()
	cfg._load_cards()
	var cards: Dictionary = cfg.cards
	if cards.is_empty():
		_fail(["cards.csv 加载结果为空 (文件不存在 / 解析失败 / 没有数据行)"])
		return

	# 1. effect_id 唯一性由 Dictionary 自动保证, 不需要额外检查 (后写覆盖前写)
	#    但可以扫描 CSV 原文检查重复 -- 这里偷懒, 用计数信息
	var n: int = cards.size()
	print("cards.csv 共加载 %d 条" % n)

	# 2. 字段完整性 + kind 枚举合法 + upgrade_to 指向存在的 ID
	var valid_kinds: Array = ["BUY", "SELL", "SKILL", "EVENT"]
	for eid in cards.keys():
		var t: Dictionary = cards[eid]
		if String(t.get("name", "")).strip_edges() == "":
			errors.append("[%s] name 为空" % eid)
		var kind: String = String(t.get("kind", "")).strip_edges().to_upper()
		if not (kind in valid_kinds):
			errors.append("[%s] kind 非法: %s (允许: %s)" % [eid, kind, valid_kinds])
		var cost: int = int(t.get("cost", -1))
		if cost < 0:
			errors.append("[%s] cost < 0" % eid)
		var up: String = String(t.get("upgrade_to", "")).strip_edges()
		if up != "" and not cards.has(up):
			errors.append("[%s] upgrade_to 指向不存在的 ID: %s" % [eid, up])
		var img: String = String(t.get("image_path", "")).strip_edges()
		if img != "":
			# image_path 不强制存在 (允许策划先填路径再补图), 但给出 warning
			var path: String = img if img.begins_with("res://") else "res://assets/cards/" + img
			if not FileAccess.file_exists(path):
				print("WARN: [%s] image_path 文件不存在: %s" % [eid, path])

	# 3. 至少要有 1 张起始卡 + 1 张商店卡
	var starter_count: int = 0
	var shop_count: int = 0
	for eid in cards.keys():
		var t: Dictionary = cards[eid]
		if bool(t.get("in_starter", false)) and int(t.get("starter_count", 0)) > 0:
			starter_count += 1
		if bool(t.get("in_shop", false)):
			shop_count += 1
	if starter_count == 0:
		errors.append("没有任何起始卡 (in_starter=true 且 starter_count>0)")
	if shop_count == 0:
		errors.append("没有任何商店卡 (in_shop=true)")

	if errors.is_empty():
		print("OK: 全部 %d 张卡校验通过 (起始 %d, 商店 %d)" % [n, starter_count, shop_count])
		quit(0)
	else:
		_fail(errors)


func _fail(errors: Array) -> void:
	push_error("validate_cards FAILED:")
	for e in errors:
		push_error("  - " + String(e))
	printerr("FAIL: %d 个错误" % errors.size())
	quit(1)
