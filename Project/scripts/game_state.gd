# 《不要怕，是技术性调整！》核心规则数据层 (autoload: /root/Game)
# 阶段2: 仅做规则与状态; UI 在阶段3 接入.
# 重构: 原 const 块已改为 var, 在 _ready 中从 /root/Cfg.balance 加载, 缺失项回退到代码默认值.
# 突发事件系统: 见底部 "Events" 段; modifier 落点散布在 apply_*/_start_turn/_settle_turn/_dispatch_effect.
extends Node

const Card = preload("res://scripts/card.gd")
const CardDatabase = preload("res://scripts/card_database.gd")
const CardEffectSystem = preload("res://scripts/systems/card_effect_system.gd")
const Event = preload("res://scripts/event.gd")
const EventDatabase = preload("res://scripts/event_database.gd")

var _effect_system: CardEffectSystem = null

# ===== 关卡/天/回合 (新手关) =====
var DAYS_PER_LEVEL: int = 5
var TURNS_PER_DAY: int = 10

# ===== 经济参数 =====
var START_CASH: float = 100000.0
var VICTORY_TARGET: float = 120000.0          # 第一关
var INITIAL_PRICE: float = 100.0
var SETTLE_DISCOUNT: float = 0.5              # 周五未卖筹码强制折价
var FIRST_TURN_DRAW: int = 6                  # 第一回合摸 6 张
var TURN_DRAW: int = 2                        # 此后每回合摸 2 张
var HAND_LIMIT: int = 10
var ACTION_POINTS_INITIAL: int = 2            # 每天首回合 AP (策划: 每天开盘 PER_TURN 重置为此, 每回合末 +1 直到 MAX)
var ACTION_POINTS_PER_TURN: int = 1           # 运行时: 当前回合 AP 上限 (_start_day 重置, _settle_turn 末递增)
var ACTION_POINTS_MAX: int = 6                # 行动力上限

# ===== 情绪参数 =====
var INITIAL_BULL: int = 50                    # 初始上涨情绪
var EMOTION_TOTAL: int = 100                  # 上涨 + 下跌 = 100

# ===== 自然波动 (clamp 范围 / σ 可调) =====
var NATURAL_DRIFT_CLAMP: float = 0.10         # ±10% (策划 4.3)
var NATURAL_VOLATILITY_SIGMA_DEFAULT: float = 0.012   # σ 暂取 1.2%, 待数值组确认
var natural_volatility_sigma: float = 0.012

# ===== 阶段 =====
enum Phase {
	PLAY = 0,    # 行动阶段, 可出牌
	SETTLE = 1,  # 价格 + 情绪结算 (瞬时, 没有玩家输入)
	SHOP = 2,    # 盘后商店 (阶段4 才接入)
	OVER = 3,    # 整局结束
}

# ===== 商店 =====
var SHOP_BUY_PRICE: int = 1000
var SHOP_UPGRADE_PRICE: int = 1000
var SHOP_DELETE_BASE_PRICE: int = 1000
var SHOP_DELETE_PRICE_INCREMENT: int = 1000   # 策划: 后续每次删卡价格+1000

var shop_offers: Array = []                     # 当前商店可购买的卡 (Card 实例数组)
var shop_delete_count: int = 0                  # 累计删卡次数, 用来计算下次删卡价
# 当日摘要 (day_open_price 在 _start_day 时记录, 其余在 _end_day 计算)
var day_open_price: float = 100.0
var day_open_assets: float = 100000.0
var day_close_summary: Dictionary = {}          # {day, open_price, close_price, day_pnl, total_assets, shares, holding_value}

# ===== 信号 =====
signal state_changed
signal hand_changed
signal turn_started(day: int, turn_in_day: int)
signal turn_ended(day: int, turn_in_day: int)
signal day_started(day: int)
signal day_ended(day: int)                       # 一天 10 回合打完, 进商店之前
signal shop_entered(day: int)                    # 已进入商店阶段
signal shop_changed                              # 商店内购买/升级/删卡后刷新
signal phase_changed(phase: int)
signal candle_committed(turn_global: int)        # 回合 K 入库
signal intraday_updated                          # 分时新点
signal level_finished(victory: bool, final_assets: float)
signal log_message(msg: String)
# 选择类卡: 派发后 emit 一个 request 信号, UI 弹窗收集玩家选择, 回调 game_state.apply_*
signal event_preview_requested(events: Array)             # 三选一突发事件 (Array of Event)
signal discard_choice_requested(hand_cards: Array)        # 顺势而为: 选 1 张手牌弃掉
signal topdeck_choice_requested(draw_pile_cards: Array)   # 计划得当: 选 1 张抽牌堆牌上顶
signal shatter_choice_requested(buy_sell_cards: Array)    # 化整为零: 多选 BUY/SELL 牌
signal event_triggered(event)                    # Event 实例 或 null (清空时)

# ===== 局内状态 =====
var cash: float = 100000.0
var shares: int = 0
var price: float = 100.0
var bull: int = 50                              # 上涨情绪
var bear: int = 50                              # 下跌情绪 (= EMOTION_TOTAL - bull)
var day: int = 0                                # 1..5
var turn_in_day: int = 0                        # 1..10
var turn_global: int = 0                        # 累计回合, 用于 K 线
var phase: int = Phase.PLAY
var action_points: int = 0
var hand: Array = []
var draw_pile: Array = []
var discard_pile: Array = []                    # 等待区 (类似杀戮尖塔), 抽牌堆空时洗回
var is_level_over: bool = false

# ===== 突发事件状态 =====
var current_event: Event = null                          # 当前生效事件 (null = 无)
var event_modifiers: Dictionary = {}                     # 当前 modifier 字典, 通用键值见 _apply_event_effects 注释
var event_modifier_dur: int = 0                          # >0 = 短期 N 回合, 0 = 持续到下次事件
var banned_effect_ids: Array = []                        # 当前被禁出的 effect_id
var triggered_event_ids_this_level: Dictionary = {}      # 本关已触发过的事件 id (一关不重复)
var skills_played_this_turn: int = 0                     # 本回合已使用技能牌数 (skill_cap_per_turn 计数)
var turn_emotion_mul: float = 1.0                        # 本回合情绪变化倍率 (水军出动 → 2.0; _start_turn 重置)
var pending_event_id: String = ""                        # 内幕消息预选: 下次 _trigger_random_event 优先用此 id
var liquidity_buffed_cards: Array = []                   # 本回合 流动性泛滥 命中后 cost-1 的 Card 引用; _settle_turn 末还原
var daily_play_count: Dictionary = {}                    # effect_id → 本日已使用次数 (供 daily_limit 检查); _start_day 重置

