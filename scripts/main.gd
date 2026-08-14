extends Control

# ── 拆分模块（game_config.gd / save_manager.gd / animation_controller.gd）──
var save_mgr := SaveManager.new()
var anim_ctl := AnimationController.new()
var shop_ui := ShopUi.new()
var certificate_ui := CertificateUi.new()
var report_ui := ReportUi.new()
var profile_ui := ProfileUi.new()
var life_cycle := LifeCycle.new()
var event_popup := EventPopupUi.new()
var world_state: WorldState
var modifier_layer: ModifierLayer
var animation_modifier: AnimationModifier
var _quitting := false
# DEMO
var memorable_events: Array = []        # this life's highlights reel, cleared on reincarnation
var _foreshadow_flags: Dictionary = {}  # tag -> {"day_set": int, "expires_day": int}, cleared on reincarnation
var _pending_decision: Dictionary = {}
var decision_indicator: Button
var decision_bubble: PanelContainer
var _indicator_tween: Tween
var furniture: FurnitureManager
var cave: CaveController

func _todays_highlight_tag() -> String:
	for tag in GameConfig.DAILY_HIGHLIGHT_PRIORITY:
		if _today_event_tags.has(tag):
			return tag
	return "none"

func _todays_memorable_highlight() -> Dictionary:
	for mem in memorable_events:
		if int(mem.get("age", -1)) == _current_age():   # set today, age hasn't moved since
			return mem
	return {}

# ── Layout tuning ──
	
var last_autosave_time := 0.0

var _last_death_punchline: Dictionary = {"zh": "", "en": ""}
var death_cause_first_punchline: Dictionary = {}


# ══════════════════════════════════════════
#  PERSONALITY SYSTEM
# ══════════════════════════════════════════



# The bias vector. Every system below reads from this, keyed by current_personality.
# Values are multipliers (1.0 = neutral) or direct overrides — see per-system notes.



var current_personality := "lazy"
var _personality_drift: Dictionary = {}  # trait_name -> accumulated pressure, reset on reincarnation
# NARRATIVE ONLY — never wire this into any chance/multiplier calculation.
# This is a text-selection bias for Dialogue/Status, not a stat.
var _instinct_tag: String = ""

func _personality_bias(key: String, default_val: float = 1.0) -> float:
	var traits: Dictionary = GameConfig.PERSONALITY_BIAS.get(current_personality, {})
	return float(traits.get(key, default_val))


func _weighted_string_pick(weights: Dictionary) -> String:
	var total := 0.0
	for v in weights.values():
		total += float(v)
	if total <= 0.0:
		return String(weights.keys().back())
	var roll := randf() * total
	var acc := 0.0
	for key in weights.keys():
		acc += float(weights[key])
		if roll < acc:
			return String(key)
	return String(weights.keys().back())


func roll_personality(previous_life_data: Dictionary, cause: Dictionary, perk: Dictionary) -> String:
	var ct := "%s %s" % [String(cause.get("title_zh","")), String(cause.get("type",""))]
	var perk_id := String(perk.get("id", ""))
	var clicks: int = int(previous_life_data.get("life_click_count", 0))
	var fails: int = int(previous_life_data.get("life_breakthrough_fails", 0))
	var pills_eaten: int = int(previous_life_data.get("life_pills_eaten", 0))

	# Strong narrative hooks — checked in priority order, first match wins
	if perk_id == "boom_expert" or ct.contains("炸") or ct.contains("爆"):
		return "reckless"
	if perk_id == "pill_phobia":
		return "cautious"
	if perk_id == "tribulation_regular" and fails >= 5:
		return "diligent"
	if clicks >= 500:
		return "eccentric"
	if pills_eaten >= 10:
		return "greedy"

	# Soft fallback: weighted random, keeps unpredictability for "uneventful" lives
	var fallback_weights := {
		"reckless": 1.0, "cautious": 1.0, "greedy": 1.0,
		"lazy": 2.0, "diligent": 1.0, "eccentric": 1.0
	}
	return _weighted_string_pick(fallback_weights)

func _roll_mortal_job() -> Dictionary:
	# Pure roll: returns a job without mutating state.
	var bias: Dictionary = GameConfig.PERSONALITY_JOB_WEIGHT.get(current_personality, {})
	var weights: Array[float] = []
	var total := 0.0

	for job in GameConfig.MORTAL_JOBS:
		var weight := maxf(0.0, float(bias.get(job["id"], 1.0)))
		weights.append(weight)
		total += weight

	if total <= 0.0:
		return GameConfig.MORTAL_JOBS.pick_random()

	var roll := randf() * total
	var accumulated := 0.0
	for i in GameConfig.MORTAL_JOBS.size():
		accumulated += weights[i]
		if roll < accumulated:
			return GameConfig.MORTAL_JOBS[i]

	return GameConfig.MORTAL_JOBS.back()

# NARRATIVE ONLY — biases which Dialogue/Status lines get picked, never a multiplier.
func _roll_instinct(previous_life_data: Dictionary, cause: Dictionary) -> String:
	var anim_key := String(cause.get("animation", "")).strip_edges()
	if anim_key == "death_tribulation":
		return "wary_of_tribulation"
	if anim_key == "death_explosion":
		return "drawn_to_furnaces"
	if int(previous_life_data.get("life_legendary_count", 0)) >= 1:
		return "seeks_encounters"
	return ""

func _is_echo_worthy(record: Dictionary) -> bool:
	var highest: int = int(record.get("highest_realm", 0))
	var legendary: int = int(record.get("life_legendary_count", 0))
	var fails: int = int(record.get("life_breakthrough_fails", 0))
	var pills: int = int(record.get("life_pills_eaten", 0))
	return highest >= 5 or legendary >= 1 or fails >= 8 or pills >= 15


func _has_echo_worthy_past_life() -> bool:
	for r in reincarnation_history:
		if typeof(r) == TYPE_DICTIONARY and _is_echo_worthy(r):
			return true
	return false

func _nudge_personality(target_trait: String, amount: float = 1.0) -> void:
	if not GameConfig.PERSONALITY_TRAITS.has(target_trait) or target_trait == current_personality:
		return
	_personality_drift[target_trait] = float(_personality_drift.get(target_trait, 0.0)) + amount
	if _personality_drift[target_trait] >= GameConfig.PERSONALITY_DRIFT_THRESHOLD:
		var old := current_personality
		current_personality = target_trait
		_personality_drift.clear()
		add_life_history(
			"skill",
			"性情转变",
			"从「%s」渐渐变成了「%s」。" % [GameConfig.PERSONALITY_META[old]["zh"], GameConfig.PERSONALITY_META[target_trait]["zh"]],
			"Personality Shift",
			"Gradually shifted from %s to %s." % [GameConfig.PERSONALITY_META[old]["en"], GameConfig.PERSONALITY_META[target_trait]["en"]]
		)


func _tier_at_least(target: String) -> bool:
	var current_idx: int = GameConfig.TIER_ORDER.find(current_tier())
	var target_idx: int = GameConfig.TIER_ORDER.find(target)
	return current_idx >= target_idx
	

var profile_tabs: TabContainer
var tab_life: VBoxContainer
var tab_bio: VBoxContainer
var tab_collection: VBoxContainer
var tab_history: VBoxContainer
var reincarnation_history: Array = []          # 完整轮回总结，最多存 100 世
var active_reincarnation_perk: Dictionary = {}  # 当前世天赋
var reincarnation_modifiers: Dictionary = {}    # 天赋换算出的数值修正（不存档，读档时重算）
var last_feed_time := -999999.0   # uses Time.get_ticks_msec() / 1000.0, not saved across sessions
var life_flags: Dictionary = {}            # flag_name -> true，转世清空
var _scheduled_chain_unlocks: Array = []   # [{"id":String,"unlock_day":int}]
var _day_counter: int = 0                  # 累计天数，用于 cooldown_days

# ── DEMO 节奏时钟（只在 DEMO_MODE 下使用）──
var _life_elapsed: float = 0.0       # 本世已经过了多少秒（挂机时走得慢）
var _demo_session_elapsed: float = 0.0   # 本次试玩总时长，用于 30 分钟硬性保护
var _demo_day_accum: float = 0.0     # demo 内「一天」的累加器
var _demo_death_waiting: float = -1.0    # >=0 表示死亡已就绪、正在等玩家回来
var _achievement_unlocked_today: Dictionary = {}  # title_zh -> true, cleared at rollover

var _today_event_tags: Dictionary = {}      # tag -> true, cleared at midnight rollover
var _yesterday_event_tags: Dictionary = {}  # snapshot of _today_event_tags before clearing
var event_manager: EventManager
var current_state := "cultivate"
var mood := "normal"
var current_language := "zh"
var anim_for_mood := {
	"normal":   "breath",
	"meditate": "meditate",
	"happy":    "happy",
	"alchemy":  "breath",
	"confused": "confused",
	"sleepy":   "sleeping",
	"walking":  "walking",
	"lazy":     "lazy",
	"workout":  "workout",
	"eat":      "eat",
	"angry":    "angry",
	"stomachache": "stomachache",
	"luck":     "luck",
	"dunwu":    "dunwu",
	"legendary": "legendary",
	"breakthrough_success": "breakthrough_success",
	"breakthrough_fail": "breakthrough_fail",
	"thunder": "thunder",
}

var anim_x_offset := {
	"breath": -0.2,
	"happy": 1.6,
	"lazy": 2.1,
	"confused": -5.6,
	"meditate": 1.2,
	"sleeping": 1.1,
	"workout": -10.0,
	"walking": 0.0,
}
var discovered_encounters: Dictionary = {}   # event_id -> true
var rare_encounter_count := 0
var legendary_encounter_count := 0
var next_breakthrough_bonus := 0.0
var failure_penalty_reduced := false
var pending_chains: Array = []
var demo_completed := false
var realm_strip: VBoxContainer
var realm_strip_label: Label
var toast_panel: PanelContainer
var toast_label: RichTextLabel
var toast_queue: Array = []
var toast_showing := false
var active_effects: Array = []
var reports: Array = []
var report_panel
var report_list: VBoxContainer
var profile_panel: PanelContainer
var profile_list: VBoxContainer
var _reincarnating := false
var _certificate_open := false
var _drag_moved := false
var _pending_event_log = []
var achievement_manager: AchievementManager
var _pending_achievements = {}  
var REINCARNATION_BONUS_PER_LIFE := 0.02     # +2% cultivation per life
var REINCARNATION_BONUS_CAP := 0.50          # +50% max
var _msg_token := 0
var _press_pos := Vector2.ZERO
var life_records: Array = []   # [{age, zh, en, type}] biography, oldest-first
var recent_events: Array = []  # [{time, zh, en, type}] feed, last 20
var sound_enabled := true
var poke_streak := 0
var last_poke_time := -9999.0


# ──────────────────────────────────────────────────────────
#  洞府家具
# ──────────────────────────────────────────────────────────

func _setup_furniture() -> void:
	furniture = FurnitureManager.new(self)

	# 洞府面板自己管窗口/缩放/布局（跟 achievement_ui、report_ui 同一套规矩）
	if cave_ui != null:
		cave_ui.main = self
		cave_ui.build_panel()

	cave = CaveController.new(self, furniture, cave_ui)
	event_manager.event_resolved.connect(furniture.on_event_resolved)


# ── 人生履历（分类美化系统）──
# 每条 entry: {life, age, realm, category, title, description, time}
var life_history: Array = []



var last_interaction_time := 0.0
var is_afk := false


var flavor_dialogues := [
	{"zh": "今天决定开始努力。", "en": "Decided to work hard today."},
	{"zh": "结果努力了五分钟。", "en": "...lasted five minutes."},
	{"zh": "二狗又领先我了。",   "en": "Ergou is ahead of me again."},
]


func _roll_root_tier() -> String:
	var luck: int = int(state.get("luck", 50))
	var legendary_chance := 0.0
	var rare_chance := 0.0
	if luck <= 30:
		rare_chance = 0.08
	elif luck <= 70:
		rare_chance = 0.20
	elif luck <= 90:
		rare_chance = 0.40
	else:
		rare_chance = 0.55
		legendary_chance = 0.05
	var roll := randf()
	if roll < legendary_chance:
		return "legendary"
	elif roll < legendary_chance + rare_chance:
		return "rare"
	else:
		return "common"




func _mortal_job_label(job_id: String, zh: bool) -> String:
	for j in GameConfig.MORTAL_JOBS:
		if j["id"] == job_id:
			return j["zh"] if zh else j["en"]
	return "未知" if zh else "Unknown"

func _assign_mortal_job() -> Dictionary:
	var job := _roll_mortal_job()
	state["mortal_job"] = job["id"]
	return job


var message_queue: Array = []
var is_showing_message := false
var context_menu: PopupMenu
var bubble_panel: PanelContainer
var bubble_label: RichTextLabel
var bubble_tail: Polygon2D
var death_history: Array = []                # [{life, highest_realm, cause_zh, cause_en, time}]
var discovered_death_causes: Dictionary = {} # cause_id -> true (for variety achievement)
var shop_panel: PanelContainer
var shop_list: VBoxContainer

var today_stats := {
	"date": "", "qi_gain": 0, "stone_gain": 0, "pill_eaten": 0,
	"sleep_count": 0, "fall_count": 0,
	"breakthrough_attempt": 0, "breakthrough_success": 0,
	"clicks_today": 0
}
var realms := [
	{"name": "引气一层", "need": 1000},
	{"name": "引气二层", "need": 1800},
	{"name": "引气三层", "need": 3200},
	{"name": "武者初期", "need": 6000},
	{"name": "武者中期", "need": 12000},
	{"name": "先天初期", "need": 22000},
	{"name": "先天大成", "need": 42000},
	{"name": "炼气一层", "need": 90000}
]

var realm_names_en = [
	"Qi Drawing I", "Qi Drawing II", "Qi Drawing III",
	"Martial Early", "Martial Mid", "Innate Early", "Innate Peak", "Qi Refining I"
]

var _click_special := {
	1: {"zh": "干嘛？", "en": "What?"},
	5: {"zh": "别戳了。", "en": "Stop poking me."},
	10: {"zh": "我在修炼！", "en": "I'm cultivating here!"},
	20: {"zh": "你是不是老板？", "en": "Are you my boss or something?"},
	50: {"zh": "再戳我要走火入魔了。", "en": "Poke again and I'll go qi-deviant."},
	100: {"zh": "你没别的事吗？", "en": "Don't you have anything better to do?"},
	500: {"zh": "你是真的闲。", "en": "You are truly bored."},
	1000: {"zh": "我悟了，你才是心魔。", "en": "I see it now — YOU are the inner demon."}
}

var state := {
	"realm_index": 0, "cultivation": 0.0, "spirit_stones": 0,
	"lifespan": 80, "last_saved_unix": 0, "luck": 50, "luck_date": "",
	"life_count": 1, "highest_realm_this_life": 0, "reincarnation_bonus": 0.0,
	"click_count": 0, "pet_name": "","mortal_job": "", "spiritual_root": "",
	"breakthrough_insight": 0,"life_click_count": 0,
	"life_breakthrough_fails": 0,
	"life_breakthrough_success": 0,
	"life_pills_eaten": 0,
	"life_legendary_count": 0,
	"life_rare_count": 0,
	"language": "zh",
	"breakthrough_success_total_lifetime": 0,
	"breakthrough_fail_total_lifetime": 0,
	"pills_total_lifetime": 0,
	"cultivation_age": 16
}

var dragging := false
var drag_start_mouse := Vector2i.ZERO
var drag_start_window := Vector2i.ZERO

@onready var pet_group: Node2D = $PetGroup
@onready var language_button = get_node_or_null("PetGroup/VBox/Buttons/Language")
@onready var cultivator_sprite = $PetGroup/CultivatorSprite
@onready var status_label = $PetGroup/StatusLabel
@onready var title_label = $PetGroup/VBox/Title
@onready var realm_label: Label = $PetGroup/VBox/Realm
@onready var progress_bar = $PetGroup/VBox/Progress
@onready var stats_label = $PetGroup/VBox/Stats
@onready var feed_button = $PetGroup/VBox/Buttons/FeedPill       # → 吃饭 Eat
@onready var meditate_button = $PetGroup/VBox/Buttons/Meditate   # → 履历 Profile
@onready var info_button = $PetGroup/VBox/Buttons/Info           # → 事件 Events (report panel)


# ══════════════════════════════════════════
#  ANIMATION
# ══════════════════════════════════════════


var name_dialog: PanelContainer
var name_edit: LineEdit
var name_title_label: Label
var name_subtitle_label: Label
var name_confirm_button: Button
var name_lang_zh_button: Button
var name_lang_en_button: Button
var name_random_button: Button

var random_names_zh := [
	"小白", "二狗", "阿尘", "小玄", "小咸鱼",
	"丹炉哥", "小道童", "阿福", "灵石仔", "摆烂仙"
]

var random_names_en := [
	"Xiao Bai", "Ergou", "Dusty", "Tiny Dao", "Little Fish",
	"Pill Bro", "Dao Kid", "Lucky", "Stone Boy", "Lazy Sage"
]



func _build_name_dialog() -> void:
	name_dialog = PanelContainer.new()
	name_dialog.name = "NameDialog"
	name_dialog.custom_minimum_size = Vector2(230, 190)
	name_dialog.visible = false
	name_dialog.z_index = 200
	add_child(name_dialog)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.96, 0.89, 0.73, 0.98)
	panel_sb.set_corner_radius_all(12)
	panel_sb.set_border_width_all(3)
	panel_sb.border_color = Color(0.50, 0.34, 0.16, 0.95)
	panel_sb.shadow_color = Color(0, 0, 0, 0.22)
	panel_sb.shadow_size = 6
	panel_sb.content_margin_left = 16
	panel_sb.content_margin_right = 16
	panel_sb.content_margin_top = 12
	panel_sb.content_margin_bottom = 14
	name_dialog.add_theme_stylebox_override("panel", panel_sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	name_dialog.add_child(vb)

	# 语言选择
	var lang_row := HBoxContainer.new()
	lang_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lang_row.add_theme_constant_override("separation", 6)
	vb.add_child(lang_row)

	name_lang_zh_button = Button.new()
	name_lang_zh_button.text = "中文"
	name_lang_zh_button.custom_minimum_size = Vector2(58, 26)
	name_lang_zh_button.pressed.connect(func():
		_set_language("zh")
	)
	lang_row.add_child(name_lang_zh_button)

	name_lang_en_button = Button.new()
	name_lang_en_button.text = "EN"
	name_lang_en_button.custom_minimum_size = Vector2(58, 26)
	name_lang_en_button.pressed.connect(func():
		_set_language("en")
	)
	lang_row.add_child(name_lang_en_button)

	name_title_label = Label.new()
	name_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_title_label.add_theme_font_size_override("font_size", 15)
	name_title_label.add_theme_color_override("font_color", Color(0.30, 0.18, 0.08))
	vb.add_child(name_title_label)

	name_subtitle_label = Label.new()
	name_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_subtitle_label.add_theme_font_size_override("font_size", 11)
	name_subtitle_label.add_theme_color_override("font_color", Color(0.48, 0.34, 0.18))
	vb.add_child(name_subtitle_label)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "小白"
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(150, 28)
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER

	var edit_sb := StyleBoxFlat.new()
	edit_sb.bg_color = Color(1.0, 0.96, 0.84, 0.98)
	edit_sb.set_corner_radius_all(6)
	edit_sb.set_border_width_all(2)
	edit_sb.border_color = Color(0.62, 0.43, 0.22, 0.9)
	edit_sb.content_margin_left = 8
	edit_sb.content_margin_right = 8
	edit_sb.content_margin_top = 3
	edit_sb.content_margin_bottom = 3

	name_edit.add_theme_stylebox_override("normal", edit_sb)
	name_edit.add_theme_stylebox_override("focus", edit_sb)
	name_edit.add_theme_color_override("font_color", Color(0.25, 0.16, 0.08))
	name_edit.add_theme_color_override("font_placeholder_color", Color(0.62, 0.50, 0.36))

# 名字输入框 + 随机按钮放同一行
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 6)
	vb.add_child(name_row)

	name_row.add_child(name_edit)

	name_random_button = Button.new()
	name_random_button.text = "随机" if current_language == "zh" else "Random"
	name_random_button.custom_minimum_size = Vector2(60, 28)
	name_random_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_random_button.pressed.connect(_roll_random_name)
	name_row.add_child(name_random_button)

	name_confirm_button = Button.new()
	name_confirm_button.custom_minimum_size = Vector2(92, 32)
	name_confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.55, 0.36, 0.15, 0.95)
	btn_sb.set_corner_radius_all(8)
	btn_sb.content_margin_left = 14
	btn_sb.content_margin_right = 14
	btn_sb.content_margin_top = 6
	btn_sb.content_margin_bottom = 6

	var btn_sb_hover := btn_sb.duplicate()
	btn_sb_hover.bg_color = Color(0.66, 0.45, 0.20, 0.98)

	var btn_sb_pressed := btn_sb.duplicate()
	btn_sb_pressed.bg_color = Color(0.42, 0.26, 0.11, 0.98)

	name_confirm_button.add_theme_stylebox_override("normal", btn_sb)
	name_confirm_button.add_theme_stylebox_override("hover", btn_sb_hover)
	name_confirm_button.add_theme_stylebox_override("pressed", btn_sb_pressed)
	name_confirm_button.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78))
	name_confirm_button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.84))
	name_confirm_button.pressed.connect(_on_name_confirmed)
	vb.add_child(name_confirm_button)

	_refresh_name_dialog_text()
	
