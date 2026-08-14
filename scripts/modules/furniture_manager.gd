class_name FurnitureManager
extends RefCounted

## 洞府家具解锁管理。
##
## 职责边界：
##   EventManager  只陈述「发生了什么」
##   FurnitureManager 决定「因此洞府多了什么」
##   CaveController   负责显示和行为池
##
## 核心规则：没有就不出现。
##   - CSV 里没有这一行 → 这件家具在游戏里不存在
##   - 贴图文件不存在   → 加载时跳过整行，只留一条 warning
##   - 条件无人认领     → set_condition_flag() 静默丢弃，不记 flag

signal furniture_unlocked(def: Dictionary)
signal furniture_rebuilt(owned_defs: Array)
const REALM_ORDER := ["fanren", "wuzhe", "xiantian", "lianqi"]
const CSV_PATH := "res://data/furniture.csv"
const CULTIVATE_STREAK_TARGET := 3
const NIGHT_AWAKE_TARGET_SEC := 30.0

var main

var _defs: Dictionary = {}           # id -> def(Dictionary)
var _by_condition: Dictionary = {}   # condition_id -> id
var _owned: Array[String] = []
var _flags: Dictionary = {}          # condition_id -> true
var _legacy: Dictionary = {}         # 跨轮回保留（雀等）


func _init(main_ref) -> void:
	main = main_ref
	_load_table()


# ---------------------------------------------------------------- 表加载

func _load_table() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_error("[furniture] 找不到 %s" % CSV_PATH)
		return

	var headers: PackedStringArray = file.get_csv_line()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() < headers.size():
			continue
		var fid: String = row[0].strip_edges()
		if fid.is_empty():
			continue

		var def: Dictionary = {}
		for i in headers.size():
			def[headers[i].strip_edges()] = row[i].strip_edges()

		# 没有就不出现：美术缺席 = 整行不存在
		var icon_path: String = String(def.get("icon_path", ""))
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			push_warning("[furniture] 跳过 %s — 缺贴图 %s" % [fid, icon_path])
			continue

		def["inherited"] = String(def.get("inherited", "false")).to_lower() == "true"
		_defs[fid] = def
		_by_condition[String(def["condition_id"])] = fid

	file.close()
	print("[furniture] 已加载 %d 件（表内 condition: %s）"
		% [_defs.size(), ", ".join(_by_condition.keys())])


# ---------------------------------------------------------------- 条件入口

## EventManager 的 event_resolved 信号接到这里。
## 只做一件事：把事件翻译成 condition flag。
func on_event_resolved(event_id: String, result: Dictionary) -> void:
	match event_id:
		"rain_outdoor":
			if bool(result.get("completed", false)):
				set_condition_flag("experienced_rain_outside")
		"name_cave":
			if not String(result.get("cave_name", "")).is_empty():
				set_condition_flag("cave_named_once")
		"sparrow_at_door":
			if String(result.get("choice_id", "")) == "share_food":
				set_condition_flag("fed_sparrow_once")
		"career_chosen":
			set_condition_flag("career_selected")
		"breakthrough_failed_major":
			set_condition_flag("first_major_grief")
		"npc_death":
			if int(result.get("relationship", 0)) >= 1:
				set_condition_flag("first_major_grief")


## 日结算的最后调用一次。计数类条件在这里判。
func on_day_end() -> void:
	var stats: Dictionary = _stats()
	if int(stats.get("cultivate_streak", 0)) >= CULTIVATE_STREAK_TARGET:
		set_condition_flag("cultivated_three_days")
	if float(stats.get("night_awake_sec", 0.0)) >= NIGHT_AWAKE_TARGET_SEC:
		set_condition_flag("stayed_awake_at_night")


func set_condition_flag(condition_id: String) -> void:
	# 没有就不出现：表里没人认领这个条件，连 flag 都不记
	if not _by_condition.has(condition_id):
		return
	if bool(_flags.get(condition_id, false)):
		return
	_flags[condition_id] = true
	_check_unlocks()


