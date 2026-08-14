# ═══════════════════════════════════════════════
#  ReportUI v2 — 事件簿（修仙小记）全屏面板
#  今日/昨日/更早 分组 · 多奖励文字 · 筛选(全部/今日/重要) · 分页 · 吉祥物点评
#  设计空间 1426×1031（report_bg.png 原尺寸）
#  对外接口 _build_report_panel / _on_report_pressed / _refresh_reports 不变
#  素材 res://assets/ui/report/: report_bg / report_logo_cn / report_logo_en / report_filter_btn
#  复用: res://assets/ui/close_button.png
# ═══════════════════════════════════════════════
class_name ReportUi
extends RefCounted

var main
const DESIGN := Vector2(1426, 1031)
const ASSETS := "res://assets/ui/report/"
const PER_PAGE := 6
const C_INK := Color(0.28, 0.20, 0.12)
const C_SOFT := Color(0.44, 0.36, 0.25)
const C_GAIN := Color(0.33, 0.52, 0.24)
const C_LOSS := Color(0.72, 0.25, 0.18)

const FILTERS := [
	{"id":"all","zh":"全部","en":"All"},
	{"id":"today","zh":"今日","en":"Today"},
	{"id":"important","zh":"重要","en":"Key"},
]
# 左下吉祥物气泡的可写区域（design space，1426×1031）。
# 这两个数要跟 report_bg.png 里画的气泡对齐 —— 现在的 (175,892)+300×70
# 比画上去的气泡又低又大，所以第二行掉到框外面了。
# 开 DEBUG_BOXES 跑一次，按看到的色块微调这两个值。
const MASCOT_POS := Vector2(178, 862)
const MASCOT_BOX := Vector2(268, 52)
const DEBUG_BOXES := false

const QUIPS_ZH := ["每一段经历，都是修仙路上的宝贵积累~", "道友今日也很努力呢~", "点滴皆修行，慢慢来~", "又是充实的一天呀~"]
const QUIPS_EN := ["Every moment is a step on the path~", "You worked hard today~", "Every drop is cultivation~", "What a full day~"]

var root: Control
var logo_rect: TextureRect
var list_box: VBoxContainer
var page_label: Label
var mascot_line: Label
var filter_buttons: Array = []
var cur_filter := "all"
var cur_page := 0

func _b() -> FontFile: return GameConfig.brush_font()
func _t() -> FontFile: return GameConfig.body_font()
func _tex(p: String) -> Texture2D: return load(p) if ResourceLoader.exists(p) else null