# ===== K线 =====
var candles: Array = []                         # 已结算回合 K, 每根 {turn_global, day, turn_in_day, open, high, low, close}
var intraday_ticks: Array[float] = []           # 当前回合分时 (每个价格变化点都 append)
var intraday_candles: Array = []                # 当前回合分时 K 事件序列, 每根 {open, high, low, close, kind}
												# kind: "play" (出牌) / "settle" (回合末自然波动)
var cur_open: float = 0.0
var cur_high: float = 0.0
var cur_low: float = 0.0


# ===========================================================
# 公共 API
# ===========================================================
func _ready() -> void:
	_apply_balance_from_cfg()
	_effect_system = CardEffectSystem.new(self)


# 从 /root/Cfg.balance 把数值刷到本节点的同名 var; 不存在的键保留代码默认.
# 调用一次即可: Cfg 是 autoload, 启动顺序保证它先 _ready.
func _apply_balance_from_cfg() -> void:
	var cfg := get_node_or_null("/root/Cfg")
	if cfg == null:
		return
	var b: Dictionary = cfg.balance
	if b.is_empty():
		return
	if b.has("DAYS_PER_LEVEL"): DAYS_PER_LEVEL = int(b["DAYS_PER_LEVEL"])
	if b.has("TURNS_PER_DAY"): TURNS_PER_DAY = int(b["TURNS_PER_DAY"])
	if b.has("START_CASH"): START_CASH = float(b["START_CASH"])
	if b.has("VICTORY_TARGET"): VICTORY_TARGET = float(b["VICTORY_TARGET"])
	if b.has("INITIAL_PRICE"): INITIAL_PRICE = float(b["INITIAL_PRICE"])
	if b.has("SETTLE_DISCOUNT"): SETTLE_DISCOUNT = float(b["SETTLE_DISCOUNT"])
	if b.has("FIRST_TURN_DRAW"): FIRST_TURN_DRAW = int(b["FIRST_TURN_DRAW"])
	if b.has("TURN_DRAW"): TURN_DRAW = int(b["TURN_DRAW"])
	if b.has("HAND_LIMIT"): HAND_LIMIT = int(b["HAND_LIMIT"])
	if b.has("ACTION_POINTS_INITIAL"): ACTION_POINTS_INITIAL = int(b["ACTION_POINTS_INITIAL"])
	if b.has("ACTION_POINTS_PER_TURN"): ACTION_POINTS_PER_TURN = int(b["ACTION_POINTS_PER_TURN"])
	if b.has("ACTION_POINTS_MAX"): ACTION_POINTS_MAX = int(b["ACTION_POINTS_MAX"])
	if b.has("INITIAL_BULL"): INITIAL_BULL = int(b["INITIAL_BULL"])
	if b.has("EMOTION_TOTAL"): EMOTION_TOTAL = int(b["EMOTION_TOTAL"])
	if b.has("NATURAL_DRIFT_CLAMP"): NATURAL_DRIFT_CLAMP = float(b["NATURAL_DRIFT_CLAMP"])
	if b.has("NATURAL_VOLATILITY_SIGMA_DEFAULT"):
		NATURAL_VOLATILITY_SIGMA_DEFAULT = float(b["NATURAL_VOLATILITY_SIGMA_DEFAULT"])
		natural_volatility_sigma = NATURAL_VOLATILITY_SIGMA_DEFAULT
	if b.has("SHOP_BUY_PRICE"): SHOP_BUY_PRICE = int(b["SHOP_BUY_PRICE"])
	if b.has("SHOP_UPGRADE_PRICE"): SHOP_UPGRADE_PRICE = int(b["SHOP_UPGRADE_PRICE"])
	if b.has("SHOP_DELETE_BASE_PRICE"): SHOP_DELETE_BASE_PRICE = int(b["SHOP_DELETE_BASE_PRICE"])
	if b.has("SHOP_DELETE_PRICE_INCREMENT"): SHOP_DELETE_PRICE_INCREMENT = int(b["SHOP_DELETE_PRICE_INCREMENT"])


func new_level() -> void:
	cash = START_CASH
	shares = 0
	price = INITIAL_PRICE
	bull = INITIAL_BULL
	bear = EMOTION_TOTAL - INITIAL_BULL
	day = 0
	turn_in_day = 0
	turn_global = 0
	action_points = ACTION_POINTS_INITIAL
	hand.clear()
	discard_pile.clear()
	draw_pile = CardDatabase.build_starter_deck()
	draw_pile.shuffle()
	liquidity_buffed_cards.clear()
	daily_play_count.clear()
	candles.clear()
	intraday_ticks.clear()
	intraday_candles.clear()
	cur_open = price
	cur_high = price
	cur_low = price
	is_level_over = false
	phase = Phase.PLAY
	shop_offers.clear()
	shop_delete_count = 0
	day_open_price = INITIAL_PRICE
	day_open_assets = START_CASH
	day_close_summary = {}
	# 突发事件状态: 一关不重复
	triggered_event_ids_this_level.clear()
	_clear_event_state()
	emit_signal("event_triggered", null)
	_log("新一关开始 - 资金 ¥%s, 目标 ¥%s, 5 天 × 10 回合" % [_fmt_money(START_CASH), _fmt_money(VICTORY_TARGET)])
	emit_signal("state_changed")
	_start_day()


