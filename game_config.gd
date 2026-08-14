# ═══════════════════════════════════════════════
#  GameConfig — 全部常量与枚举（自动拆分自 Main.gd）
#  用法：任意脚本中 GameConfig.XXX 直接访问，无需注册。
# ═══════════════════════════════════════════════
class_name GameConfig

# ── 字体分层：标题用毛笔（飞岩手书），正文用易读字体（自动识别文楷）──
const BRUSH_FONT_PATH := "res://assets/fonts/AaFeiYanShouShu.ttf"
static var _body_font: FontFile
static func body_font() -> FontFile:
	if _body_font != null:
		return _body_font
	var dir := DirAccess.open("res://assets/fonts")
	if dir != null:
		for f in dir.get_files():
			var name := f.replace(".remap", "").replace(".import", "")
			var lf := name.to_lower()
			if (lf.ends_with(".ttf") or lf.ends_with(".otf")) and (lf.contains("wenkai") or lf.contains("lxgw")):
				var p := "res://assets/fonts/" + name
				if ResourceLoader.exists(p):
					_body_font = load(p)
					return _body_font
	if ResourceLoader.exists(BRUSH_FONT_PATH):
		_body_font = load(BRUSH_FONT_PATH)
	return _body_font

static var _brush_font: FontFile
static func brush_font() -> FontFile:
	if _brush_font == null and ResourceLoader.exists(BRUSH_FONT_PATH):
		_brush_font = load(BRUSH_FONT_PATH)
	return _brush_font

# 主面板：角色垂直位置（窗口高度比例），调这里即可整体上下移
const MH_PET_Y_RATIO := 0.64

const SAVE_PATH := "user://desktop_cultivator_save.json"

const TICK_SECONDS := 1.0

const OFFLINE_CAP_SECONDS := 12 * 60 * 60

const FAREWELL_LINES := [
	{"zh": "这就走了？那我继续闭关了。", "en": "Leaving already? Back to seclusion, then."},
	{"zh": "明天见。说不定明天我就突破了。", "en": "See you tomorrow. I might just break through."},
	{"zh": "走了也别忘了我还在修炼。", "en": "Don't forget — I'll still be cultivating."},
	{"zh": "去吧去吧，凡人的事也很重要。", "en": "Go on. Mortal business matters too."},
	{"zh": "我会想你的……才怪。", "en": "I'll miss you... as if."},
]

const DEMO_MODE := true                # 正式版改 false

const DEMO_BREAKTHROUGH_BONUS := 0.08  # 突破成功率小幅加成，减小卡关

# ═══════════════════════════════════════════════
#  DEMO 节奏表 —— 目标：20 分钟走完 4 世 / 3 次死亡
#  设计意图：每一世比上一世更短更快，节奏在加速而不是重复。
#  时间是权威，境界是尽力而为：时间到了就死，没修到也死。
# ═══════════════════════════════════════════════

# 每一世的目标时长（秒）。0 = 不强制死亡（最后一世，跑到炼气为止）
const DEMO_LIFE_SECONDS := [420.0, 360.0, 240.0, 0.0]
#                            7分    6分    4分   剩下3分

# 每一世的修炼倍率。逐世递增 = 后面的世活得更快
# 调这一行就能改「每世死在什么境界」，不用动别的
const DEMO_LIFE_CULT_MULT := [14.0, 28.0, 90.0, 260.0]
#  预期到达：武者初期 → 武者中期 → 先天初期 → 炼气一层(demo 结束)

# 强制死亡次数（= DEMO_LIFE_SECONDS 里非 0 的项数）
const DEMO_FORCED_DEATHS := 3

# 最低死亡境界：时间到了但还没到这个境界，再宽限 DEMO_DEATH_GRACE 秒
# 设 0 = 关闭这个保护，纯按时间死
const DEMO_MIN_DEATH_REALM := 1
const DEMO_DEATH_GRACE := 45.0

# ── 双时钟：玩家挂机时慢下来，别让高光在没人看的时候演完 ──
const DEMO_IDLE_AFTER := 60.0          # 多久没互动算「挂机」
const DEMO_IDLE_TIME_SCALE := 0.35     # 挂机时人生时钟的速度
const DEMO_DEATH_WAIT_MAX := 180.0     # 死亡最多为玩家等这么久，超过就照演

# ── demo 内的「一天」按真实秒数推进，而不是等真实日期变化 ──
# 关掉的话，20 分钟的试玩里日报 / 伏笔 / 事件链一次都不会触发
const DEMO_DAY_SECONDS := 22.0

# 一天只有 22 秒，日报每天弹会刷屏。每 N 天出一期。
const DEMO_GAZETTE_EVERY_DAYS := 4

