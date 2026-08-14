extends Node2D
# ============================================================
#  序章原型 —— 用色块占位，不需要任何美术就能跑
#
#  目的：先把节拍、那一次点击、和进洞的转场跑通。
#  美术、天气、小记全部是后面贴上去的皮。
#
#  用法：新建 prologue.tscn，根节点 Node2D，挂这个脚本，F6 单独跑。
#        不要接进 main.tscn，等节拍调顺了再接。
#
#  按键：
#    S     跳过当前等待（调试用，2 分半一遍太久）
#    ESC   退出
# ============================================================

signal prologue_finished

const W := 960.0
const H := 540.0
const GROUND_Y := 420.0

# —— 可调节拍（秒）——
const T_OPENING_WALK   := 15.0   # 开场什么都不发生
const T_STELE_LOOK     := 3.0
const T_WALK_TO_RAIN   := 17.0
const T_SHELTER        := 25.0
const T_CAVE_PEEK      := 20.0   # 没人点，他探头
const T_CAVE_AUTOENTER := 45.0   # 还没人点，他自己进
const DARK_ALPHA       := 0.45   # 内景不点灯，留一层暗

var pet: ColorRect
var stele: ColorRect
var rock: ColorRect
var cave: ColorRect
var vines: ColorRect
var mat: ColorRect
var paper: ColorRect
var bubble: Label
var fader: ColorRect
var hint: Label

var _skip := false
var _entered := false
var _cave_clickable := false


func _ready() -> void:
	_build_exterior()
	_run.call_deferred()


# ============================================================
#  外景
# ============================================================
func _build_exterior() -> void:
	var sky := ColorRect.new()
	sky.color = Color(0.72, 0.76, 0.78)
	sky.size = Vector2(W, H)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	var ground := ColorRect.new()
	ground.color = Color(0.38, 0.40, 0.34)
	ground.position = Vector2(0, GROUND_Y)
	ground.size = Vector2(W, H - GROUND_Y)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	# 山壁（洞口所在）
	var cliff := ColorRect.new()
	cliff.color = Color(0.30, 0.31, 0.30)
	cliff.position = Vector2(0, 120)
	cliff.size = Vector2(230, GROUND_Y - 120)
	cliff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cliff)

	stele = _block(Color(0.55, 0.55, 0.52), Vector2(34, 56), Vector2(660, GROUND_Y - 56))
	rock  = _block(Color(0.45, 0.44, 0.40), Vector2(70, 46), Vector2(390, GROUND_Y - 46))

	# 洞口：默认藏在藤蔓后
	cave = _block(Color(0.06, 0.06, 0.08), Vector2(88, 110), Vector2(70, GROUND_Y - 110))
	vines = _block(Color(0.26, 0.42, 0.26), Vector2(96, 118), Vector2(66, GROUND_Y - 118))
	vines.mouse_filter = Control.MOUSE_FILTER_STOP
	vines.gui_input.connect(_on_cave_input)
	vines.mouse_entered.connect(_on_cave_hover.bind(true))
	vines.mouse_exited.connect(_on_cave_hover.bind(false))

	pet = _block(Color(0.95, 0.90, 0.72), Vector2(30, 46), Vector2(W - 60, GROUND_Y - 46))
	pet.mouse_filter = Control.MOUSE_FILTER_STOP
	pet.gui_input.connect(_on_pet_input)

	bubble = Label.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	bubble.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	bubble.add_theme_constant_override("outline_size", 8)
	bubble.visible = false
	add_child(bubble)

	fader = ColorRect.new()
	fader.color = Color(0, 0, 0, 0)
	fader.size = Vector2(W, H)
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fader)

	hint = Label.new()
	hint.text = "[S] 跳过等待   [ESC] 退出"
	hint.position = Vector2(12, 10)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(0, 0, 0, 0.4))
	add_child(hint)


