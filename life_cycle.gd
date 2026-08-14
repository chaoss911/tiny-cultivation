# ═══════════════════════════════════════════════
#  LifeCycle — 突破 / 死亡 / 轮回（含天赋 perk 系统）
#  自动拆分自 Main.gd（第四包·完结）。Main 持有实例，_ready 注入 main = self
# ═══════════════════════════════════════════════
class_name LifeCycle
extends RefCounted

var main   # Main.gd (Control) 引用

func _can_attempt_breakthrough_now() -> bool:
	if main._reincarnating:
		return false
	if GameConfig.DEMO_MODE and main.demo_completed:
		return false
	if int(main.state.get("realm_index", 0)) >= main.realms.size() - 1:
		return false
	var realm: Dictionary = main.realms[int(main.state.get("realm_index", 0))]
	return float(main.state.get("cultivation", 0.0)) >= float(realm["need"])


func try_breakthrough() -> void:
	if GameConfig.DEMO_MODE and main.demo_completed:
		return

	if int(main.state.get("realm_index", 0)) >= main.realms.size() - 1:
		main._check_demo_ending()
		return
	main.today_stats["breakthrough_attempt"] += 1
	var chance := 0.82
	if main.state["realm_index"] >= 3: chance = 0.65
	if main.state["realm_index"] >= 6: chance = 0.45
	chance = clampf(chance + main.luck_modifier() + main.next_breakthrough_bonus + float(main.reincarnation_modifiers.get("breakthrough_bonus", 0.0)), 0.05, 0.98)

	var insight: int = int(main.state.get("breakthrough_insight", 0))
	chance += insight * 0.005
	chance = clampf(chance, 0.05, 0.98)
	if GameConfig.DEMO_MODE:
		chance = clampf(chance + GameConfig.DEMO_BREAKTHROUGH_BONUS, 0.05, 0.98)

	var success: bool
	if insight >= GameConfig.BREAKTHROUGH_INSIGHT_CAP:
		success = true
	else:
		success = randf() <= chance

	main.next_breakthrough_bonus = 0.0
	var transition_anim_playing := ""

	if success:
		main.today_stats["breakthrough_success"] += 1
		main._today_event_tags["breakthrough_success"] = true
		var old_tier: String = main.current_tier()
		main.state["realm_index"] = min(main.state["realm_index"] + 1, main.realms.size() - 1)
		main.state["highest_realm_this_life"] = max(int(main.state.get("highest_realm_this_life", 0)), main.state["realm_index"])
		main.state["life_breakthrough_success"] = int(main.state.get("life_breakthrough_success", 0)) + 1
		main.state["breakthrough_success_total_lifetime"] = int(main.state.get("breakthrough_success_total_lifetime", 0)) + 1
		if main.achievement_manager != null:
			main.achievement_manager.record_breakthrough_success_total(main.state["breakthrough_success_total_lifetime"])
		var lifespan_bonus: int = main._lifespan_bonus_for_realm(main.state["realm_index"])
		main.state["lifespan"] += lifespan_bonus
		main.state["cultivation"] = 0.0
		main._check_spiritual_root_awakening()
		main._age_up(_years_for_breakthrough(main.state["realm_index"]))
		var new_tier: String = main.current_tier()
		var transition_anim := "%s_breakthrough_%s" % [
			GameConfig.TIER_ANIM_SUFFIX.get(old_tier, ""), GameConfig.TIER_ANIM_SUFFIX.get(new_tier, "")
		]
		if new_tier != old_tier and main.cultivator_sprite.sprite_frames != null \
			and main.cultivator_sprite.sprite_frames.has_animation(transition_anim):
			main._current_mood_priority = GameConfig.MoodPriority.SYSTEM
			main.cultivator_sprite.position.x = 0
			main.cultivator_sprite.play(transition_anim)
			transition_anim_playing = transition_anim
		else:
			main.request_mood("breakthrough_success", GameConfig.MoodPriority.EVENT)
		AudioManager.play_breakthrough()

		var had_insight: int = int(main.state.get("breakthrough_insight", 0))
		main.state["breakthrough_insight"] = 0

		var success_line_zh := ""
		var success_line_en := ""
		var success_pool = DataLoader.breakthrough_success_lines.filter(func(r): return r["realm"] == new_tier)
		if success_pool.is_empty():
			success_pool = DataLoader.breakthrough_success_lines
		if not success_pool.is_empty():
			var picked = success_pool.pick_random()
			success_line_zh = picked["zh"]
			success_line_en = picked["en"]

		main.add_recent_event("突破到「%s」" % main.realms[main.state["realm_index"]]["name"],
			"Advanced to %s" % main.realm_names_en[main.state["realm_index"]], "breakthrough")
		main.add_life_history("breakthrough", "突破成功", "境界提升至「%s」。" % main.realms[main.state["realm_index"]]["name"],
			"Breakthrough Success", "Advanced to %s." % main.realm_names_en[main.state["realm_index"]])
		if new_tier != old_tier:
			main.add_life_record("突破%s境" % new_tier, "Entered the %s realm" % new_tier, "breakthrough")

		if had_insight > 0:
			main.add_life_record(
				"厚积薄发，成功突破%s" % main.realms[main.state["realm_index"]]["name"],
				"Years of insight paid off — advanced to %s" % main.realm_names_en[main.state["realm_index"]],
				"breakthrough"
			)
			main._show_toast("突破成功", "Breakthrough",
				[{"zh": success_line_zh, "en": success_line_en},
				 {"zh":"突破到「%s」！" % main.realms[main.state["realm_index"]]["name"],
				  "en":"Advanced to %s!" % main.realm_names_en[main.state["realm_index"]]},
				 {"zh":"寿元 +%d" % lifespan_bonus, "en":"Lifespan +%d" % lifespan_bonus},
				 {"zh":"多年感悟终于开花结果。", "en":"Your accumulated insight has finally paid off."}])
		else:
			main._show_toast("突破成功", "Breakthrough",
				[{"zh": success_line_zh, "en": success_line_en},
				 {"zh":"突破到「%s」！" % main.realms[main.state["realm_index"]]["name"],
				  "en":"Advanced to %s!" % main.realm_names_en[main.state["realm_index"]]},
				 {"zh":"寿元 +%d" % lifespan_bonus, "en":"Lifespan +%d" % lifespan_bonus}])
		main._check_demo_ending()

	else:
		var penalty = 1 if main.failure_penalty_reduced else 3
		penalty += int(main.reincarnation_modifiers.get("failure_penalty_delta", 0))
		penalty = int(round(penalty * main._personality_bias("failure_penalty_mult")))
		penalty = max(1, penalty)
		main.state["lifespan"] -= penalty
		main.failure_penalty_reduced = false
		main.state["cultivation"] = main.state["cultivation"] * 0.5
		main.request_mood("breakthrough_fail", GameConfig.MoodPriority.EVENT)

		main.state["breakthrough_insight"] = min(GameConfig.BREAKTHROUGH_INSIGHT_CAP, int(main.state.get("breakthrough_insight", 0)) + GameConfig.BREAKTHROUGH_INSIGHT_PER_FAIL)
		main.state["life_breakthrough_fails"] = int(main.state.get("life_breakthrough_fails", 0)) + 1
		main.state["breakthrough_fail_total_lifetime"] = int(main.state.get("breakthrough_fail_total_lifetime", 0)) + 1
		if main.achievement_manager != null:
			main.achievement_manager.record_breakthrough_fail_total(main.state["breakthrough_fail_total_lifetime"])
		if int(main.state["life_breakthrough_fails"]) >= 3:
			main._nudge_personality("diligent", 1.0)
			
		main._age_up(randi_range(1, 3))
		
		main.add_recent_event(
   			 "突破失败 寿元-%d 感悟+%d%%" % [penalty, GameConfig.BREAKTHROUGH_INSIGHT_PER_FAIL],
  			  "Breakthrough failed  Lifespan -%d  Insight +%d%%" % [penalty, GameConfig.BREAKTHROUGH_INSIGHT_PER_FAIL],
  			  "special"
		)
		main.add_life_record(
			"冲击%s失败，获得感悟" % main.realms[main.state["realm_index"]]["name"],
			"Failed to break through %s — gained insight" % main.realm_names_en[main.state["realm_index"]],
			"special"
		)
		main.add_life_history("breakthrough", "突破失败", "冲击「%s」未果，灵气逆流，但有所感悟。" % main.realms[main.state["realm_index"]]["name"],
			"Breakthrough Failed", "Failed to break through %s — qi surged backward, but insight was gained." % main.realm_names_en[main.state["realm_index"]])

		var fail_reason_zh := ""
		var fail_reason_en := ""
		main._today_event_tags["breakthrough_fail"] = true
		var tier_pool = DataLoader.breakthrough_fail_reasons.filter(func(r): return r["realm"] == main.current_tier())
		if tier_pool.is_empty():
			tier_pool = DataLoader.breakthrough_fail_reasons
		if not tier_pool.is_empty():
			var picked = tier_pool.pick_random()
			fail_reason_zh = picked["zh"]
			fail_reason_en = picked["en"]

		main._show_toast("突破失败", "Breakthrough Failed",
   			 [{"zh": fail_reason_zh, "en": fail_reason_en},
   			  {"zh":"寿元 -%d" % penalty, "en":"Lifespan -%d" % penalty},
   			  {"zh":"感悟 +%d%%" % GameConfig.BREAKTHROUGH_INSIGHT_PER_FAIL, "en":"Insight +%d%%" % GameConfig.BREAKTHROUGH_INSIGHT_PER_FAIL},
				 {"zh":"修为保留 %d" % int(main.state["cultivation"]), "en":"Cultivation retained: %d" % int(main.state["cultivation"])}])
		if await check_lifespan():
			return

	if transition_anim_playing != "":
		await main.get_tree().create_timer(main.anim_ctl._death_anim_duration(transition_anim_playing) + 0.1).timeout
	else:
		# 等实际动画播完再切回 normal
		var current_anim: String = String(main.cultivator_sprite.animation)
		var anim_dur = main.anim_ctl._death_anim_duration(current_anim)
		await main.get_tree().create_timer(max(anim_dur, 1.5) + 0.3).timeout
	main.clear_mood_priority()
	main.request_mood("normal", GameConfig.MoodPriority.AMBIENT)
	main.refresh_ui()
	main.save_mgr.save_game()   # 突破是重要事件，节流后仍即时落盘