# ══════════════════════════════════════════
#  STYLE HELPERS / BUILDERS
# ══════════════════════════════════════════

func make_panel_stylebox(bg_color: Color, corner_radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(corner_radius)
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 5
	sb.content_margin_bottom = 5
	return sb

var _bubble_home_pos: Vector2 = Vector2(-110, -148)
var _bubble_tail_home_pos: Vector2 = Vector2(-30, -78)

func _build_speech_bubble() -> void:
	bubble_tail = Polygon2D.new()
	bubble_tail.color = Color(1.0, 1.0, 1.0, 0.93)
	bubble_tail.polygon = PackedVector2Array([
		Vector2(-8, 0), Vector2(8, 0), Vector2(0, 12)
	])
	bubble_tail.position = Vector2(-30, -78)
	bubble_tail.visible = false
	pet_group.add_child(bubble_tail)

	bubble_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.93)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.15)
	sb.shadow_size  = 4
	sb.content_margin_left   = 10
	sb.content_margin_right  = 10
	sb.content_margin_top    = 6
	sb.content_margin_bottom = 6
	bubble_panel.add_theme_stylebox_override("panel", sb)
	bubble_panel.custom_minimum_size = Vector2(GameConfig.BUBBLE_MIN_W, 0)
	bubble_panel.position = Vector2(-110, -148)
	bubble_panel.visible  = false
	pet_group.add_child(bubble_panel)

	bubble_label = RichTextLabel.new()
	bubble_label.bbcode_enabled  = true
	bubble_label.fit_content     = true
	bubble_label.autowrap_mode   = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.custom_minimum_size = Vector2(GameConfig.BUBBLE_MIN_W, 0)
	bubble_label.add_theme_font_size_override("normal_font_size", GameConfig.BUBBLE_FONT)
	bubble_label.add_theme_color_override("default_color", Color(0.12, 0.12, 0.12))
	bubble_panel.add_child(bubble_label)
	






func _build_realm_strip() -> void:
	realm_strip = VBoxContainer.new()
	realm_strip.add_theme_constant_override("separation", 2)
	realm_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	pet_group.add_child(realm_strip)
 
	realm_strip_label = Label.new()
	realm_strip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	realm_strip_label.add_theme_color_override("font_color", Color(0.97, 0.90, 0.70))
	realm_strip_label.add_theme_font_size_override("font_size", 14)
	realm_strip_label.add_theme_constant_override("outline_size", 3)
	realm_strip_label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05, 0.85))
	realm_strip.add_child(realm_strip_label)
	realm_strip.visible = false   # 角色身上不显示境界名（境界只在「人生」面板里看）

