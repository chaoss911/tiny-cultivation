# ═══════════════════════════════════════════════
#  ShopUI — 丹药铺面板
#  自动拆分自 Main.gd（第二包）。Main 持有实例，_ready 注入 main = self
# ═══════════════════════════════════════════════
class_name ShopUi
extends RefCounted

var main   # Main.gd (Control) 引用

func _build_shop() -> void:
	main.shop_panel = PanelContainer.new()
	main.shop_panel.name = "ShopPanel"
	main.shop_panel.add_theme_stylebox_override(
		"panel", main.make_panel_stylebox(Color(0.96, 0.94, 0.88, 0.97), 10))
	main.shop_panel.custom_minimum_size = Vector2(220, 0)
	main.shop_panel.visible = false
	main.add_child(main.shop_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(220, 240)
	main.shop_panel.add_child(scroll)
	main.shop_list = VBoxContainer.new()
	main.shop_list.add_theme_constant_override("separation", 4)
	scroll.add_child(main.shop_list)


func _open_shop() -> void:
	if main.report_panel != null: main.report_panel.visible = false
	if main.profile_panel != null: main.profile_panel.visible = false
	_refresh_shop()
	await main._dock_panel(main.shop_panel)


func _refresh_shop() -> void:
	for child in main.shop_list.get_children():
		child.queue_free()
	var source = DataLoader.pills if not DataLoader.pills.is_empty() else _fallback_pills()
	var realm_idx: int = int(main.state.get("realm_index", 0))
	source = source.filter(func(p): return realm_idx >= int(p.get("min_realm", 0)))
	var header_row := HBoxContainer.new()
	main.shop_list.add_child(header_row)
	var header := Label.new()
	header.text = ("丹药铺  灵石：%d" % main.state["spirit_stones"]) if main.current_language == "zh" \
		else ("Pill Shop  Stones: %d" % main.state["spirit_stones"])
	header.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_shop)
	header_row.add_child(close_btn)
	if source.is_empty():
		var empty := Label.new()
		empty.text = "凡人先好好吃饭。\n丹药铺会在武者后逐步开放。" if main.current_language == "zh" \
			else "Eat proper meals for now.\nPills unlock gradually from the Martial realm."
		empty.add_theme_color_override("font_color", Color(0.4, 0.35, 0.3))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(200, 0)
		main.shop_list.add_child(empty)
		return
	for pill in source:
		var btn := Button.new()
		var pname: String = pill["name_zh"] if main.current_language == "zh" else pill["name_en"]
		btn.text = "%s  (%d)" % [pname, pill["cost"]]
		btn.disabled = main.state["spirit_stones"] < pill["cost"]
		btn.pressed.connect(_on_buy_pill.bind(pill))
		main.shop_list.add_child(btn)


func _close_shop() -> void:
	if main.shop_panel != null:
		main.shop_panel.visible = false


func _on_buy_pill(pill: Dictionary) -> void:
	var min_realm := int(pill.get("min_realm", 0))
	if int(main.state.get("realm_index", 0)) < min_realm:
		main.queue_message(("境界不足，至少需要%s。" % _pill_unlock_text(min_realm)) if main.current_language == "zh" \
			else ("Realm too low. Requires %s." % _pill_unlock_text(min_realm)))
		return
	if main.state["spirit_stones"] < pill["cost"]:
		main.queue_message("灵石不足。" if main.current_language == "zh" else "Not enough stones.")
		return
	main.state["spirit_stones"] -= pill["cost"]
	main.state["life_pills_eaten"] = int(main.state.get("life_pills_eaten", 0)) + 1
	main.state["pills_total_lifetime"] = int(main.state.get("pills_total_lifetime", 0)) + 1
	main.today_stats["pill_eaten"] += 1
	if pill["cultivation_gain"] != 0:
		var pill_mult: float = float(main.reincarnation_modifiers.get("pill_effect_mult", 1.0))
		main.state["cultivation"] = max(0, main.state["cultivation"] + int(pill["cultivation_gain"] * pill_mult))
	if pill["success_bonus"] != 0:
		main.next_breakthrough_bonus += pill["success_bonus"] / 100.0
	main.request_mood(pill["mood"], GameConfig.MoodPriority.EVENT)
	var pname: String = pill["name_zh"] if main.current_language == "zh" else pill["name_en"]
	main.queue_message(("服用%s。" % pname) if main.current_language == "zh" else ("Took %s." % pname))
	main.add_recent_event("服用%s" % pname, "Took %s" % pname, "item")
	main.add_life_history("alchemy", "服用%s" % pname, "他说这是合理的修炼资源分配。")
	await _apply_pill_effects(pill)
	_refresh_shop()
	main.refresh_ui()
	main.save_mgr.save_game()


