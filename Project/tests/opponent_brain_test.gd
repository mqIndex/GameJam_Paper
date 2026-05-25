# 对手行为树 + 数值冒烟测试
# 跑法: 在 Godot 编辑器创建 OpponentBrainTest.tscn, 挂此脚本, 运行场景
extends Node

const OpponentState = preload("res://scripts/systems/opponent_state.gd")
const OpponentBrain = preload("res://scripts/systems/opponent_brain.gd")

var _log_file: FileAccess = null


class MockGameState extends RefCounted:
	var price: float = 100.0
	var bull: int = 50
	var bear: int = 50
	var shares: int = 100
	var cash: float = 50000.0
	var cur_open: float = 100.0
	var intraday_candles: Array = []


func _ready() -> void:
	_open_log()
	_say("==== opponent_brain_test 开始 ====")

	test_liquidation_math()
	test_liquidation_trigger()
	test_critical_branch()
	test_reaction_branch()
	test_pump_trap_only_snake()
	test_end_to_end_spawn_defeat()

	_say("PASS")
	_close_log()
	get_tree().quit(0)


func test_liquidation_math() -> void:
	_say("-- test_liquidation_math --")
	var opp := OpponentState.new()
	opp.n0 = 500
	opp.initial_cash = 100000.0
	opp.spawn(100.0)
	# liquidation_price = entry_avg_price + (cash + safety_pool) / short_position = 100 + 100000/500 = 300
	_assert(abs(opp.liquidation_price - 300.0) < 0.01, "入场平仓线=300, 实际=%.2f" % opp.liquidation_price)
	_assert(opp.short_position == 500, "入场仓位=500")

	# 加空 100 股 @ 110
	opp.add_short(100, 110.0)
	# new_avg = (100*500 + 110*100) / 600 = 61000/600 ≈ 101.67
	# liq = 101.67 + 100000/600 ≈ 268.33
	_assert(opp.short_position == 600, "加空后仓位=600")
	_assert(abs(opp.entry_avg_price - 101.667) < 0.1, "加空后均价≈101.67, 实际=%.2f" % opp.entry_avg_price)
	_assert(opp.liquidation_price < 300.0, "加空后平仓线下移 (%.2f < 300)" % opp.liquidation_price)

	# 减仓 200 股
	var liq_before := opp.liquidation_price
	opp.cover(200)
	_assert(opp.short_position == 400, "减仓后仓位=400")
	_assert(opp.liquidation_price > liq_before, "减仓后平仓线上移 (%.2f > %.2f)" % [opp.liquidation_price, liq_before])


func test_liquidation_trigger() -> void:
	_say("-- test_liquidation_trigger --")
	var opp := OpponentState.new()
	opp.n0 = 500
	opp.initial_cash = 100000.0
	opp.spawn(100.0)
	# liq = 300
	_assert(not opp.is_liquidated(290.0), "价格290<300, 未触发")
	_assert(opp.is_liquidated(300.0), "价格300=300, 触发")
	_assert(opp.is_liquidated(310.0), "价格310>300, 触发")

	var opp_cashout := OpponentState.new()
	opp_cashout.n0 = 500
	opp_cashout.initial_cash = 100000.0
	opp_cashout.spawn(100.0)
	_assert(not opp_cashout.try_top_up_margin(300.0), "现金补到0时视为失败")

	opp.liquidate()
	_assert(opp.defeated_this_level, "击败标记")
	_assert(not opp.present, "退场")
	_assert(opp.short_position == 0, "仓位清零")


func test_critical_branch() -> void:
	_say("-- test_critical_branch --")
	var brain := OpponentBrain.new()
	var opp := _make_test_opp()
	opp.spawn(100.0)
	# liq=300, 价格295 → health = (300-295)/300 ≈ 0.017 < critical 0.20

	var gs := MockGameState.new()
	gs.price = 295.0
	gs.cur_open = 295.0

	var counts := {"cover": 0, "idle": 0, "cover+bad_news": 0, "other": 0}
	for i in range(200):
		var result: Dictionary = brain.tick(opp, gs)
		var act: String = result.get("action", "")
		if act == "cover":
			counts["cover"] += 1
		elif act == "idle":
			counts["idle"] += 1
		elif act == "cover+bad_news":
			counts["cover+bad_news"] += 1
		else:
			counts["other"] += 1
	_say("  保命分支分布: cover=%d, cover+bad_news=%d, idle=%d, other=%d" % [
		counts["cover"], counts["cover+bad_news"], counts["idle"], counts["other"]])
	_assert(counts["cover"] + counts["cover+bad_news"] < counts["idle"],
		"保命分支: 减仓类动作少于静观")
	_assert(counts["other"] == 0, "保命分支不出add_short")


