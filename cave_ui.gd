# ═══════════════════════════════════════════════
#  CaveUI — 洞府面板
#
#  规矩（跟 achievement_ui / report_ui 一致）：
#    面板自己管三件事 —— 窗口尺寸、缩放居中、size_changed 重排。
#    main 只负责关掉别的面板，不要在 _on_window_resized() 里再算一遍。
#
#  第一版范围：能开、有背景、家具能摆出来、小白站在里面。
#  不做：门/洞府两窗口架构、今日人物事件成就搬进来、玩家摆放家具。
# ═══════════════════════════════════════════════
class_name CaveUi
extends RefCounted

var main

## 那张空洞府图的实际像素尺寸。换图必须同步改这里。
const DESIGN := Vector2(1536, 1024)
const ASSETS := "res://assets/ui/cave/"

## 家具锚点，全部是 DESIGN 空间里的坐标（左上原点）。
## 先按背景图量一遍填进来，没量到的先留着，摆错了肉眼就能看见。
const ANCHORS := {
	"door":          Vector2( 250,  520),   # 门口，出门按钮 / 小白进出的位置
	"paper":         Vector2( 455,  350),   # 勤修不辍（上一个人留下的）
	"lamp_hook":     Vector2(1090,  155),   # 梁上空钩子 —— 油灯挂这里
	"mat":           Vector2( 880,  700),   # 草席
	"bowl":          Vector2( 600,  750),   # 破碗
	"cushion":       Vector2( 760,  660),   # 蒲团
	"sign":          Vector2( 700,  120),   # 木牌（洞府名）
	"stone":         Vector2( 180,  760),   # 石头（门外）
	"roof":          Vector2( 900,   60),   # 雀
	"work_corner":   Vector2(1250,  700),   # 营生工具
	"stand":         Vector2( 830,  720),   # 小白默认站位
}

## 小白在洞府里的显示倍率。桌面上那个尺寸放进 1536 宽的图里会太小。
const PET_SCALE := 2.8

## 气泡在洞府里要往上抬 —— 角色放大了，气泡没放大，
## 用原来的偏移会压到他头上。这个值大约是 (PET_SCALE - 1) × 角色高度的一半。
const BUBBLE_LIFT := 70.0

## 锚点代表「脚站的地方」，但 AnimatedSprite2D 默认 centered，
## 原点在角色中心。不补这一下，家具就会摆在他胸口而不是脚下。
## 运行时按贴图高度算，算不出来就用这个兜底。
const PET_FOOT_LIFT_FALLBACK := 90.0

## 边框九宫格的边距（用 cave_frame.png 时生效）
const FRAME_MARGIN := 48

var panel: Control
var root: Control
var bg: TextureRect
var furniture_root: Node2D      # CaveController 往这里塞家具
var pet_slot: Node2D            # 小白进洞府时 reparent 到这里

var _pet_home: Node = null      # 记住小白原来的父节点，出洞府时放回去
var _pet_home_pos: Vector2 = Vector2.ZERO

## 气泡和尾巴挂在 pet_group 上，不是挂在 sprite 上，
## 所以要单独搬 —— 否则小白进了洞府，说话的气泡还留在外面。
var _moved: Array = []          # [{node, parent, pos, scale}, ...]


func _b() -> FontFile: return GameConfig.brush_font()
func _t() -> FontFile: return GameConfig.body_font()

func _tex(p: String) -> Texture2D:
	return load(p) if ResourceLoader.exists(p) else null


# ---------------------------------------------------------------- 构建

