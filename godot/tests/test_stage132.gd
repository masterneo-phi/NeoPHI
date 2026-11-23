extends SceneTree
## 第132段: りんぐ報告 (2026-11-23)。Pay などのポップアップ
## ダイアログと看板窓で、題名は通常の大きさなのに説明文だけが
## 小さかった。原因は、ダイアログ本文の文字サイズが全体の
## フォント設定 (MenuFontSize) ではなく地図の倍率連動のまま
## 残っていたこと。リストとステータスパネルは第125段で
## MenuFontSize 追従に直したが、ダイアログ系が漏れていた。
## 題名は本文×1.3 (下限18) で決まるため、題名だけ正常に
## 見えていた。あわせて、テーマと題名は作った時点で固定
## されるため、設定変更後に付け直されることも見る。
##
## 使い方: godot --headless --path . -s tests/test_stage132.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

const Main := preload("res://scripts/main.gd")

var _failures := 0
var _checks := 0
var _main: Node = null


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _initialize() -> void:
	call_deferred("_run")


func _find_label(node: Node, prefix: String) -> Label:
	for c in node.get_children():
		if c is Label and (c as Label).text.begins_with(prefix):
			return c as Label
		var found := _find_label(c, prefix)
		if found != null:
			return found
	return null


func _run() -> void:
	var main = Main.new()
	for p in ["user://stage132_tabs.ini", "user://stage132_cfg.ini"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main.set("_tab_session_path", "user://stage132_tabs.ini")
	main.set("_config_path", "user://stage132_cfg.ini")
	root.add_child(main)
	_main = main
	await process_frame
	await process_frame
	var config = main.get("_config")
	config.menu_font_size = 30
	_test_size_source()
	_test_ask_dialog()
	await process_frame
	_test_medit_window()
	print("test_stage132: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


# -- サイズの出どころ -----------------------------------------------------------

func _test_size_source() -> void:
	var main = _main
	# 本文は MenuFontSize から決まる (倍率連動ではない)。
	check_eq(main._dialog_body_size(), 30, "s132 body size follows menu font")
	# 題名は従来どおり本文×1.3 (下限18)。
	check_eq(main._title_font_size(), 39, "s132 title size is body x1.3")
	var theme: Theme = main._dialog_theme()
	check_eq(theme.get_font_size("font_size", "Label"), 30, "s132 theme label follows menu font")
	check_eq(theme.get_font_size("font_size", "LineEdit"), 30, "s132 theme edit follows menu font")
	check_eq(theme.get_font_size("font_size", "Button"), 30, "s132 theme button follows menu font")
	check_eq(theme.get_font_size("font_size", "CheckBox"), 30, "s132 theme checkbox follows menu font")
	check_eq(theme.get_font_size("normal_font_size", "RichTextLabel"), 30, "s132 theme rich text follows menu font")


# -- Pay (ask ダイアログ) -------------------------------------------------------

func _test_ask_dialog() -> void:
	var main = _main
	main._ask_text("Pay")
	var dlg: ConfirmationDialog = main.get("_ask_dialog")
	var title: Label = main.get("_ask_title")
	var label: Label = main.get("_ask_label")
	var edit: LineEdit = main.get("_ask_edit")
	check_eq(title.text, "支払い金額", "s132 ask title text")
	check_eq(label.text, "支払う金額を入力してください", "s132 ask label text")
	# 説明文も設定どおりの大きさになる (題名だけ大きくない)。
	check_eq(label.get_theme_font_size("font_size"), 30, "s132 ask description follows menu font")
	check_eq(edit.get_theme_font_size("font_size"), 30, "s132 ask edit follows menu font")
	check_eq(dlg.get_ok_button().get_theme_font_size("font_size"), 30, "s132 ask ok button follows menu font")
	check_eq(title.get_theme_font_size("font_size"), 39, "s132 ask title size")
	dlg.hide()
	# 設定を変えて出し直すと、新しい大きさに追従する。
	(main.get("_config") as PhiConfig).menu_font_size = 18
	main._ask_text("Pay")
	check_eq(label.get_theme_font_size("font_size"), 18, "s132 ask description follows menu font change")
	check_eq(title.get_theme_font_size("font_size"), 23, "s132 ask title follows menu font change")
	dlg.hide()
	# 作り済みのダイアログは、テーマの付け直しでも追従する。
	(main.get("_config") as PhiConfig).menu_font_size = 24
	main._refresh_dialog_themes()
	check_eq(dlg.theme.get_font_size("font_size", "Label"), 24, "s132 dialog theme refreshed")
	check_eq(label.get_theme_font_size("font_size"), 24, "s132 ask description follows theme refresh")
	(main.get("_config") as PhiConfig).menu_font_size = 30


# -- 看板窓 (medit) --------------------------------------------------------------

func _test_medit_window() -> void:
	var main = _main
	var tab: PhiCharacter = main.call("_active_tab")
	check(tab != null, "s132 active tab exists")
	if tab == null:
		return
	main._on_tab_edit_requested("multi", tab)
	var win: Window = main.get("_medit_window")
	check(win != null, "s132 medit window created")
	if win == null:
		return
	var title: Label = win.get("_title_label")
	var edit: TextEdit = win.get("_edit")
	check_eq(title.get_theme_font_size("font_size"), 39, "s132 medit title size")
	check_eq(edit.get_theme_font_size("font_size"), 30, "s132 medit body follows menu font")
	# 下部の説明文 (テーマ任せのラベル) も設定どおりになる。
	var hint := _find_label(win, "送信")
	check(hint != null, "s132 medit hint label exists")
	if hint != null:
		check_eq(hint.get_theme_font_size("font_size"), 30, "s132 medit hint follows menu font")
	main._on_tab_edit_requested("end", tab)
