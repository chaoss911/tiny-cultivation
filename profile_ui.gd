# ═══════════════════════════════════════════════
#  ProfileUI — 人生面板（属性/履历/图鉴/历史 四 tab）与履历文本构建
#  自动拆分自 Main.gd（第三包）。Main 持有实例，_ready 注入 main = self
# ═══════════════════════════════════════════════
class_name ProfileUi
extends RefCounted

var main   # Main.gd (Control) 引用

func _build_profile_panel() -> void:
	main.profile_panel = PanelContainer.new()
	main.profile_panel.name = "ProfilePanel"
	main.profile_panel.add_theme_stylebox_override(
		"panel", main.make_panel_stylebox(Color(0.95, 0.93, 0.97, 0.97), 10))
	main.profile_panel.custom_minimum_size = Vector2(300, 0)
	main.profile_panel.visible = false
	main.add_child(main.profile_panel)

	var outer_vb := VBoxContainer.new()
	outer_vb.add_theme_constant_override("separation", 0)
	main.profile_panel.add_child(outer_vb)  # ← outer_vb 加到 profile_panel

	# ✕ 按钮行
	var close_row := HBoxContainer.new()
	close_row.custom_minimum_size = Vector2(0, 24)
	close_row.add_theme_constant_override("separation", 0)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0, 0, 0, 0.8))
	close_btn.pressed.connect(_close_profile_panel)
	close_row.add_child(close_btn)
	outer_vb.add_child(close_row)

	main.profile_tabs = TabContainer.new()  # ← 先创建
	main.profile_tabs.custom_minimum_size = Vector2(300, 364)
	outer_vb.add_child(main.profile_tabs)   # ← 再加到 outer_vb

	main.profile_tabs.add_theme_stylebox_override(
		"panel", main.make_panel_stylebox(Color(0.95, 0.93, 0.97, 0.98), 8))
	main.profile_tabs.add_theme_stylebox_override(
		"tab_selected", main.make_panel_stylebox(Color(0.90, 0.87, 0.95, 0.98), 6))
	main.profile_tabs.add_theme_stylebox_override(
		"tab_unselected", main.make_panel_stylebox(Color(0.82, 0.80, 0.86, 0.95), 6))
	main.profile_tabs.add_theme_color_override("font_selected_color", Color(0.2, 0.15, 0.1))
	main.profile_tabs.add_theme_color_override("font_unselected_color", Color(0.4, 0.36, 0.42))

	main.tab_life       = _make_profile_tab()
	main.tab_bio        = _make_profile_tab()
	main.tab_collection = _make_profile_tab()
	main.tab_history    = _make_profile_tab()
	_apply_profile_tab_titles()

	main.profile_list = main.tab_life


func _make_profile_tab() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.profile_tabs.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	return vb


func _apply_profile_tab_titles() -> void:
	if main.profile_tabs == null:
		return
	if main.current_language == "zh":
		main.profile_tabs.set_tab_title(0, "现在的人生")
		main.profile_tabs.set_tab_title(1, "人生履历")
		main.profile_tabs.set_tab_title(2, "成就 & 图鉴")
		main.profile_tabs.set_tab_title(3, "历史记录")
	else:
		main.profile_tabs.set_tab_title(0, "Current Life")
		main.profile_tabs.set_tab_title(1, "Biography")
		main.profile_tabs.set_tab_title(2, "Achv & Codex")
		main.profile_tabs.set_tab_title(3, "History")


func _on_profile() -> void:
	main._mark_interaction()
	AudioManager.play_click()
	if main.profile_panel.visible:
		_close_profile_panel()
		return
	if main.shop_panel != null: main.shop_panel.visible = false
	if main.report_panel != null: main.report_panel.visible = false
	_refresh_profile()
	await main._dock_panel(main.profile_panel)


func _close_profile_panel() -> void:
	await main._undock_panel(main.profile_panel)


func _refresh_profile() -> void:
	if main.profile_tabs == null:
		return
	_apply_profile_tab_titles()
	_refresh_profile_current_life_tab(main.tab_life)
	_refresh_profile_biography_tab(main.tab_bio)
	_refresh_profile_collection_tab(main.tab_collection)
	_refresh_profile_history_tab(main.tab_history)


