extends SceneTree
## 第34段: (1) サウンドテストの再生中ハイライト (BGM は選択行、
## 効果音は開始/終了シグナル連動)、(2) gra が見つからない時の
## 既定グラ (スキンの Chara/Index.txt、LANU 系も読む)、
## (3) 地図ズームの追いかけ (タブ切り替え直後の一時的な縮小
## から収まる倍率へ戻る)。

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
	# -- (2) 既定グラ --
	var assets := GameAssets.new()
	var roots: Array[String] = ["/tmp/grafixture"]
	var empty: Array[String] = []
	assets.setup(roots, empty, empty, "Mine")
	check(assets.chara("ZeruGrade", "human", 0) != null, "gra human は既定グラ (人・銅像) になる")
	check(assets.chara("Oyaji", "LANU_Oyaji", 1) != null, "LANU 系の gra も読める")
	check(assets.chara("Nobody", "no_such_gra_xyz", 1) != null, "未知の gra は既定グラ (知的生物)")

	# -- (1) サウンドテストのハイライト --
	var config := PhiConfig.new()
	config.sound_play = true
	config.play_bgm = true
	var engine := PhiSoundEngine.new()
	root.add_child(engine)
	engine.setup(config, ["/tmp/sefixture"])
	var win := PhiSoundTestWindow.new()
	root.add_child(win)
	win.setup(engine, ["/tmp/sefixture"], ["beep.wav"], ["song_a", "song_b"], true, true)
	var se_list: ItemList = win.get("_se_list")
	var bgm_list: ItemList = win.get("_bgm_list")
	check(se_list.item_count == 1 and bgm_list.item_count == 2, "一覧が並ぶ")
	# 効果音: 鳴り始めで選択、終わりで解除。
	var started: Array = []
	var finished: Array = []
	engine.se_started.connect(func(p: String) -> void: started.append(p))
	engine.se_finished.connect(func(p: String) -> void: finished.append(p))
	engine.play_se_entry("sound/se/beep.wav")
	check(started.size() == 1, "se_started が出る")
	check(Array(se_list.get_selected_items()) == [0], "再生中の効果音がハイライト")
	await create_timer(0.8).timeout
	check(finished.size() == 1, "se_finished が出る")
	check(se_list.get_selected_items().is_empty(), "鳴り終わるとハイライト解除")
	# BGM: 選んだ行がハイライト、停止で解除。
	win.call("_play_bgm_at", 1)
	bgm_list.select(1)
	check(Array(bgm_list.get_selected_items()) == [1], "再生中の BGM がハイライト")
	win.free()
	engine.free()

	# -- (3) ズームの追いかけ --
	var mv := MapView.new()
	root.add_child(mv)
	mv.zoom = 1
	mv.size = Vector2(1100, 1056) # 7x7 で fit 4
	mv.request_zoom_growth()
	await create_timer(0.5).timeout
	check(mv.zoom == 4, "要求から収まる倍率まで追いつく: " + str(mv.zoom))
	# 一時的な縮小 (タブ切り替えの揺れ) の後も戻る。
	mv.size = Vector2(400, 500)
	await create_timer(0.15).timeout
	check(mv.zoom < 4, "一時的な縮小では落ちる: " + str(mv.zoom))
	mv.size = Vector2(1100, 1056)
	await create_timer(0.5).timeout
	check(mv.zoom == 4, "余地が戻れば追いつく: " + str(mv.zoom))
	mv.free()

	print("stage34 checks=", _checks, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