func build_panel() -> void:
	if main == null:
		push_warning("[cave] main 未注入，跳过建面板")
		return

	panel = Control.new()
	panel.name = "CavePanel"
	panel.visible = false
	panel.z_index = 210          # 低于成就(220)，高于普通 toast
	panel.top_level = true
	main.add_child(panel)

	root = Control.new()
	root.name = "CaveRoot"
	root.custom_minimum_size = DESIGN
	root.size = DESIGN
	panel.add_child(root)

	# ── 背景（那张暗版空洞府）──
	bg = TextureRect.new()
	bg.name = "CaveBg"
	var bt := _tex(ASSETS + "cave_interior_dark.png")
	if bt != null:
		bg.texture = bt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = DESIGN
	root.add_child(bg)

	# ── 边框 ──
	# 有图就用图（九宫格拉伸），没有就画一个描边，不至于开出来光秃秃。
	var frame_tex := _tex(ASSETS + "cave_frame.png")
	if frame_tex != null:
		var nine := NinePatchRect.new()
		nine.name = "CaveFrame"
		nine.texture = frame_tex
		nine.patch_margin_left = FRAME_MARGIN
		nine.patch_margin_top = FRAME_MARGIN
		nine.patch_margin_right = FRAME_MARGIN
		nine.patch_margin_bottom = FRAME_MARGIN
		nine.size = DESIGN
		nine.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nine.z_index = 50
		root.add_child(nine)
	else:
		var border := Panel.new()
		border.name = "CaveFrame"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_width_left = 10
		sb.border_width_top = 10
		sb.border_width_right = 10
		sb.border_width_bottom = 10
		sb.border_color = Color(0.20, 0.15, 0.09)
		sb.corner_radius_top_left = 14
		sb.corner_radius_top_right = 14
		sb.corner_radius_bottom_left = 14
		sb.corner_radius_bottom_right = 14
		border.add_theme_stylebox_override("panel", sb)
		border.size = DESIGN
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.z_index = 50
		root.add_child(border)

	# ── 家具层 ──
	# 用 Node2D + y_sort 让小白能走到家具前后。
	furniture_root = Node2D.new()
	furniture_root.name = "FurnitureRoot"
	furniture_root.y_sort_enabled = true
	root.add_child(furniture_root)

	# ── 小白的位置 ──
	# 挂在 furniture_root 下面，跟家具共用同一套 y_sort。
	pet_slot = Node2D.new()
	pet_slot.name = "PetSlot"
	pet_slot.position = ANCHORS["stand"]
	furniture_root.add_child(pet_slot)

	# ── 出门 ──
	var out_btn := TextureButton.new()
	out_btn.name = "ExitButton"
	var ot := _tex(ASSETS + "door_hotspot.png")
	if ot != null:
		out_btn.texture_normal = ot
	out_btn.ignore_texture_size = true
	out_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	out_btn.size = Vector2(180, 300)
	out_btn.position = ANCHORS["door"] - Vector2(90, 200)
	out_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	out_btn.pressed.connect(close)
	root.add_child(out_btn)

	# ── 洞府名（木牌上的字，没拿到木牌时就是「洞府」）──
	var name_lbl := Label.new()
	name_lbl.name = "CaveName"
	name_lbl.add_theme_font_size_override("font_size", 40)
	name_lbl.add_theme_color_override("font_color", Color(0.28, 0.20, 0.12))
	if _b() != null:
		name_lbl.add_theme_font_override("font", _b())
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size = Vector2(300, 60)
	name_lbl.position = ANCHORS["sign"] - Vector2(150, 30)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)

	# ── 关闭 ──
	var close_btn := TextureButton.new()
	var ct := _tex("res://assets/ui/close_button.png")
	if ct != null:
		close_btn.texture_normal = ct
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_btn.size = Vector2(56, 56)
	close_btn.position = Vector2(DESIGN.x - 100, 40)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(close)
	root.add_child(close_btn)

	# 尺寸变化只重算布局，不重建内容
	var w: Window = main.get_window()
	if w != null:
		w.size_changed.connect(func():
			if panel != null and panel.visible:
				_layout())


# ---------------------------------------------------------------- 开关

func open() -> void:
	if panel == null:
		push_warning("[cave] 面板没建起来，open() 跳过")
		return
	var safe_pos: Vector2i = main._get_safe_window_position(GameConfig.WIN_MAIN)
	DisplayServer.window_set_position(safe_pos)
	main.get_window().size = GameConfig.WIN_MAIN

	await main.get_tree().process_frame

	panel.visible = true
	_layout()
	_take_pet()

	# 面板是后建的，解锁可能发生在它还没建好的时候 —— 每次打开补齐一次。
	# rebuild() 里会连带刷新木牌名字，这里不用再调 refresh()。
	if main.cave != null:
		main.cave.rebuild()


func close() -> void:
	if panel == null:
		return
	_release_pet()
	panel.visible = false
	main.get_window().size = GameConfig.WIN_NORMAL
	await main.get_tree().process_frame
	main.update_layout()


## 只做缩放 + 居中，不碰内容。
func _layout() -> void:
	var view: Vector2 = main.get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var s: float = min(view.x / DESIGN.x, view.y / DESIGN.y)
	root.scale = Vector2(s, s)
	panel.position = (view - DESIGN * s) / 2.0
	panel.size = DESIGN * s


## 显示什么由 Controller 决定，UI 不知道为什么。
## 没拿到木牌时 Controller 传进来的就是「洞府」。
func refresh(cave_name: String) -> void:
	var lbl: Label = root.get_node_or_null("CaveName") as Label
	if lbl != null:
		lbl.text = cave_name