func _refresh_profile_current_life_tab(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	container.add_theme_constant_override("separation", GameConfig.LIFE_SECTION_GAP)

	var zh: bool = main.current_language == "zh"
	var realm: Dictionary = main.realms[main.state["realm_index"]]

	# ── 上方两栏：基本信息 ｜ 修炼状态 ──
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", GameConfig.LIFE_SECTION_GAP)

	# ① 基本信息
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _life_card_stylebox())
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var info_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		info_margin.add_theme_constant_override("margin_%s" % side, GameConfig.LIFE_CARD_PADDING)
	info_panel.add_child(info_margin)
	var info_vb := _build_life_section_header("res://assets/ui/icon_info.png", "基本信息", "Basic Info")
	info_margin.add_child(info_vb)

	info_vb.add_child(_build_icon_label_value_row("realm", "境界" if zh else "Realm",
		realm["name"] if zh else main.realm_names_en[main.state["realm_index"]]))
	info_vb.add_child(_build_icon_label_value_row("personality", "性情" if zh else "Personality",
		GameConfig.PERSONALITY_META.get(main.current_personality, {}).get("zh" if zh else "en", "未知")))
	info_vb.add_child(_build_icon_label_value_row("job", "职业" if zh else "Job",
		main._mortal_job_label(main.state.get("mortal_job", ""), zh) if String(main.state.get("mortal_job", "")) != "" else ("无" if zh else "None")))
	if main.current_tier() != "凡人":
		var root_text: String = main.state["spiritual_root"] if String(main.state.get("spiritual_root", "")) != "" else "未觉醒"
		if not zh:
			root_text = main.state.get("spiritual_root_en", "Not awakened")
		info_vb.add_child(_build_icon_label_value_row("root", "灵根" if zh else "Root", root_text))
	info_vb.add_child(_build_icon_label_value_row("luck", "气运" if zh else "Luck",
		("%s（%d）" % [main.luck_tier(), int(main.state["luck"])]) if zh else ("%s (%d)" % [main.luck_tier_en(), int(main.state["luck"])])))
	info_vb.add_child(_build_icon_label_value_row("lifespan", "寿元" if zh else "Lifespan",
		("%d年" % int(main.state["lifespan"])) if zh else ("%d years" % int(main.state["lifespan"]))))
	info_vb.add_child(_build_icon_label_value_row("life_count", "第" if zh else "Life",
		("%d 世" % int(main.state.get("life_count", 1))) if zh else ("Life %d" % int(main.state.get("life_count", 1)))))
	var perk_name: String = String(main.active_reincarnation_perk.get("zh" if zh else "en", "平平无奇" if zh else "Utterly Ordinary"))
	info_vb.add_child(_build_icon_label_value_row("perk", "轮回天赋" if zh else "Perk", perk_name))

	columns.add_child(info_panel)

	# ② 修炼状态 (含天道评价子卡片)
	var cult_panel := PanelContainer.new()
	cult_panel.add_theme_stylebox_override("panel", _life_card_stylebox())
	cult_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cult_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		cult_margin.add_theme_constant_override("margin_%s" % side, GameConfig.LIFE_CARD_PADDING)
	cult_panel.add_child(cult_margin)
	var cult_vb := _build_life_section_header("res://assets/ui/icon_fire.png", "修炼状态", "Cultivation")
	cult_margin.add_child(cult_vb)

	var qi_header := HBoxContainer.new()
	qi_header.add_theme_constant_override("separation", 6)
	var qi_icon := TextureRect.new()
	qi_icon.custom_minimum_size = Vector2(GameConfig.LIFE_ICON_SIZE, GameConfig.LIFE_ICON_SIZE)
	qi_header.add_child(qi_icon)
	var qi_label := Label.new()
	qi_label.text = "修为" if zh else "Cultivation"
	qi_label.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
	qi_label.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	qi_header.add_child(qi_label)
	cult_vb.add_child(qi_header)

	var qi_numbers := Label.new()
	qi_numbers.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE + 1)
	qi_numbers.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	cult_vb.add_child(qi_numbers)
	main.qi_numbers_label = qi_numbers

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	var qi_bar := ProgressBar.new()
	qi_bar.min_value = 0
	qi_bar.show_percentage = false
	qi_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qi_bar.custom_minimum_size = Vector2(0, 12)
	var bar_sb_bg := StyleBoxFlat.new()
	bar_sb_bg.bg_color = Color(0.80, 0.76, 0.66)
	bar_sb_bg.set_corner_radius_all(4)
	var bar_sb_fill := StyleBoxFlat.new()
	bar_sb_fill.bg_color = Color(0.42, 0.62, 0.30)
	bar_sb_fill.set_corner_radius_all(4)
	qi_bar.add_theme_stylebox_override("background", bar_sb_bg)
	qi_bar.add_theme_stylebox_override("fill", bar_sb_fill)
	bar_row.add_child(qi_bar)
	main.qi_progress_bar = qi_bar

	var qi_pct := Label.new()
	qi_pct.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
	qi_pct.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	bar_row.add_child(qi_pct)
	main.qi_percent_label = qi_pct
	cult_vb.add_child(bar_row)

	var extra_rows := VBoxContainer.new()
	extra_rows.add_theme_constant_override("separation", 6)
	var insight_row := Label.new()
	insight_row.text = ("突破感悟：%d%%" % int(main.state.get("breakthrough_insight", 0))) if zh \
		else ("Insight: %d%%" % int(main.state.get("breakthrough_insight", 0)))
	insight_row.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
	insight_row.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	extra_rows.add_child(insight_row)
	var stones_row := Label.new()
	stones_row.text = ("灵石：%d" % int(main.state["spirit_stones"])) if zh else ("Stones: %d" % int(main.state["spirit_stones"]))
	stones_row.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
	stones_row.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	extra_rows.add_child(stones_row)
	var clicks_row := Label.new()
	clicks_row.text = ("点击次数：%d" % int(main.state.get("click_count", 0))) if zh else ("Clicks: %d" % int(main.state.get("click_count", 0)))
	clicks_row.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
	clicks_row.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	extra_rows.add_child(clicks_row)
	cult_vb.add_child(extra_rows)

	# ③ 天道评价 — nested sub-card inside 修炼状态, matching the mockup
	var quote_panel := PanelContainer.new()
	var quote_sb := StyleBoxFlat.new()
	quote_sb.bg_color = Color(GameConfig.LIFE_CARD_BG.r + 0.01, GameConfig.LIFE_CARD_BG.g + 0.01, GameConfig.LIFE_CARD_BG.b + 0.01, 1.0)
	quote_sb.set_corner_radius_all(8)
	quote_sb.set_border_width_all(1)
	quote_sb.border_color = GameConfig.LIFE_QUOTE_BORDER
	quote_sb.content_margin_left = 10
	quote_sb.content_margin_right = 10
	quote_sb.content_margin_top = 8
	quote_sb.content_margin_bottom = 8
	quote_panel.add_theme_stylebox_override("panel", quote_sb)
	var quote_vb := VBoxContainer.new()
	quote_vb.add_theme_constant_override("separation", 4)
	var quote_title := Label.new()
	quote_title.text = "天道评价" if zh else "Heaven's Verdict"
	quote_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote_title.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
	quote_title.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	quote_vb.add_child(quote_title)
	var quote_body := Label.new()
	var perk_desc: String = String(main.active_reincarnation_perk.get("desc_zh" if zh else "desc_en", ""))
	quote_body.text = perk_desc
	quote_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote_body.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE + 1)
	quote_body.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	quote_vb.add_child(quote_body)
	quote_panel.add_child(quote_vb)
	cult_vb.add_child(quote_panel)

	columns.add_child(cult_panel)
	container.add_child(columns)


