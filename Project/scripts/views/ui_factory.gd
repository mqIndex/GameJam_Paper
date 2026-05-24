# 共享 UI 构造工具 + 配色常量
# 把原 main.gd 里的 _label / _button / _make_panel / _panel_stylebox /
# _sep_v / _h_sep / _fmt_money 提取到这里, 让多个 view 复用.
extends RefCounted

# ===== 配色 =====
const COL_BG: Color = Color("#0d1b2a")
const COL_PANEL: Color = Color("#1b2a41")
const COL_PANEL_LIGHT: Color = Color("#26395a")
const COL_BORDER: Color = Color("#3a4a6a")
const COL_TEXT: Color = Color("#ffffff")
const COL_TEXT_DIM: Color = Color("#9aa7c0")
const COL_GOLD: Color = Color("#ffd166")
const COL_UP: Color = Color("#06d6a0")
const COL_DOWN: Color = Color("#ef476f")
const COL_BLUE: Color = Color("#118ab2")
const COL_GREEN: Color = Color("#06d6a0")
const COL_YELLOW: Color = Color("#ffd166")
const COL_RED: Color = Color("#ef476f")
const COL_HIGHLIGHT: Color = Color("#ffae42")
const COL_AP_ON: Color = Color("#5cd5ff")
const COL_AP_OFF: Color = Color("#33425c")
const COL_BULL: Color = Color("#06d6a0")
const COL_BEAR: Color = Color("#ef476f")


static func panel_stylebox(border: Color = COL_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


static func label(text: String, font_size: int = 14, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, color: Color = COL_TEXT, font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", color)
	var n := StyleBoxFlat.new()
	n.bg_color = COL_PANEL
	n.border_color = color
	n.border_width_left = 2
	n.border_width_right = 2
	n.border_width_top = 2
	n.border_width_bottom = 2
	n.corner_radius_top_left = 4
	n.corner_radius_top_right = 4
	n.corner_radius_bottom_left = 4
	n.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(color.r, color.g, color.b, 0.18)
	b.add_theme_stylebox_override("hover", h)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(color.r, color.g, color.b, 0.32)
	b.add_theme_stylebox_override("pressed", p)
	var d := n.duplicate() as StyleBoxFlat
	d.border_color = COL_AP_OFF
	b.add_theme_stylebox_override("disabled", d)
	return b


static func sep_v() -> Label:
	return label("|", 16, COL_TEXT_DIM)


static func h_sep() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BORDER
	s.add_theme_stylebox_override("separator", sb)
	s.custom_minimum_size = Vector2(0, 2)
	return s


static func fmt_money(v: float) -> String:
	var n: int = int(round(v))
	var neg: bool = n < 0
	var s: String = str(abs(n))
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count == 3 and i > 0:
			out = "," + out
			count = 0
	if neg: out = "-" + out
	return out


static func kind_color(kind: int) -> Color:
	match kind:
		0: return COL_UP        # BUY
		1: return COL_DOWN      # SELL
		2: return COL_HIGHLIGHT # SKILL
		3: return COL_GOLD      # EVENT
	return COL_TEXT


static func ap_dots(n: int, max_ap: int) -> String:
	var out := ""
	for i in range(max_ap):
		out += "●" if i < n else "○"
		if i < max_ap - 1:
			out += " "
	return out


static func weekday_name(d: int) -> String:
	match d:
		1: return "(周一)"
		2: return "(周二)"
		3: return "(周三)"
		4: return "(周四)"
		5: return "(周五)"
	return ""
