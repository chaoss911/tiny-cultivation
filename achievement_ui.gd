# ═══════════════════════════════════════════════
#  AchievementUI — 成就面板（分类页签 + 状态筛选 + 滚动卡片墙）
#  设计空间 1167×959（同主面板 frame_bg）。入口：主面板左上成就吊牌。
#  素材（res://assets/ui/ach/）: ach_big_box / ach_box / ach_logo_cn / ach_logo_en / ach_tab
#  复用: frame_bg.png, close_button.png（res://assets/ui/）
# ═══════════════════════════════════════════════
class_name AchievementUi
extends RefCounted

var main
const DESIGN := Vector2(1167, 959)
const ASSETS := "res://assets/ui/ach/"
const C_INK := Color(0.28, 0.20, 0.12)
const C_SOFT := Color(0.44, 0.36, 0.25)
const C_RED := Color(0.72, 0.22, 0.16)
const C_GREEN := Color(0.42, 0.58, 0.28)

const CATS := [
	{"id":"all","zh":"全部","en":"All"},
	{"id":"cultivate","zh":"修炼","en":"Cultivate"},
	{"id":"encounter","zh":"奇遇","en":"Fortune"},
	{"id":"death","zh":"作死","en":"Deaths"},
	{"id":"reincarnation","zh":"轮回","en":"Rebirth"},
]
const FILTERS := [
	{"id":"all","zh":"全部","en":"All"},
	{"id":"done","zh":"已达成","en":"Done"},
	{"id":"doing","zh":"进行中","en":"Active"},
	{"id":"locked","zh":"未解锁","en":"Locked"},
]

var panel: Control
var root: Control
var grid: GridContainer
var cat_buttons: Array = []
var filter_buttons: Array = []
var cur_cat := "all"
var cur_filter := "all"

func _b() -> FontFile: return GameConfig.brush_font()
func _t() -> FontFile: return GameConfig.body_font()

func _lbl(text: String, size: int, color: Color, brush := false, center := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f: FontFile = _b() if brush else _t()
	if f != null: l.add_theme_font_override("font", f)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _tex(p: String) -> Texture2D:
	return load(p) if ResourceLoader.exists(p) else null

func build_panel() -> void:
	panel = Control.new()
	panel.name = "AchievementPanel"
	panel.visible = false
	panel.z_index = 220
	panel.top_level = true
	main.add_child(panel)

	root = Control.new()
	root.custom_minimum_size = DESIGN
	root.size = DESIGN
	panel.add_child(root)

	var bg := TextureRect.new()
	var bt := _tex("res://assets/ui/frame_bg.png")
	if bt != null: bg.texture = bt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = DESIGN
	root.add_child(bg)

	# 标题（中英）
	var logo := TextureRect.new()
	logo.name = "AchLogo"
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(logo)

	# 关闭
	var close := TextureButton.new()
	var ct := _tex("res://assets/ui/close_button.png")
	if ct != null: close.texture_normal = ct
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.size = Vector2(56, 56)
	close.position = Vector2(DESIGN.x - 140, 40)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(func(): panel.visible = false)
	root.add_child(close)

# 左上角：返回主面板吊牌
	var back_tag := TextureButton.new()
	var bt2 := _tex("res://assets/ui/tab.png")
	if bt2 != null: back_tag.texture_normal = bt2
	back_tag.ignore_texture_size = true
	back_tag.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	back_tag.position = Vector2(78, 6)
	back_tag.size = Vector2(109, 200)
	back_tag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_tag.pressed.connect(func():
		panel.visible = false
		main._open_main_hall())
	root.add_child(back_tag)
	var back_lbl := _lbl("人生", 24, C_INK, true)
	back_lbl.position = Vector2(78, 120)
	back_lbl.size = Vector2(109, 40)
	back_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back_lbl)
	
	# 左侧分类页签
	for i in CATS.size():
		var c: Dictionary = CATS[i]
		var tb := TextureButton.new()
		var tt := _tex(ASSETS + "ach_tab.png")
		if tt != null: tb.texture_normal = tt
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.size = Vector2(150, 105)
		tb.position = Vector2(66, 210 + i * 130)
		tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var cid := String(c["id"])
		tb.pressed.connect(func():
			cur_cat = cid
			refresh())
		root.add_child(tb)
		var tl := _lbl("", 24, C_INK, true)
		tl.name = "CatLbl"
		tl.position = tb.position + Vector2(0, 26)
		tl.size = Vector2(150, 60)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tl)
		cat_buttons.append({"btn": tb, "lbl": tl, "id": cid})

	# 内容大框
	var big := TextureRect.new()
	var bb := _tex(ASSETS + "ach_big_box.png")
	if bb != null: big.texture = bb
	big.stretch_mode = TextureRect.STRETCH_SCALE
	big.position = Vector2(250, 190)
	big.size = Vector2(866, 704)
	root.add_child(big)

	# 状态筛选条
	var fb := HBoxContainer.new()
	fb.add_theme_constant_override("separation", 16)
	fb.position = Vector2(290, 214)
	root.add_child(fb)
	for f in FILTERS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 44)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.93, 0.89, 0.79)
		sb.set_corner_radius_all(18)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.62, 0.50, 0.32)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_color_override("font_color", C_INK)
		if _t() != null: btn.add_theme_font_override("font", _t())
		btn.add_theme_font_size_override("font_size", 22)
		var fid := String(f["id"])
		btn.pressed.connect(func():
			cur_filter = fid
			refresh())
		fb.add_child(btn)
		filter_buttons.append({"btn": btn, "id": fid, "def": f})

	# 滚动卡片墙（3 列）
	var sc := ScrollContainer.new()
	sc.position = Vector2(288, 274)
	sc.size = Vector2(796, 596)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	sc.add_child(grid)
	
	# 尺寸变化只重算布局。原来这里调的是 open()，而 open() 会连带 refresh()
	# 把整个成就网格重建一遍 —— 窗口在 WIN_NORMAL / WIN_WIDE 之间切的那两帧里，
	# 面板会肉眼可见地缩一下再弹回来。
	main.get_window().size_changed.connect(func():
		if panel.visible:
			_layout())

