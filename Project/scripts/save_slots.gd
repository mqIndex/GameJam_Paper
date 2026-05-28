# 存档槽位 + 市场人格数据 (autoload: /root/Saves)
# 字段:
#   persona_id                          - 选择的人格 (mr_dealer / ms_controller)
#   played_at                           - 最近一次进入存档的时间字符串
#   max_cleared_level_index             - 已通关的最高关卡 index (-1 = 尚未通关任何关; 0 = 教学关已过, 后续以此类推)
#   tutorial_completed                  - 教学关主体流程已完成
#   tutorial_goal_intro_completed       - 教学关目标介绍 (第 3 天) 已完成
#   formal_intro_completed              - 进入第 1 个正式关时的介绍已完成
#   opponent_tutorial_completed         - 首次遇到对手的引导已完成
#   opponent_reward_tutorial_completed  - 首次击败对手的奖励引导已完成
#   opponent_intro_seen                 - {opponent_id → true} 已看过入场介绍的对手集合 (v2 起)
# 自动保存触发点 (见 main.gd):
#   - Saves.create_slot / touch_slot   (选档/续档)
#   - Game.level_finished (胜利)        → record_level_cleared
#   - Game state_changed 节流           → capture_from_game (snapshot hash 变化时)
# 文件: user://saves.cfg (Godot ConfigFile)
# 版本:
#   - v1: 初始 (无 [meta] 段; 无 opponent_intro_seen)
#   - v2: 增加 [meta] 段含 version; 槽位增加 opponent_intro_seen 字段
#   - v3: 槽位增加 current_level_index / deck_effect_ids / talent_ids (跨关继承的牌组+天赋)
#   - v4: 槽位增加 resume_day / resume_phase / resume_cash / resume_shares / resume_avg_cost / resume_price / resume_bull / resume_turn_global
#         (中途退出后恢复到最近一次 _start_day / _enter_shop 的快照点; 商店内购买不更新)
extends Node

const SAVE_PATH := "user://saves.cfg"
const SAVE_VERSION := 4
const META_SECTION := "meta"
const SLOT_COUNT := 3
# 关卡总数 = 教程关 1 + 正式关数 (LEVEL_OPPONENT_ID.size())
# 与 Game.LEVEL_OPPONENT_ID 解耦, 硬编码避免循环依赖
const TOTAL_LEVEL_COUNT := 3

# 市场人格定义 (id → {name, portrait_path, description})
# 头像在 PlayerPanel/Avatar 通过 set_portrait 应用
const PERSONAS: Dictionary = {
	"mr_dealer": {
		"name": "做局先生",
		"portrait_path": "res://assets/chev/ZJ/ZJ_M.png",
		"description": "西装革履的操盘老手, 擅长制造氛围, 收割追涨杀跌的散户。",
	},
	"ms_controller": {
		"name": "控盘女士",
		"portrait_path": "res://assets/chev/ZJ/ZJ_W.png",
		"description": "心思缜密的盘面控制者, 一手数据一手筹码, 节奏从不失控。",
	},
}

const DEFAULT_PERSONA_ID := "mr_dealer"

# 关卡 index → 显示名 (含教学关). 与 Game.LEVEL_DISPLAY_NAMES 解耦, 避免循环依赖
const LEVEL_NAMES: Array = ["新手关", "正式关", "高压关"]

# tutorial 标志位的 (Game 字段名 → 默认值) 字典, 用于序列化和回放
const TUTORIAL_FLAG_DEFAULTS: Dictionary = {
	"tutorial_completed": false,
	"tutorial_goal_intro_completed": false,
	"formal_intro_completed": false,
	"opponent_tutorial_completed": false,
	"opponent_reward_tutorial_completed": false,
}

# 从 Game 镜像的 Dictionary 字段 (Game 私有变量名 → 序列化键名)
# 通过反射读写 Game.<var_name>; capture/apply 时做深拷贝
const GAME_DICT_FIELDS: Dictionary = {
	"_opponent_intro_seen": "opponent_intro_seen",
}

signal active_slot_changed(slot_index: int, persona_id: String)

var slots: Array = []           # [{exists, persona_id, played_at, max_cleared_level_index, tutorial flags ...}]
var active_slot_index: int = -1
var active_persona_id: String = ""

# 头像缓存: persona_id → Texture2D; 懒加载
var _portrait_cache: Dictionary = {}


