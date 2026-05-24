extends Button

const UF = preload("res://scripts/views/ui_factory.gd")

@export var pile_kind: String = "draw" : set = _set_pile_kind

@onready var lbl_name: Label = $HBox/LblName
@onready var lbl_count: Label = $HBox/LblCount

var _count: int = 0


func _ready() -> void:
	_apply_style()
	_refresh_labels()


func set_count(n: int) -> void:
	_count = n
	if lbl_count != null:
		lbl_count.text = "%d" % n


func _set_pile_kind(value: String) -> void:
	pile_kind = value
	if is_inside_tree():
		_apply_style()
		_refresh_labels()


func _apply_style() -> void:
	var col: Color = UF.COL_GOLD if pile_kind == "draw" else UF.COL_DOWN
	var sb := UF.panel_stylebox(col)
	add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(col.r, col.g, col.b, 0.18)
	add_theme_stylebox_override("hover", hover)
	add_theme_color_override("font_color", col)
	if lbl_name != null:
		lbl_name.add_theme_color_override("font_color", col)
	if lbl_count != null:
		lbl_count.add_theme_color_override("font_color", col)


func _refresh_labels() -> void:
	if lbl_name == null:
		return
	lbl_name.text = "抽牌堆" if pile_kind == "draw" else "弃牌堆"
	lbl_count.text = "%d" % _count
