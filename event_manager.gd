extends Node
class_name EventManager

# ════════════════════════════════════════════════════════════════════
#  EventManager — Tiny Cultivation Random Event System (+ Encounters)
#
#  Normal events come from events.csv (no rarity column = normal).
#  Rare/legendary ENCOUNTERS come from encounters.csv (rarity column).
#  On each tick, the manager first rolls RARITY (luck-scaled), then
#  picks a weighted event of that rarity matching the current state.
# ════════════════════════════════════════════════════════════════════

signal event_fired(event: Dictionary)
signal log_updated()
signal encounter_fired(event: Dictionary)     # rare/legendary only
signal story_moment_created(moment: Dictionary)
signal event_resolved(event_id: String, result: Dictionary)   # 事件结算完毕（家具/成就等下游系统监听）
const EVENTS_PATH := "res://data/events.csv"
const ENCOUNTERS_PATH := "res://data/encounters.csv"
const LOG_CAP := 50
const MIN_INTERVAL := 60.0
const MAX_INTERVAL := 120.0


# ── RARITY PROBABILITY (central config — tune here) ──
# Per-event chance, before luck. Legendary is deliberately tiny so a
# normal idle player sees ~1 legendary per 3–5 hours (~120–200 events).
const LEGENDARY_BASE := 0.005    # 0.5%
const RARE_BASE      := 0.08     # 8%
# Luck scaling: luck is 1..100. We map it to a multiplier on the bases.
# luck 50 = neutral (x1). Low luck shrinks, high luck grows, clamped.
const LEGENDARY_MIN := 0.003     # floor 0.3%
const LEGENDARY_MAX := 0.010     # cap 1.0%
const RARE_MIN := 0.06           # floor 6%
const RARE_MAX := 0.14           # cap 14%

# normal events
var events: Array = []
var events_by_type: Dictionary = {}

# encounters by rarity then type: encounters_by_rarity["rare"]["cultivate"] = [...]
var encounters_by_rarity: Dictionary = {"rare": {}, "legendary": {}}
var all_encounter_ids: Array = []          # for "discover all legendary" totals
var legendary_ids: Array = []

var event_log: Array = []

var paused := false

func set_paused(p: bool) -> void:
	paused = p

var realm_provider: Callable             # func () -> int (current realm_index)
var state_provider: Callable
var reward_handler: Callable
var bubble_handler: Callable               # func (zh, en, rarity)  — rarity-aware
var lang_provider: Callable

# Optional hooks
var achievement_hook: Callable             # func (event)
var stats_hook: Callable
var history_hook: Callable
var luck_provider: Callable                # func () -> int (1..100)
var encounter_handler: Callable            # func (event) — host does toast/milestone/stats
var special_animation_handler: Callable     # func (anim_key: String)

var _timer_active := false


func setup(p_state: Callable, p_reward: Callable, p_bubble: Callable, p_lang: Callable) -> void:
	state_provider = p_state
	reward_handler = p_reward
	bubble_handler = p_bubble
	lang_provider  = p_lang
	load_events()
	load_encounters()
	_schedule_next()


# ──────────────────────────────────────────────────────────
#  CSV LOADING
# ──────────────────────────────────────────────────────────

func load_events() -> void:
	events.clear()
	events_by_type.clear()
	var file := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if file == null:
		push_warning("events.csv not found")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0:
			continue
		if is_header:
			is_header = false
			continue
		if cols.size() < 7:
			continue
		# events.csv schema: event_id,event_type,weight,text_zh,text_en,reward_type,reward_value,min_realm,special_animation,biography_importance
		var min_realm := 0
		if cols.size() > 7 and String(cols[7]).strip_edges() != "":
			min_realm = int(cols[7])
		var special_animation := ""
		if cols.size() > 8:
			special_animation = String(cols[8]).strip_edges()
		var biography_importance := "normal"
		if cols.size() > 9 and String(cols[9]).strip_edges() != "":
			biography_importance = String(cols[9]).strip_edges()
		var row := {
			"event_id":     cols[0].strip_edges(),
			"event_type":   cols[1].strip_edges(),
			"rarity":       "normal",
			"weight":       max(1, int(cols[2])),
			"text_zh":      cols[3].strip_edges(),
			"text_en":      cols[4].strip_edges(),
			"reward_type":  cols[5].strip_edges(),
			"reward_value": int(cols[6]),
			"min_realm":    min_realm,
			"special_animation": special_animation,
			"biography_importance": biography_importance
		}
		events.append(row)
		if not events_by_type.has(row["event_type"]):
			events_by_type[row["event_type"]] = []
		events_by_type[row["event_type"]].append(row)
	file.close()
	print("EventManager loaded %d normal events" % events.size())

