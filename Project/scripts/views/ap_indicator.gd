# 行动力点指示器: 用一排 ColorRect 圆点替代字符 ●○, 方便后续替换为 PNG.
# 由 action_bar.gd 在运行时挂载, 不影响 .tscn 结构.
extends HBoxContainer

const UF = preload("res://scripts/views/ui_factory.gd")

const DOT_SIZE: float = 10.0
const DOT_GAP: int = 4

var _dots: Array[ColorRect] = []
var _max_ap: int = 3


func _ready() -> void:
	add_theme_constant_override("separation", DOT_GAP)


func set_max(max_ap: int) -> void:
	if max_ap == _max_ap and _dots.size() == max_ap:
		return
	_max_ap = max_ap
	for d in _dots:
		d.queue_free()
	_dots.clear()
	for i in range(max_ap):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.color = UF.COL_AP_OFF
		add_child(dot)
		_dots.append(dot)


func set_active(n: int) -> void:
	for i in range(_dots.size()):
		_dots[i].color = UF.COL_AP_ON if i < n else UF.COL_AP_OFF