# ----- 出牌 -----
func play_card(index: int) -> bool:
	if is_level_over: return false
	if phase != Phase.PLAY:
		_log("非行动阶段，无法出牌")
		return false
	if index < 0 or index >= hand.size():
		return false
	var c: Card = hand[index]
	if action_points < c.cost:
		_log("行动力不足，无法打出「%s」" % c.name)
		return false
	# 资源前置检查 (策划: 不满足直接拒绝, 不扣 AP, 不进弃牌堆)
	if not _has_resources_for(c):
		return false
	# 突发事件: 重点监控 - 每回合最多 N 张技能牌
	if c.is_skill() and event_modifiers.has("skill_cap_per_turn"):
		var cap: int = int(event_modifiers["skill_cap_per_turn"])
		if skills_played_this_turn >= cap:
			_log("[重点监控] 本回合技能牌已达上限 %d" % cap)
			return false
	# 突发事件: ban 卡
	if banned_effect_ids.has(c.effect_id):
		_log("[突发事件] 此卡当前被禁用: %s" % c.name)
		return false
	# 平衡: 每日使用上限 (daily_limit)
	if c.daily_limit > 0:
		var used: int = int(daily_play_count.get(c.effect_id, 0))
		if used >= c.daily_limit:
			_log("「%s」今日已使用 %d 次, 达到上限" % [c.name, c.daily_limit])
			return false
	action_points -= c.cost
	hand.remove_at(index)
	if c.daily_limit > 0:
		daily_play_count[c.effect_id] = int(daily_play_count.get(c.effect_id, 0)) + 1
	# 记录出牌前价位
	var price_before: float = price
	var hi_before: float = cur_high
	var lo_before: float = cur_low
	var bull_before: int = bull
	_dispatch_effect(c.effect_id)
	if c.is_skill():
		skills_played_this_turn += 1
	# 出牌后这一段时间内 (effect 可能多次调用 apply_price_change), 价格区间 = (hi_before..cur_high, lo_before..cur_low)
	# 计算这次出牌的 high/low: 取 dispatch 期间 cur_high/cur_low 的"增量"
	# 简单做法: high = max(open, close, cur_high in this play), low = min(open, close, cur_low in this play)
	# 由于 cur_high/cur_low 是本回合累计, 此次出牌的实际波动范围 = 出牌前后的 price 区间 + 出牌过程中 _track_price 经过的极值
	# 为不引入新的状态, 这里取 open/close 极值作为该 K 的 high/low (足够分时可视化)
	var price_after: float = price
	var k_open: float = price_before
	var k_close: float = price_after
	var k_high: float = max(k_open, k_close)
	var k_low:  float = min(k_open, k_close)
	# 若出牌中途价格穿越过 open/close 之外 (apply_price_change 多次调用), 取累计极值
	if cur_high > hi_before and cur_high > k_high: k_high = cur_high
	if cur_low  < lo_before and cur_low  < k_low:  k_low  = cur_low
	intraday_candles.append({
		"open":  k_open,
		"close": k_close,
		"high":  k_high,
		"low":   k_low,
		"kind":  "play",
		"card_name": c.name,
		"price_delta_pct": (price_after / price_before - 1.0) * 100.0 if price_before > 0.0 else 0.0,
		"emotion_delta": bull - bull_before,
	})
	discard_pile.append(c)
	if c.daily_exile:
		c.daily_exiled = true
		_log("  [封存] 「%s」当日不再洗回牌堆" % c.name)
	_log("打出「%s」: %s" % [c.name, c.description])
	emit_signal("intraday_updated")
	emit_signal("hand_changed")
	emit_signal("state_changed")
	return true


# ----- 跳过本回合剩余出牌, 直接结算 -----
func end_turn() -> void:
	if is_level_over: return
	if phase != Phase.PLAY:
		return
	phase = Phase.SETTLE
	emit_signal("phase_changed", phase)
	_settle_turn()


# ===========================================================
# 卡牌效果分发 -> 委托给 CardEffectSystem
# ===========================================================
func _dispatch_effect(effect_id: String) -> void:
	_effect_system.dispatch(effect_id)


# 资源前置检查 (策划: 不满足直接拒绝出牌, 不扣 AP, 不进弃牌堆)
# 规则:
#   BUY  + trade_shares > 0 → 要求 cash    >= trade_shares × price
#   BUY  + buy_pct > 0      → 要求 cash    >= price (至少 1 股)
#   SELL + trade_shares > 0 → 要求 shares  >= trade_shares
#   SELL + sell_pct > 0     → 要求 shares  >= 1
# SKILL/EVENT 不受此检查
func _has_resources_for(c: Card) -> bool:
	if not (c.is_buy() or c.is_sell()):
		return true
	var cfg = get_node_or_null("/root/Cfg")
	var tpl: Variant = null if cfg == null else cfg.get_card_template(c.effect_id)
	var ts: int = 0
	var bp: float = 0.0
	var sp: float = 0.0
	if tpl != null:
		ts = int(tpl.get("trade_shares", 0))
		bp = float(tpl.get("buy_pct", 0.0))
		sp = float(tpl.get("sell_pct", 0.0))
	if c.is_buy():
		var need_cash: float = (float(ts) * price) if ts > 0 else (price if bp > 0.0 else 0.0)
		if need_cash > 0.0 and cash < need_cash:
			_log("现金不足, 无法打出「%s」(需要 ≥ ¥%s)" % [c.name, _fmt_money(need_cash)])
			return false
	else: # is_sell
		var need_shares: int = ts if ts > 0 else (1 if sp > 0.0 else 0)
		if need_shares > 0 and shares < need_shares:
			_log("持仓不足, 无法打出「%s」(需要 ≥ %d 股)" % [c.name, need_shares])
			return false
	return true


# ===========================================================
# 原子操作
# ===========================================================
# 影响股价 (rate 是相对当前价的百分比变化, 已考虑情绪倍率)
func apply_price_change(rate: float, ignore_emotion_modifier: bool = false) -> void:
	var eff_rate: float = rate
	if not ignore_emotion_modifier:
		eff_rate = rate * _emotion_modifier_for_price(rate)
	var old_price: float = price
	price = max(1.0, price * (1.0 + eff_rate))
	# 突发事件: 涨跌停封顶 (相对当日开盘价)
	if event_modifiers.has("cap_drift_up"):
		var up_cap: float = float(event_modifiers["cap_drift_up"])
		var max_p: float = day_open_price * (1.0 + up_cap)
		if price > max_p:
			price = max_p
	if event_modifiers.has("cap_drift_down"):
		var dn_cap: float = float(event_modifiers["cap_drift_down"])
		var min_p: float = max(1.0, day_open_price * (1.0 - dn_cap))
		if price < min_p:
			price = min_p
	_track_price()
	_log("  股价 %+.1f%% (¥%.2f → ¥%.2f)" % [eff_rate * 100.0, old_price, price])