func _years_for_breakthrough(realm_index: int) -> int:
	if realm_index <= 2:   return randi_range(8, 18)      # 凡人 tier: small age jumps
	elif realm_index <= 4: return randi_range(20, 45)     # 武者 tier
	elif realm_index <= 6: return randi_range(60, 120)    # 先天 tier
	else:                  return randi_range(150, 300)  # 炼气 tier: huge jumps


# 由 Main._demo_tick_clock 每秒调用。时间到 = 死，跟境界无关。
func check_demo_life_clock() -> void:
	if not GameConfig.DEMO_MODE:
		return
	if main._reincarnating or main.demo_completed:
		return
	if int(main.state.get("life_count", 1)) > GameConfig.DEMO_FORCED_DEATHS:
		return

	var target: float = main._demo_life_target_seconds()
	if target <= 0.0:
		return                      # 最后一世：不强制，跑到炼气为止
	if main._life_elapsed < target:
		return

	# 境界太低就宽限一会儿，别死在「引气一层」那么难看
	if GameConfig.DEMO_MIN_DEATH_REALM > 0 \
		and int(main.state.get("realm_index", 0)) < GameConfig.DEMO_MIN_DEATH_REALM \
		and main._life_elapsed < target + GameConfig.DEMO_DEATH_GRACE:
		return

	# 玩家不在就等他回来，死亡是全 demo 的高光
	if not main.demo_death_ready():
		return

	_demo_force_death_now()


