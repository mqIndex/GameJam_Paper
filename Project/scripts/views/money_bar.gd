extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var seg_blue: ColorRect = $SegBlue
@onready var seg_green: ColorRect = $SegGreen
@onready var seg_yellow: ColorRect = $SegYellow
@onready var seg_red: ColorRect = $SegRed
@onready var marker: ColorRect = $Marker

const BAR_TOP_PAD: float = 20.0
const BAR_BOTTOM_PAD: float = 8.0
const BAR_X: float = 14.0
const MARKER_X: float = 10.0

var _bar_top_y: float = BAR_TOP_PAD
var _bar_height: float = 432.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	resized.connect(_layout_bar)
	Game.state_changed.connect(_refresh)
	_layout_bar()


func _refresh() -> void:
	if marker == null:
		return
	var ratio: float = clamp(Game.cash / (Game.START_CASH * 2.0), 0.0, 1.0)
	marker.position.y = _bar_top_y + (1.0 - ratio) * _bar_height - 1.0


func _layout_bar() -> void:
	var segments: Array[ColorRect] = [seg_blue, seg_green, seg_yellow, seg_red]
	_bar_top_y = BAR_TOP_PAD
	_bar_height = max(48.0, size.y - BAR_TOP_PAD - BAR_BOTTOM_PAD)
	var seg_h: float = _bar_height / float(segments.size())
	var bar_w: float = max(8.0, size.x - BAR_X * 2.0)
	for i in range(segments.size()):
		var segment := segments[i]
		if segment == null:
			continue
		segment.position = Vector2(BAR_X, _bar_top_y + seg_h * float(i))
		segment.size = Vector2(bar_w, seg_h)
	if marker != null:
		marker.position.x = MARKER_X
		marker.size = Vector2(max(8.0, size.x - MARKER_X * 2.0), 2.0)
	_refresh()
