extends SceneTree
## 第42段: ログの下端の余白。
## 最終行が枠の下端に張り付かないよう、ログの地 (StyleBox) の
## 下マージンが文字サイズに比例して付くことを見る。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _bottom(tab: PhiCharacter) -> float:
	var box := tab.log_view.get_theme_stylebox("normal")
	return box.content_margin_bottom


func _run() -> void:
	var ps := load("res://main.tscn") as PackedScene
	var main: Node = ps.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var tab: PhiCharacter = main.call("_active_tab")
	check(tab != null, "active tab exists")
	# 下端余白は旧スタイル (分割配置) のログの仕様。新スタイルでは
	# フロート窓の大きさから文字サイズが決まるので、ここでは旧にする。
	(main.get("_config") as PhiConfig).ui_style = "old"
	tab.apply_ui_style()
	check(tab.get("_log_box") != null, "log stylebox duplicated")
	# 起動時点のズーム (設定由来) でも、余白が文字サイズ比例で付いている
	var start_size := PhiFont.ui_size_for_zoom(tab.map_view.zoom)
	var want_start := maxf(6.0, roundf(float(start_size) * 0.7))
	check(_bottom(tab) == want_start, "bottom margin follows zoom %d (got %s want %s)" % [tab.map_view.zoom, _bottom(tab), want_start])
	# ズーム 4 (文字 22) → 15、ズーム 2 (文字 10) → 7、ズーム 1 (文字 6) → 下限 6
	tab.map_view.zoom = 4
	tab.refresh_ui_font_size()
	check(_bottom(tab) == 15.0, "bottom margin 15 at zoom 4 (got %s)" % _bottom(tab))
	# ズーム 2 (文字 10) → 7、ズーム 1 (文字 6) → 下限 6
	tab.map_view.zoom = 2
	tab.refresh_ui_font_size()
	check(_bottom(tab) == 7.0, "bottom margin 7 at zoom 2 (got %s)" % _bottom(tab))
	tab.map_view.zoom = 1
	tab.refresh_ui_font_size()
	check(_bottom(tab) == 6.0, "bottom margin floor 6 at zoom 1 (got %s)" % _bottom(tab))
	tab.map_view.zoom = 4
	tab.refresh_ui_font_size()
	check(_bottom(tab) == 15.0, "bottom margin back to 15 at zoom 4")
	# テーマ共有の地を汚していないこと (複製側だけに付く)
	var fresh := RichTextLabel.new()
	check(fresh.get_theme_stylebox("normal").content_margin_bottom < 15.0, "shared theme box untouched")
	fresh.free()
	# スキンの地が付け直されても、余白は付け直された地に付く
	tab.call("_apply_log_css")
	tab.refresh_ui_font_size()
	check(_bottom(tab) == 15.0, "margin survives log css re-apply (got %s)" % _bottom(tab))
	# 本文サイズが変わったら、時刻サイズ統一のためログ全体の
	# 描き直しが予約される (同じサイズでは予約されない)
	tab.log_message("log", "時刻サイズ確認の行です")
	await process_frame
	check(not bool(tab.get("_img_rebuild_queued")), "no rebuild queued at same size")
	tab.map_view.zoom = 2
	tab.refresh_ui_font_size()
	check(bool(tab.get("_img_rebuild_queued")), "rebuild queued on font size change")
	await process_frame
	await process_frame
	check(not bool(tab.get("_img_rebuild_queued")), "rebuild done after frames")
	main.queue_free()

	print("stage42: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
