extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@export var avatar_size: Vector2 = Vector2(64, 64) : set = _set_avatar_size
@export var avatar_color: Color = Color("#26395a") : set = _set_avatar_color

@onready var avatar_rect: ColorRect = $AvatarRect


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	custom_minimum_size = avatar_size
	if avatar_rect != null:
		avatar_rect.color = avatar_color


func _set_avatar_size(value: Vector2) -> void:
	avatar_size = value
	custom_minimum_size = value
	if is_inside_tree():
		size = value


func _set_avatar_color(value: Color) -> void:
	avatar_color = value
	if avatar_rect != null:
		avatar_rect.color = value
