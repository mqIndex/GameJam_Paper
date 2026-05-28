# 共享 UI 构造工具 + 配色常量
# 把原 main.gd 里的 _label / _button / _make_panel / _panel_stylebox /
# _sep_v / _h_sep / _fmt_money 提取到这里, 让多个 view 复用.
extends RefCounted

# ===== 配色 (霓虹像素终端) =====
const COL_BG: Color = Color("#0a0e14")
const COL_PANEL: Color = Color("#11151c")
const COL_PANEL_LIGHT: Color = Color("#1b2230")
const COL_BORDER: Color = Color("#3a3550")
const COL_TEXT: Color = Color("#f5f5f5")
const COL_TEXT_DIM: Color = Color("#8a93a8")
const COL_GOLD: Color = Color("#ffc857")
const COL_UP: Color = Color("#ff5d6c")
const COL_DOWN: Color = Color("#3ddc97")
const COL_BLUE: Color = Color("#118ab2")
const COL_GREEN: Color = Color("#3ddc97")
const COL_YELLOW: Color = Color("#ffc857")
const COL_RED: Color = Color("#ff5d6c")
const COL_HIGHLIGHT: Color = Color("#ff8c42")
const COL_AP_ON: Color = Color("#ff8c42")
const COL_AP_OFF: Color = Color("#2c2438")
const COL_BULL: Color = Color("#3ddc97")
const COL_BEAR: Color = Color("#ff5d6c")
# 新增霓虹强调色
const COL_NEON_ORANGE: Color = Color("#ff8c42")
const COL_NEON_RED: Color = Color("#ff5d6c")
const COL_NEON_CYAN: Color = Color("#5cd5ff")
const COL_NEON_PURPLE: Color = Color("#b56cff")
const COL_BG_DEEP: Color = Color("#06080d")

# ===== 字号策略 (1280x720) =====
# 等级 / 用途 / 字号
# HERO (主标题/价格)  24
# H1   (区块标题/对手名)  16
# H2   (常规数值/按钮)    15
# BODY (说明/小数据)      13
# CAPTION (辅助灰字)      11
const FS_HERO: int = 24
const FS_H1: int = 16
const FS_H2: int = 15
const FS_BODY: int = 13
const FS_CAPTION: int = 11

# ===== 美术贴图资源 (RGB 不透明背景版, 缺失时自动 fallback 到 StyleBoxFlat) =====
# 路径常量集中, 便于美术更新替换. 加载失败会返回 null, 由调用方做 fallback.
const PATH_PANEL_DEFAULT: String = "res://assets/ui/panels/panel_neon_default.png"
const PATH_OPPONENT_FUND: String = "res://assets/ui/panels/opponent_fund_bar_frame.png"
const PATH_PLAYER_FUND: String = "res://assets/ui/panels/player_fund_bar_frame.png"
const PATH_BTN_END_TURN: String = "res://assets/ui/buttons/btn_end_turn.png"
const PATH_CARD_BUY: String = "res://assets/ui/cards/card_frame_buy.png"
const PATH_CARD_SELL: String = "res://assets/ui/cards/card_frame_sell.png"
const PATH_CARD_SKILL: String = "res://assets/ui/cards/card_frame_skill.png"
const PATH_CARD_EVENT: String = "res://assets/ui/cards/card_frame_event.png"
const PATH_CARD_DISABLED: String = "res://assets/ui/cards/card_overlay_disabled.png"
const PATH_BG_MAIN: String = "res://assets/ui/bg/bg_main.png"
# 资金条外边框 (敌/玩家)
const PATH_BORDER_ENEMY_FUND: String = "res://assets/ui/border/enemy_fund.png"
const PATH_BORDER_PLAYER_FUND: String = "res://assets/ui/border/player_fund.png"
# 资金条标题/数额下方的小图标
const PATH_ICON_ENEMY_FUND: String = "res://assets/ui/icons/enemy_fund_Icon.png"
const PATH_ICON_PLAYER_FUND: String = "res://assets/ui/icons/player_fund_Icon.png"

# 九宫格 patch_margin (面板 1024×1024, 边框约 64px = 6.25%)
const PANEL_PATCH_MARGIN: int = 64
const BTN_PATCH_MARGIN: int = 96
# 资金条框九宫格 (1024×1536 竖长, 边框较厚)
const FUND_PATCH_TOP: int = 128
const FUND_PATCH_BOTTOM: int = 128
const FUND_PATCH_SIDE: int = 64

# 卡牌图标
const PATH_CARDS_DIR: String = "res://data/Cards/"
const CARDS_VISUAL_CSV: String = "res://data/Cards/Cards_Visual.csv"
const CARDS_VISUAL_TXT: String = "res://data/Cards/Cards_Visual.txt"

# CSV 缓存: 卡牌名 → 图片文件名 (去后缀的 basename); 懒加载, 仅尝试一次
static var _card_visual_cache: Dictionary = {}
static var _card_visual_loaded: bool = false