func _mark_interaction() -> void:
	last_interaction_time = Time.get_ticks_msec() / 1000.0
	if is_afk:
		is_afk = false
		clear_mood_priority()
		request_mood("normal", GameConfig.MoodPriority.AMBIENT)

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.name = "ToastPanel"
	# 新皮肤：米色卡片底（side_panel 九宫格），素材缺失时纸色兜底
	var toast_sb := StyleBoxTexture.new()
	if ResourceLoader.exists("res://assets/ui/side_panel.png"):
		toast_sb.texture = load("res://assets/ui/side_panel.png")
		toast_sb.texture_margin_left = 26
		toast_sb.texture_margin_right = 26
		toast_sb.texture_margin_top = 26
		toast_sb.texture_margin_bottom = 26
		toast_sb.content_margin_left = 18
		toast_sb.content_margin_right = 18
		toast_sb.content_margin_top = 14
		toast_sb.content_margin_bottom = 14
		toast_panel.add_theme_stylebox_override("panel", toast_sb)
	else:
		var toast_fb := StyleBoxFlat.new()
		toast_fb.bg_color = Color(0.95, 0.91, 0.83, 0.97)
		toast_fb.set_corner_radius_all(12)
		toast_fb.set_border_width_all(2)
		toast_fb.border_color = Color(0.56, 0.42, 0.26)
		toast_fb.content_margin_left = 14
		toast_fb.content_margin_right = 14
		toast_fb.content_margin_top = 10
		toast_fb.content_margin_bottom = 10
		toast_panel.add_theme_stylebox_override("panel", toast_fb)
	toast_panel.custom_minimum_size = Vector2(GameConfig.TOAST_W, 0)
	toast_panel.visible = false
	add_child(toast_panel)

	toast_label = RichTextLabel.new()
	toast_label.bbcode_enabled = true
	toast_label.fit_content = true
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.custom_minimum_size = Vector2(GameConfig.TOAST_W - 16, 0)
	toast_label.add_theme_color_override("default_color", Color(0.95, 0.93, 0.88))
	toast_label.add_theme_font_size_override("normal_font_size", 13)
	if GameConfig.body_font() != null:
		toast_label.add_theme_font_override("normal_font", GameConfig.body_font())
	if GameConfig.brush_font() != null:
		toast_label.add_theme_font_override("bold_font", GameConfig.brush_font())
	toast_label.add_theme_color_override("default_color", Color(0.28, 0.20, 0.12))
	toast_panel.add_child(toast_label)

	toast_panel.gui_input.connect(func (e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			report_ui._open_report_panel()
	)


func _build_context_menu() -> void:
	context_menu = PopupMenu.new()
	add_child(context_menu)
	_rebuild_context_menu()
	context_menu.id_pressed.connect(_on_context_menu_id)


func _rebuild_context_menu() -> void:
	context_menu.clear()
	var mute_label := ("🔇 静音" if sound_enabled else "🔊 开启声音") if current_language == "zh" \
		else ("🔇 Mute" if sound_enabled else "🔊 Unmute")
	# 洞府 —— 临时入口，等真正的入口（门 / 事件解锁）做出来就删掉这一项
	context_menu.add_item("进入洞府" if current_language == "zh" else "Enter Cave", 1)
	# 调试用：直接给蒲团，不用真的连修三天。验证完删掉。
	context_menu.add_item("[调试] 解锁蒲团", 6)
	context_menu.add_separator()
	context_menu.add_item("改名" if current_language == "zh" else "Rename", 2)
	context_menu.add_item(mute_label, 3)
	context_menu.add_separator()
	context_menu.add_item("重置存档…" if current_language == "zh" else "Reset Save…", 4)
	context_menu.add_separator()
	context_menu.add_item("退出" if current_language == "zh" else "Quit", 5)

func _on_context_menu_id(id: int) -> void:
	_mark_interaction()
	match id:
		1:
			_open_cave()
		6:
			if furniture != null:
				furniture.set_condition_flag("cultivated_three_days")
		2:
			_open_name_dialog()
		3:
			sound_enabled = not sound_enabled
			AudioManager.set_sound_enabled(sound_enabled)
			_rebuild_context_menu()
			save_mgr.save_game()
		4:
			_confirm_reset()
		5:
			_on_quit_requested()

func _open_cave() -> void:
	if _is_cutscene_blocking():
		return
	if cave_ui == null or cave_ui.panel == null:
		push_warning("[cave] 面板还没建好")
		return

	# 关掉别的大面板 —— 窗口尺寸归 cave_ui.open() 自己管
	if main_hall_panel != null and main_hall_panel.visible:
		await _close_main_hall(false)
	if profile_panel != null: profile_panel.visible = false
	if shop_panel != null: shop_panel.visible = false
	if report_panel != null: report_panel.visible = false
	if achievement_ui != null and achievement_ui.panel != null:
		achievement_ui.panel.visible = false

	cave_ui.open()


func _confirm_reset() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "重置存档" if current_language == "zh" else "Reset Save"
	dialog.dialog_text = "确定要清除所有进度重新开始吗？此操作无法撤销。" if current_language == "zh" \
		else "Delete all progress and start over? This cannot be undone."
	dialog.add_button("取消" if current_language == "zh" else "Cancel", true, "cancel")
	dialog.confirmed.connect(_do_reset)
	add_child(dialog)
	dialog.popup_centered()

func _do_reset() -> void:
	# 删除存档文件
	if FileAccess.file_exists(GameConfig.SAVE_PATH):
		DirAccess.remove_absolute(GameConfig.SAVE_PATH)
	# 重启场景
	get_tree().reload_current_scene()

# ══════════════════════════════════════════
#  READY
# ══════════════════════════════════════════
func _on_window_size_changed() -> void:
	call_deferred("update_layout")
	call_deferred("_reposition_overlay_panels")

func _reposition_overlay_panels() -> void:
	var win := get_viewport_rect().size

	if name_dialog != null and name_dialog.visible:
		name_dialog.position = (win - name_dialog.size) / 2.0

	if intro_panel != null and intro_panel.visible:
		intro_panel.position = (win - intro_panel.size) / 2.0

	if certificate_panel != null and certificate_panel.visible:
		certificate_panel.position = (win - certificate_panel.size) / 2.0

	if report_panel != null and report_panel.visible:
		report_panel.position = Vector2(win.x - report_panel.size.x - GameConfig.REPORT_MARGIN, GameConfig.REPORT_Y)

	if profile_panel != null and profile_panel.visible:
		profile_panel.position = Vector2(win.x - profile_panel.size.x - GameConfig.REPORT_MARGIN, GameConfig.REPORT_Y)

	if toast_panel != null and toast_panel.visible:
		var ts := toast_panel.size
		toast_panel.position.x = clamp(
			toast_panel.position.x,
			GameConfig.TOAST_MARGIN,
			win.x - ts.x - GameConfig.TOAST_MARGIN
		)

func _ready() -> void:
	# 注意：洞府家具的初始化不在这里 —— event_manager 这时候还没建好。
	# 见下方 _setup_furniture()，在 EventManager 创建之后调用。
	#
	# ── 已移除：透明贴底带的窗口设置 ──────────────────────────────
	# 原本这里会把窗口改成 全屏宽 × 300px 的透明置顶带，并设 unresizable。
	# 它跟下面的 WIN_NORMAL / WIN_WIDE / WIN_MAIN 三档尺寸切换互相打架，
	# 面板打开时会被压成一小块。既然形态已经改回窗口，整段删掉。
	# 以后要做贴底带，另开一个 window_mode.gd，别塞在 _ready() 开头。
	# ──────────────────────────────────────────────────────────

	save_mgr.main = self
	anim_ctl.main = self
	shop_ui.main = self
	certificate_ui.main = self
	report_ui.main = self
	profile_ui.main = self
	life_cycle.main = self
	event_popup.main = self
	randomize()
	get_tree().set_auto_accept_quit(false)
	get_window().size = GameConfig.WIN_NORMAL
	get_window().mode = Window.MODE_WINDOWED
	get_window().size_changed.connect(_on_window_resized)
	get_window().borderless = true
	get_window().unresizable = true
	get_window().size_changed.connect(_on_window_size_changed)
	_timer = Timer.new()
	_timer.wait_time = GameConfig.DEATH_INTERVAL
	_timer.timeout.connect(_do_one_death)
	add_child(_timer)
	_build_counter_overlay()
	achievement_ui.main = self                     # _ready 注入区
	achievement_ui.build_panel()
	
	var screen_size := DisplayServer.screen_get_size()
	var start_pos := Vector2i(
		int(round((screen_size.x - GameConfig.WIN_NORMAL.x) / 2.0)),
		int(round((screen_size.y - GameConfig.WIN_NORMAL.y) / 2.0))
	)
	DisplayServer.window_set_position(start_pos)

	get_window().transparent = true
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_speech_bubble()
	_build_decision_ui()
	shop_ui._build_shop()
	report_ui._build_report_panel()
	profile_ui._build_profile_panel()
	_build_toast()
	certificate_ui._build_certificate_panel() 
	event_popup.build_popup()
	_build_intro_panel()
	_build_main_hall()
	_build_context_menu()
	world_state = WorldState.new(self)
	modifier_layer = ModifierLayer.new(self)
	animation_modifier = AnimationModifier.new(self)

	modifier_layer.setup($PetGroup)
	animation_modifier.setup($PetGroup/PropAnchor)

	# 情境变化时：重刷视觉层 + 重刷当前动画的修饰
	world_state.context_changed.connect(func() -> void:
		modifier_layer.apply(world_state)
		if cultivator_sprite != null:
			animation_modifier.apply(cultivator_sprite, cultivator_sprite.animation, world_state))

# ★ 关键：这一行替代了 AnimationController.play() 包装
# main.gd 有五处直接调 cultivator_sprite.play()，加包装函数没用。
# AnimatedSprite2D 的 animation_changed 信号能一次性覆盖全部调用点。
	cultivator_sprite.animation_changed.connect(func() -> void:
		animation_modifier.apply(cultivator_sprite, cultivator_sprite.animation, world_state))

	modifier_layer.apply(world_state, true)
	if OS.is_debug_build() and not has_node("ModifierDebugPanel"):
		var _dbg := ModifierDebugPanel.new()
		add_child(_dbg)
		_dbg.bind(world_state)
	achievement_manager = AchievementManager.new()
	achievement_manager.main = self
	achievement_manager.load_csv()

	$PetGroup/VBox.add_theme_stylebox_override(
		"panel", make_panel_stylebox(Color(0.93, 0.93, 0.93, 0.88), 10))
	var vbox := $PetGroup/VBox
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.scale = Vector2(GameConfig.VBOX_SCALE, GameConfig.VBOX_SCALE)
	$PetGroup/VBox.z_index = 100
	$PetGroup/StatusLabel.z_index = 100
	$PetGroup/SpeechLabel.z_index = 100

	save_mgr.load_game()
	achievement_manager.record_login_today()
	achievement_manager.check_all()
	_rebuild_context_menu()
	AudioManager.set_sound_enabled(sound_enabled)
	grant_offline_rewards()

	# EventManager (created before connecting / using it)
	
	event_manager = EventManager.new()
	event_manager.story_moment_created.connect(_on_story_moment_created)
	add_child(event_manager)
	event_manager.from_save(_pending_event_log)
	event_manager.setup(
		func (): return current_state,
		Callable(self, "_apply_event_reward"),
		func (zh, en, rarity):
			if rarity in ["rare", "legendary"]:
				return   # 稀有/传说由 _on_encounter 弹卷轴，这里不重复出气泡
			event_popup.show_popup_light({"zh": zh, "en": en}),
			# 回退成气泡：注释上一行，恢复 queue_message("💭 " + (zh if current_language == "zh" else en))
		func (): return current_language
	)
	event_manager.luck_provider = func (): return int(state.get("luck", 50))
	event_manager.realm_provider = func (): return int(state.get("realm_index", 0))   # ← add
	event_manager.encounter_handler = Callable(self, "_on_encounter")
	event_manager.special_animation_handler = Callable(self, "_on_event_special_animation")
	event_manager.history_hook = Callable(self, "_on_event_biography")
	event_manager.encounter_fired.connect(func (_e):
		if profile_panel != null and profile_panel.visible:
			profile_ui._refresh_profile()
	)
	event_manager.log_updated.connect(func ():
		if report_panel != null and report_panel.visible:
			report_ui._refresh_reports()
	)

	achievement_manager.check_all()
	# refresh 人生 panel live when something unlocks
	achievement_manager.achievement_unlocked.connect(func (a):
		if typeof(a) == TYPE_DICTIONARY:
			var atitle_zh := String(a.get("title_zh", ""))
			var atitle_en := String(a.get("title_en", ""))
			if atitle_zh != "" or atitle_en != "":
				add_life_history("achievement", "获得成就：%s" % atitle_zh, "",
					"Achievement Unlocked: %s" % atitle_en, "")
		if profile_panel != null and profile_panel.visible:
			profile_ui._refresh_profile()
	)
	# Buttons: 吃饭 / 履历 / 事件
	feed_button.pressed.connect(_on_feed)
	meditate_button.pressed.connect(_open_main_hall)
	info_button.pressed.connect(report_ui._on_report_pressed)

	_check_daily_report()
	anim_ctl._build_animations()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	status_label.scroll_active = false
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.custom_minimum_size = Vector2(120, 0)
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	status_label.add_theme_constant_override("outline_size", 2)
	
	var timer := Timer.new()
	timer.wait_time = GameConfig.TICK_SECONDS
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()

	var effect_timer := Timer.new()
	effect_timer.wait_time = 1.0
	effect_timer.timeout.connect(_tick_effects)
	add_child(effect_timer)
	effect_timer.start()

	_schedule_next_report_event()
	
	_schedule_next_dialogue()
	_build_realm_strip()

	_schedule_next_status()
	update_status()

	feed_button.text = _feed_button_text()
	meditate_button.text = "人生" if current_language == "zh" else "Profile"
	info_button.text     = "事件" if current_language == "zh" else "Events"
	$PetGroup/VBox.visible = false
	if language_button != null:
		language_button.visible = false   # language now lives in the right-click menu

	title_label.visible  = false
	realm_label.visible  = false
	progress_bar.visible = false
	stats_label.visible  = false

	call_deferred("update_layout")
	refresh_ui()
	
	last_interaction_time = Time.get_ticks_msec() / 1000.0

	var afk_timer := Timer.new()
	afk_timer.wait_time = 10.0
	afk_timer.timeout.connect(_check_afk)
	add_child(afk_timer)
	afk_timer.start()
	_build_quick_bar()
	_build_name_dialog()
	if String(state.get("pet_name", "")).strip_edges() == "":
		_open_name_dialog()
	elif String(state.get("mortal_job", "")).strip_edges() == "":
			# 旧存档兜底：有名字但从未分配过第一世职业
		_assign_mortal_job()
		save_mgr.save_game()
	roll_daily_luck()

	# 放在 _ready() 最末尾：这里一旦报错，后面的代码就不会执行。
	# （之前插在中间，结果 info_button 的 connect 没跑到，事件面板点不开。）
	_setup_furniture()

func _check_afk() -> void:
	if _is_intro_blocking():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not is_afk and (now - last_interaction_time) >= GameConfig.AFK_THRESHOLD_SECONDS:
		is_afk = true
		request_mood("lazy", GameConfig.MoodPriority.SYSTEM)
		
var _is_first_naming := false

func _set_main_ui_visible(visible: bool) -> void:
	if pet_group != null:
		pet_group.visible = visible

	if quick_bar != null:
		_set_quick_visible(visible)

	if not visible:
		_hide_transient_ui()

func _is_cutscene_blocking() -> bool:
	return _reincarnating or _certificate_open or _is_intro_blocking()

func _gameplay_blocked() -> bool:
	return _is_cutscene_blocking() or (GameConfig.DEMO_MODE and demo_completed)

func _hide_transient_ui() -> void:
	if bubble_panel != null:
		bubble_panel.visible = false
	if bubble_tail != null:
		bubble_tail.visible = false
	if status_label != null:
		status_label.visible = false
	if toast_panel != null:
		toast_panel.visible = false

func _process(delta: float) -> void:
	world_state.tick(delta, _day_counter, current_tier())
		
func _try_find_spirit_stone() -> void:
	var find_chance := 0.015 * (1.0 + luck_modifier() * 10.0)
	if randf() >= find_chance:
		return

	state["spirit_stones"] = int(state.get("spirit_stones", 0)) + 1
	today_stats["stone_gain"] = int(today_stats.get("stone_gain", 0)) + 1
	if achievement_manager != null:
		achievement_manager.record_stones_picked(1)
	_today_event_tags["found_stone"] = true
	add_recent_event("捡到1灵石", "Found 1 spirit stone", "stone")


func _open_name_dialog() -> void:
	_is_first_naming = String(state.get("pet_name", "")).strip_edges() == ""

	if name_edit != null:
		name_edit.text = String(state.get("pet_name", ""))

	_set_main_ui_visible(false)

	var safe_pos := _get_safe_window_position(GameConfig.WIN_WIDE)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = GameConfig.WIN_WIDE
	await get_tree().process_frame
	update_layout()

	name_dialog.visible = true
	name_dialog.z_index = 200
	request_mood("normal", GameConfig.MoodPriority.SYSTEM)

	if event_manager != null:
		event_manager.set_paused(true)

	name_dialog.size = Vector2.ZERO
	await get_tree().process_frame

	var win := get_viewport_rect().size
	var target := (win - name_dialog.size) / 2.0
	target.x = max(0.0, target.x)
	target.y = max(0.0, target.y)
	name_dialog.position = target
	name_edit.grab_focus()

func _sanitize_cultivator_name(raw_name: String) -> String:
	var n := raw_name.strip_edges()
	n = n.replace("\n", "")
	n = n.replace("\t", "")
	n = n.replace("\r", "")

	# 防止玩家输入超长名字；LineEdit 已经 max_length = 12，这里再兜底一次
	if n.length() > 12:
		n = n.substr(0, 12)

	if n == "":
		n = "Xiao Bai" if current_language == "en" else "小白"

	return n

func _on_name_confirmed() -> void:
	var n := _sanitize_cultivator_name(name_edit.text)

	state["pet_name"] = n

	if _is_first_naming and String(state.get("mortal_job", "")).strip_edges() == "":
		var job = _assign_mortal_job()
		var job_label_zh: String = job["zh"]
		var job_label_en: String = job["en"]
		add_life_history(
		"birth",
		"凡人出世",
		"%s 在桌面角落醒来，踏上修仙路。今生职业：%s。" % [n, job_label_zh],
		"Mortal Awakens",
		"%s woke up in the corner of the desktop and set out on the path of cultivation. Job this life: %s." % [n, job_label_en]
	)

	name_dialog.visible = false

	save_mgr.save_game()
	refresh_ui()

	if _is_first_naming:
		# 第一世：不要马上显示角色
		# 先显示 intro panel，等玩家点掉 intro 后才显示角色
		_show_intro_sequence(n)
	else:
		# 改名：直接回到游戏
		_set_main_ui_visible(true)
		clear_mood_priority()
		if event_manager != null:
			event_manager.set_paused(false)
		get_window().size = GameConfig.WIN_NORMAL
		show_message_now(("我叫%s。" % n) if current_language == "zh" else ("I'm %s." % n))
		
# ══════════════════════════════════════════
#  LAYOUT
# ══════════════════════════════════════════

func _pet_area_center_x() -> float:
	var win := get_viewport_rect().size

	# 打开事件/人生/商店/toast 等宽窗口时，
	# 角色永远留在左侧正常区域，不跟着整个宽窗口居中
	if int(win.x) > GameConfig.WIN_NORMAL.x + 20:
		return GameConfig.WIN_NORMAL.x / 2.0

	# 普通小窗口时才居中
	return win.x / 2.0

func update_layout() -> void:
	# 主面板开着时：布局由大厅接管，不按桌宠小窗重排（否则突破/换动画会把角色拽回左上角）
	if main_hall_panel != null and main_hall_panel.visible:
		var win := Vector2(get_window().size)
		pet_group.position = Vector2(win.x / 2.0, win.y * GameConfig.MH_PET_Y_RATIO)
		pet_group.scale = Vector2(1.5, 1.5)
		return
	pet_group.position = Vector2(_pet_area_center_x(), GameConfig.PETGROUP_Y)

	cultivator_sprite.centered = true
	cultivator_sprite.scale = Vector2(GameConfig.SPRITE_SCALE, GameConfig.SPRITE_SCALE)
	cultivator_sprite.position = Vector2(0, GameConfig.SPRITE_Y)

	status_label.position.y = GameConfig.REALM_STRIP_Y
	_center_status_label()

	var vbox = $PetGroup/VBox
	vbox.size = Vector2.ZERO
	await get_tree().process_frame

	var vbox_w: float = vbox.size.x * vbox.scale.x
	vbox.position = Vector2(-vbox_w / 2.0, GameConfig.VBOX_Y)

	if realm_strip != null:
		realm_strip.size = Vector2.ZERO
		await get_tree().process_frame
		realm_strip.position = Vector2(-realm_strip.size.x / 2.0, GameConfig.REALM_STRIP_Y + GameConfig.REALM_STRIP_OFFSET_Y)
# ══════════════════════════════════════════
#  TIER
# ══════════════════════════════════════════

func current_tier() -> String:
	if state["realm_index"] <= 2:
		return "凡人"
	elif state["realm_index"] <= 4:
		return "武者"
	elif state["realm_index"] <= 6:
		return "先天"
	else:
		return "炼气"


# ══════════════════════════════════════════
#  MOOD / STATE
# ══════════════════════════════════════════

func _state_from_mood(m: String) -> String:
	match m:
		"meditate": return "cultivate"
		"sleepy":   return "sleep"
		"alchemy":  return "alchemy"
		"workout":  return "workout"
		"lazy":     return "lazy"
		_:          return "cultivate"

func _is_intro_blocking() -> bool:
	return (name_dialog != null and name_dialog.visible) or (intro_panel != null and intro_panel.visible)


func set_mood(new_mood: String) -> void:
	mood = new_mood
	current_state = _state_from_mood(new_mood)
	if cultivator_sprite == null:
		return
	var base_anim: String = anim_for_mood.get(mood, "breath")
	var tier := current_tier()
	var suffix: String = GameConfig.TIER_ANIM_SUFFIX.get(tier, "")
	var anim := "%s_%s" % [suffix, base_anim]   # 比如 "martial_breath"
	print("[mood] 请求mood=", new_mood, " base_anim=", base_anim, " 尝试播放=", anim) 
	if suffix != "" and cultivator_sprite.sprite_frames != null and cultivator_sprite.sprite_frames.has_animation(anim):
		cultivator_sprite.play(anim)
		var offset: float = anim_x_offset.get(anim, anim_x_offset.get(base_anim, 0.0))
		cultivator_sprite.position.x = -offset * GameConfig.SPRITE_SCALE
	elif cultivator_sprite.sprite_frames != null and cultivator_sprite.sprite_frames.has_animation(base_anim):
		# 没有对应境界素材时（比如炼气期），兜底播放不带境界后缀的旧动画，不报错
		cultivator_sprite.play(base_anim)
		var fallback_offset: float = anim_x_offset.get(base_anim, 0.0)
		cultivator_sprite.position.x = -fallback_offset * GameConfig.SPRITE_SCALE

# ══════════════════════════════════════════
#  STATUS CHANNEL
# ══════════════════════════════════════════

func _schedule_next_status() -> void:
	var wait := randf_range(GameConfig.STATUS_MIN_SEC, GameConfig.STATUS_MAX_SEC)
	if is_afk:
		wait *= 2.0

	get_tree().create_timer(wait).timeout.connect(func():
		if not is_afk and not _gameplay_blocked():
			update_status()

		_schedule_next_status()
	)

func _schedule_next_dialogue() -> void:
	var wait := randf_range(6.0, 12.0)
	if is_afk:
		wait *= 2.0

	get_tree().create_timer(wait).timeout.connect(func():
		if not is_afk and not _gameplay_blocked():
			random_dialogue()

		# Always schedule the next cycle, including while AFK.
		_schedule_next_dialogue()
	)

func update_status() -> void:
	if _is_cutscene_blocking():
		return
	
	var tier := current_tier()
	# 后面保持原本代码
	var pool = DataLoader.statuses.filter(func(status_row): return status_row["realm"] == tier)
	if pool.is_empty():
		pool = DataLoader.statuses   # ← 改回 statuses
	pool = pool.filter(func(status_row):
		var req: String = String(status_row.get("require_flag", ""))
		var inst: String = String(status_row.get("instinct_tag", ""))
		if inst != "" and inst != _instinct_tag:
			return false
		return req == "" or life_flags.has(req)
	)
	pool = _job_flavor_pool(DataLoader.job_statuses, pool)
	if pool.is_empty():
		return
	var ctx := _build_dialogue_context()
	var scored: Array = []
	for row in pool:
		var s := _score_context_row(row, ctx)
		if s > 0:
			scored.append({"row": row, "score": s})
	if scored.is_empty():
		return
	var picked_status: Dictionary = _weighted_pick_scored(scored)
	var text: String = picked_status["zh"] if current_language == "zh" else picked_status["en"]
	if not request_mood(picked_status["mood"], GameConfig.MoodPriority.AMBIENT):
		return
	var color_hex := _default_color_for_mood(picked_status["mood"])
	var hint_text := "拖动窗口移动｜挂机会自动修炼" if current_language == "zh" \
	else "Drag to move  |  Idle = auto cultivate"
	status_label.text = "[center][b][color=#%s]%s[/color][/b][/center]" % [color_hex, text]
	status_label.visible = true
	call_deferred("_center_status_label")


func _center_status_label() -> void:
	status_label.position.x = -status_label.size.x / 2


# ══════════════════════════════════════════
#  DIALOGUE CHANNEL
# ══════════════════════════════════════════

func queue_dialogue(zh: String, en: String) -> void:
	queue_message(zh if current_language == "zh" else en)


func random_dialogue() -> void:
	if _is_cutscene_blocking():
		return

	var tier := current_tier()
	var pool = DataLoader.dialogues.filter(func(dialogue_row): return dialogue_row["realm"] == tier or dialogue_row["realm"] == "")
	if pool.is_empty():
		pool = DataLoader.dialogues   # ← 改回 dialogues
	pool = pool.filter(func(dialogue_row):
		var req: String = String(dialogue_row.get("require_flag", ""))
		return req == "" or life_flags.has(req)
	)

	if int(state.get("life_count", 1)) < 20:
		pool = pool.filter(func(dialogue_row): return not String(dialogue_row.get("id", "")).begins_with("self_"))

	pool = _job_flavor_pool(DataLoader.job_dialogues, pool)
	if pool.is_empty():
		var f = flavor_dialogues.pick_random()
		queue_dialogue(f["zh"], f["en"])
		return

	var ctx := _build_dialogue_context()
	var scored: Array = []
	for row in pool:
		var s := _score_context_row(row, ctx)
		if s > 0:
			scored.append({"row": row, "score": s})

	if scored.is_empty():
		var f2 = flavor_dialogues.pick_random()
		queue_dialogue(f2["zh"], f2["en"])
		return

	var picked_dialogue: Dictionary = _weighted_pick_scored(scored)
	if String(picked_dialogue.get("sets_foreshadow", "")) != "":
		_set_foreshadow(String(picked_dialogue["sets_foreshadow"]), int(picked_dialogue.get("foreshadow_days", 3)))
	if String(picked_dialogue.get("soul_echo", "")) == "true" and achievement_manager != null:
		achievement_manager.record_soul_echo_seen()
	queue_message(picked_dialogue["chinese"] if current_language == "zh" else picked_dialogue["english"])

func _weighted_pick_scored(scored: Array) -> Dictionary:
	var total := 0
	for s in scored:
		total += int(s["score"])
	var roll := randi() % total
	var acc := 0
	for s in scored:
		acc += int(s["score"])
		if roll < acc:
			return s["row"]
	return scored.back()["row"]

func _build_dialogue_context() -> Dictionary:
	var ctx := {}
	ctx["realm_tier"] = current_tier()
	ctx["luck_tier"] = luck_tier_key()
	ctx["personality"] = current_personality
	ctx["health_tier"] = _lifespan_health_tier()
	ctx["recent_fail_streak"] = int(state.get("life_breakthrough_fails", 0)) >= 2
	ctx["goal"] = _current_goal_tag()
	ctx["today_event_tags"] = _today_event_tags
	ctx["yesterday_event_tags"] = _yesterday_event_tags
	ctx["memorable_events"] = memorable_events
	ctx["soul_echo_available"] = _has_echo_worthy_past_life() or int(state.get("life_count", 1)) > 1
	ctx["instinct_tag"] = _instinct_tag
	return ctx

func luck_tier_key() -> String:
	# Reuses the same thresholds as luck_tier()/luck_tier_en(), but returns a
	# stable English key instead of a display string, since this feeds CSV matching.
	var l: int = state["luck"]
	if l <= 10: return "terrible"
	if l <= 30: return "bad"
	if l <= 70: return "normal"
	if l <= 90: return "good"
	return "blessed"


func _lifespan_health_tier() -> String:
	# Lifespan remaining as a fraction of what this realm typically grants.
	# Cheap proxy: under 15 absolute years left = "critical", under 40 = "low".
	var l: int = int(state.get("lifespan", 80))
	if l <= 15: return "critical"
	if l <= 40: return "low"
	return "normal"


func _current_goal_tag() -> String:
	# "Goal" = whatever the player is visibly working toward right now.
	# This reuses existing thresholds rather than inventing a goal-tracking system.
	if int(state.get("realm_index", 0)) >= 5 and String(state.get("spiritual_root", "")) == "":
		return "awaiting_root"
	var realm: Dictionary = realms[state["realm_index"]]
	var progress: float = float(state["cultivation"]) / float(realm["need"])
	if progress >= 0.85:
		return "near_breakthrough"
	if int(state.get("breakthrough_insight", 0)) >= 60:
		return "banking_insight"
	return "cultivating"

# ══════════════════════════════════════════
#  STATUS EFFECTS
# ══════════════════════════════════════════

func add_effect(type: String, duration: float, magnitude: float, label_zh: String, label_en: String) -> void:
	active_effects.append({
		"type": type, "remaining": duration, "magnitude": magnitude,
		"label_zh": label_zh, "label_en": label_en
	})
	queue_message(label_zh if current_language == "zh" else label_en)


func cultivation_multiplier() -> float:
	var mult := 1.0
	for e in active_effects:
		if e["type"] == "slow_cultivation" or e["type"] == "fast_cultivation":
			mult *= e["magnitude"]
	mult *= (1.0 + float(state.get("reincarnation_bonus", 0.0)))
	mult *= spiritual_root_multiplier()   
	mult *= float(reincarnation_modifiers.get("cultivation_mult", 1.0))
	if GameConfig.DEMO_MODE:
		mult *= _demo_life_cult_mult()
	return mult


func has_effect(type: String) -> bool:
	for e in active_effects:
		if e["type"] == type:
			return true
	return false


func _tick_effects() -> void:
	if _is_intro_blocking():
		return
	if active_effects.is_empty():
		return
	var expired: Array = []
	for e in active_effects:
		e["remaining"] -= 1.0
		if e["remaining"] <= 0:
			expired.append(e)
	for e in expired:
		active_effects.erase(e)
		_on_effect_expired(e)
	if not expired.is_empty():
		refresh_ui()


func _on_effect_expired(e: Dictionary) -> void:
	match e["type"]:
		"stomach_ache":
			queue_message("肚子终于不疼了。" if current_language == "zh" else "The ache fades.")
		"slow_cultivation":
			queue_message("修炼速度恢复正常。" if current_language == "zh" else "Cultivation speed normal.")
		"fast_cultivation":
			queue_message("药力散去。" if current_language == "zh" else "The pill's power fades.")
		"frenzy":
			add_effect("slow_cultivation", 15.0, 0.6,
				"狂化反噬，浑身无力。", "Frenzy backlash — weakened.")
			request_mood("confused", GameConfig.MoodPriority.EVENT)


# ══════════════════════════════════════════
#  REPORT EVENTS (story chains)
# ══════════════════════════════════════════
func _fire_report(row: Dictionary) -> void:
	state["cultivation"] = max(0, state["cultivation"] + row["cultivation_gain"])
	state["spirit_stones"] = max(0, state["spirit_stones"] + row["stone_gain"])
	today_stats["qi_gain"] += max(0, row["cultivation_gain"])
	if achievement_manager != null and int(row["cultivation_gain"]) > 0:
		achievement_manager.record_qi_gain(int(row["cultivation_gain"]))
	if row["stone_gain"] > 0:
		today_stats["stone_gain"] += row["stone_gain"]
	if row["mood"] != "":
		request_mood(row["mood"], GameConfig.MoodPriority.EVENT)
	var lines := [{"zh": row["desc_zh"], "en": row["desc_en"]}]
	if row["cultivation_gain"] != 0:
		lines.append({"zh": "修为 %+d" % row["cultivation_gain"],
					  "en": "Cultivation %+d" % row["cultivation_gain"]})
	if row["stone_gain"] != 0:
		lines.append({"zh": "灵石 %+d" % row["stone_gain"],
					  "en": "Spirit Stones %+d" % row["stone_gain"]})
	var title_zh: String = row["title_zh"]
	var title_en: String = row["title_en"]
	if row["cultivation_gain"] != 0:
		title_zh += "  修为%+d" % row["cultivation_gain"]
		title_en += "  Qi %+d" % row["cultivation_gain"]
	if row["stone_gain"] != 0:
		title_zh += "  灵石%+d" % row["stone_gain"]
		title_en += "  Stones %+d" % row["stone_gain"]
	add_recent_event(title_zh, title_en, "special", row["desc_zh"], row["desc_en"])
	_show_toast(row["title_zh"], row["title_en"], lines)
	if String(row.get("set_flag", "")) != "":
		life_flags[String(row["set_flag"])] = true
	if String(row.get("force_achievement", "")) != "" and achievement_manager != null:
		achievement_manager.unlock_by_id(String(row["force_achievement"]))
	if String(row.get("personality_nudge", "")) != "":
		_nudge_personality(String(row["personality_nudge"]), 1.5)
	var event_tag: String = String(row.get("event_tag", ""))
	if event_tag != "":
		_today_event_tags[event_tag] = true
	if String(row.get("choice_prompt_zh", "")) != "":
		_offer_decision(row)
		refresh_ui()
		return
	var next_candidates := _resolve_chain_branches(row)
	var cooldown: int = int(row.get("cooldown_days", 0))
	for nid in next_candidates:
		if nid == "" or pending_chains.has(nid):
			continue
		if cooldown > 0:
			_scheduled_chain_unlocks.append({"id": nid, "unlock_day": _day_counter + cooldown})
		else:
			pending_chains.append(nid)
	var payoff_tag: String = String(row.get("foreshadow_payoff", ""))
	var payoff_hit := payoff_tag != "" and _foreshadow_active(payoff_tag)
	if payoff_tag != "":
		_foreshadow_flags.erase(payoff_tag)
	if payoff_hit:
		lines.append({"zh": "……果然没想错。", "en": "...just as feared."})
	var fs_tag: String = String(row.get("foreshadow_set", ""))
	if fs_tag != "":
		_set_foreshadow(fs_tag, int(row.get("foreshadow_expires_days", 3)))
	var is_terminal: bool = String(row.get("next_ids", "")) == "" and String(row.get("next_id", "")) == ""
	if is_terminal and String(row.get("memorable", "")) == "true":
		if achievement_manager != null:
			achievement_manager.record_chain_outcome(String(row.get("chain_id","")), String(row["id"]))
		var summary_zh: String = String(row.get("chain_summary_zh", row["desc_zh"]))
		var summary_en: String = String(row.get("chain_summary_en", row["desc_en"]))
		_record_memorable_event(String(row["id"]), row["title_zh"], row["title_en"], String(row.get("chain_id", "")))
		add_life_history("encounter", row["title_zh"], summary_zh, row["title_en"], summary_en)
	refresh_ui()

func trigger_report_event() -> void:
	if _is_intro_blocking():
		return
	var _tier := current_tier()

	for pid in pending_chains:
		var row = DataLoader.report_by_id.get(pid, null)
		if row != null and (String(row["realm"]) == "" or _tier_at_least(String(row["realm"]))):
			pending_chains.erase(pid)
			_fire_report(row)
			return

	var pool := []
	for row in DataLoader.report_defs:
		if row["realm"] != "" and not _tier_at_least(row["realm"]):
			continue
		var is_start: bool = (row["chain_id"] != "" and row["step"] == 1)
		var is_solo:  bool = (row["chain_id"] == "")
		if is_start or is_solo:
			pool.append(row)

	if pool.is_empty():
		return

	var total := 0
	for row in pool:
		var w: int = max(1, int(row["weight"]))
		var tag: String = String(row.get("personality_tag", ""))
		if tag != "":
			w = int(round(w * _personality_bias(tag + "_weight_mult")))
		total += max(1, w)
	var roll := randi() % total
	var acc := 0
	for row in pool:
		var w: int = max(1, int(row["weight"]))
		var tag: String = String(row.get("personality_tag", ""))
		if tag != "":
			w = int(round(w * _personality_bias(tag + "_weight_mult")))
		acc += max(1, w)
		if roll < acc:
			_fire_report(row)
			return


# ══════════════════════════════════════════
#  INPUT / TICK
# ══════════════════════════════════════════

func _input(event: InputEvent) -> void:
	# Right-click → context menu (runs before GUI)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# 不要自己算屏幕坐标。PopupMenu 是 Window，Godot 默认把子窗口嵌进主视口
		# (gui_embed_subwindows)，这时候 position 是视口坐标；再加一次
		# window_get_position() 就偏了，而且主窗口一改尺寸（事件弹窗会切 WIN_WIDE）
		# 视口变换跟着变，菜单就会跟着旁边的事件一起挪。
		# popup_on_parent 用父节点坐标系，嵌入/独立窗口两种情况都对。
		context_menu.reset_size()
		context_menu.popup_on_parent(Rect2i(Vector2i(event.position), Vector2i.ONE))
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _is_intro_blocking():
		return 
	# Left-click outside an open panel closes it
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if shop_panel != null and shop_panel.visible:
			var ls: Vector2 = shop_panel.get_global_transform().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, shop_panel.size).has_point(ls):
				shop_panel.visible = false
				return
		if report_panel != null and report_panel.visible:
			var lr: Vector2 = report_panel.get_global_transform().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, report_panel.size).has_point(lr):
				report_ui._close_report_panel()
				return
		if profile_panel != null and profile_panel.visible:
			var lp: Vector2 = profile_panel.get_global_transform().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, profile_panel.size).has_point(lp):
				profile_ui._close_profile_panel()
				return

	# Drag — and click-on-character = 督促
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mark_interaction()
			dragging = true
			drag_start_mouse  = DisplayServer.mouse_get_position()
			drag_start_window = DisplayServer.window_get_position()
			_drag_moved = false
			_press_pos = event.position 
		else:
			dragging = false
			if not _drag_moved and _is_on_character(_press_pos):
				_on_pet_clicked()
	if event is InputEventMouseMotion and dragging:
		var delta := DisplayServer.mouse_get_position() - drag_start_mouse
		if delta.length() > 4:
			_drag_moved = true
		DisplayServer.window_set_position(drag_start_window + delta)

func _is_on_character(pos: Vector2) -> bool:
	if cultivator_sprite == null or cultivator_sprite.sprite_frames == null:
		return false
	var center: Vector2 = pet_group.position + cultivator_sprite.position * pet_group.scale
	var frame: Texture2D = cultivator_sprite.sprite_frames.get_frame_texture(cultivator_sprite.animation, cultivator_sprite.frame)
	if frame == null:
		return false
	var half: Vector2 = Vector2(frame.get_width(), frame.get_height()) * 0.5 * cultivator_sprite.scale * pet_group.scale
	half *= 0.6
	var rect := Rect2(center - half, half * 2.0)
	return rect.has_point(pos)
	
