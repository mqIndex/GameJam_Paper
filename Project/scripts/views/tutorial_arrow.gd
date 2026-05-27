extends Control

@export var fill_color: Color = Color(0.04, 0.07, 0.13, 0.86):
	set(value):
		fill_color = value
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
