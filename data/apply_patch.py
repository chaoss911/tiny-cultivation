#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
apply_patch.py — Tiny Cultivation demo 补丁自动应用脚本
用法（在项目脚本目录下运行）:
    python apply_patch.py Main.gd EventManager.gd

不会覆盖原文件：输出 Main_patched.gd / EventManager_patched.gd。
每条编辑打印 ✔/✘，✘ 的条目请按 Main_patch.md 手动处理。

包含内容：
  [BUG]  PetGrsoup 拼写修复
  [DEL]  死代码删除（约150行，均已确认无调用点）
  [FEAT] 一键分享按钮（证书面板，需 ShareCapture autoload）
  [FEAT] 关闭挽留语 + 右键菜单"退出"
  [FEAT] 第一天/新一世事件加密（Main 报事件 + EventManager 气泡事件）
"""
import sys, io

results = []

def log(ok, name):
    results.append((ok, name))
    print(("  ✔ " if ok else "  ✘ ") + name)

def replace_once(text, old, new, name):
    n = text.count(old)
    if n == 1:
        log(True, name)
        return text.replace(old, new)
    log(False, f"{name}（锚点出现 {n} 次，预期 1 次）")
    return text

def insert_after(text, anchor, addition, name):
    n = text.count(anchor)
    if n == 1:
        log(True, name)
        return text.replace(anchor, anchor + addition)
    log(False, f"{name}（锚点出现 {n} 次，预期 1 次）")
    return text

def insert_before(text, anchor, addition, name):
    n = text.count(anchor)
    if n == 1:
        log(True, name)
        return text.replace(anchor, addition + anchor)
    log(False, f"{name}（锚点出现 {n} 次，预期 1 次）")
    return text

def delete_block(text, start_anchor, name):
    """从 start_anchor 删到下一个顶格 func/var/const/# ═ 为止（保留终点）。"""
    s = text.find(start_anchor)
    if s < 0 or text.count(start_anchor) != 1:
        log(False, f"{name}（起点锚未唯一命中）")
        return text
    tail = text[s + len(start_anchor):]
    ends = []
    for tok in ("\nfunc ", "\nvar ", "\nconst ", "\n# \u2550"):
        i = tail.find(tok)
        if i >= 0:
            ends.append(i)
    if not ends:
        log(False, f"{name}（找不到终点）")
        return text
    e = s + len(start_anchor) + min(ends) + 1  # keep the leading newline of the end token
    log(True, name)
    return text[:s] + text[e:]

def delete_exact(text, block, name):
    n = text.count(block)
    if n == 1:
        log(True, name)
        return text.replace(block, "")
    log(False, f"{name}（块出现 {n} 次，预期 1 次）")
    return text