func test_reaction_branch() -> void:
	_say("-- test_reaction_branch --")
	var brain := OpponentBrain.new()
	var opp := _make_test_opp()
	opp.spawn(100.0)

	var gs := MockGameState.new()
	gs.price = 105.0
	gs.cur_open = 100.0  # 回合开盘100, 当前105 → +5% > reaction 3%

	var has_add := false
	var has_news := false
	for i in range(100):
		var result: Dictionary = brain.tick(opp, gs)
		var act: String = result.get("action", "")
		if "add_short" in act:
			has_add = true
		if "bad_news" in act:
			has_news = true
	_assert(has_add or has_news, "拉升反应分支必出 add_short 或 bad_news")


func test_pump_trap_only_snake() -> void:
	_say("-- test_pump_trap_only_snake --")
	var brain := OpponentBrain.new()

	# 老六: w_pump_trap = 0
	var opp_six := _make_test_opp()
	opp_six.w_pump_trap = 0.0
	opp_six.spawn(100.0)

	var gs := MockGameState.new()
	gs.price = 100.0
	gs.shares = 0
	gs.cash = 10.0

	var trap_count := 0
	for i in range(200):
		var result: Dictionary = brain.tick(opp_six, gs)
		if result.get("action", "") == "pump_trap":
			trap_count += 1
	_assert(trap_count == 0, "老六(w_pump_trap=0) 永远不抽到 pump_trap, 实际=%d" % trap_count)

	# 老蛇: w_pump_trap = 1.2
	var opp_snake := _make_test_opp()
	opp_snake.w_pump_trap = 1.2
	opp_snake.pump_trap_y_pct = 0.02
	opp_snake.spawn(100.0)

	trap_count = 0
	for i in range(200):
		var result: Dictionary = brain.tick(opp_snake, gs)
		if result.get("action", "") == "pump_trap":
			trap_count += 1
	_say("  老蛇 pump_trap 次数: %d / 200" % trap_count)
	_assert(trap_count > 0, "老蛇(w_pump_trap=1.2) 能抽到 pump_trap")


func test_end_to_end_spawn_defeat() -> void:
	_say("-- test_end_to_end_spawn_defeat --")
	var g = get_node_or_null("/root/Game")
	if g == null:
		_say("  [SKIP] /root/Game 不可用, 跳过端到端测试")
		return

	g.new_level()
	g._clear_event_state()
	var opp = g.get_opponent_state()
	if opp == null:
		_say("  [SKIP] 无对手状态")
		return
	if not opp.present:
		g._spawn_opponent()
	_assert(opp.present, "对手已入场")
	var found_opponent_candle := false
	for ic in g.intraday_candles:
		if String(ic.get("kind", "")) == "opponent":
			found_opponent_candle = true
			break
	_assert(found_opponent_candle, "对手入场行动已写入分时K")

	var liq = opp.liquidation_price
	_say("  平仓线=%.2f, 当前价=%.2f" % [liq, g.price])

	# 记录当前情绪
	var bull_before = g.bull

	# 拉高股价到超过平仓线
	var needed_rate = (liq * 1.05) / g.price - 1.0
	g.apply_price_change(needed_rate, true)
	_say("  拉升后价格=%.2f" % g.price)
	_assert(g.price >= liq, "价格 >= 平仓线")
	_assert(opp.defeated_this_level, "对手已被强平击败")
	_assert(not opp.present, "对手已退场")

	# 检查情绪奖励
	_assert(g.bull > bull_before, "情绪上升 (bull %d → %d)" % [bull_before, g.bull])

	# 检查奖励卡进入 draw_pile
	var found_reward := false
	for c in g.draw_pile:
		if c.effect_id == opp.reward_card_id:
			found_reward = true
			break
	_assert(found_reward, "奖励卡 %s 已进入 draw_pile" % opp.reward_card_id)


# ===== 工具 =====
func _make_test_opp() -> OpponentState:
	var opp := OpponentState.new()
	opp.opponent_id = "test_boss"
	opp.display_name = "测试Boss"
	opp.n0 = 500
	opp.m0 = 25000.0
	opp.action_n = 100
	opp.action_x_pct = 0.015
	opp.action_k_emotion = 3
	opp.action_m_cover = 80
	opp.pump_trap_y_pct = 0.0
	opp.critical_threshold = 0.20
	opp.reaction_threshold = 0.03
	opp.hard_hold_weight = 0.1
	opp.w_add_short = 1.0
	opp.w_bad_news = 1.0
	opp.w_cover = 1.5
	opp.w_idle = 1.5
	opp.w_pump_trap = 0.0
	opp.trigger_prob_per_turn = 0.15
	opp.trigger_rise_pct = 0.20
	return opp


func _assert(ok: bool, msg: String) -> void:
	if ok:
		_say("  [OK] %s" % msg)
	else:
		_fail("断言失败: %s" % msg)


func _open_log() -> void:
	if not DirAccess.dir_exists_absolute("res://logs"):
		DirAccess.make_dir_absolute("res://logs")
	_log_file = FileAccess.open("res://logs/opponent_brain.log", FileAccess.WRITE)
	if _log_file == null:
		_log_file = FileAccess.open("user://opponent_brain.log", FileAccess.WRITE)


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
