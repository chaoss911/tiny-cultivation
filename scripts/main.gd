extends Control

const SAVE_PATH := "user://desktop_cultivator_save.json"
const TICK_SECONDS := 1.0
const OFFLINE_CAP_SECONDS := 12 * 60 * 60

var mood := "normal"

var dialogues: Array = []
var current_language := "zh"
var current_personality := "Lazy"
var statuses: Array = []
var fallback_dialogues := [
	{"chinese": "他偷偷吃了一颗聚气丹。", "english": "He secretly ate a Qi pill.", "personality": "Lazy"},
	{"chinese": "他盯着你的鼠标，似乎悟到了什么。", "english": "He stares at your cursor and seems enlightened.", "personality": "Lazy"},
	{"chinese": "今天灵气不错。", "english": "The spiritual energy feels good today.", "personality": "Lazy"}
]
var sprite_paths := {
	"normal": "res://images/cultivator_idle.png",
	"meditate": "res://images/cultivator_meditate.png",
	"sleepy": "res://images/cultivator_sleep.png",
	"happy": "res://images/cultivator_happy.png",
	"alchemy": "res://images/cultivator_alchemy.png",
	"confused": "res://images/cultivator_level.png"
}
var realm_names_en = [
	"Qi Refining I",
	"Qi Refining II",
	"Qi Refining III",
	"Qi Refining Peak",
	"Foundation Early",
	"Foundation Mid",
	"Foundation Late",
	"Golden Core"
]
var personality_events := [
	{
		"text": "他偷偷吃了一颗聚气丹。",
		"mood": "happy",
		"cultivation_gain": 30,
		"stone_gain": 0
	},
	{
		"text": "他打坐打到睡着了。",
		"mood": "sleepy",
		"cultivation_gain": 0,
		"stone_gain": 0
	},
	{
		"text": "他在你的任务栏下面捡到灵石。",
		"mood": "happy",
		"cultivation_gain": 10,
		"stone_gain": 2
	},
	{
		"text": "炼丹炉又炸了。",
		"mood": "confused",
		"cultivation_gain": 0,
		"stone_gain": -1
	},
	{
		"text": "他认真打坐，周围灵气变浓了。",
		"mood": "meditate",
		"cultivation_gain": 20,
		"stone_gain": 0
	},
	{
		"text": "他盯着你的鼠标，似乎悟到了什么。",
		"mood": "confused",
		"cultivation_gain": 8,
		"stone_gain": 0
	}
]
var fallback_statuses := [
	{"chinese": "开始吐纳灵气……", "english": "Absorbing spiritual energy...", "mood": "normal"},
	{"chinese": "今天状态不错。", "english": "Feeling good today.", "mood": "normal"},
	{"chinese": "再睡五分钟。", "english": "Five more minutes...", "mood": "sleepy"},
	{"chinese": "周围灵气变浓了。", "english": "The spiritual energy is gathering.", "mood": "meditate"},
	{"chinese": "丹药开始生效。", "english": "The pill is taking effect.", "mood": "alchemy"},
	{"chinese": "感觉快要突破了！", "english": "I feel close to a breakthrough!", "mood": "happy"},
	{"chinese": "总觉得哪里不对劲。", "english": "Something feels off...", "mood": "confused"}
]
var realms := [
	{"name": "炼气一层", "need": 100},
	{"name": "炼气二层", "need": 180},
	{"name": "炼气三层", "need": 320},
	{"name": "炼气圆满", "need": 600},
	{"name": "筑基初期", "need": 1200},
	{"name": "筑基中期", "need": 2200},
	{"name": "筑基后期", "need": 4200},
	{"name": "金丹初期", "need": 9000}
]

var state := {
	"realm_index": 0,
	"cultivation": 0.0,
	"spirit_stones": 0,
	"lifespan": 80,
	"last_saved_unix": 0
}

var dragging := false
var drag_offset := Vector2.ZERO

@onready var pet_group: Node2D = $PetGroup
@onready var language_button = $PetGroup/VBox/Buttons/Language
@onready var cultivator_sprite = $PetGroup/CultivatorSprite
@onready var speech_label = $PetGroup/SpeechLabel
@onready var status_label = $PetGroup/StatusLabel
@onready var title_label = $PetGroup/VBox/Title
@onready var realm_label: Label = $PetGroup/VBox/Realm
@onready var progress_bar = $PetGroup/VBox/Progress
@onready var stats_label = $PetGroup/VBox/Stats
@onready var feed_button = $PetGroup/VBox/Buttons/FeedPill
@onready var meditate_button = $PetGroup/VBox/Buttons/Meditate
@onready var info_button = $PetGroup/VBox/Buttons/Info