# ══════════════════════════════════════════
#  Main.gd
# ══════════════════════════════════════════
def patch_main(text):
    print("\n[Main.gd]")

    # ── BUG 修复 ──
    text = replace_once(text,
        "$PetGrsoup/VBox.visible = true",
        "$PetGroup/VBox.visible = true",
        "[BUG] PetGrsoup 拼写修复")

    # ── 死代码删除 ──
    text = delete_exact(text,
        "var sfx: Dictionary = {}   # name -> AudioStreamPlayer\n",
        "[DEL] var sfx")
    text = delete_block(text, "func _build_sfx() -> void:", "[DEL] _build_sfx()")
    text = delete_exact(text, "var profile_detail_label: Label\n", "[DEL] var profile_detail_label")
    text = delete_block(text, "func _compose_profile_detail() -> String:", "[DEL] _compose_profile_detail()")
    text = delete_block(text, "func _profile_add_record_summary() -> void:", "[DEL] _profile_add_record_summary()")
    text = delete_block(text,
        "func _build_life_section_card(icon_path: String, title_zh: String, title_en: String) -> Dictionary:",
        "[DEL] _build_life_section_card()")
    text = delete_block(text,
        "func _build_label_value_row(label_text: String, value_text: String) -> HBoxContainer:",
        "[DEL] _build_label_value_row()")
    text = delete_block(text,
        "func _record_has_age_prefix(zh: String, en: String) -> bool:",
        "[DEL] _record_has_age_prefix()")
    text = delete_exact(text,
        'var breakthrough_fail_flavor := [\n'
        '\t{"zh": "今日突破失败，但似乎有所领悟。", "en": "Today\'s breakthrough failed, but something seems to have clicked."},\n'
        '\t{"zh": "又被天道拒绝了一次。", "en": "Rejected by heaven\'s will, once again."},\n'
        '\t{"zh": "距离成功似乎更近了一步。", "en": "It feels like success is one step closer."}\n'
        ']\n',
        "[DEL] breakthrough_fail_flavor")
    text = delete_exact(text, "var breakthrough_fail_reasons: Array = []\n", "[DEL] var breakthrough_fail_reasons")
    text = delete_exact(text,
        "func _karma_on_death(_cause_id: String) -> void:\n"
        "\tpass   # future: adjust karma based on how you died\n"
        "func _destiny_on_reincarnate(_new_life: int) -> void:\n"
        "\tpass   # future: roll destiny / fate for the new life\n"
        "func _bloodline_on_reincarnate(_new_life: int) -> void:\n"
        "\tpass   # future: inherit or mutate bloodline across lives\n",
        "[DEL] karma/destiny/bloodline 空壳")
    text = delete_exact(text,
        '\tcert_body_vbox.add_theme_constant_override("separation", 5)\n',
        "[DEL] 证书 separation 重复行")

    # ── FEAT: 顶部变量（退出挽留语）──
    text = insert_after(text,
        "const DEMO_DEATH_AT_REALM := 3         # 触发境界（3 = 武者初期）\n",
        '\n# ── 关闭挽留语 ──\n'
        'var _quitting := false\n'
        'const FAREWELL_LINES := [\n'
        '\t{"zh": "这就走了？那我继续闭关了。", "en": "Leaving already? Back to seclusion, then."},\n'
        '\t{"zh": "明天见。说不定明天我就突破了。", "en": "See you tomorrow. I might just break through."},\n'
        '\t{"zh": "走了也别忘了我还在修炼。", "en": "Don\'t forget — I\'ll still be cultivating."},\n'
        '\t{"zh": "去吧去吧，凡人的事也很重要。", "en": "Go on. Mortal business matters too."},\n'
        '\t{"zh": "我会想你的……才怪。", "en": "I\'ll miss you... as if."},\n'
        ']\n',
        "[FEAT] FAREWELL_LINES + _quitting")

    # ── FEAT: 关闭时不直接退出 ──
    text = insert_after(text,
        "\trandomize()\n",
        "\tget_tree().set_auto_accept_quit(false)   # 关闭时先说再见再退出\n",
        "[FEAT] set_auto_accept_quit(false)")

    # ── FEAT: 报事件定时器 → 自调度变频 ──
    text = replace_once(text,
        "\tvar event_timer := Timer.new()\n"
        "\tevent_timer.wait_time = 45.0\n"
        "\tevent_timer.timeout.connect(_on_report_event_timeout)\n"
        "\tadd_child(event_timer)\n"
        "\tevent_timer.start()\n",
        "\t_schedule_next_report_event()\n",
        "[FEAT] 报事件定时器改为自调度")

    # ── FEAT: EventManager 气泡事件同步加密（挂 interval_provider）──
    text = insert_after(text,
        '\tevent_manager.realm_provider = func (): return int(state.get("realm_index", 0))   # ← add\n',
        '\tevent_manager.interval_provider = func (): return 0.45 if _current_age() <= 30 else 1.0   # 新一世童年期事件更密\n',
        "[FEAT] event_manager.interval_provider 接线")

    # ── FEAT: 新函数（变频调度 + 退出流程）──
    text = insert_after(text,
        "func _on_report_event_timeout() -> void:\n"
        "\tif is_afk:\n"
        "\t\tif _afk_skip_next_report:\n"
        "\t\t\t_afk_skip_next_report = false\n"
        "\t\t\treturn\n"
        "\t\t_afk_skip_next_report = true\n"
        "\ttrigger_report_event()\n",
        "\n"
        "# ── 报事件调度：新一世童年期更密，第一世稍密 ──\n"
        "func _report_event_interval() -> float:\n"
        "\tif _current_age() <= 30:\n"
        "\t\treturn randf_range(18.0, 26.0)\n"
        "\tif int(state.get(\"life_count\", 1)) == 1:\n"
        "\t\treturn randf_range(30.0, 40.0)\n"
        "\treturn randf_range(40.0, 50.0)\n"
        "\n"
        "func _schedule_next_report_event() -> void:\n"
        "\tvar t := get_tree().create_timer(_report_event_interval())\n"
        "\tt.timeout.connect(func ():\n"
        "\t\t_on_report_event_timeout()\n"
        "\t\t_schedule_next_report_event()\n"
        "\t)\n"
        "\n"
        "# ── 关闭挽留语 ──\n"
        "func _notification(what: int) -> void:\n"
        "\tif what == NOTIFICATION_WM_CLOSE_REQUEST:\n"
        "\t\t_on_quit_requested()\n"
        "\n"
        "func _on_quit_requested() -> void:\n"
        "\tif _quitting:\n"
        "\t\tget_tree().quit()   # 二次触发直接放行，绝不卡住玩家\n"
        "\t\treturn\n"
        "\t_quitting = true\n"
        "\tsave_game()\n"
        "\tvar line: Dictionary = FAREWELL_LINES.pick_random()\n"
        "\tshow_message_now(line[\"zh\"] if current_language == \"zh\" else line[\"en\"])\n"
        "\tawait get_tree().create_timer(1.6).timeout\n"
        "\tget_tree().quit()\n",
        "[FEAT] _report_event_interval / _schedule_next_report_event / 退出流程")

    # ── FEAT: 右键菜单加"退出" ──
    text = insert_after(text,
        '\tcontext_menu.add_item("重置存档…" if current_language == "zh" else "Reset Save…", 4)\n',
        '\tcontext_menu.add_separator()\n'
        '\tcontext_menu.add_item("退出" if current_language == "zh" else "Quit", 5)\n',
        "[FEAT] 右键菜单：退出项")

    text = insert_after(text,
        "\t\t4:\n"
        "\t\t\t_confirm_reset()\n",
        "\t\t5:\n"
        "\t\t\t_on_quit_requested()\n",
        "[FEAT] 菜单处理：id=5 退出")

    # ── FEAT: 证书分享按钮 ──
    text = insert_after(text,
        "var certificate_panel: Control\n",
        "var cert_share_button: Button\n",
        "[FEAT] var cert_share_button")

    text = insert_before(text,
        "\tcertificate_panel.gui_input.connect(func (e):",
        "\t# 保存分享按钮（左下角，截图时自动隐藏不入镜）\n"
        "\tcert_share_button = Button.new()\n"
        "\tcert_share_button.text = \"保存分享 📜\"\n"
        "\tcert_share_button.add_theme_font_size_override(\"font_size\", 11)\n"
        "\tcert_share_button.position = Vector2(14, CERT_SIZE.y - 36)\n"
        "\tcert_share_button.pressed.connect(func():\n"
        "\t\tcert_share_button.visible = false\n"
        "\t\tawait ShareCapture.share_panel(certificate_panel)\n"
        "\t\tcert_share_button.visible = true\n"
        "\t)\n"
        "\tcertificate_panel.add_child(cert_share_button)\n\n",
        "[FEAT] 证书面板分享按钮")

    text = insert_after(text,
        '\tcert_hint_label.text = ""\n',
        '\tif cert_share_button != null:\n'
        '\t\tcert_share_button.text = "保存分享 📜" if zh else "Save & Share 📜"\n',
        "[FEAT] 分享按钮双语刷新")

    return text