func open() -> void:
	var safe_pos: Vector2i = main._get_safe_window_position(GameConfig.WIN_MAIN)
	DisplayServer.window_set_position(safe_pos)
	main.get_window().size = GameConfig.WIN_MAIN

	await main.get_tree().process_frame

	panel.visible = true
	_layout()
	refresh()


## 只做缩放 + 居中，不碰内容。
## 这块布局由 achievement_ui 自己负责，main._on_window_resized() 不要再算一遍。
func _layout() -> void:
	var view: Vector2 = main.get_viewport_rect().size
	var s: float = min(view.x / DESIGN.x, view.y / DESIGN.y)
	root.scale = Vector2(s, s)
	panel.position = (view - DESIGN * s) / 2.0
	panel.size = DESIGN * s

func refresh() -> void:
	var zh: bool = main.current_language == "zh"
	var am = main.achievement_manager

	var logo: TextureRect = root.get_node("AchLogo")
	var lt := _tex(ASSETS + ("ach_logo_cn.png" if zh else "ach_logo_en.png"))
	if lt != null:
		logo.texture = lt
		var lw := float(lt.get_width())
		logo.size = Vector2(lw, lt.get_height())
		logo.position = Vector2((DESIGN.x - lw) / 2.0, 66)

	# 分类页签文字 + 计数 + 选中态
	for cb in cat_buttons:
		var cid := String(cb["id"])
		var total := 0
		var done := 0
		for d in am.defs:
			if cid == "all" or String(d["category"]) == cid:
				total += 1
				if am.unlocked.has(d["achievement_id"]): done += 1
		var cdef: Dictionary = CATS.filter(func(x): return x["id"] == cid)[0]
		cb["lbl"].text = "%s\n%d / %d" % [cdef["zh"] if zh else cdef["en"], done, total]
		cb["btn"].modulate = Color(1,1,1,1) if cid == cur_cat else Color(1,1,1,0.55)

	for fbt in filter_buttons:
		fbt["btn"].text = fbt["def"]["zh"] if zh else fbt["def"]["en"]
		fbt["btn"].modulate = Color(1,1,1,1) if String(fbt["id"]) == cur_filter else Color(1,1,1,0.55)

	# 卡片墙
	for c in grid.get_children(): c.queue_free()
	for d in am.defs:
		if cur_cat != "all" and String(d["category"]) != cur_cat: continue
		var unlocked: bool = am.unlocked.has(d["achievement_id"])
		var prog: int = am.get_progress(d)
		var target: int = int(d["target"])
		var state := "done" if unlocked else ("doing" if prog > 0 else "locked")
		if cur_filter != "all" and cur_filter != state: continue
		grid.add_child(_make_card(d, unlocked, prog, target, zh))

func _make_card(d: Dictionary, unlocked: bool, prog: int, target: int, zh: bool) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(254, 150)
	var bgt := _tex(ASSETS + "ach_box.png")
	var bg := TextureRect.new()
	if bgt != null: bg.texture = bgt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = card.custom_minimum_size
	card.add_child(bg)
	var hidden_locked: bool = int(d["hidden"]) == 1 and not unlocked
	if not unlocked:
		bg.modulate = Color(0.82, 0.82, 0.82) if hidden_locked else Color(0.92, 0.92, 0.92)

	var name := _lbl("？？？" if hidden_locked else String(d["name_zh"] if zh else d["name_en"]), 24, C_INK, true)
	name.position = Vector2(0, 12); name.size = Vector2(254, 30)
	card.add_child(name)
	var desc := _lbl(String(d["desc_zh"] if zh else d["desc_en"]) if not hidden_locked else ("天机不可泄露" if zh else "Heaven's secret"), 16, C_SOFT)
	desc.position = Vector2(14, 46); desc.size = Vector2(226, 40)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(desc)

	if unlocked:
		var stamp := _lbl("已达成" if zh else "DONE", 20, C_RED, true)
		stamp.position = Vector2(77, 108); stamp.size = Vector2(100, 32)
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Color(0,0,0,0)
		ssb.set_border_width_all(2)
		ssb.border_color = C_RED
		ssb.set_corner_radius_all(4)
		stamp.add_theme_stylebox_override("normal", ssb)
		stamp.rotation_degrees = -6.0
		stamp.pivot_offset = Vector2(50, 16)
		card.add_child(stamp)
	elif not hidden_locked:
		var bar := ProgressBar.new()
		bar.min_value = 0; bar.max_value = target; bar.value = prog
		bar.show_percentage = false
		bar.position = Vector2(40, 112); bar.size = Vector2(120, 12)
		var bbg := StyleBoxFlat.new(); bbg.bg_color = Color(0.85,0.82,0.72); bbg.set_corner_radius_all(6)
		var bf := StyleBoxFlat.new(); bf.bg_color = C_GREEN; bf.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("background", bbg)
		bar.add_theme_stylebox_override("fill", bf)
		card.add_child(bar)
		var pl := _lbl("%d / %d" % [prog, target], 16, C_INK, false, false)
		pl.position = Vector2(168, 104)
		card.add_child(pl)
	return card
