# ═══════════════════════════════════════════════
#  EventPopupUI — 事件弹窗（修仙小记卷轴）
#  用途：稀有/传说奇遇、突破等"值得打断"的时刻。普通事件继续走气泡。
#
#  素材（放 res://assets/ui/event/）：
#    event_bg.png          卷轴底（635×939，设计空间）
#    event_logo_ch.png     修仙小记 / event_logo_en.png  Event
#    event_title_plate.png 标题牌（371×75，空白）
#    btn_ok.png            知道了按钮（224×81，空白）
#    illust_cultivate/lazy/alchemy/sleep/workout/breakthrough.png（560×560 圆形插画）
#  字体：res://assets/fonts/AaFeiYanShouShu.ttf
#
#  用法（任何地方）：
#    main.event_popup.show_popup(
#        {"zh":"稀有奇遇","en":"Rare Encounter"},          # 标题
#        {"zh":ev["text_zh"],"en":ev["text_en"]},          # 正文
#        ev["event_type"],                                  # 插画 id（同 event_type）
#        [{"label_zh":"修为","label_en":"Qi","value":20}])  # 奖励，最多 3 项
#  弹窗排队：已有弹窗显示时自动入队，关一个出一个。
# ═══════════════════════════════════════════════
class_name EventPopupUi
extends RefCounted

var main   # Main.gd (Control) 引用

const DESIGN := Vector2(635, 939)
const ASSETS := "res://assets/ui/event/"
const FONT_PATH := "res://assets/fonts/AaFeiYanShouShu.ttf"

# 正文可用高度：650(正文起点) → 734(奖励行 742 上方留 8px)
const BODY_BOX := Vector2(DESIGN.x - 156, 84)
const LIGHT_BODY_BOX := Vector2(LIGHT_DESIGN.x - 140, 180)
const TITLE_BOX := Vector2(371, 75)

const C_INK   := Color(0.28, 0.20, 0.12)
const C_SOFT  := Color(0.44, 0.36, 0.25)
const C_GAIN  := Color(0.33, 0.52, 0.24)
const C_LOSS  := Color(0.72, 0.25, 0.18)

var popup_panel: Control
var popup_root: Control
var logo_rect: TextureRect
var title_label: Label
var illust_rect: TextureRect
var body_label: Label
var rewards_box: HBoxContainer
var ok_label: Label
var _font: FontFile
var _queue: Array = []
var _prev_win_size: Vector2i = Vector2i.ZERO

# ── 轻量弹窗（普通事件用：无按钮，自动消失）──
const LIGHT_DESIGN := Vector2(560, 460)     # frame_bg 1167×959 等比
const LIGHT_SECS := 4.0
var light_panel: Control
var light_root: Control
var light_body: Label
var light_reward: Label
var _light_token: int = 0

func _f() -> FontFile:
	return GameConfig.body_font()

func _fb() -> FontFile:
	return GameConfig.brush_font()

func _tex(name: String) -> Texture2D:
	var p := ASSETS + name
	return load(p) if ResourceLoader.exists(p) else null

## 把文字缩进指定框内 —— 固定尺寸卷轴美术的标准做法。
## 宁可字小一号，也不能糊到画框外面去。
func _fit_label(l: Label, box: Vector2, max_size: int, min_size: int = 14) -> void:
	if l == null or l.text == "":
		return
	var f: Font = l.get_theme_font("font")
	var size: int = max_size
	if f != null:
		while size > min_size:
			var m: Vector2 = f.get_multiline_string_size(
				l.text, l.horizontal_alignment, box.x, size)
			if m.y <= box.y and (l.autowrap_mode != TextServer.AUTOWRAP_OFF or m.x <= box.x):
				break
			size -= 1
	l.add_theme_font_size_override("font_size", size)
	l.custom_minimum_size = box
	l.size = box
	l.clip_text = true          # 兜底：万一还是装不下，裁掉而不是溢出到画框外