func _refresh_profile_biography_tab(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	var life_rtl := RichTextLabel.new()
	life_rtl.bbcode_enabled = true
	life_rtl.fit_content = true
	life_rtl.scroll_active = false
	life_rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	life_rtl.custom_minimum_size = Vector2(270, 0)
	life_rtl.add_theme_font_size_override("normal_font_size", GameConfig.PROFILE_BODY_SIZE)
	life_rtl.add_theme_font_size_override("bold_font_size", GameConfig.PROFILE_HEADER_SIZE)
	life_rtl.add_theme_color_override("default_color", Color(0.3, 0.25, 0.35))
	life_rtl.text = build_life_history_text()
	container.add_child(life_rtl)


func _refresh_profile_collection_tab(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	# —— 成就 ——
	var ah := Label.new()
	if main.achievement_manager != null:
		ah.text = ("成就 %d/%d" % [main.achievement_manager.unlocked_count(), main.achievement_manager.total_count()]) if main.current_language == "zh" \
			else ("Achievements %d/%d" % [main.achievement_manager.unlocked_count(), main.achievement_manager.total_count()])
	else:
		ah.text = "成就" if main.current_language == "zh" else "Achievements"
	ah.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	ah.add_theme_font_size_override("font_size", GameConfig.PROFILE_HEADER_SIZE)
	container.add_child(ah)
	if main.achievement_manager != null:
		var unlocked_defs = main.achievement_manager.get_unlocked_defs()
		if unlocked_defs.is_empty():
			var none2 := Label.new()
			none2.text = "暂无成就" if main.current_language == "zh" else "None yet."
			none2.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			none2.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
			container.add_child(none2)
		else:
			for a in unlocked_defs:
				var al := Label.new()
				# achievements.csv / AchievementManager use name_zh and name_en.
				# Keep title_* as a fallback so older CSV files still work.
				var at: String = String(a.get("name_zh", a.get("title_zh", ""))) if main.current_language == "zh" \
					else String(a.get("name_en", a.get("title_en", "")))
				var ad: String = String(a.get("desc_zh", "")) if main.current_language == "zh" \
					else String(a.get("desc_en", ""))
				al.text = "  🏆 %s — %s" % [at, ad]
				al.add_theme_color_override("font_color", Color(0.4, 0.32, 0.15))
				al.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
				al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				al.custom_minimum_size = Vector2(270, 0)
				container.add_child(al)
	# —— 图鉴 ——
	container.add_child(HSeparator.new())
	var dc := Label.new()
	dc.text = ("☠️ 死因图鉴   %d / %d" % [main.discovered_death_causes.size(), DataLoader.death_causes.size()]) if main.current_language == "zh" \
		else ("☠️ Death Codex   %d / %d" % [main.discovered_death_causes.size(), DataLoader.death_causes.size()])
	dc.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	dc.add_theme_font_size_override("font_size", GameConfig.PROFILE_HEADER_SIZE)
	container.add_child(dc)
	for cause in DataLoader.death_causes:
		var cid: String = String(cause.get("id", ""))
		if main.discovered_death_causes.has(cid):
			var row_label := Label.new()
			var name_text: String = cause["title_zh"] if main.current_language == "zh" else cause["title_en"]
			row_label.text = "  ☠️ %s" % name_text
			row_label.add_theme_color_override("font_color", Color(0.45, 0.28, 0.28))
			row_label.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
			row_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row_label.custom_minimum_size = Vector2(260, 0)
			container.add_child(row_label)

	var undiscovered: int = DataLoader.death_causes.size() - main.discovered_death_causes.size()
	if undiscovered > 0:
		var hint := Label.new()
		hint.text = ("  还有 %d 种死法等待解锁…" % undiscovered) if main.current_language == "zh" \
			else ("  %d more ways to die, undiscovered..." % undiscovered)
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		hint.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE - 1)
		container.add_child(hint)

	_profile_add_encounter_codex(container)


func _refresh_profile_history_tab(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

	var history_title_label := Label.new()
	history_title_label.text = "🏆 历史纪录" if main.current_language == "zh" else "🏆 Records"
	history_title_label.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	history_title_label.add_theme_font_size_override("font_size", GameConfig.PROFILE_HEADER_SIZE)
	container.add_child(history_title_label)

	var record_text := RichTextLabel.new()
	record_text.bbcode_enabled = true
	record_text.fit_content = true
	record_text.scroll_active = false
	record_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_text.custom_minimum_size = Vector2(270, 0)
	record_text.add_theme_font_size_override("normal_font_size", GameConfig.PROFILE_BODY_SIZE)
	record_text.add_theme_color_override("default_color", Color(0.32, 0.27, 0.34))
	record_text.text = build_record_summary_text()
	container.add_child(record_text)

	container.add_child(HSeparator.new())

	var rh := Label.new()
	rh.text = "轮回记录" if main.current_language == "zh" else "Reincarnations"
	rh.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	rh.add_theme_font_size_override("font_size", GameConfig.PROFILE_HEADER_SIZE)
	container.add_child(rh)

	if not main.reincarnation_history.is_empty():
		var rh_rtl := RichTextLabel.new()
		rh_rtl.bbcode_enabled = true
		rh_rtl.fit_content = true
		rh_rtl.scroll_active = false
		rh_rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rh_rtl.custom_minimum_size = Vector2(270, 0)
		rh_rtl.add_theme_font_size_override("normal_font_size", GameConfig.PROFILE_BODY_SIZE)
		rh_rtl.add_theme_font_size_override("bold_font_size", GameConfig.PROFILE_BODY_SIZE)
		rh_rtl.add_theme_color_override("default_color", Color(0.4, 0.3, 0.3))
		rh_rtl.text = build_reincarnation_history_text()
		container.add_child(rh_rtl)

	elif main.death_history.is_empty():
		var none := Label.new()
		none.text = "第一世进行中……" if main.current_language == "zh" else "Life 1 in progress..."
		none.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		none.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
		container.add_child(none)

	else:
		var start = max(0, main.death_history.size() - 20)
		for i in range(main.death_history.size() - 1, start - 1, -1):
			var death_record = main.death_history[i]
			var hr_zh: String = main.realms[int(death_record["highest_realm"])]["name"]
			var hr_en: String = main.realm_names_en[int(death_record["highest_realm"])]
			var entry := Label.new()

			if main.current_language == "zh":
				entry.text = "  第%d世 · 最高%s · 死于%s" % [
					death_record["life"],
					hr_zh,
					death_record["cause_zh"]
				]
			else:
				entry.text = "  Life %d · Peak %s · %s" % [
					death_record["life"],
					hr_en,
					death_record["cause_en"]
				]

			entry.add_theme_color_override("font_color", Color(0.4, 0.3, 0.3))
			entry.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
			entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			entry.custom_minimum_size = Vector2(270, 0)
			container.add_child(entry)


func _update_profile_detail_live() -> void:
	if main.profile_panel == null or not main.profile_panel.visible:
		return
	if main.qi_progress_bar == null:
		return
	var realm: Dictionary = main.realms[main.state["realm_index"]]
	var need: float = float(realm["need"])
	var cur: float = float(main.state["cultivation"])
	main.qi_progress_bar.max_value = need
	main.qi_progress_bar.value = cur
	if main.qi_numbers_label != null:
		main.qi_numbers_label.text = "%d / %d" % [int(cur), int(need)]
	if main.qi_percent_label != null:
		var pct: float = (cur / need) * 100.0 if need > 0 else 0.0
		main.qi_percent_label.text = "%.2f%%" % pct


func _profile_add_encounter_codex(container: VBoxContainer) -> void:
	container.add_child(HSeparator.new())
	var ch := Label.new()
	var found: int = main.discovered_encounters.size()
	var total: int = main.event_manager.total_encounters() if main.event_manager != null else 40
	ch.text = ("📚 奇遇图鉴   已发现 %d / %d" % [found, total]) if main.current_language == "zh" \
		else ("📚 Encounter Codex   %d / %d" % [found, total])
	ch.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	ch.add_theme_font_size_override("font_size", GameConfig.PROFILE_HEADER_SIZE)
	container.add_child(ch)
	if main.event_manager == null:
		return

	for ev in main.event_manager.get_all_encounter_defs():
		var eid: String = ev["event_id"]
		if not main.discovered_encounters.has(eid):
			continue
		var rarity: String = ev.get("rarity", "rare")
		var icon := "✨" if rarity == "rare" else "🌟"
		var row_label := Label.new()
		var encounter_name: String = ev["text_zh"] if main.current_language == "zh" else ev["text_en"]
		row_label.text = "  %s %s" % [icon, encounter_name]
		row_label.add_theme_color_override("font_color",
			Color(0.85, 0.7, 0.2) if rarity == "legendary" else Color(0.5, 0.45, 0.2))
		row_label.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
		row_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_label.custom_minimum_size = Vector2(260, 0)
		container.add_child(row_label)

	var undiscovered := total - found
	if undiscovered > 0:
		var hint := Label.new()
		hint.text = ("  还有 %d 个奇遇等待发现…" % undiscovered) if main.current_language == "zh" \
			else ("  %d more encounters yet to discover..." % undiscovered)
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		hint.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE - 1)
		container.add_child(hint)


func _life_card_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GameConfig.LIFE_CARD_BG
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = GameConfig.LIFE_CARD_BORDER
	return sb


func _build_life_section_header(icon_path: String, title_zh: String, title_en: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(20, 20)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	header_row.add_child(icon_rect)

	var title_label := Label.new()
	title_label.text = title_zh if main.current_language == "zh" else title_en
	title_label.add_theme_font_size_override("font_size", GameConfig.PROFILE_HEADER_SIZE)
	title_label.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	header_row.add_child(title_label)
	vb.add_child(header_row)

	var rule := HSeparator.new()
	var rule_style := StyleBoxLine.new()
	rule_style.color = GameConfig.LIFE_GOLD_COLOR
	rule_style.thickness = 1
	rule.add_theme_stylebox_override("separator", rule_style)
	vb.add_child(rule)

	return vb


func build_record_summary_text() -> String:
	var zh: bool = main.current_language == "zh"

	var highest_idx: int = _record_highest_realm_index()
	var highest_name: String = ""
	if zh:
		highest_name = String(main.realms[highest_idx].get("name", "未知"))
	else:
		highest_name = String(main.realm_names_en[highest_idx])

	var longest_age: int = _record_longest_lifespan()
	var life_count: int = int(main.state.get("life_count", 1))
	var reincarnations: int = maxi(0, life_count - 1)
	var death_count: int = main.death_history.size()
	var pill_count: int = int(main.state.get("pills_total_lifetime", 0))

	var death_cause_found: int = main.discovered_death_causes.size()
	var death_cause_total: int = DataLoader.death_causes.size()
	var encounter_found: int = main.discovered_encounters.size()

	var encounter_total: int = 120
	if main.event_manager != null:
		encounter_total = int(main.event_manager.total_encounters())

	var most_common: Dictionary = _record_most_common_death_cause()
	var worst_text: String = _record_worst_death_text()

	var lines := PackedStringArray()

	if zh:
		lines.append("[b]最高境界：[/b]%s" % highest_name)
		lines.append("[b]最长寿命：[/b]%d岁" % longest_age)
		lines.append("[b]轮回次数：[/b]%d次" % reincarnations)
		lines.append("[b]死亡次数：[/b]%d次" % death_count)
		var breakthrough_success: int = int(main.state.get("breakthrough_success_total_lifetime", 0))
		var breakthrough_fail    := int(main.state.get("breakthrough_fail_total_lifetime", 0))
		lines.append("[b]突破成功 / 失败：[/b]%d / %d" % [breakthrough_success, breakthrough_fail])
		lines.append("[b]服丹次数：[/b]%d次" % pill_count)

		if int(most_common.get("count", 0)) > 0:
			lines.append("[b]最常见死因：[/b]%s ×%d" % [
				String(most_common.get("text_zh", "")),
				int(most_common.get("count", 0))
			])
		else:
			lines.append("[b]最常见死因：[/b]暂无")

		lines.append("[b]最惨纪录：[/b]%s" % worst_text)
		lines.append("[b]死因图鉴：[/b]%d / %d" % [death_cause_found, death_cause_total])
		lines.append("[b]奇遇图鉴：[/b]%d / %d" % [encounter_found, encounter_total])
		lines.append("[b]传说奇遇：[/b]%d次" % int(main.legendary_encounter_count))
	else:
		lines.append("[b]Highest Realm:[/b] %s" % highest_name)
		lines.append("[b]Longest Life:[/b] Age %d" % longest_age)
		lines.append("[b]Reincarnations:[/b] %d" % reincarnations)
		lines.append("[b]Deaths:[/b] %d" % death_count)
		var breakthrough_success: int = int(main.state.get("breakthrough_success_total_lifetime", 0))
		var breakthrough_fail    := int(main.state.get("breakthrough_fail_total_lifetime", 0))
		lines.append("[b]Breakthroughs / Fails:[/b] %d / %d" % [breakthrough_success, breakthrough_fail])
		lines.append("[b]Pills Taken:[/b] %d" % pill_count)

		if int(most_common.get("count", 0)) > 0:
			lines.append("[b]Most Common Death:[/b] %s ×%d" % [
				String(most_common.get("text_en", "")),
				int(most_common.get("count", 0))
			])
		else:
			lines.append("[b]Most Common Death:[/b] None yet")

		lines.append("[b]Worst Record:[/b] %s" % worst_text)
		lines.append("[b]Death Codex:[/b] %d / %d" % [death_cause_found, death_cause_total])
		lines.append("[b]Encounter Codex:[/b] %d / %d" % [encounter_found, encounter_total])
		lines.append("[b]Legendary Encounters:[/b] %d" % int(main.legendary_encounter_count))

	return "\n".join(lines)


func build_life_history_text() -> String:
	var zh: bool = main.current_language == "zh"
	var current_life_num: int = int(main.state.get("life_count", 1))

	# Chapter-keyed grouping: chapter_id -> Array of normalized entries
	var by_chapter: Dictionary = {}
	for chapter in GameConfig.LIFE_CHAPTERS:
		by_chapter[chapter["id"]] = []

	for raw_entry in main.life_history:
		var entry: Dictionary = main.normalize_life_history_entry(raw_entry)
		if int(entry.get("life", current_life_num)) != current_life_num:
			continue
		var realm_idx: int = int(entry.get("realm_index", 0))
		var age: int = int(entry.get("age", 0))
		var chapter := _chapter_for_entry(realm_idx, age)
		by_chapter[chapter["id"]].append(entry)

	var has_any := false
	for cid in by_chapter:
		if not by_chapter[cid].is_empty():
			has_any = true
			break

	if not has_any:
		return "[b]📖 %s[/b]\n\n%s" % [
			("人生履历" if zh else "Life Records"),
			("这一世还没有重要履历。" if zh else "No important records in this life yet.")
		]

	var text := "[b]📖 %s[/b]\n\n" % ("人生履历" if zh else "Life Records")

	for chapter in GameConfig.LIFE_CHAPTERS:
		var entries: Array = by_chapter[chapter["id"]]
		if entries.is_empty():
			continue

		var chapter_title: String = chapter["zh"] if zh else chapter["en"]
		var blurb := _chapter_blurb(chapter["id"], entries)

		text += "[b][color=#d4af37]── %s ──[/color][/b]\n" % chapter_title
		if blurb != "":
			text += "[i]%s[/i]\n" % blurb

		# Within the chapter, keep your existing category grouping + icons
		var grouped_in_chapter: Dictionary = {}
		for cat in GameConfig.LIFE_HISTORY_CATEGORY_ORDER:
			grouped_in_chapter[cat] = []
		for entry in entries:
			var cat: String = entry.get("category", "encounter")
			if not grouped_in_chapter.has(cat):
				grouped_in_chapter[cat] = []
			grouped_in_chapter[cat].append(entry)

		for cat in GameConfig.LIFE_HISTORY_CATEGORY_ORDER:
			var cat_entries: Array = grouped_in_chapter.get(cat, [])
			if cat_entries.is_empty():
				continue
			var meta: Dictionary = GameConfig.LIFE_HISTORY_CATEGORY_META.get(cat, GameConfig.LIFE_HISTORY_CATEGORY_META["encounter"])
			var icon: String = meta.get("icon", "✨")
			var start_index: int = max(0, cat_entries.size() - GameConfig.LIFE_HISTORY_MAX_PER_CATEGORY)
			for i in range(start_index, cat_entries.size()):
				text += "  %s " % icon + format_life_history_entry(cat_entries[i])

		text += "\n"

	return text.strip_edges()


func format_life_history_entry(entry: Dictionary) -> String:
	var zh: bool = main.current_language == "zh"
	var life_num: int = int(entry.get("life", 1))
	var entry_age: int = int(entry.get("age", 0))
	var realm_idx: int = int(entry.get("realm_index", 0))
	var realm: String = main.realms[realm_idx]["name"] if zh else main.realm_names_en[realm_idx]
	var title: String = str(entry.get("title_zh", "")) if zh else str(entry.get("title_en", ""))
	var description: String = str(entry.get("description_zh", "")) if zh else str(entry.get("description_en", ""))
	var line := ""
	if zh:
		line = "• 第%d世｜%d岁｜%s｜%s" % [life_num, entry_age, realm, title]
		if description != "":
			line += "：%s" % description
	else:
		line = "• L%d · Age %d · %s · %s" % [life_num, entry_age, realm, title]
		if description != "":
			line += " — %s" % description
	return line + "\n"


func _chapter_blurb(_chapter_id: String, entries: Array) -> String:
	var zh: bool = main.current_language == "zh"
	var counts := {}
	for entry in entries:
		var cat: String = entry.get("category", "encounter")
		counts[cat] = int(counts.get(cat, 0)) + 1

	var death_count: int = int(counts.get("death", 0))
	var breakthrough_count: int = int(counts.get("breakthrough", 0))
	var encounter_count: int = int(counts.get("encounter", 0))
	var alchemy_count: int = int(counts.get("alchemy", 0))

	if death_count > 0:
		return "这一章以陨落告终。" if zh else "This chapter ended in death."
	if encounter_count >= 3:
		return "充满奇遇的一段时光。" if zh else "A time full of strange encounters."
	if alchemy_count >= 3:
		return "炼丹炸炉的一段日子。" if zh else "A period marked by alchemy and explosions."
	if breakthrough_count >= 2:
		return "修为突飞猛进的一段时光。" if zh else "A period of rapid cultivation progress."
	if entries.size() <= 1:
		return "平静无事的一段时光。" if zh else "A quiet, uneventful stretch."
	return ""   # no strong signal -> say nothing rather than force a generic blurb


func _chapter_for_life_record(r: Dictionary) -> Dictionary:
	var realm_idx: int = int(r.get("highest_realm", 0))
	var age: int = int(r.get("age", 0))
	return _chapter_for_entry(realm_idx, age)


func _chapter_for_entry(realm_idx: int, age: int) -> Dictionary:
	for chapter in GameConfig.LIFE_CHAPTERS:
		var min_r: int = int(chapter.get("min_realm_index", 0))
		var max_r: int = int(chapter.get("max_realm_index", 99))
		if realm_idx < min_r or realm_idx > max_r:
			continue
		if chapter.has("max_age") and age > int(chapter["max_age"]):
			continue
		if chapter.has("min_age") and age < int(chapter["min_age"]):
			continue
		return chapter
	return GameConfig.LIFE_CHAPTERS.back()   # fallback: last-defined chapter, never crash on an edge case


func build_reincarnation_history_text() -> String:
	var zh: bool = main.current_language == "zh"
	if main.reincarnation_history.is_empty():
		return ""

	# Group completed lives by which chapter they peaked in.
	var by_chapter: Dictionary = {}
	for chapter in GameConfig.LIFE_CHAPTERS:
		by_chapter[chapter["id"]] = []

	var start: int = maxi(0, main.reincarnation_history.size() - 10)
	for i in range(main.reincarnation_history.size() - 1, start - 1, -1):
		var r = main.reincarnation_history[i]
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var chapter := _chapter_for_life_record(r)
		by_chapter[chapter["id"]].append(r)

	var text := ""
	# Reverse chapter order: most-advanced era first, since that's usually
	# what a returning player wants to see — "how far did past lives get."
	for ci in range(GameConfig.LIFE_CHAPTERS.size() - 1, -1, -1):
		var chapter: Dictionary = GameConfig.LIFE_CHAPTERS[ci]
		var lives: Array = by_chapter[chapter["id"]]
		if lives.is_empty():
			continue

		var chapter_title: String = chapter["zh"] if zh else chapter["en"]
		text += "[b][color=#d4af37]── %s 时代 ──[/color][/b]\n" % chapter_title if zh \
			else "[b][color=#d4af37]── %s Era ──[/color][/b]\n" % chapter_title

		for r in lives:
			var realm_name := String(r.get("highest_realm_zh","")) if zh else String(r.get("highest_realm_en",""))
			var cause_name := String(r.get("cause_zh","")) if zh else String(r.get("cause_en",""))
			var ttl := String(r.get("title_zh","")) if zh else String(r.get("title_en",""))
			var perk_name := String(r.get("perk_zh","")) if zh else String(r.get("perk_en",""))
			var summ := String(r.get("summary_zh","")) if zh else String(r.get("summary_en",""))
			if zh:
				text += "[b]第 %d 世｜享年 %d 岁｜最高：%s[/b]\n" % [int(r.get("life",0)), int(r.get("age",0)), realm_name]
				if cause_name != "": text += "死因：%s\n" % cause_name
				if ttl != "": text += "称号：%s\n" % ttl
				if perk_name != "": text += "天赋：%s\n" % perk_name
				if summ != "": text += "总结：%s\n" % summ
			else:
				text += "[b]Life %d ｜ Age %d ｜ Peak: %s[/b]\n" % [int(r.get("life",0)), int(r.get("age",0)), realm_name]
				if cause_name != "": text += "Cause: %s\n" % cause_name
				if ttl != "": text += "Title: %s\n" % ttl
				if perk_name != "": text += "Perk: %s\n" % perk_name
				if summ != "": text += "Summary: %s\n" % summ
			text += "\n"

	return text.strip_edges()


func _build_icon_label_value_row(icon_key: String, label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(GameConfig.LIFE_ICON_SIZE, GameConfig.LIFE_ICON_SIZE)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path: String = GameConfig.LIFE_FIELD_ICONS.get(icon_key, "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	row.add_child(icon_rect)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(GameConfig.LIFE_LABEL_WIDTH, 0)
	label.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
	label.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", GameConfig.PROFILE_BODY_SIZE)
	value.add_theme_color_override("font_color", GameConfig.LIFE_INK_COLOR)
	row.add_child(value)

	return row


# ── 死亡/生涯统计（第四包并入：调用方全部在本模块）──

func _record_most_common_death_cause() -> Dictionary:
	var counts := {}
	var labels_zh := {}
	var labels_en := {}

	for d in main.death_history:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var cause_zh := String(d.get("cause_zh", ""))
		var cause_en := String(d.get("cause_en", cause_zh))
		if cause_zh.strip_edges() == "":
			continue
		counts[cause_zh] = int(counts.get(cause_zh, 0)) + 1
		labels_zh[cause_zh] = cause_zh
		labels_en[cause_zh] = cause_en

	var best_key := ""
	var best_count := 0
	for key in counts.keys():
		var c := int(counts[key])
		if c > best_count:
			best_count = c
			best_key = String(key)

	if best_key == "":
		return {"text_zh": "", "text_en": "", "count": 0}
	return {
		"text_zh": String(labels_zh.get(best_key, best_key)),
		"text_en": String(labels_en.get(best_key, best_key)),
		"count": best_count
	}


func _record_worst_death_text() -> String:
	var zh = main.current_language == "zh"
	if main.death_history.is_empty():
		return "暂无惨案" if zh else "None yet"

	var thunder_streak := _record_longest_death_keyword_streak(["雷", "渡劫", "天劫"], ["thunder", "tribulation", "lightning"])
	if thunder_streak >= 2:
		return ("连续被雷劈 %d 次" % thunder_streak) if zh else ("Struck by tribulation %d lives in a row" % thunder_streak)

	var common := _record_most_common_death_cause()
	if int(common.get("count", 0)) >= 2:
		return ("%s ×%d" % [common.get("text_zh", ""), int(common.get("count", 0))]) if zh else ("%s ×%d" % [common.get("text_en", ""), int(common.get("count", 0))])

	var last = main.death_history.back()
	if typeof(last) == TYPE_DICTIONARY:
		return String(last.get("cause_zh", "未知死因")) if zh else String(last.get("cause_en", "Unknown death"))
	return "未知死因" if zh else "Unknown death"


func _record_longest_death_keyword_streak(zh_keywords: Array, en_keywords: Array) -> int:
	var current := 0
	var best := 0
	for d in main.death_history:
		if typeof(d) != TYPE_DICTIONARY:
			current = 0
			continue
		var text := "%s %s" % [String(d.get("cause_zh", "")), String(d.get("cause_en", ""))]
		if _record_contains_any(text, zh_keywords) or _record_contains_any(text.to_lower(), en_keywords):
			current += 1
			best = max(best, current)
		else:
			current = 0
	return best


func _record_highest_realm_index() -> int:
	var highest = int(main.state.get("realm_index", 0))
	for d in main.death_history:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		highest = max(highest, int(d.get("highest_realm", 0)))
	return clampi(highest, 0, main.realms.size() - 1)


func _record_longest_lifespan() -> int:
	var longest: int = main._current_age()
	for d in main.death_history:
		if typeof(d) == TYPE_DICTIONARY and d.has("age"):
			longest = max(longest, int(d.get("age", 0)))
	for rec in main.life_records:
		if typeof(rec) == TYPE_DICTIONARY and String(rec.get("type", "")) == "death":
			longest = max(longest, int(rec.get("age", 0)))
	for raw_entry in main.life_history:
		var entry: Dictionary = main.normalize_life_history_entry(raw_entry)
		if String(entry.get("category", "")) == "death":
			longest = max(longest, int(entry.get("age", 0)))
	return longest


func _record_contains_any(text: String, keywords: Array) -> bool:
	for k in keywords:
		if text.contains(String(k)):
			return true
	return false
