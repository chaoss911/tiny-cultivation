class_name WorldState
extends RefCounted

# 修饰符系统的唯一状态源。
# 时辰取【真实系统时间】—— 桌宠就该跟着玩家的作息走，你熬夜他也熬夜。
# 天气按游戏内天数定种，同一天读档不变天。

signal weather_changed(new_weather: int)
signal time_band_changed(new_band: int)
signal temper_changed(new_temper: int)
signal context_changed()
var stats := {
	"rain_soaked": 0,
	"cultivate_streak": 0,
	"night_awake_sec": 0.0,
}
enum Weather { CLEAR, CLOUDY, RAIN, STORM, SNOW, FOG }
enum TimeBand { DAWN, MORNING, NOON, DUSK, NIGHT }
enum Temper { LOW, NEUTRAL, HIGH }   # 改名 Temper，避免跟 main.set_mood() 的动画 mood 混淆

const WEATHER_TAG := {
	Weather.CLEAR: "clear", Weather.CLOUDY: "cloudy", Weather.RAIN: "rain",
	Weather.STORM: "storm", Weather.SNOW: "snow", Weather.FOG: "fog",
}
const TIME_TAG := {
	TimeBand.DAWN: "dawn", TimeBand.MORNING: "morning", TimeBand.NOON: "noon",
	TimeBand.DUSK: "dusk", TimeBand.NIGHT: "night",
}
const TEMPER_TAG := { Temper.LOW: "low", Temper.NEUTRAL: "neutral", Temper.HIGH: "high" }

# 天气权重，key 用你 GameConfig.TIER_ANIM_SUFFIX 的中文境界名
const WEATHER_WEIGHTS := {
	"凡人": { Weather.CLEAR: 42, Weather.CLOUDY: 26, Weather.RAIN: 20, Weather.FOG: 10, Weather.STORM: 1, Weather.SNOW: 1 },
	"武者": { Weather.CLEAR: 32, Weather.CLOUDY: 25, Weather.RAIN: 21, Weather.FOG: 12, Weather.STORM: 6, Weather.SNOW: 4 },
	"先天": { Weather.CLEAR: 26, Weather.CLOUDY: 21, Weather.RAIN: 20, Weather.FOG: 14, Weather.STORM: 11, Weather.SNOW: 8 },
	"炼气": { Weather.CLEAR: 22, Weather.CLOUDY: 18, Weather.RAIN: 19, Weather.FOG: 15, Weather.STORM: 15, Weather.SNOW: 11 },
}

const TIME_BANDS := [
	{ "band": TimeBand.DAWN,    "from": 4,  "to": 7 },
	{ "band": TimeBand.MORNING, "from": 7,  "to": 11 },
	{ "band": TimeBand.NOON,    "from": 11, "to": 16 },
	{ "band": TimeBand.DUSK,    "from": 16, "to": 19 },
	{ "band": TimeBand.NIGHT,   "from": 19, "to": 4 },
]

var main

var weather: int = Weather.CLEAR
var time_band: int = TimeBand.MORNING
var temper: int = Temper.NEUTRAL
var realm_tier: String = "凡人"          # 中文，跟 main.current_tier() 一致
var realm_slug: String = "fanren"        # 拼音，给 CSV 和资源路径用

var _temper_value: float = 0.0
var _current_day: int = -1
var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0
var debug_override: bool = false          # debug 面板强制状态时暂停自动推进

var combo_hits: Dictionary = {}

const RAIN_SOAK_SEC := 20.0
var _rain_sec: float = 0.0
var _rain_credited_day: int = -1


func _init(p_main) -> void:
	main = p_main

## 是否夜里。直接读 time_band —— 不要另写一套小时判断，
## 否则 force_time_band() 和 debug 面板会跟它对不上。
func is_night() -> bool:
	return time_band == TimeBand.NIGHT