func _on_tick() -> void:
	if _gameplay_blocked():
		return

	if GameConfig.DEMO_MODE:
		_demo_tick_clock(GameConfig.TICK_SECONDS)

	gain_cultivation(1.0)
	if achievement_manager != null:
		achievement_manager.record_meditation_seconds(1)
	_try_find_spirit_stone()
	_check_daily_report()
	save_mgr._autosave_if_due()

	if main_hall_panel != null and main_hall_panel.visible:
		_mh_session_seconds += 1
		_refresh_main_hall_live()

	if profile_panel != null and profile_panel.visible:
		profile_ui._update_profile_detail_live()


# ══════════════════════════════════════════
#  DEMO PACING CLOCK
#  20 分钟 / 4 世 / 3 次死亡。时间是权威，境界是尽力而为。
# ══════════════════════════════════════════

# 本世在节奏表里的下标（life_count 从 1 开始）
func _demo_life_index() -> int:
	return clampi(int(state.get("life_count", 1)) - 1, 0, GameConfig.DEMO_LIFE_SECONDS.size() - 1)


# 本世的目标时长；0 = 不强制死亡
func _demo_life_target_seconds() -> float:
	return float(GameConfig.DEMO_LIFE_SECONDS[_demo_life_index()])


func _demo_life_cult_mult() -> float:
	return float(GameConfig.DEMO_LIFE_CULT_MULT[_demo_life_index()])


# 玩家挂机时人生时钟慢下来 —— 死亡是全 demo 的高光，
# 绝对不能在玩家去泡咖啡的时候自己演完
func _demo_time_scale() -> float:
	var idle := (Time.get_ticks_msec() / 1000.0) - last_interaction_time
	return GameConfig.DEMO_IDLE_TIME_SCALE if idle >= GameConfig.DEMO_IDLE_AFTER else 1.0


func _demo_is_idle() -> bool:
	return (Time.get_ticks_msec() / 1000.0) - last_interaction_time >= GameConfig.DEMO_IDLE_AFTER


func _demo_tick_clock(delta: float) -> void:
	_demo_session_elapsed += delta
	_life_elapsed += delta * _demo_time_scale()

	# demo 内的「一天」按真实秒数推进，否则日报 / 伏笔 / 事件链
	# 在 20 分钟的试玩里一次都不会触发
	_demo_day_accum += delta * _demo_time_scale()
	while _demo_day_accum >= GameConfig.DEMO_DAY_SECONDS:
		_demo_day_accum -= GameConfig.DEMO_DAY_SECONDS
		_do_day_rollover(_get_today_string())

	# 30 分钟硬性保护：有人会一边工作一边挂着，至少让他看到结尾
	if _demo_session_elapsed >= GameConfig.DEMO_HARD_CAP_SECONDS and not demo_completed:
		_force_demo_ending_now()
		return

	if life_cycle != null:
		life_cycle.check_demo_life_clock()


# 时间到了，但玩家不在。等他回来再演，最多等 DEMO_DEATH_WAIT_MAX
# 返回 true = 现在可以死了
func demo_death_ready() -> bool:
	if not _demo_is_idle():
		_demo_death_waiting = -1.0
		return true
	if _demo_death_waiting < 0.0:
		_demo_death_waiting = 0.0
	_demo_death_waiting += GameConfig.TICK_SECONDS
	if _demo_death_waiting >= GameConfig.DEMO_DEATH_WAIT_MAX:
		_demo_death_waiting = -1.0
		return true
	return false


func _reset_demo_life_clock() -> void:
	_life_elapsed = 0.0
	_demo_death_waiting = -1.0


# 天数超时兜底：最后一世跑不到炼气也要给结局
func _force_demo_ending_now() -> void:
	if demo_completed:
		return
	var last := realms.size() - 1
	state["realm_index"] = last
	state["highest_realm_this_life"] = max(int(state.get("highest_realm_this_life", 0)), last)
	state["cultivation"] = 0.0
	refresh_ui()
	_check_demo_ending()


# ══════════════════════════════════════════
#  CULTIVATION / BREAKTHROUGH
# ══════════════════════════════════════════

func gain_cultivation(multiplier: float) -> void:
	if GameConfig.DEMO_MODE and demo_completed:
		return

	if int(state.get("realm_index", 0)) >= realms.size() - 1:
		return

	var realm: Dictionary = realms[state["realm_index"]]
	var gain := 2.0 * multiplier * cultivation_multiplier()
	state["cultivation"] += gain
	today_stats["qi_gain"] += int(gain)
	if achievement_manager != null:
		achievement_manager.record_qi_gain(int(round(gain)))
		achievement_manager.record_efficiency_bonus(int(round(maxf(0.0, cultivation_multiplier() - 1.0) * 100.0)))

	# 达到面板显示的需求就突破
	if state["cultivation"] >= float(realm["need"]):
		life_cycle.try_breakthrough()





# ══════════════════════════════════════════
#  LUCK SYSTEM
# ══════════════════════════════════════════

func roll_daily_luck() -> void:
	var today := _get_today_string()
	if state.get("luck_date", "") == today:
		return
	state["luck"] = randi_range(1, 100)
	state["luck_date"] = today
	if _is_intro_blocking():
		return
	if current_language == "zh":
		queue_message("今日气运：[color=%s]%s[/color]（%d）" % [luck_color(), luck_tier(), state["luck"]])
	else:
		queue_message("Today's luck: [color=%s]%s[/color] (%d)" % [luck_color(), luck_tier_en(), state["luck"]])
	
func luck_tier() -> String:
	var l: int = state["luck"]
	if l <= 10:  return "大凶"
	if l <= 30:  return "凶"
	if l <= 70:  return "平"
	if l <= 90:  return "吉"
	return "大吉"


func luck_tier_en() -> String:
	var l: int = state["luck"]
	if l <= 10:  return "Terrible"
	if l <= 30:  return "Bad"
	if l <= 70:  return "Normal"
	if l <= 90:  return "Good"
	return "Blessed"


func luck_color() -> String:
	var l: int = state["luck"]
	if l <= 10:  return "#8b3a3a"
	if l <= 30:  return "#c07878"
	if l <= 70:  return "#8eafc2"
	if l <= 90:  return "#d4af37"
	return "#ffd700"


func luck_modifier() -> float:
	return (state["luck"] - 50) / 500.0


# ══════════════════════════════════════════
#  BUTTONS / CHARACTER CLICK
# ══════════════════════════════════════════

func _on_feed() -> void:
	_mark_interaction()
	AudioManager.play_click()

	if int(state.get("realm_index", 0)) >= 5:
		shop_ui._open_shop()
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - last_feed_time < GameConfig.FEED_COOLDOWN_SECONDS:
		show_message_now("还没饿，等一下吧。" if current_language == "zh" else "Not hungry yet, give it a moment.")
		return
	last_feed_time = now

	today_stats["pill_eaten"] = int(today_stats.get("pill_eaten", 0)) + 1

	gain_cultivation(15.0)
	var eat_played := request_mood("eat", GameConfig.MoodPriority.EVENT)
	var tier := current_tier()
	var pool = DataLoader.feed_lines.filter(func(f): return f["tier"] == tier)
	if pool.is_empty():
		pool = DataLoader.feed_lines
	if pool.is_empty():
		show_message_now("吃饱了。" if current_language == "zh" else "All fed.")
	else:
		var line = pool.pick_random()
		show_message_now(line["zh"] if current_language == "zh" else line["en"])
	refresh_ui()
	if eat_played:
		var eat_anim := anim_ctl._resolve_mood_anim("eat")
		var dur := anim_ctl._death_anim_duration(eat_anim)   # 名字带"death"但其实就是纯算时长，通用
		await get_tree().create_timer(max(dur, 1.0) + 0.1).timeout
		request_mood("normal", GameConfig.MoodPriority.EVENT)
		clear_mood_priority()

func _feed_button_text() -> String:
	var eat_pill: bool = state["realm_index"] >= 5   # 先天初期 and above
	if current_language == "zh":
		return "吃丹" if eat_pill else "吃饭"
	else:
		return "Pill" if eat_pill else "Eat"

func _on_pet_clicked() -> void:
	_mark_interaction()
	state["click_count"] = int(state.get("click_count", 0)) + 1
	state["life_click_count"] = int(state.get("life_click_count", 0)) + 1
	today_stats["clicks_today"] = int(today_stats.get("clicks_today", 0)) + 1
	var c: int = state["click_count"]
	AudioManager.play_poke(-8.0, 0.12)
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_poke_time <= GameConfig.POKE_STREAK_RESET_SEC:
		poke_streak += 1
	else:
		poke_streak = 1
	last_poke_time = now

	var force_angry := poke_streak >= GameConfig.POKE_ANGRY_STREAK
	if force_angry:
		poke_streak = 0
		_nudge_personality("eccentric", 1.0)

	# Roll the random reaction (reward applies regardless of special dialogue)
	var roll := randf()
	var reward_zh := ""
	var reward_en := ""

	if force_angry:
		active_effects.append({
			"type": "slow_cultivation", "remaining": 10.0, "magnitude": 0.8,
			"label_zh": "别烦我！修炼变慢了。", "label_en": "Leave me alone! Cultivation slowed."
		})
		request_mood("angry", GameConfig.MoodPriority.EVENT)
		reward_zh = "你再戳，我真的要走火入魔了。"
		reward_en = "Poke me again and I may go qi-deviant."

	elif roll < 0.80:
		# 80% plain grumble, no reward — pick a filler line
		reward_zh = ""
		reward_en = ""
	elif roll < 0.95:
		# 15% happy, +5 cultivation
		state["cultivation"] = max(0, state["cultivation"] + 5)
		if achievement_manager != null:
			achievement_manager.record_qi_gain(5)
		request_mood("happy", GameConfig.MoodPriority.EVENT)
		reward_zh = "嘿嘿，修为 +5。"
		reward_en = "Hehe, cultivation +5."
	elif roll < 0.99:
		active_effects.append({
			"type": "slow_cultivation", "remaining": 10.0, "magnitude": 0.8,
			"label_zh": "别烦我！修炼变慢了。", "label_en": "Leave me alone! Cultivation slowed."
		})
		request_mood("angry", GameConfig.MoodPriority.EVENT)
		reward_zh = "别戳了，修炼都乱了。"
		reward_en = "Stop it, you're breaking my focus."
	else:
		# 1% epiphany, +50 cultivation
		state["cultivation"] = max(0, state["cultivation"] + 50)
		if achievement_manager != null:
			achievement_manager.record_qi_gain(50)
		request_mood("meditate", GameConfig.MoodPriority.EVENT)
		reward_zh = "顿悟！修为 +50！"
		reward_en = "Epiphany! Cultivation +50!"

	# Decide what to say: special line takes priority
	var say_zh := ""
	var say_en := ""
	if _click_special.has(c):
		say_zh = _click_special[c]["zh"]
		say_en = _click_special[c]["en"]
	elif reward_zh != "":
		say_zh = reward_zh
		say_en = reward_en
	else:
		# plain grumble filler
		var grumbles := [
			{"zh": "唔……", "en": "Hmph..."},
			{"zh": "你又来了。", "en": "You again."},
			{"zh": "戳够了没？", "en": "Done poking yet?"},
			{"zh": "我很忙的。", "en": "I'm busy, you know."}
		]
		var g = grumbles.pick_random()
		say_zh = g["zh"]
		say_en = g["en"]

	show_message_now(say_zh if current_language == "zh" else say_en)

	# Achievements (click milestones)
	if achievement_manager != null:
		achievement_manager.record_click(c)

	# Log only at special milestones (avoid spam)
	if c in [100, 500, 1000]:
		var note_zh := "小白被戳到怀疑人生（第%d次）" % c
		var note_en := "Poked into an existential crisis (%d times)" % c
		add_recent_event(note_zh, note_en, "special")
		

	refresh_ui()
	save_mgr.save_game()

# ══════════════════════════════════════════
#  EVENT REWARD HANDLER (for EventManager)
# ══════════════════════════════════════════

func _apply_event_reward(type: String, value: int) -> void:
	match type:
		"qi":
			state["cultivation"] = max(0, state["cultivation"] + value)
			if achievement_manager != null and value > 0:
				achievement_manager.record_qi_gain(value)
		"stone":
			state["spirit_stones"] = max(0, state["spirit_stones"] + value)
			if value > 0: today_stats["stone_gain"] += value
		"lifespan":
			state["lifespan"] += value
		"luck":
			state["luck"] = clampi(int(state.get("luck", 50)) + value, 1, 100)
		"insight":
			state["breakthrough_insight"] = clampi(int(state.get("breakthrough_insight", 0)) + value, 0, GameConfig.BREAKTHROUGH_INSIGHT_CAP)
		"breakthrough_bonus":
			next_breakthrough_bonus += value / 100.0
		"death_risk":
			var adjusted_value := float(value) * _personality_bias("death_risk_mult")
			if randf() < adjusted_value / 100.0:
				state["lifespan"] = 0
				if await life_cycle.check_lifespan():
					return
		"pill":
			pass
	refresh_ui()
	save_mgr.save_game()


# ══════════════════════════════════════════
#  OFFLINE REWARDS
# ══════════════════════════════════════════

func grant_offline_rewards() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var last := int(state.get("last_saved_unix", now))
	if last <= 0:
		last = now
	var offline_seconds: int = clampi(now - last, 0, GameConfig.OFFLINE_CAP_SECONDS)
	if offline_seconds > 60:
		var cultivation_gain := int(floor(offline_seconds / 10.0))
		var stones_gain      := int(floor(offline_seconds / 600.0))
		state["cultivation"]   += cultivation_gain
		state["spirit_stones"] += stones_gain
		var hours := offline_seconds / 3600.0
		var hours_str := "%.1f" % hours
		_mh_offline_seconds = offline_seconds
		add_recent_event(
			"离线修炼 %s小时" % hours_str,
			"Offline cultivation %sh" % hours_str,
			"cultivate",
			"修为 +%d  灵石 +%d" % [cultivation_gain, stones_gain],
			"Cultivation +%d  Stones +%d" % [cultivation_gain, stones_gain]
		)
		# No realm-up loop — offline never triggers breakthroughs, stories, encounters, or achievements.


# ══════════════════════════════════════════
#  UI REFRESH
# ══════════════════════════════════════════

func refresh_ui() -> void:
	var realm: Dictionary = realms[state["realm_index"]]
	if realm_strip_label != null:
		feed_button.text = _feed_button_text()
		var rname: String = realm["name"] if current_language == "zh" else realm_names_en[state["realm_index"]]
		realm_strip_label.text = rname
		realm_strip.size = Vector2.ZERO
		call_deferred("_recenter_realm_strip")


func _recenter_realm_strip() -> void:
	if realm_strip != null:
		realm_strip.position.x = -realm_strip.size.x / 2


# ══════════════════════════════════════════
#  DAILY ROLLOVER SUMMARY
# ══════════════════════════════════════════

func _get_today_string() -> String:
	var date = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [date.year, date.month, date.day]


func _check_daily_report() -> void:
	var today := _get_today_string()
	if today_stats["date"] == "":
		today_stats["date"] = today
		return
	# DEMO 下由 _demo_tick_clock 按秒推进，这里不再依赖真实日期变化
	if GameConfig.DEMO_MODE:
		return
	if today_stats["date"] != today:
		_do_day_rollover(today)


func _do_day_rollover(today: String) -> void:
	_push_daily_summary()
	_yesterday_event_tags = _today_event_tags.duplicate()
	_today_event_tags.clear()
	_reset_today_stats(today)
	_day_counter += 1
	_drain_scheduled_chain_unlocks()
	_clear_expired_foreshadows()
	_auto_resolve_stale_decision()
	save_mgr.save_game()

func _drain_scheduled_chain_unlocks() -> void:
	var remaining: Array = []

	for entry in _scheduled_chain_unlocks:
		var unlock_day := int(entry.get("unlock_day", 0))
		var id := String(entry.get("id", ""))

		if unlock_day > _day_counter:
			remaining.append(entry)
			continue

		if id != "" and not pending_chains.has(id):
			pending_chains.append(id)

	_scheduled_chain_unlocks = remaining

func _reset_today_stats(today: String) -> void:
	today_stats = {
		"date": today, "qi_gain": 0, "stone_gain": 0, "pill_eaten": 0,
		"sleep_count": 0, "fall_count": 0,
		"breakthrough_attempt": 0, "breakthrough_success": 0,
		"clicks_today": 0
	}

func _push_daily_summary() -> void:
	var gazette := _build_daily_gazette()

	var detail_zh := "【%s】\n%s\n\n气运：%s\n传闻：%s\n明日：%s\n成就：%s\n邻里：%s\n\n修为+%d 灵石+%d 突破%d/%d" % [
		gazette["headline_zh"], gazette["highlight_zh"],
		gazette["fortune_zh"], gazette["rumour_zh"], gazette["hint_zh"],
		gazette["achievement_zh"], gazette["neighbour_zh"],
		int(today_stats.get("qi_gain",0)), int(today_stats.get("stone_gain",0)),
		int(today_stats.get("breakthrough_success",0)), int(today_stats.get("breakthrough_attempt",0))
	]
	var detail_en := "[%s]\n%s\n\nFortune: %s\nRumour: %s\nTomorrow: %s\nAchievement: %s\nWord around: %s\n\nQi+%d Stones+%d Breakthroughs %d/%d" % [
		gazette["headline_en"], gazette["highlight_en"],
		gazette["fortune_en"], gazette["rumour_en"], gazette["hint_en"],
		gazette["achievement_en"], gazette["neighbour_en"],
		int(today_stats.get("qi_gain",0)), int(today_stats.get("stone_gain",0)),
		int(today_stats.get("breakthrough_success",0)), int(today_stats.get("breakthrough_attempt",0))
	]

	add_recent_event("今日修炼小结", "Daily Recap", "cultivate", detail_zh, detail_en)
	_achievement_unlocked_today.clear()   # reset for tomorrow

	if report_panel != null and report_panel.visible:
		report_ui._refresh_reports()
		return
	# DEMO 下一天只有 22 秒，日报每天都弹会变成刷屏 —— 隔几天出一期
	if GameConfig.DEMO_MODE and (_day_counter % GameConfig.DEMO_GAZETTE_EVERY_DAYS) != 0:
		return
	_show_toast("📰 桌面修仙报", "📰 The Tiny Cultivator Gazette", [{"zh": detail_zh, "en": detail_en}])

# ══════════════════════════════════════════
#  SPEECH BUBBLE + MESSAGE QUEUE
# ══════════════════════════════════════════

func queue_message(text: String) -> void:
	message_queue.append(text)
	if not is_showing_message:
		_show_next_message()


func _show_next_message() -> void:
	if message_queue.is_empty():
		is_showing_message = false
		_hide_bubble()
		return
	is_showing_message = true
	_msg_token += 1
	var my_token := _msg_token
	_show_bubble(message_queue.pop_front())
	await get_tree().create_timer(3.0).timeout
	if my_token != _msg_token:
		return
	_show_next_message()


func _show_bubble(text: String) -> void:
	# 主面板开着时不显示对话气泡（会压到名字牌）
	if main_hall_panel != null and main_hall_panel.visible:
		return
	if bubble_panel == null:
		return
	bubble_label.text     = text
	bubble_panel.visible  = true
	bubble_tail.visible   = true
	bubble_panel.modulate = Color(1, 1, 1, 0)
	bubble_tail.modulate  = Color(1, 1, 1, 0)
	await get_tree().process_frame
	# 二道守卫：await 期间面板可能刚被打开（竞态）
	if main_hall_panel != null and main_hall_panel.visible:
		bubble_panel.visible = false
		bubble_tail.visible = false
		return
	var target_y := GameConfig.BUBBLE_ANCHOR_Y - bubble_panel.size.y - GameConfig.BUBBLE_GAP
	var top_edge := pet_group.position.y + target_y * pet_group.scale.y
	if top_edge < 4.0:
		target_y += (4.0 - top_edge) / pet_group.scale.y
	var target := Vector2(-bubble_panel.size.x / 2.0, target_y)
	bubble_panel.position = target
	bubble_tail.position = Vector2(0, target_y + bubble_panel.size.y)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(bubble_panel, "modulate", Color(1, 1, 1, 1), 0.2)
	tween.tween_property(bubble_tail,  "modulate", Color(1, 1, 1, 1), 0.2)
	tween.tween_property(bubble_panel, "position", target, 0.15)\
		.from(target + Vector2(0, 12))