# ---------------------------------------------------------------- 小白进出

## 把桌面上那个小白搬进洞府。不新建 sprite —— 同一个节点换父级，
## 动画状态、境界、修饰符全都跟着走，不用同步两份。
func _take_pet() -> void:
	var spr: Node2D = main.cultivator_sprite
	if spr == null or not is_instance_valid(spr):
		return
	_pet_home = spr.get_parent()
	if _pet_home == null:
		return
	_pet_home_pos = spr.position

	# 小白本体。往上抬半个身高，让脚落在锚点上。
	_reparent(spr, pet_slot, Vector2(0.0, -_pet_foot_lift(spr)), Vector2(PET_SCALE, PET_SCALE))

	# 气泡 + 尾巴：位置保持原样（相对角色的偏移），只是换了父节点。
	# 它们本来就是按 pet_group 原点摆的，pet_slot 也是角色原点，所以直接搬。
	_reparent(main.bubble_tail, pet_slot, Vector2.INF, Vector2.ONE)
	_reparent(main.bubble_panel, pet_slot, Vector2.INF, Vector2.ONE)
	_lift_bubble(-BUBBLE_LIFT)

	# 室内不下雨不下雪
	if main.modifier_layer != null:
		main.modifier_layer.set_indoor(true)


## 半个身高 × 缩放。取当前帧的贴图高度，取不到就用兜底值。
func _pet_foot_lift(spr: Node2D) -> float:
	var h: float = 0.0
	if spr is AnimatedSprite2D:
		var a := spr as AnimatedSprite2D
		if a.sprite_frames != null and a.sprite_frames.has_animation(a.animation):
			var t: Texture2D = a.sprite_frames.get_frame_texture(a.animation, a.frame)
			if t != null:
				h = float(t.get_height())
	elif spr is Sprite2D and (spr as Sprite2D).texture != null:
		h = float((spr as Sprite2D).texture.get_height())
	if h <= 0.0:
		return PET_FOOT_LIFT_FALLBACK * PET_SCALE
	return h * 0.5 * PET_SCALE


## 气泡整体上下移。进洞府时抬高，出去时 _release_pet() 会用记录的原位置还原，
## 所以这里不用再降回来。
func _lift_bubble(dy: float) -> void:
	for n in [main.bubble_panel, main.bubble_tail]:
		if n == null or not is_instance_valid(n):
			continue
		if n is Node2D:
			(n as Node2D).position.y += dy
		elif n is Control:
			(n as Control).position.y += dy


## pos 传 Vector2.INF 表示保持原位置不动
func _reparent(n: Node, to: Node, pos: Vector2, sc: Vector2) -> void:
	if n == null or not is_instance_valid(n) or to == null:
		return
	var old_parent: Node = n.get_parent()
	if old_parent == null or old_parent == to:
		return
	var ci := n as CanvasItem
	var old_pos: Vector2 = Vector2.ZERO
	var old_scale: Vector2 = Vector2.ONE
	if ci is Node2D:
		old_pos = (ci as Node2D).position
		old_scale = (ci as Node2D).scale
	elif ci is Control:
		old_pos = (ci as Control).position
		old_scale = (ci as Control).scale

	_moved.append({"node": n, "parent": old_parent, "pos": old_pos, "scale": old_scale})

	old_parent.remove_child(n)
	to.add_child(n)

	if pos != Vector2.INF:
		if ci is Node2D: (ci as Node2D).position = pos
		elif ci is Control: (ci as Control).position = pos
	if ci is Node2D: (ci as Node2D).scale = sc
	elif ci is Control: (ci as Control).scale = sc


func _release_pet() -> void:
	# 倒着还原，顺序跟搬进来时相反
	for i in range(_moved.size() - 1, -1, -1):
		var rec: Dictionary = _moved[i]
		var n: Node = rec["node"]
		if n == null or not is_instance_valid(n):
			continue
		var home: Node = rec["parent"]
		if home == null or not is_instance_valid(home):
			continue
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		home.add_child(n)
		if n is Node2D:
			(n as Node2D).position = rec["pos"]
			(n as Node2D).scale = rec["scale"]
		elif n is Control:
			(n as Control).position = rec["pos"]
			(n as Control).scale = rec["scale"]
	_moved.clear()
	_pet_home = null

	if main.modifier_layer != null:
		main.modifier_layer.set_indoor(false)


## 家具/小白走到某个锚点。CaveController 用这个定位。
func anchor(id: String) -> Vector2:
	return ANCHORS.get(id, ANCHORS["stand"])
