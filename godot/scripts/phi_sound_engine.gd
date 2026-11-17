class_name PhiSoundEngine
extends Node
## 音の司令塔(第5段)。全タブ共有でメイン画面が1つ持つ。
##
## 効果音: 各タブから受けたログ行を PhiSeRules に照合し、
## 合った .wav を小さなプールで鳴らす(Philly は1音だけだが、
## ここでは同時に鳴っても破綻しないよう数チャンネル用意し、
## 空きが無ければ一番古いものを止めて使う)。ファイルが
## 見つからなければ無音。ファイル名が空のルールは、Philly と
## 同じく注意を促す合図(タスクバーフラッシュ相当)にする。
##
## BGM: PhiBgmPlayer への橋渡し。どのタブの曲を鳴らすかの
## 判断はメイン画面が行う。

signal se_requested(path: String)
## 効果音が鳴り始めた / 鳴り終わった (サウンドテストの
## ハイライト用)。path は解決済みのファイルパス。
signal se_started(path: String)
signal se_finished(path: String)
signal flash_requested

## 同時に鳴らせる効果音の数。
const SE_CHANNELS := 4
## 効果音の音量 (dB)。合成波形の効果音は BGM (MIDI) より大きく
## 聞こえるので、振幅で 1/4 程度に落とす (ユーザーの指定)。
const SE_VOLUME_DB := -12.0

var _config: PhiConfig = null
var _roots: Array = []
var _rules := PhiSeRules.new()
var _bgm := PhiBgmPlayer.new()
var _se_players: Array[AudioStreamPlayer] = []
var _se_streams: Dictionary = {} # path -> AudioStream(読めなかったら null)
var _se_next := 0
var _se_playing_paths: Array[String] = [] # チャンネルごとの再生中パス


func _init() -> void:
	add_child(_bgm)
	for i in range(SE_CHANNELS):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = SE_VOLUME_DB
		add_child(player)
		_se_players.append(player)
		_se_playing_paths.append("")
		var ch := i
		player.finished.connect(func() -> void:
			var done := _se_playing_paths[ch]
			_se_playing_paths[ch] = ""
			if not done.is_empty():
				se_finished.emit(done))


func setup(p_config: PhiConfig, roots: Array) -> void:
	_config = p_config
	_roots = roots.duplicate()
	_bgm.soundfont_path = PhiSoundPaths.resolve_soundfont(_roots)


func set_se_texts(regexp_text: String, file_text: String) -> void:
	## SoundRegexp.ini / SoundFile.ini の中身を読み直す。
	_rules.load_texts(regexp_text, file_text)


func se_rule_count() -> int:
	return _rules.rule_count()


func soundfont_path() -> String:
	return _bgm.soundfont_path


func play_se_for_line(line: String) -> void:
	## ログ行1行に対して効果音を判定し、鳴らす。
	if _config == null or not _config.sound_play:
		return
	var entry := _rules.match_entry(line)
	if entry.is_empty():
		return
	if bool(entry["flash"]):
		flash_requested.emit()
		DisplayServer.window_request_attention()
		return
	var path := PhiSoundPaths.resolve_se(str(entry["file"]), _roots)
	if path.is_empty():
		return # ファイルが無ければ無音で何もしない
	se_requested.emit(path)
	_play_se(path)


func play_se_entry(entry: String) -> void:
	## ログ行を介さない直接の効果音 (壁ぶつかり・選択・priv 受信
	## など、クライアント側の出来事用)。表記は SoundFile.ini と
	## 同じ (ルートからの相対か絶対)。
	if _config == null or not _config.sound_play:
		return
	var path := PhiSoundPaths.resolve_se(entry, _roots)
	if path.is_empty():
		return
	se_requested.emit(path)
	_play_se(path)


func _play_se(path: String) -> void:
	var stream: Variant = _se_streams.get(path, false)
	if stream is bool:
		stream = PhiWav.load_audio_file(path)
		_se_streams[path] = stream
	if stream == null:
		return
	var ch := _se_next
	_se_next = (_se_next + 1) % _se_players.size()
	var player := _se_players[ch]
	# 使い回すチャンネルで前の音がまだ鳴っていたら、そちらの
	# 終了として先に知らせる (finished は来ないため)。
	var prev := _se_playing_paths[ch]
	if player.playing and not prev.is_empty():
		se_finished.emit(prev)
	player.stream = stream
	player.play()
	_se_playing_paths[ch] = path
	se_started.emit(path)


# -- BGM の橋渡し ------------------------------------------------------------

func bgm_play(path: String) -> bool:
	if _config != null and not _config.play_bgm:
		return false
	return _bgm.play(path)


func bgm_stop() -> void:
	_bgm.stop()


func bgm_pause() -> void:
	_bgm.pause()


func bgm_resume() -> void:
	_bgm.resume()


func bgm_set_speed(percent: int) -> void:
	_bgm.set_speed(percent)


func bgm_current_path() -> String:
	return _bgm.current_path()


func bgm_state() -> String:
	return _bgm.state()


func bgm_player() -> PhiBgmPlayer:
	return _bgm
