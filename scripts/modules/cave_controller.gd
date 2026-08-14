class_name CaveController
extends RefCounted

## 洞府显示层。只负责「把 FurnitureManager 说有的东西摆出来」，
## 不做任何解锁判断。
##
## 坐标全部走 cave_ui.anchor(id) —— 锚点归 CaveUi 管，
## 这里不再自己维护一份 ANCHORS，否则换背景图时两边会对不上。

const ACQUIRE_BUBBLE_SEC := 3.0

var main
var manager: FurnitureManager
var cave_ui                            # CaveUi
var _nodes: Dictionary = {}            # id -> Sprite2D


func _init(main_ref, manager_ref: FurnitureManager, cave_ui_ref) -> void:
	main = main_ref
	manager = manager_ref
	cave_ui = cave_ui_ref
	manager.furniture_unlocked.connect(_on_unlocked)
	manager.furniture_rebuilt.connect(_on_rebuilt)


func _root() -> Node2D:
	if cave_ui == null:
		return null
	return cave_ui.furniture_root


# ---------------------------------------------------------------- 摆放

func _spawn(def: Dictionary) -> void:
	var root: Node2D = _root()
	if root == null:
		return

	var fid: String = String(def["id"])
	if _nodes.has(fid):
		return

	# 没有就不出现：贴图不在，这件家具在游戏里不存在
	var path: String = String(def.get("icon_path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return

	var s := Sprite2D.new()
	s.name = fid
	s.texture = tex
	# 居中：锚点 = 家具的中心点，摆位好调，也不受贴图尺寸影响
	s.centered = true
	s.offset = Vector2(0.0, -float(tex.get_height()) * 0.5)
	s.position = cave_ui.anchor(String(def.get("anchor_id", "mat")))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(s)
	_nodes[fid] = s


func _clear_all() -> void:
	for fid in _nodes.keys():
		var n: Node = _nodes[fid]
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()


## 洞府面板打开时调一次，把已解锁的家具补齐。
## 面板是后建的，解锁可能发生在面板还没建好的时候。
func rebuild() -> void:
	_clear_all()
	for def in manager.owned_defs():
		_spawn(def)
	_sync_behaviour()
	_refresh_label()
	_place_pet()


## 有蒲团就坐蒲团上，没有就站原位。
## 这是 replaces_action 在视觉上的那一半 —— 动画换了，位置也得换。
func _place_pet() -> void:
	if cave_ui == null or cave_ui.pet_slot == null:
		return
	if manager.has("meditation_cushion"):
		# 往下挪几像素：y_sort 按 y 排序，他的 y 比蒲团大就会画在蒲团前面，
		# 看起来才像坐在上面而不是被蒲团盖住。
		cave_ui.pet_slot.position = cave_ui.anchor("cushion") + Vector2(0.0, 10.0)
	else:
		cave_ui.pet_slot.position = cave_ui.anchor("stand")


# ---------------------------------------------------------------- 信号

func _on_unlocked(def: Dictionary) -> void:
	_spawn(def)
	_play_acquire(def)
	_sync_behaviour()
	_place_pet()


func _on_rebuilt(owned_defs: Array) -> void:
	_clear_all()
	for def in owned_defs:
		_spawn(def)
	_sync_behaviour()
	_refresh_label()


## 获得演出：气泡 + 写进事件日志。
## 不弹窗、不加通知逻辑 —— 它只是一条普通事件。
##
## 注意：这里没有「走过去」。main.gd 目前没有 walk_to()，
## 而且洞府面板未必开着。等自主行为做出来再补走位。
func _play_acquire(def: Dictionary) -> void:
	var line: String = String(def.get("unlock_line", ""))
	var zh: String = String(def.get("name_zh", ""))

	if not line.is_empty():
		main.log_event(line)

	if main.has_method("add_recent_event"):
		main.add_recent_event(
			"洞府多了%s" % zh,
			"The cave gained: %s" % zh,
			"furniture",
			line,
			line,
			[]
		)

	_refresh_label()


# ---------------------------------------------------------------- 同步

func _sync_behaviour() -> void:
	# 行为池反向从已解锁物件生成。
	# behaviour_director 还没做（在两个月计划里），没有就跳过。
	var bd = main.get("behaviour_director")
	if bd == null or not bd.has_method("set_furniture_actions"):
		return
	bd.set_furniture_actions(manager.active_actions(), manager.replaced_actions())


## 木牌上的名字。由 Controller 决定显示什么，CaveUi 只负责画出来。
func _refresh_label() -> void:
	if cave_ui == null or cave_ui.panel == null or not cave_ui.panel.visible:
		return
	cave_ui.refresh(manager.cave_display_name())


# ---------------------------------------------------------------- 轮回

func on_reincarnate() -> void:
	manager.reset_for_reincarnation()

	if not manager.has_returning_sparrow():
		return
	# 雀还在屋顶上。新的小白不认得它。
	await main.get_tree().create_timer(2.0).timeout
	main.log_event("它是不是认错人了？")
