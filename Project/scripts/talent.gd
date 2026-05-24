# 天赋数据类
# 阶段5: 数据驱动的天赋系统; 模板字段从 data/talents.csv 读取
# 效果分发交由 GameState 的具体逻辑处理 (按 effect_id 分支)
extends RefCounted

var id: String = ""
var name: String = ""
var description: String = ""
var price: int = 0
var effect_id: String = ""
var in_first_day: bool = false


func _init(p_id: String, p_name: String, p_desc: String, p_price: int, p_effect_id: String, p_in_first_day: bool = false) -> void:
	id = p_id
	name = p_name
	description = p_desc
	price = p_price
	effect_id = p_effect_id
	in_first_day = p_in_first_day