func _demo_force_death_now() -> void:
	if main._reincarnating:
		return
	main.state["lifespan"] = 0
	await check_lifespan()   # 死亡动画 + 轮回证书 + 转世


# 兼容旧调用点（突破成功后）：现在改由时钟驱动，这里永远不再强制
func _demo_force_death_if_due() -> bool:
	return false


func check_lifespan() -> bool:
	if main._reincarnating:
		return false
	if int(main.state["lifespan"]) > 0:
		return false

	main._reincarnating = true
	main.state["lifespan"] = 0

	var cause := _pick_death_cause()
	var cause_zh: String = cause["title_zh"]
	var cause_en: String = cause["title_en"]
	var cause_id: String = cause.get("id", "")

	var prev_life: int = int(main.state.get("life_count", 1))
	var highest: int = int(main.state.get("highest_realm_this_life", main.state["realm_index"]))
	main.death_history.append({
		"life": prev_life,
		"age": main._current_age(),
		"highest_realm": highest,
		"cause_zh": cause_zh,
		"cause_en": cause_en,
		"time": Time.get_time_string_from_system().substr(0, 5)
	})
	if main.death_history.size() > 50:
		main.death_history.pop_front()

	if cause_id != "":
		main.discovered_death_causes[cause_id] = true

	# 轮回总结 + 抽下一世天赋（必须在 _reincarnate 重置前收集本世数据）
	var life_title := _pick_life_title()
	var prev_data: Dictionary = main.collect_current_life_data(cause, life_title)
	var next_perk := roll_reincarnation_perk(prev_data, cause)
	var next_personality: String = main.roll_personality(prev_data, cause, next_perk)
	var next_instinct: String = main._roll_instinct(prev_data, cause)
	var picked_last_words := _pick_last_words(cause)
	var punchline := _generate_death_punchline(cause, life_title, picked_last_words)
	main._last_death_punchline = punchline
	add_reincarnation_history_record(cause, life_title, next_perk)
	
	
	main.add_life_record("寿终：%s" % cause_zh, "Died: %s" % cause_en, "death")
	main.add_recent_event("陨落：%s" % cause_zh, "Fell: %s" % cause_en, "death")
	main.add_life_history("death", "本世陨落：%s" % cause_zh, punchline["zh"],
		"Fell this life: %s" % cause_en, punchline["en"])
	main._today_event_tags["death"] = true
	if cause_id != "" and not main.death_cause_first_punchline.has(cause_id):
		main.death_cause_first_punchline[cause_id] = punchline
	if main.achievement_manager != null:
		main.achievement_manager.record_death_cause(cause_zh, cause_en)
		main.achievement_manager.record_death_variety(main.discovered_death_causes.size())

	var death_anim: String = main._play_death_animation(cause)
	AudioManager.play_death(-4.0)
	main.refresh_ui()
	main.save_mgr.save_game()

	# 先等死亡动画完整播完（+0.3秒定格在焦黑/魂魄那帧），再弹证书
	await main.get_tree().create_timer(main.anim_ctl._death_anim_duration(death_anim) + 0.3).timeout

	main.certificate_ui._show_reincarnation_certificate(cause_zh, cause_en, prev_life, highest, punchline)
	# 等玩家点掉证书再轮回（最多兜底 12 秒，避免一直卡死）
	var waited := 0.0
	while main._certificate_open and waited < 12.0:
		await main.get_tree().create_timer(0.2).timeout
		waited += 0.2
	if main.certificate_panel != null:
		main.certificate_panel.visible = false
	_reincarnate(next_perk, next_personality, next_instinct)
	return true


