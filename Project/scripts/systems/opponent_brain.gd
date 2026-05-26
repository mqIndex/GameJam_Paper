# 对手行为树 + 加权选择器 (RefCounted, 纯逻辑)
extends RefCounted

const OpponentState = preload("res://scripts/systems/opponent_state.gd")


func tick(opp: OpponentState, gs) -> Dictionary:
	# 健康度 = 1 - 危险度 (对手离爆仓线越远越健康)
	var health: float = 1.0 - opp.get_danger_pct(gs.price)
	var turn_rise := _calc_turn_rise(gs)
	var branch := ""
	var actions: Array = []

	# 1. 保命分支
	if health <= opp.critical_threshold:
		branch = "critical"
		actions = _critical_actions(opp, gs, health)
	# 2. 拉升反应
	elif turn_rise >= opp.reaction_threshold:
		branch = "reaction"
		actions = _reaction_actions(opp, gs, health)
	# 3. 引诱反扑
	elif gs.shares == 0 and gs.cash < gs.price * 50.0 and opp.w_pump_trap > 0:
		branch = "lure"
		actions = _lure_actions(opp, gs, health)
	# 4. 默认日常
	else:
		branch = "default"
		actions = _default_actions(opp, gs, health)

	var result := _weighted_pick(actions)

	# 气泡逻辑
	var bubble := ""
	if branch != opp._last_branch and opp._last_branch != "":
		bubble = _branch_switch_bubble(opp, branch)
	if result.get("action", "") == "pump_trap" and opp.dialog_trap != "":
		bubble = opp.dialog_trap
	if health < 0.05 and opp.dialog_dying != "":
		bubble = opp.dialog_dying
	opp._last_branch = branch

	result["bubble"] = bubble
	return result


func _calc_turn_rise(gs) -> float:
	if gs.intraday_candles.is_empty():
		return 0.0
	var first_open: float = gs.cur_open
	if gs.price <= 0.0 or first_open <= 0.0:
		return 0.0
	return (gs.price - first_open) / first_open


# ===== 分支动作生成 =====
func _critical_actions(opp: OpponentState, gs, health: float) -> Array:
	var cover_w: float = 0.10 * _sit_cover(health)
	var combo_w: float = min(cover_w, 0.10 * opp.w_bad_news * _sit_bad_news(gs))
	var hold_w: float = max(opp.hard_hold_weight, 2.0)
	return [
		{"action": "cover", "params": {"M": opp.action_m_cover}, "weight": cover_w},
		{"action": "cover+bad_news", "params": {"M": opp.action_m_cover, "K": opp.action_k_emotion}, "weight": combo_w},
		{"action": "idle", "params": {}, "weight": hold_w},
	]


func _reaction_actions(opp: OpponentState, gs, health: float) -> Array:
	var add_w: float = opp.w_add_short * _sit_add_short(opp, gs, health)
	var news_w: float = opp.w_bad_news * _sit_bad_news(gs)
	var combo_w: float = min(add_w, news_w) * 0.5
	return [
		{"action": "add_short", "params": {"N": opp.action_n, "X": opp.action_x_pct}, "weight": add_w},
		{"action": "bad_news", "params": {"K": opp.action_k_emotion}, "weight": news_w},
		{"action": "add_short+bad_news", "params": {"N": opp.action_n, "X": opp.action_x_pct, "K": opp.action_k_emotion}, "weight": combo_w},
	]


func _lure_actions(opp: OpponentState, gs, _health: float) -> Array:
	var trap_w := opp.w_pump_trap * _sit_pump_trap(gs)
	var idle_w := opp.w_idle * 1.0
	return [
		{"action": "pump_trap", "params": {"Y": opp.pump_trap_y_pct}, "weight": trap_w},
		{"action": "idle", "params": {}, "weight": idle_w},
	]


func _default_actions(opp: OpponentState, gs, health: float) -> Array:
	var add_w: float = opp.w_add_short * _sit_add_short(opp, gs, health)
	var news_w: float = opp.w_bad_news * _sit_bad_news(gs)
	var cover_w: float = opp.w_cover * _sit_cover(health) * 0.05
	var idle_w: float = opp.w_idle * _sit_idle(gs)
	return [
		{"action": "add_short", "params": {"N": opp.action_n, "X": opp.action_x_pct}, "weight": add_w},
		{"action": "bad_news", "params": {"K": opp.action_k_emotion}, "weight": news_w},
		{"action": "cover", "params": {"M": opp.action_m_cover}, "weight": cover_w},
		{"action": "idle", "params": {}, "weight": idle_w},
	]


# ===== 情境系数 =====
func _sit_add_short(opp: OpponentState, gs, health: float) -> float:
	var needed_cash: float = float(opp.action_n) * gs.price * 0.5
	if opp.cash < needed_cash:
		return 0.0
	var m := 1.0
	if gs.shares > 0:
		m *= 1.5
	if gs.bull > 70:
		m *= 1.3
	if health < 0.3:
		m *= 0.3
	return m


func _sit_bad_news(gs) -> float:
	var m := 1.0
	if gs.bull > 50:
		m *= 1.4
	if gs.bull < 30:
		m *= 0.5
	return m


func _sit_cover(health: float) -> float:
	var m := 1.0
	if health < 0.5:
		m *= 2.0
	if health > 0.8:
		m *= 0.3
	return m


func _sit_idle(gs) -> float:
	var m := 1.0
	if gs.shares == 0:
		m *= 2.0
	return m


func _sit_pump_trap(gs) -> float:
	if gs.shares == 0 and gs.cash < gs.price * 50.0:
		return 3.0
	return 1.0


# ===== 加权抽签 =====
func _weighted_pick(actions: Array) -> Dictionary:
	var total := 0.0
	for a in actions:
		total += max(0.0, a.get("weight", 0.0))
	if total <= 0.0:
		return {"action": "idle", "params": {}}
	var roll := randf() * total
	var acc := 0.0
	for a in actions:
		acc += max(0.0, a.get("weight", 0.0))
		if roll <= acc:
			return {"action": a["action"], "params": a["params"]}
	return actions.back()


# ===== 分支切换气泡 =====
func _branch_switch_bubble(opp: OpponentState, branch: String) -> String:
	match branch:
		"critical":
			return opp.dialog_cover if opp.dialog_cover != "" else ""
		"reaction":
			return opp.dialog_react if opp.dialog_react != "" else ""
		"lure":
			return opp.dialog_trap if opp.dialog_trap != "" else ""
	return ""
