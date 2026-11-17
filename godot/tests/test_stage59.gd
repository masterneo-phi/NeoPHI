extends SceneTree
## 第59段: タグの [b] [i] が描けるよう、太字・斜体フォントを
## ログと看板プレビューへ明示する。今までは未指定で既定テーマの
## フォント (日本語なし) に落ち、太さも傾きも出なかった。
## あわせて看板窓へ body_font が渡っていなかったのも直す。

const MeditScene := preload("res://scripts/phi_medit_window.gd")

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# フォント生成: 斜体は変形、太字+斜体は embolden も付く。
	var it := PhiFont.make_italics_font()
	check(it is FontVariation, "italics font is a variation")
	check((it as FontVariation).variation_transform != Transform2D.IDENTITY, "italics font is sheared")
	var bi := PhiFont.make_bold_italics_font()
	check((bi as FontVariation).variation_embolden > 0.0, "bold-italics is emboldened")
	check((bi as FontVariation).variation_transform != Transform2D.IDENTITY, "bold-italics is sheared")
	# メイン画面経由のタブ: ログに3種の上書きが付く。
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	var tab: Variant = main.call("_active_tab")
	check(tab.log_view.has_theme_font_override("normal_font"), "log normal_font set")
	check(tab.log_view.has_theme_font_override("bold_font"), "log bold_font set")
	check(tab.log_view.has_theme_font_override("italics_font"), "log italics_font set")
	check(tab.log_view.has_theme_font_override("bold_italics_font"), "log bold_italics_font set")
	# 看板窓: Main と同じ渡し方でプレビューにも付く。
	var w: Window = MeditScene.new()
	w.body_font = main.get("_font")
	w.bold_font = main.get("_bold_font")
	w.italics_font = main.get("_italics_font")
	w.bold_italics_font = main.get("_bold_italics_font")
	root.add_child(w)
	w.show_editor("テスト")
	check(w._preview.has_theme_font_override("bold_font"), "preview bold_font set")
	check(w._preview.has_theme_font_override("italics_font"), "preview italics_font set")
	check(w._preview.has_theme_font_override("bold_italics_font"), "preview bold_italics_font set")
	w.queue_free()
	main.queue_free()

	print("stage59: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
