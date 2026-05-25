# 阶段4 商店冒烟测试: 验证 day_ended → SHOP 阶段 → 买/升/删卡 → 离开 → 下一天.
# 写到 res://logs/shop_smoke.log
extends Node

const Card = preload("res://scripts/card.gd")
const CardDatabase = preload("res://scripts/card_database.gd")

var _f: FileAccess = null


func _ready() -> void:
	_open_log()
	_say("==== shop_smoke_test ====")
	var g = get_node_or_null("/root/Game")
	if g == null:
		_fail("Game autoload 未挂载"); return
	g.log_message.connect(_on_log)
	g.new_level()

	# 跑完第一天 10 回合直接 end_turn 推进
	while g.phase == g.Phase.PLAY and g.day == 1:
		# 出 1 张内幕拉股价 + 立刻 end_turn
		var played: bool = false
		for i in range(g.hand.size()):
			if g.hand[i].effect_id == "insider_basic" and g.hand[i].cost <= g.action_points:
				if g.play_card(i): played = true; break
		await g.end_turn()
		if g.turn_global > 50: _fail("第1天太长了"); return

	# 应该进 SHOP
	_assert(g.phase == g.Phase.SHOP, "第1天结束后进入 SHOP, 实际 phase=%d" % g.phase)
	_assert(g.day == 1, "仍是第1天 (商店尚未离开)")
	_assert(g.shop_offers.size() > 0, "商店应有可买卡, 实际 %d" % g.shop_offers.size())
	_assert(not g.day_close_summary.is_empty(), "当日结算摘要应已生成")
	_say("当日摘要: open=%.2f close=%.2f pnl=%.0f" % [
		g.day_close_summary["open_price"],
		g.day_close_summary["close_price"],
		g.day_close_summary["day_pnl"],
	])

	# 买 1 张
	var deck_before: int = g.get_deck_size()
	var cash_before: float = g.cash
	_assert(g.shop_buy_card(0), "买卡 0 应成功")
	_assert(g.get_deck_size() == deck_before + 1, "买卡后牌组 +1")
	_assert(g.cash == cash_before - g.SHOP_BUY_PRICE, "买卡扣 1000")

	# 升级 1 张 (找 deck 里第一张能升的)
	var up_target_index: int = -1
	var deck: Array = g.get_full_deck()
	for i in range(deck.size()):
		if CardDatabase.upgrade_target(deck[i].effect_id) != "":
			up_target_index = i
			break
	_assert(up_target_index >= 0, "至少应有 1 张可升级卡")
	cash_before = g.cash
	var up_old_name: String = deck[up_target_index].name
	_assert(g.shop_upgrade_card(up_target_index), "升级应成功")
	_assert(g.cash == cash_before - g.SHOP_UPGRADE_PRICE, "升级扣 1000")
	# 验证该位置的牌名变化
	var deck2: Array = g.get_full_deck()
	_assert(deck2[up_target_index].name != up_old_name, "升级后名字应改变 (旧 %s)" % up_old_name)
	_say("升级位置 %d: %s → %s" % [up_target_index, up_old_name, deck2[up_target_index].name])

	# 删 1 张
	cash_before = g.cash
	var deck_count_before: int = g.get_deck_size()
	var del_price: int = g.current_delete_price()
	_assert(g.shop_delete_card(0), "删卡应成功")
	_assert(g.cash == cash_before - del_price, "删卡扣 %d" % del_price)
	_assert(g.get_deck_size() == deck_count_before - 1, "牌组 -1")
	# 下次删卡价应 +1000
	_assert(g.current_delete_price() == del_price + 1000, "删卡价应递增")

	# 离开商店, 进入第 2 天
	g.leave_shop_to_next_day()
	_assert(g.day == 2, "应进入第 2 天, 实际 day=%d" % g.day)
	_assert(g.phase == g.Phase.PLAY, "新一天应回到 PLAY 阶段")
	_assert(g.turn_in_day == 1, "新一天的第 1 回合")

	# 把第 2 ~ 5 天用 end_turn 跑光, 中间每天进商店都直接离开
	while not g.is_level_over:
		if g.phase == g.Phase.SHOP:
			g.leave_shop_to_next_day()
			continue
		await g.end_turn()
		if g.turn_global > g.DAYS_PER_LEVEL * g.TURNS_PER_DAY + 10:
			_fail("超长循环"); return

	_assert(g.day == g.DAYS_PER_LEVEL, "应在第 5 天结束")
	_assert(g.candles.size() == g.DAYS_PER_LEVEL * g.TURNS_PER_DAY, "总蜡烛 = 50")
	_say("最终资产: ¥%.0f" % g.cash)
	_say("PASS")
	_close_log()
	get_tree().quit(0)


# ---- helpers ----
func _assert(ok: bool, msg: String) -> void:
	if ok: _say("  [OK] %s" % msg)
	else: _fail("断言失败: %s" % msg)


func _open_log() -> void:
	if not DirAccess.dir_exists_absolute("res://logs"):
		DirAccess.make_dir_absolute("res://logs")
	_f = FileAccess.open("res://logs/shop_smoke.log", FileAccess.WRITE)
	if _f == null:
		_f = FileAccess.open("user://shop_smoke.log", FileAccess.WRITE)


func _on_log(msg: String) -> void: _say(msg)


func _say(msg: String) -> void:
	print(msg)
	if _f != null:
		_f.store_line(msg); _f.flush()


func _fail(reason: String) -> void:
	var msg: String = "FAIL: " + reason
	printerr(msg)
	if _f != null:
		_f.store_line(msg); _f.flush()
	_close_log()
	get_tree().quit(1)


func _close_log() -> void:
	if _f != null: _f.close(); _f = null