func _pick_death_cause() -> Dictionary:
	if DataLoader.death_causes.is_empty():
		return {"id": "death_007", "title_zh": "寿元耗尽", "title_en": "Lifespan ran dry"}
	var total := 0
	for c in DataLoader.death_causes:
		total += c["weight"]
	var roll := randi() % total
	var acc := 0
	for c in DataLoader.death_causes:
		acc += c["weight"]
		if roll < acc:
			return c
	return DataLoader.death_causes.back()


func _generate_death_punchline(cause: Dictionary, life_title: Dictionary, final_words: Dictionary) -> Dictionary:
	var pet_name: String = String(main.state.get("pet_name", ""))
	var age: int = main._current_age()
	var cause_zh: String = String(cause.get("title_zh",""))
	var cause_en: String = String(cause.get("title_en",""))
	var title_zh: String = String(life_title.get("zh",""))
	var title_en: String = String(life_title.get("en",""))
	var lw_zh: String = final_words.get("zh","")
	var lw_en: String = final_words.get("en","")
	var zh := "「%s」——这是%s留下的最后一句话。下一秒，他%s，享年%d岁，临终称号「%s」。" % [
		lw_zh if lw_zh != "" else "……", pet_name, cause_zh, age, title_zh
	]
	var en := "\"%s\" — %s's last words. Moments later, he %s, age %d, remembered as \"%s.\"" % [
		lw_en if lw_en != "" else "...", pet_name, cause_en, age, title_en
	]
	return {"zh": zh, "en": en}