func _ready() -> void:
	_init_empty_slots()
	_load_from_disk()


# ---------- 人格查询 ----------
func get_persona_ids() -> Array:
	return PERSONAS.keys()


func get_persona(persona_id: String) -> Dictionary:
	return PERSONAS.get(persona_id, {})


func get_persona_portrait(persona_id: String) -> Texture2D:
	if persona_id == "":
		return null
	if _portrait_cache.has(persona_id):
		return _portrait_cache[persona_id]
	var data: Dictionary = PERSONAS.get(persona_id, {})
	var path: String = String(data.get("portrait_path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_portrait_cache[persona_id] = tex
	return tex


func get_active_portrait() -> Texture2D:
	return get_persona_portrait(active_persona_id)


func get_active_persona_name() -> String:
	var data: Dictionary = PERSONAS.get(active_persona_id, {})
	return String(data.get("name", ""))


func get_level_name(level_index: int) -> String:
	if level_index < 0 or level_index >= LEVEL_NAMES.size():
		return ""
	return String(LEVEL_NAMES[level_index])


# 槽位进度描述: 用于 SaveOverlay 卡片次行
# 空槽位 → ""; 新存档 → "新人入职"; 通关 N 关 → "已通关 X / Y"; 全通关 → "全通关"
func describe_slot_progress(index: int) -> String:
	if is_slot_empty(index):
		return ""
	var slot: Dictionary = get_slot(index)
	var max_cleared: int = int(slot.get("max_cleared_level_index", -1))
	if max_cleared < 0:
		return "新人入职"
	if max_cleared >= TOTAL_LEVEL_COUNT - 1:
		return "全通关"
	# 显示已通关到哪一关 + 下一关名
	var next_level: int = max_cleared + 1
	return "已通关 %s · 下一战: %s" % [get_level_name(max_cleared), get_level_name(next_level)]


# ---------- 槽位查询 ----------
func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	return slots[index]


func is_slot_empty(index: int) -> bool:
	var s: Dictionary = get_slot(index)
	return s.is_empty() or not bool(s.get("exists", false))


func get_active_slot() -> Dictionary:
	if active_slot_index < 0:
		return {}
	return get_slot(active_slot_index)


# ---------- 槽位生命周期 ----------
# 玩家在新槽位选定人格后调用: 写入空白进度的新槽位 + 设为 active
func create_slot(index: int, persona_id: String) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	if not PERSONAS.has(persona_id):
		persona_id = DEFAULT_PERSONA_ID
	var slot: Dictionary = _empty_slot()
	slot["exists"] = true
	slot["persona_id"] = persona_id
	slot["played_at"] = _now_string()
	slots[index] = slot
	_set_active(index, persona_id)
	_save_to_disk()


# 玩家选中已有槽位时调用: 只更新最近游玩时间 + active
func touch_slot(index: int) -> void:
	if is_slot_empty(index):
		return
	slots[index]["played_at"] = _now_string()
	_set_active(index, String(slots[index].get("persona_id", DEFAULT_PERSONA_ID)))
	_save_to_disk()


func delete_slot(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	slots[index] = _empty_slot()
	if active_slot_index == index:
		active_slot_index = -1
		active_persona_id = ""
		emit_signal("active_slot_changed", -1, "")
	_save_to_disk()


# ---------- 自动保存 API ----------
# 把当前 Game 的进度同步进 active slot 并落盘 (节流: 仅在标志变化时调用方负责判断)
func capture_from_game() -> void:
	if active_slot_index < 0:
		return
	var slot: Dictionary = slots[active_slot_index]
	var game := _get_game()
	if game == null:
		return
	for flag_name in TUTORIAL_FLAG_DEFAULTS.keys():
		slot[flag_name] = bool(game.get(flag_name))
	for var_name in GAME_DICT_FIELDS.keys():
		var d: Variant = game.get(var_name)
		slot[GAME_DICT_FIELDS[var_name]] = (d as Dictionary).duplicate(true) if d is Dictionary else {}
	slot["current_level_index"] = int(game.get("current_level_index"))
	slot["deck_effect_ids"] = _to_string_array(game.get("snapshot_deck_effect_ids"))
	slot["talent_ids"] = _to_string_array(game.get("snapshot_talent_ids"))
	slot["resume_day"] = int(game.get("snapshot_day"))
	slot["resume_phase"] = String(game.get("snapshot_phase"))
	slot["resume_cash"] = float(game.get("snapshot_cash"))
	slot["resume_shares"] = int(game.get("snapshot_shares"))
	slot["resume_avg_cost"] = float(game.get("snapshot_avg_cost"))
	slot["resume_price"] = float(game.get("snapshot_price"))
	slot["resume_bull"] = int(game.get("snapshot_bull"))
	slot["resume_turn_global"] = int(game.get("snapshot_turn_global"))
	slot["played_at"] = _now_string()
	slots[active_slot_index] = slot
	_save_to_disk()


# 节流哈希: 把所有"需要 capture 的 Game 字段"折叠成一个 hash, 供 main.gd 比较是否要写盘
# (避免每次 state_changed 都触发 capture_from_game)
func compute_capture_hash() -> int:
	var game := _get_game()
	if game == null:
		return 0
	var snap: Dictionary = {}
	for flag_name in TUTORIAL_FLAG_DEFAULTS.keys():
		snap[flag_name] = bool(game.get(flag_name))
	for var_name in GAME_DICT_FIELDS.keys():
		var d: Variant = game.get(var_name)
		snap[GAME_DICT_FIELDS[var_name]] = (d as Dictionary).duplicate(true) if d is Dictionary else {}
	snap["current_level_index"] = int(game.get("current_level_index"))
	snap["deck_effect_ids"] = _to_string_array(game.get("snapshot_deck_effect_ids"))
	snap["talent_ids"] = _to_string_array(game.get("snapshot_talent_ids"))
	snap["resume_day"] = int(game.get("snapshot_day"))
	snap["resume_phase"] = String(game.get("snapshot_phase"))
	snap["resume_cash"] = float(game.get("snapshot_cash"))
	snap["resume_shares"] = int(game.get("snapshot_shares"))
	snap["resume_avg_cost"] = float(game.get("snapshot_avg_cost"))
	snap["resume_price"] = float(game.get("snapshot_price"))
	snap["resume_bull"] = int(game.get("snapshot_bull"))
	snap["resume_turn_global"] = int(game.get("snapshot_turn_global"))
	return snap.hash()


# 关卡通关后调用: 推进 max_cleared_level_index 并落盘
func record_level_cleared(level_index: int) -> void:
	if active_slot_index < 0:
		return
	var slot: Dictionary = slots[active_slot_index]
	var cur: int = int(slot.get("max_cleared_level_index", -1))
	if level_index > cur:
		slot["max_cleared_level_index"] = level_index
	slot["played_at"] = _now_string()
	slots[active_slot_index] = slot
	_save_to_disk()


# 把 active slot 的进度回放到 Game 上: 设置 tutorial 标志 + current_level_index + Dict 字段
# 注意: 调用方必须在 Game.new_level() 之前调用此函数 (它修改的是用于 _configure_current_level_params 之前的状态)
# start_level_override: >=0 时, 强制使用该关卡 index (用于"再玩一次"重玩选关; 不回退 max_cleared)
func apply_to_game(start_level_override: int = -1) -> void:
	var game := _get_game()
	if game == null:
		return
	if active_slot_index < 0:
		# 没选档 (cmdline 直跑等场景): 全部清零, 走默认教学流程
		for flag_name in TUTORIAL_FLAG_DEFAULTS.keys():
			game.set(flag_name, TUTORIAL_FLAG_DEFAULTS[flag_name])
		for var_name in GAME_DICT_FIELDS.keys():
			game.set(var_name, {})
		game.set("pending_restore_deck_effect_ids", [])
		game.set("pending_restore_talent_ids", [])
		game.set("pending_restore_day_target", 0)
		game.set("pending_restore_phase_target", "")
		game.current_level_index = 0
		return
	var slot: Dictionary = slots[active_slot_index]
	for flag_name in TUTORIAL_FLAG_DEFAULTS.keys():
		game.set(flag_name, bool(slot.get(flag_name, TUTORIAL_FLAG_DEFAULTS[flag_name])))
	for var_name in GAME_DICT_FIELDS.keys():
		var stored: Variant = slot.get(GAME_DICT_FIELDS[var_name], {})
		game.set(var_name, (stored as Dictionary).duplicate(true) if stored is Dictionary else {})
	# 跨关继承的牌组 + 天赋 + 当关恢复点: 写入 Game 的 pending 缓冲, new_level 末尾自动应用
	var deck_ids: Variant = slot.get("deck_effect_ids", [])
	var talent_ids: Variant = slot.get("talent_ids", [])
	game.set("pending_restore_deck_effect_ids", (deck_ids as Array).duplicate() if deck_ids is Array else [])
	game.set("pending_restore_talent_ids", (talent_ids as Array).duplicate() if talent_ids is Array else [])
	game.set("pending_restore_day_target", int(slot.get("resume_day", 0)))
	game.set("pending_restore_phase_target", String(slot.get("resume_phase", "")))
	game.set("pending_restore_cash", float(slot.get("resume_cash", 0.0)))
	game.set("pending_restore_shares", int(slot.get("resume_shares", 0)))
	game.set("pending_restore_avg_cost", float(slot.get("resume_avg_cost", 0.0)))
	game.set("pending_restore_price", float(slot.get("resume_price", 0.0)))
	game.set("pending_restore_bull", int(slot.get("resume_bull", 0)))
	game.set("pending_restore_turn_global", int(slot.get("resume_turn_global", 0)))
	# 启动关卡: override > slot.current_level_index > 默认 (max_cleared + 1)
	var start_level: int
	if start_level_override >= 0:
		start_level = clamp(start_level_override, 0, TOTAL_LEVEL_COUNT - 1)
	else:
		var saved_cur: int = int(slot.get("current_level_index", -1))
		if saved_cur >= 0:
			start_level = clamp(saved_cur, 0, TOTAL_LEVEL_COUNT - 1)
		else:
			var max_cleared: int = int(slot.get("max_cleared_level_index", -1))
			start_level = clamp(max_cleared + 1, 0, TOTAL_LEVEL_COUNT - 1)
	game.current_level_index = start_level


# ---------- 内部 ----------
func _set_active(index: int, persona_id: String) -> void:
	active_slot_index = index
	active_persona_id = persona_id
	emit_signal("active_slot_changed", index, persona_id)


func _init_empty_slots() -> void:
	slots.clear()
	for _i in range(SLOT_COUNT):
		slots.append(_empty_slot())


func _empty_slot() -> Dictionary:
	var slot: Dictionary = {
		"exists": false,
		"persona_id": "",
		"played_at": "",
		"max_cleared_level_index": -1,
		"current_level_index": -1,
		"deck_effect_ids": [],
		"talent_ids": [],
		"resume_day": 0,
		"resume_phase": "",
		"resume_cash": 0.0,
		"resume_shares": 0,
		"resume_avg_cost": 0.0,
		"resume_price": 0.0,
		"resume_bull": 0,
		"resume_turn_global": 0,
	}
	for flag_name in TUTORIAL_FLAG_DEFAULTS.keys():
		slot[flag_name] = TUTORIAL_FLAG_DEFAULTS[flag_name]
	for var_name in GAME_DICT_FIELDS.keys():
		slot[GAME_DICT_FIELDS[var_name]] = {}
	return slot


func _load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	# 旧档 (v1) 没有 [meta] 段, 默认按 v1 处理; 缺失字段一律按 _empty_slot 默认
	var file_version: int = int(cfg.get_value(META_SECTION, "version", 1))
	for i in range(SLOT_COUNT):
		var sec := "slot_%d" % i
		if not cfg.has_section(sec):
			continue
		var persona_id: String = String(cfg.get_value(sec, "persona_id", ""))
		if persona_id == "" or not PERSONAS.has(persona_id):
			continue
		var slot: Dictionary = _empty_slot()
		slot["exists"] = true
		slot["persona_id"] = persona_id
		slot["played_at"] = String(cfg.get_value(sec, "played_at", ""))
		slot["max_cleared_level_index"] = int(cfg.get_value(sec, "max_cleared_level_index", -1))
		slot["current_level_index"] = int(cfg.get_value(sec, "current_level_index", -1))
		var deck_v: Variant = cfg.get_value(sec, "deck_effect_ids", [])
		slot["deck_effect_ids"] = _to_string_array(deck_v)
		var talent_v: Variant = cfg.get_value(sec, "talent_ids", [])
		slot["talent_ids"] = _to_string_array(talent_v)
		slot["resume_day"] = int(cfg.get_value(sec, "resume_day", 0))
		slot["resume_phase"] = String(cfg.get_value(sec, "resume_phase", ""))
		slot["resume_cash"] = float(cfg.get_value(sec, "resume_cash", 0.0))
		slot["resume_shares"] = int(cfg.get_value(sec, "resume_shares", 0))
		slot["resume_avg_cost"] = float(cfg.get_value(sec, "resume_avg_cost", 0.0))
		slot["resume_price"] = float(cfg.get_value(sec, "resume_price", 0.0))
		slot["resume_bull"] = int(cfg.get_value(sec, "resume_bull", 0))
		slot["resume_turn_global"] = int(cfg.get_value(sec, "resume_turn_global", 0))
		for flag_name in TUTORIAL_FLAG_DEFAULTS.keys():
			slot[flag_name] = bool(cfg.get_value(sec, flag_name, TUTORIAL_FLAG_DEFAULTS[flag_name]))
		for var_name in GAME_DICT_FIELDS.keys():
			var key: String = GAME_DICT_FIELDS[var_name]
			var stored: Variant = cfg.get_value(sec, key, {})
			slot[key] = (stored as Dictionary).duplicate(true) if stored is Dictionary else {}
		_migrate_slot(slot, file_version)
		slots[i] = slot


# 版本迁移钩子: 升版本时在此为新字段填默认值 / 转换旧字段
# 当前 v1→v2 不需要额外处理 (新字段已由 _empty_slot 提供空字典默认)
func _migrate_slot(_slot: Dictionary, _from_version: int) -> void:
	pass


func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(META_SECTION, "version", SAVE_VERSION)
	for i in range(SLOT_COUNT):
		var s: Dictionary = slots[i]
		if not bool(s.get("exists", false)):
			continue
		var sec := "slot_%d" % i
		cfg.set_value(sec, "persona_id", String(s.get("persona_id", "")))
		cfg.set_value(sec, "played_at", String(s.get("played_at", "")))
		cfg.set_value(sec, "max_cleared_level_index", int(s.get("max_cleared_level_index", -1)))
		cfg.set_value(sec, "current_level_index", int(s.get("current_level_index", -1)))
		cfg.set_value(sec, "deck_effect_ids", _to_string_array(s.get("deck_effect_ids", [])))
		cfg.set_value(sec, "talent_ids", _to_string_array(s.get("talent_ids", [])))
		cfg.set_value(sec, "resume_day", int(s.get("resume_day", 0)))
		cfg.set_value(sec, "resume_phase", String(s.get("resume_phase", "")))
		cfg.set_value(sec, "resume_cash", float(s.get("resume_cash", 0.0)))
		cfg.set_value(sec, "resume_shares", int(s.get("resume_shares", 0)))
		cfg.set_value(sec, "resume_avg_cost", float(s.get("resume_avg_cost", 0.0)))
		cfg.set_value(sec, "resume_price", float(s.get("resume_price", 0.0)))
		cfg.set_value(sec, "resume_bull", int(s.get("resume_bull", 0)))
		cfg.set_value(sec, "resume_turn_global", int(s.get("resume_turn_global", 0)))
		for flag_name in TUTORIAL_FLAG_DEFAULTS.keys():
			cfg.set_value(sec, flag_name, bool(s.get(flag_name, TUTORIAL_FLAG_DEFAULTS[flag_name])))
		for var_name in GAME_DICT_FIELDS.keys():
			var key: String = GAME_DICT_FIELDS[var_name]
			cfg.set_value(sec, key, s.get(key, {}))
	cfg.save(SAVE_PATH)


func _get_game() -> Node:
	return get_node_or_null("/root/Game")


func _now_string() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute]


# ---- 牌组 / 天赋 helper ----
func _collect_deck_effect_ids(game: Node) -> Array:
	var ids: Array = []
	if game == null:
		return ids
	if not game.has_method("get_full_deck"):
		return ids
	var full: Array = game.get_full_deck()
	for c in full:
		if c == null:
			continue
		if "transient" in c and bool(c.transient):
			continue
		var eid: String = String(c.get("effect_id"))
		if eid != "":
			ids.append(eid)
	return ids


func _collect_talent_ids(game: Node) -> Array:
	var ids: Array = []
	if game == null:
		return ids
	var talents: Variant = game.get("owned_talents")
	if not (talents is Array):
		return ids
	for t in talents:
		if t == null:
			continue
		var tid: String = String(t.get("id"))
		if tid != "":
			ids.append(tid)
	return ids


func _to_string_array(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for item in v:
			out.append(String(item))
	return out