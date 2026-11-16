extends SceneTree
## 第5段(音: 効果音と BGM)のテスト。
##
## 使い方: godot --headless --path . -s tests/test_stage5.gd
## 終了コード 0 = 全一致、1 = 不一致あり。
##
## 音そのものはこの環境では鳴らせないので、再生要求が正しく
## 発行されること(パーサの通知、照合、場所探し、プレイヤーの
## 状態)までを確認する。実際に音が出るかは Mac 実機で確認する。

const TMP := "user://stage5test"
const ROOT1 := "user://stage5test/root1"

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
	Cp932.ensure_loaded()
	_make_tmp_files()
	_test_parser()
	_test_se_rules()
	_test_sound_paths()
	_test_wav()
	_test_config()
	# ツリーが動き出してからでないと、ノードの _ready が走らず
	# プレイヤーの初期化ができない。最初のフレームで始める。
	process_frame.connect(_run_tree_tests, CONNECT_ONE_SHOT)


# -- 準備 ----------------------------------------------------------------------

func _le16(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF])


func _le32(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])


func _wav_bytes(rate: int, bits: int, channels: int, frames: int) -> PackedByteArray:
	## 無音の WAV(PCM)のバイト列を作る。
	var bytes_per_sample := bits / 8
	var data_size := frames * channels * bytes_per_sample
	var b := PackedByteArray()
	b.append_array("RIFF".to_ascii_buffer())
	b.append_array(_le32(36 + data_size))
	b.append_array("WAVE".to_ascii_buffer())
	b.append_array("fmt ".to_ascii_buffer())
	b.append_array(_le32(16))
	b.append_array(_le16(1))
	b.append_array(_le16(channels))
	b.append_array(_le32(rate))
	b.append_array(_le32(rate * channels * bytes_per_sample))
	b.append_array(_le16(channels * bytes_per_sample))
	b.append_array(_le16(bits))
	b.append_array("data".to_ascii_buffer())
	b.append_array(_le32(data_size))
	b.resize(44 + data_size)
	return b


func _midi_bytes() -> PackedByteArray:
	## 最小の MIDI(format 0、ピアノで1音)。
	var b := PackedByteArray()
	b.append_array("MThd".to_ascii_buffer())
	b.append_array(PackedByteArray([0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]))
	var track := PackedByteArray()
	track.append_array(PackedByteArray([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]))
	track.append_array(PackedByteArray([0x00, 0xC0, 0x00]))
	track.append_array(PackedByteArray([0x00, 0x90, 0x3C, 0x64]))
	track.append_array(PackedByteArray([0x83, 0x60, 0x80, 0x3C, 0x00]))
	track.append_array(PackedByteArray([0x00, 0xFF, 0x2F, 0x00]))
	b.append_array("MTrk".to_ascii_buffer())
	b.append_array(PackedByteArray([0, 0, 0, track.size()]))
	b.append_array(track)
	return b


