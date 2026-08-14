# ═══════════════════════════════════════════════
#  CertificateUI v2 — 轮回证书（整幅美术皮 + 动态死亡卡片槽）
#  设计空间 1000×750 = 素材原位坐标，零手算。
#  流程与旧版一致：死亡 → _show_reincarnation_certificate → 点任意处/重生 关闭。
#
#  素材（放 res://assets/ui/cert/）：
#    cert_bg.png        整幅背景框（1000×750 原图直接用）
#    cert_logo_ch.png   轮回证书 标题
#    cert_logo_en.png   DEATH CERTIFICATE
#    cert_name.png      信息面板（461×266，原位 132,330）
#    btn_share.png      分享按钮（186×56，原位 236,651）
#    btn_reborn.png     重生按钮（224×53，原位 607,651）
#  复用：res://assets/ui/name_panel.png（名字牌）
#  死亡卡片：res://assets/ui/death_cards/<id>.png
#  字体：res://assets/fonts/AaFeiYanShouShu.ttf
# ═══════════════════════════════════════════════
class_name CertificateUi
extends RefCounted

var main   # Main.gd (Control) 引用

const CERT_DESIGN := Vector2(1000, 750)
const CERT_FONT_PATH := "res://assets/fonts/AaFeiYanShouShu.ttf"
const CERT_ASSETS := "res://assets/ui/cert/"
const CARDS_DIR := "res://assets/ui/death_cards/"

# 现在这套卡片自带文字；换成无字卡后改为 false，标题/稀有度改由代码按 CSV 渲染
const CARDS_HAVE_TEXT := true

const C_INK  := Color(0.28, 0.20, 0.12)
const C_SOFT := Color(0.44, 0.36, 0.25)

# 模块自持的节点引用（不占用 Main 的变量）
var cert_root: Control
var logo_rect: TextureRect
var name_label: Label
var revenant_line: Label          # 已投胎，勿念
var field_realm: Label
var field_years: Label
var field_lastwords: Label
var life_num_label: Label
var card_rect: TextureRect
var card_title: Label             # 无字卡模式下的死因标题
var card_rarity: Label
var share_label: Label
var reborn_label: Label
var cert_font: FontFile

func _cfont() -> FontFile:
	return GameConfig.body_font()

func _cbrush() -> FontFile:
	return GameConfig.brush_font()

