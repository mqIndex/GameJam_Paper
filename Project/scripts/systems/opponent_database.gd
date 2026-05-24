# 对手数据库: 从 Cfg.opponents 读取 Boss 模板 (RefCounted)
extends RefCounted

const OpponentState = preload("res://scripts/systems/opponent_state.gd")


static func make(opponent_id: String) -> OpponentState:
	var cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	if cfg == null:
		push_error("[OpponentDatabase] Cfg autoload not found")
		return OpponentState.new()
	var tpl: Variant = cfg.get_opponent_template(opponent_id)
	if tpl == null:
		push_error("[OpponentDatabase] Unknown opponent_id: %s" % opponent_id)
		return OpponentState.new()
	return OpponentState.new(tpl)
