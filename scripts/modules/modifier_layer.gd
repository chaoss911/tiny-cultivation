class_name ModifierLayer
extends RefCounted

# 视觉层：天气粒子 + 日夜色温 + 境界灵光。
# 不动任何动画资源，只在角色上下叠层。

var main

var _weather_particles: GPUParticles2D
var _aura: Sprite2D

## 会被日夜/天气染色的节点。只放"世界"，不放 UI。
## 用逐节点 modulate 而不是 CanvasModulate —— CanvasModulate 染整个 canvas layer，
## 面板、气泡、toast 跟角色同层，会一起变色。
var _tint_nodes: Array[CanvasItem] = []
var _current_tint: Color = Color.WHITE

## 室内（洞府里）：不下雨不下雪。屋顶是干的。
var indoor: bool = false
var _tween: Tween
var _tex_cache: Dictionary = {}

# 日夜色温。CLEAR 之外的天气会在此基础上再压一层。
const TIME_TINT := {
	WorldState.TimeBand.DAWN:    Color(0.82, 0.88, 1.00),
	WorldState.TimeBand.MORNING: Color(1.00, 1.00, 0.98),
	WorldState.TimeBand.NOON:    Color(1.00, 1.00, 1.00),
	WorldState.TimeBand.DUSK:    Color(1.00, 0.84, 0.68),
	WorldState.TimeBand.NIGHT:   Color(0.55, 0.62, 0.85),
}

# 天气对整体色调的乘算修正
const WEATHER_TINT := {
	WorldState.Weather.CLEAR:  Color(1.00, 1.00, 1.00),
	WorldState.Weather.CLOUDY: Color(0.88, 0.90, 0.92),
	WorldState.Weather.RAIN:   Color(0.74, 0.80, 0.88),
	WorldState.Weather.STORM:  Color(0.58, 0.63, 0.75),
	WorldState.Weather.SNOW:   Color(0.92, 0.95, 1.00),
	WorldState.Weather.FOG:    Color(0.86, 0.87, 0.86),
}

# tex：贴图种类；align：雨丝要顺着速度方向转，雪和雾不用
const PARTICLE_PRESETS := {
	WorldState.Weather.RAIN:  { "amount": 110, "gravity": Vector2(-40, 900),  "scale": 1.0, "lifetime": 0.9, "tex": "rain",  "align": true },
	WorldState.Weather.STORM: { "amount": 240, "gravity": Vector2(-160, 1200),"scale": 1.4, "lifetime": 0.7, "tex": "rain",  "align": true },
	WorldState.Weather.SNOW:  { "amount": 60,  "gravity": Vector2(10, 60),    "scale": 1.0, "lifetime": 5.0, "tex": "snow",  "align": false },
	WorldState.Weather.FOG:   { "amount": 20,  "gravity": Vector2(12, 0),     "scale": 2.2, "lifetime": 8.0, "tex": "fog",   "align": false },
}

# 粒子从角色上方多高处开始落。
# 桌宠窗口小，这个值给大了粒子会全落在窗口外面 —— 320 就太高了。
# 世界层节点名单（在 root 下按名字找，找不到的静默跳过）
const TINT_TARGET_NAMES := ["CultivatorSprite", "wuzhe", "PropAnchor", "CaveAnchor"]

const EMIT_HEIGHT := 80.0
const EMIT_WIDTH := 220.0

# 调试用：开了之后粒子又大又多又不透明，先确认"到底有没有在发射"。
# 确认看得见之后改回 false，再慢慢调 EMIT_HEIGHT / EMIT_WIDTH / scale。
const DEBUG_PARTICLES := false


func _init(p_main) -> void:
	main = p_main


