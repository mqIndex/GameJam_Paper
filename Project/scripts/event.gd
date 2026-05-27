# 突发事件数据类 (类 Card 风格)
# 仅承载数据 + 字段; 实际效果落地在 GameState._apply_event_effects.
# 字段语义对应原先字典版的事件 schema, 见 EventDatabase 的事件清单.
extends RefCounted

# 事件分类 (UI 配色: good→红, bad→绿, neutral→金)
enum Category {
	GOOD,     # 利好 (情绪+ / 价格+)
	BAD,      # 利空 (情绪- / 价格- / 监管打压)
	NEUTRAL,  # 中性 (限幅 / 行动力扰动 / 价格情绪脱钩 等)
}

var id: String = ""
var name: String = ""
var category: int = Category.NEUTRAL
var desc: String = ""                  # 文字描述 (弹窗 / 日志)
var effect_desc: String = ""           # 效果文字 (弹窗显示)
var image_path: String = ""            # 事件配图 res:// 路径 (空 = 无图)
var theme_color: Color = Color(0.22, 0.85, 1.0, 1.0) # 事件图边框颜色

# ---- 一次性效果 ----
var delta_bull: int = 0                # 一次性情绪 ±N
var delta_bull_random: int = 0         # 当回合情绪随机 ±N (0=无)
var price_rate: float = 0.0            # 一次性股价 × (1+rate)
var emotion_floor: int = -1            # 情绪下限 (-1 = 不锚定)
var emotion_ceiling: int = -1          # 情绪上限 (-1 = 不锚定)
var ap_chaos: bool = false             # 触发瞬间 50% AP-1 / 50% AP+1

# ---- 持续修饰 ----
var modifiers: Dictionary = {}         # 写入 GameState.event_modifiers
var dur_turns: int = -1                # 持续回合 (-1 = 持续到下次事件 / 日切)
var banned_effect_ids: Array = []      # ban 的卡 effect_id (持续到下次事件)


func _init(p_id: String, p_name: String, p_category: int,
		p_desc: String, p_effect_desc: String) -> void:
	id = p_id
	name = p_name
	category = p_category
	desc = p_desc
	effect_desc = p_effect_desc


func is_good() -> bool:    return category == Category.GOOD
func is_bad() -> bool:     return category == Category.BAD
func is_neutral() -> bool: return category == Category.NEUTRAL


# 返回 "good" / "bad" / "neutral", 用于 UI 配色查表
func category_str() -> String:
	match category:
		Category.GOOD: return "good"
		Category.BAD:  return "bad"
		_:             return "neutral"
