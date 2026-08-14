class_name ModifierDebugPanel
extends Control

# 调试面板：手动切天气/时辰/心情，不用等游戏内时间过。
# 用法：把这个脚本挂到一个 Control 上，加进场景，调 bind(world_state)。
# 快捷键 F8 或 Ctrl+D 开关，面板右上角也有关闭按钮。
# macOS 的 F9 被 Mission Control 占用，所以不用 F9。
# 发版前用 OS.is_debug_build() 挡住就行。

const TOGGLE_KEY := KEY_F8
const NODE_NAME := "ModifierDebugPanel"

var world_state: WorldState

var _weather_btn: OptionButton
var _time_btn: OptionButton
var _temper_btn: OptionButton
var _coverage_label: RichTextLabel


func _ready() -> void:
	# 防重复：同一个父节点下已经有一个了就自杀。
	# 两个实例会交替开关 —— 按一次两个一起翻转，看起来就是"永远关不掉"。
	var p: Node = get_parent()
	if p != null:
		for sib in p.get_children():
			if sib != self and sib is ModifierDebugPanel:
				print("[修饰符面板] 已存在实例，本次创建作废")
				queue_free()
				return
	name = NODE_NAME

	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 12)
	z_index = 400          # 压在所有面板之上，不然被证书/报纸盖住会以为没开
	top_level = true
	visible = false
	set_process_input(true)
	_build_ui()


func bind(p_state: WorldState) -> void:
	# UI 没建起来 = 这是被防重复作废的实例，不要接线
	if _weather_btn == null or is_queued_for_deletion():
		return
	world_state = p_state
	if world_state != null:
		if not world_state.context_changed.is_connected(_sync_from_state):
			world_state.context_changed.connect(_sync_from_state)
		_sync_from_state()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == TOGGLE_KEY or (k.keycode == KEY_D and k.ctrl_pressed):
		toggle()
		get_viewport().set_input_as_handled()   # 吃掉，别让游戏也收到


func toggle() -> void:
	visible = not visible
	# 按了没反应就看这行有没有打印；实例数不是 1 就是创建了多个
	var count: int = 0
	if get_parent() != null:
		for sib in get_parent().get_children():
			if sib is ModifierDebugPanel:
				count += 1
	print("[修饰符面板] ", "开" if visible else "关", "  实例数=", count)
	if visible:
		_refresh_coverage()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var panel := PanelContainer.new()
	add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(260, 0)
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	# 标题行 + 关闭按钮（快捷键被系统吞掉时的后路）
	var head := HBoxContainer.new()
	box.add_child(head)

	var title := Label.new()
	title.text = "修饰符调试  (F8 / Ctrl+D)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.pressed.connect(toggle)
	head.add_child(close_btn)

	_weather_btn = _add_row(box, "天气", ["晴", "阴", "雨", "暴雨", "雪", "雾"])
	_weather_btn.item_selected.connect(func(i: int) -> void:
		if world_state != null:
			world_state.debug_override = true
			world_state.force_weather(i))

	_time_btn = _add_row(box, "时辰", ["拂晓", "上午", "正午", "黄昏", "夜"])
	_time_btn.item_selected.connect(func(i: int) -> void:
		if world_state != null:
			world_state.debug_override = true
			world_state.force_time_band(i))

	_temper_btn = _add_row(box, "心境", ["低落", "平静", "愉悦"])
	_temper_btn.item_selected.connect(func(i: int) -> void:
		if world_state != null:
			world_state.force_temper(i))

	box.add_child(HSeparator.new())

	var cov_title := Label.new()
	cov_title.text = "组合覆盖率"
	box.add_child(cov_title)

	_coverage_label = RichTextLabel.new()
	_coverage_label.custom_minimum_size = Vector2(0, 140)
	_coverage_label.bbcode_enabled = true
	_coverage_label.scroll_active = true
	box.add_child(_coverage_label)

	var release := Button.new()
	release.text = "恢复自动推进"
	release.pressed.connect(func() -> void:
		if world_state != null:
			world_state.debug_override = false)
	box.add_child(release)

	var refresh := Button.new()
	refresh.text = "刷新统计"
	refresh.pressed.connect(_refresh_coverage)
	box.add_child(refresh)


func _add_row(parent: VBoxContainer, label_text: String, options: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(48, 0)
	row.add_child(lbl)

	var btn := OptionButton.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for o in options:
		btn.add_item(str(o))
	row.add_child(btn)
	return btn


func _sync_from_state() -> void:
	if world_state == null or _weather_btn == null or _time_btn == null or _temper_btn == null:
		return
	_weather_btn.select(world_state.weather)
	_time_btn.select(world_state.time_band)
	_temper_btn.select(world_state.temper)


func _refresh_coverage() -> void:
	if world_state == null or _coverage_label == null:
		return
	var hits: Dictionary = world_state.combo_hits
	var total_possible: int = 6 * 5 * 3   # 天气 × 时辰 × 心情（单一境界）
	var seen: int = hits.size()

	var keys: Array = hits.keys()
	keys.sort_custom(func(a, b) -> bool: return int(hits[a]) > int(hits[b]))

	var text: String = "[b]已出现 %d / %d[/b]\n" % [seen, total_possible]
	var shown: int = 0
	for k in keys:
		text += "%s  ×%d\n" % [k, int(hits[k])]
		shown += 1
		if shown >= 20:
			text += "…\n"
			break
	_coverage_label.text = text