# ── 硬性保护：不管怎样，真实时长超过这个数就强制推进到 demo 结局 ──
const DEMO_HARD_CAP_SECONDS := 1800.0  # 30 分钟

const DECISION_INDICATOR_POS := Vector2(24.0, -168.0)   # 相对角色中心，头顶右上

const MEMORABLE_EVENTS_CAP := 8

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

const AUTOSAVE_INTERVAL := 15.0

const REALM_STRIP_OFFSET_Y := -24.0

const TIER_ORDER := ["凡人", "武者", "先天", "炼气"]

const TIER_ANIM_SUFFIX := {
	"凡人": "fanren",
	"武者": "wuzhe",
	"先天": "xiantian",
	"炼气": "lianqi"
}

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

const PERSONALITY_TRAITS := ["reckless", "cautious", "greedy", "lazy", "diligent", "eccentric"]

const PERSONALITY_META := {
	"reckless": {"zh": "莽撞", "en": "Reckless"},
	"cautious": {"zh": "谨慎", "en": "Cautious"},
	"greedy":   {"zh": "贪婪", "en": "Greedy"},
	"lazy":     {"zh": "摆烂", "en": "Lazy"},
	"diligent": {"zh": "勤勉", "en": "Diligent"},
	"eccentric":{"zh": "古怪", "en": "Eccentric"}
}

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

const FEED_COOLDOWN_SECONDS := 60.0

const WIN_NORMAL := Vector2i(280, 360)

const WIN_WIDE   := Vector2i(640, 420)

const REPORT_MARGIN := 12.0

const POKE_STREAK_RESET_SEC := 1.2

const POKE_ANGRY_STREAK := 8

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

const CERT_SIZE := Vector2(560, 420)   # 与底图 4:3 完全同比

const CERT_TITLE_RECT   := Rect2(153, 30, 254, 56)    # 顶部横匾：标题

const CERT_LEFT_RECT    := Rect2(48, 122, 132, 248)   # 左侧长框：基本信息

const CERT_WITNESS_RECT := Rect2(382, 122, 140, 158)  # 右上框：天地鉴证（punchline）

const CERT_ISSUE_RECT   := Rect2(382, 306, 84, 70)    # 右下框：签发（避开红印）

const CERT_SEAL_RECT    := Rect2(252, 342, 50, 48)    # 中下红印框 → 留影按钮

const CERT_INK  := Color(0.32, 0.24, 0.14)

const CERT_GOLD := Color(0.55, 0.42, 0.18)

const CERT_RED  := Color(0.68, 0.18, 0.13)

const DEATH_INTERVAL := 4.0        # 每次死亡间隔秒数（录GIF建议3-5秒）

const SHOW_CERTIFICATE := true     # 是否每次闪一下转世证书

const CERT_FLASH_TIME := 1.2       # 证书停留秒数

const FEATURED_DEATHS: Array[String] = []  # 空 = 全池随机

const QUICK_ICON_SIZE := 56.0        # 屏幕上按钮直径

const QUICK_BAR_Y := 118.0           # 相对角色中心，按钮条的 y（原 VBox 位置附近）

const QUICK_HOVER_MARGIN := 46.0     # 悬停判定区在角色四周的外扩量

const QUICK_FADE := 0.18

const MH_FRAME_SIZE := Vector2(1167, 959)

const WIN_MAIN := Vector2i(1024, 842)          # ≈ frame 比例 (1167/959)

const MH_FONT_PATH := "res://assets/fonts/AaFeiYanShouShu.ttf"

const MH_INK      := Color(0.28, 0.20, 0.12)   # 墨色（正文/数值）

const MH_INK_SOFT := Color(0.42, 0.34, 0.24)   # 次级（标签）

const MH_GOLD     := Color(0.60, 0.46, 0.20)   # 分隔线/强调

const MH_GREEN    := Color(0.52, 0.68, 0.34)   # 修为条

const MH_GREEN_BG := Color(0.80, 0.82, 0.68)   # 修为条底

const MH_FS_SECTION := 30    # 分区标题：基本信息 / 天道评价

const MH_FS_LABEL   := 24    # 字段名

const MH_FS_VALUE   := 24    # 字段值

const MH_FS_NAME    := 30    # 名字牌里的名字

const MH_FS_VERDICT := 30    # 天道评价正文

const MH_FS_CULT    := 34    # 底部修为数字

enum MoodPriority {
	AMBIENT = 0,    # status ticks, dialogue-adjacent flavor — lowest, easily overridden
	EVENT = 1,      # report events, encounters, pet-click reactions — normal gameplay moments
	SYSTEM = 2,     # AFK/lazy, and any future "持续状态" that should hold until cleared
}