# 改变上涨情绪 (下跌情绪自动补足)
# 突发事件: emotion_floor / emotion_ceiling 在此处 clamp
func apply_emotion_delta_bull(delta: int) -> void:
	var old: int = bull
	if turn_emotion_mul != 1.0 and delta != 0:
		delta = int(round(float(delta) * turn_emotion_mul))
	bull = clamp(bull + delta, 0, EMOTION_TOTAL)
	if event_modifiers.has("emotion_floor"):
		bull = max(bull, int(event_modifiers["emotion_floor"]))
	if event_modifiers.has("emotion_ceiling"):
		bull = min(bull, int(event_modifiers["emotion_ceiling"]))
	bear = EMOTION_TOTAL - bull
	_log("  情绪 上涨%+d → %d/%d" % [delta, bull, bear])
	if old == bull:
		return


# 直接把 bull 设到指定值 (稳定人心: 50)
func set_emotion_bull(v: int) -> void:
	var old: int = bull
	bull = clamp(v, 0, EMOTION_TOTAL)
	if event_modifiers.has("emotion_floor"):
		bull = max(bull, int(event_modifiers["emotion_floor"]))
	if event_modifiers.has("emotion_ceiling"):
		bull = min(bull, int(event_modifiers["emotion_ceiling"]))
	bear = EMOTION_TOTAL - bull
	_log("  情绪 强制设定 → %d/%d" % [bull, bear])
	if old == bull:
		return


# 当前情绪反转 (舆论反转: bull = total - bull)
func invert_emotion() -> void:
	set_emotion_bull(EMOTION_TOTAL - bull)


# ===========================================================
# 选择类卡 API: dispatch → request_* signal → UI 弹窗 → apply_*
# ===========================================================

# 内幕消息: 抽 3 个候选事件 (排除本关已触发, 不足 3 张则有几张算几张), emit 让 UI 三选一
func request_event_preview() -> void:
	var pool: Array = EventDatabase.build_event_pool()
	var filtered: Array = []
	for ev in pool:
		if not triggered_event_ids_this_level.has(ev.id):
			filtered.append(ev)
	if filtered.is_empty():
		filtered = pool
	filtered.shuffle()
	var n: int = min(3, filtered.size())
	var picks: Array = []
	for i in range(n):
		picks.append(filtered[i])
	if picks.is_empty():
		_log("  [内幕消息] 候选池为空, 无效果")
		return
	_log("  [内幕消息] 提供 %d 个事件候选, 等待玩家选择" % picks.size())
	emit_signal("event_preview_requested", picks)


# UI 回调: 玩家从三选一里选定的事件 id
func set_pending_event(event_id: String) -> void:
	pending_event_id = event_id
	_log("  [内幕消息] 已预选下一次事件: %s" % event_id)


# 顺势而为: 让 UI 列出当前手牌让玩家选 1 张
func request_discard_choice() -> void:
	if hand.is_empty():
		_log("  [顺势而为] 手牌为空, 直接抽 1")
		draw_cards(1)
		return
	emit_signal("discard_choice_requested", hand.duplicate())


# UI 回调: 弃 hand[idx] 后抽 1
func discard_one_then_draw(idx: int) -> void:
	if idx < 0 or idx >= hand.size():
		return
	var c: Card = hand[idx]
	hand.remove_at(idx)
	discard_pile.append(c)
	_log("  [顺势而为] 弃掉「%s」" % c.name)
	emit_signal("hand_changed")
	draw_cards(1)
	emit_signal("state_changed")


# 计划得当: 让 UI 列出抽牌堆所有牌让玩家选 1 张
func request_topdeck_choice() -> void:
	if draw_pile.is_empty():
		_log("  [计划得当] 抽牌堆为空, 无效果")
		return
	emit_signal("topdeck_choice_requested", draw_pile.duplicate())


# UI 回调: 把 draw_pile[idx] 移到牌堆顶 (pop_back 是抽牌, 所以堆顶 = 数组末尾)
func place_on_top_of_draw(idx: int) -> void:
	if idx < 0 or idx >= draw_pile.size():
		return
	var c: Card = draw_pile[idx]
	draw_pile.remove_at(idx)
	draw_pile.append(c)
	_log("  [计划得当] 「%s」已放到牌堆顶, 下次必抽" % c.name)
	emit_signal("state_changed")


# 流动性泛滥: chance 概率让所有手牌 cost -1 (最低 0), 仅本回合生效, _settle_turn 末还原
func try_apply_liquidity(chance: float) -> void:
	if randf() >= chance:
		_log("  [流动性泛滥] 未触发 (%.0f%% 概率)" % (chance * 100.0))
		return
	var n: int = 0
	for c in hand:
		if c.cost > 0:
			c.cost -= 1
			liquidity_buffed_cards.append(c)
			n += 1
	_log("  [流动性泛滥] 触发! %d 张手牌费用 -1 (仅本回合)" % n)
	emit_signal("hand_changed")
	emit_signal("state_changed")


# 还原流动性泛滥的 cost-1 buff (回合末调用; Card 可能已经离开 hand 进 discard, 引用还原仍生效)
func _revert_liquidity_buffs() -> void:
	if liquidity_buffed_cards.is_empty():
		return
	for c in liquidity_buffed_cards:
		c.cost += 1
	_log("  [流动性泛滥] 回合结束, %d 张卡费用还原" % liquidity_buffed_cards.size())
	liquidity_buffed_cards.clear()
	emit_signal("hand_changed")


# 化整为零: 让 UI 列出手牌中所有 BUY/SELL 牌让玩家多选
func request_shatter() -> void:
	var cands: Array = []
	for c in hand:
		if c.is_buy() or c.is_sell():
			cands.append(c)
	if cands.is_empty():
		_log("  [化整为零] 手牌中没有 BUY/SELL 牌, 无效果")
		return
	emit_signal("shatter_choice_requested", cands)


# UI 回调: 玩家选定的卡 (Array of Card 实例) 全部进弃牌堆, 每张 BUY 换 2 张 small_buy, 每张 SELL 换 2 张 small_sell (全部 transient)
func shatter_cards(picked_cards: Array) -> void:
	if picked_cards.is_empty():
		return
	var add_buy: int = 0
	var add_sell: int = 0
	for c in picked_cards:
		var idx: int = hand.find(c)
		if idx < 0:
			continue
		hand.remove_at(idx)
		discard_pile.append(c)
		if c.is_buy():
			add_buy += 2
		elif c.is_sell():
			add_sell += 2
	for i in range(add_buy):
		hand.append(CardDatabase.make_by_effect("small_buy", "shatter_b_%d_%d" % [turn_global, i], true))
	for i in range(add_sell):
		hand.append(CardDatabase.make_by_effect("small_sell", "shatter_s_%d_%d" % [turn_global, i], true))
	_log("  [化整为零] 碎掉 %d 张 → 生成 %d 小买 + %d 小卖 (本回合限定)" % [picked_cards.size(), add_buy, add_sell])
	emit_signal("hand_changed")
	emit_signal("state_changed")


