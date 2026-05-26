# 虚线刻度横线绘制控件 (PlayerTargetBar / EnemyHpBar 共用)
# 用 _draw 在容器内的指定 y 比例位置画水平虚线, 比拼 ColorRect 更省节点.
extends Control

const DASH_LEN: float = 4.0
const GAP_LEN: float = 4.0

var line_color: Color = Color(1, 1, 1, 0.3)
var line_thickness: float = 1.0
# 刻度比例数组 (0.0=底, 1.0=顶)
var tick_ratios: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var period: float = DASH_LEN + GAP_LEN
	for r in tick_ratios:
		var y: float = (1.0 - clamp(r, 0.0, 1.0)) * h
		var x: float = 0.0
		while x < w:
			var x_end: float = min(x + DASH_LEN, w)
			draw_line(Vector2(x, y), Vector2(x_end, y), line_color, line_thickness)
			x += period


func set_ticks(ratios: Array, color: Color = Color(1, 1, 1, 0.35), thickness: float = 1.0) -> void:
	tick_ratios.clear()
	for r in ratios:
		tick_ratios.append(float(r))
	line_color = color
	line_thickness = thickness
	queue_redraw()