static func try_load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if tex is Texture2D:
		return tex as Texture2D
	return null


# 资金条外边框: StyleBoxTexture 九宫格; 纹理缺失时返回 null, 调用方走 fallback
static func fund_bar_border_stylebox(texture_path: String, patch: int = 32) -> StyleBox:
	var tex := try_load_texture(texture_path)
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = patch
	sb.texture_margin_top = patch
	sb.texture_margin_right = patch
	sb.texture_margin_bottom = patch
	# 不挤压内部内容: content_margin 走 view 自身的 BAR_TOP_PAD/BAR_X 计算
	sb.content_margin_left = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_bottom = 0.0
	return sb


# ===== 卡牌 Icon 路径解析 =====
# 数据驱动: 不在逻辑代码里按卡牌名写死映射, 全部从 Cards_Visual.csv 查询.
# 优先级:
#   1) explicit_path (例如 card.image_path, 若 cards.csv 后续填写)
#   2) Cards_Visual.csv 中 "卡牌" 列 == card_name 行的 "资源1" (逗号分隔取第一个)
#      若升级牌名未配置 (如 大V吹票+), 自动回退到去掉末尾 "+" 的基础牌名
#   3) fallback 同名: res://data/Cards/{card_name}.png
# 最终找不到返回空字符串 "" (调用方应隐藏 Icon)
static func card_icon_path_for(card_name: String, explicit_path: String = "") -> String:
	if explicit_path != "" and ResourceLoader.exists(explicit_path):
		return explicit_path
	if not _card_visual_loaded:
		_load_card_visual_csv()
	var entry: Dictionary = _visual_entry_for_card(card_name)
	var filename: String = String(entry.get("image", ""))
	if filename != "":
		var path: String = PATH_CARDS_DIR + filename
		if ResourceLoader.exists(path):
			return path
	# fallback 同名
	if card_name != "":
		var same: String = PATH_CARDS_DIR + card_name + ".png"
		if ResourceLoader.exists(same):
			return same
		var base_name := _base_card_name(card_name)
		if base_name != card_name:
			var base_same: String = PATH_CARDS_DIR + base_name + ".png"
			if ResourceLoader.exists(base_same):
				return base_same
	return ""


# 卡牌边框色: 来源 Cards_Visual.csv "颜色" 列, 格式 "中文色名+#RRGGBB hex" 如 "红色a54f4e"
# 提取末尾 6 位十六进制; 解析失败返回 Color(0,0,0,0) (调用方应 fallback 到 kind_color)
static func card_color_for(card_name: String) -> Color:
	if not _card_visual_loaded:
		_load_card_visual_csv()
	var entry: Dictionary = _visual_entry_for_card(card_name)
	var raw: String = String(entry.get("color", "")).strip_edges()
	if raw == "":
		return Color(0, 0, 0, 0)
	# 优先 #RRGGBB 完整 hex
	if raw.begins_with("#"):
		return Color.html(raw)
	# 末尾 6 字符若为十六进制视为 hex
	if raw.length() >= 6:
		var tail: String = raw.substr(raw.length() - 6, 6).to_lower()
		if _is_hex6(tail):
			return Color.html("#" + tail)
	# 中文色名兜底 (Events theme_color 风格)
	match raw:
		"红", "红色": return Color("#ff5a4f")
		"橙", "橙色": return Color("#ff9f2e")
		"黄", "黄色", "金", "金色": return Color("#ffd166")
		"绿", "绿色": return Color("#30d158")
		"青", "青色": return Color("#38d9ff")
		"蓝", "蓝色": return Color("#4aa3ff")
		"紫", "紫色": return Color("#b06cff")
		"灰", "灰色": return Color("#9aa4b2")
	return Color(0, 0, 0, 0)


static func _visual_entry_for_card(card_name: String) -> Dictionary:
	var entry: Dictionary = _card_visual_cache.get(card_name, {})
	if not entry.is_empty():
		return entry
	var base_name := _base_card_name(card_name)
	if base_name != card_name:
		return _card_visual_cache.get(base_name, {})
	return {}


static func _base_card_name(card_name: String) -> String:
	var name := card_name.strip_edges()
	if name.ends_with("+"):
		return name.substr(0, name.length() - 1).strip_edges()
	return name


static func _is_hex6(s: String) -> bool:
	if s.length() != 6:
		return false
	for i in range(6):
		var c: String = s.substr(i, 1)
		if not ("0123456789abcdef".find(c) >= 0):
			return false
	return true