func _check_unlocks() -> void:
	for condition_id in _flags.keys():
		var fid: String = String(_by_condition.get(condition_id, ""))
		if fid.is_empty() or fid in _owned:
			continue
		var def: Dictionary = _defs[fid]
		if not _tier_ok(String(def.get("min_realm", "fanren"))):
			continue
		_owned.append(fid)
		furniture_unlocked.emit(def)


func _tier_ok(min_realm: String) -> bool:
	var need: int = REALM_ORDER.find(_to_slug(min_realm))
	if need < 0:
		return true   # CSV 写了没见过的值，不拦
	var cur: int = REALM_ORDER.find(_to_slug(String(main.current_tier())))
	return cur >= need

func _to_slug(realm: String) -> String:
	var r: String = realm.strip_edges()
	if r in REALM_ORDER:
		return r
	return String(GameConfig.TIER_ANIM_SUFFIX.get(r, "fanren"))

func _stats() -> Dictionary:
	if main.world_state == null:
		return {}
	return main.world_state.stats


# ---------------------------------------------------------------- 查询

func has(fid: String) -> bool:
	return fid in _owned

func owned_defs() -> Array:
	var out: Array = []
	for fid in _owned:
		out.append(_defs[fid])
	return out

## 空闲行为池反向从已解锁物件生成 —— 行为池里不要写 if has_furniture()
func active_actions() -> Array[String]:
	var replaced: Array[String] = []
	var actions: Array[String] = []
	for fid in _owned:
		var def: Dictionary = _defs[fid]
		var act: String = String(def.get("action_id", ""))
		var rep: String = String(def.get("replaces_action", ""))
		if not act.is_empty():
			actions.append(act)
		if not rep.is_empty():
			replaced.append(rep)
	for r in replaced:
		actions.erase(r)
	return actions

## 被家具顶替掉的旧动作（蒲团顶掉 meditate_ground）
func replaced_actions() -> Array[String]:
	var out: Array[String] = []
	for fid in _owned:
		var rep: String = String(_defs[fid].get("replaces_action", ""))
		if not rep.is_empty():
			out.append(rep)
	return out

func cave_display_name() -> String:
	# 没有木牌就是它本来的样子，不是占位
	var named: String = String(_legacy.get("cave_name_current", ""))
	if has("wooden_sign") and not named.is_empty():
		return named
	return "洞府"


# ---------------------------------------------------------------- 轮回

func reset_for_reincarnation() -> void:
	var kept: Array[String] = []
	for fid in _owned:
		if bool(_defs[fid].get("inherited", false)):
			kept.append(fid)
	_owned = kept

	# 条件 flag 全部重置，但继承物件的 flag 保留，避免重新播放初次台词
	var kept_flags: Dictionary = {}
	for fid in _owned:
		kept_flags[String(_defs[fid]["condition_id"])] = true
	_flags = kept_flags

	if has("sparrow"):
		_legacy["sparrow_bond"] = true

	_legacy["cave_name_current"] = ""
	furniture_rebuilt.emit(owned_defs())


## 转世后是否该播「它是不是认错人了？」
func has_returning_sparrow() -> bool:
	return bool(_legacy.get("sparrow_bond", false))


func set_cave_name(new_name: String) -> void:
	_legacy["cave_name_current"] = new_name


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"owned": _owned,
		"flags": _flags,
		"legacy": _legacy,
	}


func from_dict(data) -> void:
	# 老存档没有这个字段，安静地按空处理
	if typeof(data) != TYPE_DICTIONARY:
		_owned = []
		_flags = {}
		_legacy = {}
		return

	_flags = data.get("flags", {})
	_legacy = data.get("legacy", {})

	# 表可能已经变了（某件被删/贴图没了）→ 只恢复现在还存在的
	_owned = []
	for fid in data.get("owned", []):
		if _defs.has(String(fid)):
			_owned.append(String(fid))

	furniture_rebuilt.emit(owned_defs())