## 在 Main._ready() 里调一次。root 传 $PetGroup（角色所在的那个 Node2D）。
##
## 不再使用 CanvasModulate：它染的是整个 canvas layer，而 SpeechLabel / StatusLabel /
## VBox / 各种面板都跟角色同层，夜里会一起变蓝。改成只给名单里的世界节点逐个上 modulate。
func setup(root: Node2D) -> void:
	_tint_nodes.clear()
	for n in TINT_TARGET_NAMES:
		var node := root.get_node_or_null(NodePath(n)) as CanvasItem
		if node != null:
			_tint_nodes.append(node)

	_weather_particles = GPUParticles2D.new()
	_weather_particles.name = "WeatherParticles"
	_weather_particles.emitting = false
	_weather_particles.z_index = 0             # 不靠 z_index，靠树顺序（见 _order_particles）
	_weather_particles.local_coords = false
	_weather_particles.process_material = _make_particle_material()
	_weather_particles.position = Vector2(0, -EMIT_HEIGHT)   # 从角色上方落下来
	root.add_child(_weather_particles)

	_aura = Sprite2D.new()
	_aura.name = "RealmAura"
	_aura.z_index = -1                          # 垫在角色后面
	_aura.visible = false
	root.add_child(_aura)
	_tint_nodes.append(_aura)

	_order_particles(root)


## 之后才生成的世界节点（洞府家具等）用这个加进来，让它也跟着日夜变色。
func add_tint_target(node: CanvasItem) -> void:
	if node == null or node in _tint_nodes:
		return
	_tint_nodes.append(node)
	node.modulate = _current_tint


## 把粒子插到「角色之后、UI 之前」。
## 同一 z_index 下，树里越靠后画得越上面 —— 比 z_index 可靠，不会被别处代码改掉。
func _order_particles(root: Node2D) -> void:
	if _weather_particles == null:
		return
	_weather_particles.z_index = 0
	_weather_particles.z_as_relative = true

	# 找最后一个角色精灵（CultivatorSprite / wuzhe）
	var last_sprite: int = -1
	for i in root.get_child_count():
		if root.get_child(i) is AnimatedSprite2D:
			last_sprite = i
	if last_sprite >= 0:
		root.move_child(_weather_particles, last_sprite + 1)

	# 诊断：实际绘制顺序，从下到上
	print("[粒子层] PetGroup 绘制顺序（越下面 = 画得越上面）：")
	for i in root.get_child_count():
		var c: Node = root.get_child(i)
		var z: int = (c as CanvasItem).z_index if c is CanvasItem else 0
		print("   ", i, "  ", c.name, "   z_index=", z)


## 挂到 WorldState.context_changed 上
func apply(state: WorldState, instant: bool = false) -> void:
	_apply_tint(state, instant)
	_apply_weather(state)
	_apply_aura(state)


# ---------------------------------------------------------------- 内部

func _apply_tint(state: WorldState, instant: bool) -> void:
	var base: Color = TIME_TINT.get(state.time_band, Color.WHITE)
	var wx: Color = WEATHER_TINT.get(state.weather, Color.WHITE)
	var target := Color(base.r * wx.r, base.g * wx.g, base.b * wx.b, 1.0)
	_current_tint = target

	# 清掉已经被释放的节点（换境界换 sprite 时会有）
	_tint_nodes = _tint_nodes.filter(func(n): return is_instance_valid(n))
	if _tint_nodes.is_empty():
		return

	if instant:
		for n in _tint_nodes:
			n.modulate = target
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = _tint_nodes[0].create_tween()
	_tween.set_parallel(true)
	# 时段切换要慢，玩家不该"看到"它变，只该发现它已经变了
	for n in _tint_nodes:
		_tween.tween_property(n, "modulate", target, 3.0)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 进出洞府时调。室内直接停掉粒子，不改 world_state 的天气本身 ——
## 外面还在下，只是你在屋里看不到。
func set_indoor(v: bool) -> void:
	if indoor == v:
		return
	indoor = v
	if _weather_particles != null and indoor:
		_weather_particles.emitting = false
		_weather_particles.visible = false
	elif _weather_particles != null:
		_weather_particles.visible = true