func _hide_bubble() -> void:
	if bubble_panel == null:
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(bubble_panel, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.tween_property(bubble_tail,  "modulate", Color(1, 1, 1, 0), 0.2)
	await tween.finished
	bubble_panel.visible = false
	bubble_tail.visible  = false


func log_event(text: String) -> void:
	queue_message(text)


# ══════════════════════════════════════════
#  SAVE / LOAD
# ══════════════════════════════════════════

	




# ══════════════════════════════════════════
#  CSV LOADERS
# ══════════════════════════════════════════

func _check_branch_condition(cond: String) -> bool:
	if cond == "":
		return true
	if cond.begins_with("luck<"):
		return int(state.get("luck", 50)) < int(cond.substr(5))
	if cond.begins_with("luck>="):
		return int(state.get("luck", 50)) >= int(cond.substr(6))
	if cond.begins_with("realm>="):
		return int(state.get("realm_index", 0)) >= int(cond.substr(7))
	if cond.begins_with("job:"):
		return String(state.get("mortal_job", "")) == cond.substr(4)
	if cond.begins_with("flag:"):
		return life_flags.has(cond.substr(5))
	if cond.begins_with("stone>="):
		return int(state.get("spirit_stones", 0)) >= int(cond.substr(7))
	return true   # 未知条件字符串 -> 放行，绝不让链卡死


func _resolve_chain_branches(row: Dictionary) -> Array:
	var raw_ids: String = String(row.get("next_ids", ""))
	if raw_ids == "":
		var single: String = String(row.get("next_id", ""))
		return [single] if single != "" else []

	var ids := raw_ids.split("|")
	var raw_weights: String = String(row.get("branch_weights", ""))
	var weights: Array = Array(raw_weights.split("|")) if raw_weights != "" else []

	var eligible: Array = []
	var eligible_weights: Array = []
	for i in ids.size():
		var candidate_id: String = ids[i].strip_edges()
		var candidate_row = DataLoader.report_by_id.get(candidate_id, null)
		if candidate_row == null:
			continue
		if not _check_branch_condition(String(candidate_row.get("branch_condition", ""))):
			continue
		eligible.append(candidate_id)
		eligible_weights.append(int(weights[i]) if i < weights.size() else 1)

	if eligible.is_empty():
		return []

	var total := 0
	for w in eligible_weights:
		total += max(1, w)
	var roll := randi() % total
	var acc := 0
	for i in eligible.size():
		acc += max(1, eligible_weights[i])
		if roll < acc:
			return [eligible[i]]
	return [eligible.back()]





func _default_color_for_mood(m: String) -> String:
	match m:
		"normal":   return "8eafc2"
		"sleepy":   return "a99abf"
		"meditate": return "5db5a0"
		"alchemy":  return "c8943a"
		"happy":    return "d4af37"
		"confused": return "c07878"
		"angry":    return "d85c4a"
		_:          return "8eafc2"


# ══════════════════════════════════════════
#  SHOP
# ══════════════════════════════════════════










# ══════════════════════════════════════════
#  REPORT PANEL  (事件)
# ══════════════════════════════════════════







var report_expanded := false



# ══════════════════════════════════════════
#  PROFILE PANEL  (履历)
# ══════════════════════════════════════════




# Tab 1：现在的人生

# Tab 2：人生履历

# Tab 3：成就 & 图鉴


# Tab 4：历史记录

var qi_progress_bar: ProgressBar
var qi_numbers_label: Label
var qi_percent_label: Label















# ══════════════════════════════════════════
#  TOAST
# ══════════════════════════════════════════

func _show_toast(title_zh: String, title_en: String, lines: Array) -> void:
	toast_queue.append({"title_zh": title_zh, "title_en": title_en, "lines": lines})
	if not toast_showing:
		_next_toast()


func _next_toast() -> void:
	if toast_queue.is_empty():
		toast_showing = false
		return
	toast_showing = true
	var t = toast_queue.pop_front()
	var title: String = t["title_zh"] if current_language == "zh" else t["title_en"]
	var body := "📜 [b]%s[/b]\n" % title
	for line in t["lines"]:
		body += (line["zh"] if current_language == "zh" else line["en"]) + "\n"
	toast_label.text = body.strip_edges()

	toast_panel.visible = true
	toast_panel.modulate = Color(1, 1, 1, 0)
	await get_tree().process_frame

	var win := get_viewport_rect().size
	var ts := toast_panel.size
	var is_daily_report := title.contains("每日修仙日报") or title.contains("Daily Cultivation Report")

	# 所有事件/日报/突破 toast 都改成右侧滑入
	if not _has_open_wide_panel():
		get_window().size = GameConfig.WIN_WIDE
		await get_tree().process_frame
		update_layout()
	win = get_viewport_rect().size

	var target_y := pet_group.position.y - 70.0

	# 每日修仙日报可以稍微高一点，普通事件放中间一点
	if is_daily_report:
		target_y = pet_group.position.y - 75.0
	else:
		target_y = pet_group.position.y - 55.0

	target_y = clamp(target_y, 60.0, win.y - ts.y - 30.0)

	var end_pos := Vector2(win.x - ts.x - GameConfig.REPORT_MARGIN, target_y)

	# 从窗口右侧外面滑进来，不再从上方下来
	var start_pos := Vector2(win.x + 16.0, target_y)

	toast_panel.position = start_pos

	var tw := create_tween().set_parallel(true)
	tw.tween_property(toast_panel, "position", end_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(toast_panel, "modulate", Color(1,1,1,1), 0.25)
	await tw.finished

	await get_tree().create_timer(GameConfig.TOAST_SECS).timeout

	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(toast_panel, "position", start_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.tween_property(toast_panel, "modulate", Color(1,1,1,0), 0.3)
	await tw2.finished
	toast_panel.visible = false

	# 只有没有任何大面板打开时，toast 结束才缩回普通窗口
	if not _has_open_wide_panel():
		get_window().size = GameConfig.WIN_NORMAL

	_next_toast()

func _has_open_wide_panel() -> bool:
	if report_panel != null and report_panel.visible:
		return true
	if profile_panel != null and profile_panel.visible:
		return true
	if shop_panel != null and shop_panel.visible:
		return true
	if name_dialog != null and name_dialog.visible:
		return true
	if intro_panel != null and intro_panel.visible:
		return true
	if certificate_panel != null and certificate_panel.visible:
		return true
	# 成就面板漏在名单外，是「成就页面会变大变小」的原因：
	# toast 开始时把窗口撑成 WIN_WIDE、结束时缩回 WIN_NORMAL，
	# 每次尺寸变化都会触发 _on_window_resized() 重算 achievement_ui.root.scale。
	if achievement_ui != null and achievement_ui.panel != null and achievement_ui.panel.visible:
		return true
	# 主殿是 WIN_MAIN，更不能被 toast 缩回 WIN_NORMAL
	if main_hall_panel != null and main_hall_panel.visible:
		return true
	if cave_ui != null and cave_ui.panel != null and cave_ui.panel.visible:
		return true
	return false
	
# ══════════════════════════════════════════
#  DEMO ENDING
# ══════════════════════════════════════════

func _check_demo_ending() -> void:
	if demo_completed:
		return

	if current_tier() != "炼气":
		return

	demo_completed = true

	add_life_record(
		"踏入炼气，demo 告一段落",
		"Reached Qi Refining — demo complete",
		"special"
	)

	add_recent_event(
		"Demo 结束",
		"Demo Complete",
		"special",
		"恭喜踏入炼气境！当前试玩版到这里结束。正式版会开放更多境界、死法、奇遇和宗门社区。",
		"You reached Qi Refining! This is the end of the demo. The full version will include more realms, deaths, encounters, and sect life."
	)

	save_mgr.save_game()
	# Demo 结束：禁用主要交互按钮
	if feed_button != null:
		feed_button.disabled = true


	_show_toast(
		"演示结束",
		"Demo Complete",
		[
			{
				"zh": "恭喜踏入炼气境！",
				"en": "You reached Qi Refining!"
			},
			{
				"zh": "当前试玩版到这里结束。",
				"en": "This is the end of the demo."
			},
			{
				"zh": "正式版会开放：更多境界、更多死法、更多奇遇、宗门社区。",
				"en": "Full version: more realms, more deaths, more encounters, and sect life."
			},
			{
				"zh": "感谢照顾这位小修士。",
				"en": "Thanks for raising this tiny cultivator."
			}
		]
	)

# ══════════════════════════════════════════
#  LANGUAGE TOGGLE
# ══════════════════════════════════════════
func _refresh_quick_bar_labels() -> void:
	if quick_bar == null:
		return
	for item in quick_bar.get_children():
		for c in item.get_children():
			if c is Label:
				c.text = String(c.get_meta("zh")) if current_language == "zh" else String(c.get_meta("en"))

func _set_language(lang: String) -> void:
	
	if lang != "zh" and lang != "en":
		return

	current_language = lang

	feed_button.text = _feed_button_text()
	meditate_button.text = "人生" if current_language == "zh" else "Profile"
	info_button.text = "事件" if current_language == "zh" else "Events"

	_refresh_name_dialog_text()
	_refresh_quick_bar_labels()

	if shop_panel != null and shop_panel.visible:
		shop_ui._refresh_shop()
	if report_panel != null and report_panel.visible:
		report_ui._refresh_reports()
	if profile_panel != null and profile_panel.visible:
		profile_ui._refresh_profile()
	state["language"] = current_language
	save_mgr.save_game()
	_rebuild_context_menu()
	update_status()
	refresh_ui()

func _roll_random_name() -> void:
	if name_edit == null:
		return

	if current_language == "zh":
		name_edit.text = random_names_zh.pick_random()
	else:
		name_edit.text = random_names_en.pick_random()

func _refresh_name_dialog_text() -> void:
	if name_title_label != null:
		name_title_label.text = "给小修士起名" if current_language == "zh" else "Name Your Cultivator"

	if name_subtitle_label != null:
		name_subtitle_label.text = "第一世，即将开始。" if current_language == "zh" else "Life one begins."

	if name_confirm_button != null:
		name_confirm_button.text = "开始修仙" if current_language == "zh" else "Begin"

	if name_random_button != null:
		name_random_button.text = "随机" if current_language == "zh" else "Random"

	if name_edit != null:
		name_edit.placeholder_text = "小白" if current_language == "zh" else "Xiao Bai"

	if name_lang_zh_button != null:
		name_lang_zh_button.disabled = current_language == "zh"

	if name_lang_en_button != null:
		name_lang_en_button.disabled = current_language == "en"


func show_message_now(text: String) -> void:
	message_queue.clear()
	is_showing_message = true
	_msg_token += 1
	var my_token := _msg_token
	_show_bubble(text)
	await get_tree().create_timer(3.0).timeout
	# Only the most recent call proceeds; older ones bail out
	if my_token != _msg_token:
		return
	_show_next_message()

func _on_encounter(ev: Dictionary) -> void:
	var rarity: String = ev.get("rarity", "rare")
	var eid: String = ev["event_id"]
	_today_event_tags["legendary_encounter" if rarity == "legendary" else "rare_encounter"] = true
 
	# Track discovery + counts
	var is_new_encounter := not discovered_encounters.has(eid)
	discovered_encounters[eid] = true

	# 奇遇只在「首次发现」时写入人生履历，重复触发不再刷屏（图鉴/事件栏仍照常）
	if is_new_encounter:
		var encounter_title_zh := "传说奇遇" if rarity == "legendary" else "获得奇遇"
		var encounter_title_en := "Legendary Encounter" if rarity == "legendary" else "Encounter Gained"
		var encounter_desc_zh := String(ev.get("text_zh", ""))
		var encounter_desc_en := String(ev.get("text_en", ""))
		add_life_history("encounter", encounter_title_zh, encounter_desc_zh, encounter_title_en, encounter_desc_en)
	
	if rarity == "rare":
		rare_encounter_count += 1
		state["life_rare_count"] = int(state.get("life_rare_count", 0)) + 1
	elif rarity == "legendary":
		legendary_encounter_count += 1
		state["life_legendary_count"] = int(state.get("life_legendary_count", 0)) + 1

	# 稀有/传说 → 卷轴弹窗（取代原 toast）
	if rarity == "legendary":
		AudioManager.play_legendary()
		_record_memorable_event(eid, ev["text_zh"], ev["text_en"], "")
	var _rw: Array = []
	var _rt := String(ev.get("reward_type", "none"))
	var _rv := int(ev.get("reward_value", 0))
	if _rt != "none" and _rv != 0:
		var _lab: Array = {"qi": ["修为","Qi"], "stone": ["灵石","Stones"], "lifespan": ["寿元","Lifespan"]}.get(_rt, ["奖励","Reward"])
		_rw = [{"label_zh": _lab[0], "label_en": _lab[1], "value": _rv}]
	event_popup.show_popup(
		{"zh": "传说奇遇" if rarity == "legendary" else "稀有奇遇",
		 "en": "Legendary!" if rarity == "legendary" else "Rare Encounter"},
		{"zh": ev["text_zh"], "en": ev["text_en"]},
		String(ev.get("event_type", "cultivate")), _rw)
	if rarity == "legendary":
		add_life_record(ev["text_zh"], ev["text_en"], "legendary")
		add_recent_event(ev["text_zh"], ev["text_en"], "legendary")
		_age_up(randi_range(1, 5))
	else:
		add_recent_event(ev["text_zh"], ev["text_en"], "fortune")
		_age_up(randi_range(0, 2))
# Achievements
	if achievement_manager != null:
		var total_encounters := rare_encounter_count + legendary_encounter_count
		achievement_manager.record_encounter_count(total_encounters)
		achievement_manager.record_encounter_variety(discovered_encounters.size())
		if rarity == "legendary":
			achievement_manager.record_encounter_legendary(legendary_encounter_count)
			var distinct_leg := 0
			for lid in event_manager.legendary_ids:
				if discovered_encounters.has(lid):
					distinct_leg += 1
			if distinct_leg >= event_manager.total_legendary():
				achievement_manager.record_encounter_legendary_all(distinct_leg)

	refresh_ui()
	save_mgr.save_game()
func _current_age() -> int:
	return int(state.get("cultivation_age", 16))


func _age_up(years: int) -> void:
	state["cultivation_age"] = _current_age() + max(0, years)
	if achievement_manager != null:
		achievement_manager.record_age_low_realm(state["cultivation_age"], state["realm_index"])

func add_life_record(zh: String, en: String, type: String) -> void:
	life_records.append({"age": _current_age(), "zh": zh, "en": en, "type": type})
	if life_records.size() > 100:
		life_records.pop_front()

	# 同步旧履历到新的分类人生履历。
	# 突破/死亡已有专门 add_life_history()；legendary 奇遇由 _on_encounter() 统一记录，避免重复。
	var synced_to_life_history := false
	var category := _life_category_from_type(type, zh)
	var should_sync := (
		type != "breakthrough"
		and type != "death"
		and type != "legendary"
		and category != "breakthrough"
		and category != "death"
		and not zh.contains("转世")
	)

	if should_sync:
		add_life_history(category, zh, "", en, "")
		synced_to_life_history = true

	# milestone achievements now fire from here (add_report retired)
	if achievement_manager != null:
		achievement_manager.record_milestone(zh)

	if not synced_to_life_history and profile_panel != null and profile_panel.visible:
		profile_ui._refresh_profile()

	save_mgr.save_game()

func add_recent_event(zh: String, en: String, type: String, desc_zh: String = "", desc_en: String = "", rewards: Array = []) -> void:
	recent_events.append({
		"time": Time.get_time_string_from_system().substr(0, 5),
		"date": Time.get_date_string_from_system(),          # "2026-07-19"
		"ts": int(Time.get_unix_time_from_system()),          # 排序用
		"zh": zh, "en": en, "type": type,
		"desc_zh": desc_zh, "desc_en": desc_en,
		"rewards": rewards,                                    # [{label_zh,label_en,value}, ...]
	})
	if recent_events.size() > 200:
		recent_events.pop_front()
	if report_panel != null and report_panel.visible:
		report_ui._refresh_reports()
	if main_hall_panel != null and main_hall_panel.visible:
		_refresh_main_hall()

func _event_icon(type: String) -> String:
	match type:
		"breakthrough": return "🟢"
		"stone":     return "💰"
		"item","alchemy": return "💊"
		"cultivate": return "🧘"
		"beast":     return "🐾"
		"fortune":   return "🟡"
		"legendary": return "🌟"
		"death":     return "🔴"
		"special":   return "⭐"
		_:           return "•"

func spiritual_root_multiplier() -> float:
	var tier: String = state.get("spiritual_root_tier", "")
	if tier == "":
		return 1.0
	return GameConfig.ROOT_MULTIPLIERS.get(tier, 1.0)
	
func _job_flavor_pool(source: Dictionary, fallback_pool: Array) -> Array:
	var job := String(state.get("mortal_job", ""))
	if job == "" or not source.has(job):
		return fallback_pool

	var tier := current_tier()
	var job_pool: Array = source[job].filter(func(row):
		var r := String(row.get("realm", ""))
		return r == "" or r == tier
	)

	return fallback_pool + job_pool
	
func _check_spiritual_root_awakening() -> void:
	if state["realm_index"] != 5:
		return
	if String(state.get("spiritual_root", "")) != "":
		return
	var tier := _roll_root_tier()
	var pool: Array = GameConfig.SPIRITUAL_ROOTS[tier]
	var root = pool.pick_random()
	state["spiritual_root"] = root["zh"]
	state["spiritual_root_en"] = root["en"]
	state["spiritual_root_tier"] = tier

	var reveal_zh := ""
	var reveal_en := ""
	var reveal_pool = DataLoader.spiritual_root_awakening_lines.filter(func(r): return r["tier"] == tier)
	if not reveal_pool.is_empty():
		var picked = reveal_pool.pick_random()
		reveal_zh = picked["zh"]
		reveal_en = picked["en"]

	add_life_record(
		"觉醒%s" % root["zh"] if reveal_zh == "" else "觉醒%s — %s" % [root["zh"], reveal_zh],
		"Awakened: %s" % root["en"] if reveal_en == "" else "Awakened: %s — %s" % [root["en"], reveal_en],
		"special"
	)

	var toast_lines := [
		{"zh": "你感受到天地灵气。开始测定灵根……", "en": "You sense the qi of heaven and earth. Testing your root..."},
		{"zh": "灵根：%s" % root["zh"], "en": "Root: %s" % root["en"]}
	]
	if reveal_zh != "":
		toast_lines.append({"zh": reveal_zh, "en": reveal_en})

	_show_toast("【灵根觉醒】", "【Spiritual Root Awakening】", toast_lines)

# ══════════════════════════════════════════
#  REINCARNATION CERTIFICATE
# ══════════════════════════════════════════

	

# ═══════════════════════════════════════════════════════════════
#  轮回证书 · 新版（底图  .png，1024×768）

#
#  底图放在: res://assets/ui/death_certificate_panel.png
#  导入设置: 贴图过滤 Linear（默认即可，别设 Nearest）
# ═══════════════════════════════════════════════════════════════

var certificate_panel: Control
var cert_share_button: Button
var cert_bg: TextureRect
var cert_title_label: Label
var cert_left_vbox: VBoxContainer
var cert_witness_vbox: VBoxContainer
var cert_issue_vbox: VBoxContainer
var cert_hint_label: Label

# 底图各留白框换算到 560×420 后的区域（原图坐标 × 560/1024）



# ── 小工具 ──





func _get_safe_window_position(new_size: Vector2i) -> Vector2i:
	var screen_size := DisplayServer.screen_get_size()
	var current_pos := DisplayServer.window_get_position()

	# Default: keep top-left anchored (expand rightward, current behavior)
	var new_pos := current_pos

	# If expanding rightward would push off the right edge, anchor from the right instead
	if current_pos.x + new_size.x > screen_size.x:
		new_pos.x = max(0, screen_size.x - new_size.x)

	# Clamp vertically too, in case the window is near the bottom
	if current_pos.y + new_size.y > screen_size.y:
		new_pos.y = max(0, screen_size.y - new_size.y)

	return new_pos

var _afk_skip_next_report := false

func _on_report_event_timeout() -> void:
	if is_afk:
		if _afk_skip_next_report:
			_afk_skip_next_report = false
			return
		_afk_skip_next_report = true
	trigger_report_event()

func _report_event_interval() -> float:
	# 新一世的"童年期"（虚岁≤30）事件更密：第一印象期不冷场
	if _current_age() <= 30:
		return randf_range(18.0, 26.0)
	# 第一世全程也稍密一点（demo 玩家大多停在第一二世）
	if int(state.get("life_count", 1)) == 1:
		return randf_range(30.0, 40.0)
	return randf_range(40.0, 50.0)

func _schedule_next_report_event() -> void:
	var t := get_tree().create_timer(_report_event_interval())
	t.timeout.connect(func():
		_on_report_event_timeout()
		_schedule_next_report_event()
	)

# ══════════════════════════════════════════
#  MOOD PRIORITY SYSTEM
# ══════════════════════════════════════════


var _current_mood_priority: int = GameConfig.MoodPriority.AMBIENT

func request_mood(new_mood: String, priority: int) -> bool:
	if priority < _current_mood_priority:
		return false   # a higher-priority mood is already active; ignore this request
	_current_mood_priority = priority
	set_mood(new_mood)
	return true

func clear_mood_priority() -> void:
	_current_mood_priority = GameConfig.MoodPriority.AMBIENT

func _lifespan_bonus_for_realm(realm_index: int) -> int:
	if realm_index <= 0:
		return 0
	elif realm_index == 1:
		return randi_range(5, 15)      # 引气二层
	elif realm_index == 2:
		return randi_range(10, 20)     # 引气三层
	elif realm_index == 3:
		return randi_range(40, 80)     # 武者初期
	elif realm_index == 4:
		return randi_range(60, 100)    # 武者中期
	elif realm_index == 5:
		return randi_range(180, 320)   # 先天初期
	elif realm_index == 6:
		return randi_range(280, 420)   # 先天大成
	else:
		return randi_range(600, 1000)  # 炼气一层

func _pick_daily_comment(stats: Dictionary, clicks_today: int) -> Dictionary:
	var category := "default"
	var lazy_threshold := 30.0 * _personality_bias("daily_qi_mult")
	if clicks_today >= 30:
		category = "high_click"
	elif stats["breakthrough_attempt"] > 0 and stats["breakthrough_success"] == 0:
		category = "all_fail"
	elif stats["breakthrough_attempt"] > 0 and stats["breakthrough_success"] == stats["breakthrough_attempt"]:
		category = "all_success"
	elif stats["sleep_count"] >= 3:
		category = "sleepy_day"
	elif stats["qi_gain"] >= 200:
		category = "productive"
	elif stats["qi_gain"] < lazy_threshold and stats["breakthrough_attempt"] == 0:
		category = "lazy_day"
	var pool = DataLoader.daily_comments.filter(func(c): return c["category"] == category)
	if pool.is_empty():
		pool = DataLoader.daily_comments
	if pool.is_empty():
		return {"zh": "今天没什么特别的。", "en": "Nothing much today."}
	return pool.pick_random()   # ← 这行要加

var intro_panel: PanelContainer




func _build_intro_panel() -> void:
	intro_panel = PanelContainer.new()
	intro_panel.name = "IntroPanel"
	intro_panel.add_theme_stylebox_override(
		"panel", make_panel_stylebox(Color(0.96, 0.94, 0.90, 0.98), 14))
	intro_panel.custom_minimum_size = Vector2(280, 0)
	intro_panel.visible = false
	intro_panel.z_index = 100
	add_child(intro_panel)

	intro_panel.gui_input.connect(func (e):
		if e is InputEventMouseButton and e.pressed:
			intro_panel.visible = false
			_set_main_ui_visible(true)
			clear_mood_priority()

			if event_manager != null:
				event_manager.set_paused(false)

			get_window().size = GameConfig.WIN_NORMAL
			await get_tree().process_frame
			update_layout()
			_reposition_overlay_panels()
	)

func _show_intro_sequence(cultivator_name: String, reincarnated: bool = false) -> void:
	for child in intro_panel.get_children():
		child.queue_free()
	var safe_pos := _get_safe_window_position(GameConfig.WIN_WIDE)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = GameConfig.WIN_WIDE
	await get_tree().process_frame
	update_layout()
	_reposition_overlay_panels()

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	intro_panel.add_child(vb)

	var life_num: int = int(state.get("life_count", 1))
	var named_line := Label.new()
	if reincarnated and not _last_death_punchline.get("zh","").is_empty():
		var callback := Label.new()
		callback.text = ("上一世的结局是：%s" % _last_death_punchline.get("zh","")) if current_language == "zh" \
			else ("Last life ended with: %s" % _last_death_punchline.get("en",""))
		callback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		callback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		callback.custom_minimum_size = Vector2(240, 0)
		callback.add_theme_font_size_override("font_size", 12)
		callback.add_theme_color_override("font_color", Color(0.55, 0.45, 0.35))
		vb.add_child(callback)
		vb.add_child(HSeparator.new())

	var pool: Array = DataLoader.intro_lines_reincarnated if reincarnated else DataLoader.intro_lines_first
	if pool.is_empty():
		pool = DataLoader.intro_lines_first if not DataLoader.intro_lines_first.is_empty() else DataLoader.intro_lines_reincarnated
	if not pool.is_empty():
		var picked = pool.pick_random()
		var body := Label.new()
		var raw: String = picked["zh"] if current_language == "zh" else picked["en"]
		body.text = raw.replace("{name}", cultivator_name).replace("{life}", str(life_num))
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(240, 0)
		body.add_theme_font_size_override("font_size", 15)
		body.add_theme_color_override("font_color", Color(0.25, 0.2, 0.18))
		vb.add_child(body)
		vb.add_child(HSeparator.new())

	var start_line := Label.new()
	start_line.text = ("【重新修仙】" if reincarnated else "【开始修仙】") if current_language == "zh" else ("[Begin Again]" if reincarnated else "[Begin Cultivation]")
	start_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_line.add_theme_font_size_override("font_size", 16)
	start_line.add_theme_color_override("font_color", Color(0.5, 0.3, 0.15))
	vb.add_child(start_line)

	var hint := Label.new()
	hint.text = "（点击关闭）" if current_language == "zh" else "(tap to close)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35))
	vb.add_child(hint)

	intro_panel.visible = true
	request_mood("normal", GameConfig.MoodPriority.SYSTEM)
	if event_manager != null:
		event_manager.set_paused(true)
	intro_panel.size = Vector2.ZERO
	await get_tree().process_frame
	var win := get_viewport_rect().size
	intro_panel.position = (win - intro_panel.size) / 2.0


# ════════════════════════════════════════════
#  死因 → 死亡动画 映射
# ════════════════════════════════════════════


 
 
func _play_death_animation(cause: Dictionary) -> String:
	var base_anim := anim_ctl._death_anim_for_cause(cause)
	var tier := current_tier()
	var suffix: String = GameConfig.TIER_ANIM_SUFFIX.get(tier, "")
	var tiered_anim := "%s_%s" % [suffix, base_anim]
	_current_mood_priority = GameConfig.MoodPriority.SYSTEM
	if cultivator_sprite == null or cultivator_sprite.sprite_frames == null:
		return ""
	if suffix != "" and cultivator_sprite.sprite_frames.has_animation(tiered_anim):
		cultivator_sprite.position.x = 0
		cultivator_sprite.play(tiered_anim)
		return tiered_anim
	elif cultivator_sprite.sprite_frames.has_animation(base_anim):
		cultivator_sprite.position.x = 0
		cultivator_sprite.play(base_anim)
		return base_anim
	else:
		request_mood("confused", GameConfig.MoodPriority.SYSTEM)
		return ""
	

# ════════════════════════════════════════════
#  人生履历分类美化系统  (life_history)
# ════════════════════════════════════════════

# 记录一条人生履历。category 见 LIFE_HISTORY_CATEGORY_ORDER。
func add_life_history(category: String, title_zh: String, description_zh: String = "",
		title_en: String = "", description_en: String = "") -> void:
	if not GameConfig.LIFE_HISTORY_CATEGORY_META.has(category):
		category = guess_life_history_category(title_zh + " " + description_zh)
	life_history.append({
		"life":  int(state.get("life_count", 1)),
		"age":   _current_age(),
		"realm_index": state["realm_index"],
		"category": category,
		"title_zh": title_zh,
		"title_en": title_en if title_en != "" else title_zh,
		"description_zh": description_zh,
		"description_en": description_en if description_en != "" else description_zh,
		"time":  Time.get_datetime_string_from_system()
	})
	if life_history.size() > GameConfig.LIFE_HISTORY_STORE_CAP:
		life_history.pop_front()
	if profile_panel != null and profile_panel.visible:
		profile_ui._refresh_profile()

# 兼容旧数据：String 自动转 Dictionary，不会读档报错
func normalize_life_history_entry(raw_entry) -> Dictionary:
	if typeof(raw_entry) == TYPE_DICTIONARY:
		if raw_entry.has("realm") and not raw_entry.has("realm_index"):
			var found_idx := 0
			for i in realms.size():
				if realms[i]["name"] == String(raw_entry["realm"]):
					found_idx = i
					break
			raw_entry["realm_index"] = found_idx
		# 旧格式迁移：title/description（单语言）→ title_zh/title_en（双语言，旧数据
		if raw_entry.has("title") and not raw_entry.has("title_zh"):
			raw_entry["title_zh"] = String(raw_entry["title"])
			raw_entry["title_en"] = String(raw_entry["title"])
		if raw_entry.has("description") and not raw_entry.has("description_zh"):
			raw_entry["description_zh"] = String(raw_entry["description"])
			raw_entry["description_en"] = String(raw_entry["description"])
		return raw_entry
	var text := str(raw_entry)
	return {
		"life":  int(state.get("life_count", 1)),
		"age":   _current_age(),
		"realm": realms[state["realm_index"]]["name"],
		"category": guess_life_history_category(text),
		"title": text,
		"description": "",
		"time":  ""
	}

# 旧 life_records 的 type → 履历分类
func _life_category_from_type(type: String, title: String) -> String:
	match type:
		"breakthrough": return "breakthrough"
		"death":        return "death"
		"legendary":    return "encounter"
		"item", "alchemy": return "alchemy"
		_:              return guess_life_history_category(title)

# 没有明确分类时，按关键词猜
func guess_life_history_category(text: String) -> String:
	if text.contains("出生") or text.contains("出世") or text.contains("转世") or text.contains("投胎") or text.contains("重修"):
		return "birth"
	if (
		text.contains("成为") or text.contains("职业") or text.contains("农夫") or text.contains("猎户")
		or text.contains("书生") or text.contains("商人") or text.contains("铁匠") or text.contains("无业游民")
	):
		return "birth"
	if text.contains("武者") or text.contains("练武") or text.contains("习武"):
		return "martial"
	if (
		text.contains("奇遇") or text.contains("捡到") or text.contains("机缘") or text.contains("秘境")
		or text.contains("传说")
	):
		return "encounter"
	if (
		text.contains("功法") or text.contains("秘籍") or text.contains("心法")
		or text.contains("灵根") or text.contains("觉醒")
	):
		return "skill"
	if text.contains("突破") or text.contains("晋升") or text.contains("境界") or text.contains("冲击"):
		return "breakthrough"
	if text.contains("炼丹") or text.contains("丹药") or text.contains("服用") or text.contains("嗑丹") or text.contains("炸炉"):
		return "alchemy"
	if text.contains("成就") or text.contains("称号") or text.contains("达成"):
		return "achievement"
	if text.contains("死") or text.contains("陨落") or text.contains("寿终") or text.contains("雷劈"):
		return "death"
	return "encounter"

# 生成分类美化后的 BBCode 文本（给 RichTextLabel 用）

# 单条履历：第几世｜年龄｜境界｜标题（：描述）


	
# ══════════════════════════════════════════
#  轮回天赋系统 (reincarnation perks)
# ══════════════════════════════════════════






# 越靠前越优先；爆炸放在丹药前面，因为「炸炉」类死因同时含「丹」和「炸」。


# ══════════════════════════════════════════
#  完整轮回历史 (reincarnation_history)
# ══════════════════════════════════════════

func collect_current_life_data(cause: Dictionary, title: Dictionary) -> Dictionary:
	var highest: int = clampi(int(state.get("highest_realm_this_life", state.get("realm_index", 0))), 0, realms.size() - 1)
	return {
		"life": int(state.get("life_count", 1)), "name": String(state.get("pet_name", "")),
		"age": _current_age(), "highest_realm": highest,
		"highest_realm_zh": realms[highest]["name"], "highest_realm_en": realm_names_en[highest],
		"cause_id": String(cause.get("id","")), "cause_zh": String(cause.get("title_zh","")), "cause_en": String(cause.get("title_en","")),
		"title_zh": String(title.get("zh","")), "title_en": String(title.get("en","")),
		"personality": current_personality, "mortal_job": String(state.get("mortal_job","")),
		"spiritual_root": String(state.get("spiritual_root","")), "final_luck": int(state.get("luck", 50)),
		"life_click_count": int(state.get("life_click_count", 0)),
		"life_breakthrough_fails": int(state.get("life_breakthrough_fails", 0)),
		"life_breakthrough_success": int(state.get("life_breakthrough_success", 0)),
		"life_pills_eaten": int(state.get("life_pills_eaten", 0)),
		"life_rare_count": int(state.get("life_rare_count", 0)),
		"life_legendary_count": int(state.get("life_legendary_count", 0))
	}





func _on_event_special_animation(anim_key: String) -> void:
	if anim_key == "" or cultivator_sprite == null or cultivator_sprite.sprite_frames == null:
		return
	var tier := current_tier()
	var suffix: String = GameConfig.TIER_ANIM_SUFFIX.get(tier, "")
	var tiered_anim := "%s_%s" % [suffix, anim_key]
	var anim_to_play := ""
	if suffix != "" and cultivator_sprite.sprite_frames.has_animation(tiered_anim):
		anim_to_play = tiered_anim
	elif cultivator_sprite.sprite_frames.has_animation(anim_key):
		anim_to_play = anim_key
	else:
		return   # 这个特殊动画素材还没画，安静跳过，不影响事件本身的奖励/文字
	_current_mood_priority = GameConfig.MoodPriority.SYSTEM
	cultivator_sprite.position.x = 0
	cultivator_sprite.play(anim_to_play)
	var dur := anim_ctl._death_anim_duration(anim_to_play)
	await get_tree().create_timer(max(dur, 1.0) + 0.1).timeout
	clear_mood_priority()
	request_mood("normal", GameConfig.MoodPriority.AMBIENT)


func _on_event_biography(row: Dictionary) -> void:
	var zh := String(row.get("text_zh", ""))
	var en := String(row.get("text_en", ""))
	if zh == "":
		return
	var category := guess_life_history_category(zh)
	add_life_history(category, zh, "", en, "")

func _score_context_row(row: Dictionary, ctx: Dictionary) -> int:
	var score := 0
	var matched_any_context_tag := false

	var realm_tag: String = String(row.get("realm", ""))
	if realm_tag != "" and realm_tag == current_tier():
		score += 1   # baseline realm relevance, same weight as before — not a new signal

	var luck_tag: String = String(row.get("luck_tag", ""))
	if luck_tag != "":
		if luck_tag == ctx["luck_tier"]:
			score += 3
			matched_any_context_tag = true
		else:
			return -1   # line explicitly wants a different luck state — wrong moment, hard exclude

	var personality_tag: String = String(row.get("personality_tag", ""))
	if personality_tag != "":
		if personality_tag == ctx["personality"]:
			score += 3
			matched_any_context_tag = true
		else:
			return -1

	var health_tag: String = String(row.get("health_tag", ""))
	if health_tag != "":
		if health_tag == ctx["health_tier"]:
			score += 4
			matched_any_context_tag = true
		else:
			return -1
	
	var memorable_tag: String = String(row.get("memorable_tag", ""))
	if memorable_tag != "":
		var has_memory := false
		for mem in ctx["memorable_events"]:
			if String(mem.get("tag", "")) == memorable_tag:
				has_memory = true
				break
		if has_memory:
			score += 5
			matched_any_context_tag = true
		else:
			return -1
			
	if String(row.get("soul_echo", "")) == "true":
		if ctx["soul_echo_available"]:
			score += 4
			matched_any_context_tag = true
		else:
			return -1

	var instinct_tag: String = String(row.get("instinct_tag", ""))
	if instinct_tag != "":
		if instinct_tag == ctx["instinct_tag"]:
			score += 3
			matched_any_context_tag = true
		else:
			return -1
	
	var goal_tag: String = String(row.get("goal_tag", ""))
	if goal_tag != "":
		if goal_tag == ctx["goal"]:
			score += 3
			matched_any_context_tag = true
		else:
			return -1

	if String(row.get("requires_fail_streak", "")) == "true":
		if ctx["recent_fail_streak"]:
			score += 4
			matched_any_context_tag = true
		else:
			return -1

	var event_tag: String = String(row.get("event_tag", ""))
	if event_tag != "":
		if ctx["today_event_tags"].has(event_tag):
			score += 6   # today's events are the strongest signal — this just happened
			matched_any_context_tag = true
		elif ctx["yesterday_event_tags"].has(event_tag):
			score += 2   # yesterday still echoes, but much quieter
			matched_any_context_tag = true
		else:
			return -1

	if not matched_any_context_tag and row.get("luck_tag","")=="" and row.get("personality_tag","")=="" \
		and row.get("health_tag","")=="" and row.get("goal_tag","")=="" and row.get("event_tag","")=="" \
		and row.get("memorable_tag","")=="" and row.get("soul_echo","")!="true" \
		and row.get("instinct_tag","")=="" and row.get("requires_fail_streak","")!="true":
		score = max(score, 1)

	return score

func _tomorrow_hint_text() -> Dictionary:
	var goal := _current_goal_tag()
	match goal:
		"near_breakthrough":
			return {"zh": "明日似乎将有突破之机。", "en": "Tomorrow may bring a chance to break through."}
		"awaiting_root":
			return {"zh": "灵根觉醒，似乎就在不远处。", "en": "Spiritual root awakening feels close."}
		"banking_insight":
			return {"zh": "感悟渐深，明日或有转机。", "en": "Insight deepens — tomorrow may turn the tide."}
		_:
			return {"zh": "明日如何，尚未可知。", "en": "What tomorrow holds remains unknown."}
		
func _build_daily_gazette() -> Dictionary:
	var today_memory := _todays_memorable_highlight()
	var highlight_tag := _todays_highlight_tag()
	var headline: Dictionary = GameConfig.HEADLINE_TEMPLATES.get(highlight_tag, GameConfig.HEADLINE_TEMPLATES["none"])
	var highlight_text: Dictionary
	if not today_memory.is_empty():
		highlight_text = {"zh": String(today_memory.get("title_zh","")), "en": String(today_memory.get("title_en",""))}
	else:
		highlight_text = _highlight_text_for_tag(highlight_tag)
		
	var fortune_zh := "%s（%d）" % [luck_tier(), int(state["luck"])]
	var fortune_en := "%s (%d)" % [luck_tier_en(), int(state["luck"])]

	var rumour_pool: Array = DataLoader.rumours.filter(
	func(r): return r["realm"] == "" or r["realm"] == current_tier()
)
	if rumour_pool.is_empty(): rumour_pool = DataLoader.rumours
	var legendary_rumour := _legendary_past_life_rumour()
	if not legendary_rumour.is_empty() and randf() < 0.15:
		rumour_pool = [legendary_rumour]
	var rumour: Dictionary = rumour_pool.pick_random() if not rumour_pool.is_empty() else {"zh":"","en":""}
	
	var hint := _tomorrow_hint_text()

	var achievement_zh := "无" if _achievement_unlocked_today.is_empty() else ", ".join(_achievement_unlocked_today.keys())
	var achievement_en := "None" if _achievement_unlocked_today.is_empty() else "Unlocked today"

	var nb_pool: Array = DataLoader.neighbour_comments.filter(func(r):
		var tag: String = String(r.get("personality_tag", ""))
		return tag == "" or tag == current_personality
	)
	var neighbour: Dictionary = nb_pool.pick_random() if not nb_pool.is_empty() else {"zh":"","en":""}

	return {
		"headline_zh": headline["zh"], "headline_en": headline["en"],
		"highlight_zh": highlight_text["zh"], "highlight_en": highlight_text["en"],
		"fortune_zh": fortune_zh, "fortune_en": fortune_en,
		"rumour_zh": rumour["zh"], "rumour_en": rumour["en"],
		"hint_zh": hint["zh"], "hint_en": hint["en"],
		"achievement_zh": achievement_zh, "achievement_en": achievement_en,
		"neighbour_zh": neighbour["zh"], "neighbour_en": neighbour["en"]
	}

func _legendary_past_life_rumour() -> Dictionary:
	var candidates: Array = []
	for r in reincarnation_history:
		if typeof(r) == TYPE_DICTIONARY and _is_echo_worthy(r):
			candidates.append(r)
	if candidates.is_empty():
		return {}
	var idx := randi() % candidates.size()
	var picked: Dictionary = candidates[idx]
	var title_zh: String = String(picked.get("title_zh",""))
	var title_en: String = String(picked.get("title_en",""))
	var cause_zh: String = String(picked.get("cause_zh",""))
	var cause_en: String = String(picked.get("cause_en",""))
	if title_zh == "" or cause_zh == "":
		return {}
	return {
		"zh": "听说曾有位「%s」的修士，最后%s。" % [title_zh, cause_zh],
		"en": "They say a cultivator known as \"%s\" once existed — in the end, %s." % [title_en, cause_en]
	}

func _highlight_text_for_tag(tag: String) -> Dictionary:
	match tag:
		"breakthrough_success":
			var realm_name_zh: String = realms[state["realm_index"]]["name"]
			var realm_name_en: String = realm_names_en[state["realm_index"]]
			return {
				"zh": "今日成功突破至「%s」，可喜可贺。" % realm_name_zh,
				"en": "Successfully broke through to %s today — cause for celebration." % realm_name_en
			}
		"breakthrough_fail":
			var fails_today: int = int(today_stats.get("breakthrough_attempt", 0)) - int(today_stats.get("breakthrough_success", 0))
			return {
				"zh": "今日突破未果，已失败 %d 次，但感悟未曾白费。" % max(1, fails_today),
				"en": "Breakthrough attempts failed %d time(s) today — but the insight wasn't wasted." % max(1, fails_today)
			}
		"legendary_encounter":
			return {
				"zh": "今日撞上了一场传说级奇遇，整条街都在议论。",
				"en": "Ran into a legendary encounter today — the whole street is talking about it."
			}
		"death":
			return _last_death_punchline if not _last_death_punchline.get("zh","").is_empty() else {"zh":"今日没有特别的事。","en":"Nothing remarkable today."}
		"rare_encounter":
			return {
				"zh": "今日有些不寻常的奇遇，运气不错。",
				"en": "Something unusual happened today. Lucky, all things considered."
			}
		"furnace_explosion":
			return {
				"zh": "丹炉今日再度殉职，邻居都听到了响声。",
				"en": "The furnace gave its life again today. The neighbors heard the bang."
			}
		"found_stone":
			var stones_today: int = int(today_stats.get("stone_gain", 0))
			return {
				"zh": "今日捡到了 %d 颗灵石，小有收获。" % max(1, stones_today),
				"en": "Picked up %d spirit stone(s) today. A modest gain." % max(1, stones_today)
			}
		_:
			return {
				"zh": "今日修炼如常，没有什么特别的事。",
				"en": "Cultivation proceeded as usual today. Nothing remarkable."
			}

	

	

func _record_memorable_event(tag: String, title_zh: String, title_en: String, chain_id: String = "") -> void:
	memorable_events.append({
		"tag": tag, "age": _current_age(),
		"title_zh": title_zh, "title_en": title_en, "chain_id": chain_id
	})
	if memorable_events.size() > GameConfig.MEMORABLE_EVENTS_CAP:
		memorable_events.pop_front()
		
func _set_foreshadow(tag: String, expires_in_days: int) -> void:
	_foreshadow_flags[tag] = {"day_set": _day_counter, "expires_day": _day_counter + max(1, expires_in_days)}

func _foreshadow_active(tag: String) -> bool:
	if not _foreshadow_flags.has(tag):
		return false
	return int(_foreshadow_flags[tag].get("expires_day", 0)) >= _day_counter

func _clear_expired_foreshadows() -> void:
	var remaining: Dictionary = {}
	for tag in _foreshadow_flags:
		if int(_foreshadow_flags[tag].get("expires_day", 0)) >= _day_counter:
			remaining[tag] = _foreshadow_flags[tag]
	_foreshadow_flags = remaining

func _on_story_moment_created(moment: Dictionary) -> void:
	moment["age"] = _current_age()
	moment["day"] = _day_counter

	_register_today_event_tag(moment)
	_register_memorable_event(moment)
	_update_dialogue_context(moment)
	_update_daily_report_context(moment)
	_update_life_chronicle_from_moment(moment)
	_update_achievement_from_moment(moment)
	_update_foreshadow_from_moment(moment)

	save_mgr.save_game()

func _register_today_event_tag(moment: Dictionary) -> void:
	var event_type := String(moment.get("event_type", ""))
	var rarity := String(moment.get("rarity", ""))

	if event_type != "":
		_today_event_tags[event_type] = true

	if rarity == "rare":
		_today_event_tags["rare_encounter"] = true
	elif rarity == "legendary":
		_today_event_tags["legendary_encounter"] = true
		
func _register_memorable_event(moment: Dictionary) -> void:
	var rarity := String(moment.get("rarity", "normal"))
	var importance := String(moment.get("importance", "normal"))

	if rarity == "normal" and importance == "normal":
		return

	memorable_events.append(moment)

	while memorable_events.size() > GameConfig.MEMORABLE_EVENTS_CAP:
		memorable_events.pop_front()
func _update_dialogue_context(moment: Dictionary) -> void:
	life_flags["last_event_type"] = String(moment.get("event_type", ""))
	life_flags["last_event_id"] = String(moment.get("event_id", ""))
	life_flags["last_event_rarity"] = String(moment.get("rarity", "normal"))

func _update_daily_report_context(moment: Dictionary) -> void:
	var event_type := String(moment.get("event_type", ""))
	if event_type != "":
		_today_event_tags[event_type] = true

	if String(moment.get("rarity", "")) == "legendary":
		_today_event_tags["legendary_encounter"] = true
		
func _update_life_chronicle_from_moment(moment: Dictionary) -> void:
	var importance := String(moment.get("importance", "normal"))
	var rarity := String(moment.get("rarity", "normal"))

	if importance == "normal" and rarity == "normal":
		return

	add_life_history(
		"encounter",
		String(moment.get("text_zh", "")),
		"",
		String(moment.get("text_en", "")),
		""
	)
func _update_achievement_from_moment(moment: Dictionary) -> void:
	if achievement_manager == null:
		return
	achievement_manager.record_story_moment(moment)

	var event_type := String(moment.get("event_type", ""))
	if event_type != "":
		achievement_manager.record_event(event_type)

	if String(moment.get("rarity", "")) == "legendary":
		achievement_manager.record_encounter_legendary()
func _update_foreshadow_from_moment(moment: Dictionary) -> void:
	var event_type := String(moment.get("event_type", ""))

	if event_type == "alchemy":
		_foreshadow_flags["furnace_risk"] = {
			"day_set": _day_counter,
			"expires_day": _day_counter + 2
		}

func _instinct_display_text(zh: bool) -> String:
	match _instinct_tag:
		"wary_of_tribulation": return "惧雷" if zh else "Wary of Tribulation"
		"drawn_to_furnaces":   return "好炼丹" if zh else "Drawn to Furnaces"
		"seeks_encounters":    return "好奇遇" if zh else "Seeks Encounters"
		_: return "无" if zh else "None"

		
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_quit_requested()

func _on_quit_requested() -> void:
	if _quitting:
		get_tree().quit()   # 二次触发直接放行，绝不卡住玩家
		return
	_quitting = true
	save_mgr.save_game()
	var line: Dictionary = GameConfig.FAREWELL_LINES.pick_random()
	show_message_now(line["zh"] if current_language == "zh" else line["en"])
	await get_tree().create_timer(1.6).timeout
	get_tree().quit()
func _build_decision_ui() -> void:
	# 头顶灵光（可点击）
	decision_indicator = Button.new()
	decision_indicator.flat = true
	decision_indicator.text = "✦"
	decision_indicator.add_theme_font_size_override("font_size", 22)
	decision_indicator.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	decision_indicator.add_theme_color_override("font_hover_color", Color(1.0, 0.82, 0.35))
	decision_indicator.custom_minimum_size = Vector2(30, 30)
	decision_indicator.position = GameConfig.DECISION_INDICATOR_POS
	decision_indicator.visible = false
	decision_indicator.pressed.connect(_open_decision_bubble)
	pet_group.add_child(decision_indicator)
 
	# 问题气泡（复用对话气泡的视觉语言）
	decision_bubble = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.95, 0.86, 0.97)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.62, 0.48, 0.24, 0.9)
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 5
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	decision_bubble.add_theme_stylebox_override("panel", sb)
	decision_bubble.custom_minimum_size = Vector2(190, 0)
	decision_bubble.visible = false
	decision_bubble.z_index = 150
	pet_group.add_child(decision_bubble)
 
 
func _offer_decision(row: Dictionary) -> void:
	var ids := String(row.get("next_ids", "")).split("|")
	if ids.size() < 2:
		# CSV 配置不完整：不卡链，按普通分支放行
		if ids.size() == 1 and ids[0].strip_edges() != "":
			pending_chains.append(ids[0].strip_edges())
		return
	# 同时只允许一个待决心念；旧的先自动了结
	if not _pending_decision.is_empty():
		_resolve_decision("a" if randf() < 0.5 else "b", false)
	_pending_decision = {
		"row_id": String(row.get("id", "")),
		"prompt_zh": String(row.get("choice_prompt_zh", "")),
		"prompt_en": String(row.get("choice_prompt_en", "")),
		"a_zh": String(row.get("choice_a_zh", "选项一")),
		"a_en": String(row.get("choice_a_en", "Option A")),
		"a_next": ids[0].strip_edges(),
		"b_zh": String(row.get("choice_b_zh", "选项二")),
		"b_en": String(row.get("choice_b_en", "Option B")),
		"b_next": ids[1].strip_edges(),
		"set_day": _day_counter
	}
	_show_decision_indicator()
	save_mgr.save_game()
 
 
func _show_decision_indicator() -> void:
	if decision_indicator == null or _pending_decision.is_empty():
		return
	decision_indicator.visible = true
	if _indicator_tween != null and _indicator_tween.is_valid():
		_indicator_tween.kill()
	decision_indicator.modulate = Color(1, 1, 1, 0.55)
	_indicator_tween = create_tween().set_loops()
	_indicator_tween.tween_property(decision_indicator, "modulate:a", 1.0, 0.9)
	_indicator_tween.tween_property(decision_indicator, "modulate:a", 0.55, 0.9)
 
 
func _hide_decision_indicator() -> void:
	if _indicator_tween != null and _indicator_tween.is_valid():
		_indicator_tween.kill()
	if decision_indicator != null:
		decision_indicator.visible = false
	if decision_bubble != null:
		decision_bubble.visible = false
 
 
func _open_decision_bubble() -> void:
	_mark_interaction()
	if _pending_decision.is_empty() or _is_cutscene_blocking():
		return
	var zh := current_language == "zh"
	for child in decision_bubble.get_children():
		child.queue_free()
 
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	decision_bubble.add_child(vb)
 
	var prompt := Label.new()
	prompt.text = String(_pending_decision["prompt_zh"] if zh else _pending_decision["prompt_en"])
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(180, 0)
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", Color(0.25, 0.18, 0.10))
	vb.add_child(prompt)
 
	var btn_a := Button.new()
	btn_a.text = String(_pending_decision["a_zh"] if zh else _pending_decision["a_en"])
	btn_a.pressed.connect(func(): _resolve_decision("a", true))
	vb.add_child(btn_a)
 
	var btn_b := Button.new()
	btn_b.text = String(_pending_decision["b_zh"] if zh else _pending_decision["b_en"])
	btn_b.pressed.connect(func(): _resolve_decision("b", true))
	vb.add_child(btn_b)
 
	decision_bubble.visible = true
	decision_bubble.size = Vector2.ZERO
	await get_tree().process_frame
	decision_bubble.position = Vector2(-decision_bubble.size.x / 2.0,
		GameConfig.BUBBLE_ANCHOR_Y - decision_bubble.size.y - GameConfig.BUBBLE_GAP)
 
 
func _resolve_decision(which: String, by_player: bool) -> void:
	if _pending_decision.is_empty():
		return
	var zh := current_language == "zh"
	var nid := String(_pending_decision["a_next"] if which == "a" else _pending_decision["b_next"])
	var label_zh := String(_pending_decision["a_zh"] if which == "a" else _pending_decision["b_zh"])
	var label_en := String(_pending_decision["a_en"] if which == "a" else _pending_decision["b_en"])
 
	if nid != "" and not pending_chains.has(nid):
		pending_chains.append(nid)
 
	if by_player:
		add_recent_event("拿定主意：%s" % label_zh, "Decided: %s" % label_en, "special")
		show_message_now(("就这么办——%s。" % label_zh) if zh else ("So be it - %s." % label_en))
	else:
		add_recent_event("他自己拿了主意：%s" % label_zh,
			"He made up his own mind: %s" % label_en, "special")
		add_life_history("encounter", "心念自决",
			"等不到师父示下，他自己拿了主意——%s。" % label_zh,
			"Mind Made Up",
			"With no word from above - he decided himself: %s." % label_en)
 
	_pending_decision = {}
	_hide_decision_indicator()
	save_mgr.save_game()
 
 
func _auto_resolve_stale_decision() -> void:
	if _pending_decision.is_empty():
		return
	if int(_pending_decision.get("set_day", 0)) >= _day_counter:
		return   # 当天不催
	# CSV 约定：A=冒险/行动，B=保守/不动 → 按性格加权
	var chance_a := 0.5
	match current_personality:
		"reckless", "diligent":
			chance_a = 0.75
		"cautious", "lazy":
			chance_a = 0.25
	_resolve_decision("a" if randf() < chance_a else "b", false)
 
 
func _clear_decision() -> void:
	_pending_decision = {}
	_hide_decision_indicator()
 

var _active := false
var _death_count := 0
var _timer: Timer
var _counter_label: Label

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_toggle()

func _toggle() -> void:
	_active = not _active
	_counter_label.visible = _active
	if _active:
		_timer.start()
		_do_one_death()  # 立刻来一次，不等第一个interval
	else:
		_timer.stop()

func _do_one_death() -> void:
	_death_count += 1
	_counter_label.text = "观测第 %d 次身亡" % _death_count

	# --- TODO: 接你的死亡系统 ---
	# 1. 随机挑一条死法（如果只想录"最上镜"的几种，用白名单）
	var death := _pick_death()
	# 2. 触发死亡流程，但跳过正常的存档/统计副作用
	#    建议在你的 die() 函数加一个 marketing_mode 参数，
	#    跳过 save、成就、离线收益结算，只走视觉流程
	# Main.trigger_death(death["id"], true)  # true = marketing_mode

	# 3. 遗言+点评弹幕（复用你的punchline生成）
	# var last_words := Main.generate_last_words(death)
	# Main.show_death_popup(death["cause"], last_words)

	if GameConfig.SHOW_CERTIFICATE:
		await get_tree().create_timer(GameConfig.DEATH_INTERVAL - GameConfig.CERT_FLASH_TIME - 0.5).timeout
		# Main.show_certificate_panel()
		await get_tree().create_timer(GameConfig.CERT_FLASH_TIME).timeout
		# Main.hide_certificate_panel()
		# Main.instant_reincarnate()  # 跳过正常转世等待

# 白名单：只轮播表现力最强的死法（按你的 death_causes.csv 实际 id 填）

func _pick_death() -> Dictionary:
	# TODO: 换成你的 CSV 数据访问方式
	# var pool = DeathData.all() if FEATURED_DEATHS.is_empty() \
	#     else DeathData.all().filter(func(d): return d["id"] in FEATURED_DEATHS)
	# return pool.pick_random()
	return {}

func _build_counter_overlay() -> void:
	_counter_label = Label.new()
	_counter_label.text = "观测第 0 次身亡"
	_counter_label.visible = false
	_counter_label.add_theme_font_size_override("font_size", 28)
	_counter_label.position = Vector2(24, 24)
	# 描边让计数器在任何桌面背景上都清晰
	_counter_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_counter_label.add_theme_constant_override("outline_size", 6)
	add_child(_counter_label)

# ══════════════════════════════════════════
#  面板统一定位：钉在角色旁，屏幕边缘自动翻面
# ══════════════════════════════════════════

# 记录当前"停靠中"的面板，undock 时才知道要把窗口缩回去
var _docked_panel: Control = null

func _dock_panel(panel: Control) -> void:
	# 1. 选一个不会被顶出屏幕的窗口位置，再 resize
	main_hall_panel.visible
	var safe_pos := _get_safe_window_position(GameConfig.WIN_WIDE)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = GameConfig.WIN_WIDE
	await get_tree().process_frame
	update_layout()
	_reposition_overlay_panels()

	# 2. 显示面板，等它把 size 撑出来
	panel.visible = true
	panel.size = Vector2.ZERO
	await get_tree().process_frame

	# 3. 算面板该贴在角色的哪一侧
	panel.position = _panel_dock_position(panel.size)
	_docked_panel = panel

func _undock_panel(panel: Control) -> void:
	panel.visible = false
	if _docked_panel == panel:
		_docked_panel = null
	get_window().size = GameConfig.WIN_NORMAL
	await get_tree().process_frame
	update_layout()
	_reposition_overlay_panels()


# 面板默认贴在角色右侧（现有布局习惯）；
# 如果当前窗口在屏幕上的位置太靠右/靠下，翻到左侧/上方。
func _panel_dock_position(panel_size: Vector2) -> Vector2:
	var win := get_viewport_rect().size
	var win_screen_pos := DisplayServer.window_get_position()
	var screen_size := DisplayServer.screen_get_size()

	var dock_right := true
	# 如果窗口右边缘已经贴着屏幕边缘（说明 _get_safe_window_position 把窗口
	# 往左顶过了），面板贴右侧会紧贴屏幕边界，体验局促——改贴左侧。
	if win_screen_pos.x + win.x >= screen_size.x - 4:
		dock_right = false

	var x: float
	if dock_right:
		x = win.x - panel_size.x - GameConfig.REPORT_MARGIN
	else:
		x = GameConfig.REPORT_MARGIN

	var y := GameConfig.REPORT_Y
	# 垂直方向同理：面板底部若超出窗口，往上收
	if y + panel_size.y > win.y - GameConfig.REPORT_MARGIN:
		y = max(GameConfig.REPORT_MARGIN, win.y - panel_size.y - GameConfig.REPORT_MARGIN)

	return Vector2(x, y)



#---------------------------------------------------------
 
var quick_bar: HBoxContainer
var _quick_shown := false
var _quick_tween: Tween
 
func _build_quick_bar() -> void:
	quick_bar = HBoxContainer.new()
	quick_bar.name = "QuickBar"
	quick_bar.add_theme_constant_override("separation", 14)
	quick_bar.modulate = Color(1, 1, 1, 0)
	quick_bar.visible = false
	quick_bar.z_index = 30
	pet_group.add_child(quick_bar)
 
	var defs := [
		{"icon": "res://assets/ui/quick_eat.png",    "fallback": "🍚",
		 "zh": "吃", "en": "Eat", "fn": func(): _on_feed()},
		{"icon": "res://assets/ui/quick_life.png",   "fallback": "🧘",
		 "zh": "人生", "en": "Life", "fn": func(): _open_main_hall()},
		{"icon": "res://assets/ui/quick_events.png", "fallback": "📜",
		 "zh": "事件", "en": "Events", "fn": func(): report_ui._on_report_pressed()},
	]
 
	for d in defs:
		var item_vb := VBoxContainer.new()
		item_vb.add_theme_constant_override("separation", 2)
		item_vb.alignment = BoxContainer.ALIGNMENT_CENTER

		var btn: BaseButton
		if ResourceLoader.exists(d["icon"]):
			var tb := TextureButton.new()
			tb.texture_normal = load(d["icon"])
			tb.ignore_texture_size = true
			tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			tb.custom_minimum_size = Vector2(GameConfig.QUICK_ICON_SIZE, GameConfig.QUICK_ICON_SIZE)
			btn = tb
		else:
			var b := Button.new()
			b.text = d["fallback"]
			b.custom_minimum_size = Vector2(GameConfig.QUICK_ICON_SIZE, GameConfig.QUICK_ICON_SIZE)
			b.add_theme_font_size_override("font_size", 26)
			btn = b
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(d["fn"])
		btn.mouse_entered.connect(func():
			btn.pivot_offset = btn.size / 2.0
			var t := create_tween()
			t.tween_property(btn, "scale", Vector2(1.12, 1.12), 0.1))
		btn.mouse_exited.connect(func():
			var t := create_tween()
			t.tween_property(btn, "scale", Vector2.ONE, 0.1))
		item_vb.add_child(btn)

		var lbl := Label.new()
		lbl.text = d["zh"] if current_language == "zh" else d["en"]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.28, 0.20, 0.12))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.add_theme_color_override("font_outline_color", Color(0.98, 0.96, 0.90, 0.95))
		lbl.set_meta("zh", d["zh"])
		lbl.set_meta("en", d["en"])
		item_vb.add_child(lbl)

		quick_bar.add_child(item_vb)
 
	# 每 0.1 秒检查一次鼠标是否在角色附近
	var hover_timer := Timer.new()
	hover_timer.wait_time = 0.1
	hover_timer.timeout.connect(_check_quick_hover)
	add_child(hover_timer)
	hover_timer.start()
 
