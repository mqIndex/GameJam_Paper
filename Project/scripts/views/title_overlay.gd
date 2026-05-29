# 启动封面 (main.gd 实例化, 在 SaveOverlay 之前)
# 整张封面图占满, 屏幕任意位置点击 → emit start_pressed → main.gd 关掉本 overlay 弹 SaveOverlay
# 底部一行呼吸闪烁的提示文字: 点击屏幕开始游戏
extends Control

const UF = preload("res://scripts/views/ui_factory.gd")

signal start_pressed

const COVER_PATH := "res://assets/startPage.png"
const FALLBACK_COVER_PATH := "res://assets/loadingPage.png"
const HINT_TEXT := "点击屏幕开始游戏"
const HINT_BOTTOM_PAD := 56.0
const HINT_FONT_SIZE := 22

var _bg: TextureRect = null
var _hint: Label = null
var _hint_tween: Tween = null


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 400
	_build_bg()
	_build_hint()
	resized.connect(_layout)
	_layout()
	_start_hint_blink()


func _build_bg() -> void:
	_bg = TextureRect.new()
	_bg.name = "Cover"
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = MOUSE_FILTER_IGNORE
	var tex: Texture2D = null
	if ResourceLoader.exists(COVER_PATH):
		tex = load(COVER_PATH) as Texture2D
	if tex == null and ResourceLoader.exists(FALLBACK_COVER_PATH):
		tex = load(FALLBACK_COVER_PATH) as Texture2D
	if tex != null:
		_bg.texture = tex
	add_child(_bg)


func _build_hint() -> void:
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = HINT_TEXT
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.mouse_filter = MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint.add_theme_color_override("font_color", UF.COL_TEXT)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	add_child(_hint)


func _layout() -> void:
	var sz: Vector2 = size
	if _bg != null:
		_bg.position = Vector2.ZERO
		_bg.size = sz
	if _hint != null:
		var hint_w: float = max(360.0, sz.x * 0.6)
		var hint_h: float = float(HINT_FONT_SIZE) + 14.0
		_hint.size = Vector2(hint_w, hint_h)
		_hint.position = Vector2((sz.x - hint_w) * 0.5, sz.y - hint_h - HINT_BOTTOM_PAD)


func _start_hint_blink() -> void:
	if _hint == null:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(_hint, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_emit_start()
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_emit_start()
			accept_event()


func _emit_start() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	emit_signal("start_pressed")