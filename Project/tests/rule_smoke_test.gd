# 规则数据层冒烟测试
# 跑通 1 关 5 天 50 回合, 只验证状态机和 K 线基础不变量.
# 把日志写到 res://logs/rule_smoke.log
extends Node

const CardDatabase = preload("res://scripts/card_database.gd")

var _log_file: FileAccess = null

func _ready() -> void:
	_open_log()
	_say("==== rule_smoke_test 开始 ====")
	_say("godot=%s os=%s" % [Engine.get_version_info().get("string", "?"), OS.get_name()])

	var g = get_node_or_null("/root/Game")
	if g == null:
		_fail("/root/Game autoload 未挂载")
		return
	g.log_message.connect(_on_game_log)

	g.new_level()
	# 基本检查
	_assert(g.cash == g.START_CASH, "初始资金=10w")
	_assert(g.shares == 0, "初始持仓=0")
	_assert(g.price == g.INITIAL_PRICE, "初始股价=100")
	_assert(g.bull + g.bear == g.EMOTION_TOTAL, "情绪总和保持 %d" % g.EMOTION_TOTAL)
	var expected_deck_size: int = CardDatabase.build_starter_deck().size()
	_assert(g.draw_pile.size() + g.hand.size() + g.discard_pile.size() == expected_deck_size, "牌组=%d" % expected_deck_size)
	_assert(g.day == 1, "第1天")
	_assert(g.turn_in_day == 1, "第1回合")
	_assert(g.hand.size() >= g.FIRST_TURN_DRAW, "第一回合至少抽 6 张")
	# 第一回合保底: 至少 1 买 + 1 卖 + 1 技能
	var has_buy: bool = false
	var has_sell: bool = false
	var has_skill: bool = false
	for c in g.hand:
		if c.is_buy(): has_buy = true
		elif c.is_sell(): has_sell = true
		elif c.is_skill(): has_skill = true
	_assert(has_buy and has_sell and has_skill, "第一回合保底买/卖/技能各一")

	# 验证 μ 计算公式: bull=50 且无事件修饰时 → 0
	var sum: float = 0.0
	var n_samples: int = 200
	var saved_bull: int = g.bull
	var saved_bear: int = g.bear
	var saved_event_modifiers: Dictionary = g.event_modifiers.duplicate()
	g.bull = 50
	g.bear = 50
	g.event_modifiers.clear()
	for i in range(n_samples):
		sum += g._roll_natural_drift()
	g.bull = saved_bull
	g.bear = saved_bear
	g.event_modifiers = saved_event_modifiers
	var avg: float = sum / float(n_samples)
	_say("情绪 50 时, 200 次自然波动均值 = %+.4f (期望接近 0)" % avg)
	_assert(abs(avg) < 0.01, "情绪 50 时 μ=0")

	# 跑 5 天 × 10 回合
	while not g.is_level_over:
		# SHOP 阶段: 直接离开进入下一天 (阶段2 冒烟不测商店)
		if g.phase == g.Phase.SHOP:
			g.leave_shop_to_next_day()
			continue
		# 规则数值经常调整, 冒烟测试不绑定行动点/费用/出牌策略.
		await g.end_turn()
		if g.turn_global > g.DAYS_PER_LEVEL * g.TURNS_PER_DAY + 5:
			_fail("回合数超限, 状态机死循环?")
			return

	# 收盘检查
	_assert(g.day == g.DAYS_PER_LEVEL, "结算时 day=%d" % g.DAYS_PER_LEVEL)
	_assert(g.candles.size() == g.DAYS_PER_LEVEL * g.TURNS_PER_DAY, "candles=%d" % (g.DAYS_PER_LEVEL * g.TURNS_PER_DAY))
	for c in g.candles:
		_assert(c["low"] <= c["open"] and c["low"] <= c["close"] and c["high"] >= c["open"] and c["high"] >= c["close"],
			"candle OHLC 一致性")
	_say("总资产 = %.0f, 目标 = %.0f" % [g.cash, g.VICTORY_TARGET])

	_say("PASS")
	_close_log()
	get_tree().quit(0)


# ----- 工具 -----
func _assert(ok: bool, msg: String) -> void:
	if ok:
		_say("  [OK] %s" % msg)
	else:
		_fail("断言失败: %s" % msg)


func _open_log() -> void:
	if not DirAccess.dir_exists_absolute("res://logs"):
		DirAccess.make_dir_absolute("res://logs")
	_log_file = FileAccess.open("res://logs/rule_smoke.log", FileAccess.WRITE)
	if _log_file == null:
		_log_file = FileAccess.open("user://rule_smoke.log", FileAccess.WRITE)


func _on_game_log(msg: String) -> void:
	_say(msg)


func _say(msg: String) -> void:
	print(msg)
	if _log_file != null:
		_log_file.store_line(msg)
		_log_file.flush()


func _fail(reason: String) -> void:
	var msg: String = "FAIL: " + reason
	printerr(msg)
	if _log_file != null:
		_log_file.store_line(msg)
		_log_file.flush()
	_close_log()
	get_tree().quit(1)


func _close_log() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null