func _quick_bar_blocked() -> bool:
	if _is_cutscene_blocking():
		return true
	if main_hall_panel != null and main_hall_panel.visible:
		return true
	if dragging:
		return true
	# 补：任何全屏/模态弹窗开着时都不出快捷条
	if event_popup != null and event_popup.popup_panel != null and event_popup.popup_panel.visible:
		return true
	if achievement_ui != null and achievement_ui.panel != null and achievement_ui.panel.visible:
		return true
	if certificate_panel != null and certificate_panel.visible:
		return true
	if report_panel != null and report_panel.visible:
		return true
	if shop_panel != null and shop_panel.visible:
		return true
	if profile_panel != null and profile_panel.visible:
		return true
	return false
 
func _check_quick_hover() -> void:
	if quick_bar == null:
		return
	if _quick_bar_blocked():
		_set_quick_visible(false)
		return
 
	# 悬停判定区：角色包围盒外扩 + 按钮条区域（鼠标移到按钮上不会缩回去）
	var mp := get_viewport().get_mouse_position()
	var center: Vector2 = pet_group.position + cultivator_sprite.position * pet_group.scale
	var half := Vector2(70, 90) + Vector2(GameConfig.QUICK_HOVER_MARGIN, GameConfig.QUICK_HOVER_MARGIN)
	var zone := Rect2(center - half, half * 2.0)
	# 把按钮条区域并进判定区
	zone = zone.merge(Rect2(
		pet_group.position + Vector2(-110, GameConfig.QUICK_BAR_Y - 10),
		Vector2(220, GameConfig.QUICK_ICON_SIZE + 40)
	))
 
	_set_quick_visible(zone.has_point(mp))
 