static func _load_card_visual_csv() -> void:
	_card_visual_loaded = true
	var f := _open_text_data_file(CARDS_VISUAL_CSV, CARDS_VISUAL_TXT)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	# 剥 UTF-8 BOM
	if text.length() >= 1 and text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	var lines: PackedStringArray = text.split("\n")
	var first: bool = true
	for raw_line in lines:
		var line: String = String(raw_line).strip_edges()
		if line == "":
			continue
		if first:
			first = false  # 跳过表头
			continue
		var cols: Array = _parse_csv_line_simple(line)
		if cols.size() < 4:
			continue
		var card_name: String = String(cols[0]).strip_edges()
		var resource_field: String = String(cols[2]).strip_edges()
		var color_field: String = String(cols[3]).strip_edges()
		var first_file: String = _pick_first_csv_value(resource_field)
		if card_name != "":
			_card_visual_cache[card_name] = {
				"image": first_file,
				"color": color_field,
			}


static func _open_text_data_file(primary_path: String, fallback_path: String) -> FileAccess:
	for path in [primary_path, fallback_path]:
		if path == "":
			continue
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			return f
	return null


# 解析单行 CSV: 支持双引号包裹字段 (含字段内逗号) 与转义 ""
static func _parse_csv_line_simple(line: String) -> Array:
	var out: Array = []
	var cur: String = ""
	var in_quote: bool = false
	var i: int = 0
	while i < line.length():
		var ch: String = line.substr(i, 1)
		if in_quote:
			if ch == "\"":
				if i + 1 < line.length() and line.substr(i + 1, 1) == "\"":
					cur += "\""
					i += 2
					continue
				in_quote = false
				i += 1
				continue
			cur += ch
			i += 1
		else:
			if ch == ",":
				out.append(cur)
				cur = ""
				i += 1
			elif ch == "\"":
				in_quote = true
				i += 1
			else:
				cur += ch
				i += 1
	out.append(cur)
	return out


# 取逗号分隔字段中的第一个非空值 (如 "a.png,b.png" → "a.png")
static func _pick_first_csv_value(field: String) -> String:
	var parts: PackedStringArray = field.split(",")
	for p in parts:
		var s: String = String(p).strip_edges()
		if s != "":
			return s
	return ""


# 通用九宫格面板 StyleBoxTexture; 若纹理缺失, fallback 到 StyleBoxFlat
static func texture_panel_stylebox(fallback_border: Color = COL_BORDER, patch: int = PANEL_PATCH_MARGIN) -> StyleBox:
	var tex := try_load_texture(PATH_PANEL_DEFAULT)
	if tex == null:
		return panel_stylebox(fallback_border)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = patch
	sb.texture_margin_top = patch
	sb.texture_margin_right = patch
	sb.texture_margin_bottom = patch
	# 修整外边距, 让内容不要贴边
	sb.content_margin_left = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_bottom = 8.0
	return sb


# 霓虹按钮 (结束回合): StyleBoxTexture; 若纹理缺失 fallback
static func texture_button_stylebox(path: String, fallback_color: Color = COL_NEON_ORANGE, patch: int = BTN_PATCH_MARGIN) -> StyleBox:
	var tex := try_load_texture(path)
	if tex == null:
		return neon_button_stylebox(fallback_color)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = patch
	sb.texture_margin_top = patch
	sb.texture_margin_right = patch
	sb.texture_margin_bottom = patch
	sb.content_margin_left = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 6.0
	return sb


# 卡牌框 StyleBoxTexture; 不开九宫格 (卡牌为整图贴), 若缺失 fallback 到彩色描边
static func texture_card_stylebox(kind: int) -> StyleBox:
	var path: String = PATH_CARD_BUY
	match kind:
		0: path = PATH_CARD_BUY
		1: path = PATH_CARD_SELL
		2: path = PATH_CARD_SKILL
		3: path = PATH_CARD_EVENT
	var tex := try_load_texture(path)
	if tex == null:
		# fallback: 调用方按原 StyleBoxFlat 自绘
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	# 卡牌底图不切九宫格 (拉伸时整体缩放); 内边距给 VBox 留位
	sb.content_margin_left = 8.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 8.0
	sb.content_margin_bottom = 8.0
	return sb


static func panel_stylebox(border: Color = COL_BORDER) -> StyleBoxFlat:
	# 像素霓虹面板: 外深底 + 较粗描边, 圆角接近 0
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb


static func neon_panel_stylebox(border: Color = COL_NEON_ORANGE) -> StyleBoxFlat:
	# 强霓虹面板: 深黑底 + 双感描边 (用 shadow 模拟外发光)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG_DEEP
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	sb.shadow_color = Color(border.r, border.g, border.b, 0.25)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2.ZERO
	return sb


static func neon_button_stylebox(color: Color = COL_NEON_ORANGE) -> StyleBoxFlat:
	# 霓虹大按钮 (结束回合): 实心彩底 + 暗描边
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r * 0.85, color.g * 0.5, color.b * 0.25, 1.0)
	sb.border_color = color
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	sb.shadow_color = Color(color.r, color.g, color.b, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2.ZERO
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
	n.corner_radius_top_left = 2
	n.corner_radius_top_right = 2
	n.corner_radius_bottom_left = 2
	n.corner_radius_bottom_right = 2
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
