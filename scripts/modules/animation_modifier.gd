class_name AnimationModifier
extends RefCounted

# 动作层修饰：同一段动画，在不同情境下播得不一样。
# 不新增动画资源 —— 只改速度、偏移，外加一个道具挂点。
#
# 动画名格式为 "境界_动作"（fanren_breath / wuzhe_walking / fanren_death_old），
# 所以一律用「包含」匹配，不能用 begins_with。

var main
var _prop: Sprite2D
var _base_offset: Vector2 = Vector2.ZERO
var _offset_captured: bool = false

const WEATHER_POSE := {
	WorldState.Weather.CLEAR:  { "speed": 1.00, "offset": Vector2(0, 0), "prop": "" },
	WorldState.Weather.CLOUDY: { "speed": 0.98, "offset": Vector2(0, 0), "prop": "" },
	WorldState.Weather.RAIN:   { "speed": 0.88, "offset": Vector2(0, 3), "prop": "umbrella" },
	WorldState.Weather.STORM:  { "speed": 0.78, "offset": Vector2(0, 6), "prop": "umbrella" },
	WorldState.Weather.SNOW:   { "speed": 0.85, "offset": Vector2(0, 4), "prop": "hat" },
	WorldState.Weather.FOG:    { "speed": 0.92, "offset": Vector2(0, 1), "prop": "" },
}

const TEMPER_SPEED := {
	WorldState.Temper.LOW: 0.86, WorldState.Temper.NEUTRAL: 1.00, WorldState.Temper.HIGH: 1.12,
}

const TIME_SPEED := {
	WorldState.TimeBand.DAWN: 0.92, WorldState.TimeBand.MORNING: 1.00,
	WorldState.TimeBand.NOON: 1.00, WorldState.TimeBand.DUSK: 0.96,
	WorldState.TimeBand.NIGHT: 0.88,
}

# 坐着/躺着的动作，不该撑伞（用 GameConfig.TIER_ACTION_FPS 里的真实动作名）
const SITTING := ["meditate", "sleeping", "lazy", "dunwu", "eat", "stomachache"]

# 走动/待机，晴夜可以提灯笼。breath 是待机动画。
const MOVING := ["breath", "walking", "workout"]

const PROP_PATHS := {
	"umbrella": "res://assets/props/umbrella.png",
	"hat": "res://assets/props/straw_hat.png",
	"lantern": "res://assets/props/lantern.png",
}


func _init(p_main) -> void:
	main = p_main


## prop_anchor 传 PetGroup 下新建的 Marker2D
func setup(prop_anchor: Node2D) -> void:
	if prop_anchor == null:
		push_warning("[AnimationModifier] PropAnchor 为空，道具功能关闭")
		return
	_prop = Sprite2D.new()
	_prop.name = "ModifierProp"
	_prop.visible = false
	_prop.z_index = 1
	prop_anchor.add_child(_prop)


func apply(sprite: AnimatedSprite2D, anim_name: String, state: WorldState) -> void:
	if sprite == null or state == null or anim_name == "":
		return

	if not _offset_captured:
		_base_offset = sprite.position
		_offset_captured = true

	# 一次性演出（突破/死亡/渡劫/事件特写）保持原速原位
	if _is_oneshot(anim_name):
		sprite.speed_scale = 1.0
		sprite.position = _base_offset
		_show_prop("")
		return

	var pose: Dictionary = WEATHER_POSE.get(state.weather, WEATHER_POSE[WorldState.Weather.CLEAR])

	var speed: float = float(pose["speed"]) \
		* float(TEMPER_SPEED.get(state.temper, 1.0)) \
		* float(TIME_SPEED.get(state.time_band, 1.0))
	sprite.speed_scale = clampf(speed, 0.6, 1.4)
	sprite.position = _base_offset + Vector2(pose["offset"])

	var prop_key: String = str(pose["prop"])
	if _matches(anim_name, SITTING):
		prop_key = ""
	# 晴夜走动/待机提灯笼 —— 条件苛刻，出现频率低，正好当小惊喜
	if state.time_band == WorldState.TimeBand.NIGHT \
		and state.weather == WorldState.Weather.CLEAR \
		and _matches(anim_name, MOVING):
		prop_key = "lantern"
	_show_prop(prop_key)


func reset(sprite: AnimatedSprite2D) -> void:
	if sprite != null and _offset_captured:
		sprite.position = _base_offset
		sprite.speed_scale = 1.0
	_show_prop("")


# ---------------------------------------------------------------- 内部

## 直接复用 GameConfig.TIER_NON_LOOPING —— 不循环的动画一律是一次性演出，不该被修饰。
## 这样以后加新特殊动画只要写进 TIER_NON_LOOPING，这边自动跟上。
func _is_oneshot(anim_name: String) -> bool:
	if _matches(anim_name, GameConfig.TIER_NON_LOOPING):
		return true
	return anim_name.contains("breakthrough")   # 覆盖 fanren_breakthrough_wuzhe 这类过渡动画


func _matches(anim_name: String, keywords) -> bool:
	var lower: String = anim_name.to_lower()
	for key in keywords:
		if lower.contains(str(key)):
			return true
	return false


func _show_prop(key: String) -> void:
	if _prop == null:
		return
	if key == "":
		_prop.visible = false
		return
	var path: String = str(PROP_PATHS.get(key, ""))
	if path == "" or not ResourceLoader.exists(path):
		_prop.visible = false
		return
	_prop.texture = load(path)
	_prop.visible = true