func _lbl(text: String, size: int, color: Color, brush := false, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f: FontFile = _b() if brush else _t()
	if f != null: l.add_theme_font_override("font", f)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## 把文字缩进指定框内。框固定、文字长度不定时用这个。
## 必须在设完 text 之后调 —— 字号是按当前文字算的。
func _fit_label(l: Label, box: Vector2, max_size: int, min_size: int = 12) -> void:
	if l == null or l.text == "":
		return
	var f: Font = l.get_theme_font("font")
	var size: int = max_size
	if f != null:
		while size > min_size:
			var m: Vector2 = f.get_multiline_string_size(
				l.text, l.horizontal_alignment, box.x, size)
			if m.y <= box.y:
				break
			size -= 1
	l.add_theme_font_size_override("font_size", size)
	l.custom_minimum_size = box
	l.size = box
	l.clip_text = true


func _build_report_panel() -> void:
	main.report_panel = Control.new()
	main.report_panel.name = "ReportPanel"
	main.report_panel.visible = false
	main.report_panel.z_index = 240
	main.report_panel.top_level = true
	main.add_child(main.report_panel)

	root = Control.new()
	root.custom_minimum_size = DESIGN
	root.size = DESIGN
	main.report_panel.add_child(root)

	# 背景整幅
	var bg := TextureRect.new()
	var bt := _tex(ASSETS + "report_bg.png")
	if bt != null: bg.texture = bt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = DESIGN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# 标题 logo（中英切换）
	logo_rect = TextureRect.new()
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(logo_rect)

	# 关闭
	var close := TextureButton.new()
	var ct := _tex("res://assets/ui/close_button.png")
	if ct != null: close.texture_normal = ct
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.size = Vector2(56, 56)
	close.position = Vector2(DESIGN.x - 150, 66)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_close_report_panel)
	root.add_child(close)

	# 筛选按钮：全部 / 今日 / 重要
	var fx := 210.0
	for f in FILTERS:
		var btn := TextureButton.new()
		var ft := _tex(ASSETS + "report_filter_btn.png")
		if ft != null: btn.texture_normal = ft
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.size = Vector2(150, 56)
		btn.position = Vector2(fx, 205)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var fid := String(f["id"])
		btn.pressed.connect(func():
			cur_filter = fid; cur_page = 0; _refresh_reports())
		root.add_child(btn)
		var fl := _lbl("", 24, C_INK, true, true)
		fl.position = btn.position; fl.size = btn.size
		fl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(fl)
		filter_buttons.append({"btn": btn, "lbl": fl, "def": f, "id": fid})
		fx += 170

	# 事件列表滚动区（内框内，留出底部分页空间）
	var sc := ScrollContainer.new()
	sc.position = Vector2(210, 275)
	sc.size = Vector2(1010, 545)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 10)
	list_box.custom_minimum_size = Vector2(1010, 0)
	sc.add_child(list_box)

	# 分页
	var prev := Button.new()
	prev.text = "‹"; prev.flat = true
	prev.add_theme_font_size_override("font_size", 40)
	prev.add_theme_color_override("font_color", C_INK)
	prev.position = Vector2(560, 852); prev.size = Vector2(60, 60)
	prev.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	prev.pressed.connect(func():
		if cur_page > 0: cur_page -= 1; _refresh_reports())
	root.add_child(prev)
	page_label = _lbl("", 26, C_INK, true, true)
	page_label.position = Vector2(630, 865); page_label.size = Vector2(160, 40)
	root.add_child(page_label)
	var nxt := Button.new()
	nxt.text = "›"; nxt.flat = true
	nxt.add_theme_font_size_override("font_size", 40)
	nxt.add_theme_color_override("font_color", C_INK)
	nxt.position = Vector2(800, 852); nxt.size = Vector2(60, 60)
	nxt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	nxt.pressed.connect(func():
		cur_page += 1; _refresh_reports())
	root.add_child(nxt)

	# 左下吉祥物点评（背景自带气泡框）
	if DEBUG_BOXES:
		var dbg := ColorRect.new()
		dbg.color = Color(1, 0, 0, 0.25)
		dbg.position = MASCOT_POS
		dbg.size = MASCOT_BOX
		dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(dbg)

	mascot_line = _lbl("", 20, C_SOFT)
	mascot_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mascot_line.position = MASCOT_POS
	mascot_line.size = MASCOT_BOX
	mascot_line.custom_minimum_size = MASCOT_BOX
	mascot_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mascot_line.clip_text = true
	mascot_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mascot_line)

func _on_report_pressed() -> void:
	main._mark_interaction()
	AudioManager.play_click()
	if main.report_panel.visible:
		_close_report_panel()
		return
	if main.shop_panel != null: main.shop_panel.visible = false
	if main.profile_panel != null: main.profile_panel.visible = false
	_open_report_panel()

func _open_report_panel() -> void:
	# 和主面板一样：锁定窗口尺寸
	var safe_pos: Vector2i = main._get_safe_window_position(GameConfig.WIN_MAIN)
	DisplayServer.window_set_position(safe_pos)
	main.get_window().size = GameConfig.WIN_MAIN
	await main.get_tree().process_frame

	main.report_panel.visible = true
	cur_page = 0
	var zh: bool = main.current_language == "zh"
	var idx := randi() % QUIPS_ZH.size()
	mascot_line.text = QUIPS_ZH[idx] if zh else QUIPS_EN[idx]
	# 四句台词长度不同，英文更长 —— 每次都重新算字号
	_fit_label(mascot_line, MASCOT_BOX, 20, 13)

	# 尺寸变化时自己重算布局（只连一次）。
	# main._on_window_resized() 不再管这块 —— 两边同时改 root.scale 会打架。
	var w: Window = main.get_window()   # main 是无类型 Variant，:= 推不出来
	if not w.size_changed.is_connected(_on_size_changed):
		w.size_changed.connect(_on_size_changed)

	_layout()
	_refresh_reports()


func _on_size_changed() -> void:
	if main.report_panel != null and main.report_panel.visible:
		_layout()


## 只做缩放 + 居中，不碰内容。
## 用真实视口尺寸算，不要用 WIN_MAIN 常量 —— 屏幕小的时候
## _get_safe_window_position 会把窗口挤小，常量就跟实际对不上了。
func _layout() -> void:
	var win: Vector2 = main.get_viewport_rect().size
	if win.x <= 0.0 or win.y <= 0.0:
		return
	var s: float = min(win.x / DESIGN.x, win.y / DESIGN.y)
	root.scale = Vector2(s, s)
	main.report_panel.position = (win - DESIGN * s) / 2.0

func _close_report_panel() -> void:
	main.report_panel.visible = false
	if main.event_manager != null:
		main.event_manager.set_paused(false)

