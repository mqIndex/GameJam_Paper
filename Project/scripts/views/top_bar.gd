extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")

@onready var lbl_day: Label = $HBox/LblDay
@onready var lbl_turn: Label = $HBox/LblTurn
@onready var lbl_price: Label = $HBox/LblPrice
@onready var lbl_bull: Label = $HBox/LblBull
@onready var lbl_bear: Label = $HBox/LblBear
@onready var lbl_emotion_state: Label = $HBox/LblEmotionState


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	Game.state_changed.connect(_refresh)


func _refresh() -> void:
	lbl_day.text = "第 %d / %d 天 %s" % [max(Game.day, 1), Game.DAYS_PER_LEVEL, UF.weekday_name(Game.day)]
	lbl_turn.text = "第 %d / %d 回合" % [max(Game.turn_in_day, 1), Game.TURNS_PER_DAY]
	lbl_price.text = "¥%.2f" % Game.price
	lbl_bull.text = "上涨 %d" % Game.bull
	lbl_bear.text = "%d 下跌" % Game.bear
	lbl_emotion_state.text = "· " + Game.emotion_state()
