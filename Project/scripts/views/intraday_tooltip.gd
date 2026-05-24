extends PanelContainer

@onready var lbl_card: Label = $VBox/LblCard
@onready var lbl_price: Label = $VBox/LblPrice
@onready var lbl_detail: Label = $VBox/LblEmotion


func show_at(candle: Dictionary, anchor_pos: Vector2) -> void:
	lbl_card.text = String(candle.get("card_name", "?"))
	var price_pct: float = float(candle.get("price_delta_pct", 0.0))
	lbl_price.text = "股价 %+.2f%%" % price_pct
	if price_pct > 0.0:
		lbl_price.add_theme_color_override("font_color", Color(0.024, 0.839, 0.627, 1))
	elif price_pct < 0.0:
		lbl_price.add_theme_color_override("font_color", Color(0.937, 0.278, 0.435, 1))
	else:
		lbl_price.add_theme_color_override("font_color", Color.WHITE)
	var parts: Array = []
	if candle.has("ohlc"):
		parts.append(String(candle["ohlc"]))
	elif candle.has("emotion_delta"):
		var emo: int = int(candle["emotion_delta"])
		parts.append("情绪 %+d" % emo)
	if candle.has("source"):
		parts.append(String(candle["source"]))
	if candle.has("cards_played") and String(candle["cards_played"]) != "":
		parts.append(String(candle["cards_played"]))
	lbl_detail.text = "\n".join(parts)
	lbl_detail.add_theme_color_override("font_color", Color(0.604, 0.655, 0.753, 1))
	position = anchor_pos
	visible = true


func hide_tooltip() -> void:
	visible = false