func _mk_label(text: String, size: int, color: Color, pos: Vector2, w: float = 0.0, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f := _cfont()
	if f != null:
		l.add_theme_font_override("font", f)
	l.position = pos
	if w > 0.0:
		l.custom_minimum_size = Vector2(w, 0)
		l.size = Vector2(w, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cert_root.add_child(l)
	return l

func _tex(name: String) -> Texture2D:
	var p := CERT_ASSETS + name
	return load(p) if ResourceLoader.exists(p) else null

func _build_certificate_panel() -> void:
	main.certificate_panel = Control.new()
	main.certificate_panel.name = "CertificatePanel"
	main.certificate_panel.visible = false
	main.certificate_panel.z_index = 300
	main.certificate_panel.top_level = true
	main.add_child(main.certificate_panel)

	cert_root = Control.new()
	cert_root.custom_minimum_size = CERT_DESIGN
	cert_root.size = CERT_DESIGN
	main.certificate_panel.add_child(cert_root)

	# ① 背景整幅
	var bg := TextureRect.new()
	var bg_tex := _tex("cert_bg.png")
	if bg_tex != null:
		bg.texture = bg_tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = CERT_DESIGN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cert_root.add_child(bg)

	# ② 标题 logo（语言切换时换图）
	logo_rect = TextureRect.new()
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cert_root.add_child(logo_rect)

	# ③ 名字牌（复用主面板的 name_panel）
	var plate := TextureRect.new()
	var plate_tex: Texture2D = null
	if ResourceLoader.exists("res://assets/ui/name_panel.png"):
		plate_tex = load("res://assets/ui/name_panel.png")
	var pw := 300.0
	var ph := 80.0
	if plate_tex != null:
		plate.texture = plate_tex
		pw = plate_tex.get_width()
		ph = plate_tex.get_height()
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plate.size = Vector2(pw, ph)
	plate.position = Vector2((CERT_DESIGN.x - pw) / 2.0, 168.0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cert_root.add_child(plate)

	name_label = _mk_label("", 34, C_INK, plate.position, pw, true)
	name_label.size = Vector2(pw, ph)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _cbrush() != null:
		name_label.add_theme_font_override("font", _cbrush())

	# ④ 已投胎，勿念
	revenant_line = _mk_label("已投胎，勿念", 30, C_INK, Vector2(240, 288))
	if _cbrush() != null:
		revenant_line.add_theme_font_override("font", _cbrush())

	# ⑤ 信息面板（素材原位 132,330）+ 字段
	var info := TextureRect.new()
	var info_tex := _tex("cert_name.png")
	if info_tex != null:
		info.texture = info_tex
	info.position = Vector2(132, 330)
	info.size = Vector2(461, 266)
	info.stretch_mode = TextureRect.STRETCH_SCALE
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cert_root.add_child(info)

	field_realm     = _mk_label("", 26, C_INK, Vector2(170, 362), 390)
	field_years     = _mk_label("", 26, C_INK, Vector2(170, 418), 390)
	field_lastwords = _mk_label("", 24, C_INK, Vector2(170, 474), 390)
	life_num_label  = _mk_label("", 18, C_SOFT, Vector2(170, 556), 385)
	life_num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# ⑥ 死亡卡片槽（右侧）
	card_rect = TextureRect.new()
	card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_rect.position = Vector2(700, 248)
	card_rect.size = Vector2(206, 341)
	card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cert_root.add_child(card_rect)
	# 无字卡模式的文字层（有字卡时隐藏）
	card_title = _mk_label("", 20, C_INK, card_rect.position + Vector2(0, 16), card_rect.size.x, true)
	card_rarity = _mk_label("", 16, C_SOFT, card_rect.position + Vector2(0, card_rect.size.y - 40), card_rect.size.x, true)
	card_title.visible = not CARDS_HAVE_TEXT
	card_rarity.visible = not CARDS_HAVE_TEXT

	# ⑦ 分享按钮（素材原位 236,651）
	var share_btn := TextureButton.new()
	var share_tex := _tex("btn_share.png")
	if share_tex != null:
		share_btn.texture_normal = share_tex
	share_btn.ignore_texture_size = true
	share_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	share_btn.position = Vector2(236, 651)
	share_btn.size = Vector2(186, 56)
	share_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	share_btn.pressed.connect(_on_share_pressed)
	cert_root.add_child(share_btn)
	share_label = _mk_label("分享", 26, C_INK, share_btn.position + Vector2(24, 10), share_btn.size.x - 24, true)
	if _cbrush() != null:
		share_label.add_theme_font_override("font", _cbrush())
	share_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ⑧ 重生按钮（素材原位 607,651）
	var reborn_btn := TextureButton.new()
	var reborn_tex := _tex("btn_reborn.png")
	if reborn_tex != null:
		reborn_btn.texture_normal = reborn_tex
	reborn_btn.ignore_texture_size = true
	reborn_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	reborn_btn.position = Vector2(607, 651)
	reborn_btn.size = Vector2(224, 53)
	reborn_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reborn_btn.pressed.connect(_close_certificate)
	cert_root.add_child(reborn_btn)
	reborn_label = _mk_label("重生", 26, Color(0.96, 0.93, 0.85), reborn_btn.position + Vector2(0, 8), reborn_btn.size.x, true)
	if _cbrush() != null:
		reborn_label.add_theme_font_override("font", _cbrush())
	reborn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reborn_label.add_theme_color_override("font_outline_color", Color(0.30, 0.34, 0.18))
	reborn_label.add_theme_constant_override("outline_size", 3)

	# 点任意处关闭（保持旧行为）
	main.certificate_panel.gui_input.connect(func (e):
		if e is InputEventMouseButton and e.pressed:
			_close_certificate()
	)

func _close_certificate() -> void:
	main.certificate_panel.visible = false
	main._certificate_open = false

func _on_share_pressed() -> void:
	await ShareCapture.share_panel(main.certificate_panel)

# ── 死因 → 卡片映射（CSV 有 card_id 时优先；否则关键词兜底）──
func _card_for_cause(cause_zh: String, cause_en: String, card_id: String = "") -> String:
	if card_id != "" and ResourceLoader.exists(CARDS_DIR + card_id + ".png"):
		return card_id
	var t := cause_zh + " " + cause_en.to_lower()
	var rules := [
		["鹅|goose", "death_goose"],
		["炸炉|丹炉|炼丹|furnace|alchem", "death_furnace"],
		["丹药|过量|pill|overdose", "death_pill_overdose"],
		["打伞|umbrella", "death_umbrella"],
		["雷|渡劫|天劫|lightning|tribulation", "death_lightning"],
		["心魔|inner demon", "death_inner_demon"],
		["走火入魔|qi deviation|deviation", "death_qi_deviation"],
		["熬夜|猝死|all night|stayed up|overwork", "death_allnighter"],
		["饿|辟谷|忘了吃|starv|hunger|fasting", "death_forgot_to_eat"],
		["寿|睡|老|lifespan|sleep|old age|natural", "death_lifespan"],
	]
	for r in rules:
		var rex := RegEx.new()
		rex.compile(r[0])
		if rex.search(t) != null:
			return r[1]
	return "death_lifespan"

func _show_reincarnation_certificate(cause_zh: String, cause_en: String, life_num: int, highest_realm_idx: int, punchline: Dictionary = {}) -> void:
	_enter_certificate_mode()
	var zh: bool = main.current_language == "zh"

	if main.toast_panel != null:
		main.toast_panel.visible = false
		main.toast_showing = false
		main.toast_queue.clear()
	if main.bubble_panel != null:
		main.bubble_panel.visible = false
	if main.bubble_tail != null:
		main.bubble_tail.visible = false
	if main.status_label != null:
		main.status_label.visible = false
	main.message_queue.clear()
	main.is_showing_message = false

	# 窗口撑到证书设计尺寸（沿用旧版防裁切逻辑，尺寸换成 1000×750）
	var win_size := Vector2i(int(CERT_DESIGN.x), int(CERT_DESIGN.y))
	var safe_pos: Vector2i = main._get_safe_window_position(win_size)
	DisplayServer.window_set_position(safe_pos)
	main.get_window().size = win_size
	await main.get_tree().process_frame

	var pet_name: String = String(main.state.get("pet_name", ""))
	var age: int = main._current_age()
	var realm_name: String = main.realms[highest_realm_idx]["name"] if zh else main.realm_names_en[highest_realm_idx]

	# 标题 logo
	var logo_tex := _tex("cert_logo_ch.png" if zh else "cert_logo_en.png")
	if logo_tex != null:
		logo_rect.texture = logo_tex
		var lw := float(logo_tex.get_width())
		logo_rect.size = Vector2(lw, logo_tex.get_height())
		logo_rect.position = Vector2((CERT_DESIGN.x - lw) / 2.0, 71.0)

	name_label.text = pet_name
	revenant_line.text = "已投胎，勿念" if zh else "Reincarnated. Do not miss him."

	var punchline_text: String = String(punchline.get("zh","")) if zh else String(punchline.get("en",""))
	if punchline_text == "":
		punchline_text = "此生已了，来世再修。" if zh else "This life is complete; cultivate again."

	field_realm.text = ("最高境界：%s" % realm_name) if zh else ("Peak Realm: %s" % realm_name)
	field_years.text = ("生存时间：%d 年" % age) if zh else ("Lifespan: %d years" % age)
	field_lastwords.text = ("遗言：%s" % punchline_text) if zh else ("Last words: %s" % punchline_text)
	life_num_label.text = ("—— 第 %d 世" % life_num) if zh else ("— Life %d" % life_num)

	# 死亡卡片
	var card_id := _card_for_cause(cause_zh, cause_en, String(punchline.get("card_id","")))
	var card_path := CARDS_DIR + card_id + ".png"
	if ResourceLoader.exists(card_path):
		card_rect.texture = load(card_path)
	if not CARDS_HAVE_TEXT:
		card_title.text = cause_zh if zh else cause_en
		card_rarity.text = String(punchline.get("rarity_zh", "普通")) if zh else String(punchline.get("rarity_en", "Common"))

	share_label.text = "分享" if zh else "Share"
	reborn_label.text = "重生" if zh else "Again"

	# 面板整体缩放并居中
	main.certificate_panel.visible = true
	var view: Vector2 = main.get_viewport_rect().size
	var s: float = min(view.x / CERT_DESIGN.x, view.y / CERT_DESIGN.y)
	cert_root.scale = Vector2(s, s)
	main.certificate_panel.position = (view - CERT_DESIGN * s) / 2.0
	main.certificate_panel.size = CERT_DESIGN * s

func _enter_certificate_mode() -> void:
	main._certificate_open = true

	if main.profile_panel != null:
		main.profile_panel.visible = false
	if main.report_panel != null:
		main.report_panel.visible = false
	if main.shop_panel != null:
		main.shop_panel.visible = false

	if main.bubble_panel != null:
		main.bubble_panel.visible = false
	if main.bubble_tail != null:
		main.bubble_tail.visible = false
	if main.status_label != null:
		main.status_label.visible = false
	if main.toast_panel != null:
		main.toast_panel.visible = false

	main.toast_showing = false
	main.toast_queue.clear()
	main.message_queue.clear()
	main.is_showing_message = false

	if main.get_node("PetGroup/VBox") != null:
		main.get_node("PetGroup/VBox").visible = false

	if main.event_manager != null:
		main.event_manager.set_paused(true)