## 小白是否在睡。main 上没有 is_sleeping 变量，看动画名最稳。
func _is_sleeping() -> bool:
	if main == null:
		return false
	var spr = main.get("cultivator_sprite")
	if spr == null:
		return false
	return String(spr.animation).ends_with("_sleeping")
# ---------------------------------------------------------------- 每帧调用（内部自己节流）

## Main._process 里调：world_state.tick(delta, _day_counter, current_tier())
func tick(delta: float, day_counter: int, tier: String) -> void:
	_accum += delta
	if _accum < 1.0:          # 每秒才真正算一次，别每帧 hash
		return
	var elapsed: float = _accum
	_accum = 0.0

	_tick_stats(elapsed, day_counter)

	var changed: bool = false

	if tier != realm_tier:
		realm_tier = tier
		realm_slug = str(GameConfig.TIER_ANIM_SUFFIX.get(tier, "fanren"))
		changed = true

	if not debug_override:
		if day_counter != _current_day:
			_current_day = day_counter
			var rolled: int = _roll_weather(day_counter)
			if rolled != weather:
				weather = rolled
				weather_changed.emit(weather)
				changed = true

		var band: int = _band_for_hour(Time.get_datetime_dict_from_system()["hour"])
		if band != time_band:
			time_band = band
			time_band_changed.emit(time_band)
			changed = true

	if absf(_temper_value) > 0.01:
		_temper_value = move_toward(_temper_value, 0.0, elapsed * 0.5)
		var t: int = _temper_from_value(_temper_value)
		if t != temper:
			temper = t
			temper_changed.emit(temper)
			changed = true

	if changed:
		_note_combo()
		context_changed.emit()


# ---------------------------------------------------------------- 计数器（给家具解锁用）

## 每秒调一次。只累加 world_state 自己知道的东西；
## cultivate_streak 属于日结算，放 life_cycle 里加。
func _tick_stats(elapsed: float, day_counter: int) -> void:
	if is_night() and not _is_sleeping():
		stats.night_awake_sec = float(stats.get("night_awake_sec", 0.0)) + elapsed

	# 淋雨：连续待满 RAIN_SOAK_SEC 才算一次，每天最多记一次
	if weather == Weather.RAIN or weather == Weather.STORM:
		_rain_sec += elapsed
		if _rain_sec >= RAIN_SOAK_SEC and _rain_credited_day != day_counter:
			_rain_credited_day = day_counter
			stats.rain_soaked = int(stats.get("rain_soaked", 0)) + 1
	else:
		_rain_sec = 0.0


# ---------------------------------------------------------------- 外部写入

## 事件结算时调：好事传正数，坏事传负数。约 2 分钟回归平静。
func adjust_temper(delta: float) -> void:
	_temper_value = clampf(_temper_value + delta, -100.0, 100.0)
	var t: int = _temper_from_value(_temper_value)
	if t != temper:
		temper = t
		temper_changed.emit(temper)
		_note_combo()
		context_changed.emit()


func force_weather(w: int) -> void:
	if w == weather: return
	weather = w
	weather_changed.emit(weather)
	_note_combo()
	context_changed.emit()


func force_time_band(b: int) -> void:
	if b == time_band: return
	time_band = b
	time_band_changed.emit(time_band)
	_note_combo()
	context_changed.emit()


func force_temper(t: int) -> void:
	if t == temper: return
	temper = t
	_temper_value = [-60.0, 0.0, 60.0][t]
	temper_changed.emit(temper)
	_note_combo()
	context_changed.emit()


# ---------------------------------------------------------------- 给内容层用

func get_tags() -> Array:
	return [
		"weather_" + str(WEATHER_TAG[weather]),
		"time_" + str(TIME_TAG[time_band]),
		"temper_" + str(TEMPER_TAG[temper]),
		"realm_" + realm_slug,
	]