func _lbl(size: int, color: Color, center := true) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if _f() != null:
		l.add_theme_font_override("font", _f())
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func build_popup() -> void:
	popup_panel = Control.new()
	popup_panel.name = "EventPopupPanel"
	popup_panel.visible = false
	popup_panel.z_index = 280        # 低于证书(300)，证书优先
	popup_panel.top_level = true
	main.add_child(popup_panel)

	# 半透明遮罩，吞掉点击（模态）
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.22)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_panel.add_child(dim)

	popup_root = Control.new()
	popup_root.custom_minimum_size = DESIGN
	popup_root.size = DESIGN
	popup_panel.add_child(popup_root)

	var bg := TextureRect.new()
	var bg_tex := _tex("event_bg.png")
	if bg_tex != null:
		bg.texture = bg_tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = DESIGN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_root.add_child(bg)

	# 顶部 logo（修仙小记 / Event）
	logo_rect = TextureRect.new()
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_root.add_child(logo_rect)

	# 标题牌 + 标题
	var plate := TextureRect.new()
	var plate_tex := _tex("event_title_plate.png")
	if plate_tex != null:
		plate.texture = plate_tex
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plate.size = Vector2(371, 75)
	plate.position = Vector2((DESIGN.x - 371) / 2.0, 158)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_root.add_child(plate)
	title_label = _lbl(34, C_INK)
	title_label.position = plate.position
	title_label.size = plate.size
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _fb() != null:
		title_label.add_theme_font_override("font", _fb())
	popup_root.add_child(title_label)

	# 插画（圆形，380×380 居中）
	illust_rect = TextureRect.new()
	illust_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illust_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illust_rect.size = Vector2(380, 380)
	illust_rect.position = Vector2((DESIGN.x - 380) / 2.0, 252)
	illust_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_root.add_child(illust_rect)

	# 正文
	body_label = _lbl(24, C_INK)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.position = Vector2(78, 650)
	# 原本高度写死 0，正文一多就压到 742 的奖励行和 838 的按钮上。
	# 给它 650→734 这 84px，超出的部分交给 _fit_label 缩字号。
	body_label.custom_minimum_size = Vector2(DESIGN.x - 156, BODY_BOX.y)
	body_label.size = BODY_BOX
	body_label.clip_text = true
	popup_root.add_child(body_label)

	# 奖励行（最多 3 栏）
	rewards_box = HBoxContainer.new()
	rewards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	rewards_box.add_theme_constant_override("separation", 56)
	rewards_box.position = Vector2(78, 742)
	rewards_box.size = Vector2(DESIGN.x - 156, 84)
	popup_root.add_child(rewards_box)

	# 知道了按钮
	var ok_btn := TextureButton.new()
	var ok_tex := _tex("btn_ok.png")
	if ok_tex != null:
		ok_btn.texture_normal = ok_tex
	ok_btn.ignore_texture_size = true
	ok_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	ok_btn.size = Vector2(224, 81)
	ok_btn.position = Vector2((DESIGN.x - 224) / 2.0, 838)
	ok_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ok_btn.pressed.connect(_close_popup)
	popup_root.add_child(ok_btn)
	ok_label = _lbl(30, C_INK)
	ok_label.position = ok_btn.position + Vector2(0, 20)
	ok_label.size = Vector2(224, 40)
	if _fb() != null:
		ok_label.add_theme_font_override("font", _fb())
	ok_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_root.add_child(ok_label)

	_build_light_panel()

func _build_light_panel() -> void:
	light_panel = Control.new()
	light_panel.name = "EventLightPopup"
	light_panel.visible = false
	light_panel.z_index = 260        # 低于卷轴弹窗(280)和证书(300)
	light_panel.top_level = true
	main.add_child(light_panel)

	light_root = Control.new()
	light_root.custom_minimum_size = LIGHT_DESIGN
	light_root.size = LIGHT_DESIGN
	light_panel.add_child(light_root)

	var bg := TextureRect.new()
	var bg_tex := _tex("event_bg_light.png")
	if bg_tex != null:
		bg.texture = bg_tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = LIGHT_DESIGN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	light_root.add_child(bg)

	light_body = _lbl(26, C_INK)
	light_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	light_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	light_body.position = Vector2(70, 110)
	light_body.custom_minimum_size = LIGHT_BODY_BOX
	light_body.size = LIGHT_BODY_BOX
	light_body.clip_text = true
	light_root.add_child(light_body)

	light_reward = _lbl(30, C_GAIN)
	light_reward.position = Vector2(70, 312)
	light_reward.size = Vector2(LIGHT_DESIGN.x - 140, 40)
	light_root.add_child(light_reward)

	# 点一下立即关
	light_panel.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_hide_light())

# 普通事件轻量弹窗：无按钮，LIGHT_SECS 秒后自动淡出
func show_popup_light(body: Dictionary, reward_value: int = 0, reward_label: Dictionary = {}) -> void:
	if light_panel == null:
		return
	# 重量级弹窗/证书在场时不凑热闹，直接丢给气泡系统兜底
	if (popup_panel != null and popup_panel.visible) or (main._certificate_open if "_certificate_open" in main else false):
		return
	var zh: bool = main.current_language == "zh"
	light_body.text = String(body.get("zh","")) if zh else String(body.get("en",""))
	_fit_label(light_body, LIGHT_BODY_BOX, 26, 15)
	if reward_value != 0:
		var lab := String(reward_label.get("zh","修为")) if zh else String(reward_label.get("en","Qi"))
		light_reward.text = "%s %s%d" % [lab, "+" if reward_value > 0 else "", reward_value]
		light_reward.add_theme_color_override("font_color", C_GAIN if reward_value > 0 else C_LOSS)
		light_reward.visible = true
	else:
		light_reward.visible = false

	# 窗口管理只归 toast/主面板，轻量弹窗绝不抢：
	# 窗口不够大（桌宠模式）→ 回退成气泡，保持桌宠的不打扰
	var need := Vector2i(int(LIGHT_DESIGN.x) + 20, int(LIGHT_DESIGN.y) + 20)
	var cur: Vector2i = main.get_window().size
	if cur.x < need.x or cur.y < need.y:
		main.queue_message("💭 " + (String(body.get("zh","")) if zh else String(body.get("en",""))))
		return

	light_panel.visible = true
	light_panel.modulate = Color(1, 1, 1, 0)
	var view: Vector2 = main.get_viewport_rect().size
	var s: float = min(view.x / LIGHT_DESIGN.x, view.y / LIGHT_DESIGN.y, 1.0)
	light_root.scale = Vector2(s, s)
	light_root.position = (view - LIGHT_DESIGN * s) / 2.0
	var tw: Tween = main.create_tween()
	tw.tween_property(light_panel, "modulate:a", 1.0, 0.2)

	# 自动关闭（token 防止连发时旧计时器关掉新弹窗）
	_light_token += 1
	var my_token := _light_token
	await main.get_tree().create_timer(LIGHT_SECS).timeout
	if my_token == _light_token:
		_hide_light()

