extends Node
# ══════════════════════════════════════════
#  DataLoader  —  Autoload
#
#  把 Main.gd 里所有 CSV 加载函数和对应的数据数组集中到这里。
#  在 Godot 项目设置里注册为 Autoload，名称填 "DataLoader"。
#  Main.gd 里把所有  dialogues / pills / ...  替换成  DataLoader.dialogues / DataLoader.pills / ...
# ══════════════════════════════════════════

# ── 数据数组 ──────────────────────────────
var dialogues:                      Array = []
var statuses:                       Array = []
var pills:                          Array = []
var report_defs:                    Array = []
var report_by_id:                   Dictionary = {}
var death_causes:                   Array = []
var feed_lines:                     Array = []
var breakthrough_fail_reasons:      Array = []
var breakthrough_success_lines:     Array = []
var spiritual_root_awakening_lines: Array = []
var intro_lines_first:              Array = []
var intro_lines_reincarnated:       Array = []
var daily_comments:                 Array = []
var job_dialogues:                  Dictionary = {}
var job_statuses:                   Dictionary = {}
var last_words:                     Array = []
var rumours:                        Array = []
var neighbour_comments:             Array = []

# pill_zh 留在这里，因为 load_pills_from_csv 需要它做名称覆盖
const PILL_ZH := {
	"pill_001": {"name": "聚气丹",     "desc": "适合炼气期的基础丹药。"},
	"pill_002": {"name": "小聚气丹",   "desc": "日常修炼的温和丹药。"},
	"pill_003": {"name": "大聚气丹",   "desc": "灵气浓郁的强效丹药。"},
	"pill_004": {"name": "凝气丹",     "desc": "帮助修士凝练内气。"},
	"pill_005": {"name": "筑基丹",     "desc": "筑基期珍贵丹药。"},
	"pill_006": {"name": "护脉丹",     "desc": "减少突破失败的寿元损失。"},
	"pill_007": {"name": "回春丹",     "desc": "恢复少量寿元。"},
	"pill_008": {"name": "清心丹",     "desc": "清除杂念，略增突破稳定。"},
	"pill_009": {"name": "顿悟丹",     "desc": "窥见大道一隅。"},
	"pill_010": {"name": "狂化丹",     "desc": "强大但危险。"},
	"pill_011": {"name": "来历不明丹", "desc": "神秘的丹药，可能拉肚子。"},
	"pill_012": {"name": "过期丹",     "desc": "闻起来怪怪的，不推荐。"},
	"pill_013": {"name": "辟谷丹",     "desc": "闭关时抑制饥饿。"},
	"pill_014": {"name": "安神丹",     "desc": "安定心神，但会犯困。"},
	"pill_015": {"name": "避雷丹",     "desc": "提升渡劫前的存活几率。"}
}


# ══════════════════════════════════════════
#  统一入口：_ready 里一次性加载全部 CSV
# ══════════════════════════════════════════
func _ready() -> void:
	load_all()


func load_all() -> void:
	load_dialogues_from_csv()
	load_status_from_csv()
	load_pills_from_csv()
	load_reports_from_csv()
	load_death_causes_from_csv()
	load_feed_lines_from_csv()
	load_breakthrough_fail_reasons_from_csv()
	load_breakthrough_success_lines_from_csv()
	load_spiritual_root_awakening_lines_from_csv()
	load_intro_lines_from_csv()
	load_daily_comments_from_csv()
	load_job_dialogues_from_csv()
	load_job_statuses_from_csv()
	load_last_words_from_csv()
	load_rumours_from_csv()
	load_neighbour_comments_from_csv()


# ══════════════════════════════════════════
#  CSV 加载函数
# ══════════════════════════════════════════

