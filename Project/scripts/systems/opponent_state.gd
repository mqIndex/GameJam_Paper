# 对手数值状态 (RefCounted, 纯数据)
extends RefCounted

var opponent_id: String = ""
var display_name: String = ""
var personality: String = ""
var level: int = 1

# 做空仓位 / 资金
var short_position: int = 0
var entry_avg_price: float = 0.0
var safety_pool: float = 0.0       # 已锁定为保证金的总额
var cash: float = 0.0              # 现金, 用于追加保证金
var required_margin: float = 0.0   # 当前需要的总保证金 (随股价变化)
var liquidation_price: float = 0.0 # 强平价 (cash 用尽时的股价), 仅用于 UI 展示

# 在场状态
var present: bool = false
var defeated_this_level: bool = false

# 难度参数
var n0: int = 500
var m0: float = 25000.0          # 旧字段, 保留兼容 CSV 解析, 不再使用
var initial_cash: float = 100000.0  # 新字段: 对手初始现金
var action_n: int = 100
var action_x_pct: float = 0.015
var action_k_emotion: int = 3
var action_m_cover: int = 80
var pump_trap_y_pct: float = 0.0

# 行为树阈值
var critical_threshold: float = 0.20
var reaction_threshold: float = 0.03
var hard_hold_weight: float = 0.1

# 个性权重
var w_add_short: float = 1.0
var w_bad_news: float = 1.0
var w_cover: float = 1.5
var w_idle: float = 1.5
var w_pump_trap: float = 0.0

# 触发参数 (旧, 保留兼容 CSV, 不再使用)
var trigger_prob_per_turn: float = 0.15
var trigger_rise_pct: float = 0.20

# 台词
var dialog_enter: String = ""
var dialog_react: String = ""
var dialog_cover: String = ""
var dialog_trap: String = ""
var dialog_dying: String = ""
var dialog_defeat: String = ""

# 奖励
var reward_card_id: String = ""

# 上一次行为树分支 (用于检测分支切换弹气泡)
var _last_branch: String = ""


func _init(template: Dictionary = {}) -> void:
	if template.is_empty():
		return
	opponent_id = template.get("opponent_id", "")
	display_name = template.get("display_name", "")
	personality = template.get("personality", "")
	level = int(template.get("level", 1))
	n0 = int(template.get("n0", 500))
	m0 = float(template.get("m0", 25000))
	initial_cash = float(template.get("initial_cash", 100000))
	cash = initial_cash
	action_n = int(template.get("action_n", 100))
	action_x_pct = float(template.get("action_x_pct", 0.015))
	action_k_emotion = int(template.get("action_k_emotion", 3))
	action_m_cover = int(template.get("action_m_cover", 80))
	pump_trap_y_pct = float(template.get("pump_trap_y_pct", 0.0))
	critical_threshold = float(template.get("critical_threshold", 0.20))
	reaction_threshold = float(template.get("reaction_threshold", 0.03))
	hard_hold_weight = float(template.get("hard_hold_weight", 0.1))
	w_add_short = float(template.get("w_add_short", 1.0))
	w_bad_news = float(template.get("w_bad_news", 1.0))
	w_cover = float(template.get("w_cover", 1.5))
	w_idle = float(template.get("w_idle", 1.5))
	w_pump_trap = float(template.get("w_pump_trap", 0.0))
	trigger_prob_per_turn = float(template.get("trigger_prob_per_turn", 0.15))
	trigger_rise_pct = float(template.get("trigger_rise_pct", 0.20))
	dialog_enter = str(template.get("dialog_enter", ""))
	dialog_react = str(template.get("dialog_react", ""))
	dialog_cover = str(template.get("dialog_cover", ""))
	dialog_trap = str(template.get("dialog_trap", ""))
	dialog_dying = str(template.get("dialog_dying", ""))
	dialog_defeat = str(template.get("dialog_defeat", ""))
	reward_card_id = str(template.get("reward_card_id", ""))


# 入场: 建立初始仓位 + 初始保证金 (从 cash 扣)
func spawn(current_price: float) -> void:
	present = true
	defeated_this_level = false
	short_position = n0
	entry_avg_price = current_price
	# 初始保证金 = 股数 × 均价 × 50%, 从 cash 扣
	var initial_margin: float = float(short_position) * current_price * 0.5
	safety_pool = initial_margin
	cash = max(0.0, initial_cash - initial_margin)
	recalc_margin(current_price)
	_last_branch = ""


# 加仓: 重新加权均价, 同时扣初始 50% 保证金
func add_short(n: int, current_price: float) -> bool:
	if n <= 0:
		return false
	var extra_margin: float = float(n) * current_price * 0.5
	if cash < extra_margin:
		# 现金不够开新仓, Brain 应避免, 这里静默返回
		return false
	# 加权均价
	var old_pos := short_position
	entry_avg_price = (entry_avg_price * float(old_pos) + current_price * float(n)) / float(old_pos + n)
	short_position += n
	# 扣 cash 到 safety_pool
	cash -= extra_margin
	safety_pool += extra_margin
	recalc_margin(current_price)
	return true


# 主动减仓 (按比例释放 safety_pool 回 cash)
func cover(m: int) -> void:
	if m <= 0 or short_position <= 0:
		return
	var cover_count: int = min(m, short_position)
	var ratio: float = float(cover_count) / float(short_position)
	var released: float = safety_pool * ratio
	safety_pool -= released
	cash += released
	short_position -= cover_count
	# 仓位归零时, 把残留保证金也还给 cash
	if short_position <= 0:
		cash += safety_pool
		safety_pool = 0.0
		liquidation_price = entry_avg_price
	else:
		liquidation_price = entry_avg_price + (cash + safety_pool) / float(short_position)


# 重新计算 required_margin 和 liquidation_price
func recalc_margin(current_price: float) -> void:
	if short_position <= 0:
		required_margin = 0.0
		liquidation_price = entry_avg_price
		return
	var r: float = current_price / entry_avg_price - 1.0
	required_margin = float(short_position) * entry_avg_price * max(0.5, r)
	# 平仓线 = 当 cash + safety_pool 全部用尽时的股价
	# 公式: short_position * entry_avg_price * r_max = cash + safety_pool
	# => r_max = (cash + safety_pool) / (short_position * entry_avg_price)
	# => liq = entry_avg_price * (1 + r_max) = entry_avg_price + (cash + safety_pool) / short_position
	liquidation_price = entry_avg_price + (cash + safety_pool) / float(short_position)


# 尝试追加保证金, 返回 true 表示成功 (含无需追加), false 表示现金不够 → 强平
func try_top_up_margin(current_price: float) -> bool:
	recalc_margin(current_price)
	if cash <= 0.0:
		return false
	var shortfall: float = required_margin - safety_pool
	if shortfall <= 0.0:
		return true
	if cash >= shortfall:
		cash -= shortfall
		safety_pool += shortfall
		return cash > 0.0
	return false


func is_liquidated(current_price: float) -> bool:
	recalc_margin(current_price)
	if cash <= 0.0:
		return true
	var shortfall: float = required_margin - safety_pool
	return shortfall >= cash


# 危险度 0~1, UI 用. 1 表示触及平仓线即将强平
func get_danger_pct(current_price: float) -> float:
	if liquidation_price <= 0.0:
		return 0.0
	return clampf(current_price / liquidation_price, 0.0, 1.0)


func liquidate() -> void:
	short_position = 0
	defeated_this_level = true
	present = false
	cash = 0.0
	safety_pool = 0.0
