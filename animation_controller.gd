# ═══════════════════════════════════════════════
#  AnimationController — 动画构建与解析
#  自动拆分自 Main.gd。Main 持有实例，_ready 里注入 main = self
# ═══════════════════════════════════════════════
class_name AnimationController
extends RefCounted

var main   # Main.gd (Control) 引用

func _build_animations() -> void:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	_add_tier_animations(sf)
	_add_transition_animations(sf)
	main.cultivator_sprite.sprite_frames = sf
	main.set_mood("normal")

func _add_tier_animations(sf: SpriteFrames) -> void:
	var added := 0
	for tier in GameConfig.TIER_ANIM_SUFFIX:
		var suffix: String = GameConfig.TIER_ANIM_SUFFIX[tier]
		if suffix == "":
			continue
		var dir := "res://assets/sprites/%s/" % suffix
		for action in GameConfig.TIER_ACTION_FPS:
			var sheet_path := "%s%s_%s.png" % [dir, suffix, action]
			if not ResourceLoader.exists(sheet_path):
				print("[境界动画] 没找到: ", sheet_path)
				continue

			var tex: Texture2D = load(sheet_path)
			if tex == null:
				print("[境界动画] 加载失败: ", sheet_path)
				continue
			
			var grid: Dictionary = GameConfig.TIER_GRID_OVERRIDE.get(action, {"cols": 5, "rows": 4, "frames": 16})
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
			sf.set_animation_loop(anim_name, not (action in GameConfig.TIER_NON_LOOPING))
			sf.set_animation_speed(anim_name, float(GameConfig.TIER_ACTION_FPS[action]))

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


func _add_transition_animations(sf: SpriteFrames) -> void:
	for anim_name in GameConfig.TIER_TRANSITION_ANIMS:
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
		sf.set_animation_speed(anim_name, float(GameConfig.TIER_TRANSITION_ANIMS[anim_name]))

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


func _resolve_mood_anim(m: String) -> String:
	if main.cultivator_sprite == null or main.cultivator_sprite.sprite_frames == null:
		return ""
	var base_anim: String = main.anim_for_mood.get(m, "breath")
	var tier: String = main.current_tier()
	var suffix: String = GameConfig.TIER_ANIM_SUFFIX.get(tier, "")
	var tiered := "%s_%s" % [suffix, base_anim]
	if suffix != "" and main.cultivator_sprite.sprite_frames.has_animation(tiered):
		return tiered
	elif main.cultivator_sprite.sprite_frames.has_animation(base_anim):
		return base_anim
	return ""


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


func _death_anim_duration(anim: String) -> float:
	if anim == "" or main.cultivator_sprite == null or main.cultivator_sprite.sprite_frames == null:
		return 0.0
	var sf: SpriteFrames = main.cultivator_sprite.sprite_frames
	if not sf.has_animation(anim):
		return 0.0
	var speed := sf.get_animation_speed(anim)
	if speed <= 0.0:
		return 2.0
	return float(sf.get_frame_count(anim)) / speed   # 16帧 / 7.7 ≈ 2.08秒