func load_dialogues_from_csv() -> void:
	dialogues.clear()
	var file := FileAccess.open("res://data/Dialogues.csv", FileAccess.READ)
	if file == null:
		print("Dialogues.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 5:
			print("Skipped dialogue row, cols=", cols.size(), " -> ", cols)
			continue
		var row := {
			"id":      cols[0].strip_edges(),
			"realm":   cols[1].strip_edges(),
			"chinese": cols[2].strip_edges(),
			"english": cols[3].strip_edges(),
			"mood":    cols[4].strip_edges()
		}
		if cols.size() > 5  and cols[5].strip_edges()  != "": row["require_flag"]       = cols[5].strip_edges()
		if cols.size() > 6  and cols[6].strip_edges()  != "": row["luck_tag"]            = cols[6].strip_edges()
		if cols.size() > 7  and cols[7].strip_edges()  != "": row["personality_tag"]     = cols[7].strip_edges()
		if cols.size() > 8  and cols[8].strip_edges()  != "": row["health_tag"]          = cols[8].strip_edges()
		if cols.size() > 9  and cols[9].strip_edges()  != "": row["goal_tag"]            = cols[9].strip_edges()
		if cols.size() > 10 and cols[10].strip_edges() != "": row["event_tag"]           = cols[10].strip_edges()
		if cols.size() > 11 and cols[11].strip_edges() != "": row["requires_fail_streak"]= cols[11].strip_edges()
		if cols.size() > 12 and cols[12].strip_edges() != "": row["memorable_tag"]       = cols[12].strip_edges()
		if cols.size() > 13 and cols[13].strip_edges() != "": row["soul_echo"]           = cols[13].strip_edges()
		if cols.size() > 14 and cols[14].strip_edges() != "": row["instinct_tag"]        = cols[14].strip_edges()
		if cols.size() > 15 and cols[15].strip_edges() != "": row["sets_foreshadow"]     = cols[15].strip_edges()
		if cols.size() > 16 and cols[16].strip_edges() != "": row["foreshadow_days"]     = int(cols[16])
		dialogues.append(row)
	file.close()
	print("Loaded dialogues: ", dialogues.size())


func load_status_from_csv() -> void:
	statuses.clear()
	var file := FileAccess.open("res://data/Status.csv", FileAccess.READ)
	if file == null: return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 5: continue
		var row := {
			"realm": cols[1].strip_edges(),
			"zh":    cols[2].strip_edges(),
			"en":    cols[3].strip_edges(),
			"mood":  cols[4].strip_edges()
		}
		if cols.size() > 5 and cols[5].strip_edges() != "": row["require_flag"]  = cols[5].strip_edges()
		if cols.size() > 6 and cols[6].strip_edges() != "": row["instinct_tag"]  = cols[6].strip_edges()
		statuses.append(row)
	file.close()
	print("Loaded statuses: ", statuses.size())


func load_pills_from_csv() -> void:
	pills.clear()
	var file := FileAccess.open("res://data/pill.csv", FileAccess.READ)
	if file == null:
		print("pill.csv not found — using built-in pill list.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 11: continue
		var id := cols[0].strip_edges()
		var zh_entry: Dictionary = PILL_ZH.get(id, {})
		var min_realm := 0
		if cols.size() > 13 and cols[13].strip_edges() != "":
			min_realm = int(cols[13])
		pills.append({
			"id":               id,
			"name_zh":          zh_entry.get("name", cols[1].strip_edges()),
			"name_en":          cols[2].strip_edges(),
			"type":             cols[3].strip_edges(),
			"cost":             int(cols[5]),
			"cultivation_gain": int(cols[6]),
			"mood":             cols[7].strip_edges(),
			"success_bonus":    int(cols[8]),
			"side_effect":      cols[9].strip_edges(),
			"min_realm":        min_realm,
			"desc_zh":          zh_entry.get("desc", cols[11].strip_edges() if cols.size() > 11 else ""),
			"desc_en":          cols[12].strip_edges() if cols.size() > 12 else ""
		})
	file.close()
	print("Loaded pills: ", pills.size())


func load_reports_from_csv() -> void:
	report_defs.clear()
	report_by_id.clear()
	var file := FileAccess.open("res://data/DailyReports.csv", FileAccess.READ)
	if file == null:
		print("DailyReports.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 13: continue
		var row := {
			"id":               cols[0].strip_edges(),
			"chain_id":         cols[1].strip_edges(),
			"step":             int(cols[2]),
			"next_id":          cols[3].strip_edges(),
			"realm":            cols[4].strip_edges(),
			"title_zh":         cols[5].strip_edges(),
			"title_en":         cols[6].strip_edges(),
			"desc_zh":          cols[7].strip_edges(),
			"desc_en":          cols[8].strip_edges(),
			"mood":             cols[9].strip_edges(),
			"cultivation_gain": int(cols[10]),
			"stone_gain":       int(cols[11]),
			"weight":           int(cols[12])
		}
		if cols.size() > 13 and cols[13].strip_edges() != "": row["next_ids"]           = cols[13].strip_edges()
		if cols.size() > 14 and cols[14].strip_edges() != "": row["branch_weights"]     = cols[14].strip_edges()
		if cols.size() > 15 and cols[15].strip_edges() != "": row["branch_condition"]   = cols[15].strip_edges()
		if cols.size() > 16 and cols[16].strip_edges() != "": row["set_flag"]           = cols[16].strip_edges()
		if cols.size() > 17 and cols[17].strip_edges() != "": row["cooldown_days"]      = int(cols[17])
		if cols.size() > 18 and cols[18].strip_edges() != "": row["force_achievement"]  = cols[18].strip_edges()
		if cols.size() > 19 and cols[19].strip_edges() != "": row["personality_tag"]    = cols[19].strip_edges()
		if cols.size() > 20 and cols[20].strip_edges() != "": row["personality_nudge"]  = cols[20].strip_edges()
		if cols.size() > 21 and cols[21].strip_edges() != "": row["chain_summary_zh"]   = cols[21].strip_edges()
		if cols.size() > 22 and cols[22].strip_edges() != "": row["chain_summary_en"]   = cols[22].strip_edges()
		if cols.size() > 23 and cols[23].strip_edges() != "": row["memorable"]          = cols[23].strip_edges()
		if cols.size() > 24 and cols[24].strip_edges() != "": row["foreshadow_set"]     = cols[24].strip_edges()
		if cols.size() > 25 and cols[25].strip_edges() != "": row["foreshadow_expires_days"] = int(cols[25])
		if cols.size() > 26 and cols[26].strip_edges() != "": row["foreshadow_payoff"]  = cols[26].strip_edges()
		if cols.size() > 27 and cols[27].strip_edges() != "": row["choice_prompt_zh"] = cols[27].strip_edges()
		if cols.size() > 28 and cols[28].strip_edges() != "": row["choice_prompt_en"] = cols[28].strip_edges()
		if cols.size() > 29 and cols[29].strip_edges() != "": row["choice_a_zh"] = cols[29].strip_edges()
		if cols.size() > 30 and cols[30].strip_edges() != "": row["choice_a_en"] = cols[30].strip_edges()
		if cols.size() > 31 and cols[31].strip_edges() != "": row["choice_b_zh"] = cols[31].strip_edges()
		if cols.size() > 32 and cols[32].strip_edges() != "": row["choice_b_en"] = cols[32].strip_edges()
		report_defs.append(row)
		report_by_id[row["id"]] = row
	file.close()
	print("Loaded report defs: ", report_defs.size())


func load_death_causes_from_csv() -> void:
	death_causes.clear()
	var file := FileAccess.open("res://data/death_causes.csv", FileAccess.READ)
	if file == null:
		print("death_causes.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 5: continue
		death_causes.append({
			"id":        cols[0].strip_edges(),
			"type":      cols[1].strip_edges(),
			"weight":    max(1, int(cols[2])),
			"title_zh":  cols[3].strip_edges(),
			"title_en":  cols[4].strip_edges(),
			"animation": cols[5].strip_edges() if cols.size() > 5 else ""
		})
	file.close()
	print("Loaded death causes: ", death_causes.size())


func load_feed_lines_from_csv() -> void:
	feed_lines.clear()
	var file := FileAccess.open("res://data/feed_lines.csv", FileAccess.READ)
	if file == null:
		print("feed_lines.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 4: continue
		feed_lines.append({
			"tier": cols[1].strip_edges(),
			"zh":   cols[2].strip_edges(),
			"en":   cols[3].strip_edges()
		})
	file.close()
	print("Loaded feed lines: ", feed_lines.size())


func load_breakthrough_fail_reasons_from_csv() -> void:
	breakthrough_fail_reasons.clear()
	var file := FileAccess.open("res://data/BreakthroughFailReasons.csv", FileAccess.READ)
	if file == null:
		print("BreakthroughFailReasons.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 4: continue
		breakthrough_fail_reasons.append({
			"realm": cols[1].strip_edges(),
			"zh":    cols[2].strip_edges(),
			"en":    cols[3].strip_edges()
		})
	file.close()
	print("Loaded breakthrough fail reasons: ", breakthrough_fail_reasons.size())


func load_breakthrough_success_lines_from_csv() -> void:
	breakthrough_success_lines.clear()
	var file := FileAccess.open("res://data/BreakthroughSuccessLines.csv", FileAccess.READ)
	if file == null:
		print("BreakthroughSuccessLines.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 4: continue
		breakthrough_success_lines.append({
			"realm": cols[1].strip_edges(),
			"zh":    cols[2].strip_edges(),
			"en":    cols[3].strip_edges()
		})
	file.close()
	print("Loaded breakthrough success lines: ", breakthrough_success_lines.size())


func load_spiritual_root_awakening_lines_from_csv() -> void:
	spiritual_root_awakening_lines.clear()
	var file := FileAccess.open("res://data/SpiritualRootAwakeningLines.csv", FileAccess.READ)
	if file == null:
		print("SpiritualRootAwakeningLines.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 4: continue
		spiritual_root_awakening_lines.append({
			"tier": cols[1].strip_edges(),
			"zh":   cols[2].strip_edges(),
			"en":   cols[3].strip_edges()
		})
	file.close()
	print("Loaded spiritual root awakening lines: ", spiritual_root_awakening_lines.size())


func load_intro_lines_from_csv() -> void:
	intro_lines_first       = _load_intro_file("res://data/IntroLines_FirstLife.csv")
	intro_lines_reincarnated = _load_intro_file("res://data/IntroLines_Reincarnated.csv")
	print("Loaded first-life intro lines: ",    intro_lines_first.size())
	print("Loaded reincarnated intro lines: ",  intro_lines_reincarnated.size())

func _load_intro_file(path: String) -> Array:
	var result: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("Intro file not found: ", path)
		return result
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 3: continue
		result.append({
			"zh": String(cols[1]).strip_edges().replace("\\n", "\n"),
			"en": String(cols[2]).strip_edges().replace("\\n", "\n")
		})
	file.close()
	return result


func load_daily_comments_from_csv() -> void:
	daily_comments.clear()
	var file := FileAccess.open("res://data/DailySummaryComments.csv", FileAccess.READ)
	if file == null:
		print("DailySummaryComments.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 4: continue
		daily_comments.append({
			"category": cols[1].strip_edges(),
			"zh":       cols[2].strip_edges(),
			"en":       cols[3].strip_edges()
		})
	file.close()
	print("Loaded daily comments: ", daily_comments.size())


func load_job_dialogues_from_csv() -> void:
	job_dialogues.clear()
	var file := FileAccess.open("res://data/JobDialogues.csv", FileAccess.READ)
	if file == null:
		print("JobDialogues.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 6: continue
		var job_id := cols[1].strip_edges()
		if job_id == "": continue
		if not job_dialogues.has(job_id):
			job_dialogues[job_id] = []
		job_dialogues[job_id].append({
			"id":      cols[0].strip_edges(),
			"realm":   cols[2].strip_edges(),
			"chinese": cols[3].strip_edges(),
			"english": cols[4].strip_edges(),
			"mood":    cols[5].strip_edges()
		})
	file.close()
	var total := 0
	for k in job_dialogues: total += job_dialogues[k].size()
	print("Loaded job dialogues: ", total, " across ", job_dialogues.size(), " jobs")


func load_job_statuses_from_csv() -> void:
	job_statuses.clear()
	var file := FileAccess.open("res://data/JobStatuses.csv", FileAccess.READ)
	if file == null:
		print("JobStatuses.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 6: continue
		var job_id := cols[1].strip_edges()
		if job_id == "": continue
		var mood := cols[5].strip_edges()
		if mood == "": mood = "normal"
		if not job_statuses.has(job_id):
			job_statuses[job_id] = []
		job_statuses[job_id].append({
			"realm": cols[2].strip_edges(),
			"zh":    cols[3].strip_edges(),
			"en":    cols[4].strip_edges(),
			"mood":  mood
		})
	file.close()
	var total := 0
	for k in job_statuses: total += job_statuses[k].size()
	print("Loaded job statuses: ", total, " across ", job_statuses.size(), " jobs")


func load_last_words_from_csv() -> void:
	last_words.clear()
	var file := FileAccess.open("res://data/LastWords.csv", FileAccess.READ)
	if file == null:
		print("LastWords.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 4: continue
		last_words.append({
			"cause_type": cols[1].strip_edges(),
			"zh":         cols[2].strip_edges(),
			"en":         cols[3].strip_edges()
		})
	file.close()
	print("Loaded last words: ", last_words.size())


func load_rumours_from_csv() -> void:
	rumours.clear()
	var file := FileAccess.open("res://data/Rumours.csv", FileAccess.READ)
	if file == null:
		print("Rumours.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 4: continue
		rumours.append({
			"realm": cols[1].strip_edges(),
			"zh":    cols[2].strip_edges(),
			"en":    cols[3].strip_edges()
		})
	file.close()
	print("Loaded rumours: ", rumours.size())


func load_neighbour_comments_from_csv() -> void:
	neighbour_comments.clear()
	var file := FileAccess.open("res://data/NeighbourComments.csv", FileAccess.READ)
	if file == null:
		print("NeighbourComments.csv not found.")
		return
	var is_header := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if cols.size() == 0: continue
		if is_header: is_header = false; continue
		if cols.size() < 4: continue
		neighbour_comments.append({
			"id":              cols[0].strip_edges(),
			"personality_tag": cols[1].strip_edges(),
			"zh":              cols[2].strip_edges(),
			"en":              cols[3].strip_edges()
		})
	file.close()
	print("Loaded neighbour comments: ", neighbour_comments.size())