func _set_quick_visible(v: bool) -> void:
	if v == _quick_shown:
		return
	_quick_shown = v
	if _quick_tween != null and _quick_tween.is_valid():
		_quick_tween.kill()
	if v:
		quick_bar.visible = true
		# 先摆好位置（水平居中在角色下方）
		quick_bar.size = Vector2.ZERO
		await get_tree().process_frame
		quick_bar.position = Vector2(-quick_bar.size.x / 2.0, GameConfig.QUICK_BAR_Y)
		_quick_tween = create_tween()
		_quick_tween.tween_property(quick_bar, "modulate:a", 1.0, GameConfig.QUICK_FADE)
	else:
		_quick_tween = create_tween()
		_quick_tween.tween_property(quick_bar, "modulate:a", 0.0, GameConfig.QUICK_FADE)
		_quick_tween.tween_callback(func(): quick_bar.visible = false)
		
 
# 颜色
 
# 字号（都是 frame 原始坐标系下的，最后随面板一起缩放）
 
var mh_font: FontFile
 
var main_hall_panel: Control
var mh_root: Control                # 所有内容挂这下面，统一缩放
var mh_name_label: Label
var mh_verdict_label: Label
var mh_cult_bar: ProgressBar
var mh_cult_pct: Label
var mh_cult_nums: Label
# 基本信息各值
var mh_v_realm: Label
var mh_v_personality: Label
var mh_v_job: Label
var mh_v_luck: Label
var mh_v_lifespan: Label
var mh_v_life: Label
var mh_v_perk: Label
var mh_v_stones: Label
# 本世记录各值
var mh_r_time: Label
var mh_r_events: Label
var mh_r_break: Label
var mh_r_death: Label
var mh_r_encounter: Label
var mh_r_companion: Label
 
