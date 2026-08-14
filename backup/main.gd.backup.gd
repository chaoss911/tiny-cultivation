extends Control

const SAVE_PATH := "user://desktop_cultivator_save.json"
const TICK_SECONDS := 1.0
const OFFLINE_CAP_SECONDS := 12 * 60 * 60
var _quitting := false
const FAREWELL_LINES := [
	{"zh": "这就走了？那我继续闭关了。", "en": "Leaving already? Back to seclusion, then."},
	{"zh": "明天见。说不定明天我就突破了。", "en": "See you tomorrow. I might just break through."},
	{"zh": "走了也别忘了我还在修炼。", "en": "Don't forget — I'll still be cultivating."},
	{"zh": "去吧去吧，凡人的事也很重要。", "en": "Go on. Mortal business matters too."},
	{"zh": "我会想你的……才怪。", "en": "I'll miss you... as if."},
]
# DEMO
const DEMO_MODE := true                # 正式版改 false
const DEMO_CULT_MULT := 100.0            # 修炼倍率：2.0≈挂一天通关
const DEMO_BREAKTHROUGH_BONUS := 0.08  # 突破成功率小幅加成，减小卡关
const DEMO_FORCED_DEATHS := 2          # 前 2 世强制结束，稳定展示死亡+证书
const DEMO_DEATH_AT_REALM := 3         # 触发境界（3 = 武者初期）
const DECISION_INDICATOR_POS := Vector2(24.0, -168.0)   # 相对角色中心，头顶右上
var memorable_events: Array = []        # this life's highlights reel, cleared on reincarnation
const MEMORABLE_EVENTS_CAP := 8
var _foreshadow_flags: Dictionary = {}  # tag -> {"day_set": int, "expires_day": int}, cleared on reincarnation
var _pending_decision: Dictionary = {}
var decision_indicator: Button
var decision_bubble: PanelContainer
var _indicator_tween: Tween
const LIFE_CHAPTERS := [
	{"id": "childhood",   "zh": "童年",   "en": "Childhood",
	 "min_realm_index": 0, "max_realm_index": 0, "max_age": 20},
	{"id": "youth",       "zh": "少年",   "en": "Youth",
	 "min_realm_index": 0, "max_realm_index": 2, "min_age": 20},
	{"id": "warrior",     "zh": "武者",   "en": "Warrior",
	 "min_realm_index": 3, "max_realm_index": 4},
	{"id": "innate",      "zh": "先天",   "en": "Innate",
	 "min_realm_index": 5, "max_realm_index": 6},
	{"id": "qi_refining", "zh": "炼气",   "en": "Qi Refining",
	 "min_realm_index": 7, "max_realm_index": 7},
]

const HEADLINE_TEMPLATES := {
	"breakthrough_success": {"zh": "震惊！本村修士突破成功！", "en": "Shocking! Local Cultivator Breaks Through!"},
	"breakthrough_fail":    {"zh": "丹田再次表示不服。", "en": "Dantian Refuses to Cooperate, Again."},
	"death": {"zh": "讣告？不，是喜报！新的一世已经开始。", "en": "An Obituary? No — Good News! A New Life Has Already Begun."},
	"legendary_encounter":  {"zh": "今日奇遇登上头条！", "en": "Today's Encounter Makes Front Page!"},
	"found_stone":          {"zh": "灵石虽小，喜悦不小。", "en": "Small Stone, Big Smile."},
	"furnace_explosion":    {"zh": "丹炉again不幸殉职。", "en": "Another Furnace Lost in the Line of Duty."},
	"none":                 {"zh": "今日，什么都没发生。", "en": "Today, Absolutely Nothing Happened."}
}
const DAILY_HIGHLIGHT_PRIORITY := [
	"death", "breakthrough_success", "legendary_encounter", "breakthrough_fail",
	"rare_encounter", "furnace_explosion", "found_stone"
]

func _todays_highlight_tag() -> String:
	for tag in DAILY_HIGHLIGHT_PRIORITY:
		if _today_event_tags.has(tag):
			return tag
	return "none"

func _todays_memorable_highlight() -> Dictionary:
	for mem in memorable_events:
		if int(mem.get("age", -1)) == _current_age():   # set today, age hasn't moved since
			return mem
	return {}

