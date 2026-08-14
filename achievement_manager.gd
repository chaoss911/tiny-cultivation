# ═══════════════════════════════════════════════════════════════
# AchievementManager — Tiny Cultivation
# CSV-driven achievements + compatibility API used by Main/LifeCycle.
# CSV: res://data/achievements.csv
# ═══════════════════════════════════════════════════════════════
class_name AchievementManager
extends RefCounted

signal achievement_unlocked(info: Dictionary)

const CSV_PATH := "res://data/achievements.csv"

var main
var defs: Array = []
var stats: Dictionary = {}
var unlocked: Dictionary = {} # achievement_id -> unix timestamp


func load_csv() -> void:
	defs.clear()
	if not FileAccess.file_exists(CSV_PATH):
		push_warning("achievements.csv not found: " + CSV_PATH)
		return

	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_warning("Unable to open achievements.csv: " + CSV_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	if header.is_empty():
		return
	header[0] = String(header[0]).trim_prefix("\ufeff")

	while not file.eof_reached():
		var cols: PackedStringArray = file.get_csv_line()
		if cols.is_empty() or String(cols[0]).strip_edges() == "":
			continue
		if cols.size() < header.size():
			push_warning("Skipped malformed achievement row: %s" % String(cols[0]))
			continue

		var row: Dictionary = {}
		for i in range(header.size()):
			row[String(header[i]).strip_edges()] = String(cols[i]).strip_edges()

		if String(row.get("enabled", "1")) != "1":
			continue

		row["target"] = int(row.get("target", 0))
		row["hidden"] = int(row.get("hidden", 0))
		row["reward_value"] = int(row.get("reward_value", 0))
		defs.append(row)


# ── Generic stat writers ──────────────────────────────────────
func bump(key: String, amount: int = 1) -> void:
	if amount == 0:
		return
	stats[key] = int(stats.get(key, 0)) + amount
	_check_key(key)


func set_max(key: String, value: int) -> void:
	if value > int(stats.get(key, 0)):
		stats[key] = value
		_check_key(key)


func set_value(key: String, value: int) -> void:
	stats[key] = value
	_check_key(key)


# ── Progress resolution / old-save backfill ──────────────────
func _resolve(key: String) -> int:
	if main == null:
		return int(stats.get(key, 0))

	match key:
		"qi_lifetime_total":
			# Old saves did not store lifetime qi. Preserve new tracked data and
			# use current-life visible progress as a conservative fallback.
			return maxi(int(stats.get(key, 0)), _estimated_current_life_qi())
		"breakthrough_success_total":
			return maxi(int(stats.get(key, 0)), int(main.state.get("breakthrough_success_total_lifetime", 0)))
		"highest_realm_index":
			return maxi(int(stats.get(key, 0)), _highest_realm_ever())
		"rare_encounter_total":
			return maxi(int(stats.get(key, 0)), int(main.rare_encounter_count))
		"legendary_encounter_total":
			return maxi(int(stats.get(key, 0)), int(main.legendary_encounter_count))
		"codex_encounter_count":
			return main.discovered_encounters.size()
		"death_total":
			return maxi(int(stats.get(key, 0)), main.death_history.size())
		"codex_death_count":
			return main.discovered_death_causes.size()
		"reincarnation_total":
			return maxi(0, int(main.state.get("life_count", 1)) - 1)
		"perk_kinds_owned":
			return maxi(int(stats.get(key, 0)), _perk_kinds_owned())
		"age_single_life_max":
			return maxi(int(stats.get(key, 0)), _maximum_life_age())
		"same_job_streak":
			return maxi(int(stats.get(key, 0)), _same_job_streak())
		_:
			return int(stats.get(key, 0))


func _estimated_current_life_qi() -> int:
	var total := int(maxf(0.0, float(main.state.get("cultivation", 0.0))))
	var realm_index := clampi(int(main.state.get("realm_index", 0)), 0, main.realms.size())
	for i in range(realm_index):
		if i < main.realms.size():
			total += int(main.realms[i].get("need", 0))
	return total


func _highest_realm_ever() -> int:
	var best := int(main.state.get("realm_index", 0))
	best = maxi(best, int(main.state.get("highest_realm_this_life", 0)))
	for entry in main.death_history:
		if typeof(entry) == TYPE_DICTIONARY:
			best = maxi(best, int(entry.get("highest_realm", 0)))
	for entry in main.reincarnation_history:
		if typeof(entry) == TYPE_DICTIONARY:
			best = maxi(best, int(entry.get("highest_realm", 0)))
	return best


func _perk_kinds_owned() -> int:
	var ids: Dictionary = {}
	for entry in main.reincarnation_history:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pid := String(entry.get("perk_id", ""))
		if pid != "":
			ids[pid] = true
	if typeof(main.active_reincarnation_perk) == TYPE_DICTIONARY:
		var active_id := String(main.active_reincarnation_perk.get("id", ""))
		if active_id != "":
			ids[active_id] = true
	return ids.size()


func _maximum_life_age() -> int:
	var best := int(main.state.get("cultivation_age", 16))
	for entry in main.death_history:
		if typeof(entry) == TYPE_DICTIONARY:
			best = maxi(best, int(entry.get("age", 0)))
	for entry in main.reincarnation_history:
		if typeof(entry) == TYPE_DICTIONARY:
			best = maxi(best, int(entry.get("age", 0)))
	return best


func _same_job_streak() -> int:
	var jobs: Array[String] = []
	for entry in main.reincarnation_history:
		if typeof(entry) == TYPE_DICTIONARY:
			var old_job := String(entry.get("mortal_job", ""))
			if old_job != "":
				jobs.append(old_job)
	var current_job := String(main.state.get("mortal_job", ""))
	if current_job != "":
		jobs.append(current_job)

	var best := 0
	var current := 0
	var previous := ""
	for job in jobs:
		if job == previous:
			current += 1
		else:
			previous = job
			current = 1
		best = maxi(best, current)
	return best


func get_progress(definition: Dictionary) -> int:
	return _resolve(String(definition.get("track_key", "")))


func _check_key(key: String) -> void:
	for definition in defs:
		if String(definition.get("track_key", "")) != key:
			continue
		var achievement_id := String(definition.get("achievement_id", ""))
		if achievement_id == "" or unlocked.has(achievement_id):
			continue
		if _resolve(key) >= int(definition.get("target", 0)):
			_unlock(definition)


func check_all() -> void:
	_sync_backfillable_stats()
	for definition in defs:
		var achievement_id := String(definition.get("achievement_id", ""))
		if achievement_id == "" or unlocked.has(achievement_id):
			continue
		if get_progress(definition) >= int(definition.get("target", 0)):
			_unlock(definition)


func _sync_backfillable_stats() -> void:
	set_max("breakthrough_success_total", int(main.state.get("breakthrough_success_total_lifetime", 0)))
	set_max("highest_realm_index", _highest_realm_ever())
	set_max("rare_encounter_total", int(main.rare_encounter_count))
	set_max("legendary_encounter_total", int(main.legendary_encounter_count))
	set_max("codex_encounter_count", main.discovered_encounters.size())
	set_max("death_total", main.death_history.size())
	set_max("codex_death_count", main.discovered_death_causes.size())
	set_max("reincarnation_total", maxi(0, int(main.state.get("life_count", 1)) - 1))
	set_max("perk_kinds_owned", _perk_kinds_owned())
	set_max("age_single_life_max", _maximum_life_age())
	set_max("same_job_streak", _same_job_streak())
	_backfill_death_cause_counts()


func _backfill_death_cause_counts() -> void:
	var lightning := 0
	var goose := 0
	for entry in main.death_history:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var text := "%s %s" % [String(entry.get("cause_zh", "")), String(entry.get("cause_en", "")).to_lower()]
		if _contains_any(text, ["雷", "天劫", "雷劫", "lightning", "tribulation", "thunder"]):
			lightning += 1
		if _contains_any(text, ["鹅", "goose", "geese"]):
			goose += 1
	set_max("death_by_lightning", lightning)
	set_max("death_by_goose", goose)


# ── Public recording API used by the game ────────────────────
func record_qi_gain(amount: int) -> void:
	if amount > 0:
		bump("qi_lifetime_total", amount)


func record_meditation_seconds(seconds: int) -> void:
	if seconds <= 0:
		return
	var session_seconds := int(stats.get("meditate_session_seconds", 0)) + seconds
	stats["meditate_session_seconds"] = session_seconds
	set_max("meditate_hours_single", int(floor(session_seconds / 3600.0)))


func reset_meditation_session() -> void:
	stats["meditate_session_seconds"] = 0


func record_login_today() -> void:
	var day_number := int(Time.get_unix_time_from_system() / 86400.0)
	var previous_day := int(stats.get("last_login_day", -999999))
	if previous_day == day_number:
		return
	var streak := 1
	if previous_day == day_number - 1:
		streak = int(stats.get("login_streak", 0)) + 1
	stats["last_login_day"] = day_number
	set_value("login_streak", streak)


func record_efficiency_bonus(percent: int) -> void:
	set_max("efficiency_bonus_total", maxi(0, percent))


func record_stones_picked(amount: int = 1) -> void:
	if amount > 0:
		bump("stones_picked_total", amount)


func record_breakthrough_success_total(total: int) -> void:
	set_max("breakthrough_success_total", total)
	set_max("highest_realm_index", _highest_realm_ever())


func record_breakthrough_fail_total(total: int) -> void:
	set_max("breakthrough_fail_total", total)


func record_encounter_count(_total: int) -> void:
	# Existing Main call supplies rare + legendary combined. Read the two
	# authoritative counters instead so rare achievements are not inflated.
	set_max("rare_encounter_total", int(main.rare_encounter_count))
	set_max("legendary_encounter_total", int(main.legendary_encounter_count))


func record_encounter_variety(count: int) -> void:
	set_max("codex_encounter_count", count)


func record_encounter_legendary(count: int = -1) -> void:
	if count >= 0:
		set_max("legendary_encounter_total", count)
	else:
		bump("legendary_encounter_total")


func record_encounter_legendary_all(_count: int) -> void:
	# Compatibility hook for achievements removed from the current CSV.
	pass


func record_hidden_encounter(amount: int = 1) -> void:
	bump("hidden_encounter_total", amount)


func record_scroll_fragments(count: int) -> void:
	set_max("scroll_fragments", count)


func record_death_cause(cause_zh: String, cause_en: String = "") -> void:
	set_max("death_total", main.death_history.size())
	var text := "%s %s" % [cause_zh, cause_en.to_lower()]
	if _contains_any(text, ["雷", "天劫", "雷劫", "lightning", "tribulation", "thunder"]):
		bump("death_by_lightning")
	if _contains_any(text, ["鹅", "goose", "geese"]):
		bump("death_by_goose")


func record_death_variety(count: int) -> void:
	set_max("codex_death_count", count)


func record_alchemy_fail(amount: int = 1) -> void:
	bump("alchemy_fail_total", amount)


func record_poison(amount: int = 1) -> void:
	bump("poison_total", amount)


func record_furnace_explosion(amount: int = 1) -> void:
	bump("furnace_explosion_total", amount)


func record_life_count(new_life: int) -> void:
	set_max("reincarnation_total", maxi(0, new_life - 1))
	set_max("perk_kinds_owned", _perk_kinds_owned())
	set_max("age_single_life_max", _maximum_life_age())
	set_max("same_job_streak", _same_job_streak())


func record_age_low_realm(age: int, _realm_index: int) -> void:
	set_max("age_single_life_max", age)


func record_ascended() -> void:
	set_value("ascended", 1)


# Compatibility calls retained by the current Main script. They are safe even
# when the current achievements.csv has no matching track_key.
func record_click(_count: int) -> void:
	pass


func record_soul_echo_seen() -> void:
	pass


func record_chain_outcome(_chain_id: String, _outcome_id: String) -> void:
	pass


func record_milestone(title_zh: String) -> void:
	if title_zh.contains("突破成功"):
		record_breakthrough_success_total(int(main.state.get("breakthrough_success_total_lifetime", 0)))


func record_story_moment(moment: Dictionary) -> void:
	# record_event() is called immediately after this by Main, so only handle
	# information that cannot be represented by event_type here.
	var event_type := String(moment.get("event_type", "")).to_lower()
	var text := "%s %s" % [String(moment.get("text_zh", "")), String(moment.get("text_en", "")).to_lower()]
	if event_type not in ["furnace_explosion", "explosion"] and _contains_any(text, ["炸炉", "furnace explosion"]):
		record_furnace_explosion()
	if String(moment.get("rarity", "")) == "hidden":
		record_hidden_encounter()


func record_event(event_type: String) -> void:
	match event_type.to_lower():
		"alchemy_fail", "pill_fail":
			record_alchemy_fail()
		"poison", "poisoned":
			record_poison()
		"furnace_explosion", "explosion":
			record_furnace_explosion()
		"hidden_encounter":
			record_hidden_encounter()


func unlock_by_id(achievement_id: String) -> void:
	if achievement_id == "" or unlocked.has(achievement_id):
		return
	for definition in defs:
		if String(definition.get("achievement_id", "")) == achievement_id:
			_unlock(definition)
			return
	push_warning("Unknown or disabled achievement id: " + achievement_id)


func _contains_any(text: String, needles: Array) -> bool:
	var lower := text.to_lower()
	for needle in needles:
		if lower.contains(String(needle).to_lower()):
			return true
	return false


# ── Unlock / reward / UI notification ───────────────────────
func _unlock(definition: Dictionary) -> void:
	var achievement_id := String(definition.get("achievement_id", ""))
	if achievement_id == "" or unlocked.has(achievement_id):
		return
	unlocked[achievement_id] = int(Time.get_unix_time_from_system())

	var reward_type := String(definition.get("reward_type", ""))
	var reward_value := int(definition.get("reward_value", 0))
	if reward_value > 0:
		match reward_type:
			"stone":
				main.state["spirit_stones"] = int(main.state.get("spirit_stones", 0)) + reward_value
			"qi":
				main.state["cultivation"] = float(main.state.get("cultivation", 0.0)) + reward_value
				record_qi_gain(reward_value)

	var reward_line_zh := ""
	var reward_line_en := ""
	if reward_value > 0:
		if reward_type == "qi":
			reward_line_zh = "奖励：修为 ×%d" % reward_value
			reward_line_en = "Reward: %d qi" % reward_value
		else:
			reward_line_zh = "奖励：灵石 ×%d" % reward_value
			reward_line_en = "Reward: %d stones" % reward_value

	main._show_toast("🏆 成就达成", "🏆 Achievement Unlocked", [
		{"zh": "[b]%s[/b]" % String(definition.get("name_zh", "")), "en": "[b]%s[/b]" % String(definition.get("name_en", ""))},
		{"zh": String(definition.get("desc_zh", "")), "en": String(definition.get("desc_en", ""))},
		{"zh": reward_line_zh, "en": reward_line_en}
	])

	achievement_unlocked.emit({
		"achievement_id": achievement_id,
		"title_zh": String(definition.get("name_zh", "")),
		"title_en": String(definition.get("name_en", "")),
		"definition": definition
	})

	if main.save_mgr != null:
		main.save_mgr.save_game()


# ── Save data ────────────────────────────────────────────────
func get_save_data() -> Dictionary:
	return {
		"stats": stats.duplicate(true),
		"unlocked": unlocked.duplicate(true)
	}


func apply_save_data(data: Dictionary) -> void:
	stats = data.get("stats", {}).duplicate(true) if typeof(data.get("stats", {})) == TYPE_DICTIONARY else {}
	unlocked = data.get("unlocked", {}).duplicate(true) if typeof(data.get("unlocked", {})) == TYPE_DICTIONARY else {}


func unlocked_count() -> int:
	return unlocked.size()


func total_count() -> int:
	return defs.size()


func get_unlocked_defs() -> Array:
	var result: Array = []
	for definition in defs:
		if unlocked.has(String(definition.get("achievement_id", ""))):
			result.append(definition)
	return result
