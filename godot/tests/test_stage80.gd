extends SceneTree
## 第80段のテスト: BGM ゲートの「忙しい」判定は、受信が大量に
## 溜まっている時だけにする。発言のエコー (数行) では曲が
## 止まらないこと、洪水時には従来どおり止まることを確認する。
##
## 使い方: godot --headless --path . -s tests/test_stage80.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0
var _tab: PhiCharacter = null
var _frames := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	var config := PhiConfig.new()
	config.log_auto_save = false
	var font := PhiFont.make_ui_font()
	var bold := PhiFont.make_bold_font()
	_tab = PhiCharacter.new()
	_tab.setup(GameAssets.new(), config, font, bold, PhiLogFilter.new(), PhiTagMenu.parse(PhiTagMenu.DEFAULT_XML))
	root.add_child(_tab)
	_tab.position = Vector2.ZERO
	_tab.size = Vector2(1280, 1024)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 3:
		_test_activity_busy()
		print("test_stage80: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_activity_busy() -> void:
	var tab := _tab
	# (1) 何も溜まっていなければ忙しくない。
	tab.set("_log_batch", [])
	_check(not tab._bgm_activity_busy(), "s80 idle is not busy")
	# (2) 発言のエコー程度 (数行) では忙しくない → 曲は止まらない。
	var echo: Array = []
	for i in range(3):
		echo.append(["text", "line", ""])
	tab.set("_log_batch", echo)
	_check(not tab._bgm_activity_busy(), "s80 speech echo is not busy")
	# (3) しきい値ちょうど (30行) でもまだ忙しくない。
	var thirty: Array = []
	for i in range(30):
		thirty.append(["text", "line", ""])
	tab.set("_log_batch", thirty)
	_check(not tab._bgm_activity_busy(), "s80 30 lines is not busy")
	# (4) しきい値を超えたら忙しい (洪水時は従来どおり止める)。
	var flood: Array = []
	for i in range(31):
		flood.append(["text", "line", ""])
	tab.set("_log_batch", flood)
	_check(tab._bgm_activity_busy(), "s80 31 lines is busy")
	tab.set("_log_batch", [])