# transient 卡清理: 从手/抽/弃牌堆里全部移除, 不入任何堆 (相当于销毁)
func _strip_transient_cards() -> void:
	var removed: int = 0
	for arr in [hand, draw_pile, discard_pile]:
		var i: int = arr.size() - 1
		while i >= 0:
			if arr[i].transient:
				arr.remove_at(i)
				removed += 1
			i -= 1
	if removed > 0:
		_log("  [本回合限定卡] 清理 %d 张" % removed)
		emit_signal("hand_changed")


func _buy_with_cash(spend: float, trade_price_pct: float = 0.0) -> void:
	if spend <= 0.0 or price <= 0.0:
		return
	if spend > cash:
		spend = cash
	var n: int = int(floor(spend / price))
	if n <= 0:
		_log("  资金过少, 无法成交 1 股")
		return
	var cost: float = float(n) * price
	cash -= cost
	shares += n
	_log("  买入 %d 股 @ ¥%.2f, 花费 ¥%s" % [n, price, _fmt_money(cost)])
	if trade_price_pct != 0.0:
		apply_price_change(trade_price_pct)


# 按固定股数买入 (策划: 基础买入卡用此分支, 100 股 + 股价 +1%)
# 资源检查由 play_card 前置, 此处只做兜底
func _buy_shares(n: int, trade_price_pct: float = 0.0) -> void:
	if n <= 0 or price <= 0.0:
		return
	var cost: float = float(n) * price
	if cost > cash:
		_log("  现金不足, 无法成交 %d 股 @ ¥%.2f" % [n, price])
		return
	cash -= cost
	shares += n
	_log("  买入 %d 股 @ ¥%.2f, 花费 ¥%s" % [n, price, _fmt_money(cost)])
	if trade_price_pct != 0.0:
		apply_price_change(trade_price_pct)


func _sell_shares(n: int, trade_price_pct: float = 0.0) -> void:
	if n <= 0:
		_log("  持仓不足, 无法卖出")
		return
	if n > shares: n = shares
	var income: float = float(n) * price
	shares -= n
	cash += income
	_log("  卖出 %d 股 @ ¥%.2f, 收入 ¥%s" % [n, price, _fmt_money(income)])
	if trade_price_pct != 0.0:
		apply_price_change(trade_price_pct)


# ===========================================================
# 抽牌 / 弃牌
# ===========================================================
func draw_cards(n: int) -> int:
	var got: int = 0
	for i in range(n):
		if hand.size() >= HAND_LIMIT: break
		if draw_pile.is_empty():
			if discard_pile.is_empty(): break
			var reshuffleable: Array = []
			var keep_exiled: Array = []
			for dc in discard_pile:
				if dc.daily_exiled:
					keep_exiled.append(dc)
				else:
					reshuffleable.append(dc)
			if reshuffleable.is_empty(): break
			draw_pile = reshuffleable
			discard_pile = keep_exiled
			draw_pile.shuffle()
			if keep_exiled.is_empty():
				_log("  抽牌堆空, 等待区 %d 张洗回" % draw_pile.size())
			else:
				_log("  抽牌堆空, 等待区 %d 张洗回 (封存 %d 张留在弃牌堆)" % [draw_pile.size(), keep_exiled.size()])
		hand.append(draw_pile.pop_back())
		got += 1
	if got > 0:
		emit_signal("hand_changed")
	return got


# 整局第一回合保底: 先种 1 买 + 1 卖 + 1 技能 (策划 7.2.8)
# 在 draw_cards 之前调用, 保证三类齐全且总手牌 = FIRST_TURN_DRAW
func _seed_first_turn() -> void:
	_take_first_of_kind(Card.Kind.BUY)
	_take_first_of_kind(Card.Kind.SELL)
	_take_first_of_kind(Card.Kind.SKILL)


func _take_first_of_kind(kind: int) -> bool:
	if hand.size() >= HAND_LIMIT: return false
	for i in range(draw_pile.size()):
		if draw_pile[i].kind == kind:
			hand.append(draw_pile[i])
			draw_pile.remove_at(i)
			return true
	return false


# ===========================================================
# 内部: 天 / 回合 / 结算
# ===========================================================
func _start_day() -> void:
	day += 1
	turn_in_day = 0
	day_open_price = price
	ACTION_POINTS_PER_TURN = ACTION_POINTS_INITIAL
	bull = INITIAL_BULL
	bear = EMOTION_TOTAL - INITIAL_BULL
	day_open_assets = get_total_assets()
	daily_play_count.clear()
	# 突发事件: 清当天事件残留 (modifier / banned / dur 都按"持续到下次事件"截断在天结束)
	_clear_event_state()
	emit_signal("event_triggered", null)
	_log("==== 第 %d / %d 天 开盘 ¥%.2f (情绪重置 50/50) ====" % [day, DAYS_PER_LEVEL, day_open_price])
	emit_signal("day_started", day)
	_start_turn()


