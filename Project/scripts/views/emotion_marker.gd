# EmotionMarker — 市场情绪条游标
# 在 Control 内用 _draw 画 1px 白竖线 + 顶部小三角, 不依赖额外子节点.
# 由 top_bar.gd 在 emotion_bar_slot 内挂一个实例, 调 set_anchor(x, h) 更新位置.
extends Control

const LINE_COLOR: Color = Color.WHITE
const LINE_WIDTH: float = 1.0
const ARROW_HALF: float = 4.0
const ARROW_HEIGHT: float = 5.0

var _bar_h: float = 14.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# 把游标定位到 (anchor_x, top_y), 并指定 bar 高度
# top_y: bar 内底顶部 y; bar_h: bar 高度. marker 的 0,0 = bar 顶部
func update_marker(anchor_x: float, top_y: float, bar_h: float) -> void:
	_bar_h = bar_h
	# 控件区域: 从三角顶部 (top_y - ARROW_HEIGHT) 到 bar 底部
	position = Vector2(anchor_x - ARROW_HALF, top_y - ARROW_HEIGHT)
	size = Vector2(ARROW_HALF * 2.0, ARROW_HEIGHT + bar_h)
	queue_redraw()


func _draw() -> void:
	# 顶部小三角 (尖端朝下)
	var tri := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(ARROW_HALF * 2.0, 0.0),
		Vector2(ARROW_HALF, ARROW_HEIGHT)
	])
	draw_colored_polygon(tri, LINE_COLOR)
	# 竖线 (从三角下沿到 bar 底)
	var cx: float = ARROW_HALF
	draw_line(
		Vector2(cx, ARROW_HEIGHT),
		Vector2(cx, ARROW_HEIGHT + _bar_h),
		LINE_COLOR, LINE_WIDTH
	)
