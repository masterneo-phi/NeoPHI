extends SceneTree
## 地図の余白のモノグラム壁紙のテスト。
##
## 使い方: godot --headless --path . -s tests/test_wallpaper.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _initialize() -> void:
	_test_wallpaper()
	print("test_wallpaper: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _test_wallpaper() -> void:
	# 壁紙の絵があり、タイルの大きさと一致する。
	_check(ResourceLoader.exists(MapView.WALLPAPER_PATH), "wallpaper exists")
	var tex := load(MapView.WALLPAPER_PATH) as Texture2D
	_check(tex != null, "wallpaper loads")
	_check_eq(tex.get_size(), MapView.WALLPAPER_TILE, "wallpaper size is tile size")
	# MapView が壁紙を持ち、無くても動く作りである。
	var view := MapView.new()
	_check(view.wallpaper_texture() != null, "view wallpaper texture")
	_check(view.get("_wallpaper") != null, "view has wallpaper")
	_check(MapView.WALLPAPER_MODULATE.r > 0.0 and MapView.WALLPAPER_MODULATE.r <= 1.0, "modulate in range")
	view.free()
