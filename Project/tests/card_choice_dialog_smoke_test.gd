extends Node

const ConfigLoaderScript = preload("res://scripts/config/config_loader.gd")
const CardDatabase = preload("res://scripts/card_database.gd")
const EventDatabase = preload("res://scripts/event_database.gd")
const CardChoiceDialog = preload("res://scripts/views/card_choice_dialog.gd")

var _failed: bool = false
var _log_file: FileAccess = null


func _ready() -> void:
	_open_log()
	_say("==== card_choice_dialog_smoke_test ====")
	var cfg: Variant = get_tree().root.get_node_or_null("Cfg")
	if cfg == null:
		cfg = ConfigLoaderScript.new()
		cfg.name = "Cfg"
		get_tree().root.call_deferred("add_child", cfg)
		await get_tree().process_frame
		cfg.call("_load_balance")
		cfg.call("_load_cards")

	var dialog := CardChoiceDialog.new()
	call_deferred("add_child", dialog)
	await get_tree().process_frame

	var cards: Array = [
		CardDatabase.make_by_effect("buy_basic", "choice_buy"),
		CardDatabase.make_by_effect("sell_basic", "choice_sell"),
		CardDatabase.make_by_effect("plan_well", "choice_plan"),
	]

	dialog.show_card_single("顺势而为", "选择 1 张要弃掉的手牌。", cards, func(_picked): pass)
	if not _assert_card_grid(dialog, cards, "single"):
		return

	dialog.show_card_single("计划得当", "从抽牌堆选 1 张放到牌堆顶。", cards, func(_picked): pass)
	if not _assert_card_grid(dialog, cards, "topdeck"):
		return

	dialog.show_card_multi("化整为零", "选择要碎掉的 BUY/SELL 牌。", cards, func(_picked): pass)
	if not _assert_card_grid(dialog, cards, "multi"):
		return

	var events: Array = [
		EventDatabase.make_by_id("rate_cut"),
		EventDatabase.make_by_id("black_swan"),
		EventDatabase.make_by_id("chaos_day"),
	]
	dialog.show_event_single("内幕消息", "选择一个事件作为下一次突发事件。", events, func(_picked): pass)
	if not _assert_event_grid(dialog, events, "event"):
		return

	_say("PASS")
	get_tree().quit(0)


func _assert_card_grid(dialog: Control, cards: Array, label: String) -> bool:
	var grid := dialog.get("_grid") as GridContainer
	if grid == null:
		_fail("%s: grid missing" % label)
		return false
	if grid.get_child_count() != cards.size():
		_fail("%s: expected %d card buttons, got %d" % [label, cards.size(), grid.get_child_count()])
		return false
	for i in range(cards.size()):
		var child := grid.get_child(i)
		if not child.has_method("set_choice_selected"):
			_fail("%s: child %d is not CardButton visual" % [label, i])
			return false
		var name_label := child.get_node_or_null("VBox/LblName") as Label
		if name_label == null:
			_fail("%s: child %d name label missing" % [label, i])
			return false
		if name_label.text != cards[i].name:
			_fail("%s: child %d name mismatch, expected %s got %s" % [label, i, cards[i].name, name_label.text])
			return false
	return true


func _assert_event_grid(dialog: Control, events: Array, label: String) -> bool:
	var grid := dialog.get("_grid") as GridContainer
	if grid == null:
		_fail("%s: grid missing" % label)
		return false
	if grid.get_child_count() != events.size():
		_fail("%s: expected %d event buttons, got %d" % [label, events.size(), grid.get_child_count()])
		return false
	for i in range(events.size()):
		var child := grid.get_child(i) as Button
		if child == null:
			_fail("%s: child %d is not Button" % [label, i])
			return false
		var image := child.get_node_or_null("EventMargin/EventRoot/EventImage") as TextureRect
		if image == null or image.texture == null:
			_fail("%s: child %d event image missing" % [label, i])
			return false
		var name_label := child.get_node_or_null("EventMargin/EventRoot/LblEventName") as Label
		if name_label == null or name_label.text != events[i].name:
			_fail("%s: child %d event name mismatch" % [label, i])
			return false
	return true


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	_say("FAIL: " + message)
	get_tree().quit(1)


func _open_log() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	_log_file = FileAccess.open("res://logs/card_choice_dialog_smoke.log", FileAccess.WRITE)


func _say(message: String) -> void:
	print(message)
	if _log_file != null:
		_log_file.store_line(message)
		_log_file.flush()