func _apply_weather(state: WorldState) -> void:
	if indoor:
		if _weather_particles != null:
			_weather_particles.emitting = false
		return

	if _weather_particles == null:
		return
	if not PARTICLE_PRESETS.has(state.weather):
		_weather_particles.emitting = false
		return

	var p: Dictionary = PARTICLE_PRESETS[state.weather]
	var mat := _weather_particles.process_material as ParticleProcessMaterial
	if mat != null:
		mat.gravity = Vector3(p["gravity"].x, p["gravity"].y, 0.0)
		mat.scale_min = float(p["scale"]) * 0.7
		mat.scale_max = float(p["scale"]) * 1.3
		# 雨丝顺着速度方向拉长，不然是一根根竖着的短棍
		mat.particle_flag_align_y = bool(p["align"])
	# ★ 关键：没贴图的话 GPUParticles2D 只画一个默认的极小方块
	_weather_particles.texture = _tex(str(p["tex"]))
	_weather_particles.amount = int(p["amount"])
	_weather_particles.lifetime = float(p["lifetime"])
	_weather_particles.emitting = true

	if DEBUG_PARTICLES:
		if mat != null:
			mat.scale_min = float(p["scale"]) * 2.5
			mat.scale_max = float(p["scale"]) * 4.0
		_weather_particles.amount = int(p["amount"]) * 2
		_weather_particles.modulate = Color(1, 0.2, 0.2, 1.0)   # 染红，一眼看出在哪
		var tex_size: Vector2 = _weather_particles.texture.get_size() if _weather_particles.texture != null else Vector2.ZERO
		print("[粒子] 天气=", p["tex"],
			"  节点位置=", _weather_particles.position,
			"  全局=", _weather_particles.global_position,
			"  贴图=", tex_size,
			"  数量=", _weather_particles.amount,
			"  emitting=", _weather_particles.emitting)
	else:
		# 跟着日夜色调走，别硬设成纯白（否则夜里雨是亮的）
		_weather_particles.modulate = _current_tint


func _apply_aura(state: WorldState) -> void:
	if _aura == null:
		return
	# 凡人不发光 —— 留白，让后面境界的灵光有对比
	if state.realm_slug == "fanren":
		_aura.visible = false
		return
	var path: String = "res://assets/aura/%s.png" % state.realm_slug
	if ResourceLoader.exists(path):
		_aura.texture = load(path)
		_aura.visible = true
	else:
		_aura.visible = false


func _make_particle_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 8.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 60.0
	mat.gravity = Vector3(0, 900, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(EMIT_WIDTH, 4, 1)
	return mat


# ---------------------------------------------------------------- 粒子贴图（代码生成，不占美术工时）

func _tex(kind: String) -> Texture2D:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var t: Texture2D
	match kind:
		"rain": t = _make_streak(5, 34, Color(0.80, 0.88, 1.00), 0.75)
		"snow": t = _make_dot(16, Color(1.00, 1.00, 1.00), 0.95, 1.8)
		"fog":  t = _make_dot(96, Color(0.92, 0.93, 0.94), 0.16, 1.1)
		_:      t = _make_dot(8, Color.WHITE, 0.8, 2.0)
	_tex_cache[kind] = t
	return t


## 雨丝：竖直细条，两端淡中间实
func _make_streak(w: int, h: int, color: Color, peak_alpha: float) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var half: float = maxf(float(w - 1) * 0.5, 0.001)
	for y in h:
		var ty: float = float(y) / float(maxi(h - 1, 1))
		var a_y: float = sin(ty * PI)                    # 两端渐隐
		for x in w:
			var cx: float = absf(float(x) - half) / half
			var a_x: float = clampf(1.0 - cx * cx, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a_y * a_x * peak_alpha))
	return ImageTexture.create_from_image(img)


## 雪花 / 雾团：径向柔边圆点。falloff 越大边缘越锐。
func _make_dot(size: int, color: Color, peak_alpha: float, falloff: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c: float = float(size - 1) * 0.5
	var r: float = maxf(c, 0.001)
	for y in size:
		for x in size:
			var d: float = Vector2(float(x) - c, float(y) - c).length() / r
			var a: float = clampf(1.0 - pow(clampf(d, 0.0, 1.0), falloff), 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a * peak_alpha))
	return ImageTexture.create_from_image(img)