func _start_turn() -> void:
	# 化整为零产物: 上回合留下的临时卡, 在新回合开始时全部消失 (不入弃牌堆)
	_strip_transient_cards()
	turn_in_day += 1
	turn_global += 1
	action_points = ACTION_POINTS_PER_TURN
	# 本回合 OHLC 初始化
	cur_open = price
	cur_high = price
	cur_low = price
	intraday_ticks.clear()
	intraday_ticks.append(price)
	intraday_candles.clear()
	# 阶段必须在抽牌前切回 PLAY, 否则 hand_changed 信号触发 UI 重建按钮时
	# UI 仍认为是 SETTLE 阶段而把所有手牌按钮 disable
	phase = Phase.PLAY
	skills_played_this_turn = 0
	turn_emotion_mul = 1.0
	# 抽牌 (会发 hand_changed)
	# 每天第 1 回合摸 6 张 (首日及每天开始时的"起始手牌"); 其它回合摸 2 张.
	# 整局首回合: 先种 1 买 + 1 卖 + 1 技能, 再补到 6 张 (策划 7.2.8, 修复 "缺类型补 1 → 7 张" bug)
	if turn_in_day == 1:
		if turn_global == 1:
			_seed_first_turn()
			var to_draw: int = max(0, FIRST_TURN_DRAW - hand.size())
			if to_draw > 0:
				draw_cards(to_draw)
			emit_signal("hand_changed")
		else:
			draw_cards(FIRST_TURN_DRAW)
	else:
		draw_cards(TURN_DRAW)
	# 突发事件: 账户审查 - 抽完牌后随机弃 N 张
	if event_modifiers.has("freeze_per_turn"):
		var n: int = int(event_modifiers["freeze_per_turn"])
		for _i in range(n):
			if hand.is_empty(): break
			var idx: int = randi() % hand.size()
			var c: Card = hand[idx]
			hand.remove_at(idx)
			discard_pile.append(c)
			_log("  [账户审查] 冻结手牌「%s」" % c.name)
		emit_signal("hand_changed")
	# 突发事件: 混乱之日 - 每回合 50% AP+1 / 50% AP-1
	if event_modifiers.get("ap_chaos", false):
		_apply_ap_chaos()
	_log("--- 第 %d 天 第 %d 回合 [行动阶段] ---" % [day, turn_in_day])
	emit_signal("turn_started", day, turn_in_day)
	emit_signal("phase_changed", phase)
	emit_signal("intraday_updated")
	# 兜底再发一次 hand_changed, 确保 UI 用最新 phase/AP 重建所有手牌按钮
	emit_signal("hand_changed")
	emit_signal("state_changed")
	# 突发事件刷新: 每天第 1 / 第 5 回合开盘抽牌后
	if turn_in_day == 1 or turn_in_day == 5:
		_trigger_random_event()


func _settle_turn() -> void:
	# 1. 自然波动
	var drift: float = _roll_natural_drift()
	var old_price: float = price
	price = max(1.0, price * (1.0 + drift))
	# 涨跌停封顶 (与 apply_price_change 一致)
	if event_modifiers.has("cap_drift_up"):
		var up_cap: float = float(event_modifiers["cap_drift_up"])
		var max_p: float = day_open_price * (1.0 + up_cap)
		if price > max_p: price = max_p
	if event_modifiers.has("cap_drift_down"):
		var dn_cap: float = float(event_modifiers["cap_drift_down"])
		var min_p: float = max(1.0, day_open_price * (1.0 - dn_cap))
		if price < min_p: price = min_p
	_track_price()
	_log("  回合末自然波动 %+.2f%% → ¥%.2f" % [drift * 100.0, price])
	# 1.5 自然波动作为分时 K 最后一根
	intraday_candles.append({
		"open":  old_price,
		"close": price,
		"high":  max(old_price, price),
		"low":   min(old_price, price),
		"kind":  "settle",
		"card_name": "自然波动",
		"price_delta_pct": drift * 100.0,
		"emotion_delta": 0,
	})
	# 1.6 神秘资金: 30% 概率额外 ±5%
	if event_modifiers.get("mystery_active", false) and randf() < 0.3:
		var bonus: float = 0.05 if randf() < 0.5 else -0.05
		var pre: float = price
		apply_price_change(bonus, true)
		_log("  [神秘资金] 额外 %+.2f%% (¥%.2f → ¥%.2f)" % [bonus * 100.0, pre, price])
	emit_signal("intraday_updated")
	# 2. 提交一根回合 K
	var turn_cards: Array = []
	for ic in intraday_candles:
		if ic["kind"] == "play":
			turn_cards.append(String(ic["card_name"]))
	candles.append({
		"turn_global": turn_global,
		"day": day,
		"turn_in_day": turn_in_day,
		"open": cur_open,
		"high": cur_high,
		"low":  cur_low,
		"close": price,
		"cards": turn_cards,
	})
	emit_signal("candle_committed", turn_global)
	ACTION_POINTS_PER_TURN = min(ACTION_POINTS_PER_TURN + 1, ACTION_POINTS_MAX)
	_revert_liquidity_buffs()
	# 3. 触发回合结束
	emit_signal("turn_ended", day, turn_in_day)
	# 4. 突发事件 dur_turns 倒计时 (短期事件如 超预期财报 / 财报逆袭 = 3)
	if event_modifier_dur > 0:
		event_modifier_dur -= 1
		if event_modifier_dur == 0:
			_log("  [突发事件] 「%s」效果到期" % (current_event.name if current_event != null else ""))
			_clear_event_state()
			emit_signal("event_triggered", null)
			emit_signal("state_changed")
	# 5. 推进
	if turn_in_day >= TURNS_PER_DAY:
		_end_day()
	else:
		_start_turn()


func _end_day() -> void:
	# 一天 10 回合打完
	_log("==== 第 %d 天 收盘 ¥%.2f ====" % [day, price])
	# 当日结算摘要
	day_close_summary = {
		"day": day,
		"open_price": day_open_price,
		"close_price": price,
		"price_change_pct": (price / day_open_price - 1.0) * 100.0,
		"day_pnl": get_total_assets() - day_open_assets,
		"total_assets": get_total_assets(),
		"shares": shares,
		"holding_value": get_holding_value(),
		"cash": cash,
	}
	emit_signal("day_ended", day)
	if day >= DAYS_PER_LEVEL:
		# 第 5 天直接进入最终结算 (策划文档未指定第 5 天后是否还有商店, 暂走结算)
		_settle_level()
	else:
		_enter_shop()


func _enter_shop() -> void:
	phase = Phase.SHOP
	shop_offers = CardDatabase.build_shop_offers(day, _owned_effect_ids())   # 用 day 作 seed; owned 用于过滤 shop_unique
	_log("---- 进入第 %d 天 盘后商店 ----" % day)
	emit_signal("phase_changed", phase)
	emit_signal("shop_entered", day)
	emit_signal("shop_changed")
	emit_signal("state_changed")


# 玩家牌组里出现过的全部 effect_id (去重), 供 shop_unique 过滤
func _owned_effect_ids() -> Array:
	var seen: Dictionary = {}
	for c in get_full_deck():
		seen[c.effect_id] = true
	return seen.keys()


# 玩家点 "离开商店" 进入下一天
func leave_shop_to_next_day() -> void:
	if phase != Phase.SHOP:
		return
	if day >= DAYS_PER_LEVEL:
		_settle_level()
		return
	_log("---- 离开商店, 进入第 %d 天 ----" % (day + 1))
	# 进入下一天前清空"等待区"和手牌, 让新一天从牌库重新抽 (策划: 玩家牌组保留)
	# 杀戮尖塔风格: 抽牌堆 = 自己的牌组, 等待区+手牌都洗回去
	for c in hand:
		discard_pile.append(c)
	hand.clear()
	# 把所有牌合并到抽牌堆, 重洗 (跨日, 解除当日封存)
	for c in discard_pile:
		c.daily_exiled = false
	for c in draw_pile:
		c.daily_exiled = false
	for c in discard_pile:
		draw_pile.append(c)
	discard_pile.clear()
	draw_pile.shuffle()
	_start_day()


