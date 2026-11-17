extends SceneTree
## 第23段: 効果音の音量・ポップアップの収まり・タイトル帯の色の確認。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	# 効果音: 全プレイヤーが -12dB (振幅 1/4) になっている。
	var engine := PhiSoundEngine.new()
	root.add_child(engine)
	check(engine._se_players.size() == PhiSoundEngine.SE_CHANNELS, "SE プレイヤーの数")
	for p in engine._se_players:
		check(absf(p.volume_db - PhiSoundEngine.SE_VOLUME_DB) < 0.01, "SE 音量が下がっている")
	check(PhiSoundEngine.SE_VOLUME_DB <= -11.9 and PhiSoundEngine.SE_VOLUME_DB >= -12.1,
		"SE 音量は -12dB (半分のさらに半分)")
	engine.queue_free()
	# ポップアップの大きさ: 親窓に収まる範囲に丸める。
	check(UiStyle.fit_popup_size(Vector2i(800, 560), Vector2i(1700, 1300)) == Vector2i(800, 560),
		"大きい親ではそのまま")
	check(UiStyle.fit_popup_size(Vector2i(800, 560), Vector2i(700, 500)) == Vector2i(676, 476),
		"小さい親では収まる大きさに")
	check(UiStyle.fit_popup_size(Vector2i(880, 420), Vector2i(1280, 1024)) == Vector2i(880, 420),
		"中くらいではそのまま")
	# タイトル帯: 最初の濃紺 (0.05,0.09,0.28) より明るい。
	check(UiStyle.TITLE_NAVY.b > 0.45 and UiStyle.TITLE_NAVY.r > 0.1,
		"タイトル帯は明るめの濃紺: %s" % str(UiStyle.TITLE_NAVY))
	print("test_stage23: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