## CSV 单元格匹配。支持 "rain"、"rain|snow"，留空 / "any" / "*" 表示不限。
func cell_matches(cell: String, kind: String) -> bool:
	var v: String = cell.strip_edges().to_lower()
	if v == "" or v == "any" or v == "*":
		return true
	var mine: String = ""
	match kind:
		"weather": mine = str(WEATHER_TAG[weather])
		"time":    mine = str(TIME_TAG[time_band])
		"temper":  mine = str(TEMPER_TAG[temper])
		"realm":   mine = realm_slug
		_:         return true
	for part in v.split("|", false):
		if str(part).strip_edges() == mine:
			return true
	return false


## 接进你现有的八轴打分。返回 -999 表示情境不匹配，应淘汰该行。
func score_bonus(row: Dictionary, weight: float = 1.0) -> float:
	var specific: int = 0
	for pair in [["weather_tag", "weather"], ["time_tag", "time"], ["temper_tag", "temper"]]:
		var cell: String = str(row.get(str(pair[0]), ""))
		if not cell_matches(cell, str(pair[1])):
			return -999.0
		var c: String = cell.strip_edges().to_lower()
		if c != "" and c != "any" and c != "*":
			specific += 1
	match specific:
		1: return 2.0 * weight
		2: return 5.0 * weight
		3: return 12.0 * weight    # 三项全指定 = 特写台词
	return 0.0


func context_key() -> String:
	return "%s|%s|%s|%s" % [WEATHER_TAG[weather], TIME_TAG[time_band], TEMPER_TAG[temper], realm_slug]


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	return {
		"weather": weather, "time_band": time_band, "temper": temper,
		"temper_value": _temper_value, "realm_tier": realm_tier,
		"current_day": _current_day, "combo_hits": combo_hits,
		"stats": stats,
	}


func from_dict(d: Dictionary) -> void:
	weather = int(d.get("weather", Weather.CLEAR))
	time_band = int(d.get("time_band", TimeBand.MORNING))
	temper = int(d.get("temper", Temper.NEUTRAL))
	_temper_value = float(d.get("temper_value", 0.0))
	realm_tier = str(d.get("realm_tier", "凡人"))
	realm_slug = str(GameConfig.TIER_ANIM_SUFFIX.get(realm_tier, "fanren"))
	_current_day = int(d.get("current_day", -1))
	combo_hits = d.get("combo_hits", {})
	# 老存档没有 stats，保留默认值不要整个覆盖成空
	var saved_stats = d.get("stats", null)
	if typeof(saved_stats) == TYPE_DICTIONARY:
		for k in saved_stats:
			stats[k] = saved_stats[k]
	context_changed.emit()


# ---------------------------------------------------------------- 内部

func _roll_weather(day_counter: int) -> int:
	_rng.seed = hash("weather_v1|%d|%s" % [day_counter, realm_tier])
	var table: Dictionary = WEATHER_WEIGHTS.get(realm_tier, WEATHER_WEIGHTS["凡人"])
	var total: int = 0
	for k in table:
		total += int(table[k])
	var pick: int = _rng.randi_range(1, maxi(total, 1))
	var acc: int = 0
	for k in table:
		acc += int(table[k])
		if pick <= acc:
			return int(k)
	return Weather.CLEAR


func _band_for_hour(hour: int) -> int:
	var h: int = posmod(hour, 24)
	for entry in TIME_BANDS:
		var f: int = int(entry["from"])
		var t: int = int(entry["to"])
		if f < t:
			if h >= f and h < t:
				return int(entry["band"])
		else:
			if h >= f or h < t:
				return int(entry["band"])
	return TimeBand.NOON


func _temper_from_value(v: float) -> int:
	if v <= -30.0: return Temper.LOW
	if v >= 30.0:  return Temper.HIGH
	return Temper.NEUTRAL


func _note_combo() -> void:
	var key: String = context_key()
	combo_hits[key] = int(combo_hits.get(key, 0)) + 1