func _settle_level() -> void:
	# 周五结算: 未卖筹码 × 当前股价 × 50% 强制折算
	var liquidation: float = float(shares) * price * SETTLE_DISCOUNT
	var final_assets: float = cash + liquidation
	is_level_over = true
	phase = Phase.OVER
	_log("==== 关卡结算 ====")
	_log("现金 ¥%s + 持仓折价 (¥%.2f × %d × %.0f%%) = ¥%s" % [
		_fmt_money(cash), price, shares, SETTLE_DISCOUNT * 100.0,
		_fmt_money(final_assets)
	])
	# 落清算金额; 持仓清零便于 UI 显示
	cash = final_assets
	shares = 0
	var victory: bool = final_assets >= VICTORY_TARGET
	if victory:
		_log("[胜利] 达到目标 ¥%s" % _fmt_money(VICTORY_TARGET))
	else:
		_log("[失败] 未达目标 ¥%s" % _fmt_money(VICTORY_TARGET))
	emit_signal("phase_changed", phase)
	emit_signal("state_changed")
	emit_signal("level_finished", victory, final_assets)


# ===========================================================
# 自然波动 / 情绪倍率
# ===========================================================
func _roll_natural_drift() -> float:
	# 突发事件: 市场失真 → μ 强制为 0
	var decoupled: bool = event_modifiers.get("decouple", false)
	var mu: float = 0.0 if decoupled else (float(bull) - 50.0) / 50.0 * NATURAL_DRIFT_CLAMP
	var x: float = _gaussian(mu, natural_volatility_sigma)
	return clamp(x, -NATURAL_DRIFT_CLAMP, NATURAL_DRIFT_CLAMP)


# Box-Muller 正态分布 (Godot 没内建)
func _gaussian(mean: float, sigma: float) -> float:
	var u1: float = max(randf(), 1e-9)
	var u2: float = randf()
	var z: float = sqrt(-2.0 * log(u1)) * cos(TAU * u2)
	return mean + sigma * z


# 情绪对价格变化的倍率 (策划 3.4 表)
# rate>0 → 买入方向取 "买入上涨倍率"
# rate<0 → 卖出方向取 "卖出下跌倍率"
# 突发事件: decouple → 直接 1.0; emotion_modifier_mul → 末尾再乘
func _emotion_modifier_for_price(rate: float) -> float:
	if event_modifiers.get("decouple", false):
		return 1.0
	var m: float = 1.0
	if rate >= 0.0:
		# buy direction
		if bull <= 30: m = 0.5
		elif bull <= 50: m = 0.8
		elif bull <= 70: m = 1.5
		else: m = 2.0
	else:
		# sell / 砸盘 direction; 看下跌情绪 (=100-bull)
		var bear_v: int = EMOTION_TOTAL - bull
		if bear_v <= 30: m = 0.5
		elif bear_v <= 50: m = 0.8
		elif bear_v <= 70: m = 1.5
		else: m = 2.0
	if event_modifiers.has("emotion_modifier_mul"):
		m *= float(event_modifiers["emotion_modifier_mul"])
	return m


# ===========================================================
# 查询
# ===========================================================
func emotion_state() -> String:
	if bull <= 30: return "极度恐慌"
	elif bull <= 50: return "偏空"
	elif bull <= 70: return "偏多"
	else: return "极度狂热"


func get_holding_value() -> float:
	return float(shares) * price


func get_total_assets() -> float:
	return cash + get_holding_value()


# ===========================================================
# 内部辅助
# ===========================================================
func _track_price() -> void:
	intraday_ticks.append(price)
	if price > cur_high: cur_high = price
	if price < cur_low: cur_low = price
	emit_signal("intraday_updated")


func _fmt_money(v: float) -> String:
	var n: int = int(round(v))
	var neg: bool = n < 0
	var s: String = str(abs(n))
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count == 3 and i > 0:
			out = "," + out
			count = 0
	if neg: out = "-" + out
	return out


func _log(msg: String) -> void:
	emit_signal("log_message", msg)
	print(msg)


# ===========================================================
# 商店 API (阶段4)
# ===========================================================
# 牌组聚合 (玩家拥有的全部卡牌, 包含手牌+抽牌堆+等待区)
func get_full_deck() -> Array:
	var all: Array = []
	for c in hand: all.append(c)
	for c in draw_pile: all.append(c)
	for c in discard_pile: all.append(c)
	return all


func get_deck_size() -> int:
	return hand.size() + draw_pile.size() + discard_pile.size()


# 当前删卡价 (基础 1000 + 已删次数 × 1000)
func current_delete_price() -> int:
	return SHOP_DELETE_BASE_PRICE + shop_delete_count * SHOP_DELETE_PRICE_INCREMENT


# 商店: 买卡 (从 shop_offers 拿一张)
func shop_buy_card(offer_index: int) -> bool:
	if phase != Phase.SHOP: return false
	if offer_index < 0 or offer_index >= shop_offers.size(): return false
	var card: Card = shop_offers[offer_index]
	var price_due: int = card.shop_price if card.shop_price > 0 else SHOP_BUY_PRICE
	if cash < price_due:
		_log("现金不足, 无法购买 (需要 ¥%d)" % price_due)
		return false
	cash -= price_due
	# 进入抽牌堆 (杀戮尖塔: 新卡进 deck, 下一次洗牌时随机)
	draw_pile.append(card)
	draw_pile.shuffle()
	shop_offers.remove_at(offer_index)
	_log("[商店] 买入「%s」, 花费 ¥%d" % [card.name, price_due])
	emit_signal("shop_changed")
	emit_signal("state_changed")
	return true