func _write_file(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _make_tmp_files() -> void:
	var base := ProjectSettings.globalize_path(TMP)
	DirAccess.make_dir_recursive_absolute(base + "/root1/sound/bgm")
	DirAccess.make_dir_recursive_absolute(base + "/root1/sound/s.e")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://sound/bgm"))
	_write_file(ROOT1 + "/sound/bgm/song.mid", _midi_bytes())
	_write_file(ROOT1 + "/sound/s.e/hit.wav", _wav_bytes(22050, 16, 1, 2205))
	_write_file(TMP + "/test.mid", _midi_bytes())
	_write_file(TMP + "/test.wav", _wav_bytes(22050, 16, 1, 2205))
	_write_file("user://sound/bgm/stage5_song.mid", _midi_bytes())


func _cleanup_tmp() -> void:
	var base := ProjectSettings.globalize_path(TMP)
	for path in [
		ROOT1 + "/sound/bgm/song.mid", ROOT1 + "/sound/s.e/hit.wav",
		TMP + "/test.mid", TMP + "/test.wav",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://sound/bgm/stage5_song.mid"))
	for dir in [
		"/root1/sound/bgm", "/root1/sound/s.e", "/root1/sound", "/root1", "",
	]:
		DirAccess.remove_absolute(base + dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://sound/bgm"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://sound"))


# -- パーサ ----------------------------------------------------------------------

func _feed(parser: PhiParser, line: String) -> Array:
	var out: Array = []
	for event in parser.feed(line.to_ascii_buffer()):
		out.append(event)
	return out


func _test_parser() -> void:
	# パーサ本体は wphi 互換で #bgm を無視する(golden の notice
	# シナリオに `#bgm Seiju` → イベント無しがある)。
	var parser := PhiParser.new()
	_check_eq(_feed(parser, "#bgm Seiju").size(), 0, "parser ignores bgm (golden)")
	_check_eq(_feed(parser, "#ex-bgm-speed 150").size(), 0, "parser ignores bgm speed")
	# 解釈は PhiParser.bgm_event_for_line が担う。
	var event := PhiParser.bgm_event_for_line("#bgm test")
	_check_eq(event.get("type"), "bgm", "bgm line type")
	_check_eq(event.get("name"), "test.mid", "bgm line adds .mid")
	event = PhiParser.bgm_event_for_line("#bgm song.mid")
	_check_eq(event.get("name"), "song.mid", "bgm line keeps .mid")
	event = PhiParser.bgm_event_for_line("#bgm BGM.WAV")
	_check_eq(event.get("name"), "BGM.WAV", "bgm line keeps wav")
	_check(PhiParser.bgm_event_for_line("#bgm").is_empty(), "bgm line no name")
	_check(PhiParser.bgm_event_for_line("#bgm ").is_empty(), "bgm line blank name")
	event = PhiParser.bgm_event_for_line("#ex-bgm-speed 150")
	_check_eq(event.get("type"), "bgmSpeed", "speed line type")
	_check_eq(event.get("speed"), 150, "speed line value")
	_check(PhiParser.bgm_event_for_line("#ex-bgm-speed abc").is_empty(), "speed line no digits")
	_check(PhiParser.bgm_event_for_line("#ex-bgm-speed").is_empty(), "speed line no value")
	_check(PhiParser.bgm_event_for_line("hello").is_empty(), "bgm line other")
	# セッションが行を受けて BGM イベントを出すところまで。
	var session := PhiSession.new()
	var got: Array = []
	session.event_received.connect(func(e: Dictionary) -> void: got.append(e))
	session._process_line("#bgm Seiju".to_ascii_buffer())
	_check_eq(got.size(), 1, "session bgm 1 event")
	if got.size() == 1:
		_check_eq(got[0].get("type"), "bgm", "session bgm type")
		_check_eq(got[0].get("name"), "Seiju.mid", "session bgm name")
	got.clear()
	session._process_line("#ex-bgm-speed 120".to_ascii_buffer())
	_check_eq(got.size(), 1, "session speed 1 event")
	if got.size() == 1:
		_check_eq(got[0].get("speed"), 120, "session speed value")
	got.clear()
	session._process_line("DM > hello".to_ascii_buffer())
	_check_eq(got.size(), 1, "session plain line 1 event")
	if got.size() == 1:
		_check_eq(got[0].get("type"), "message", "session plain line is message")


# -- 効果音のルール ---------------------------------------------------------------

const REGEXP_TEXT := "サウンドの正規表現文字列（ perl5 にほぼ準拠）\n/攻撃/\n/ダメージ/\n/([/\n"
const FILE_TEXT := "サウンドファイル名（.wav）空文字列でタスクバーフラッシュ\nsound\\s.e\\hit.wav\n\nx.wav\n"


func _test_se_rules() -> void:
	var rules := PhiSeRules.new()
	rules.load_texts(REGEXP_TEXT, FILE_TEXT)
	_check_eq(rules.rule_count(), 3, "se rules count")
	_check_eq(rules.bad_count, 1, "se rules bad pattern counted")
	var entry := rules.match_entry("DM > 猫 は あなた を攻撃した")
	_check(not entry.is_empty(), "se match attack")
	if not entry.is_empty():
		_check_eq(entry["index"], 1, "se match attack index")
		_check_eq(entry["file"], "sound\\s.e\\hit.wav", "se match attack file")
		_check_eq(entry["flash"], false, "se match attack not flash")
	entry = rules.match_entry("DM > ダメージを受けた")
	_check(not entry.is_empty(), "se match damage")
	if not entry.is_empty():
		_check_eq(entry["index"], 2, "se match damage index")
		_check_eq(entry["flash"], true, "se match damage flash (empty file)")
	entry = rules.match_entry("攻撃してダメージ")
	_check_eq(entry.get("index", 0), 1, "se first match wins")
	_check(rules.match_entry("関係ない行").is_empty(), "se no match")
	# 既定(説明文だけ)では何も合わない。
	var empty_rules := PhiSeRules.new()
	empty_rules.load_texts(PhiSeRules.DEFAULT_REGEXP_TEXT, PhiSeRules.DEFAULT_FILE_TEXT)
	_check_eq(empty_rules.rule_count(), 0, "se default no rules")
	_check(empty_rules.match_entry("攻撃").is_empty(), "se default no match")


# -- 場所探し ----------------------------------------------------------------------

func _test_sound_paths() -> void:
	_check_eq(PhiSoundPaths.normalize_entry("sound\\s.e\\hit.wav"), "sound/s.e/hit.wav", "paths normalize backslash")
	_check(PhiSoundPaths.is_absolute("/tmp/x.wav"), "paths absolute unix")
	_check(PhiSoundPaths.is_absolute("D:/home/x.wav"), "paths absolute drive")
	_check(not PhiSoundPaths.is_absolute("sound/x.wav"), "paths relative")
	_check_eq(PhiSoundPaths.resolve_se("sound\\s.e\\hit.wav", [ROOT1]), ROOT1 + "/sound/s.e/hit.wav", "paths se found")
	_check_eq(PhiSoundPaths.resolve_se("sound\\s.e\\none.wav", [ROOT1]), "", "paths se missing")
	_check_eq(PhiSoundPaths.resolve_se("", [ROOT1]), "", "paths se empty")
	var abs_wav := ProjectSettings.globalize_path(ROOT1 + "/sound/s.e/hit.wav")
	_check_eq(PhiSoundPaths.resolve_se(abs_wav, []), abs_wav, "paths se absolute found")
	_check_eq(PhiSoundPaths.resolve_se("/nonexistent/x.wav", [ROOT1]), "", "paths se absolute missing")
	_check_eq(PhiSoundPaths.resolve_bgm("song.mid", [ROOT1]), ROOT1 + "/sound/bgm/song.mid", "paths bgm found")
	_check_eq(PhiSoundPaths.resolve_bgm("none.mid", [ROOT1]), "", "paths bgm missing")
	_check_eq(PhiSoundPaths.resolve_bgm("stage5_song.mid", []), "user://sound/bgm/stage5_song.mid", "paths bgm user dir")
	_check_eq(PhiSoundPaths.resolve_soundfont([]), "res://assets/GeneralUser-GS.sf2", "paths soundfont bundled")


# -- WAV 読み込み -------------------------------------------------------------------

func _test_wav() -> void:
	var stream := PhiWav.parse_wav(_wav_bytes(22050, 16, 1, 100))
	_check(stream != null, "wav 16bit parsed")
	if stream != null:
		_check_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "wav 16bit format")
		_check_eq(stream.mix_rate, 22050, "wav rate")
		_check_eq(stream.stereo, false, "wav mono")
		_check_eq(stream.data.size(), 200, "wav data size")
	stream = PhiWav.parse_wav(_wav_bytes(44100, 8, 2, 50))
	_check(stream != null, "wav 8bit parsed")
	if stream != null:
		_check_eq(stream.format, AudioStreamWAV.FORMAT_8_BITS, "wav 8bit format")
		_check_eq(stream.stereo, true, "wav stereo")
		_check_eq(stream.data.size(), 100, "wav 8bit data size")
	stream = PhiWav.parse_wav(_wav_bytes(22050, 24, 1, 40))
	_check(stream != null, "wav 24bit parsed")
	if stream != null:
		_check_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "wav 24bit to 16bit")
		_check_eq(stream.data.size(), 80, "wav 24bit data size")
	_check(PhiWav.parse_wav(PackedByteArray()) == null, "wav empty null")
	_check(PhiWav.parse_wav("not a wav file at all........".to_ascii_buffer()) == null, "wav garbage null")
	var loaded := PhiWav.load_audio_file(TMP + "/test.wav")
	_check(loaded != null, "wav load from file")
	_check(PhiWav.load_audio_file(TMP + "/none.wav") == null, "wav missing null")


# -- 設定 ---------------------------------------------------------------------------

func _test_config() -> void:
	var config := PhiConfig.new()
	_check_eq(config.sound_play, true, "config sound_play default")
	_check_eq(config.play_bgm, true, "config play_bgm default")
	_check_eq(config.play_bgm_deactivate, false, "config play_bgm_deactivate default")
	config.sound_play = false
	config.play_bgm = false
	config.play_bgm_deactivate = true
	var path := TMP + "/test_config.ini"
	_check(config.save_file(path), "config save sound")
	var loaded := PhiConfig.new()
	_check(loaded.load_file(path), "config load sound")
	_check_eq(loaded.sound_play, false, "config sound_play saved")
	_check_eq(loaded.play_bgm, false, "config play_bgm saved")
	_check_eq(loaded.play_bgm_deactivate, true, "config play_bgm_deactivate saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# -- ツリーが要るテスト ---------------------------------------------------------------

func _run_tree_tests() -> void:
	await _test_bgm_player()
	await _test_engine()
	await _test_character_wiring()
	_cleanup_tmp()
	print("test_stage5: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _test_bgm_player() -> void:
	var bgm := PhiBgmPlayer.new()
	root.add_child(bgm)
	bgm.soundfont_path = "res://assets/GeneralUser-GS.sf2"
	_check(bgm.midi_available(), "bgm midi available")
	_check_eq(bgm.state(), "stop", "bgm initial stop")
	# MIDI 再生(サウンドフォントの読み込みで数秒かかる)。
	_check(bgm.play(TMP + "/test.mid"), "bgm play mid")
	_check_eq(bgm.state(), "playing", "bgm state playing")
	_check_eq(bgm.current_path(), TMP + "/test.mid", "bgm current path")
	var midi: Variant = bgm.get("_midi")
	_check(midi != null, "bgm midi player created")
	await create_timer(0.6).timeout
	if midi != null:
		_check((midi as MidiPlayer).position > 0.0, "bgm position advances")
		_check((midi as MidiPlayer).loop, "bgm loop on")
	# 同じ曲は再生し直さない。
	_check(bgm.play(TMP + "/test.mid"), "bgm replay same ok")
	_check_eq(bgm.state(), "playing", "bgm still playing")
	# 速度変更は MIDI に効く。
	bgm.set_speed(150)
	if midi != null:
		_check_eq((midi as MidiPlayer).play_speed, 1.5, "bgm speed applied")
	bgm.set_speed(100)
	# 一時停止と再開(位置を覚えて止め、同じ位置から再開)。
	bgm.pause()
	_check_eq(bgm.state(), "paused", "bgm paused")
	bgm.resume()
	_check_eq(bgm.state(), "playing", "bgm resumed")
	bgm.stop()
	_check_eq(bgm.state(), "stop", "bgm stopped")
	_check_eq(bgm.current_path(), "", "bgm path cleared")
	# WAV の BGM。
	_check(bgm.play(TMP + "/test.wav"), "bgm play wav")
	_check_eq(bgm.get("_kind"), "audio", "bgm wav kind")
	_check_eq(bgm.state(), "playing", "bgm wav playing")
	bgm.stop()
	# 無いファイルは鳴らせない。
	_check(not bgm.play(TMP + "/none.mid"), "bgm missing file")
	# サウンドフォントが無ければ MIDI は無音。
	var no_font := PhiBgmPlayer.new()
	root.add_child(no_font)
	no_font.soundfont_path = TMP + "/none.sf2"
	_check(not no_font.midi_available(), "bgm midi unavailable without font")
	_check(not no_font.play(TMP + "/test.mid"), "bgm mid silent without font")
	_check(no_font.play(TMP + "/test.wav"), "bgm wav works without font")
	no_font.stop()
	no_font.queue_free()
	bgm.queue_free()
	await process_frame


func _test_engine() -> void:
	var config := PhiConfig.new()
	var engine := PhiSoundEngine.new()
	root.add_child(engine)
	engine.setup(config, [ROOT1])
	_check_eq(engine.soundfont_path(), "res://assets/GeneralUser-GS.sf2", "engine soundfont")
	engine.set_se_texts(REGEXP_TEXT, FILE_TEXT)
	_check_eq(engine.se_rule_count(), 3, "engine se rules")
	var se_got: Array[String] = []
	engine.se_requested.connect(func(p: String) -> void: se_got.append(p))
	var flash_count := [0]
	engine.flash_requested.connect(func() -> void: flash_count[0] += 1)
	engine.play_se_for_line("DM > 猫 は あなた を攻撃した")
	_check_eq(se_got.size(), 1, "engine se fired")
	if se_got.size() == 1:
		_check_eq(se_got[0], ROOT1 + "/sound/s.e/hit.wav", "engine se path")
	var players: Array = engine.get("_se_players")
	var any_stream := false
	for player in players:
		if (player as AudioStreamPlayer).stream != null:
			any_stream = true
	_check(any_stream, "engine se stream set")
	engine.play_se_for_line("DM > ダメージを受けた")
	_check_eq(flash_count[0], 1, "engine flash fired")
	engine.play_se_for_line("関係ない行")
	_check_eq(se_got.size(), 1, "engine se no match silent")
	# 効果音 off では鳴らない。
	config.sound_play = false
	engine.play_se_for_line("DM > 猫 は あなた を攻撃した")
	_check_eq(se_got.size(), 1, "engine se off silent")
	config.sound_play = true
	# BGM の橋渡し。
	_check(engine.bgm_play(TMP + "/test.wav"), "engine bgm play")
	_check_eq(engine.bgm_current_path(), TMP + "/test.wav", "engine bgm path")
	_check_eq(engine.bgm_state(), "playing", "engine bgm state")
	engine.bgm_stop()
	_check_eq(engine.bgm_state(), "stop", "engine bgm stop")
	config.play_bgm = false
	_check(not engine.bgm_play(TMP + "/test.wav"), "engine bgm off")
	config.play_bgm = true
	engine.queue_free()
	await process_frame


func _test_character_wiring() -> void:
	var config := PhiConfig.new()
	var engine := PhiSoundEngine.new()
	root.add_child(engine)
	engine.setup(config, [ROOT1])
	engine.set_se_texts(REGEXP_TEXT, FILE_TEXT)
	var tab := PhiCharacter.new()
	tab.setup(GameAssets.new(), config, PhiFont.make_ui_font(), PhiFont.make_bold_font(), PhiLogFilter.new(), {})
	tab.set_sound_engine(engine)
	root.add_child(tab)
	# BGM 通知で曲名を覚え、場所が引ける。
	tab._on_event({"type": "bgm", "name": "stage5_song.mid"})
	_check_eq(tab.bgm_name, "stage5_song.mid", "char bgm name")
	_check_eq(tab.bgm_resolved_path(), "user://sound/bgm/stage5_song.mid", "char bgm resolved")
	tab._on_event({"type": "bgmSpeed", "speed": 150})
	_check_eq(tab.bgm_speed, 150, "char bgm speed")
	# ログ行で効果音の要求が出る。
	var se_got: Array[String] = []
	engine.se_requested.connect(func(p: String) -> void: se_got.append(p))
	tab._on_event({"type": "message", "channel": "log", "text": "DM > 猫 は あなた を攻撃した"})
	_check_eq(se_got.size(), 1, "char se fired")
	# 切断で BGM の曲名が空に戻る。
	tab._on_session_closed()
	_check_eq(tab.bgm_name, "", "char bgm cleared on close")
	_check_eq(tab.bgm_speed, 100, "char bgm speed reset")
	tab.queue_free()
	engine.queue_free()
	await process_frame