func _ready() -> void:
	language_button.text = "中"
	language_button.pressed.connect(_on_language_pressed)
	randomize()
	get_window().size = Vector2i(360, 420)

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)

	update_layout()

	load_game()
	grant_offline_rewards()

	feed_button.pressed.connect(_on_feed_pill)
	meditate_button.pressed.connect(_on_meditate)
	info_button.pressed.connect(_on_info_pressed)

	load_dialogues_from_csv()
	load_status_from_csv()
	set_mood("normal")

	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()

	if cultivator_sprite != null:
		cultivator_sprite.scale = Vector2(0.35, 0.35)

	var personality_timer := Timer.new()
	personality_timer.wait_time = 12.0
	personality_timer.timeout.connect(trigger_personality_event)
	add_child(personality_timer)
	personality_timer.start()
	var dialogue_timer := Timer.new()
	dialogue_timer.wait_time = 5.0
	dialogue_timer.timeout.connect(random_dialogue)
	add_child(dialogue_timer)
	dialogue_timer.start()
	current_language = "zh"
	var status_timer := Timer.new()
	status_timer.wait_time = 6.0
	status_timer.timeout.connect(update_status)
	add_child(status_timer)
	status_timer.start()
	
	language_button.text = "中"
	feed_button.text = "吃丹药"
	meditate_button.text = "打坐"
	info_button.text = "资料"
	$PetGroup/VBox.visible = true
	$PetGroup/VBox/Buttons.visible = true
	feed_button.visible = true
	meditate_button.visible = true
	language_button.visible = true
	info_button.visible = true
	refresh_ui()
	

func update_layout() -> void:
	var viewport_size = get_viewport_rect().size

	pet_group.position = Vector2(
		viewport_size.x / 2,
		130
	)

	cultivator_sprite.centered = true
	cultivator_sprite.scale = Vector2(0.35, 0.35)
	cultivator_sprite.position = Vector2(0, -30)

	speech_label.position = Vector2(-90, -120)
	status_label.position = Vector2(-70, 35)

	var vbox = $PetGroup/VBox
	vbox.position = Vector2(
		-vbox.size.x / 2,
		55
	)

func set_mood(new_mood: String) -> void:
	mood = new_mood

	if cultivator_sprite == null:
		return

	if sprite_paths.has(mood):
		cultivator_sprite.texture = load(sprite_paths[mood])

	update_status()

func trigger_personality_event() -> void:
	var event: Dictionary = personality_events.pick_random()

	set_mood(event["mood"])

	state["cultivation"] += event["cultivation_gain"]
	state["spirit_stones"] += event["stone_gain"]

	if state["cultivation"] < 0:
		state["cultivation"] = 0

	if state["spirit_stones"] < 0:
		state["spirit_stones"] = 0

	log_event(event["text"])
	say(event["text"])
	refresh_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		drag_offset = get_global_mouse_position()

	if event is InputEventMouseMotion and dragging:
		var current_mouse := get_global_mouse_position()
		var delta := current_mouse - drag_offset
		drag_offset = current_mouse
		DisplayServer.window_set_position(DisplayServer.window_get_position() + Vector2i(delta))


func _on_tick() -> void:
	gain_cultivation(1.0)

	if randi() % 20 == 0:
		state["spirit_stones"] += 1
		log_event("捡到 1 枚灵石。")

	save_game()
	refresh_ui()


func gain_cultivation(multiplier: float) -> void:
	var realm: Dictionary = realms[state["realm_index"]]
	var gain := 2.0 * multiplier

	state["cultivation"] += gain

	if state["cultivation"] >= realm["need"]:
		try_breakthrough()


func try_breakthrough() -> void:
	var chance := 0.82

	if state["realm_index"] >= 3:
		chance = 0.65

	if state["realm_index"] >= 6:
		chance = 0.45

	state["cultivation"] = 0.0

	if randf() <= chance:
		state["realm_index"] = min(state["realm_index"] + 1, realms.size() - 1)
		set_mood("happy")
		log_event("[color=yellow]突破成功！进入「%s」。[/color]" % realms[state["realm_index"]]["name"])
	else:
		state["lifespan"] -= 3
		set_mood("confused")
		log_event("[color=red]突破失败，被心魔反噬，寿元 -3。[/color]")

	await get_tree().create_timer(1.0).timeout
	set_mood("normal")


func _on_feed_pill() -> void:
	if state["spirit_stones"] < 5:
		log_event("灵石不足，无法购买聚气丹。")
		set_mood("confused")
		return

	state["spirit_stones"] -= 5
	gain_cultivation(18.0)
	set_mood("alchemy")
	log_event("服用聚气丹，修为大涨。")

	if randf() < 0.05:
		log_event("服用神秘丹药，顿悟了。")
		state["cultivation"] += 300

	refresh_ui()


func _on_meditate() -> void:
	gain_cultivation(8.0)
	set_mood("meditate")
	log_event("你盯了他一眼，他开始认真打坐。")
	refresh_ui()