func load_encounters() -> void:
	encounters_by_rarity = {"rare": {}, "legendary": {}}
	all_encounter_ids.clear()
	legendary_ids.clear()
	var file := FileAccess.open(ENCOUNTERS_PATH, FileAccess.READ)
	if file == null:
		push_warning("encounters.csv not found")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0:
			continue
		if is_header:
			is_header = false
			continue
		if cols.size() < 9:
			continue

		var rarity := cols[2].strip_edges()
		if not (rarity == "rare" or rarity == "legendary"):
			continue
		var row := {
			"event_id":     cols[0].strip_edges(),
			"event_type":   cols[1].strip_edges(),
			"rarity":       rarity,
			"min_realm":    max(0, int(cols[3])),
			"weight":       max(1, int(cols[4])),
			"text_zh":      cols[5].strip_edges(),
			"text_en":      cols[6].strip_edges(),
			"reward_type":  cols[7].strip_edges(),
			"reward_value": int(cols[8])
		}
		var bucket: Dictionary = encounters_by_rarity[rarity]
		if not bucket.has(row["event_type"]):
			bucket[row["event_type"]] = []
		bucket[row["event_type"]].append(row)
		all_encounter_ids.append(row["event_id"])
		if rarity == "legendary":
			legendary_ids.append(row["event_id"])
	file.close()
	print("EventManager loaded %d encounters (%d legendary)" % [all_encounter_ids.size(), legendary_ids.size()])


# ──────────────────────────────────────────────────────────
#  TIMING
# ──────────────────────────────────────────────────────────

func _schedule_next() -> void:
	if _timer_active:
		return
	_timer_active = true
	var wait := randf_range(MIN_INTERVAL, MAX_INTERVAL)
	var t := get_tree().create_timer(wait)
	t.timeout.connect(func ():
		_timer_active = false
		trigger_event()
		_schedule_next()
	)


# ──────────────────────────────────────────────────────────
#  RARITY ROLL (luck-scaled)
# ──────────────────────────────────────────────────────────

func _luck() -> int:
	if luck_provider.is_valid():
		return int(luck_provider.call())
	return 50


# Maps luck 1..100 to a 0..1 factor where 50 -> 0.5
func _luck_factor() -> float:
	return clampf(float(_luck()) / 100.0, 0.0, 1.0)


func _legendary_chance() -> float:
	# lerp from MIN (luck 0) through ~BASE (luck 50) to MAX (luck 100)
	return lerpf(LEGENDARY_MIN, LEGENDARY_MAX, _luck_factor())


func _rare_chance() -> float:
	return lerpf(RARE_MIN, RARE_MAX, _luck_factor())


func _roll_rarity() -> String:
	var r := randf()
	if r < _legendary_chance():
		return "legendary"
	if r < _legendary_chance() + _rare_chance():
		return "rare"
	return "normal"


# ──────────────────────────────────────────────────────────
#  TRIGGERING
# ──────────────────────────────────────────────────────────

func _realm() -> int:
	if realm_provider.is_valid():
		return int(realm_provider.call())
	return 0

func trigger_event() -> void:
	if paused:
		return
	if not state_provider.is_valid():
		return
	var state: String = state_provider.call()
	var rarity := _roll_rarity()

	var pool: Array = []
	if rarity == "normal":
		pool = events_by_type.get(state, [])
		if pool.is_empty():
			for k in events_by_type:
				pool += events_by_type[k]
		var cur_realm := _realm()
		pool = pool.filter(func(r): return int(r.get("min_realm", 0)) <= cur_realm)
		if pool.is_empty():
			return   # 这个境界还没有任何可用的普通事件，安静跳过这次触发
	else:
		var bucket: Dictionary = encounters_by_rarity.get(rarity, {})
		pool = bucket.get(state, [])
		if pool.is_empty():
			for k in bucket:
				pool += bucket[k]
		# Gate by realm: drop encounters whose min_realm exceeds current realm
		var cur_realm := _realm()
		pool = pool.filter(func(r): return int(r.get("min_realm", 0)) <= cur_realm)
		# if still empty (nothing unlocked at this realm), fall back to normal
		if pool.is_empty():
			rarity = "normal"
			pool = events_by_type.get(state, [])

	if pool.is_empty():
		return
	var row: Dictionary = _weighted_pick(pool)
	if row.is_empty():
		return
	_apply_event(row)


func _weighted_pick(pool: Array) -> Dictionary:
	var total := 0
	for row in pool:
		total += row["weight"]
	if total <= 0:
		return {}
	var roll := randi() % total
	var acc := 0
	for row in pool:
		acc += row["weight"]
		if roll < acc:
			return row
	return pool.back()