# 商店: 升级一张牌 (按"全牌组中的索引"操作)
# deck_index: 0..get_deck_size()-1, 顺序与 get_full_deck() 一致
func shop_upgrade_card(deck_index: int) -> bool:
	if phase != Phase.SHOP: return false
	if cash < SHOP_UPGRADE_PRICE:
		_log("现金不足, 无法升级 (需要 ¥%d)" % SHOP_UPGRADE_PRICE)
		return false
	var entry: Dictionary = _locate_in_deck(deck_index)
	if entry.is_empty(): return false
	var card: Card = entry["card"]
	var target_eid: String = CardDatabase.upgrade_target(card.effect_id)
	if target_eid == "":
		_log("「%s」无可升级目标" % card.name)
		return false
	# 替换
	var new_card: Card = CardDatabase.make_by_effect(target_eid, card.id + "_up")
	cash -= SHOP_UPGRADE_PRICE
	entry["pile"][entry["index"]] = new_card
	_log("[商店] 升级「%s」→「%s」, 花费 ¥%d" % [card.name, new_card.name, SHOP_UPGRADE_PRICE])
	emit_signal("hand_changed")
	emit_signal("shop_changed")
	emit_signal("state_changed")
	return true


# 商店: 删卡
func shop_delete_card(deck_index: int) -> bool:
	if phase != Phase.SHOP: return false
	var del_price: int = current_delete_price()
	if cash < del_price:
		_log("现金不足, 无法删卡 (需要 ¥%d)" % del_price)
		return false
	if get_deck_size() <= 1:
		_log("牌组至少保留 1 张")
		return false
	var entry: Dictionary = _locate_in_deck(deck_index)
	if entry.is_empty(): return false
	var card: Card = entry["card"]
	cash -= del_price
	(entry["pile"] as Array).remove_at(entry["index"])
	shop_delete_count += 1
	_log("[商店] 删除「%s」, 花费 ¥%d, 下次删卡 ¥%d" % [card.name, del_price, current_delete_price()])
	emit_signal("hand_changed")
	emit_signal("shop_changed")
	emit_signal("state_changed")
	return true


# 把"全牌组索引"映射回具体的 (pile, in-pile index)
# 顺序: hand → draw_pile → discard_pile
func _locate_in_deck(deck_index: int) -> Dictionary:
	if deck_index < 0:
		return {}
	if deck_index < hand.size():
		return {"pile": hand, "index": deck_index, "card": hand[deck_index]}
	var off: int = deck_index - hand.size()
	if off < draw_pile.size():
		return {"pile": draw_pile, "index": off, "card": draw_pile[off]}
	off -= draw_pile.size()
	if off < discard_pile.size():
		return {"pile": discard_pile, "index": off, "card": discard_pile[off]}
	return {}


# ===========================================================
# Events: 突发事件系统
# - 每天第 1 / 第 5 回合开盘抽牌后调用 _trigger_random_event()
# - 一关不重复 (triggered_event_ids_this_level), 整池跑完后兜底
# - 新事件刷新时清空旧 modifiers / dur / banned
# - 短期事件用 dur_turns; _settle_turn 末尾倒计时, 归零时清空并 emit event_triggered(null)
# ===========================================================
func _trigger_random_event() -> void:
	# 清旧事件
	_clear_event_state()
	# 内幕消息: 玩家已预选下一次事件 → 优先使用
	if pending_event_id != "":
		var picked_ev: Event = EventDatabase.make_by_id(pending_event_id)
		pending_event_id = ""
		if picked_ev != null:
			triggered_event_ids_this_level[picked_ev.id] = true
			current_event = picked_ev
			_log("[突发事件] (玩家预选生效)")
			_apply_event_effects(picked_ev)
			emit_signal("event_triggered", picked_ev)
			emit_signal("state_changed")
			return
	# 候选池: 排除本关已触发
	var pool: Array = EventDatabase.build_event_pool()
	var filtered: Array = []
	for ev in pool:
		if not triggered_event_ids_this_level.has(ev.id):
			filtered.append(ev)
	if filtered.is_empty():
		# 兜底: 整池跑完后退回完整池
		filtered = pool
	var picked: Event = filtered[randi() % filtered.size()]
	triggered_event_ids_this_level[picked.id] = true
	current_event = picked
	_apply_event_effects(picked)
	emit_signal("event_triggered", picked)
	emit_signal("state_changed")


# 一次性 + 持续修饰 全部落地
func _apply_event_effects(ev: Event) -> void:
	_log("[突发事件] %s · %s" % [ev.name, ev.effect_desc])
	# modifiers: 长期/短期 (放到 event_modifiers 字典, 各落地点查表)
	if not ev.modifiers.is_empty():
		for k in ev.modifiers.keys():
			event_modifiers[k] = ev.modifiers[k]
	# emotion_floor / ceiling: 既写 modifier (后续 apply_emotion_delta_bull 会 clamp), 也立即收紧当前 bull
	if ev.emotion_floor >= 0:
		event_modifiers["emotion_floor"] = ev.emotion_floor
	if ev.emotion_ceiling >= 0:
		event_modifiers["emotion_ceiling"] = ev.emotion_ceiling
	# 一次性 delta_bull / delta_bull_random
	if ev.delta_bull != 0:
		apply_emotion_delta_bull(ev.delta_bull)
	if ev.delta_bull_random > 0:
		var d: int = randi_range(-ev.delta_bull_random, ev.delta_bull_random)
		apply_emotion_delta_bull(d)
	# floor/ceiling 即使没改 delta, 也立即把 bull 拉进区间
	if ev.emotion_floor >= 0 or ev.emotion_ceiling >= 0:
		apply_emotion_delta_bull(0)
	# 一次性股价冲击 (无视情绪倍率)
	if ev.price_rate != 0.0:
		apply_price_change(ev.price_rate, true)
	# ap_chaos: 触发瞬间也来一次, 后续每回合 _start_turn 还会再来
	if ev.ap_chaos:
		event_modifiers["ap_chaos"] = true
		_apply_ap_chaos()
	# ban list
	if not ev.banned_effect_ids.is_empty():
		banned_effect_ids = ev.banned_effect_ids.duplicate()
	# dur_turns: >0 → 短期; <=0 → 持续到下次事件
	event_modifier_dur = ev.dur_turns if ev.dur_turns > 0 else 0


func _clear_event_state() -> void:
	current_event = null
	event_modifiers.clear()
	event_modifier_dur = 0
	banned_effect_ids.clear()


func _apply_ap_chaos() -> void:
	if randf() < 0.5:
		action_points = min(action_points + 1, ACTION_POINTS_MAX)
		_log("  [混乱之日] 行动力 +1 → %d" % action_points)
	else:
		action_points = max(action_points - 1, 0)
		_log("  [混乱之日] 行动力 -1 → %d" % action_points)