var _mh_session_seconds: int = 0
var _mh_offline_seconds: int = 0
 
# ── 字体小工具 ──
func _mh_get_font() -> FontFile:
	return GameConfig.body_font()

func _mh_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f := _mh_get_font()
	if f != null:
		l.add_theme_font_override("font", f)
	return l
 
# 基本信息一行：标签（定宽）+ 值
func _mh_field_row(label_text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var lab := _mh_label(label_text, GameConfig.MH_FS_LABEL, GameConfig.MH_INK_SOFT)
	lab.custom_minimum_size = Vector2(96, 0)
	row.add_child(lab)
	var val := _mh_label("", GameConfig.MH_FS_VALUE, GameConfig.MH_INK)
	row.add_child(val)
	return [row, val]
 
# 本世记录一行：名称（左）+ 值（右对齐）
func _mh_record_row(name_text: String) -> Array:
	var row := HBoxContainer.new()
	var nm := _mh_label(name_text, GameConfig.MH_FS_LABEL, GameConfig.MH_INK)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	var val := _mh_label("", GameConfig.MH_FS_VALUE, GameConfig.MH_INK)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return [row, val]
 
func _mh_tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null
 
# ══════════════════════════════════════════
#  BUILD
# ══════════════════════════════════════════
 
func _build_main_hall() -> void:
	main_hall_panel = Control.new()
	main_hall_panel.name = "MainHallPanel"
	main_hall_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hall_panel.visible = false
	main_hall_panel.z_index = 40
	add_child(main_hall_panel)
 
	# mh_root 用 frame 原始坐标系（1167×959），打开时整体 scale 到窗口
	mh_root = Control.new()
	mh_root.custom_minimum_size = GameConfig.MH_FRAME_SIZE
	mh_root.size = GameConfig.MH_FRAME_SIZE
	main_hall_panel.add_child(mh_root)
 
	# ① 背景框（固定尺寸，不拉伸，保住四角装饰）
	var frame := TextureRect.new()
	var frame_tex := _mh_tex("res://assets/ui/frame_bg.png")
	if frame_tex != null:
		frame.texture = frame_tex
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = GameConfig.MH_FRAME_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mh_root.add_child(frame)
 
	# ② 标题（中/英随语言切换）
	var logo := TextureRect.new()
	logo.name = "MHLogo"
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mh_root.add_child(logo)
	_mh_update_logo(logo)
 
	# ③ ✕ 关闭
	var close := TextureButton.new()
	var close_tex := _mh_tex("res://assets/ui/close_button.png")
	if close_tex != null:
		close.texture_normal = close_tex
	else:
		# 兜底：文字按钮
		var cb := Button.new()
		cb.text = "✕"
		cb.position = Vector2(GameConfig.MH_FRAME_SIZE.x - 130, 40)
		cb.pressed.connect(_close_main_hall)
		mh_root.add_child(cb)
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.custom_minimum_size = Vector2(56, 56)
	close.size = Vector2(56, 56)
	close.position = Vector2(GameConfig.MH_FRAME_SIZE.x - 150, 44)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_close_main_hall)
	mh_root.add_child(close)
 
	_mh_build_name_plate()
	_mh_build_left_panel()
	_mh_build_right_panel()
	_mh_build_cultivation_bar()
 
		# 成就吊牌
	var ach_tag := TextureButton.new()
	if ResourceLoader.exists("res://assets/ui/tab.png"):
		ach_tag.texture_normal = load("res://assets/ui/tab.png")
	ach_tag.ignore_texture_size = true
	ach_tag.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	ach_tag.position = Vector2(78, 8)
	ach_tag.size = Vector2(130, 200)
	ach_tag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ach_tag.pressed.connect(_open_achievement_panel)
	mh_root.add_child(ach_tag)
	var ach_lbl := _mh_label("成就", 26, GameConfig.MH_INK)
	ach_lbl.position = Vector2(78, 118)
	ach_lbl.size = Vector2(130, 40)
	ach_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if GameConfig.brush_font() != null:
		ach_lbl.add_theme_font_override("font", GameConfig.brush_font())
	ach_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mh_root.add_child(ach_lbl)


func _open_achievement_panel() -> void:
	_mark_interaction()
	if _is_cutscene_blocking():
		return

	if achievement_ui == null or achievement_ui.panel == null:
		push_warning("Achievement panel is not ready.")
		return

	# 成就面板是自己的面板，跟 profile_panel / profile_tabs 无关。
	# 原来这里挡了一道 `profile_tabs == null`，而 profile_tabs 全项目从来没被赋值过，
	# 所以这个函数一直在提前 return —— 点成就只看到大厅关掉、窗口缩回 WIN_NORMAL。
	if main_hall_panel != null and main_hall_panel.visible:
		await _close_main_hall(false)   # 不要缩窗口，下面马上要撑到 WIN_MAIN

	if profile_panel != null: profile_panel.visible = false
	if shop_panel != null: shop_panel.visible = false
	if report_panel != null: report_panel.visible = false

	# 窗口尺寸由 achievement_ui.open() 自己负责（跟 report_ui 一致），
	# 这里不要再设一次，否则两边各撑一回。
	achievement_ui.open()

# ── 名字牌（居中偏上，角色头顶）──
func _mh_build_name_plate() -> void:
	var plate := TextureRect.new()
	var tex := _mh_tex("res://assets/ui/name_panel.png")
	var pw := 340.0
	var ph := 90.0
	if tex != null:
		plate.texture = tex
		pw = tex.get_width()
		ph = tex.get_height()
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plate.size = Vector2(pw, ph)
	plate.position = Vector2((GameConfig.MH_FRAME_SIZE.x - pw) / 2.0, 205.0)
	mh_root.add_child(plate)
 
	mh_name_label = _mh_label("", GameConfig.MH_FS_NAME, GameConfig.MH_INK)
	mh_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mh_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mh_name_label.size = Vector2(pw, ph)
	mh_name_label.position = plate.position
	mh_root.add_child(mh_name_label)
 
# ── 左栏：基本信息 ──
func _mh_build_left_panel() -> void:
	var card := TextureRect.new()
	var tex := _mh_tex("res://assets/ui/side_panel.png")
	var cw := 324.0
	var ch := 612.0
	if tex != null:
		card.texture = tex
		cw = tex.get_width()
		ch = tex.get_height()
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.size = Vector2(cw, ch)
	card.position = Vector2(88, 185)
	mh_root.add_child(card)
 
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	# 卡内留白（避开描边和四角铆钉）
	vb.position = card.position + Vector2(34, 40)
	vb.custom_minimum_size = Vector2(cw - 68, 0)
	mh_root.add_child(vb)
 
	var head := _mh_label("基本信息", GameConfig.MH_FS_SECTION, GameConfig.MH_INK)
	if GameConfig.brush_font() != null:
		head.add_theme_font_override("font", GameConfig.brush_font())
	vb.add_child(head)
	vb.add_child(_mh_gold_rule(cw - 78))
 
	var r1 = _mh_field_row("境界");      vb.add_child(r1[0]); mh_v_realm = r1[1]
	var r2 = _mh_field_row("性情");      vb.add_child(r2[0]); mh_v_personality = r2[1]
	var r3 = _mh_field_row("职业");      vb.add_child(r3[0]); mh_v_job = r3[1]
	var r4 = _mh_field_row("气运");      vb.add_child(r4[0]); mh_v_luck = r4[1]
	var r5 = _mh_field_row("寿元");      vb.add_child(r5[0]); mh_v_lifespan = r5[1]
	var r6 = _mh_field_row("第");        vb.add_child(r6[0]); mh_v_life = r6[1]
	var r7 = _mh_field_row("轮回天赋");  vb.add_child(r7[0]); mh_v_perk = r7[1]
	vb.add_child(_mh_gold_rule(cw - 78))
	var r8 = _mh_field_row("灵石");      vb.add_child(r8[0]); mh_v_stones = r8[1]
	var r9 = _mh_field_row("陪伴时间");  vb.add_child(r9[0]); mh_r_companion = r9[1]
 
# ── 右栏：天道评价 + 本世记录 ──
func _mh_build_right_panel() -> void:
	var card := TextureRect.new()
	var tex := _mh_tex("res://assets/ui/side_panel.png")
	var cw := 324.0
	var ch := 612.0
	if tex != null:
		card.texture = tex
		cw = tex.get_width()
		ch = tex.get_height()
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.size = Vector2(cw, ch)
	card.position = Vector2(GameConfig.MH_FRAME_SIZE.x - cw - 88, 185)
	mh_root.add_child(card)
 
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.position = card.position + Vector2(34, 40)
	vb.custom_minimum_size = Vector2(cw - 68, 0)
	mh_root.add_child(vb)
 
	# 天道评价
	var head := _mh_label("天道评价", GameConfig.MH_FS_SECTION, GameConfig.MH_INK)
	if GameConfig.brush_font() != null:
		head.add_theme_font_override("font", GameConfig.brush_font())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.custom_minimum_size = Vector2(cw - 68, 0)
	vb.add_child(head)
	vb.add_child(_mh_gold_rule(cw - 78))
 
	mh_verdict_label = _mh_label("", GameConfig.MH_FS_VERDICT, GameConfig.MH_INK)
	mh_verdict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mh_verdict_label.custom_minimum_size = Vector2(cw - 78, 0)
	vb.add_child(mh_verdict_label)
 
	# 间隔
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vb.add_child(spacer)
 
	# 本世记录
	var rec_head := _mh_label("本世记录", GameConfig.MH_FS_SECTION, GameConfig.MH_INK)
	if GameConfig.brush_font() != null:
		rec_head.add_theme_font_override("font", GameConfig.brush_font())
	vb.add_child(rec_head)
	vb.add_child(_mh_gold_rule(cw - 78))
 
	var t1 = _mh_record_row("修炼时长"); vb.add_child(t1[0]); mh_r_time = t1[1]
	var t2 = _mh_record_row("事件");     vb.add_child(t2[0]); mh_r_events = t2[1]
	var t3 = _mh_record_row("突破");     vb.add_child(t3[0]); mh_r_break = t3[1]
	var t4 = _mh_record_row("死亡");     vb.add_child(t4[0]); mh_r_death = t4[1]
	var t5 = _mh_record_row("奇遇");     vb.add_child(t5[0]); mh_r_encounter = t5[1]

 
# ── 底部修为条 ──
func _mh_build_cultivation_bar() -> void:
	var y := GameConfig.MH_FRAME_SIZE.y - 130.0
	var lab := _mh_label("修为", GameConfig.MH_FS_SECTION, GameConfig.MH_INK)
	if GameConfig.brush_font() != null:
		lab.add_theme_font_override("font", GameConfig.brush_font())
	lab.position = Vector2(200, y)
	mh_root.add_child(lab)
 
	mh_cult_bar = ProgressBar.new()
	mh_cult_bar.min_value = 0
	mh_cult_bar.show_percentage = false
	mh_cult_bar.position = Vector2(300, y + 6)
	mh_cult_bar.size = Vector2(640, 30)
	mh_cult_bar.custom_minimum_size = Vector2(640, 30)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.86, 0.83, 0.74)   # 中性米灰底，配任意 fill 都好看
	bg.set_corner_radius_all(15)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.42, 0.62, 0.58)   # A 青碧玉（推荐）
	fill.set_corner_radius_all(15)
	mh_cult_bar.add_theme_stylebox_override("background", bg)
	mh_cult_bar.add_theme_stylebox_override("fill", fill)
	mh_root.add_child(mh_cult_bar)
 
	mh_cult_pct = _mh_label("", GameConfig.MH_FS_LABEL, GameConfig.MH_INK)
	mh_cult_pct.position = Vector2(300, y + 6)
	mh_cult_pct.size = Vector2(640, 30)
	mh_cult_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mh_cult_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mh_root.add_child(mh_cult_pct)
 
	mh_cult_nums = _mh_label("", GameConfig.MH_FS_CULT, GameConfig.MH_INK)
	mh_cult_nums.position = Vector2(300, y + 44)
	mh_cult_nums.size = Vector2(640, 44)
	mh_cult_nums.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mh_root.add_child(mh_cult_nums)
 
func _mh_gold_rule(w: float) -> Control:
	var line := ColorRect.new()
	line.color = Color(GameConfig.MH_GOLD.r, GameConfig.MH_GOLD.g, GameConfig.MH_GOLD.b, 0.55)
	line.custom_minimum_size = Vector2(w, 2)
	return line
 
func _mh_update_logo(logo: TextureRect) -> void:
	var path := "res://assets/ui/chinese_logo.png" if current_language == "zh" else "res://assets/ui/english_logo.png"
	var tex := _mh_tex(path)
	if tex == null:
		return
	logo.texture = tex
	var lw := float(tex.get_width())
	var lh := float(tex.get_height())
	logo.size = Vector2(lw, lh)
	logo.position = Vector2((GameConfig.MH_FRAME_SIZE.x - lw) / 2.0, 70.0)
 
# ══════════════════════════════════════════
#  OPEN / CLOSE
# ══════════════════════════════════════════
 
func _open_main_hall() -> void:
	_mark_interaction()
	if _is_cutscene_blocking():
		return
	if shop_panel != null: shop_panel.visible = false
	if report_panel != null: report_panel.visible = false
	if profile_panel != null: profile_panel.visible = false

	var safe_pos := _get_safe_window_position(GameConfig.WIN_MAIN)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = GameConfig.WIN_MAIN
	await get_tree().process_frame

	main_hall_panel.visible = true
	_hide_bubble()

	# 角色状态（位置/缩放由 _on_window_resized 统一算，这里只设不依赖尺寸的）
	pet_group.z_index = 60
	pet_group.scale = Vector2(1.5, 1.5)
	var inv := 1.0 / 1.5
	if bubble_panel != null:
		bubble_panel.position = Vector2(-110 * inv, 120)
		bubble_panel.scale = Vector2(inv, inv)
	if bubble_tail != null:
		bubble_tail.position = Vector2(-30 * inv, 112)
		bubble_tail.scale = Vector2(inv, inv)
		bubble_tail.rotation = PI
	$PetGroup/VBox.visible = false
	if status_label != null:
		status_label.visible = true
		status_label.z_index = 61

	_on_window_resized()    # 统一算 mh_root 缩放/位置 + 角色/status 位置
	_refresh_main_hall()
	_refresh_main_hall_live()
 
## restore_window=false：只关大厅、不改窗口尺寸。
## 从大厅跳到另一个大面板（成就/日报）时用，否则会先缩到 WIN_NORMAL 再撑回去，
## 中间那一下就是肉眼看到的「变小」。
func _close_main_hall(restore_window: bool = true) -> void:
	main_hall_panel.visible = false
	pet_group.z_index = 0
	pet_group.scale = Vector2.ONE
	# 还原气泡
	if bubble_panel != null:
		bubble_panel.position = _bubble_home_pos
		bubble_panel.scale = Vector2.ONE
	if bubble_tail != null:
		bubble_tail.position = _bubble_tail_home_pos
		bubble_tail.scale = Vector2.ONE
		bubble_tail.rotation = 0.0
	# status 还原（大厅里改过它的 position / z_index）
	if status_label != null:
		status_label.z_index = 0
	# 状态一 = 零 UI：旧按钮栏保持隐藏（入口在悬停快捷条）
	if restore_window:
		get_window().size = GameConfig.WIN_NORMAL
	await get_tree().process_frame
	update_layout()               # 这一步应该重算角色位置
	_reposition_overlay_panels()
 
func _on_window_resized() -> void:
	# 窗口尺寸一变，右键菜单原来的位置就没意义了，直接收掉
	if context_menu != null and context_menu.visible:
		context_menu.hide()

	var win: Vector2 = get_viewport_rect().size

	# 每个面板按「自己的设计尺寸」算缩放。
	# 原来三个面板共用一个 s（用主殿的 MH_FRAME_SIZE 算出来的），
	# 但 report_ui.DESIGN / achievement_ui.DESIGN 跟主殿不一样大，
	# 于是打开成就时会按主殿的比例缩，看起来就是「一按成就 tab 就变小」。
	var s: float = _fit_scale(win, GameConfig.MH_FRAME_SIZE)
	if main_hall_panel != null and main_hall_panel.visible:
		mh_root.scale = Vector2(s, s)
		mh_root.position = (win - GameConfig.MH_FRAME_SIZE * s) / 2.0
		pet_group.position = Vector2(win.x / 2.0, win.y * GameConfig.MH_PET_Y_RATIO)
		if status_label != null:
			status_label.position = Vector2(win.x / 2.0, win.y * GameConfig.MH_PET_Y_RATIO + 90.0 * pet_group.scale.y)

	# 日报面板同理，归 report_ui._layout() 管。

	# 成就面板不在这里算 —— achievement_ui 自己连了 window.size_changed，
	# 两边同时改 root.scale 会互相打架，这就是「一按成就 tab 就变小」的直接原因。
	# 它的布局归 achievement_ui._layout() 管。


## 把 design 尺寸等比塞进 win，最大不放大超过 1:1（面板放大会糊）
func _fit_scale(win: Vector2, design: Vector2) -> float:
	if design.x <= 0.0 or design.y <= 0.0:
		return 1.0
	return minf(minf(win.x / design.x, win.y / design.y), 1.0)
	
# ══════════════════════════════════════════
#  REFRESH
# ══════════════════════════════════════════
 
func _refresh_main_hall() -> void:
	if main_hall_panel == null or not main_hall_panel.visible:
		return
	# 语言切换后换标题图
	var logo := mh_root.get_node_or_null("MHLogo")
	if logo != null:
		_mh_update_logo(logo)
 
	var zh := current_language == "zh"
	mh_name_label.text = String(state.get("pet_name", "小白"))
 
	# 天道评价 = 当前轮回天赋的描述
	var verdict := String(active_reincarnation_perk.get("desc_zh" if zh else "desc_en", ""))
	if verdict == "":
		verdict = "此生尚未盖棺。" if zh else "This life is not yet written."
	mh_verdict_label.text = verdict
 
func _refresh_main_hall_live() -> void:
	if main_hall_panel == null or not main_hall_panel.visible:
		return
	# 大厅内不显示对话气泡（兜底压制）
	if bubble_panel != null and bubble_panel.visible:
		bubble_panel.visible = false
		bubble_tail.visible = false
	var zh := current_language == "zh"
	var realm: Dictionary = realms[state["realm_index"]]
 
	# 基本信息
	mh_v_realm.text = realm["name"] if zh else realm_names_en[state["realm_index"]]
	mh_v_personality.text = GameConfig.PERSONALITY_META.get(current_personality, {}).get("zh" if zh else "en", "未知")
	var job := String(state.get("mortal_job", ""))
	mh_v_job.text = _mortal_job_label(job, zh) if job != "" else ("无" if zh else "None")
	mh_v_luck.text = ("%s（%d）" % [luck_tier(), int(state["luck"])]) if zh \
		else ("%s (%d)" % [luck_tier_en(), int(state["luck"])])
	mh_v_lifespan.text = ("%d年" % int(state["lifespan"])) if zh else ("%d yrs" % int(state["lifespan"]))
	mh_v_life.text = ("%d 世" % int(state.get("life_count", 1))) if zh else ("Life %d" % int(state.get("life_count", 1)))
	mh_v_perk.text = String(active_reincarnation_perk.get("zh" if zh else "en", "平平无奇" if zh else "Ordinary"))
	mh_v_stones.text = str(int(state["spirit_stones"]))
 
	# 本世记录
	var s := _mh_session_seconds
	mh_r_time.text = "%02d:%02d" % [s / 3600, (s % 3600) / 60]
	mh_r_events.text = str(recent_events.size())
	mh_r_break.text = str(int(state.get("life_breakthrough_success", 0)))
	mh_r_death.text = str(death_history.size())
	mh_r_encounter.text = str(int(state.get("life_rare_count", 0)) + int(state.get("life_legendary_count", 0)))
	var off_h := int(round(_mh_offline_seconds / 3600.0))
	mh_r_companion.text = ("%d小时" % off_h) if zh else ("%dh" % off_h)
 
	# 修为条
	var need := float(realm["need"])
	var cur := float(state["cultivation"])
	mh_cult_bar.max_value = need
	mh_cult_bar.value = cur
	var pct := (cur / need * 100.0) if need > 0 else 0.0
	mh_cult_pct.text = "%.2f%%" % pct
	mh_cult_nums.text = "%d / %d" % [int(cur), int(need)]

var achievement_ui := AchievementUi.new()          # 声明区
var cave_ui := CaveUi.new()