func _apply_event(row: Dictionary) -> void:
	var rarity: String = row.get("rarity", "normal")
	var moment := {
	"type": "event",
	"event_id": row["event_id"],
	"event_type": row["event_type"],
	"rarity": rarity,
	"tags": [row["event_type"], rarity],
	"text_zh": row["text_zh"],
	"text_en": row["text_en"],
	"importance": row.get("biography_importance", "normal"),
	"animation": row.get("special_animation", "")
}
	story_moment_created.emit(moment)

	# 1. Reward
	if row["reward_type"] != "none" and row["reward_value"] != 0:
		if reward_handler.is_valid():
			reward_handler.call(row["reward_type"], row["reward_value"])

	# 2. Bubble (rarity-aware so host can pick 💭 / ✨ / 🌟)
	if bubble_handler.is_valid():
		bubble_handler.call(row["text_zh"], row["text_en"], rarity)
	# 3. 特殊动画（交给宿主播放）
	var special_anim: String = String(row.get("special_animation", ""))
	if special_anim != "" and special_animation_handler.is_valid():
		special_animation_handler.call(special_anim)
	var importance: String = String(row.get("biography_importance", "normal"))
	if importance != "normal" and history_hook.is_valid():
		history_hook.call(row)

	# 3. Log
	_add_to_log(row)

# 4. Signals + hooks
	event_fired.emit(row)
	if achievement_hook.is_valid(): achievement_hook.call(row)
	if stats_hook.is_valid():       stats_hook.call(row)
	

	# 5. Encounter-specific routing (toast / milestone / stats handled by host)
	if rarity == "rare" or rarity == "legendary":
		encounter_fired.emit(row)
		if encounter_handler.is_valid():
			encounter_handler.call(row)

	# 6. 结算完毕 —— 唯一的 emit 点，必须放在最后一行
	#    上面所有状态（奖励、日志、动画、hook）都已经落定，
	#    下游系统（FurnitureManager 等）读到的 result 才是最终值。
	_emit_resolved(row)


## 唯一的结算出口。以后如果事件多了几种结束分支（跳过 / 动画结束 / 玩家选择），
## 都收到这里来 emit，不要在别处再 emit 一次 —— 否则获得台词会播两遍。
func _emit_resolved(row: Dictionary) -> void:
	var result := {
		"completed":    true,
		"event_type":   String(row.get("event_type", "")),
		"rarity":       String(row.get("rarity", "normal")),
		"reward_type":  String(row.get("reward_type", "none")),
		"reward_value": int(row.get("reward_value", 0)),
	}
	event_resolved.emit(String(row.get("event_id", "")), result)


# ──────────────────────────────────────────────────────────
#  LOG
# ──────────────────────────────────────────────────────────

func _add_to_log(row: Dictionary) -> void:
	event_log.append({
		"time":     Time.get_time_string_from_system().substr(0, 5),
		"event_id": row["event_id"],
		"text_zh":  row["text_zh"],
		"text_en":  row["text_en"],
		"rarity":   row.get("rarity", "normal")
	})
	while event_log.size() > LOG_CAP:
		event_log.pop_front()
	log_updated.emit()


func get_log_lines() -> Array:
	var lang := "zh"
	if lang_provider.is_valid():
		lang = lang_provider.call()
	var out: Array = []
	for i in range(event_log.size() - 1, -1, -1):
		var e = event_log[i]
		var icon := "💭"
		match e.get("rarity", "normal"):
			"rare": icon = "✨"
			"legendary": icon = "🌟"
		var text: String = e["text_zh"] if lang == "zh" else e["text_en"]
		out.append("%s %s  %s" % [e["time"], icon, text])
	return out


# Totals for the encounter codex
func total_encounters() -> int:
	return all_encounter_ids.size()


func total_legendary() -> int:
	return legendary_ids.size()


# Returns all encounter defs (for codex display), rare first then legendary
func get_all_encounter_defs() -> Array:
	var out: Array = []
	for rarity in ["rare", "legendary"]:
		var bucket: Dictionary = encounters_by_rarity[rarity]
		for k in bucket:
			for row in bucket[k]:
				out.append(row)
	return out


# ────────────────────────────────────	x──────────────────────
#  SAVE / LOAD  (event log only; encounter discovery lives in host)
# ──────────────────────────────────────────────────────────

func to_save() -> Array:
	return event_log


func from_save(data) -> void:
	if typeof(data) == TYPE_ARRAY:
		event_log = data
		while event_log.size() > LOG_CAP:
			event_log.pop_front()
		log_updated.emit()