func _block(c: Color, s: Vector2, p: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.size = s
	r.position = p
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


# ============================================================
#  序章主流程
# ============================================================
func _run() -> void:
	# 0:00 什么都不发生
	await _walk_to(700.0, T_OPENING_WALK)

	# 0:15 石碑
	await _wait(1.0)
	await _say("修仙。", T_STELE_LOOK)

	# 0:35 下雨
	await _walk_to(470.0, 6.0)
	_set_rain(true)          # TODO: 接你现成的 weather layer
	await _wait(2.0)

	# 0:50 躲雨失败（石头挡不住斜雨）
	await _walk_to(rock.position.x + 78.0, 4.0)
	await _wait(T_SHELTER * 0.4)
	# 他缩了一下——没有台词
	await _nudge()
	await _wait(T_SHELTER * 0.6)

	# 1:20 他看见了
	_set_rain(false)
	await _walk_to(cave.position.x + 110.0, 6.0)
	await _say("有人住过吗？", 2.5)

	# 犹豫 —— 交给玩家
	_cave_clickable = true
	vines.modulate = Color(1.06, 1.06, 1.06)

	var waited := 0.0
	while not _entered:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > T_CAVE_PEEK and waited < T_CAVE_PEEK + 0.1:
			await _nudge()                       # 探头
		if waited > T_CAVE_AUTOENTER:
			await _say("……失礼了。", 1.5)
			_enter_cave()

	await _fade(1.0, 0.8)
	_build_interior()
	await _wait(1.2)

	# 2:00 洞里很暗 —— 不点灯。只有洞口透进来的冷光
	await _fade(DARK_ALPHA, 1.6)
	await _say("……至少淋不到雨。", 3.0)

	# 2:20 那张纸 —— 看得见有字，读不出来
	await _walk_to(paper.position.x + 10.0, 3.0)
	await _say("这上面……写了什么？", 3.0)

	# 2:30 坐下，听雨
	await _walk_to(mat.position.x + 40.0, 2.5)
	pet.size = Vector2(30, 32)
	pet.position.y = GROUND_Y - 32
	await _wait(2.5)

	print("《修仙小记》 今日避雨，误入一处旧洞。虽暗，尚可安身。")
	# 「勤修不辍……写得真好。」留到日后获得油灯时才兑现
	prologue_finished.emit()


# ============================================================
#  内景
# ============================================================
func _build_interior() -> void:
	for c in get_children():
		if c != fader and c != bubble and c != hint:
			c.queue_free()

	# 暗色调 —— 没有灯，只有洞口和圆窗透进来的冷光
	_block(Color(0.14, 0.13, 0.14), Vector2(W, H), Vector2.ZERO)
	_block(Color(0.18, 0.16, 0.16), Vector2(W, H - GROUND_Y), Vector2(0, GROUND_Y))
	_block(Color(0.42, 0.46, 0.50), Vector2(90, 150), Vector2(W - 160, GROUND_Y - 150))  # 洞口冷光
	_block(Color(0.34, 0.38, 0.42), Vector2(60, 60), Vector2(150, 130))                  # 圆窗雨光
	_block(Color(0.22, 0.20, 0.16), Vector2(22, 14), Vector2(520, GROUND_Y - 14))        # 破碗

	mat   = _block(Color(0.26, 0.24, 0.18), Vector2(110, 18), Vector2(380, GROUND_Y - 18))
	paper = _block(Color(0.30, 0.29, 0.25), Vector2(40, 56), Vector2(300, 190))          # 有字，但读不出

	pet = _block(Color(0.62, 0.60, 0.50), Vector2(30, 46), Vector2(560, GROUND_Y - 46))

	move_child(fader, get_child_count() - 1)
	move_child(bubble, get_child_count() - 1)


func _enter_cave() -> void:
	if _entered:
		return
	_entered = true
	_cave_clickable = false


# ============================================================
#  小工具
# ============================================================
func _walk_to(target_x: float, dur: float) -> void:
	var start := pet.position.x
	var t := 0.0
	while t < dur and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
		pet.position.x = lerpf(start, target_x, minf(t / dur, 1.0))
		_place_bubble()
	pet.position.x = target_x
	_skip = false


func _say(text: String, hold: float) -> void:
	bubble.text = text
	bubble.visible = true
	_place_bubble()
	if hold > 0.0:
		await _wait(hold)
		bubble.visible = false


func _place_bubble() -> void:
	bubble.position = Vector2(pet.position.x - 40.0, pet.position.y - 40.0)


func _nudge() -> void:
	# 缩一下 / 探个头，没有台词
	var base := pet.position.y
	for i in 2:
		pet.position.y = base + 4.0
		await _wait(0.12)
		pet.position.y = base
		await _wait(0.12)


func _fade(to_alpha: float, dur: float) -> void:
	var from := fader.color.a
	var t := 0.0
	while t < dur and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
		fader.color.a = lerpf(from, to_alpha, minf(t / dur, 1.0))
	fader.color.a = to_alpha
	_skip = false


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
	_skip = false


func _set_rain(on: bool) -> void:
	# TODO: 换成你现成的 weather layer
	print("[天气] 雨 = ", on)


# ============================================================
#  输入
# ============================================================
func _on_cave_input(event: InputEvent) -> void:
	if not _cave_clickable:
		return
	if event is InputEventMouseButton and event.pressed:
		_enter_cave()


func _on_cave_hover(inside: bool) -> void:
	if not _cave_clickable:
		return
	vines.modulate = Color(1.18, 1.18, 1.18) if inside else Color(1.06, 1.06, 1.06)


func _on_pet_input(event: InputEvent) -> void:
	# 1:00 玩家的第一次触碰
	if event is InputEventMouseButton and event.pressed and not _entered:
		_say("……嗯。", 1.8)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S:
				_skip = true
			KEY_ESCAPE:
				get_tree().quit()
