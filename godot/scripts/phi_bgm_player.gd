class_name PhiBgmPlayer
extends Node
## BGM の再生(第5段)。Philly の classBgmPlayer にあたる受け口。
##
## 拡張子で振り分ける:
## - `.mid` / `.midi` … 同梱の GDScript 製 MIDI プレイヤー
##   (addons/midi、MIT ライセンス)と SF2 サウンドフォント
##   (FluidR3 GM)で合成して鳴らす。サウンドフォントが
##   無ければ MIDI は無音(他の形式は鳴らせる)。
## - `.wav` / `.ogg` / `.mp3` … AudioStreamPlayer で鳴らす。
##
## Philly と同じく、既定でリピート再生する。同じ曲を再生中に
## もう一度 play しても再生し直さない。速度変更は MIDI のみ。
## 一時停止は、アプリが非アクティブになった時に使う
## (Philly の Pause/Resume 相当。MIDI は位置を覚えて止め、
## 再開時にその位置から再生する)。

signal started(path: String)
signal stopped

## サウンドフォントの場所。エンジンが最初に決めて入れる。
var soundfont_path := ""

var _midi: MidiPlayer = null
var _audio := AudioStreamPlayer.new()
var _kind := "" # "" | "midi" | "audio"
var _state := "stop" # "stop" | "playing" | "paused"
var _current_path := ""
var _speed_percent := 100
var _paused_position := 0.0


func _init() -> void:
	_audio.bus = "Master"
	add_child(_audio)


func current_path() -> String:
	return _current_path


func state() -> String:
	return _state


func is_playing() -> bool:
	return _state == "playing"


func midi_available() -> bool:
	## MIDI を鳴らせるか(サウンドフォントがあるか)。
	return not soundfont_path.is_empty() and FileAccess.file_exists(soundfont_path)


func play(path: String) -> bool:
	## 曲を再生する。再生中と同じ曲なら何もしない。
	## 再生を始めたら true、始められなければ false。
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	if _state != "stop" and _current_path == path:
		return true
	stop()
	var ext := path.get_extension().to_lower()
	if ext == "mid" or ext == "midi":
		if not _play_midi(path):
			return false
		_kind = "midi"
	else:
		if not _play_audio(path):
			return false
		_kind = "audio"
	_current_path = path
	_state = "playing"
	_paused_position = 0.0
	started.emit(path)
	return true


func stop() -> void:
	if _midi != null and _kind == "midi":
		_midi.stop()
	if _audio.playing:
		_audio.stop()
	_kind = ""
	_current_path = ""
	_paused_position = 0.0
	if _state != "stop":
		_state = "stop"
		stopped.emit()
	else:
		_state = "stop"


func pause() -> void:
	## 再生を一時停止する(位置は覚える)。
	if _state != "playing":
		return
	if _kind == "midi" and _midi != null:
		_paused_position = _midi.position
		_midi.stop()
	elif _kind == "audio":
		_audio.stream_paused = true
	_state = "paused"


func resume() -> void:
	## 一時停止から再開する。
	if _state != "paused":
		return
	if _kind == "midi" and _midi != null:
		_midi.play(_paused_position)
	elif _kind == "audio":
		_audio.stream_paused = false
	_state = "playing"


func set_speed(percent: int) -> void:
	## 再生速度(%)。Philly と同じく MIDI のみ効く。
	_speed_percent = clampi(percent, 1, 10000)
	if _midi != null:
		_midi.play_speed = _speed_percent / 100.0


func _play_midi(path: String) -> bool:
	if not midi_available():
		return false
	if _midi == null:
		# 初回だけサウンドフォントを読む(数秒かかる)。
		# 全音色読み込みにする(オンデマンド読み込みはアドオン側の
		# 不具合で再生が始まらないため)。
		_midi = MidiPlayer.new()
		_midi.load_all_voices_from_soundfont = true
		_midi.max_polyphony = 64
		add_child(_midi)
		_midi.volume_db = -10.0
		_midi.loop = true
		_midi.soundfont = soundfont_path
	_midi.play_speed = _speed_percent / 100.0
	_midi.file = path
	_midi.play()
	return _midi.playing


func _play_audio(path: String) -> bool:
	var stream := PhiWav.load_audio_file(path)
	if stream == null:
		return false
	# リピート再生にする(Philly の Repeat=true)。
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = _sample_count(wav)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_audio.stream = stream
	_audio.stream_paused = false
	_audio.play()
	return true


static func _sample_count(wav: AudioStreamWAV) -> int:
	## WAV ストリームのサンプル数(フレーム数)。
	var bytes_per_sample := 1
	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS:
			bytes_per_sample = 1
		AudioStreamWAV.FORMAT_16_BITS:
			bytes_per_sample = 2
		AudioStreamWAV.FORMAT_IMA_ADPCM:
			bytes_per_sample = 1
	if wav.stereo:
		bytes_per_sample *= 2
	if bytes_per_sample <= 0:
		return 0
	return wav.data.size() / bytes_per_sample