# ── Layout tuning ──
const SPRITE_SCALE    := 2.0
const SPRITE_Y        := -13.0
const VBOX_Y          := 120.0
const VBOX_SCALE      := 1
const PETGROUP_Y      := 133.0
const BUBBLE_ANCHOR_Y := -150.0
const BUBBLE_GAP      := 8.0
const BUBBLE_MIN_W    := 150.0
const BUBBLE_FONT     := 14
const REALM_STRIP_Y := 95
const STATUS_LABEL_Y    := -173.0 
const SHOP_Y          := 100.0
const STATUS_Y_ABOVE  := -120.0
const REPORT_Y        := 12.0
const STATUS_MIN_SEC  := 20.0
const STATUS_MAX_SEC  := 60.0
const TOAST_MARGIN := 30.0
const TOAST_W      := 220.0
const TOAST_SECS   := 5.0
const PROFILE_HEADER_SIZE := 15   # 分区标题：轮回记录/成就/人生履历/奇遇图鉴
const PROFILE_BODY_SIZE   := 13   # 正文内容：境界详情/记录条目/提示文字
const BREAKTHROUGH_INSIGHT_PER_FAIL := 10   # 每次突破失败感悟+10（原20，保底拉长到10次失败）
const BREAKTHROUGH_INSIGHT_CAP := 100       # 感悟达到上限即保底必中
const LIFE_CARD_BG := Color(0.96, 0.92, 0.82, 0.97)
const LIFE_CARD_BORDER := Color(0.62, 0.52, 0.34, 0.7)
const LIFE_CARD_BORDER_INNER := Color(0.72, 0.62, 0.40, 0.5)
const LIFE_SECTION_GAP := 16.0
const LIFE_CARD_PADDING := 14
const LIFE_LABEL_WIDTH := 56.0
const LIFE_ICON_SIZE := 18.0
const LIFE_INK_COLOR := Color(0.28, 0.20, 0.12)
const LIFE_GOLD_COLOR := Color(0.55, 0.42, 0.18)
const LIFE_QUOTE_BORDER := Color(0.50, 0.46, 0.40, 0.6)
const TRAIL_NODE_BG := Color(0.94, 0.90, 0.80)
const TRAIL_NODE_BORDER := Color(0.55, 0.42, 0.18)
const TRAIL_LINE_COLOR := Color(0.62, 0.52, 0.34, 0.5)
const LIFE_FIELD_ICONS := {
	"realm": "res://assets/ui/icon_realm.png",
	"personality": "res://assets/ui/icon_personality.png",
	"job": "res://assets/ui/icon_job.png",
	"root": "res://assets/ui/icon_root.png",
	"luck": "res://assets/ui/icon_luck.png",
	"lifespan": "res://assets/ui/icon_lifespan.png",
	"life_count": "res://assets/ui/icon_lifecount.png",
	"perk": "res://assets/ui/icon_perk.png",
}
func _build_icon_label_value_row(icon_key: String, label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(LIFE_ICON_SIZE, LIFE_ICON_SIZE)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path: String = LIFE_FIELD_ICONS.get(icon_key, "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	row.add_child(icon_rect)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LIFE_LABEL_WIDTH, 0)
	label.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
	label.add_theme_color_override("font_color", LIFE_INK_COLOR)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
	value.add_theme_color_override("font_color", LIFE_INK_COLOR)
	row.add_child(value)

	return row
	
var last_autosave_time := 0.0
const AUTOSAVE_INTERVAL := 15.0
const REALM_STRIP_OFFSET_Y := -24.0
const TIER_ORDER := ["凡人", "武者", "先天", "炼气"]
const TIER_ANIM_SUFFIX := {
	"凡人": "fanren",
	"武者": "wuzhe",
	"先天": "xiantian",
	"炼气": "lianqi"
}

var _last_death_punchline: Dictionary = {"zh": "", "en": ""}
var death_cause_first_punchline: Dictionary = {}

const TIER_ACTION_FPS := {
	"breath": 6, "sleeping": 5, "walking": 10, "lazy": 6, "workout": 8,
	"meditate": 5,
	"happy": 10, "confused": 8, "angry": 10, "stomachache": 8,
	"eat": 10, "luck": 10, "dunwu": 8, "legendary": 10,
	"breakthrough_success": 12, "breakthrough_fail": 12, "thunder": 12,
	"death_old": 7, "death_explosion": 12, "death_tribulation": 10,

# ── 随机事件特殊动画 (special_animation) ──
	"sword_fly": 12, "sword_fly_fail": 10,
	"root_awaken": 8, "thunder_hit": 12,
	"alchemy_boom": 12, "pill_backfire": 10,
	"stone_found": 10,
	"beast_encounter": 8, "chase_butterfly": 10,
	"aura_burst": 10, "ascend_small": 12,
	"trip_fail": 10,
	"stretch_lazy": 6,
}

# ══════════════════════════════════════════
#  PERSONALITY SYSTEM
# ══════════════════════════════════════════

const PERSONALITY_TRAITS := ["reckless", "cautious", "greedy", "lazy", "diligent", "eccentric"]

const PERSONALITY_META := {
	"reckless": {"zh": "莽撞", "en": "Reckless"},
	"cautious": {"zh": "谨慎", "en": "Cautious"},
	"greedy":   {"zh": "贪婪", "en": "Greedy"},
	"lazy":     {"zh": "摆烂", "en": "Lazy"},
	"diligent": {"zh": "勤勉", "en": "Diligent"},
	"eccentric":{"zh": "古怪", "en": "Eccentric"}
}

# The bias vector. Every system below reads from this, keyed by current_personality.
# Values are multipliers (1.0 = neutral) or direct overrides — see per-system notes.
const PERSONALITY_BIAS := {
	"reckless": {
		"fight_weight_mult": 2.0, "flee_weight_mult": 0.4,
		"alchemy_attempt_mult": 1.6, "breakthrough_eagerness": 1.5,
		"death_risk_mult": 1.3, "explore_weight_mult": 1.5
	},
	"cautious": {
		"fight_weight_mult": 0.4, "flee_weight_mult": 2.2,
		"alchemy_attempt_mult": 0.5, "breakthrough_eagerness": 0.6,
		"death_risk_mult": 0.7, "explore_weight_mult": 0.7
	},
	"greedy": {
		"stone_event_weight_mult": 1.8, "pill_buy_mult": 1.4,
		"breakthrough_eagerness": 0.7, "death_risk_mult": 1.0,
		"explore_weight_mult": 1.3
	},
	"lazy": {
		"status_lazy_weight_mult": 2.5, "breakthrough_eagerness": 0.5,
		"failure_penalty_mult": 0.8, "explore_weight_mult": 0.5,
		"daily_qi_mult": 0.85
	},
	"diligent": {
		"status_workout_weight_mult": 2.0, "breakthrough_eagerness": 1.8,
		"daily_qi_mult": 1.15, "explore_weight_mult": 1.1
	},
	"eccentric": {
		"variance_mult": 1.8, "encounter_luck_bonus": 0.08,
		"breakthrough_eagerness": 1.0, "explore_weight_mult": 1.4
	}
}

const PERSONALITY_JOB_WEIGHT := {
	"reckless":  {"hunter": 2.0, "blacksmith": 1.5},
	"cautious":  {"scholar": 2.0, "farmer": 1.5},
	"greedy":    {"merchant": 2.5},
	"lazy":      {"unemployed": 2.5},
	"diligent":  {"farmer": 1.5, "blacksmith": 1.5, "scholar": 1.3},
	"eccentric": {}  # no bias — eccentric is genuinely random, that's the point
}

const PERSONALITY_DRIFT_THRESHOLD := 5.0

var current_personality := "lazy"
var _personality_drift: Dictionary = {}  # trait_name -> accumulated pressure, reset on reincarnation
# NARRATIVE ONLY — never wire this into any chance/multiplier calculation.
# This is a text-selection bias for Dialogue/Status, not a stat.
var _instinct_tag: String = ""

func _personality_bias(key: String, default_val: float = 1.0) -> float:
	var traits: Dictionary = PERSONALITY_BIAS.get(current_personality, {})
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
	var bias: Dictionary = PERSONALITY_JOB_WEIGHT.get(current_personality, {})
	var weights: Array[float] = []
	var total := 0.0

	for job in MORTAL_JOBS:
		var weight := maxf(0.0, float(bias.get(job["id"], 1.0)))
		weights.append(weight)
		total += weight

	if total <= 0.0:
		return MORTAL_JOBS.pick_random()

	var roll := randf() * total
	var accumulated := 0.0
	for i in MORTAL_JOBS.size():
		accumulated += weights[i]
		if roll < accumulated:
			return MORTAL_JOBS[i]

	return MORTAL_JOBS.back()

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
	if not PERSONALITY_TRAITS.has(target_trait) or target_trait == current_personality:
		return
	_personality_drift[target_trait] = float(_personality_drift.get(target_trait, 0.0)) + amount
	if _personality_drift[target_trait] >= PERSONALITY_DRIFT_THRESHOLD:
		var old := current_personality
		current_personality = target_trait
		_personality_drift.clear()
		add_life_history(
			"skill",
			"性情转变",
			"从「%s」渐渐变成了「%s」。" % [PERSONALITY_META[old]["zh"], PERSONALITY_META[target_trait]["zh"]],
			"Personality Shift",
			"Gradually shifted from %s to %s." % [PERSONALITY_META[old]["en"], PERSONALITY_META[target_trait]["en"]]
		)

const TIER_NON_LOOPING := [
	"breakthrough_success", "breakthrough_fail", "thunder",
	"death_old", "death_explosion", "death_tribulation",

	# ── 随机事件特殊动画，全部播一次定格/收尾，不循环 ──
	"sword_fly", "sword_fly_fail",
	"root_awaken", "thunder_hit",
	"alchemy_boom", "pill_backfire",
	"stone_found",
	"beast_encounter", "chase_butterfly",
	"aura_burst", "ascend_small",
	"trip_fail",
	"stretch_lazy",
]
const TIER_GRID_OVERRIDE := {
	# "某动作名": {"cols": 8, "rows": 1, "frames": 8},
}

func _tier_at_least(target: String) -> bool:
	var current_idx: int = TIER_ORDER.find(current_tier())
	var target_idx: int = TIER_ORDER.find(target)
	return current_idx >= target_idx
	
const LIFESPAN_BONUS_PER_REALM := {
	0: 0,     # 引气一层 — starting realm, no bonus
	1: 10,    # 引气二层
	2: 15,    # 引气三层
	3: 60,    # 武者初期
	4: 80,    # 武者中期
	5: 250,   # 先天初期
	6: 350,   # 先天大成
	7: 800,   # 炼气一层
}

var profile_tabs: TabContainer
var tab_life: VBoxContainer
var tab_bio: VBoxContainer
var tab_collection: VBoxContainer
var tab_history: VBoxContainer
var reincarnation_history: Array = []          # 完整轮回总结，最多存 100 世
var active_reincarnation_perk: Dictionary = {}  # 当前世天赋
var reincarnation_modifiers: Dictionary = {}    # 天赋换算出的数值修正（不存档，读档时重算）
const FEED_COOLDOWN_SECONDS := 60.0
var last_feed_time := -999999.0   # uses Time.get_ticks_msec() / 1000.0, not saved across sessions
var life_flags: Dictionary = {}            # flag_name -> true，转世清空
var _scheduled_chain_unlocks: Array = []   # [{"id":String,"unlock_day":int}]
var _day_counter: int = 0                  # 累计天数，用于 cooldown_days
var _achievement_unlocked_today: Dictionary = {}  # title_zh -> true, cleared at rollover

const WIN_NORMAL := Vector2i(280, 360)
const WIN_WIDE   := Vector2i(640, 420)
const REPORT_MARGIN := 12.0
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
var report_panel: PanelContainer
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

const POKE_STREAK_RESET_SEC := 1.2
const POKE_ANGRY_STREAK := 8

# ── 人生履历（分类美化系统）──
# 每条 entry: {life, age, realm, category, title, description, time}
var life_history: Array = []
const LIFE_HISTORY_MAX_PER_CATEGORY := 8   # 每个分类最多显示几条（旧的折叠成“……还有 N 条”）
const LIFE_HISTORY_STORE_CAP := 300        # 存档里最多保留多少条，防止无限膨胀

const LIFE_HISTORY_CATEGORY_ORDER := [
	"birth", "martial", "encounter", "skill",
	"breakthrough", "alchemy", "achievement", "death"
]

const LIFE_HISTORY_CATEGORY_META := {
	"birth":        {"icon": "👶", "title_zh": "出生", "title_en": "Birth",        "color": "a8e6cf"},
	"martial":      {"icon": "⚔️", "title_zh": "武者", "title_en": "Martial",      "color": "ffd166"},
	"encounter":    {"icon": "✨", "title_zh": "奇遇", "title_en": "Encounter",    "color": "cdb4db"},
	"skill":        {"icon": "📖", "title_zh": "功法", "title_en": "Skills",       "color": "90dbf4"},
	"breakthrough": {"icon": "⬆️", "title_zh": "突破", "title_en": "Breakthrough", "color": "bde0fe"},
	"alchemy":      {"icon": "🧪", "title_zh": "炼丹", "title_en": "Alchemy",      "color": "ffc8dd"},
	"achievement":  {"icon": "🏆", "title_zh": "成就", "title_en": "Achievement",  "color": "f6d860"},
	"death":        {"icon": "☠️", "title_zh": "死亡", "title_en": "Death",        "color": "ffadad"}
}

const AFK_THRESHOLD_SECONDS := 600.0   # 10 minutes
var last_interaction_time := 0.0
var is_afk := false


var flavor_dialogues := [
	{"zh": "今天决定开始努力。", "en": "Decided to work hard today."},
	{"zh": "结果努力了五分钟。", "en": "...lasted five minutes."},
	{"zh": "二狗又领先我了。",   "en": "Ergou is ahead of me again."},
]

const SPIRITUAL_ROOTS := {
	"common": [
		{"zh": "金灵根", "en": "Metal Root"},
		{"zh": "木灵根", "en": "Wood Root"},
		{"zh": "水灵根", "en": "Water Root"},
		{"zh": "火灵根", "en": "Fire Root"},
		{"zh": "土灵根", "en": "Earth Root"}
	],
	"rare": [
		{"zh": "雷灵根", "en": "Thunder Root"},
		{"zh": "冰灵根", "en": "Ice Root"},
		{"zh": "风灵根", "en": "Wind Root"}
	],
	"legendary": [
		{"zh": "天灵根", "en": "Heavenly Root"}
	]
}
const ROOT_MULTIPLIERS := {
	"common": 1.00, "rare": 1.15, "legendary": 1.30
}

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

const MORTAL_JOBS := [
	{"id": "farmer",     "zh": "农夫",     "en": "Farmer"},
	{"id": "hunter",     "zh": "猎户",     "en": "Hunter"},
	{"id": "scholar",    "zh": "书生",     "en": "Scholar"},
	{"id": "merchant",   "zh": "商人",     "en": "Merchant"},
	{"id": "blacksmith", "zh": "铁匠",     "en": "Blacksmith"},
	{"id": "unemployed", "zh": "无业游民", "en": "Unemployed"}
]
const TIER_TRANSITION_ANIMS := {
	"fanren_breakthrough_wuzhe": 12,
	"wuzhe_breakthrough_xiantian": 12,
}

func _add_transition_animations(sf: SpriteFrames) -> void:
	for anim_name in TIER_TRANSITION_ANIMS:
		if sf.has_animation(anim_name):
			continue
		var from_suffix: String = anim_name.split("_breakthrough_")[0]
		var sheet_path := "res://assets/sprites/%s/%s.png" % [from_suffix, anim_name]
		if not ResourceLoader.exists(sheet_path):
			continue
		var tex: Texture2D = load(sheet_path)
		if tex == null:
			continue

		var cols := 5
		var rows := 4
		var total_frames := 16
		var fw := int(tex.get_width() / float(cols))
		var fh := int(tex.get_height() / float(rows))

		sf.add_animation(anim_name)
		sf.set_animation_loop(anim_name, false)   # 过渡动画永远不循环，播完定格在新形象上
		sf.set_animation_speed(anim_name, float(TIER_TRANSITION_ANIMS[anim_name]))

		var frame_count := 0
		for r in rows:
			for c in cols:
				if frame_count >= total_frames:
					break
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(c * fw, r * fh, fw, fh)
				sf.add_frame(anim_name, atlas)
				frame_count += 1


func _mortal_job_label(job_id: String, zh: bool) -> String:
	for j in MORTAL_JOBS:
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

func _build_animations() -> void:
	var sheets := {
		"breath":    {"path": "res://images/breath_sheet.png",    "cols": 5, "rows": 4, "frames": 16},
		"sleeping":  {"path": "res://images/sleeping_sheet.png",  "cols": 5, "rows": 4, "frames": 16},
		"happy":     {"path": "res://images/happy_sheet.png",     "cols": 5, "rows": 4, "frames": 16},
		"confused":  {"path": "res://images/confused_sheet.png",  "cols": 5, "rows": 4, "frames": 16},
		"meditate":  {"path": "res://images/meditate_sheet.png",  "cols": 5, "rows": 4, "frames": 16},
		"workout":   {"path": "res://images/workout_sheet.png",   "cols": 5, "rows": 4, "frames": 16},
		"lazy":      {"path": "res://images/lazy_sheet.png",      "cols": 5, "rows": 4, "frames": 16},
		# ── 死亡动画（不循环）──
		"death_old":         {"path": "res://images/death_old_sheet.png",         "cols": 5, "rows": 4, "frames": 16},
		"death_explosion":   {"path": "res://images/death_explosion_sheet.png",   "cols": 5, "rows": 4, "frames": 16},
		"death_tribulation": {"path": "res://images/death_tribulation_sheet.png", "cols": 5, "rows": 4, "frames": 16},
	}
	# 这几个动画只播一次、定格最后一帧
	var non_looping := ["death_old", "death_explosion", "death_tribulation"]
 
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in sheets:
		var info = sheets[anim_name]
		var tex: Texture2D = load(info["path"])
		if tex == null:
			print("Missing sprite sheet: ", info["path"])
			continue
		var cols: int = info["cols"]
		var rows: int = info["rows"]
		var total_frames: int = info["frames"]
		var fw := int(tex.get_width() / float(cols))
		var fh := int(tex.get_height() / float(rows))
		sf.add_animation(anim_name)
		sf.set_animation_loop(anim_name, not (anim_name in non_looping))   # ← 死亡动画不循环
		sf.set_animation_speed(anim_name, 7.7)
		var frame_count := 0
		for r in rows:
			for c in cols:
				if frame_count >= total_frames:
					break
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(c * fw, r * fh, fw, fh)
				sf.add_frame(anim_name, atlas)
				frame_count += 1
	_add_tier_animations(sf)
	_add_transition_animations(sf) 
	cultivator_sprite.sprite_frames = sf
	if sf.has_animation("breath"):
		set_mood("normal")

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

func _add_tier_animations(sf: SpriteFrames) -> void:
	var added := 0
	for tier in TIER_ANIM_SUFFIX:
		var suffix: String = TIER_ANIM_SUFFIX[tier]
		if suffix == "":
			continue
		var dir := "res://assets/sprites/%s/" % suffix
		for action in TIER_ACTION_FPS:
			var sheet_path := "%s%s_%s.png" % [dir, suffix, action]
			if not ResourceLoader.exists(sheet_path):
				print("[境界动画] 没找到: ", sheet_path)
				continue

			var tex: Texture2D = load(sheet_path)
			if tex == null:
				print("[境界动画] 加载失败: ", sheet_path)
				continue
			
			var grid: Dictionary = TIER_GRID_OVERRIDE.get(action, {"cols": 5, "rows": 4, "frames": 16})
			var cols: int = grid["cols"]
			var rows: int = grid["rows"]
			var total_frames: int = grid["frames"]
			var fw := int(tex.get_width() / float(cols))
			var fh := int(tex.get_height() / float(rows))

			var anim_name := "%s_%s" % [suffix, action]
			if sf.has_animation(anim_name):
				continue   # 避免重复添加（比如热重载时）

			sf.add_animation(anim_name)
			added += 1
			sf.set_animation_loop(anim_name, not (action in TIER_NON_LOOPING))
			sf.set_animation_speed(anim_name, float(TIER_ACTION_FPS[action]))

			var frame_count := 0
			for r in rows:
				for c in cols:
					if frame_count >= total_frames:
						break
					var atlas := AtlasTexture.new()
					atlas.atlas = tex
					atlas.region = Rect2(c * fw, r * fh, fw, fh)
					sf.add_frame(anim_name, atlas)
					frame_count += 1
	print("[境界动画] 一共加载了 ", added, " 个")


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
	bubble_panel.custom_minimum_size = Vector2(BUBBLE_MIN_W, 0)
	bubble_panel.position = Vector2(-110, -148)
	bubble_panel.visible  = false
	pet_group.add_child(bubble_panel)

	bubble_label = RichTextLabel.new()
	bubble_label.bbcode_enabled  = true
	bubble_label.fit_content     = true
	bubble_label.autowrap_mode   = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.custom_minimum_size = Vector2(BUBBLE_MIN_W, 0)
	bubble_label.add_theme_font_size_override("normal_font_size", BUBBLE_FONT)
	bubble_label.add_theme_color_override("default_color", Color(0.12, 0.12, 0.12))
	bubble_panel.add_child(bubble_label)
	
func _build_shop() -> void:
	shop_panel = PanelContainer.new()
	shop_panel.name = "ShopPanel"
	shop_panel.add_theme_stylebox_override(
		"panel", make_panel_stylebox(Color(0.96, 0.94, 0.88, 0.97), 10))
	shop_panel.custom_minimum_size = Vector2(220, 0)
	shop_panel.visible = false
	pet_group.add_child(shop_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(220, 240)
	shop_panel.add_child(scroll)
	shop_list = VBoxContainer.new()
	shop_list.add_theme_constant_override("separation", 4)
	scroll.add_child(shop_list)


func _build_report_panel() -> void:
	report_panel = PanelContainer.new()
	report_panel.name = "ReportPanel"
	report_panel.add_theme_stylebox_override(
		"panel", make_panel_stylebox(Color(0.97, 0.95, 0.90, 0.97), 10))
	report_panel.custom_minimum_size = Vector2(290, 0)
	report_panel.visible = false
	add_child(report_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(290, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_panel.add_child(scroll)
	report_list = VBoxContainer.new()
	report_list.add_theme_constant_override("separation", 8)
	scroll.add_child(report_list)

func _build_profile_panel() -> void:
	profile_panel = PanelContainer.new()
	profile_panel.name = "ProfilePanel"
	profile_panel.add_theme_stylebox_override(
		"panel", make_panel_stylebox(Color(0.95, 0.93, 0.97, 0.97), 10))
	profile_panel.custom_minimum_size = Vector2(300, 0)
	profile_panel.visible = false
	add_child(profile_panel)

	var outer_vb := VBoxContainer.new()
	outer_vb.add_theme_constant_override("separation", 0)
	profile_panel.add_child(outer_vb)  # ← outer_vb 加到 profile_panel

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

	profile_tabs = TabContainer.new()  # ← 先创建
	profile_tabs.custom_minimum_size = Vector2(300, 364)
	outer_vb.add_child(profile_tabs)   # ← 再加到 outer_vb

	profile_tabs.add_theme_stylebox_override(
		"panel", make_panel_stylebox(Color(0.95, 0.93, 0.97, 0.98), 8))
	profile_tabs.add_theme_stylebox_override(
		"tab_selected", make_panel_stylebox(Color(0.90, 0.87, 0.95, 0.98), 6))
	profile_tabs.add_theme_stylebox_override(
		"tab_unselected", make_panel_stylebox(Color(0.82, 0.80, 0.86, 0.95), 6))
	profile_tabs.add_theme_color_override("font_selected_color", Color(0.2, 0.15, 0.1))
	profile_tabs.add_theme_color_override("font_unselected_color", Color(0.4, 0.36, 0.42))

	tab_life       = _make_profile_tab()
	tab_bio        = _make_profile_tab()
	tab_collection = _make_profile_tab()
	tab_history    = _make_profile_tab()
	_apply_profile_tab_titles()

	profile_list = tab_life

func _make_profile_tab() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	profile_tabs.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	return vb

func _apply_profile_tab_titles() -> void:
	if profile_tabs == null:
		return
	if current_language == "zh":
		profile_tabs.set_tab_title(0, "现在的人生")
		profile_tabs.set_tab_title(1, "人生履历")
		profile_tabs.set_tab_title(2, "成就 & 图鉴")
		profile_tabs.set_tab_title(3, "历史记录")
	else:
		profile_tabs.set_tab_title(0, "Current Life")
		profile_tabs.set_tab_title(1, "Biography")
		profile_tabs.set_tab_title(2, "Achv & Codex")
		profile_tabs.set_tab_title(3, "History")

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
		request_mood("normal", MoodPriority.AMBIENT)

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.name = "ToastPanel"
	toast_panel.add_theme_stylebox_override(
		"panel", make_panel_stylebox(Color(0.20, 0.14, 0.08, 0.92), 10))
	toast_panel.custom_minimum_size = Vector2(TOAST_W, 0)
	toast_panel.visible = false
	add_child(toast_panel)

	toast_label = RichTextLabel.new()
	toast_label.bbcode_enabled = true
	toast_label.fit_content = true
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.custom_minimum_size = Vector2(TOAST_W - 16, 0)
	toast_label.add_theme_color_override("default_color", Color(0.95, 0.93, 0.88))
	toast_label.add_theme_font_size_override("normal_font_size", 13)
	toast_panel.add_child(toast_label)

	toast_panel.gui_input.connect(func (e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_report_panel()
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
	context_menu.add_item("改名" if current_language == "zh" else "Rename", 2)
	context_menu.add_item(mute_label, 3)
	context_menu.add_separator()
	context_menu.add_item("重置存档…" if current_language == "zh" else "Reset Save…", 4)
	context_menu.add_separator()
	context_menu.add_item("退出" if current_language == "zh" else "Quit", 5)

func _on_context_menu_id(id: int) -> void:
	_mark_interaction()
	match id:
		2:
			_open_name_dialog()
		3:
			sound_enabled = not sound_enabled
			AudioManager.set_sound_enabled(sound_enabled)
			_rebuild_context_menu()
			save_game()
		4:
			_confirm_reset()
		5:
			_on_quit_requested()

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
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
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
		report_panel.position = Vector2(win.x - report_panel.size.x - REPORT_MARGIN, REPORT_Y)

	if profile_panel != null and profile_panel.visible:
		profile_panel.position = Vector2(win.x - profile_panel.size.x - REPORT_MARGIN, REPORT_Y)

	if toast_panel != null and toast_panel.visible:
		var ts := toast_panel.size
		toast_panel.position.x = clamp(
			toast_panel.position.x,
			TOAST_MARGIN,
			win.x - ts.x - TOAST_MARGIN
		)

func _ready() -> void:
	randomize()
	get_tree().set_auto_accept_quit(false)
	get_window().size = WIN_NORMAL
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = true
	get_window().unresizable = true
	get_window().size_changed.connect(_on_window_size_changed)
	_timer = Timer.new()
	_timer.wait_time = DEATH_INTERVAL
	_timer.timeout.connect(_do_one_death)
	add_child(_timer)
	_build_counter_overlay()


	var screen_size := DisplayServer.screen_get_size()
	var start_pos := Vector2i(
		int(round((screen_size.x - WIN_NORMAL.x) / 2.0)),
		int(round((screen_size.y - WIN_NORMAL.y) / 2.0))
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
	_build_shop()
	_build_report_panel()
	_build_profile_panel()
	_build_toast()
	_build_certificate_panel() 
	_build_intro_panel()
	_build_main_hall()
	_build_context_menu()
	
	achievement_manager = AchievementManager.new()
	add_child(achievement_manager)
	achievement_manager.setup(
		Callable(self, "_show_toast"),          # reuse your toast
		func (): return current_language
	)

	$PetGroup/VBox.add_theme_stylebox_override(
		"panel", make_panel_stylebox(Color(0.93, 0.93, 0.93, 0.88), 10))
	var vbox := $PetGroup/VBox
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.scale = Vector2(VBOX_SCALE, VBOX_SCALE)

	load_game()
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
			var icon := "💭"
			if rarity == "rare": icon = "✨"
			elif rarity == "legendary": icon = "🌟"
			queue_message(icon + " " + (zh if current_language == "zh" else en)),
		func (): return current_language
	)
	event_manager.luck_provider = func (): return int(state.get("luck", 50))
	event_manager.realm_provider = func (): return int(state.get("realm_index", 0))   # ← add
	event_manager.encounter_handler = Callable(self, "_on_encounter")
	event_manager.special_animation_handler = Callable(self, "_on_event_special_animation")
	event_manager.history_hook = Callable(self, "_on_event_biography")
	event_manager.encounter_fired.connect(func (_e):
		if profile_panel != null and profile_panel.visible:
			_refresh_profile()
	)
	event_manager.log_updated.connect(func ():
		if report_panel != null and report_panel.visible:
			_refresh_reports()
	)

	achievement_manager.from_save(_pending_achievements)
	# refresh 人生 panel live when something unlocks
	achievement_manager.achievement_unlocked.connect(func (a):
		if typeof(a) == TYPE_DICTIONARY:
			var atitle_zh := String(a.get("title_zh", ""))
			var atitle_en := String(a.get("title_en", ""))
			if atitle_zh != "" or atitle_en != "":
				add_life_history("achievement", "获得成就：%s" % atitle_zh, "",
					"Achievement Unlocked: %s" % atitle_en, "")
		if profile_panel != null and profile_panel.visible:
			_refresh_profile()
	)
	# Buttons: 吃饭 / 履历 / 事件
	feed_button.pressed.connect(_on_feed)
	meditate_button.pressed.connect(_open_main_hall)
	info_button.pressed.connect(_on_report_pressed)

	_check_daily_report()
	_build_animations()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	status_label.scroll_active = false
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.custom_minimum_size = Vector2(120, 0)
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	status_label.add_theme_constant_override("outline_size", 2)
	
	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
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
		save_game()
	roll_daily_luck()

func _check_afk() -> void:
	if _is_intro_blocking():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not is_afk and (now - last_interaction_time) >= AFK_THRESHOLD_SECONDS:
		is_afk = true
		request_mood("lazy", MoodPriority.SYSTEM)
		
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
	return _is_cutscene_blocking() or (DEMO_MODE and demo_completed)

func _hide_transient_ui() -> void:
	if bubble_panel != null:
		bubble_panel.visible = false
	if bubble_tail != null:
		bubble_tail.visible = false
	if status_label != null:
		status_label.visible = false
	if toast_panel != null:
		toast_panel.visible = false

func _try_find_spirit_stone() -> void:
	var find_chance := 0.015 * (1.0 + luck_modifier() * 10.0)
	if randf() >= find_chance:
		return

	state["spirit_stones"] = int(state.get("spirit_stones", 0)) + 1
	today_stats["stone_gain"] = int(today_stats.get("stone_gain", 0)) + 1
	_today_event_tags["found_stone"] = true
	add_recent_event("捡到1灵石", "Found 1 spirit stone", "stone")

func _autosave_if_due() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_autosave_time < AUTOSAVE_INTERVAL:
		return

	last_autosave_time = now
	save_game()

func _open_name_dialog() -> void:
	_is_first_naming = String(state.get("pet_name", "")).strip_edges() == ""

	if name_edit != null:
		name_edit.text = String(state.get("pet_name", ""))

	_set_main_ui_visible(false)

	var safe_pos := _get_safe_window_position(WIN_WIDE)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = WIN_WIDE
	await get_tree().process_frame
	update_layout()

	name_dialog.visible = true
	name_dialog.z_index = 200
	request_mood("normal", MoodPriority.SYSTEM)

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

	save_game()
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
		get_window().size = WIN_NORMAL
		show_message_now(("我叫%s。" % n) if current_language == "zh" else ("I'm %s." % n))
		
# ══════════════════════════════════════════
#  LAYOUT
# ══════════════════════════════════════════

func _pet_area_center_x() -> float:
	var win := get_viewport_rect().size

	# 打开事件/人生/商店/toast 等宽窗口时，
	# 角色永远留在左侧正常区域，不跟着整个宽窗口居中
	if int(win.x) > WIN_NORMAL.x + 20:
		return WIN_NORMAL.x / 2.0

	# 普通小窗口时才居中
	return win.x / 2.0

func update_layout() -> void:
	pet_group.position = Vector2(_pet_area_center_x(), PETGROUP_Y)

	cultivator_sprite.centered = true
	cultivator_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	cultivator_sprite.position = Vector2(0, SPRITE_Y)

	status_label.position.y = REALM_STRIP_Y
	_center_status_label()

	var vbox = $PetGroup/VBox
	vbox.size = Vector2.ZERO
	await get_tree().process_frame

	var vbox_w: float = vbox.size.x * vbox.scale.x
	vbox.position = Vector2(-vbox_w / 2.0, VBOX_Y)

	if realm_strip != null:
		realm_strip.size = Vector2.ZERO
		await get_tree().process_frame
		realm_strip.position = Vector2(-realm_strip.size.x / 2.0, REALM_STRIP_Y + REALM_STRIP_OFFSET_Y)
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
	var suffix: String = TIER_ANIM_SUFFIX.get(tier, "")
	var anim := "%s_%s" % [suffix, base_anim]   # 比如 "martial_breath"
	print("[mood] 请求mood=", new_mood, " base_anim=", base_anim, " 尝试播放=", anim) 
	if suffix != "" and cultivator_sprite.sprite_frames != null and cultivator_sprite.sprite_frames.has_animation(anim):
		cultivator_sprite.play(anim)
		var offset: float = anim_x_offset.get(anim, anim_x_offset.get(base_anim, 0.0))
		cultivator_sprite.position.x = -offset * SPRITE_SCALE
	elif cultivator_sprite.sprite_frames != null and cultivator_sprite.sprite_frames.has_animation(base_anim):
		# 没有对应境界素材时（比如炼气期），兜底播放不带境界后缀的旧动画，不报错
		cultivator_sprite.play(base_anim)
		var fallback_offset: float = anim_x_offset.get(base_anim, 0.0)
		cultivator_sprite.position.x = -fallback_offset * SPRITE_SCALE

# ══════════════════════════════════════════
#  STATUS CHANNEL
# ══════════════════════════════════════════

func _schedule_next_status() -> void:
	var wait := randf_range(STATUS_MIN_SEC, STATUS_MAX_SEC)
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
	if not request_mood(picked_status["mood"], MoodPriority.AMBIENT):
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
	if DEMO_MODE:
		mult *= DEMO_CULT_MULT
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
			request_mood("confused", MoodPriority.EVENT)


# ══════════════════════════════════════════
#  REPORT EVENTS (story chains)
# ══════════════════════════════════════════
func _fire_report(row: Dictionary) -> void:
	state["cultivation"] = max(0, state["cultivation"] + row["cultivation_gain"])
	state["spirit_stones"] = max(0, state["spirit_stones"] + row["stone_gain"])
	today_stats["qi_gain"] += max(0, row["cultivation_gain"])
	if row["stone_gain"] > 0:
		today_stats["stone_gain"] += row["stone_gain"]
	if row["mood"] != "":
		request_mood(row["mood"], MoodPriority.EVENT)
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
		context_menu.position = DisplayServer.window_get_position() + Vector2i(event.position)
		context_menu.reset_size()
		context_menu.popup()
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
				_close_report_panel()
				return
		if profile_panel != null and profile_panel.visible:
			var lp: Vector2 = profile_panel.get_global_transform().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, profile_panel.size).has_point(lp):
				_close_profile_panel()
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

	gain_cultivation(1.0)
	_try_find_spirit_stone()
	_check_daily_report()
	_autosave_if_due()

	if main_hall_panel != null and main_hall_panel.visible:
		_mh_session_seconds += 1
		_refresh_main_hall_live()

	if profile_panel != null and profile_panel.visible:
		_update_profile_detail_live()


# ══════════════════════════════════════════
#  CULTIVATION / BREAKTHROUGH
# ══════════════════════════════════════════

func gain_cultivation(multiplier: float) -> void:
	if DEMO_MODE and demo_completed:
		return

	if int(state.get("realm_index", 0)) >= realms.size() - 1:
		return

	var realm: Dictionary = realms[state["realm_index"]]
	var gain := 2.0 * multiplier * cultivation_multiplier()
	state["cultivation"] += gain
	today_stats["qi_gain"] += int(gain)

	# 达到面板显示的需求就突破
	if state["cultivation"] >= float(realm["need"]):
		try_breakthrough()

func _can_attempt_breakthrough_now() -> bool:
	if _reincarnating:
		return false
	if DEMO_MODE and demo_completed:
		return false
	if int(state.get("realm_index", 0)) >= realms.size() - 1:
		return false
	var realm: Dictionary = realms[int(state.get("realm_index", 0))]
	return float(state.get("cultivation", 0.0)) >= float(realm["need"])

func try_breakthrough() -> void:
	if DEMO_MODE and demo_completed:
		return

	if int(state.get("realm_index", 0)) >= realms.size() - 1:
		_check_demo_ending()
		return
	today_stats["breakthrough_attempt"] += 1
	var chance := 0.82
	if state["realm_index"] >= 3: chance = 0.65
	if state["realm_index"] >= 6: chance = 0.45
	chance = clampf(chance + luck_modifier() + next_breakthrough_bonus + float(reincarnation_modifiers.get("breakthrough_bonus", 0.0)), 0.05, 0.98)

	var insight: int = int(state.get("breakthrough_insight", 0))
	chance += insight * 0.005
	chance = clampf(chance, 0.05, 0.98)
	if DEMO_MODE:
		chance = clampf(chance + DEMO_BREAKTHROUGH_BONUS, 0.05, 0.98)

	var success: bool
	if insight >= BREAKTHROUGH_INSIGHT_CAP:
		success = true
	else:
		success = randf() <= chance

	next_breakthrough_bonus = 0.0
	var transition_anim_playing := ""

	if success:
		today_stats["breakthrough_success"] += 1
		_today_event_tags["breakthrough_success"] = true
		var old_tier := current_tier()
		state["realm_index"] = min(state["realm_index"] + 1, realms.size() - 1)
		state["highest_realm_this_life"] = max(int(state.get("highest_realm_this_life", 0)), state["realm_index"])
		state["life_breakthrough_success"] = int(state.get("life_breakthrough_success", 0)) + 1
		state["breakthrough_success_total_lifetime"] = int(state.get("breakthrough_success_total_lifetime", 0)) + 1
		var lifespan_bonus: int = _lifespan_bonus_for_realm(state["realm_index"])
		state["lifespan"] += lifespan_bonus
		state["cultivation"] = 0.0
		_check_spiritual_root_awakening()
		_age_up(_years_for_breakthrough(state["realm_index"]))
		var new_tier := current_tier()
		var transition_anim := "%s_breakthrough_%s" % [
			TIER_ANIM_SUFFIX.get(old_tier, ""), TIER_ANIM_SUFFIX.get(new_tier, "")
		]
		if new_tier != old_tier and cultivator_sprite.sprite_frames != null \
			and cultivator_sprite.sprite_frames.has_animation(transition_anim):
			_current_mood_priority = MoodPriority.SYSTEM
			cultivator_sprite.position.x = 0
			cultivator_sprite.play(transition_anim)
			transition_anim_playing = transition_anim
		else:
			request_mood("breakthrough_success", MoodPriority.EVENT)
		AudioManager.play_breakthrough()

		var had_insight: int = int(state.get("breakthrough_insight", 0))
		state["breakthrough_insight"] = 0

		var success_line_zh := ""
		var success_line_en := ""
		var success_pool = DataLoader.breakthrough_success_lines.filter(func(r): return r["realm"] == new_tier)
		if success_pool.is_empty():
			success_pool = DataLoader.breakthrough_success_lines
		if not success_pool.is_empty():
			var picked = success_pool.pick_random()
			success_line_zh = picked["zh"]
			success_line_en = picked["en"]

		add_recent_event("突破到「%s」" % realms[state["realm_index"]]["name"],
			"Advanced to %s" % realm_names_en[state["realm_index"]], "breakthrough")
		add_life_history("breakthrough", "突破成功", "境界提升至「%s」。" % realms[state["realm_index"]]["name"],
			"Breakthrough Success", "Advanced to %s." % realm_names_en[state["realm_index"]])
		if new_tier != old_tier:
			add_life_record("突破%s境" % new_tier, "Entered the %s realm" % new_tier, "breakthrough")

		if had_insight > 0:
			add_life_record(
				"厚积薄发，成功突破%s" % realms[state["realm_index"]]["name"],
				"Years of insight paid off — advanced to %s" % realm_names_en[state["realm_index"]],
				"breakthrough"
			)
			_show_toast("突破成功", "Breakthrough",
				[{"zh": success_line_zh, "en": success_line_en},
				 {"zh":"突破到「%s」！" % realms[state["realm_index"]]["name"],
				  "en":"Advanced to %s!" % realm_names_en[state["realm_index"]]},
				 {"zh":"寿元 +%d" % lifespan_bonus, "en":"Lifespan +%d" % lifespan_bonus},
				 {"zh":"多年感悟终于开花结果。", "en":"Your accumulated insight has finally paid off."}])
		else:
			_show_toast("突破成功", "Breakthrough",
				[{"zh": success_line_zh, "en": success_line_en},
				 {"zh":"突破到「%s」！" % realms[state["realm_index"]]["name"],
				  "en":"Advanced to %s!" % realm_names_en[state["realm_index"]]},
				 {"zh":"寿元 +%d" % lifespan_bonus, "en":"Lifespan +%d" % lifespan_bonus}])
		_check_demo_ending()
		if await _demo_force_death_if_due():
			return

	else:
		var penalty := 1 if failure_penalty_reduced else 3
		penalty += int(reincarnation_modifiers.get("failure_penalty_delta", 0))
		penalty = int(round(penalty * _personality_bias("failure_penalty_mult")))
		penalty = max(1, penalty)
		state["lifespan"] -= penalty
		failure_penalty_reduced = false
		state["cultivation"] = state["cultivation"] * 0.5
		request_mood("breakthrough_fail", MoodPriority.EVENT)

		state["breakthrough_insight"] = min(BREAKTHROUGH_INSIGHT_CAP, int(state.get("breakthrough_insight", 0)) + BREAKTHROUGH_INSIGHT_PER_FAIL)
		state["life_breakthrough_fails"] = int(state.get("life_breakthrough_fails", 0)) + 1
		state["breakthrough_fail_total_lifetime"] = int(state.get("breakthrough_fail_total_lifetime", 0)) + 1
		if achievement_manager != null:
			achievement_manager.record_breakthrough_fail_total(state["breakthrough_fail_total_lifetime"])
		if int(state["life_breakthrough_fails"]) >= 3:
			_nudge_personality("diligent", 1.0)
			
		_age_up(randi_range(1, 3))
		
		add_recent_event(
   			 "突破失败 寿元-%d 感悟+%d%%" % [penalty, BREAKTHROUGH_INSIGHT_PER_FAIL],
  			  "Breakthrough failed  Lifespan -%d  Insight +%d%%" % [penalty, BREAKTHROUGH_INSIGHT_PER_FAIL],
  			  "special"
		)
		add_life_record(
			"冲击%s失败，获得感悟" % realms[state["realm_index"]]["name"],
			"Failed to break through %s — gained insight" % realm_names_en[state["realm_index"]],
			"special"
		)
		add_life_history("breakthrough", "突破失败", "冲击「%s」未果，灵气逆流，但有所感悟。" % realms[state["realm_index"]]["name"],
			"Breakthrough Failed", "Failed to break through %s — qi surged backward, but insight was gained." % realm_names_en[state["realm_index"]])

		var fail_reason_zh := ""
		var fail_reason_en := ""
		_today_event_tags["breakthrough_fail"] = true
		var tier_pool = DataLoader.breakthrough_fail_reasons.filter(func(r): return r["realm"] == current_tier())
		if tier_pool.is_empty():
			tier_pool = DataLoader.breakthrough_fail_reasons
		if not tier_pool.is_empty():
			var picked = tier_pool.pick_random()
			fail_reason_zh = picked["zh"]
			fail_reason_en = picked["en"]

		_show_toast("突破失败", "Breakthrough Failed",
   			 [{"zh": fail_reason_zh, "en": fail_reason_en},
   			  {"zh":"寿元 -%d" % penalty, "en":"Lifespan -%d" % penalty},
   			  {"zh":"感悟 +%d%%" % BREAKTHROUGH_INSIGHT_PER_FAIL, "en":"Insight +%d%%" % BREAKTHROUGH_INSIGHT_PER_FAIL},
				 {"zh":"修为保留 %d" % int(state["cultivation"]), "en":"Cultivation retained: %d" % int(state["cultivation"])}])
		if await check_lifespan():
			return

	if transition_anim_playing != "":
		await get_tree().create_timer(_death_anim_duration(transition_anim_playing) + 0.1).timeout
	else:
		# 等实际动画播完再切回 normal
		var current_anim: String = String(cultivator_sprite.animation)
		var anim_dur := _death_anim_duration(current_anim)
		await get_tree().create_timer(max(anim_dur, 1.5) + 0.3).timeout
	clear_mood_priority()
	request_mood("normal", MoodPriority.AMBIENT)
	refresh_ui()
	save_game()   # 突破是重要事件，节流后仍即时落盘

func check_lifespan() -> bool:
	if _reincarnating:
		return false
	if int(state["lifespan"]) > 0:
		return false

	_reincarnating = true
	state["lifespan"] = 0

	var cause := _pick_death_cause()
	var cause_zh: String = cause["title_zh"]
	var cause_en: String = cause["title_en"]
	var cause_id: String = cause.get("id", "")

	var prev_life: int = int(state.get("life_count", 1))
	var highest: int = int(state.get("highest_realm_this_life", state["realm_index"]))
	death_history.append({
		"life": prev_life,
		"age": _current_age(),
		"highest_realm": highest,
		"cause_zh": cause_zh,
		"cause_en": cause_en,
		"time": Time.get_time_string_from_system().substr(0, 5)
	})
	if death_history.size() > 50:
		death_history.pop_front()

	if cause_id != "":
		discovered_death_causes[cause_id] = true

	# 轮回总结 + 抽下一世天赋（必须在 _reincarnate 重置前收集本世数据）
	var life_title := _pick_life_title()
	var prev_data := collect_current_life_data(cause, life_title)
	var next_perk := roll_reincarnation_perk(prev_data, cause)
	var next_personality := roll_personality(prev_data, cause, next_perk)
	var next_instinct := _roll_instinct(prev_data, cause)
	var picked_last_words := _pick_last_words(cause)
	var punchline := _generate_death_punchline(cause, life_title, picked_last_words)
	_last_death_punchline = punchline
	add_reincarnation_history_record(cause, life_title, next_perk)
	
	
	add_life_record("寿终：%s" % cause_zh, "Died: %s" % cause_en, "death")
	add_recent_event("陨落：%s" % cause_zh, "Fell: %s" % cause_en, "death")
	add_life_history("death", "本世陨落：%s" % cause_zh, punchline["zh"],
		"Fell this life: %s" % cause_en, punchline["en"])
	_today_event_tags["death"] = true
	if cause_id != "" and not death_cause_first_punchline.has(cause_id):
		death_cause_first_punchline[cause_id] = punchline
	if achievement_manager != null:
		achievement_manager.record_death_cause(cause_zh)
		achievement_manager.record_death_variety(discovered_death_causes.size())

	var death_anim := _play_death_animation(cause)
	AudioManager.play_death(-4.0)
	refresh_ui()
	save_game()

	# 先等死亡动画完整播完（+0.3秒定格在焦黑/魂魄那帧），再弹证书
	await get_tree().create_timer(_death_anim_duration(death_anim) + 0.3).timeout

	_show_reincarnation_certificate(cause_zh, cause_en, prev_life, highest, punchline)
	# 等玩家点掉证书再轮回（最多兜底 12 秒，避免一直卡死）
	var waited := 0.0
	while _certificate_open and waited < 12.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	if certificate_panel != null:
		certificate_panel.visible = false
	_reincarnate(next_perk, next_personality, next_instinct)
	return true

func _reincarnate(next_perk: Dictionary = {}, next_personality: String = "", next_instinct: String = "") -> void:
	var new_life: int = int(state.get("life_count", 1)) + 1
	var bonus := float(state.get("reincarnation_bonus", 0.0)) + REINCARNATION_BONUS_PER_LIFE
	bonus = min(bonus, REINCARNATION_BONUS_CAP)

	# 先应用下一世天赋，算出初始加成
	apply_reincarnation_perk(next_perk)
	var lifespan_bonus := int(reincarnation_modifiers.get("lifespan_bonus", 0))
	var luck_bonus := int(reincarnation_modifiers.get("starting_luck_bonus", 0))
	var stone_keep_bonus := float(reincarnation_modifiers.get("stone_keep_bonus", 0.0))

	# 性情先于职业抽取设置好，这样 _assign_mortal_job() 里的偏好表才能正确生效
	active_effects.clear()
	life_flags.clear()
	_personality_drift.clear()
	memorable_events.clear()
	_foreshadow_flags.clear()
	_clear_decision()
	if next_personality != "" and PERSONALITY_TRAITS.has(next_personality):
		current_personality = next_personality
	elif current_personality == "" or not PERSONALITY_TRAITS.has(current_personality):
		current_personality = "lazy"   # absolute fallback — should never trigger, but never leave it blank

	var job := _roll_mortal_job()
	var previous_state := state.duplicate(true)
	var old_luck := int(previous_state.get("luck", 50))
	var stones_kept := int(int(previous_state.get("spirit_stones", 0) / 2) * (1.0 + stone_keep_bonus))

	state = {
		"realm_index": 0, "cultivation": 0.0,
		"spirit_stones": stones_kept, "lifespan": 80 + lifespan_bonus,
		"last_saved_unix": Time.get_unix_time_from_system(),
		"luck": clampi(old_luck + luck_bonus, 1, 100), "luck_date": previous_state.get("luck_date", ""),
		"life_count": new_life, "highest_realm_this_life": 0,
		"reincarnation_bonus": bonus,
		"click_count": int(previous_state.get("click_count", 0)),
		"pet_name": previous_state.get("pet_name", ""), "mortal_job": "",
		"spiritual_root": "","language": current_language,
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
	state["mortal_job"] = job["id"]
	var perk_name := String(active_reincarnation_perk.get("zh", "平平无奇")) if not active_reincarnation_perk.is_empty() else "平平无奇"
	var perk_name_en := String(active_reincarnation_perk.get("en", "Utterly Ordinary")) if not active_reincarnation_perk.is_empty() else "Utterly Ordinary"
	add_life_record("第 %d 次转世" % (new_life - 1), "Reincarnation #%d" % (new_life - 1), "special")
	var job_label_zh2: String = job["zh"]
	var job_label_en2: String = job["en"]
	add_life_history(
		"birth",
		"转世重修",
		"第 %d 世开始。今生职业：%s。轮回天赋：%s。性情：%s。" % [new_life, job_label_zh2, perk_name, PERSONALITY_META[current_personality]["zh"]],
		"Reincarnated",
		"Life %d begins. Job this life: %s. Reincarnation perk: %s. Personality: %s." % [new_life, job_label_en2, perk_name_en, PERSONALITY_META[current_personality]["en"]]
	)
	if achievement_manager != null:
		achievement_manager.record_life_count(new_life)
	_instinct_tag = next_instinct
	clear_mood_priority()
	request_mood("normal", MoodPriority.AMBIENT)
	refresh_ui()
	save_game()
	_reincarnating = false
	_set_main_ui_visible(false)
	_show_intro_sequence(String(state.get("pet_name", "小白")), true)

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
		_open_shop()
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - last_feed_time < FEED_COOLDOWN_SECONDS:
		show_message_now("还没饿，等一下吧。" if current_language == "zh" else "Not hungry yet, give it a moment.")
		return
	last_feed_time = now

	today_stats["pill_eaten"] = int(today_stats.get("pill_eaten", 0)) + 1

	gain_cultivation(15.0)
	var eat_played := request_mood("eat", MoodPriority.EVENT)
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
		var eat_anim := _resolve_mood_anim("eat")
		var dur := _death_anim_duration(eat_anim)   # 名字带"death"但其实就是纯算时长，通用
		await get_tree().create_timer(max(dur, 1.0) + 0.1).timeout
		request_mood("normal", MoodPriority.EVENT)
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
	if now - last_poke_time <= POKE_STREAK_RESET_SEC:
		poke_streak += 1
	else:
		poke_streak = 1
	last_poke_time = now

	var force_angry := poke_streak >= POKE_ANGRY_STREAK
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
		request_mood("angry", MoodPriority.EVENT)
		reward_zh = "你再戳，我真的要走火入魔了。"
		reward_en = "Poke me again and I may go qi-deviant."

	elif roll < 0.80:
		# 80% plain grumble, no reward — pick a filler line
		reward_zh = ""
		reward_en = ""
	elif roll < 0.95:
		# 15% happy, +5 cultivation
		state["cultivation"] = max(0, state["cultivation"] + 5)
		request_mood("happy", MoodPriority.EVENT)
		reward_zh = "嘿嘿，修为 +5。"
		reward_en = "Hehe, cultivation +5."
	elif roll < 0.99:
		active_effects.append({
			"type": "slow_cultivation", "remaining": 10.0, "magnitude": 0.8,
			"label_zh": "别烦我！修炼变慢了。", "label_en": "Leave me alone! Cultivation slowed."
		})
		request_mood("angry", MoodPriority.EVENT)
		reward_zh = "别戳了，修炼都乱了。"
		reward_en = "Stop it, you're breaking my focus."
	else:
		# 1% epiphany, +50 cultivation
		state["cultivation"] = max(0, state["cultivation"] + 50)
		request_mood("meditate", MoodPriority.EVENT)
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
	save_game()

# ══════════════════════════════════════════
#  EVENT REWARD HANDLER (for EventManager)
# ══════════════════════════════════════════

func _apply_event_reward(type: String, value: int) -> void:
	match type:
		"qi":
			state["cultivation"] = max(0, state["cultivation"] + value)
		"stone":
			state["spirit_stones"] = max(0, state["spirit_stones"] + value)
			if value > 0: today_stats["stone_gain"] += value
		"lifespan":
			state["lifespan"] += value
		"luck":
			state["luck"] = clampi(int(state.get("luck", 50)) + value, 1, 100)
		"insight":
			state["breakthrough_insight"] = clampi(int(state.get("breakthrough_insight", 0)) + value, 0, BREAKTHROUGH_INSIGHT_CAP)
		"breakthrough_bonus":
			next_breakthrough_bonus += value / 100.0
		"death_risk":
			var adjusted_value := float(value) * _personality_bias("death_risk_mult")
			if randf() < adjusted_value / 100.0:
				state["lifespan"] = 0
				if await check_lifespan():
					return
		"pill":
			pass
	refresh_ui()
	save_game()


# ══════════════════════════════════════════
#  OFFLINE REWARDS
# ══════════════════════════════════════════

func grant_offline_rewards() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var last := int(state.get("last_saved_unix", now))
	if last <= 0:
		last = now
	var offline_seconds: int = clampi(now - last, 0, OFFLINE_CAP_SECONDS)
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
	if today_stats["date"] != today:
		_push_daily_summary()
		_yesterday_event_tags = _today_event_tags.duplicate()
		_today_event_tags.clear()
		_reset_today_stats(today)
		_day_counter += 1
		_drain_scheduled_chain_unlocks()
		_clear_expired_foreshadows()
		_auto_resolve_stale_decision()
		save_game()

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
		_refresh_reports()
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
	if bubble_panel == null:
		return
	bubble_label.text     = text
	bubble_panel.visible  = true
	bubble_tail.visible   = true
	bubble_panel.modulate = Color(1, 1, 1, 0)
	bubble_tail.modulate  = Color(1, 1, 1, 0)
	await get_tree().process_frame
	var target_y := BUBBLE_ANCHOR_Y - bubble_panel.size.y - BUBBLE_GAP
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

func save_game() -> void:
	state["last_saved_unix"] = Time.get_unix_time_from_system()
	var data := {"state": state, "today_stats": today_stats,
		"active_effects": active_effects, "reports": reports,
		"pending_chains": pending_chains, "demo_completed": demo_completed, "death_history": death_history,
		"discovered_death_causes": discovered_death_causes, "discovered_encounters": discovered_encounters,
		"life_records": life_records, "sound_enabled": sound_enabled,
		"recent_events": recent_events,
		"life_history": life_history,
		"life_flags": life_flags,"pending_decision": _pending_decision,
		"memorable_events": memorable_events,
		"foreshadow_flags": _foreshadow_flags,
		"achievement_unlocked_today": _achievement_unlocked_today,
		"today_event_tags": _today_event_tags,
		"yesterday_event_tags": _yesterday_event_tags,
		"scheduled_chain_unlocks": _scheduled_chain_unlocks,
		"day_counter": _day_counter,
		"current_personality": current_personality,
		"personality_drift": _personality_drift,
		"instinct_tag": _instinct_tag,
		"rare_encounter_count": rare_encounter_count,
		"legendary_encounter_count": legendary_encounter_count,
		"last_death_punchline": _last_death_punchline,
		"death_cause_first_punchline": death_cause_first_punchline,
		"reincarnation_history": reincarnation_history,
		"active_reincarnation_perk": active_reincarnation_perk,
		"achievements": achievement_manager.to_save() if achievement_manager != null else {},
		"event_log": event_manager.to_save() if event_manager != null else []}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
	


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	
	if typeof(parsed) == TYPE_DICTIONARY:
		if parsed.has("state") and typeof(parsed["state"]) == TYPE_DICTIONARY:
			for key in parsed["state"].keys():
				state[key] = parsed["state"][key]
		if parsed.has("today_stats") and typeof(parsed["today_stats"]) == TYPE_DICTIONARY:
			for key in parsed["today_stats"].keys():
				today_stats[key] = parsed["today_stats"][key]
		if parsed.has("active_effects") and typeof(parsed["active_effects"]) == TYPE_ARRAY:
			active_effects = parsed["active_effects"]
		if parsed.has("life_records") and typeof(parsed["life_records"]) == TYPE_ARRAY:
			life_records = parsed["life_records"]
		if parsed.has("recent_events") and typeof(parsed["recent_events"]) == TYPE_ARRAY:
			recent_events = parsed["recent_events"]
		if parsed.has("sound_enabled"):
			sound_enabled = parsed["sound_enabled"]
		if not state.has("breakthrough_insight"):
			state["breakthrough_insight"] = 0
		if parsed.has("reports") and typeof(parsed["reports"]) == TYPE_ARRAY:
			reports = parsed["reports"]
		if parsed.has("death_history") and typeof(parsed["death_history"]) == TYPE_ARRAY:
			death_history = parsed["death_history"]
		if parsed.has("discovered_death_causes") and typeof(parsed["discovered_death_causes"]) == TYPE_DICTIONARY:
			discovered_death_causes = parsed["discovered_death_causes"]
		if parsed.has("pending_chains") and typeof(parsed["pending_chains"]) == TYPE_ARRAY:
			pending_chains = parsed["pending_chains"]
		if parsed.has("demo_completed"):
			demo_completed = parsed["demo_completed"]
		if parsed.has("event_log"):
			_pending_event_log = parsed["event_log"]
		if parsed.has("achievements"):
			_pending_achievements = parsed["achievements"]
		if parsed.has("last_death_punchline") and typeof(parsed["last_death_punchline"]) == TYPE_DICTIONARY:
			_last_death_punchline = parsed["last_death_punchline"]
		if parsed.has("death_cause_first_punchline") and typeof(parsed["death_cause_first_punchline"]) == TYPE_DICTIONARY:
			death_cause_first_punchline = parsed["death_cause_first_punchline"]
		if parsed.has("reincarnation_history") and typeof(parsed["reincarnation_history"]) == TYPE_ARRAY:
			reincarnation_history = parsed["reincarnation_history"]
		if parsed.has("active_reincarnation_perk") and typeof(parsed["active_reincarnation_perk"]) == TYPE_DICTIONARY:
			active_reincarnation_perk = parsed["active_reincarnation_perk"]
		if parsed.has("discovered_encounters") and typeof(parsed["discovered_encounters"]) == TYPE_DICTIONARY:
			discovered_encounters = parsed["discovered_encounters"]
		if parsed.has("rare_encounter_count"):
			rare_encounter_count = int(parsed["rare_encounter_count"])
		if parsed.has("legendary_encounter_count"):
			legendary_encounter_count = int(parsed["legendary_encounter_count"])
		if parsed.has("life_history") and typeof(parsed["life_history"]) == TYPE_ARRAY:
			life_history = parsed["life_history"]
		if parsed.has("life_flags") and typeof(parsed["life_flags"]) == TYPE_DICTIONARY:
			life_flags = parsed["life_flags"]
		if parsed.has("scheduled_chain_unlocks") and typeof(parsed["scheduled_chain_unlocks"]) == TYPE_ARRAY:
			_scheduled_chain_unlocks = parsed["scheduled_chain_unlocks"]
		if parsed.has("day_counter"):
			_day_counter = int(parsed["day_counter"])
		if parsed.has("pending_decision") and typeof(parsed["pending_decision"]) == TYPE_DICTIONARY:
			_pending_decision = parsed["pending_decision"]
			if not _pending_decision.is_empty():
				call_deferred("_show_decision_indicator")
		if parsed.has("current_personality"):
			current_personality = String(parsed["current_personality"])
		if parsed.has("personality_drift") and typeof(parsed["personality_drift"]) == TYPE_DICTIONARY:
			_personality_drift = parsed["personality_drift"]
		if parsed.has("today_event_tags") and typeof(parsed["today_event_tags"]) == TYPE_DICTIONARY:
			_today_event_tags = parsed["today_event_tags"]
		if parsed.has("yesterday_event_tags") and typeof(parsed["yesterday_event_tags"]) == TYPE_DICTIONARY:
			_yesterday_event_tags = parsed["yesterday_event_tags"]
		if parsed.has("achievement_unlocked_today") and typeof(parsed["achievement_unlocked_today"]) == TYPE_DICTIONARY:
			_achievement_unlocked_today = parsed["achievement_unlocked_today"]
		if parsed.has("memorable_events") and typeof(parsed["memorable_events"]) == TYPE_ARRAY:
			memorable_events = parsed["memorable_events"]
		if parsed.has("foreshadow_flags") and typeof(parsed["foreshadow_flags"]) == TYPE_DICTIONARY:
			_foreshadow_flags = parsed["foreshadow_flags"]
		if parsed.has("instinct_tag"):
			_instinct_tag = String(parsed["instinct_tag"])
		if demo_completed and feed_button != null:
			feed_button.disabled = true
	if not PERSONALITY_TRAITS.has(current_personality):
		current_personality = "lazy"
	# 旧存档迁移：有 life_records 但还没有 life_history → 自动转换，避免历史丢失
	if life_history.is_empty() and not life_records.is_empty():
		for rec in life_records:
			if typeof(rec) != TYPE_DICTIONARY:
				life_history.append(normalize_life_history_entry(rec))
				continue
			var t := String(rec.get("zh", ""))
			life_history.append({
				"life": int(state.get("life_count", 1)),
				"age": int(rec.get("age", _current_age())),
				"realm": realms[state["realm_index"]]["name"],
				"category": _life_category_from_type(String(rec.get("type", "")), t),
				"title": t,
				"description": "",
				"time": ""
			})
	apply_reincarnation_perk(active_reincarnation_perk)
	current_language = String(state.get("language", "zh"))


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
	var idx: int = clampi(min_realm, 0, realms.size() - 1)
	return realms[idx]["name"] if current_language == "zh" else realm_names_en[idx]


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

func _open_shop() -> void:
	if report_panel != null: report_panel.visible = false
	if profile_panel != null: profile_panel.visible = false
	_refresh_shop()
	await _dock_panel(shop_panel)


func _refresh_shop() -> void:
	for child in shop_list.get_children():
		child.queue_free()
	var source = DataLoader.pills if not DataLoader.pills.is_empty() else _fallback_pills()
	var realm_idx := int(state.get("realm_index", 0))
	source = source.filter(func(p): return realm_idx >= int(p.get("min_realm", 0)))
	var header_row := HBoxContainer.new()
	shop_list.add_child(header_row)
	var header := Label.new()
	header.text = ("丹药铺  灵石：%d" % state["spirit_stones"]) if current_language == "zh" \
		else ("Pill Shop  Stones: %d" % state["spirit_stones"])
	header.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_shop)
	header_row.add_child(close_btn)
	if source.is_empty():
		var empty := Label.new()
		empty.text = "凡人先好好吃饭。\n丹药铺会在武者后逐步开放。" if current_language == "zh" \
			else "Eat proper meals for now.\nPills unlock gradually from the Martial realm."
		empty.add_theme_color_override("font_color", Color(0.4, 0.35, 0.3))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(200, 0)
		shop_list.add_child(empty)
		return
	for pill in source:
		var btn := Button.new()
		var pname: String = pill["name_zh"] if current_language == "zh" else pill["name_en"]
		btn.text = "%s  (%d)" % [pname, pill["cost"]]
		btn.disabled = state["spirit_stones"] < pill["cost"]
		btn.pressed.connect(_on_buy_pill.bind(pill))
		shop_list.add_child(btn)


func _close_shop() -> void:
	if shop_panel != null:
		shop_panel.visible = false


func _on_buy_pill(pill: Dictionary) -> void:
	var min_realm := int(pill.get("min_realm", 0))
	if int(state.get("realm_index", 0)) < min_realm:
		queue_message(("境界不足，至少需要%s。" % _pill_unlock_text(min_realm)) if current_language == "zh" \
			else ("Realm too low. Requires %s." % _pill_unlock_text(min_realm)))
		return
	if state["spirit_stones"] < pill["cost"]:
		queue_message("灵石不足。" if current_language == "zh" else "Not enough stones.")
		return
	state["spirit_stones"] -= pill["cost"]
	state["life_pills_eaten"] = int(state.get("life_pills_eaten", 0)) + 1
	state["pills_total_lifetime"] = int(state.get("pills_total_lifetime", 0)) + 1
	today_stats["pill_eaten"] += 1
	if pill["cultivation_gain"] != 0:
		var pill_mult := float(reincarnation_modifiers.get("pill_effect_mult", 1.0))
		state["cultivation"] = max(0, state["cultivation"] + int(pill["cultivation_gain"] * pill_mult))
	if pill["success_bonus"] != 0:
		next_breakthrough_bonus += pill["success_bonus"] / 100.0
	request_mood(pill["mood"], MoodPriority.EVENT)
	var pname: String = pill["name_zh"] if current_language == "zh" else pill["name_en"]
	queue_message(("服用%s。" % pname) if current_language == "zh" else ("Took %s." % pname))
	add_recent_event("服用%s" % pname, "Took %s" % pname, "item")
	add_life_history("alchemy", "服用%s" % pname, "他说这是合理的修炼资源分配。")
	await _apply_pill_effects(pill)
	_refresh_shop()
	refresh_ui()
	save_game()


func _apply_pill_effects(pill: Dictionary) -> void:
	var risk_mult := float(reincarnation_modifiers.get("pill_risk_mult", 1.0)) * _personality_bias("alchemy_attempt_mult")

	match pill["id"]:
		"pill_009":
			add_effect("fast_cultivation", 60.0, 1.5, "灵感如泉涌！", "Inspiration surges!")
			return
		"pill_010":
			add_effect("frenzy", 20.0, 1.0, "狂化！修为暴涨但隐患潜伏。", "Frenzy! Power soars, danger lurks.")
			return
		"pill_014":
			add_effect("slow_cultivation", 20.0, 0.85, "心神宁静，但有些困。", "Calm but drowsy.")
			request_mood("sleepy", MoodPriority.EVENT)
			return

	match pill.get("side_effect", "none"):
		"restore_lifespan_3":
			state["lifespan"] += 3

		"reduce_failure_penalty":
			failure_penalty_reduced = true

		"lose_lifespan_2":
			var loss: int = maxi(1, int(round(2.0 * risk_mult)))
			state["lifespan"] = int(state["lifespan"]) - loss

		"lose_cultivation_10":
			var loss_qi: int = maxi(1, int(round(10.0 * risk_mult)))
			state["cultivation"] = maxf(0.0, float(state["cultivation"]) - float(loss_qi))

		"random_bad_stomach":
			var chance := clampf(0.5 * risk_mult, 0.05, 0.95)
			if randf() < chance:
				add_effect("stomach_ache", 30.0, 1.0, "肚子开始翻江倒海……", "Your stomach churns...")
				add_effect("slow_cultivation", 30.0, 0.5, "修为增长变慢了。", "Cultivation slows.")
				request_mood("confused", MoodPriority.EVENT)

	if await check_lifespan():
		return

# ══════════════════════════════════════════
#  REPORT PANEL  (事件)
# ══════════════════════════════════════════


func _on_report_pressed() -> void:
	_mark_interaction()
	AudioManager.play_click()
	if report_panel.visible:
		_close_report_panel()
		return
	if shop_panel != null: shop_panel.visible = false
	if profile_panel != null: profile_panel.visible = false
	_open_report_panel()


func _open_report_panel() -> void:
	report_expanded = false
	if shop_panel != null: shop_panel.visible = false
	if profile_panel != null: profile_panel.visible = false
	_refresh_reports()
	await _dock_panel(report_panel)

func _close_report_panel() -> void:
	await _undock_panel(report_panel)


var report_expanded := false

func _refresh_reports() -> void:
	# 先清空，再加 header
	for child in report_list.get_children():
		child.queue_free()

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := Label.new()
	header.text = "📢 最近事件" if current_language == "zh" else "📢 Recent Events"
	header.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0, 0, 0, 0.8))
	close_btn.pressed.connect(_close_report_panel)
	header_row.add_child(close_btn)
	report_list.add_child(header_row)

	if recent_events.is_empty():
		var empty := Label.new()
		empty.text = "暂无近期事件" if current_language == "zh" else "No recent events."
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		report_list.add_child(empty)
		return

	var display_count: int = recent_events.size() if report_expanded else min(20, recent_events.size())
	var start_index: int = recent_events.size() - display_count

	for i in range(recent_events.size() - 1, start_index - 1, -1):
		var ev = recent_events[i]
		var row := Label.new()
		var text: String = ev.get("zh", "") if current_language == "zh" else ev.get("en", "")
		row.text = "%s  %s %s" % [ev.get("time", ""), _event_icon(ev.get("type", "")), text]
		row.add_theme_color_override("font_color", Color(0.32, 0.28, 0.36))
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(270, 0)
		report_list.add_child(row)

		var dtext: String = ev.get("desc_zh", "") if current_language == "zh" else ev.get("desc_en", "")
		if dtext.strip_edges() != "":
			var desc := Label.new()
			desc.text = "    %s" % dtext
			desc.add_theme_color_override("font_color", Color(0.5, 0.46, 0.5))
			desc.add_theme_font_size_override("font_size", 14)
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.custom_minimum_size = Vector2(270, 0)
			report_list.add_child(desc)

		var sep := HSeparator.new()
		var sep_style := StyleBoxLine.new()
		sep_style.color = Color(0.6, 0.55, 0.5, 0.35)
		sep_style.thickness = 1
		sep_style.grow_begin = -8.0
		sep_style.grow_end = -8.0
		sep.add_theme_stylebox_override("separator", sep_style)
		report_list.add_child(sep)

	# Show "查看更多" button if there's more history than currently displayed
	if not report_expanded and recent_events.size() > 20:
		var more_btn := Button.new()
		more_btn.text = "查看更多" if current_language == "zh" else "Show More"
		more_btn.pressed.connect(func():
			report_expanded = true
			_refresh_reports()
		)
		report_list.add_child(more_btn)
	elif report_expanded and recent_events.size() > 20:
		var less_btn := Button.new()
		less_btn.text = "收起" if current_language == "zh" else "Show Less"
		less_btn.pressed.connect(func():
			report_expanded = false
			_refresh_reports()
		)
		report_list.add_child(less_btn)


# ══════════════════════════════════════════
#  PROFILE PANEL  (履历)
# ══════════════════════════════════════════

func _on_profile() -> void:
	_mark_interaction()
	AudioManager.play_click()
	if profile_panel.visible:
		_close_profile_panel()
		return
	if shop_panel != null: shop_panel.visible = false
	if report_panel != null: report_panel.visible = false
	_refresh_profile()
	await _dock_panel(profile_panel)

func _close_profile_panel() -> void:
	await _undock_panel(profile_panel)

func _refresh_profile() -> void:
	if profile_tabs == null:
		return
	_apply_profile_tab_titles()
	_refresh_profile_current_life_tab(tab_life)
	_refresh_profile_biography_tab(tab_bio)
	_refresh_profile_collection_tab(tab_collection)
	_refresh_profile_history_tab(tab_history)

# Tab 1：现在的人生
func _refresh_profile_current_life_tab(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	container.add_theme_constant_override("separation", LIFE_SECTION_GAP)

	var zh := current_language == "zh"
	var realm: Dictionary = realms[state["realm_index"]]

	# ── 上方两栏：基本信息 ｜ 修炼状态 ──
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", LIFE_SECTION_GAP)

	# ① 基本信息
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _life_card_stylebox())
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var info_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		info_margin.add_theme_constant_override("margin_%s" % side, LIFE_CARD_PADDING)
	info_panel.add_child(info_margin)
	var info_vb := _build_life_section_header("res://assets/ui/icon_info.png", "基本信息", "Basic Info")
	info_margin.add_child(info_vb)

	info_vb.add_child(_build_icon_label_value_row("realm", "境界" if zh else "Realm",
		realm["name"] if zh else realm_names_en[state["realm_index"]]))
	info_vb.add_child(_build_icon_label_value_row("personality", "性情" if zh else "Personality",
		PERSONALITY_META.get(current_personality, {}).get("zh" if zh else "en", "未知")))
	info_vb.add_child(_build_icon_label_value_row("job", "职业" if zh else "Job",
		_mortal_job_label(state.get("mortal_job", ""), zh) if String(state.get("mortal_job", "")) != "" else ("无" if zh else "None")))
	if current_tier() != "凡人":
		var root_text: String = state["spiritual_root"] if String(state.get("spiritual_root", "")) != "" else "未觉醒"
		if not zh:
			root_text = state.get("spiritual_root_en", "Not awakened")
		info_vb.add_child(_build_icon_label_value_row("root", "灵根" if zh else "Root", root_text))
	info_vb.add_child(_build_icon_label_value_row("luck", "气运" if zh else "Luck",
		("%s（%d）" % [luck_tier(), int(state["luck"])]) if zh else ("%s (%d)" % [luck_tier_en(), int(state["luck"])])))
	info_vb.add_child(_build_icon_label_value_row("lifespan", "寿元" if zh else "Lifespan",
		("%d年" % int(state["lifespan"])) if zh else ("%d years" % int(state["lifespan"]))))
	info_vb.add_child(_build_icon_label_value_row("life_count", "第" if zh else "Life",
		("%d 世" % int(state.get("life_count", 1))) if zh else ("Life %d" % int(state.get("life_count", 1)))))
	var perk_name: String = String(active_reincarnation_perk.get("zh" if zh else "en", "平平无奇" if zh else "Utterly Ordinary"))
	info_vb.add_child(_build_icon_label_value_row("perk", "轮回天赋" if zh else "Perk", perk_name))

	columns.add_child(info_panel)

	# ② 修炼状态 (含天道评价子卡片)
	var cult_panel := PanelContainer.new()
	cult_panel.add_theme_stylebox_override("panel", _life_card_stylebox())
	cult_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cult_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		cult_margin.add_theme_constant_override("margin_%s" % side, LIFE_CARD_PADDING)
	cult_panel.add_child(cult_margin)
	var cult_vb := _build_life_section_header("res://assets/ui/icon_fire.png", "修炼状态", "Cultivation")
	cult_margin.add_child(cult_vb)

	var qi_header := HBoxContainer.new()
	qi_header.add_theme_constant_override("separation", 6)
	var qi_icon := TextureRect.new()
	qi_icon.custom_minimum_size = Vector2(LIFE_ICON_SIZE, LIFE_ICON_SIZE)
	qi_header.add_child(qi_icon)
	var qi_label := Label.new()
	qi_label.text = "修为" if zh else "Cultivation"
	qi_label.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
	qi_label.add_theme_color_override("font_color", LIFE_INK_COLOR)
	qi_header.add_child(qi_label)
	cult_vb.add_child(qi_header)

	var qi_numbers := Label.new()
	qi_numbers.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE + 1)
	qi_numbers.add_theme_color_override("font_color", LIFE_INK_COLOR)
	cult_vb.add_child(qi_numbers)
	qi_numbers_label = qi_numbers

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
	qi_progress_bar = qi_bar

	var qi_pct := Label.new()
	qi_pct.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
	qi_pct.add_theme_color_override("font_color", LIFE_INK_COLOR)
	bar_row.add_child(qi_pct)
	qi_percent_label = qi_pct
	cult_vb.add_child(bar_row)

	var extra_rows := VBoxContainer.new()
	extra_rows.add_theme_constant_override("separation", 6)
	var insight_row := Label.new()
	insight_row.text = ("突破感悟：%d%%" % int(state.get("breakthrough_insight", 0))) if zh \
		else ("Insight: %d%%" % int(state.get("breakthrough_insight", 0)))
	insight_row.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
	insight_row.add_theme_color_override("font_color", LIFE_INK_COLOR)
	extra_rows.add_child(insight_row)
	var stones_row := Label.new()
	stones_row.text = ("灵石：%d" % int(state["spirit_stones"])) if zh else ("Stones: %d" % int(state["spirit_stones"]))
	stones_row.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
	stones_row.add_theme_color_override("font_color", LIFE_INK_COLOR)
	extra_rows.add_child(stones_row)
	var clicks_row := Label.new()
	clicks_row.text = ("点击次数：%d" % int(state.get("click_count", 0))) if zh else ("Clicks: %d" % int(state.get("click_count", 0)))
	clicks_row.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
	clicks_row.add_theme_color_override("font_color", LIFE_INK_COLOR)
	extra_rows.add_child(clicks_row)
	cult_vb.add_child(extra_rows)

	# ③ 天道评价 — nested sub-card inside 修炼状态, matching the mockup
	var quote_panel := PanelContainer.new()
	var quote_sb := StyleBoxFlat.new()
	quote_sb.bg_color = Color(LIFE_CARD_BG.r + 0.01, LIFE_CARD_BG.g + 0.01, LIFE_CARD_BG.b + 0.01, 1.0)
	quote_sb.set_corner_radius_all(8)
	quote_sb.set_border_width_all(1)
	quote_sb.border_color = LIFE_QUOTE_BORDER
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
	quote_title.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
	quote_title.add_theme_color_override("font_color", LIFE_INK_COLOR)
	quote_vb.add_child(quote_title)
	var quote_body := Label.new()
	var perk_desc: String = String(active_reincarnation_perk.get("desc_zh" if zh else "desc_en", ""))
	quote_body.text = perk_desc
	quote_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote_body.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE + 1)
	quote_body.add_theme_color_override("font_color", LIFE_INK_COLOR)
	quote_vb.add_child(quote_body)
	quote_panel.add_child(quote_vb)
	cult_vb.add_child(quote_panel)

	columns.add_child(cult_panel)
	container.add_child(columns)

# Tab 2：人生履历
func _refresh_profile_biography_tab(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	var life_rtl := RichTextLabel.new()
	life_rtl.bbcode_enabled = true
	life_rtl.fit_content = true
	life_rtl.scroll_active = false
	life_rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	life_rtl.custom_minimum_size = Vector2(270, 0)
	life_rtl.add_theme_font_size_override("normal_font_size", PROFILE_BODY_SIZE)
	life_rtl.add_theme_font_size_override("bold_font_size", PROFILE_HEADER_SIZE)
	life_rtl.add_theme_color_override("default_color", Color(0.3, 0.25, 0.35))
	life_rtl.text = build_life_history_text()
	container.add_child(life_rtl)

# Tab 3：成就 & 图鉴
func _refresh_profile_collection_tab(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	# —— 成就 ——
	var ah := Label.new()
	if achievement_manager != null:
		ah.text = ("成就 %d/%d" % [achievement_manager.unlocked_count(), achievement_manager.total_count()]) if current_language == "zh" \
			else ("Achievements %d/%d" % [achievement_manager.unlocked_count(), achievement_manager.total_count()])
	else:
		ah.text = "成就" if current_language == "zh" else "Achievements"
	ah.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	ah.add_theme_font_size_override("font_size", PROFILE_HEADER_SIZE)
	container.add_child(ah)
	if achievement_manager != null:
		var unlocked_defs = achievement_manager.get_unlocked_defs()
		if unlocked_defs.is_empty():
			var none2 := Label.new()
			none2.text = "暂无成就" if current_language == "zh" else "None yet."
			none2.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			none2.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
			container.add_child(none2)
		else:
			for a in unlocked_defs:
				var al := Label.new()
				var at: String = a["title_zh"] if current_language == "zh" else a["title_en"]
				var ad: String = a["desc_zh"] if current_language == "zh" else a["desc_en"]
				al.text = "  🏆 %s — %s" % [at, ad]
				al.add_theme_color_override("font_color", Color(0.4, 0.32, 0.15))
				al.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
				al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				al.custom_minimum_size = Vector2(270, 0)
				container.add_child(al)
	# —— 图鉴 ——
	container.add_child(HSeparator.new())
	var dc := Label.new()
	dc.text = ("☠️ 死因图鉴   %d / %d" % [discovered_death_causes.size(), DataLoader.death_causes.size()]) if current_language == "zh" \
		else ("☠️ Death Codex   %d / %d" % [discovered_death_causes.size(), DataLoader.death_causes.size()])
	dc.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	dc.add_theme_font_size_override("font_size", PROFILE_HEADER_SIZE)
	container.add_child(dc)
	for cause in DataLoader.death_causes:
		var cid: String = String(cause.get("id", ""))
		if discovered_death_causes.has(cid):
			var row_label := Label.new()
			var name_text: String = cause["title_zh"] if current_language == "zh" else cause["title_en"]
			row_label.text = "  ☠️ %s" % name_text
			row_label.add_theme_color_override("font_color", Color(0.45, 0.28, 0.28))
			row_label.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
			row_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row_label.custom_minimum_size = Vector2(260, 0)
			container.add_child(row_label)

	var undiscovered := DataLoader.death_causes.size() - discovered_death_causes.size()
	if undiscovered > 0:
		var hint := Label.new()
		hint.text = ("  还有 %d 种死法等待解锁…" % undiscovered) if current_language == "zh" \
			else ("  %d more ways to die, undiscovered..." % undiscovered)
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		hint.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE - 1)
		container.add_child(hint)

	_profile_add_encounter_codex(container)


# Tab 4：历史记录
func _refresh_profile_history_tab(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

	var history_title_label := Label.new()
	history_title_label.text = "🏆 历史纪录" if current_language == "zh" else "🏆 Records"
	history_title_label.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	history_title_label.add_theme_font_size_override("font_size", PROFILE_HEADER_SIZE)
	container.add_child(history_title_label)

	var record_text := RichTextLabel.new()
	record_text.bbcode_enabled = true
	record_text.fit_content = true
	record_text.scroll_active = false
	record_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_text.custom_minimum_size = Vector2(270, 0)
	record_text.add_theme_font_size_override("normal_font_size", PROFILE_BODY_SIZE)
	record_text.add_theme_color_override("default_color", Color(0.32, 0.27, 0.34))
	record_text.text = build_record_summary_text()
	container.add_child(record_text)

	container.add_child(HSeparator.new())

	var rh := Label.new()
	rh.text = "轮回记录" if current_language == "zh" else "Reincarnations"
	rh.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	rh.add_theme_font_size_override("font_size", PROFILE_HEADER_SIZE)
	container.add_child(rh)

	if not reincarnation_history.is_empty():
		var rh_rtl := RichTextLabel.new()
		rh_rtl.bbcode_enabled = true
		rh_rtl.fit_content = true
		rh_rtl.scroll_active = false
		rh_rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rh_rtl.custom_minimum_size = Vector2(270, 0)
		rh_rtl.add_theme_font_size_override("normal_font_size", PROFILE_BODY_SIZE)
		rh_rtl.add_theme_font_size_override("bold_font_size", PROFILE_BODY_SIZE)
		rh_rtl.add_theme_color_override("default_color", Color(0.4, 0.3, 0.3))
		rh_rtl.text = build_reincarnation_history_text()
		container.add_child(rh_rtl)

	elif death_history.is_empty():
		var none := Label.new()
		none.text = "第一世进行中……" if current_language == "zh" else "Life 1 in progress..."
		none.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		none.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
		container.add_child(none)

	else:
		var start = max(0, death_history.size() - 20)
		for i in range(death_history.size() - 1, start - 1, -1):
			var death_record = death_history[i]
			var hr_zh: String = realms[int(death_record["highest_realm"])]["name"]
			var hr_en: String = realm_names_en[int(death_record["highest_realm"])]
			var entry := Label.new()

			if current_language == "zh":
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
			entry.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
			entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			entry.custom_minimum_size = Vector2(270, 0)
			container.add_child(entry)

var qi_progress_bar: ProgressBar
var qi_numbers_label: Label
var qi_percent_label: Label

func _update_profile_detail_live() -> void:
	if profile_panel == null or not profile_panel.visible:
		return
	if qi_progress_bar == null:
		return
	var realm: Dictionary = realms[state["realm_index"]]
	var need: float = float(realm["need"])
	var cur: float = float(state["cultivation"])
	qi_progress_bar.max_value = need
	qi_progress_bar.value = cur
	if qi_numbers_label != null:
		qi_numbers_label.text = "%d / %d" % [int(cur), int(need)]
	if qi_percent_label != null:
		var pct: float = (cur / need) * 100.0 if need > 0 else 0.0
		qi_percent_label.text = "%.2f%%" % pct

func build_record_summary_text() -> String:
	var zh: bool = current_language == "zh"

	var highest_idx: int = _record_highest_realm_index()
	var highest_name: String = ""
	if zh:
		highest_name = String(realms[highest_idx].get("name", "未知"))
	else:
		highest_name = String(realm_names_en[highest_idx])

	var longest_age: int = _record_longest_lifespan()
	var life_count: int = int(state.get("life_count", 1))
	var reincarnations: int = maxi(0, life_count - 1)
	var death_count: int = death_history.size()
	var pill_count := int(state.get("pills_total_lifetime", 0))

	var death_cause_found: int = discovered_death_causes.size()
	var death_cause_total: int = DataLoader.death_causes.size()
	var encounter_found: int = discovered_encounters.size()

	var encounter_total: int = 120
	if event_manager != null:
		encounter_total = int(event_manager.total_encounters())

	var most_common: Dictionary = _record_most_common_death_cause()
	var worst_text: String = _record_worst_death_text()

	var lines := PackedStringArray()

	if zh:
		lines.append("[b]最高境界：[/b]%s" % highest_name)
		lines.append("[b]最长寿命：[/b]%d岁" % longest_age)
		lines.append("[b]轮回次数：[/b]%d次" % reincarnations)
		lines.append("[b]死亡次数：[/b]%d次" % death_count)
		var breakthrough_success := int(state.get("breakthrough_success_total_lifetime", 0))
		var breakthrough_fail    := int(state.get("breakthrough_fail_total_lifetime", 0))
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
		lines.append("[b]传说奇遇：[/b]%d次" % int(legendary_encounter_count))
	else:
		lines.append("[b]Highest Realm:[/b] %s" % highest_name)
		lines.append("[b]Longest Life:[/b] Age %d" % longest_age)
		lines.append("[b]Reincarnations:[/b] %d" % reincarnations)
		lines.append("[b]Deaths:[/b] %d" % death_count)
		var breakthrough_success := int(state.get("breakthrough_success_total_lifetime", 0))
		var breakthrough_fail    := int(state.get("breakthrough_fail_total_lifetime", 0))
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
		lines.append("[b]Legendary Encounters:[/b] %d" % int(legendary_encounter_count))

	return "\n".join(lines)


func _record_highest_realm_index() -> int:
	var highest := int(state.get("realm_index", 0))
	for d in death_history:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		highest = max(highest, int(d.get("highest_realm", 0)))
	return clampi(highest, 0, realms.size() - 1)


func _record_longest_lifespan() -> int:
	var longest := _current_age()
	for d in death_history:
		if typeof(d) == TYPE_DICTIONARY and d.has("age"):
			longest = max(longest, int(d.get("age", 0)))
	for rec in life_records:
		if typeof(rec) == TYPE_DICTIONARY and String(rec.get("type", "")) == "death":
			longest = max(longest, int(rec.get("age", 0)))
	for raw_entry in life_history:
		var entry := normalize_life_history_entry(raw_entry)
		if String(entry.get("category", "")) == "death":
			longest = max(longest, int(entry.get("age", 0)))
	return longest

func _record_most_common_death_cause() -> Dictionary:
	var counts := {}
	var labels_zh := {}
	var labels_en := {}

	for d in death_history:
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
	var zh := current_language == "zh"
	if death_history.is_empty():
		return "暂无惨案" if zh else "None yet"

	var thunder_streak := _record_longest_death_keyword_streak(["雷", "渡劫", "天劫"], ["thunder", "tribulation", "lightning"])
	if thunder_streak >= 2:
		return ("连续被雷劈 %d 次" % thunder_streak) if zh else ("Struck by tribulation %d lives in a row" % thunder_streak)

	var common := _record_most_common_death_cause()
	if int(common.get("count", 0)) >= 2:
		return ("%s ×%d" % [common.get("text_zh", ""), int(common.get("count", 0))]) if zh else ("%s ×%d" % [common.get("text_en", ""), int(common.get("count", 0))])

	var last = death_history.back()
	if typeof(last) == TYPE_DICTIONARY:
		return String(last.get("cause_zh", "未知死因")) if zh else String(last.get("cause_en", "Unknown death"))
	return "未知死因" if zh else "Unknown death"


func _record_longest_death_keyword_streak(zh_keywords: Array, en_keywords: Array) -> int:
	var current := 0
	var best := 0
	for d in death_history:
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


func _record_contains_any(text: String, keywords: Array) -> bool:
	for k in keywords:
		if text.contains(String(k)):
			return true
	return false

func _profile_add_encounter_codex(container: VBoxContainer) -> void:
	container.add_child(HSeparator.new())
	var ch := Label.new()
	var found := discovered_encounters.size()
	var total := event_manager.total_encounters() if event_manager != null else 40
	ch.text = ("📚 奇遇图鉴   已发现 %d / %d" % [found, total]) if current_language == "zh" \
		else ("📚 Encounter Codex   %d / %d" % [found, total])
	ch.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	ch.add_theme_font_size_override("font_size", PROFILE_HEADER_SIZE)
	container.add_child(ch)
	if event_manager == null:
		return

	for ev in event_manager.get_all_encounter_defs():
		var eid: String = ev["event_id"]
		if not discovered_encounters.has(eid):
			continue
		var rarity: String = ev.get("rarity", "rare")
		var icon := "✨" if rarity == "rare" else "🌟"
		var row_label := Label.new()
		var encounter_name: String = ev["text_zh"] if current_language == "zh" else ev["text_en"]
		row_label.text = "  %s %s" % [icon, encounter_name]
		row_label.add_theme_color_override("font_color",
			Color(0.85, 0.7, 0.2) if rarity == "legendary" else Color(0.5, 0.45, 0.2))
		row_label.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE)
		row_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_label.custom_minimum_size = Vector2(260, 0)
		container.add_child(row_label)

	var undiscovered := total - found
	if undiscovered > 0:
		var hint := Label.new()
		hint.text = ("  还有 %d 个奇遇等待发现…" % undiscovered) if current_language == "zh" \
			else ("  %d more encounters yet to discover..." % undiscovered)
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		hint.add_theme_font_size_override("font_size", PROFILE_BODY_SIZE - 1)
		container.add_child(hint)

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
		get_window().size = WIN_WIDE
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

	var end_pos := Vector2(win.x - ts.x - REPORT_MARGIN, target_y)

	# 从窗口右侧外面滑进来，不再从上方下来
	var start_pos := Vector2(win.x + 16.0, target_y)

	toast_panel.position = start_pos

	var tw := create_tween().set_parallel(true)
	tw.tween_property(toast_panel, "position", end_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(toast_panel, "modulate", Color(1,1,1,1), 0.25)
	await tw.finished

	await get_tree().create_timer(TOAST_SECS).timeout

	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(toast_panel, "position", start_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.tween_property(toast_panel, "modulate", Color(1,1,1,0), 0.3)
	await tw2.finished
	toast_panel.visible = false

	# 只有没有任何大面板打开时，toast 结束才缩回普通窗口
	if not _has_open_wide_panel():
		get_window().size = WIN_NORMAL

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

	save_game()
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
		_refresh_shop()
	if report_panel != null and report_panel.visible:
		_refresh_reports()
	if profile_panel != null and profile_panel.visible:
		_refresh_profile()
	state["language"] = current_language
	save_game()
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

	# Toast — gold for rare, bigger for legendary
	if rarity == "legendary":
		AudioManager.play_legendary()
		_record_memorable_event(eid, ev["text_zh"], ev["text_en"], "")
		_show_toast("🌟 传说奇遇", "🌟 Legendary Encounter", [
			{"zh": ev["text_zh"], "en": ev["text_en"]}
		])
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
	save_game()
func _current_age() -> int:
	return int(state.get("cultivation_age", 16))

func _years_for_breakthrough(realm_index: int) -> int:
	if realm_index <= 2:   return randi_range(8, 18)      # 凡人 tier: small age jumps
	elif realm_index <= 4: return randi_range(20, 45)     # 武者 tier
	elif realm_index <= 6: return randi_range(60, 120)    # 先天 tier
	else:                  return randi_range(150, 300)  # 炼气 tier: huge jumps

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
		_refresh_profile()

	save_game()

func add_recent_event(zh: String, en: String, type: String, desc_zh: String = "", desc_en: String = "") -> void:
	recent_events.append({
		"time": Time.get_time_string_from_system().substr(0, 5),
		"zh": zh, "en": en, "type": type,
		"desc_zh": desc_zh, "desc_en": desc_en
	})
	if recent_events.size() > 200:
		recent_events.pop_front()
	if report_panel != null and report_panel.visible:
		_refresh_reports()
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
	return ROOT_MULTIPLIERS.get(tier, 1.0)
	
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
	var pool: Array = SPIRITUAL_ROOTS[tier]
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

func _pick_life_title() -> Dictionary:
	var clicks: int = int(state.get("life_click_count", 0))
	var fails: int = int(state.get("life_breakthrough_fails", 0))
	var successes: int = int(state.get("life_breakthrough_success", 0))
	var pills_eaten: int = int(state.get("life_pills_eaten", 0))
	var legendary: int = int(state.get("life_legendary_count", 0))
	var rare: int = int(state.get("life_rare_count", 0))
	var age: int = _current_age()

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

const CERT_SIZE := Vector2(560, 420)   # 与底图 4:3 完全同比
# 底图各留白框换算到 560×420 后的区域（原图坐标 × 560/1024）
const CERT_TITLE_RECT   := Rect2(153, 30, 254, 56)    # 顶部横匾：标题
const CERT_LEFT_RECT    := Rect2(48, 122, 132, 248)   # 左侧长框：基本信息
const CERT_WITNESS_RECT := Rect2(382, 122, 140, 158)  # 右上框：天地鉴证（punchline）
const CERT_ISSUE_RECT   := Rect2(382, 306, 84, 70)    # 右下框：签发（避开红印）
const CERT_SEAL_RECT    := Rect2(252, 342, 50, 48)    # 中下红印框 → 留影按钮
const CERT_INK  := Color(0.32, 0.24, 0.14)
const CERT_GOLD := Color(0.55, 0.42, 0.18)
const CERT_RED  := Color(0.68, 0.18, 0.13)

func _build_certificate_panel() -> void:
	certificate_panel = Control.new()
	certificate_panel.name = "CertificatePanel"
	certificate_panel.custom_minimum_size = CERT_SIZE
	certificate_panel.size = CERT_SIZE
	certificate_panel.visible = false
	certificate_panel.z_index = 300
	certificate_panel.top_level = true
	add_child(certificate_panel)

	# 背景整图（与面板同为4:3，直接铺满）
	cert_bg = TextureRect.new()
	cert_bg.texture = load("res://assets/ui/death_certificate_panel.png")
	cert_bg.stretch_mode = TextureRect.STRETCH_SCALE
	cert_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cert_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cert_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	certificate_panel.add_child(cert_bg)

	# 顶部标题
	cert_title_label = Label.new()
	cert_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cert_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cert_title_label.add_theme_font_size_override("font_size", 20)
	cert_title_label.add_theme_color_override("font_color", CERT_INK)
	cert_title_label.position = CERT_TITLE_RECT.position
	cert_title_label.size = CERT_TITLE_RECT.size
	certificate_panel.add_child(cert_title_label)

	# 左栏：基本信息
	cert_left_vbox = VBoxContainer.new()
	cert_left_vbox.add_theme_constant_override("separation", 3)
	cert_left_vbox.position = CERT_LEFT_RECT.position
	cert_left_vbox.size = CERT_LEFT_RECT.size
	certificate_panel.add_child(cert_left_vbox)

	# 右上：天地鉴证（punchline 专区）
	cert_witness_vbox = VBoxContainer.new()
	cert_witness_vbox.add_theme_constant_override("separation", 4)
	cert_witness_vbox.position = CERT_WITNESS_RECT.position
	cert_witness_vbox.size = CERT_WITNESS_RECT.size
	certificate_panel.add_child(cert_witness_vbox)

	# 右下：签发区
	cert_issue_vbox = VBoxContainer.new()
	cert_issue_vbox.add_theme_constant_override("separation", 2)
	cert_issue_vbox.position = CERT_ISSUE_RECT.position
	cert_issue_vbox.size = CERT_ISSUE_RECT.size
	certificate_panel.add_child(cert_issue_vbox)

	# 留影按钮：落在中下方的红印框里，像盖章一样
	cert_share_button = Button.new()
	cert_share_button.flat = true
	cert_share_button.text = "留影"
	cert_share_button.add_theme_font_size_override("font_size", 14)
	cert_share_button.add_theme_color_override("font_color", CERT_RED)
	cert_share_button.add_theme_color_override("font_hover_color", Color(0.85, 0.25, 0.18))
	cert_share_button.position = CERT_SEAL_RECT.position
	cert_share_button.size = CERT_SEAL_RECT.size
	cert_share_button.pressed.connect(func():
		cert_share_button.visible = false
		if cert_hint_label != null:
			cert_hint_label.visible = false      # 提示文字也不入镜
		await ShareCapture.share_panel(certificate_panel)
		cert_share_button.visible = true
		if cert_hint_label != null:
			cert_hint_label.visible = true
	)
	certificate_panel.add_child(cert_share_button)

	# 底部关闭提示
	cert_hint_label = Label.new()
	cert_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cert_hint_label.add_theme_font_size_override("font_size", 9)
	cert_hint_label.add_theme_color_override("font_color", Color(0.55, 0.48, 0.38, 0.8))
	cert_hint_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cert_hint_label.position.y = CERT_SIZE.y - 20.0
	cert_hint_label.size.x = CERT_SIZE.x
	certificate_panel.add_child(cert_hint_label)

	certificate_panel.gui_input.connect(func (e):
		if e is InputEventMouseButton and e.pressed:
			certificate_panel.visible = false
			_certificate_open = false
	)


# ── 小工具 ──
func _cert_clear(vb: VBoxContainer) -> void:
	for child in vb.get_children():
		child.queue_free()

func _cert_add_field(vb: VBoxContainer, label_text: String, value_text: String) -> void:
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", CERT_GOLD)
	vb.add_child(l)
	var v := Label.new()
	v.text = value_text
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", CERT_INK)
	vb.add_child(v)

func _cert_add_text(vb: VBoxContainer, text: String, size: int, color: Color, center := false) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	vb.add_child(l)


func _show_reincarnation_certificate(cause_zh: String, cause_en: String, life_num: int, highest_realm_idx: int, punchline: Dictionary = {}) -> void:
	_enter_certificate_mode()   # 内部第一行就置 _certificate_open = true，后面 await 安全
	var zh := current_language == "zh"

	if toast_panel != null:
		toast_panel.visible = false
		toast_showing = false
		toast_queue.clear()
	if bubble_panel != null:
		bubble_panel.visible = false
	if bubble_tail != null:
		bubble_tail.visible = false
	if status_label != null:
		status_label.visible = false
	message_queue.clear()
	is_showing_message = false

	# 证书是 560×420 固定尺寸，窗口必须先撑到至少这么大——
	# 否则窗口还是小尺寸时证书会被裁切（就是之前报的那个裁切 bug）。
	var safe_pos := _get_safe_window_position(WIN_WIDE)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = WIN_WIDE
	await get_tree().process_frame

	var title = _pick_life_title()
	var pet_name := String(state.get("pet_name", ""))
	var age: int = _current_age()
	var realm_name: String = realms[highest_realm_idx]["name"] if zh else realm_names_en[highest_realm_idx]

	cert_title_label.text = "轮回证书" if zh else "Certificate of Reincarnation"

	# 左栏
	_cert_clear(cert_left_vbox)
	_cert_add_field(cert_left_vbox, "姓名 Name" if zh else "Name", pet_name)
	_cert_add_field(cert_left_vbox, "此生所达境界" if zh else "Realm Reached", realm_name)
	_cert_add_field(cert_left_vbox, "陨落之龄" if zh else "Age at Death",
		("%d岁" % age) if zh else ("%d" % age))
	_cert_add_field(cert_left_vbox, "陨落之因" if zh else "Cause of Death",
		cause_zh if zh else cause_en)
	_cert_add_field(cert_left_vbox, "临终称号" if zh else "Final Title",
		String(title["zh"]) if zh else String(title["en"]))

	# 右上：天地鉴证 = punchline
	_cert_clear(cert_witness_vbox)
	_cert_add_text(cert_witness_vbox, "天地鉴证" if zh else "Heavens' Witness", 12, CERT_INK, true)
	var punchline_text: String = String(punchline.get("zh","")) if zh else String(punchline.get("en",""))
	if punchline_text == "":
		punchline_text = "此生已了，来世再修。" if zh else "This life is complete; cultivate again in the next."
	_cert_add_text(cert_witness_vbox, punchline_text, 10, CERT_INK)

	# 右下：签发
	_cert_clear(cert_issue_vbox)
	_cert_add_text(cert_issue_vbox, "证书签发" if zh else "Issued By", 9, CERT_GOLD)
	_cert_add_text(cert_issue_vbox, "天道轮回司" if zh else "Bureau of Samsara", 11, CERT_INK)
	_cert_add_text(cert_issue_vbox,
		("第 %d 世 · 卷宗" % life_num) if zh else ("Life %d · Records" % life_num), 9, CERT_GOLD)

	cert_share_button.text = "留影" if zh else "Save"
	cert_hint_label.text = "（点击任意处关闭）" if zh else "(tap anywhere to close)"

	certificate_panel.visible = true
	var win := get_viewport_rect().size
	certificate_panel.position = (win - CERT_SIZE) / 2.0

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

enum MoodPriority {
	AMBIENT = 0,    # status ticks, dialogue-adjacent flavor — lowest, easily overridden
	EVENT = 1,      # report events, encounters, pet-click reactions — normal gameplay moments
	SYSTEM = 2,     # AFK/lazy, and any future "持续状态" that should hold until cleared
}

var _current_mood_priority: int = MoodPriority.AMBIENT

func request_mood(new_mood: String, priority: int) -> bool:
	if priority < _current_mood_priority:
		return false   # a higher-priority mood is already active; ignore this request
	_current_mood_priority = priority
	set_mood(new_mood)
	return true

func clear_mood_priority() -> void:
	_current_mood_priority = MoodPriority.AMBIENT

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


func _life_card_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = LIFE_CARD_BG
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = LIFE_CARD_BORDER
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
	title_label.text = title_zh if current_language == "zh" else title_en
	title_label.add_theme_font_size_override("font_size", PROFILE_HEADER_SIZE)
	title_label.add_theme_color_override("font_color", LIFE_INK_COLOR)
	header_row.add_child(title_label)
	vb.add_child(header_row)

	var rule := HSeparator.new()
	var rule_style := StyleBoxLine.new()
	rule_style.color = LIFE_GOLD_COLOR
	rule_style.thickness = 1
	rule.add_theme_stylebox_override("separator", rule_style)
	vb.add_child(rule)

	return vb

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

			get_window().size = WIN_NORMAL
			await get_tree().process_frame
			update_layout()
			_reposition_overlay_panels()
	)

func _show_intro_sequence(cultivator_name: String, reincarnated: bool = false) -> void:
	for child in intro_panel.get_children():
		child.queue_free()
	var safe_pos := _get_safe_window_position(WIN_WIDE)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = WIN_WIDE
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
	request_mood("normal", MoodPriority.SYSTEM)
	if event_manager != null:
		event_manager.set_paused(true)
	intro_panel.size = Vector2.ZERO
	await get_tree().process_frame
	var win := get_viewport_rect().size
	intro_panel.position = (win - intro_panel.size) / 2.0


# ════════════════════════════════════════════
#  死因 → 死亡动画 映射
# ════════════════════════════════════════════


func _death_anim_for_cause(cause: Dictionary) -> String:
	# 1) CSV里 animation 这一列填了就直接用（现在的权威数据源）
	var csv_anim := String(cause.get("animation", "")).strip_edges()
	if csv_anim != "":
		return csv_anim

	# 2) 关键词兜底（按中文死因标题 / type 猜）——只给"忘了填animation列"的死因用
	var ctype := String(cause.get("type", ""))
	var title := String(cause.get("title_zh", ""))
	if title.find("渡劫") != -1 or title.find("雷") != -1 or title.find("天劫") != -1 or ctype == "tribulation":
		return "death_tribulation"
	if title.find("爆") != -1 or title.find("炸") != -1 or title.find("走火") != -1 or title.find("入魔") != -1 or title.find("烤") != -1 or ctype == "explosion":
		return "death_explosion"
	if title.find("寿") != -1 or title.find("老") != -1 or title.find("年迈") != -1 or ctype == "old" or ctype == "natural":
		return "death_old"

	# 3) 默认：安详老死
	return "death_old"
 
 
func _play_death_animation(cause: Dictionary) -> String:
	var base_anim := _death_anim_for_cause(cause)
	var tier := current_tier()
	var suffix: String = TIER_ANIM_SUFFIX.get(tier, "")
	var tiered_anim := "%s_%s" % [suffix, base_anim]
	_current_mood_priority = MoodPriority.SYSTEM
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
		request_mood("confused", MoodPriority.SYSTEM)
		return ""
	
func _death_anim_duration(anim: String) -> float:
	if anim == "" or cultivator_sprite == null or cultivator_sprite.sprite_frames == null:
		return 0.0
	var sf: SpriteFrames = cultivator_sprite.sprite_frames
	if not sf.has_animation(anim):
		return 0.0
	var speed := sf.get_animation_speed(anim)
	if speed <= 0.0:
		return 2.0
	return float(sf.get_frame_count(anim)) / speed   # 16帧 / 7.7 ≈ 2.08秒

# ════════════════════════════════════════════
#  人生履历分类美化系统  (life_history)
# ════════════════════════════════════════════

# 记录一条人生履历。category 见 LIFE_HISTORY_CATEGORY_ORDER。
func add_life_history(category: String, title_zh: String, description_zh: String = "",
		title_en: String = "", description_en: String = "") -> void:
	if not LIFE_HISTORY_CATEGORY_META.has(category):
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
	if life_history.size() > LIFE_HISTORY_STORE_CAP:
		life_history.pop_front()
	if profile_panel != null and profile_panel.visible:
		_refresh_profile()

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
func build_life_history_text() -> String:
	var zh := current_language == "zh"
	var current_life_num := int(state.get("life_count", 1))

	# Chapter-keyed grouping: chapter_id -> Array of normalized entries
	var by_chapter: Dictionary = {}
	for chapter in LIFE_CHAPTERS:
		by_chapter[chapter["id"]] = []

	for raw_entry in life_history:
		var entry := normalize_life_history_entry(raw_entry)
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

	for chapter in LIFE_CHAPTERS:
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
		for cat in LIFE_HISTORY_CATEGORY_ORDER:
			grouped_in_chapter[cat] = []
		for entry in entries:
			var cat: String = entry.get("category", "encounter")
			if not grouped_in_chapter.has(cat):
				grouped_in_chapter[cat] = []
			grouped_in_chapter[cat].append(entry)

		for cat in LIFE_HISTORY_CATEGORY_ORDER:
			var cat_entries: Array = grouped_in_chapter.get(cat, [])
			if cat_entries.is_empty():
				continue
			var meta: Dictionary = LIFE_HISTORY_CATEGORY_META.get(cat, LIFE_HISTORY_CATEGORY_META["encounter"])
			var icon: String = meta.get("icon", "✨")
			var start_index: int = max(0, cat_entries.size() - LIFE_HISTORY_MAX_PER_CATEGORY)
			for i in range(start_index, cat_entries.size()):
				text += "  %s " % icon + format_life_history_entry(cat_entries[i])

		text += "\n"

	return text.strip_edges()

# 单条履历：第几世｜年龄｜境界｜标题（：描述）
func format_life_history_entry(entry: Dictionary) -> String:
	var zh := current_language == "zh"
	var life_num: int = int(entry.get("life", 1))
	var entry_age: int = int(entry.get("age", 0))
	var realm_idx: int = int(entry.get("realm_index", 0))
	var realm: String = realms[realm_idx]["name"] if zh else realm_names_en[realm_idx]
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

func _demo_force_death_if_due() -> bool:
	if not DEMO_MODE:
		return false
	if int(state.get("life_count", 1)) > DEMO_FORCED_DEATHS:
		return false
	if state["realm_index"] < DEMO_DEATH_AT_REALM:
		return false
	state["lifespan"] = 0
	await check_lifespan()   # 死亡动画 + 轮回证书 + 转世
	return true

func _chapter_blurb(_chapter_id: String, entries: Array) -> String:
	var zh := current_language == "zh"
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
	
# ══════════════════════════════════════════
#  轮回天赋系统 (reincarnation perks)
# ══════════════════════════════════════════

func get_default_reincarnation_modifiers() -> Dictionary:
	return {
		"cultivation_mult": 1.0, "breakthrough_bonus": 0.0, "lifespan_bonus": 0,
		"starting_luck_bonus": 0, "pill_effect_mult": 1.0, "pill_risk_mult": 1.0,
		"failure_penalty_delta": 0, "stone_keep_bonus": 0.0, "encounter_luck_bonus": 0.0
	}

func get_active_perk_modifiers() -> Dictionary:
	var mods := get_default_reincarnation_modifiers()
	if typeof(active_reincarnation_perk) == TYPE_DICTIONARY:
		var pm = active_reincarnation_perk.get("modifiers", {})
		if typeof(pm) == TYPE_DICTIONARY:
			for k in pm.keys():
				mods[k] = pm[k]
	return mods

func apply_reincarnation_perk(perk: Dictionary) -> void:
	active_reincarnation_perk = perk if typeof(perk) == TYPE_DICTIONARY else {}
	reincarnation_modifiers = get_active_perk_modifiers()

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

# 越靠前越优先；爆炸放在丹药前面，因为「炸炉」类死因同时含「丹」和「炸」。
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

func build_current_perk_text() -> String:
	var zh := current_language == "zh"
	if active_reincarnation_perk.is_empty():
		return "轮回天赋：平平无奇" if zh else "Reincarnation Perk: Utterly Ordinary"
	var pn := String(active_reincarnation_perk.get("zh","")) if zh else String(active_reincarnation_perk.get("en",""))
	var pd := String(active_reincarnation_perk.get("desc_zh","")) if zh else String(active_reincarnation_perk.get("desc_en",""))
	return ("轮回天赋：%s\n%s" % [pn, pd]) if zh else ("Reincarnation Perk: %s\n%s" % [pn, pd])

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

func generate_life_summary(cause: Dictionary, _title: Dictionary) -> Dictionary:
	var fails := int(state.get("life_breakthrough_fails", 0))
	var success := int(state.get("life_breakthrough_success", 0))
	var pills_eaten := int(state.get("life_pills_eaten", 0))
	var clicks := int(state.get("life_click_count", 0))
	var age := _current_age()
	var highest := int(state.get("highest_realm_this_life", 0))
	var legendary := int(state.get("life_legendary_count", 0))
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

func add_reincarnation_history_record(cause: Dictionary, title: Dictionary, perk: Dictionary) -> void:
	var data := collect_current_life_data(cause, title)
	var summary := generate_life_summary(cause, title)
	data["summary_zh"] = summary["zh"]
	data["summary_en"] = summary["en"]
	data["punchline_zh"] = _last_death_punchline.get("zh", "")
	data["punchline_en"] = _last_death_punchline.get("en", "")
	data["perk_id"] = String(perk.get("id","")) if typeof(perk) == TYPE_DICTIONARY else ""
	data["perk_zh"] = String(perk.get("zh","")) if typeof(perk) == TYPE_DICTIONARY else ""
	data["perk_en"] = String(perk.get("en","")) if typeof(perk) == TYPE_DICTIONARY else ""
	data["time"] = Time.get_datetime_string_from_system()
	reincarnation_history.append(data)
	if reincarnation_history.size() > 100:
		reincarnation_history.pop_front()

func build_reincarnation_history_text() -> String:
	var zh := current_language == "zh"
	if reincarnation_history.is_empty():
		return ""

	# Group completed lives by which chapter they peaked in.
	var by_chapter: Dictionary = {}
	for chapter in LIFE_CHAPTERS:
		by_chapter[chapter["id"]] = []

	var start := maxi(0, reincarnation_history.size() - 10)
	for i in range(reincarnation_history.size() - 1, start - 1, -1):
		var r = reincarnation_history[i]
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var chapter := _chapter_for_life_record(r)
		by_chapter[chapter["id"]].append(r)

	var text := ""
	# Reverse chapter order: most-advanced era first, since that's usually
	# what a returning player wants to see — "how far did past lives get."
	for ci in range(LIFE_CHAPTERS.size() - 1, -1, -1):
		var chapter: Dictionary = LIFE_CHAPTERS[ci]
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

func _resolve_mood_anim(m: String) -> String:
	if cultivator_sprite == null or cultivator_sprite.sprite_frames == null:
		return ""
	var base_anim: String = anim_for_mood.get(m, "breath")
	var tier := current_tier()
	var suffix: String = TIER_ANIM_SUFFIX.get(tier, "")
	var tiered := "%s_%s" % [suffix, base_anim]
	if suffix != "" and cultivator_sprite.sprite_frames.has_animation(tiered):
		return tiered
	elif cultivator_sprite.sprite_frames.has_animation(base_anim):
		return base_anim
	return ""

func _on_event_special_animation(anim_key: String) -> void:
	if anim_key == "" or cultivator_sprite == null or cultivator_sprite.sprite_frames == null:
		return
	var tier := current_tier()
	var suffix: String = TIER_ANIM_SUFFIX.get(tier, "")
	var tiered_anim := "%s_%s" % [suffix, anim_key]
	var anim_to_play := ""
	if suffix != "" and cultivator_sprite.sprite_frames.has_animation(tiered_anim):
		anim_to_play = tiered_anim
	elif cultivator_sprite.sprite_frames.has_animation(anim_key):
		anim_to_play = anim_key
	else:
		return   # 这个特殊动画素材还没画，安静跳过，不影响事件本身的奖励/文字
	_current_mood_priority = MoodPriority.SYSTEM
	cultivator_sprite.position.x = 0
	cultivator_sprite.play(anim_to_play)
	var dur := _death_anim_duration(anim_to_play)
	await get_tree().create_timer(max(dur, 1.0) + 0.1).timeout
	clear_mood_priority()
	request_mood("normal", MoodPriority.AMBIENT)


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
	var headline: Dictionary = HEADLINE_TEMPLATES.get(highlight_tag, HEADLINE_TEMPLATES["none"])
	var highlight_text: Dictionary
	if not today_memory.is_empty():
		highlight_text = {"zh": String(today_memory.get("title_zh","")), "en": String(today_memory.get("title_en",""))}
	else:
		highlight_text = _highlight_text_for_tag(highlight_tag)
		
	var fortune_zh := "%s（%d）" % [luck_tier(), int(state["luck"])]
	var fortune_en := "%s (%d)" % [luck_tier_en(), int(state["luck"])]

	var rumour_pool := DataLoader.rumours.filter(func(r): return r["realm"] == "" or r["realm"] == current_tier())
	if rumour_pool.is_empty(): rumour_pool = DataLoader.rumours
	var legendary_rumour := _legendary_past_life_rumour()
	if not legendary_rumour.is_empty() and randf() < 0.15:
		rumour_pool = [legendary_rumour]
	var rumour: Dictionary = rumour_pool.pick_random() if not rumour_pool.is_empty() else {"zh":"","en":""}
	
	var hint := _tomorrow_hint_text()

	var achievement_zh := "无" if _achievement_unlocked_today.is_empty() else ", ".join(_achievement_unlocked_today.keys())
	var achievement_en := "None" if _achievement_unlocked_today.is_empty() else "Unlocked today"

	var nb_pool := DataLoader.neighbour_comments.filter(func(r):
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
func _enter_certificate_mode() -> void:
	_certificate_open = true

	# 关掉所有普通面板
	if profile_panel != null:
		profile_panel.visible = false
	if report_panel != null:
		report_panel.visible = false
	if shop_panel != null:
		shop_panel.visible = false

	# 关掉气泡 / 状态 / toast
	if bubble_panel != null:
		bubble_panel.visible = false
	if bubble_tail != null:
		bubble_tail.visible = false
	if status_label != null:
		status_label.visible = false
	if toast_panel != null:
		toast_panel.visible = false

	toast_showing = false
	toast_queue.clear()
	message_queue.clear()
	is_showing_message = false

	# 关掉底部按钮，保留角色本体也可以
	if $PetGroup/VBox != null:
		$PetGroup/VBox.visible = false

	# 暂停随机事件，避免证书期间又弹东西
	if event_manager != null:
		event_manager.set_paused(true)

func _chapter_for_life_record(r: Dictionary) -> Dictionary:
	var realm_idx: int = int(r.get("highest_realm", 0))
	var age: int = int(r.get("age", 0))
	return _chapter_for_entry(realm_idx, age)
	
func _chapter_for_entry(realm_idx: int, age: int) -> Dictionary:
	for chapter in LIFE_CHAPTERS:
		var min_r: int = int(chapter.get("min_realm_index", 0))
		var max_r: int = int(chapter.get("max_realm_index", 99))
		if realm_idx < min_r or realm_idx > max_r:
			continue
		if chapter.has("max_age") and age > int(chapter["max_age"]):
			continue
		if chapter.has("min_age") and age < int(chapter["min_age"]):
			continue
		return chapter
	return LIFE_CHAPTERS.back()   # fallback: last-defined chapter, never crash on an edge case

func _pick_last_words(cause: Dictionary) -> Dictionary:
	var anim_key: String = String(cause.get("animation", "")).strip_edges()
	var pool := DataLoader.last_words.filter(func(r): return r["cause_type"] == anim_key)
	if pool.is_empty():
		pool = DataLoader.last_words.filter(func(r): return r["cause_type"] == "generic")
	if pool.is_empty():
		return {"zh": "", "en": ""}
	var picked: Dictionary = pool.pick_random()
	return {"zh": picked["zh"], "en": picked["en"]}
	
func _generate_death_punchline(cause: Dictionary, life_title: Dictionary, final_words: Dictionary) -> Dictionary:
	var pet_name: String = String(state.get("pet_name", ""))
	var age: int = _current_age()
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

func _record_memorable_event(tag: String, title_zh: String, title_en: String, chain_id: String = "") -> void:
	memorable_events.append({
		"tag": tag, "age": _current_age(),
		"title_zh": title_zh, "title_en": title_en, "chain_id": chain_id
	})
	if memorable_events.size() > MEMORABLE_EVENTS_CAP:
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

	save_game()

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

	while memorable_events.size() > MEMORABLE_EVENTS_CAP:
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

func _recent_life_milestones(count: int) -> Array:
	var current_life_num := int(state.get("life_count", 1))
	var this_life: Array = []
	for raw_entry in life_history:
		var entry := normalize_life_history_entry(raw_entry)
		if int(entry.get("life", current_life_num)) == current_life_num:
			this_life.append(entry)
	var start: int = max(0, this_life.size() - count)
	var out: Array = []
	for i in range(this_life.size() - 1, start - 1, -1):
		out.append(this_life[i])
	return out
func _milestone_icon_path(entry: Dictionary) -> String:
	match String(entry.get("category", "")):
		"birth": return "res://assets/ui/icon_milestone_birth.png"
		"skill": return "res://assets/ui/icon_milestone_root.png"
		"breakthrough": return "res://assets/ui/icon_milestone_breakthrough.png"
		"encounter": return "res://assets/ui/icon_milestone_encounter.png"
		"alchemy": return "res://assets/ui/icon_milestone_alchemy.png"
		"death": return "res://assets/ui/icon_milestone_death.png"
		"achievement": return "res://assets/ui/icon_milestone_achievement.png"
		_: return "res://assets/ui/icon_milestone_default.png"
		
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_quit_requested()

func _on_quit_requested() -> void:
	if _quitting:
		get_tree().quit()   # 二次触发直接放行，绝不卡住玩家
		return
	_quitting = true
	save_game()
	var line: Dictionary = FAREWELL_LINES.pick_random()
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
	decision_indicator.position = DECISION_INDICATOR_POS
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
	save_game()
 
 
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
		BUBBLE_ANCHOR_Y - decision_bubble.size.y - BUBBLE_GAP)
 
 
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
	save_game()
 
 
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
 
const DEATH_INTERVAL := 4.0        # 每次死亡间隔秒数（录GIF建议3-5秒）
const SHOW_CERTIFICATE := true     # 是否每次闪一下转世证书
const CERT_FLASH_TIME := 1.2       # 证书停留秒数

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

	if SHOW_CERTIFICATE:
		await get_tree().create_timer(DEATH_INTERVAL - CERT_FLASH_TIME - 0.5).timeout
		# Main.show_certificate_panel()
		await get_tree().create_timer(CERT_FLASH_TIME).timeout
		# Main.hide_certificate_panel()
		# Main.instant_reincarnate()  # 跳过正常转世等待

# 白名单：只轮播表现力最强的死法（按你的 death_causes.csv 实际 id 填）
const FEATURED_DEATHS: Array[String] = []  # 空 = 全池随机

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
	var safe_pos := _get_safe_window_position(WIN_WIDE)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = WIN_WIDE
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
	get_window().size = WIN_NORMAL
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
		x = win.x - panel_size.x - REPORT_MARGIN
	else:
		x = REPORT_MARGIN

	var y := REPORT_Y
	# 垂直方向同理：面板底部若超出窗口，往上收
	if y + panel_size.y > win.y - REPORT_MARGIN:
		y = max(REPORT_MARGIN, win.y - panel_size.y - REPORT_MARGIN)

	return Vector2(x, y)



#---------------------------------------------------------
const QUICK_ICON_SIZE := 56.0        # 屏幕上按钮直径
const QUICK_BAR_Y := 118.0           # 相对角色中心，按钮条的 y（原 VBox 位置附近）
const QUICK_HOVER_MARGIN := 46.0     # 悬停判定区在角色四周的外扩量
const QUICK_FADE := 0.18
 
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
		 "zh": "事件", "en": "Events", "fn": func(): _on_report_pressed()},
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
			tb.custom_minimum_size = Vector2(QUICK_ICON_SIZE, QUICK_ICON_SIZE)
			btn = tb
		else:
			var b := Button.new()
			b.text = d["fallback"]
			b.custom_minimum_size = Vector2(QUICK_ICON_SIZE, QUICK_ICON_SIZE)
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
	var half := Vector2(70, 90) + Vector2(QUICK_HOVER_MARGIN, QUICK_HOVER_MARGIN)
	var zone := Rect2(center - half, half * 2.0)
	# 把按钮条区域并进判定区
	zone = zone.merge(Rect2(
		pet_group.position + Vector2(-110, QUICK_BAR_Y - 10),
		Vector2(220, QUICK_ICON_SIZE + 40)
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
		quick_bar.position = Vector2(-quick_bar.size.x / 2.0, QUICK_BAR_Y)
		_quick_tween = create_tween()
		_quick_tween.tween_property(quick_bar, "modulate:a", 1.0, QUICK_FADE)
	else:
		_quick_tween = create_tween()
		_quick_tween.tween_property(quick_bar, "modulate:a", 0.0, QUICK_FADE)
		_quick_tween.tween_callback(func(): quick_bar.visible = false)
		
const MH_FRAME_SIZE := Vector2(1167, 959)
const WIN_MAIN := Vector2i(1024, 842)          # ≈ frame 比例 (1167/959)
const MH_FONT_PATH := "res://assets/fonts/AaFeiYanShouShu.ttf"
 
# 颜色
const MH_INK      := Color(0.28, 0.20, 0.12)   # 墨色（正文/数值）
const MH_INK_SOFT := Color(0.42, 0.34, 0.24)   # 次级（标签）
const MH_GOLD     := Color(0.60, 0.46, 0.20)   # 分隔线/强调
const MH_GREEN    := Color(0.52, 0.68, 0.34)   # 修为条
const MH_GREEN_BG := Color(0.80, 0.82, 0.68)   # 修为条底
 
# 字号（都是 frame 原始坐标系下的，最后随面板一起缩放）
const MH_FS_SECTION := 30    # 分区标题：基本信息 / 天道评价
const MH_FS_LABEL   := 24    # 字段名
const MH_FS_VALUE   := 24    # 字段值
const MH_FS_NAME    := 30    # 名字牌里的名字
const MH_FS_VERDICT := 30    # 天道评价正文
const MH_FS_CULT    := 34    # 底部修为数字
 
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
	if mh_font == null and ResourceLoader.exists(MH_FONT_PATH):
		mh_font = load(MH_FONT_PATH)
	return mh_font
 
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
	var lab := _mh_label(label_text, MH_FS_LABEL, MH_INK_SOFT)
	lab.custom_minimum_size = Vector2(96, 0)
	row.add_child(lab)
	var val := _mh_label("", MH_FS_VALUE, MH_INK)
	row.add_child(val)
	return [row, val]
 
# 本世记录一行：名称（左）+ 值（右对齐）
func _mh_record_row(name_text: String) -> Array:
	var row := HBoxContainer.new()
	var nm := _mh_label(name_text, MH_FS_LABEL, MH_INK)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	var val := _mh_label("", MH_FS_VALUE, MH_INK)
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
	mh_root.custom_minimum_size = MH_FRAME_SIZE
	mh_root.size = MH_FRAME_SIZE
	main_hall_panel.add_child(mh_root)
 
	# ① 背景框（固定尺寸，不拉伸，保住四角装饰）
	var frame := TextureRect.new()
	var frame_tex := _mh_tex("res://assets/ui/frame_bg.png")
	if frame_tex != null:
		frame.texture = frame_tex
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = MH_FRAME_SIZE
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
		cb.position = Vector2(MH_FRAME_SIZE.x - 130, 40)
		cb.pressed.connect(_close_main_hall)
		mh_root.add_child(cb)
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.custom_minimum_size = Vector2(56, 56)
	close.size = Vector2(56, 56)
	close.position = Vector2(MH_FRAME_SIZE.x - 150, 44)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_close_main_hall)
	mh_root.add_child(close)
 
	_mh_build_name_plate()
	_mh_build_left_panel()
	_mh_build_right_panel()
	_mh_build_cultivation_bar()
 
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
	plate.position = Vector2((MH_FRAME_SIZE.x - pw) / 2.0, 205.0)
	mh_root.add_child(plate)
 
	mh_name_label = _mh_label("", MH_FS_NAME, MH_INK)
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
	card.position = Vector2(88, 210)
	mh_root.add_child(card)
 
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	# 卡内留白（避开描边和四角铆钉）
	vb.position = card.position + Vector2(34, 40)
	vb.custom_minimum_size = Vector2(cw - 68, 0)
	mh_root.add_child(vb)
 
	var head := _mh_label("基本信息", MH_FS_SECTION, MH_INK)
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
	card.position = Vector2(MH_FRAME_SIZE.x - cw - 88, 210)
	mh_root.add_child(card)
 
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.position = card.position + Vector2(34, 40)
	vb.custom_minimum_size = Vector2(cw - 68, 0)
	mh_root.add_child(vb)
 
	# 天道评价
	var head := _mh_label("天道评价", MH_FS_SECTION, MH_INK)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.custom_minimum_size = Vector2(cw - 68, 0)
	vb.add_child(head)
	vb.add_child(_mh_gold_rule(cw - 78))
 
	mh_verdict_label = _mh_label("", MH_FS_VERDICT, MH_INK)
	mh_verdict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mh_verdict_label.custom_minimum_size = Vector2(cw - 78, 0)
	vb.add_child(mh_verdict_label)
 
	# 间隔
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vb.add_child(spacer)
 
	# 本世记录
	var rec_head := _mh_label("本世记录", MH_FS_SECTION, MH_INK)
	vb.add_child(rec_head)
	vb.add_child(_mh_gold_rule(cw - 78))
 
	var t1 = _mh_record_row("修炼时长"); vb.add_child(t1[0]); mh_r_time = t1[1]
	var t2 = _mh_record_row("事件");     vb.add_child(t2[0]); mh_r_events = t2[1]
	var t3 = _mh_record_row("突破");     vb.add_child(t3[0]); mh_r_break = t3[1]
	var t4 = _mh_record_row("死亡");     vb.add_child(t4[0]); mh_r_death = t4[1]
	var t5 = _mh_record_row("奇遇");     vb.add_child(t5[0]); mh_r_encounter = t5[1]
	vb.add_child(_mh_gold_rule(cw - 78))
	var t6 = _mh_record_row("陪伴时间"); vb.add_child(t6[0]); mh_r_companion = t6[1]
 
# ── 底部修为条 ──
func _mh_build_cultivation_bar() -> void:
	var y := MH_FRAME_SIZE.y - 130.0
	var lab := _mh_label("修为", MH_FS_SECTION, MH_INK)
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
 
	mh_cult_pct = _mh_label("", MH_FS_LABEL, MH_INK)
	mh_cult_pct.position = Vector2(300, y + 6)
	mh_cult_pct.size = Vector2(640, 30)
	mh_cult_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mh_cult_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mh_root.add_child(mh_cult_pct)
 
	mh_cult_nums = _mh_label("", MH_FS_CULT, MH_INK)
	mh_cult_nums.position = Vector2(300, y + 44)
	mh_cult_nums.size = Vector2(640, 44)
	mh_cult_nums.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mh_root.add_child(mh_cult_nums)
 
func _mh_gold_rule(w: float) -> Control:
	var line := ColorRect.new()
	line.color = Color(MH_GOLD.r, MH_GOLD.g, MH_GOLD.b, 0.55)
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
	logo.position = Vector2((MH_FRAME_SIZE.x - lw) / 2.0, 70.0)
 
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
 
	var safe_pos := _get_safe_window_position(WIN_MAIN)
	DisplayServer.window_set_position(safe_pos)
	get_window().size = WIN_MAIN
	await get_tree().process_frame
 
	# 整体缩放：frame 原始 1167×959 → 窗口大小
	var sx := float(WIN_MAIN.x) / MH_FRAME_SIZE.x
	var sy := float(WIN_MAIN.y) / MH_FRAME_SIZE.y
	var s: float = min(sx, sy)
	mh_root.scale = Vector2(s, s)
	mh_root.position = Vector2(
		(WIN_MAIN.x - MH_FRAME_SIZE.x * s) / 2.0,
		(WIN_MAIN.y - MH_FRAME_SIZE.y * s) / 2.0
	)
 
	main_hall_panel.visible = true
 
	# 角色移到中央，浮在面板上（名字牌下方、修为条上方）
	pet_group.z_index = 60
	pet_group.position = Vector2(WIN_MAIN.x / 2.0, WIN_MAIN.y * 0.60)
	pet_group.scale = Vector2(1.5, 1.5)   # 大厅里放大 1.5 倍
	var inv := 1.0 / 1.5
	if bubble_panel != null:
		bubble_panel.position = Vector2(-110 * inv, 120)   # 正数 = 角色下方
		bubble_panel.scale = Vector2(inv, inv)
	if bubble_tail != null:
		bubble_tail.position = Vector2(-30 * inv, 112)
		bubble_tail.scale = Vector2(inv, inv)
		bubble_tail.rotation = PI    # 尾巴翻转朝上（因为气泡现在在下方）
	$PetGroup/VBox.visible = false
	if status_label != null:
		status_label.visible = true
		status_label.position = Vector2(WIN_MAIN.x / 2.0, WIN_MAIN.y * 0.60 + 90.0 * pet_group.scale.y)
		status_label.z_index = 61
 
	_refresh_main_hall()
	_refresh_main_hall_live()
 
func _close_main_hall() -> void:
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
	$PetGroup/VBox.visible = true
	get_window().size = WIN_NORMAL
	await get_tree().process_frame
	update_layout()               # 这一步应该重算角色位置
	_reposition_overlay_panels()
 
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
	var zh := current_language == "zh"
	var realm: Dictionary = realms[state["realm_index"]]
 
	# 基本信息
	mh_v_realm.text = realm["name"] if zh else realm_names_en[state["realm_index"]]
	mh_v_personality.text = PERSONALITY_META.get(current_personality, {}).get("zh" if zh else "en", "未知")
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