func _apply_pill_effects(pill: Dictionary) -> void:
	var risk_mult: float = float(main.reincarnation_modifiers.get("pill_risk_mult", 1.0)) * main._personality_bias("alchemy_attempt_mult")

	match pill["id"]:
		"pill_009":
			main.add_effect("fast_cultivation", 60.0, 1.5, "灵感如泉涌！", "Inspiration surges!")
			return
		"pill_010":
			main.add_effect("frenzy", 20.0, 1.0, "狂化！修为暴涨但隐患潜伏。", "Frenzy! Power soars, danger lurks.")
			return
		"pill_014":
			main.add_effect("slow_cultivation", 20.0, 0.85, "心神宁静，但有些困。", "Calm but drowsy.")
			main.request_mood("sleepy", GameConfig.MoodPriority.EVENT)
			return

	match pill.get("side_effect", "none"):
		"restore_lifespan_3":
			main.state["lifespan"] += 3

		"reduce_failure_penalty":
			main.failure_penalty_reduced = true

		"lose_lifespan_2":
			var loss: int = maxi(1, int(round(2.0 * risk_mult)))
			main.state["lifespan"] = int(main.state["lifespan"]) - loss

		"lose_cultivation_10":
			var loss_qi: int = maxi(1, int(round(10.0 * risk_mult)))
			main.state["cultivation"] = maxf(0.0, float(main.state["cultivation"]) - float(loss_qi))

		"random_bad_stomach":
			var chance := clampf(0.5 * risk_mult, 0.05, 0.95)
			if randf() < chance:
				main.add_effect("stomach_ache", 30.0, 1.0, "肚子开始翻江倒海……", "Your stomach churns...")
				main.add_effect("slow_cultivation", 30.0, 0.5, "修为增长变慢了。", "Cultivation slows.")
				main.request_mood("confused", GameConfig.MoodPriority.EVENT)

	if await main.life_cycle.check_lifespan():
		return


func _fallback_pills() -> Array:
	return [
		{"id":"pill_002","name_zh":"小聚气丹","name_en":"Minor Qi Pill","cost":3,"cultivation_gain":15,"mood":"happy","success_bonus":0,"side_effect":"none","min_realm":5},
		{"id":"pill_001","name_zh":"聚气丹","name_en":"Qi Gathering Pill","cost":5,"cultivation_gain":30,"mood":"happy","success_bonus":0,"side_effect":"none","min_realm":5},
		{"id":"pill_009","name_zh":"顿悟丹","name_en":"Insight Pill","cost":80,"cultivation_gain":300,"mood":"meditate","success_bonus":10,"side_effect":"none","min_realm":5},
		{"id":"pill_010","name_zh":"狂化丹","name_en":"Frenzy Pill","cost":10,"cultivation_gain":200,"mood":"confused","success_bonus":-10,"side_effect":"lose_lifespan_2","min_realm":3},
		{"id":"pill_005","name_zh":"筑基丹","name_en":"Foundation Pill","cost":50,"cultivation_gain":0,"mood":"meditate","success_bonus":15,"side_effect":"none","min_realm":7},
		{"id":"pill_007","name_zh":"回春丹","name_en":"Rejuvenation Pill","cost":15,"cultivation_gain":0,"mood":"happy","success_bonus":0,"side_effect":"restore_lifespan_3","min_realm":3}
	]


func _pill_unlock_text(min_realm: int) -> String:
	var idx: int = clampi(min_realm, 0, main.realms.size() - 1)
	return main.realms[idx]["name"] if main.current_language == "zh" else main.realm_names_en[idx]