func grant_offline_rewards() -> void:
	var now := Time.get_unix_time_from_system()
	var last := int(state.get("last_saved_unix", now))
	var offline_seconds: int = clampi(int(now - last), 0, OFFLINE_CAP_SECONDS)

	if offline_seconds > 60:
		var cultivation_gain := int(floor(offline_seconds / 10.0))
		var stones_gain := int(floor(offline_seconds / 600.0))

		state["cultivation"] += cultivation_gain
		state["spirit_stones"] += stones_gain

		log_event("离线修炼 %s 分钟，获得修为 %s，灵石 %s。" % [int(floor(offline_seconds / 60.0)), cultivation_gain, stones_gain])

		while state["realm_index"] < realms.size() - 1 and state["cultivation"] >= realms[state["realm_index"]]["need"]:
			state["cultivation"] -= realms[state["realm_index"]]["need"]
			state["realm_index"] += 1


func refresh_ui() -> void:
	var realm: Dictionary = realms[state["realm_index"]]

	if current_language == "zh":
		title_label.text = "桌面修仙"
		realm_label.text = "境界：%s" % realm["name"]

		stats_label.text = "修为：%d / %d\n灵石：%d\n寿元：%d年" % [
			int(state["cultivation"]),
			int(realm["need"]),
			int(state["spirit_stones"]),
			int(state["lifespan"])
		]
	else:
		title_label.text = "Mini Cultivator"
		realm_label.text = "Realm: %s" % realm_names_en[state["realm_index"]]

		stats_label.text = "Cultivation: %d / %d\nSpirit Stones: %d\nLifespan: %d yrs" % [
			int(state["cultivation"]),
			int(realm["need"]),
			int(state["spirit_stones"]),
			int(state["lifespan"])
		]

	progress_bar.max_value = realm["need"]
	progress_bar.value = state["cultivation"]

func log_event(text: String) -> void:
	if speech_label == null:
		return

	speech_label.text = text
	speech_label.visible = true

	await get_tree().create_timer(4.0).timeout

	speech_label.visible = false


func save_game() -> void:
	state["last_saved_unix"] = Time.get_unix_time_from_system()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	if file:
		file.store_string(JSON.stringify(state))


func say(text: String) -> void:
	print(text)
	
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)

	if not file:
		return

	var parsed = JSON.parse_string(file.get_as_text())

	if typeof(parsed) == TYPE_DICTIONARY:
		for key in state.keys():
			if parsed.has(key):
				state[key] = parsed[key]

func load_dialogues_from_csv() -> void:
	dialogues.clear()

	var file := FileAccess.open("res://data/Dialogues.csv", FileAccess.READ)

	if file == null:
		print("Dialogues.csv not found.")
		return

	var is_header := true

	while not file.eof_reached():
		var cols := file.get_csv_line()

		if cols.size() == 0:
			continue

		if is_header:
			is_header = false
			continue

		if cols.size() < 4:
			continue

		dialogues.append({
			"id": cols[0].strip_edges(),
			"chinese": cols[1].strip_edges(),
			"english": cols[2].strip_edges(),
			"personality": cols[3].strip_edges()
		})

	file.close()

	print("Loaded dialogues: ", dialogues.size())


func random_dialogue() -> void:
	var source = dialogues

	if source.is_empty():
		source = fallback_dialogues

	var selected: Dictionary = source.pick_random()
	var text := ""

	if current_language == "zh":
		text = selected["chinese"]
	else:
		text = selected["english"]

	log_event(text)

func _on_info_pressed() -> void:
	var show_info: bool = !realm_label.visible

	title_label.visible = false
	realm_label.visible = show_info
	progress_bar.visible = show_info
	stats_label.visible = show_info

	if show_info:
		get_window().size = Vector2i(360, 520)
	else:
		get_window().size = Vector2i(360, 420)

	update_layout()

	var drag_hint = get_node_or_null("PetGroup/VBox/DragHint")
	if drag_hint != null:
		drag_hint.visible = false

func load_status_from_csv():
	statuses.clear()

	var file = FileAccess.open("res://data/Status.csv", FileAccess.READ)

	if file == null:
		return

	var is_header = true

	while not file.eof_reached():
		var cols = file.get_csv_line()

		if cols.size() == 0:
			continue

		if is_header:
			is_header = false
			continue

		if cols.size() < 4:
			continue

		statuses.append({
			"chinese": cols[1].strip_edges(),
			"english": cols[2].strip_edges(),
			"mood": cols[3].strip_edges()
		})

	file.close()
		
func update_status():
	var source = statuses

	if source.is_empty():
		source = fallback_statuses

	var filtered = []

	for s in source:
		if s["mood"] == mood:
			filtered.append(s)

	if filtered.is_empty():
		for s in source:
			if s["mood"] == "normal":
				filtered.append(s)

	if filtered.is_empty():
		return

	var selected = filtered.pick_random()

	if current_language == "zh":
		status_label.text = selected["chinese"]
	else:
		status_label.text = selected["english"]

	status_label.visible = true
func _on_language_pressed() -> void:
	if current_language == "zh":
		current_language = "en"

		language_button.text = "EN"
		feed_button.text = "Pill"
		meditate_button.text = "Meditate"
		info_button.text = "Info"
	else:
		current_language = "zh"

		language_button.text = "中"
		feed_button.text = "吃丹药"
		meditate_button.text = "打坐"
		info_button.text = "资料"

	update_status()
	refresh_ui()