# ── 过滤 + 排序（最新在上）──
func _filtered_events() -> Array:
	var today := Time.get_date_string_from_system()
	var out: Array = []
	for ev in main.recent_events:
		if cur_filter == "today" and String(ev.get("date","")) != today:
			continue
		if cur_filter == "important":
			var t := String(ev.get("type",""))
			if not (t in ["encounter","breakthrough","death","legendary"]):
				continue
		out.append(ev)
	out.sort_custom(func(a, b):
		return int(a.get("ts", 0)) > int(b.get("ts", 0)))
	return out

func _refresh_reports() -> void:
	if main.report_panel == null or not main.report_panel.visible:
		return
	var zh: bool = main.current_language == "zh"

	# 标题 logo
	var lt := _tex(ASSETS + ("report_logo_cn.png" if zh else "report_logo_en.png"))
	if lt != null:
		logo_rect.texture = lt
		var lw := float(lt.get_width())
		logo_rect.size = Vector2(lw, lt.get_height())
		logo_rect.position = Vector2((DESIGN.x - lw) / 2.0, 70)

	for fb in filter_buttons:
		fb["lbl"].text = fb["def"]["zh"] if zh else fb["def"]["en"]
		fb["btn"].modulate = Color(1,1,1,1) if String(fb["id"]) == cur_filter else Color(1,1,1,0.6)

	var events := _filtered_events()
	var total_pages: int = max(1, int(ceil(float(events.size()) / PER_PAGE)))
	cur_page = clampi(cur_page, 0, total_pages - 1)
	page_label.text = "%d / %d" % [cur_page + 1, total_pages]

	for c in list_box.get_children(): c.queue_free()
	var start := cur_page * PER_PAGE
	var page_events: Array = events.slice(start, start + PER_PAGE)

	var last_group := ""
	var today := Time.get_date_string_from_system()
	for ev in page_events:
		var group := _group_name(String(ev.get("date","")), today, zh)
		if group != last_group:
			list_box.add_child(_group_header(group))
			last_group = group
		list_box.add_child(_event_row(ev, zh))

	if page_events.is_empty():
		list_box.add_child(_lbl("暂无事件" if zh else "No events", 24, C_SOFT, false, true))

func _group_name(date_str: String, today: String, zh: bool) -> String:
	if date_str == "":
		return "更早" if zh else "Earlier"
	if date_str == today:
		return "今日" if zh else "Today"
	var yday: String = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)
	if date_str == yday:
		return "昨日" if zh else "Yesterday"
	return date_str

func _group_header(text: String) -> Control:
	var h := _lbl("❀ " + text, 24, C_SOFT, true)
	h.custom_minimum_size = Vector2(980, 40)
	return h

func _event_row(ev: Dictionary, zh: bool) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.94, 0.87, 0.55)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 12; sb.content_margin_bottom = 12
	row.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	row.add_child(hb)

	var tl := _lbl(String(ev.get("time","")), 22, C_SOFT)
	tl.custom_minimum_size = Vector2(72, 0)
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(tl)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	var title := _lbl(String(ev.get("zh","") if zh else ev.get("en","")), 24, C_INK, true)
	title.clip_text = true          # 长标题裁掉，别糊到奖励栏上
	mid.add_child(title)
	var dtxt := String(ev.get("desc_zh","") if zh else ev.get("desc_en",""))
	if dtxt != "":
		# 用 RichTextLabel + fit_content，不用 Label。
		# Label 开 autowrap 放进容器里，最小高度按单行算，多行就会压到下一行上去。
		var desc := RichTextLabel.new()
		desc.bbcode_enabled = false
		desc.text = dtxt
		desc.fit_content = true
		desc.scroll_active = false
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(560, 0)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc.add_theme_font_size_override("normal_font_size", 18)
		desc.add_theme_color_override("default_color", C_SOFT)
		if _t() != null:
			desc.add_theme_font_override("normal_font", _t())
		mid.add_child(desc)
	hb.add_child(mid)

	var rewards: Array = ev.get("rewards", [])
	if not rewards.is_empty():
		var rb := HBoxContainer.new()
		rb.add_theme_constant_override("separation", 20)
		rb.alignment = BoxContainer.ALIGNMENT_END
		for r in rewards:
			var v: int = int(r.get("value", 0))
			var lab := String(r.get("label_zh","") if zh else r.get("label_en",""))
			var rl := _lbl("%s %s%d" % [lab, "+" if v > 0 else "", v], 22, C_GAIN if v >= 0 else C_LOSS)
			rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			rb.add_child(rl)
		hb.add_child(rb)
	return row