func _hide_light() -> void:
	if light_panel == null or not light_panel.visible:
		return
	_light_token += 1
	var tw: Tween = main.create_tween()
	tw.tween_property(light_panel, "modulate:a", 0.0, 0.2)
	await tw.finished
	light_panel.visible = false

func show_popup(title: Dictionary, body: Dictionary, illust_id: String, rewards: Array = []) -> void:
	if popup_panel == null:
		return
	if popup_panel.visible or (main._certificate_open if "_certificate_open" in main else false):
		_queue.append([title, body, illust_id, rewards])
		return
	_display(title, body, illust_id, rewards)

func _display(title: Dictionary, body: Dictionary, illust_id: String, rewards: Array) -> void:
	var zh: bool = main.current_language == "zh"

	var logo_tex := _tex("event_logo_ch.png" if zh else "event_logo_en.png")
	if logo_tex != null:
		logo_rect.texture = logo_tex
		var lw := float(logo_tex.get_width())
		logo_rect.size = Vector2(lw, logo_tex.get_height())
		logo_rect.position = Vector2((DESIGN.x - lw) / 2.0, 88)

	title_label.text = String(title.get("zh","")) if zh else String(title.get("en",""))
	body_label.text = String(body.get("zh","")) if zh else String(body.get("en",""))

	# ★ 必须在设完 text 之后调 —— 字号是按当前文字长度算的
	_fit_label(title_label, TITLE_BOX, 34, 20)
	_fit_label(body_label, BODY_BOX, 24, 15)

	var ipath := ASSETS + "illust_" + illust_id + ".png"
	if not ResourceLoader.exists(ipath):
		ipath = ASSETS + "illust_cultivate.png"      # 兜底
	if ResourceLoader.exists(ipath):
		illust_rect.texture = load(ipath)

	for c in rewards_box.get_children():
		c.queue_free()
	for r in rewards.slice(0, 3):
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var name := _lbl(20, C_SOFT)
		name.text = String(r.get("label_zh","")) if zh else String(r.get("label_en",""))
		name.clip_text = true
		name.custom_minimum_size = Vector2(120, 0)
		col.add_child(name)
		var v: int = int(r.get("value", 0))
		var val := _lbl(32, C_GAIN if v >= 0 else C_LOSS)
		val.text = ("+%d" % v) if v > 0 else str(v)
		col.add_child(val)
		rewards_box.add_child(col)

	ok_label.text = "知道了" if zh else "OK"

	# 窗口不够大时撑起来，并记住原尺寸
	var need := Vector2i(int(DESIGN.x) + 24, int(DESIGN.y) + 24)
	var cur: Vector2i = main.get_window().size
	_prev_win_size = Vector2i.ZERO
	if cur.x < need.x or cur.y < need.y:
		_prev_win_size = cur
		var safe_pos: Vector2i = main._get_safe_window_position(need)
		DisplayServer.window_set_position(safe_pos)
		main.get_window().size = need
		await main.get_tree().process_frame

	if main.event_manager != null:
		main.event_manager.set_paused(true)

	popup_panel.visible = true
	var view: Vector2 = main.get_viewport_rect().size
	var s: float = min(view.x / DESIGN.x, view.y / DESIGN.y)
	popup_root.scale = Vector2(s, s)
	popup_root.position = (view - DESIGN * s) / 2.0

func _close_popup() -> void:
	popup_panel.visible = false
	# 还原窗口（只在弹窗自己撑大过的情况下）
	if _prev_win_size != Vector2i.ZERO:
		main.get_window().size = _prev_win_size
		_prev_win_size = Vector2i.ZERO
		await main.get_tree().process_frame
		main.update_layout()
		main._reposition_overlay_panels()
	# 出队下一个
	if _queue.size() > 0:
		var nxt: Array = _queue.pop_front()
		_display(nxt[0], nxt[1], nxt[2], nxt[3])
		return
	if main.event_manager != null and not main._certificate_open:
		main.event_manager.set_paused(false)