func _pick_last_words(cause: Dictionary) -> Dictionary:
	var anim_key: String = String(cause.get("animation", "")).strip_edges()
	var pool: Array = DataLoader.last_words.filter(
	func(r): return r["cause_type"] == anim_key
)
	if pool.is_empty():
		pool = DataLoader.last_words.filter(func(r): return r["cause_type"] == "generic")
	if pool.is_empty():
		return {"zh": "", "en": ""}
	var picked: Dictionary = pool.pick_random()
	return {"zh": picked["zh"], "en": picked["en"]}


func _pick_life_title() -> Dictionary:
	var clicks: int = int(main.state.get("life_click_count", 0))
	var fails: int = int(main.state.get("life_breakthrough_fails", 0))
	var successes: int = int(main.state.get("life_breakthrough_success", 0))
	var pills_eaten: int = int(main.state.get("life_pills_eaten", 0))
	var legendary: int = int(main.state.get("life_legendary_count", 0))
	var rare: int = int(main.state.get("life_rare_count", 0))
	var age: int = main._current_age()

	# Each candidate: title, score (only considered if score crosses its threshold)
	var candidates := []

	if clicks >= 500:
		candidates.append({"score": clicks, "zh": "摸鱼大仙", "en": "Slacking Immortal"})
	if fails >= 8:
		candidates.append({"score": fails * 10, "zh": "天选震鱼人", "en": "Heaven-Chosen Failure"})
	if legendary >= 3:
		candidates.append({"score": legendary * 50, "zh": "天命之子", "en": "Child of Destiny"})
	if pills_eaten >= 15:
		candidates.append({"score": pills_eaten * 8, "zh": "嗑丹狂魔", "en": "Pill-Popping Maniac"})
	if successes >= 5 and fails == 0:
		candidates.append({"score": successes * 30, "zh": "天纵奇才", "en": "Natural-Born Genius"})
	if age >= 500:
		candidates.append({"score": age, "zh": "长生不老（差一点）", "en": "Almost Immortal"})
	if rare >= 5:
		candidates.append({"score": rare * 15, "zh": "机缘不断", "en": "Fortune's Favorite"})
	if clicks == 0 and fails == 0 and successes <= 1:
		candidates.append({"score": 1, "zh": "平平无奇的修仙者", "en": "An Utterly Unremarkable Cultivator"})

	if candidates.is_empty():
		return {"zh": "平平无奇的修仙者", "en": "An Utterly Unremarkable Cultivator"}

	candidates.sort_custom(func(a, b): return a["score"] > b["score"])
	return candidates[0]


