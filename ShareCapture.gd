# ShareCapture.gd — 一键分享存图
# 用法1: 加为 Autoload (项目设置→Autoload→命名 ShareCapture)
#        然后任意处调用 ShareCapture.share_panel(证书面板节点)
# 用法2: 把下面两个函数直接并入 Main.gd,去掉 class 头即可
#
# 功能: 截取指定 Control 面板 → 加水印 → 存到系统"图片"文件夹 → 打开文件夹
# 适用: 转世证书 / 日报 / 遗言面板,任何 Control 都能传进来

extends Node

const WATERMARK_TEXT := "桌面修仙 Tiny Cultivation"
const FILE_PREFIX := "TinyCultivation"

## 主入口: 截取面板并保存
func share_panel(panel: Control) -> void:
	if panel == null or not panel.is_visible_in_tree():
		push_warning("ShareCapture: 面板不可见,取消截图")
		return

	# 1. 临时挂水印(截完就删,不影响正常UI)
	var watermark := _make_watermark()
	panel.add_child(watermark)
	# 贴右下角
	watermark.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	watermark.position = panel.size - watermark.get_minimum_size() - Vector2(12, 8)

	# 2. 等一帧确保水印渲染出来
	await RenderingServer.frame_post_draw

	# 3. 截整个viewport,按面板的全局矩形裁剪
	var full_img: Image = panel.get_viewport().get_texture().get_image()
	var rect := _panel_pixel_rect(panel)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, full_img.get_size()))
	var cropped: Image = full_img.get_region(rect)

	watermark.queue_free()

	# 4. 保存到系统图片文件夹
	var save_path := _build_save_path()
	var err := cropped.save_png(save_path)
	if err != OK:
		# 图片文件夹不可写时退回 user://
		save_path = "user://" + save_path.get_file()
		err = cropped.save_png(save_path)

	if err == OK:
		print("ShareCapture: 已保存 → ", save_path)
		# 5. 打开文件所在位置 (Godot 4.2+; 老版本用 OS.shell_open(save_path.get_base_dir()))
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(save_path))
		_show_toast(panel, "已保存到图片文件夹 📜")
	else:
		push_error("ShareCapture: 保存失败 err=%d" % err)
		_show_toast(panel, "保存失败…")


## 计算面板在viewport像素坐标下的矩形(处理content scale缩放)
func _panel_pixel_rect(panel: Control) -> Rect2i:
	var global_rect := panel.get_global_rect()
	# 若项目用了 content_scale_factor / stretch,需换算到真实像素
	var vp := panel.get_viewport()
	var xform := vp.get_final_transform()
	var top_left := xform * global_rect.position
	var bottom_right := xform * global_rect.end
	return Rect2i(Vector2i(top_left.floor()), Vector2i((bottom_right - top_left).ceil()))


func _make_watermark() -> Label:
	var label := Label.new()
	label.text = WATERMARK_TEXT
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35, 0.75)) # 淡金色
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_save_path() -> String:
	var pictures_dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	var ts := Time.get_datetime_string_from_system().replace(":", "-") # 文件名不能有冒号
	return pictures_dir.path_join("%s_%s.png" % [FILE_PREFIX, ts])


## 简易toast提示(2秒后消失)
func _show_toast(anchor: Control, text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color.WHITE)
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.get_viewport().add_child(toast) # 挂到viewport根,不受面板关闭影响
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(anchor.get_global_rect().get_center().x - 80, anchor.get_global_rect().position.y - 30)
	var tween := toast.create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	tween.tween_callback(toast.queue_free)

# ── 按钮接线示例(放到你创建证书面板的地方) ─────────────
