# ═══════════════════════════════════════════════
#  SaveManager — 存档 / 读档 / 自动存档
#  自动拆分自 Main.gd。Main 持有实例，_ready 里注入 main = self
# ═══════════════════════════════════════════════
class_name SaveManager
extends RefCounted

var main   # Main.gd (Control) 引用

func save_game() -> void:
	main.state["last_saved_unix"] = Time.get_unix_time_from_system()
	var data: Dictionary = {"state": main.state, "today_stats": main.today_stats,
		"active_effects": main.active_effects, "reports": main.reports,
		"pending_chains": main.pending_chains, "demo_completed": main.demo_completed, "death_history": main.death_history,
		"discovered_death_causes": main.discovered_death_causes, "discovered_encounters": main.discovered_encounters,
		"life_records": main.life_records, "sound_enabled": main.sound_enabled,
		"recent_events": main.recent_events,
		"life_history": main.life_history,
		"achievements": main.achievement_manager.get_save_data() if main.achievement_manager != null else {},
		"life_flags": main.life_flags,"pending_decision": main._pending_decision,
		"memorable_events": main.memorable_events,
		"foreshadow_flags": main._foreshadow_flags,
		"achievement_unlocked_today": main._achievement_unlocked_today,
		"today_event_tags": main._today_event_tags,
		"yesterday_event_tags": main._yesterday_event_tags,
		"scheduled_chain_unlocks": main._scheduled_chain_unlocks,
		"day_counter": main._day_counter,
		"demo_life_elapsed": main._life_elapsed,
		"demo_session_elapsed": main._demo_session_elapsed,
		"demo_day_accum": main._demo_day_accum,
		"current_personality": main.current_personality,
		"personality_drift": main._personality_drift,
		"instinct_tag": main._instinct_tag,
		"rare_encounter_count": main.rare_encounter_count,
		"legendary_encounter_count": main.legendary_encounter_count,
		"last_death_punchline": main._last_death_punchline,
		"death_cause_first_punchline": main.death_cause_first_punchline,
		"reincarnation_history": main.reincarnation_history,
		"active_reincarnation_perk": main.active_reincarnation_perk,
		"event_log": main.event_manager.to_save() if main.event_manager != null else [],
		"world_state": main.world_state.to_dict() if main.world_state != null else {}}
	var file := FileAccess.open(GameConfig.SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func load_game() -> void:
	if not FileAccess.file_exists(GameConfig.SAVE_PATH):
		return
	var file := FileAccess.open(GameConfig.SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	
	if typeof(parsed) == TYPE_DICTIONARY:
		if parsed.has("state") and typeof(parsed["state"]) == TYPE_DICTIONARY:
			for key in parsed["state"].keys():
				main.state[key] = parsed["state"][key]
		if parsed.has("today_stats") and typeof(parsed["today_stats"]) == TYPE_DICTIONARY:
			for key in parsed["today_stats"].keys():
				main.today_stats[key] = parsed["today_stats"][key]
		if parsed.has("active_effects") and typeof(parsed["active_effects"]) == TYPE_ARRAY:
			main.active_effects = parsed["active_effects"]
		if parsed.has("life_records") and typeof(parsed["life_records"]) == TYPE_ARRAY:
			main.life_records = parsed["life_records"]
		if parsed.has("recent_events") and typeof(parsed["recent_events"]) == TYPE_ARRAY:
			main.recent_events = parsed["recent_events"]
		if parsed.has("sound_enabled"):
			main.sound_enabled = parsed["sound_enabled"]
		if not main.state.has("breakthrough_insight"):
			main.state["breakthrough_insight"] = 0
		if parsed.has("reports") and typeof(parsed["reports"]) == TYPE_ARRAY:
			main.reports = parsed["reports"]
		if parsed.has("death_history") and typeof(parsed["death_history"]) == TYPE_ARRAY:
			main.death_history = parsed["death_history"]
		if parsed.has("discovered_death_causes") and typeof(parsed["discovered_death_causes"]) == TYPE_DICTIONARY:
			main.discovered_death_causes = parsed["discovered_death_causes"]
		if parsed.has("pending_chains") and typeof(parsed["pending_chains"]) == TYPE_ARRAY:
			main.pending_chains = parsed["pending_chains"]
		if parsed.has("demo_completed"):
			main.demo_completed = parsed["demo_completed"]
		if parsed.has("event_log"):
			main._pending_event_log = parsed["event_log"]
		if parsed.has("achievements"):
			main._pending_achievements = parsed["achievements"]
		if parsed.has("last_death_punchline") and typeof(parsed["last_death_punchline"]) == TYPE_DICTIONARY:
			main._last_death_punchline = parsed["last_death_punchline"]
		if parsed.has("death_cause_first_punchline") and typeof(parsed["death_cause_first_punchline"]) == TYPE_DICTIONARY:
			main.death_cause_first_punchline = parsed["death_cause_first_punchline"]
		if parsed.has("reincarnation_history") and typeof(parsed["reincarnation_history"]) == TYPE_ARRAY:
			main.reincarnation_history = parsed["reincarnation_history"]
		if parsed.has("active_reincarnation_perk") and typeof(parsed["active_reincarnation_perk"]) == TYPE_DICTIONARY:
			main.active_reincarnation_perk = parsed["active_reincarnation_perk"]
		if parsed.has("discovered_encounters") and typeof(parsed["discovered_encounters"]) == TYPE_DICTIONARY:
			main.discovered_encounters = parsed["discovered_encounters"]
		if parsed.has("rare_encounter_count"):
			main.rare_encounter_count = int(parsed["rare_encounter_count"])
		if parsed.has("legendary_encounter_count"):
			main.legendary_encounter_count = int(parsed["legendary_encounter_count"])
		if parsed.has("life_history") and typeof(parsed["life_history"]) == TYPE_ARRAY:
			main.life_history = parsed["life_history"]
		if parsed.has("life_flags") and typeof(parsed["life_flags"]) == TYPE_DICTIONARY:
			main.life_flags = parsed["life_flags"]
		if parsed.has("scheduled_chain_unlocks") and typeof(parsed["scheduled_chain_unlocks"]) == TYPE_ARRAY:
			main._scheduled_chain_unlocks = parsed["scheduled_chain_unlocks"]
		if parsed.has("day_counter"):
			main._day_counter = int(parsed["day_counter"])
		# ── DEMO 节奏时钟 ──
		# _life_elapsed 必须存：不然玩家中途关掉再开，本世时钟归零，
		# 那一世会被拉长成两倍，20 分钟的排布就散了。
		if parsed.has("demo_life_elapsed"):
			main._life_elapsed = float(parsed["demo_life_elapsed"])
		if parsed.has("demo_day_accum"):
			main._demo_day_accum = float(parsed["demo_day_accum"])
		# 30 分钟硬性保护只针对「一次连续试玩」。重开视为新一场，
		# 否则玩家隔天回来会被立刻推到结局。
		if parsed.has("demo_session_elapsed"):
			var away := Time.get_unix_time_from_system() - float(main.state.get("last_saved_unix", 0))
			main._demo_session_elapsed = 0.0 if away > 900.0 else float(parsed["demo_session_elapsed"])
		if parsed.has("pending_decision") and typeof(parsed["pending_decision"]) == TYPE_DICTIONARY:
			main._pending_decision = parsed["pending_decision"]
			if not main._pending_decision.is_empty():
				main.call_deferred("_show_decision_indicator")
		if parsed.has("current_personality"):
			main.current_personality = String(parsed["current_personality"])
		if parsed.has("personality_drift") and typeof(parsed["personality_drift"]) == TYPE_DICTIONARY:
			main._personality_drift = parsed["personality_drift"]
		if parsed.has("today_event_tags") and typeof(parsed["today_event_tags"]) == TYPE_DICTIONARY:
			main._today_event_tags = parsed["today_event_tags"]
		if parsed.has("yesterday_event_tags") and typeof(parsed["yesterday_event_tags"]) == TYPE_DICTIONARY:
			main._yesterday_event_tags = parsed["yesterday_event_tags"]
		if parsed.has("achievement_unlocked_today") and typeof(parsed["achievement_unlocked_today"]) == TYPE_DICTIONARY:
			main._achievement_unlocked_today = parsed["achievement_unlocked_today"]
		if parsed.has("memorable_events") and typeof(parsed["memorable_events"]) == TYPE_ARRAY:
			main.memorable_events = parsed["memorable_events"]
		if parsed.has("foreshadow_flags") and typeof(parsed["foreshadow_flags"]) == TYPE_DICTIONARY:
			main._foreshadow_flags = parsed["foreshadow_flags"]
		if parsed.has("instinct_tag"):
			main._instinct_tag = String(parsed["instinct_tag"])
		if parsed.has("world_state") and typeof(parsed["world_state"]) == TYPE_DICTIONARY \
			and main.world_state != null:
			main.world_state.from_dict(parsed["world_state"])
		if main.demo_completed and main.feed_button != null:
			main.feed_button.disabled = true
	if not GameConfig.PERSONALITY_TRAITS.has(main.current_personality):
		main.current_personality = "lazy"
	# 旧存档迁移：有 life_records 但还没有 life_history → 自动转换，避免历史丢失
	if main.life_history.is_empty() and not main.life_records.is_empty():
		for rec in main.life_records:
			if typeof(rec) != TYPE_DICTIONARY:
				main.life_history.append(main.normalize_life_history_entry(rec))
				continue
			var t := String(rec.get("zh", ""))
			main.life_history.append({
				"life": int(main.state.get("life_count", 1)),
				"age": int(rec.get("age", main._current_age())),
				"realm": main.realms[main.state["realm_index"]]["name"],
				"category": main._life_category_from_type(String(rec.get("type", "")), t),
				"title": t,
				"description": "",
				"time": ""
			})
	main.life_cycle.apply_reincarnation_perk(main.active_reincarnation_perk)
	main.current_language = String(main.state.get("language", "zh"))
	main.achievement_manager.apply_save_data(parsed.get("achievements", {}))


func _autosave_if_due() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - main.last_autosave_time < GameConfig.AUTOSAVE_INTERVAL:
		return

	main.last_autosave_time = now
	save_game()