func _reincarnate(next_perk: Dictionary = {}, next_personality: String = "", next_instinct: String = "") -> void:
	var new_life: int = int(main.state.get("life_count", 1)) + 1
	var bonus = float(main.state.get("reincarnation_bonus", 0.0)) + main.REINCARNATION_BONUS_PER_LIFE
	bonus = min(bonus, main.REINCARNATION_BONUS_CAP)

	# 先应用下一世天赋，算出初始加成
	apply_reincarnation_perk(next_perk)
	var lifespan_bonus = int(main.reincarnation_modifiers.get("lifespan_bonus", 0))
	var luck_bonus = int(main.reincarnation_modifiers.get("starting_luck_bonus", 0))
	var stone_keep_bonus = float(main.reincarnation_modifiers.get("stone_keep_bonus", 0.0))

	# 性情先于职业抽取设置好，这样 _assign_mortal_job() 里的偏好表才能正确生效
	main.active_effects.clear()
	main.life_flags.clear()
	main._personality_drift.clear()
	main.memorable_events.clear()
	main._foreshadow_flags.clear()
	main._clear_decision()
	if next_personality != "" and GameConfig.PERSONALITY_TRAITS.has(next_personality):
		main.current_personality = next_personality
	elif main.current_personality == "" or not GameConfig.PERSONALITY_TRAITS.has(main.current_personality):
		main.current_personality = "lazy"   # absolute fallback — should never trigger, but never leave it blank

	var job: Dictionary = main._roll_mortal_job()
	var previous_state = main.state.duplicate(true)
	var old_luck := int(previous_state.get("luck", 50))
	var stones_kept := int(int(previous_state.get("spirit_stones", 0) / 2) * (1.0 + stone_keep_bonus))

	main.state = {
		"realm_index": 0, "cultivation": 0.0,
		"spirit_stones": stones_kept, "lifespan": 80 + lifespan_bonus,
		"last_saved_unix": Time.get_unix_time_from_system(),
		"luck": clampi(old_luck + luck_bonus, 1, 100), "luck_date": previous_state.get("luck_date", ""),
		"life_count": new_life, "highest_realm_this_life": 0,
		"reincarnation_bonus": bonus,
		"click_count": int(previous_state.get("click_count", 0)),
		"pet_name": previous_state.get("pet_name", ""), "mortal_job": "",
		"spiritual_root": "","language": main.current_language,
		"breakthrough_insight": 0,
		"cultivation_age": 16,
		"life_click_count": 0,
		"life_breakthrough_fails": 0,
		"life_breakthrough_success": 0,
		"life_pills_eaten": 0,
		"life_legendary_count": 0,
		"life_rare_count": 0,
		"breakthrough_success_total_lifetime": int(previous_state.get("breakthrough_success_total_lifetime", 0)),
		"breakthrough_fail_total_lifetime": int(previous_state.get("breakthrough_fail_total_lifetime", 0)),
		"pills_total_lifetime": int(previous_state.get("pills_total_lifetime", 0))
	}
	main.state["mortal_job"] = job["id"]
	var perk_name = String(main.active_reincarnation_perk.get("zh", "平平无奇")) if not main.active_reincarnation_perk.is_empty() else "平平无奇"
	var perk_name_en = String(main.active_reincarnation_perk.get("en", "Utterly Ordinary")) if not main.active_reincarnation_perk.is_empty() else "Utterly Ordinary"
	main.add_life_record("第 %d 次转世" % (new_life - 1), "Reincarnation #%d" % (new_life - 1), "special")
	var job_label_zh2: String = job["zh"]
	var job_label_en2: String = job["en"]
	main.add_life_history(
		"birth",
		"转世重修",
		"第 %d 世开始。今生职业：%s。轮回天赋：%s。性情：%s。" % [new_life, job_label_zh2, perk_name, GameConfig.PERSONALITY_META[main.current_personality]["zh"]],
		"Reincarnated",
		"Life %d begins. Job this life: %s. Reincarnation perk: %s. Personality: %s." % [new_life, job_label_en2, perk_name_en, GameConfig.PERSONALITY_META[main.current_personality]["en"]]
	)
	if main.achievement_manager != null:
		main.achievement_manager.record_life_count(new_life)
	main._instinct_tag = next_instinct
	if GameConfig.DEMO_MODE:
		main._reset_demo_life_clock()
	main.clear_mood_priority()
	main.request_mood("normal", GameConfig.MoodPriority.AMBIENT)
	main.refresh_ui()
	main.save_mgr.save_game()
	main._reincarnating = false
	main._set_main_ui_visible(false)
	main._show_intro_sequence(String(main.state.get("pet_name", "小白")), true)


func get_default_reincarnation_modifiers() -> Dictionary:
	return {
		"cultivation_mult": 1.0, "breakthrough_bonus": 0.0, "lifespan_bonus": 0,
		"starting_luck_bonus": 0, "pill_effect_mult": 1.0, "pill_risk_mult": 1.0,
		"failure_penalty_delta": 0, "stone_keep_bonus": 0.0, "encounter_luck_bonus": 0.0
	}


func get_active_perk_modifiers() -> Dictionary:
	var mods := get_default_reincarnation_modifiers()
	if typeof(main.active_reincarnation_perk) == TYPE_DICTIONARY:
		var pm = main.active_reincarnation_perk.get("modifiers", {})
		if typeof(pm) == TYPE_DICTIONARY:
			for k in pm.keys():
				mods[k] = pm[k]
	return mods


func apply_reincarnation_perk(perk: Dictionary) -> void:
	main.active_reincarnation_perk = perk if typeof(perk) == TYPE_DICTIONARY else {}
	main.reincarnation_modifiers = get_active_perk_modifiers()