# ══════════════════════════════════════════
#  EventManager.gd
# ══════════════════════════════════════════
def patch_event_manager(text):
    print("\n[EventManager.gd]")
    text = insert_after(text,
        "var luck_provider: Callable                # func () -> int (1..100)\n",
        "var interval_provider: Callable            # func () -> float，事件间隔倍率（1.0=正常，<1 更密）\n",
        "[FEAT] var interval_provider")
    text = insert_after(text,
        "\tvar wait := randf_range(MIN_INTERVAL, MAX_INTERVAL)\n",
        "\tif interval_provider.is_valid():\n"
        "\t\twait *= clampf(float(interval_provider.call()), 0.2, 2.0)\n",
        "[FEAT] _schedule_next 应用倍率")
    return text

# ══════════════════════════════════════════
def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    for path in args:
        with io.open(path, "r", encoding="utf-8") as f:
            text = f.read()
        low = path.lower()
        if "main" in low:
            text = patch_main(text)
            out = path.replace(".gd", "_patched.gd")
        elif "event" in low:
            text = patch_event_manager(text)
            out = path.replace(".gd", "_patched.gd")
        else:
            print(f"跳过未识别文件: {path}")
            continue
        with io.open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"→ 已写出 {out}")

    ok = sum(1 for r, _ in results if r)
    bad = [n for r, n in results if not r]
    print(f"\n完成：{ok}/{len(results)} 条编辑成功。")
    if bad:
        print("以下条目未命中，请按 Main_patch.md 手动处理：")
        for n in bad:
            print("  - " + n)

if __name__ == "__main__":
    main()
