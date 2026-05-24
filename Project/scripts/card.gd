# 卡牌数据类
# 阶段2: 仅承载数据 + effect_id; 效果分发交由 GameState._dispatch_effect 处理
# 重构后: 增加 image_path 字段, 配合 ConfigLoader (Cfg) 从 data/cards.csv 读取
extends RefCounted

# 卡牌种类 (粗分, 用于 UI 着色与"第一回合保底"判定)
enum Kind {
	BUY,      # 基础-买入
	SELL,     # 基础-卖出
	SKILL,    # 技能 (情绪/预测/杠杆/保险等)
	EVENT,    # 事件 (本阶段尚未实现具体事件牌)
}

var id: String = ""
var name: String = ""
var kind: int = Kind.SKILL
var cost: int = 1                # 行动力消耗
var description: String = ""
var effect_id: String = ""       # 由 GameState._dispatch_effect 解析
var image_path: String = ""      # 相对 res:// 或绝对; 空字符串 = 无图(UI 回退到纯色块)

func _init(p_id: String, p_name: String, p_kind: int, p_cost: int, p_desc: String, p_effect_id: String, p_image_path: String = "") -> void:
	id = p_id
	name = p_name
	kind = p_kind
	cost = p_cost
	description = p_desc
	effect_id = p_effect_id
	image_path = p_image_path


func is_buy() -> bool:   return kind == Kind.BUY
func is_sell() -> bool:  return kind == Kind.SELL
func is_skill() -> bool: return kind == Kind.SKILL


# kind 字符串 ("BUY"/"SELL"/"SKILL"/"EVENT") <-> 枚举 互转, 配置加载用
static func kind_from_string(s: String) -> int:
	match s.strip_edges().to_upper():
		"BUY":   return Kind.BUY
		"SELL":  return Kind.SELL
		"SKILL": return Kind.SKILL
		"EVENT": return Kind.EVENT
	push_warning("Unknown card kind string: %s, fallback SKILL" % s)
	return Kind.SKILL