func _all_reincarnation_perks() -> Array:
	return [
		{"id":"boom_expert","zh":"丹炉爆破专家","en":"Furnace Demolition Expert",
		 "desc_zh":"他不一定会炼丹，但很会制造动静。","desc_en":"Not great at alchemy, but excellent at making a bang.",
		 "modifiers":{"pill_effect_mult":1.10,"pill_risk_mult":1.20,"cultivation_mult":1.02}},
		{"id":"pill_phobia","zh":"丹药恐惧症","en":"Pill Phobia",
		 "desc_zh":"上一世被丹药教育得很彻底。本世吃丹效果略低，但更不容易被丹药害死。","desc_en":"A harsh pill lesson last life. Pills do a bit less, but rarely kill you now.",
		 "modifiers":{"pill_effect_mult":0.90,"pill_risk_mult":0.75,"cultivation_mult":1.03}},
		{"id":"tribulation_regular","zh":"雷劫熟客","en":"Tribulation Regular",
		 "desc_zh":"被雷劈多了，多少知道该往哪里躲。","desc_en":"Struck enough times to know where to stand.",
		 "modifiers":{"breakthrough_bonus":0.03,"failure_penalty_delta":-1,"encounter_luck_bonus":0.05}},
		{"id":"minor_fate","zh":"小有仙缘","en":"Touched by Fate",
		 "desc_zh":"上一世摸到了一点仙缘，这一世开局比较顺。","desc_en":"A brush with fortune makes for a smoother start.",
		 "modifiers":{"cultivation_mult":1.05,"breakthrough_bonus":0.02,"starting_luck_bonus":5}},
		{"id":"born_to_chill","zh":"天生躺平","en":"Born to Chill",
		 "desc_zh":"这一世不一定努力，但应该会活比较久。","desc_en":"Maybe not hardworking, but probably long-lived.",
		 "modifiers":{"cultivation_mult":0.95,"lifespan_bonus":8,"starting_luck_bonus":3}},
		{"id":"plain","zh":"平平无奇","en":"Utterly Ordinary",
		 "desc_zh":"没有特别天赋，但至少没有特别倒霉。","desc_en":"No special talent, but no special misfortune either.",
		 "modifiers":{}}
	]


func _perk_by_id(pid: String) -> Dictionary:
	for p in _all_reincarnation_perks():
		if p["id"] == pid:
			return p
	return _all_reincarnation_perks().back()


func roll_reincarnation_perk(previous_life_data: Dictionary, cause: Dictionary) -> Dictionary:
	var ct := "%s %s %s" % [String(cause.get("title_zh","")), String(cause.get("title_en","")).to_lower(), String(cause.get("type",""))]
	var pills_eaten: int = int(previous_life_data.get("life_pills_eaten", 0))
	var fails: int = int(previous_life_data.get("life_breakthrough_fails", 0))
	var success: int = int(previous_life_data.get("life_breakthrough_success", 0))
	var clicks: int = int(previous_life_data.get("life_click_count", 0))
	var age: int = int(previous_life_data.get("age", 0))
	var highest: int = int(previous_life_data.get("highest_realm", 0))
	var legendary: int = int(previous_life_data.get("life_legendary_count", 0))
	if ct.contains("炸") or ct.contains("爆") or ct.contains("explosion") or pills_eaten >= 12:
		return _perk_by_id("boom_expert")
	if ct.contains("丹") or ct.contains("药") or ct.contains("pill") or pills_eaten >= 8:
		return _perk_by_id("pill_phobia")
	if ct.contains("雷") or ct.contains("劫") or ct.contains("tribulation") or ct.contains("lightning") or fails >= 5:
		return _perk_by_id("tribulation_regular")
	if highest >= 5 or legendary >= 1:
		return _perk_by_id("minor_fate")
	if clicks < 5 or (success <= 1 and age >= 200):
		return _perk_by_id("born_to_chill")
	return _perk_by_id("plain")


