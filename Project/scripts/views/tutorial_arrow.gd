extends Control

@export var fill_color: Color = Color(0.04, 0.07, 0.13, 0.86):
	set(value):
		fill_color = value
		queue_redraw()

@export var border_color: Color = Color(1.0, 0.55, 0.26, 0.98):
	set(value):
		border_color = value
		queue_redraw()

@export var border_width: float = 2.0:
	set(value):
		border_width = value
		queue_redraw()

@export var points_down: bool = true:
	set(value):
		points_down = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var pts: PackedVector2Array
	if points_down:
		pts = PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x * 0.5, size.y),
		])
	else:
		pts = PackedVector2Array([
			Vector2(size.x * 0.5, 0.0),
			Vector2(0.0, size.y),
			Vector2(size.x, size.y),
		])
	draw_colored_polygon(pts, fill_color)
	for i in range(pts.size()):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		draw_line(a, b, border_color, border_width, true)
