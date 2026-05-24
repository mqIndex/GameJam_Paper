extends Control

var fill_color: Color = Color(0, 0, 0, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var points := PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		Vector2(size.x * 0.5, size.y),
	])
	draw_colored_polygon(points, fill_color)