func add_reincarnation_history_record(cause: Dictionary, title: Dictionary, perk: Dictionary) -> void:
	var data: Dictionary = main.collect_current_life_data(cause, title)
	var summary := generate_life_summary(cause, title)
	data["summary_zh"] = summary["zh"]
	data["summary_en"] = summary["en"]
	data["punchline_zh"] = main._last_death_punchline.get("zh", "")
	data["punchline_en"] = main._last_death_punchline.get("en", "")
	data["perk_id"] = String(perk.get("id","")) if typeof(perk) == TYPE_DICTIONARY else ""
	data["perk_zh"] = String(perk.get("zh","")) if typeof(perk) == TYPE_DICTIONARY else ""
	data["perk_en"] = String(perk.get("en","")) if typeof(perk) == TYPE_DICTIONARY else ""
	data["time"] = Time.get_datetime_string_from_system()
	main.reincarnation_history.append(data)
	if main.reincarnation_history.size() > 100:
		main.reincarnation_history.pop_front()


func generate_life_summary(cause: Dictionary, _title: Dictionary) -> Dictionary:
	var fails = int(main.state.get("life_breakthrough_fails", 0))
	var success = int(main.state.get("life_breakthrough_success", 0))
	var pills_eaten = int(main.state.get("life_pills_eaten", 0))
	var clicks = int(main.state.get("life_click_count", 0))
	var age: int = main._current_age()
	var highest = int(main.state.get("highest_realm_this_life", 0))
	var legendary = int(main.state.get("life_legendary_count", 0))
	var ct := "%s %s" % [String(cause.get("title_zh","")), String(cause.get("title_en","")).to_lower()]
	var zh := "这一世平平淡淡，没什么好说的。"
	var en := "An unremarkable life, all things considered."
	if ct.contains("炸") or ct.contains("爆") or ct.contains("explosion"):
		zh = "这一世最大的成就是制造了一次响亮的爆炸。结论：丹炉不是玩具。"
		en = "This life's crowning achievement was a very loud explosion. Furnaces are not toys."
	elif ct.contains("雷") or ct.contains("劫") or ct.contains("tribulation"):
		zh = "被雷劈得很有层次。天道大概很喜欢他。"
		en = "Struck by tribulation with real artistry. The heavens had a favorite."
	elif (ct.contains("丹") or ct.contains("药") or ct.contains("pill")) and pills_eaten >= 5:
		zh = "这一世吃丹吃得很有信仰，最后也死在了信仰上。结论：丹药不是饭。"
		en = "A life of devout pill-popping, ended by that devotion. Pills are not food."
	elif legendary >= 1:
		zh = "这一世摸到了一点仙缘，可惜没能走到最后。"
		en = "Brushed against true fortune, but couldn't see it through."
	elif highest >= 5:
		zh = "这一世修为不俗，踏入了先天，已经比大多数同门强了。"
		en = "A strong life — reached the Innate realm, ahead of most peers."
	elif fails > success and fails >= 3:
		zh = "这一世很努力，但突破失败明显多于成功。精神可嘉，方法存疑。"
		en = "Earnest, but undone by far more failed breakthroughs than successful ones."
	elif clicks >= 300:
		zh = "这一世大部分时间都在被戳。修仙是副业，挨戳才是主业。"
		en = "Mostly spent being poked. Cultivation was, at best, a side hustle."
	elif age >= 300:
		zh = "这一世没成大器，但活得是真的久。长寿也是一种本事。"
		en = "Achieved little, but lived remarkably long."
	elif success == 0 and highest <= 1:
		zh = "这一世一事无成，连境界都没怎么动。但至少没惹麻烦。"
		en = "A life of almost nothing — but it stayed out of trouble."
	return {"zh": zh, "en": en}


func build_current_perk_text() -> String:
	var zh = main.current_language == "zh"
	if main.active_reincarnation_perk.is_empty():
		return "轮回天赋：平平无奇" if zh else "Reincarnation Perk: Utterly Ordinary"
	var pn = String(main.active_reincarnation_perk.get("zh","")) if zh else String(main.active_reincarnation_perk.get("en",""))
	var pd = String(main.active_reincarnation_perk.get("desc_zh","")) if zh else String(main.active_reincarnation_perk.get("desc_en",""))
	return ("轮回天赋：%s\n%s" % [pn, pd]) if zh else ("Reincarnation Perk: %s\n%s" % [pn, pd])
