class_name PhiConfig
extends RefCounted
## 設定の保存と読み込み。
##
## Philly.ini 互換のセクション名で、Godot の ConfigFile に書く。
## 保存先は既定で `user://NeoPHI.ini`。起動時に読み、終了時と
## 設定の変更時に保存する。コマンドライン引数は設定より優先する。
##
## セクションと項目:
## [Connection] Host, Port … Philly の .phirc 相当。ID は保存しない
##   (ID は起動引数か既定の guest を使う)。
## [Skin] SkinName … Philly.ini 互換(起動時のみ有効なのと同じ扱い)。
## [Map] MapSize (40=5x5, 57=7x7, 121=11x11), MapStyle (solid/turn)。
## [Disp] WindowWidth, WindowHeight … 起動時の窓の大きさ。
## [Disp] SplitOffset … 地図とログの分割位置(地図側の幅ピクセル)。
##   0 以下なら未設定で、初回は地図 55%・ログ 45% にする。
## [Disp] ToolbarX, ToolbarY … ツールバーのフロート位置
##   (地図の中の座標)。どちらか欠けるか負なら未設定で、
##   既定の左上 (8, 8) に置く。
## [Disp] TalkButtonX, TalkButtonY … Talk ボタンの位置
##   (地図の中の座標)。どちらか欠けるか負なら未設定で、
##   既定の左下に置く。ドラッグで動かせる。
## [Disp] ListX, ListY … #list パネルの位置 (地図の中の座標)。
##   どちらか欠けるか負なら未設定で、既定の左上 (8, 8) に置く。
##   見出しのドラッグで動かせる。大きさは行数で決まるので保存しない。
## [Disp] MoveRepeatMs … 移動キー (とマウス長押し) の押し続け
##   リピートの最小間隔 (ms)。小さいほど速く歩ける (第128段)。
## [Disp] InputHeight … 入力欄の高さ(ピクセル)。負なら未設定で、
##   既定の3行ぶんにする。ログとの境目のドラッグで変わる。
## [Log] ScrollStop … ログの自動スクロールを止めるか。
## [Log] LogAutoSave, LogSaveDir, LogSaveHtml, LogSaveDeleteTag,
##   LogSaveTextWithTime … ログの自動保存(第4段。Philly.ini 互換)。
## [Log] LogDeleteFilter … 削除フィルタを使うか(第4段。Philly には
##   on/off が無いが、NeoPHI では切り替えられるようにした)。
## [Tab] LoadTabSession, MClickTabClose … タブセッションの復元と
##   中クリックで閉じるか(第4段。Philly.ini 互換)。
## [Shortcut] FuncKeyMagicFix, MagicF01〜F07, ShortcutF08〜F12,
##   ShortcutF08ListCancel〜F12, ListModeShortcutF08〜F12, AltGWord …
##   Philly.ini 互換。F1〜F7 の魔法名(31文字まで)と F8〜F12 の自由な
##   文字列(48文字まで。`\n` で改行)。ID は保存しない。
## [Edit] LoudlyByAsterisk, PartyTalkByCtrl … 行頭 `*` の扱いと
##   Ctrl+Enter のパーティー発言。
## [Priv] PopupPrivForm … priv を受けたら priv ウィンドウを出すか。
## [Sound] SoundPlay, PlayBgm, PlayBgmDeactivate … 効果音と BGM
##   (第5段。Philly.ini 互換)。

const DEFAULT_PATH := "user://NeoPHI.ini"

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 20017
const DEFAULT_SKIN := "Mine"
const DEFAULT_MAP_SIZE := 121
const DEFAULT_MAP_STYLE := "solid"
const DEFAULT_WINDOW_WIDTH := 1280
const DEFAULT_WINDOW_HEIGHT := 1024
## 魔法ショートカットの名前の長さの上限(Philly と同じ)。
const MAX_MAGIC_LEN := 31
## 自由ショートカットの文字列の長さの上限(Philly と同じ)。
const MAX_SHORTCUT_LEN := 48
const DEFAULT_ALT_G_WORD := "おやすみなさいませ"
## 境目の位置(地図側の幅の割合)。窓の幅が変わっても割合を保つ。
## 0.62 は、中段の幅(窓幅から右列を引いたもの)に対する割合で、
## 既定の窓幅 1280 では地図が約 702px になり、従来の既定(704px)と
## 同じ見た目になる(窓幅に対する割合は約 55% で従来どおり)。
const DEFAULT_SPLIT_RATIO := 0.62
## 境目の割合の範囲。ドラッグと読み込みでこの範囲に収める。
const MIN_SPLIT_RATIO := 0.15
const MAX_SPLIT_RATIO := 0.85
## ログの最小幅。境目を動かしてもこれより狭くしない。
const MIN_LOG_WIDTH := 280
## 移動リピート間隔の既定と範囲 (第128段)。既定 60ms で
## 秒間約16マスが天井になる。下限 30ms の理由: 60fps の
## 1フレーム (約16.7ms) の2倍弱で、これより細かい指定は
## フレーム駆動の送信では守れないし、1歩ごとにサーバとの
## 往復がある以上、実効速度も頭打ちになる。上限は保険
## タイマーの間隔 (500ms) に合わせる (それ以上は保険側の
## 間隔で送られてしまい、指定の意味が無くなる)。
const DEFAULT_MOVE_REPEAT_MS := 60
const MIN_MOVE_REPEAT_MS := 30
const MAX_MOVE_REPEAT_MS := 500
## 旧設定の移行で窓幅から差し引く右列の幅の目安。
## ズーム3時の列幅 144＋区切り 4。これで旧設定の地図幅が保たれる。
const MIGRATION_COLUMN_ALLOWANCE := 148

var host := DEFAULT_HOST
var port := DEFAULT_PORT
var skin := DEFAULT_SKIN
var map_size := DEFAULT_MAP_SIZE
var map_style := DEFAULT_MAP_STYLE
## 地図の倍率の決め方。0 = 窓に合わせる (収まる整数倍率)、
## 1 = 固定倍率 (map_zoom_fixed の倍率に固定し、窓が小さくても
## 縮めない・大きくても広げない)。
var map_zoom_mode := 0
## 固定倍率モードの倍率 (1〜8 の整数倍。ドット絵が崩れない範囲)。
var map_zoom_fixed := 3
## サーバーからの魔法表示を受け取るか(Philly DispMagicClientSide)。
var disp_magic := true
## 移動時に地図をドット単位で滑らかにスクロールするか
## (表示メニュー「スムーズマップスクロール」。既定 on。
## 北固定の時だけ効き、回転の時は従来どおり切り替わる)。
var smooth_scroll := true
## キャラにマウスを止めると名前をヒント表示するか
## (Philly [Map] SearchHintName。既定 on)。
var search_hint_name := true
## マウス移動時に目安ラインを描くか (Philly [Map]
## MouseMoveLine。既定 off)。
var mouse_move_line := false
var window_width := DEFAULT_WINDOW_WIDTH
var window_height := DEFAULT_WINDOW_HEIGHT
var split_ratio := DEFAULT_SPLIT_RATIO
## ツールバーのフロート位置(地図の中の座標)。(-1, -1) は未設定で、
## その場合は地図の左上 (8, 8) に置く。ドラッグで動かすと更新され、
## 分割比率と同じく、保存はメイン画面のタイミング(終了時など)。
var toolbar_pos := Vector2(-1, -1)
## コマンドパレットの列数 (第100段)。0 は未設定で、その場合は
## グループごとに1段に並べる (従来)。パネルの右下をドラッグ
## して幅を変えると、その幅に合う列数が入る。
var toolbar_cols := 0
## 表示スタイル (第101段、0.5.0)。 "new" はログと入力欄を
## 地図の上に浮かせる新スタイル、"old" は従来の分割配置。
## 既定は新スタイル (ユーザーの指定)。
var ui_style := "new"
## 地図の配置 (第101段)。0=中央 (既定)、1=左寄せ、2=右寄せ。
## 地図が画面全域に広がる新スタイルで効く。
var map_align := 0
## ログ/入力フロート窓の位置と大きさ (地図の中の座標)。
## 大きさ 0 は未設定で、その場合は既定の置き方にする。
var log_float_rect := Rect2(0, 0, 0, 0)
var input_float_rect := Rect2(0, 0, 0, 0)
## フロート窓の文字サイズ (第104段)。0 は自動で、窓の大きさ
## から決める (従来)。1 以上はその数値に固定する (実効は
## 8〜48)。設定画面で数値を指定する (ユーザーの指定)。
var log_font_size := 0
var input_font_size := 0
## メニューバー・プルダウンメニュー・タブなどのフォントサイズ。
## かつては地図の倍率 (窓の大きさ) に連動していたが、タブの
## 切断・終了で極端に小さくなる事があったため連動を廃止し、
## この固定値を使う (ユーザーの指定)。実効は 10〜48。
var menu_font_size := 20
## コマンドパレットのアイコンの大きさ (ピクセル)。0 は
## アイコン本来の大きさ。それ以外はその大きさに拡大する
## (ドット絵なので拡大は NEAREST)。実効は 0 または 12〜64。
var toolbar_icon_size := 0
var talk_button_pos := Vector2(-1, -1)
## #list パネルの位置(地図の中の座標)。(-1, -1) は未設定で、
## その場合は地図の左上 (8, 8) に置く。見出しのドラッグで
## 更新され、保存はメイン画面のタイミング(終了時など)。
## 大きさはリストの行数で決まるので持たない。
var list_pos := Vector2(-1, -1)
## 移動キー (とマウス長押し) の押し続けリピートの最小間隔
## (ms、第128段)。地図が届くたびに次の一歩を送る方式の
## 間引きに使う。かつては 120ms 固定だった。
var move_repeat_ms := DEFAULT_MOVE_REPEAT_MS
## 入力欄の高さ(ピクセル)。-1 は未設定で、その場合は既定の
## 3行ぶんにする。境目のドラッグで更新され、保存はメイン画面の
## タイミング(終了時など)。
var input_height := -1
var scroll_stop := false
## ログをファイルに自動保存するか(Philly LogAutoSave。既定 off)。
var log_auto_save := false
## 送受信の生バイトを Logs/wire_*.log に記録するか (第82段、
## 診断用)。NeoPHI.ini の [Debug] WireTrace=true で有効化。
var wire_trace := false
## ログ表示に行頭の時刻 [HH:MM] を付けるか(Philly LogDispTime。
## 既定 on)。
var log_disp_time := true
## ログ中の /*img=URL*/ を画像そのもので表示するか (Philly
## LogImageDisp。既定 on)。off の間は [画像: URL] の文字で出す。
var log_image_disp := true
## 自動保存の保存先フォルダ(Philly の Logs/ 相当)。
var log_save_dir := PhiLogFile.DEFAULT_DIR
## HTML で保存するか(Philly LogSaveHtml。off ならテキスト)。
var log_save_html := true
## テキストで保存するときにタグを削除するか(Philly LogSaveDeleteTag)。
var log_save_delete_tag := false
## テキストで保存するときに時刻を入れるか(Philly LogSaveTextWithTime)。
var log_save_text_with_time := true
## 削除フィルタを使うか(第4段)。
var log_delete_filter := true
## 起動時にタブセッションを復元するか(Philly LoadTabSession)。
var load_tab_session := true
## 中クリックでタブを閉じるか(Philly MClickTabClose)。
var mclick_tab_close := true
## F1〜F7 で番号ではなく設定した魔法名を送るか(Philly FuncKeyMagicFix)。
var func_key_magic_fix := false
## F1〜F7 の魔法名(Philly MagicF01〜F07)。
var magic_f: Array[String] = ["", "", "", "", "", "", ""]
## F8〜F12 の自由な文字列(Philly ShortcutF08〜F12)。
var shortcut_f: Array[String] = ["", "", "", "", ""]
## F8〜F12 の後に抑えるリストの数(Philly ShortcutF08ListCancel〜)。
var shortcut_list_cancel: Array[int] = [0, 0, 0, 0, 0]
## リストの間の F8〜F12 の文字列(Philly ListModeShortcutF08〜)。
var list_mode_shortcut: Array[String] = [".", ".", ".", ".", "."]
## Alt+G で発言する言葉(Philly AltGWord)。
var alt_g_word := DEFAULT_ALT_G_WORD
## 行頭 `*` の扱い(Philly LoudlyByAsterisk)。
## 0: 大声にしない、1: Ctrl+Enter の時だけ大声、2: いつでも大声。
var loudly_by_asterisk := 0
## Ctrl+Enter でパーティー発言にするか(Philly PartyTalkByCtrl)。
var party_talk_by_ctrl := true
## Call / Return の前に確認ダイアログを出すか
## (Philly [Input] DialogForCall / DialogForReturn。既定 on)。
var dialog_for_call := true
var dialog_for_return := true
## priv を受けたら priv ウィンドウを出すか(Philly PopupPrivForm)。
var popup_priv_form := true
## ログ行に正規表現が合ったら効果音を鳴らすか(Philly SoundPlay)。
var sound_play := true
## BGM を鳴らすか(Philly PlayBgm)。
var play_bgm := true
## 超魔法メニューを、マスター (EXP 99999999) でなくても出すか
## (WPHI の masterMagicMenu 設定。既定 off)。
var master_magic_always := false
## アプリがアクティブでない時も BGM を鳴らすか
## (Philly PlayBgmDeactivate。off なら非アクティブで一時停止)。
var play_bgm_deactivate := false


func split_offset_for(total_width: int, separation: float) -> int:
	## 境目の位置(地図側の幅)。割合で決め、ログの最小幅を保つ。
	## 幅が足りなければログを優先し、地図側を 0 まで詰める。
	var off := int(round(total_width * split_ratio))
	off = mini(off, int(total_width - MIN_LOG_WIDTH - separation))
	return maxi(off, 0)


func reset() -> void:
	host = DEFAULT_HOST
	port = DEFAULT_PORT
	skin = DEFAULT_SKIN
	map_size = DEFAULT_MAP_SIZE
	map_style = DEFAULT_MAP_STYLE
	map_zoom_mode = 0
	map_zoom_fixed = 3
	disp_magic = true
	smooth_scroll = true
	search_hint_name = true
	mouse_move_line = false
	window_width = DEFAULT_WINDOW_WIDTH
	window_height = DEFAULT_WINDOW_HEIGHT
	split_ratio = DEFAULT_SPLIT_RATIO
	toolbar_pos = Vector2(-1, -1)
	toolbar_cols = 0
	ui_style = "new"
	map_align = 0
	log_font_size = 0
	input_font_size = 0
	menu_font_size = 20
	toolbar_icon_size = 0
	log_float_rect = Rect2(0, 0, 0, 0)
	input_float_rect = Rect2(0, 0, 0, 0)
	talk_button_pos = Vector2(-1, -1)
	list_pos = Vector2(-1, -1)
	move_repeat_ms = DEFAULT_MOVE_REPEAT_MS
	input_height = -1
	scroll_stop = false
	log_auto_save = false
	log_disp_time = true
	log_image_disp = true
	log_save_dir = PhiLogFile.DEFAULT_DIR
	log_save_html = true
	log_save_delete_tag = false
	log_save_text_with_time = true
	log_delete_filter = true
	load_tab_session = true
	mclick_tab_close = true
	func_key_magic_fix = false
	magic_f = ["", "", "", "", "", "", ""]
	shortcut_f = ["", "", "", "", ""]
	shortcut_list_cancel = [0, 0, 0, 0, 0]
	list_mode_shortcut = [".", ".", ".", ".", "."]
	alt_g_word = DEFAULT_ALT_G_WORD
	loudly_by_asterisk = 0
	party_talk_by_ctrl = true
	dialog_for_call = true
	dialog_for_return = true
	popup_priv_form = true
	sound_play = true
	play_bgm = true
	play_bgm_deactivate = false
	master_magic_always = false


func load_file(path: String = DEFAULT_PATH) -> bool:
	## 設定ファイルを読む。無ければ既定値のまま false を返す。
	## おかしな値は既定値に戻す。
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return false
	var h := str(cfg.get_value("Connection", "Host", DEFAULT_HOST)).strip_edges()
	host = h if not h.is_empty() else DEFAULT_HOST
	var p := int(cfg.get_value("Connection", "Port", DEFAULT_PORT))
	port = p if p >= 1 and p <= 65535 else DEFAULT_PORT
	var s := str(cfg.get_value("Skin", "SkinName", DEFAULT_SKIN)).strip_edges()
	skin = s if not s.is_empty() else DEFAULT_SKIN
	var ms := int(cfg.get_value("Map", "MapSize", DEFAULT_MAP_SIZE))
	# 旧 81 (9x9) の設定は仕様削除に伴い既定の 121 (11x11) になる。
	map_size = ms if ms == 40 or ms == 57 or ms == 121 else DEFAULT_MAP_SIZE
	var mst := str(cfg.get_value("Map", "MapStyle", DEFAULT_MAP_STYLE)).strip_edges().to_lower()
	map_style = mst if mst == "solid" or mst == "turn" else DEFAULT_MAP_STYLE
	map_zoom_mode = 1 if int(cfg.get_value("Map", "ZoomMode", 0)) == 1 else 0
	map_zoom_fixed = clampi(int(cfg.get_value("Map", "ZoomFixed", 3)), 1, 8)
	disp_magic = bool(cfg.get_value("Map", "DispMagicClientSide", true))
	search_hint_name = bool(cfg.get_value("Map", "SearchHintName", true))
	mouse_move_line = bool(cfg.get_value("Map", "MouseMoveLine", false))
	var ww := int(cfg.get_value("Disp", "WindowWidth", DEFAULT_WINDOW_WIDTH))
	window_width = ww if ww >= 320 else DEFAULT_WINDOW_WIDTH
	var wh := int(cfg.get_value("Disp", "WindowHeight", DEFAULT_WINDOW_HEIGHT))
	window_height = wh if wh >= 240 else DEFAULT_WINDOW_HEIGHT
	# 境目は比率で持つ。古い設定(絶対ピクセルの SplitOffset)は、
	# 保存時の地図幅を保つよう、窓幅から右列分を引いた幅に対する
	# 比率とみなして移行する。
	if cfg.has_section_key("Disp", "SplitRatio"):
		var ratio := float(cfg.get_value("Disp", "SplitRatio", DEFAULT_SPLIT_RATIO))
		split_ratio = clampf(ratio, MIN_SPLIT_RATIO, MAX_SPLIT_RATIO)
	elif cfg.has_section_key("Disp", "SplitOffset"):
		var old := int(cfg.get_value("Disp", "SplitOffset", -1))
		var base := maxi(window_width - MIGRATION_COLUMN_ALLOWANCE, 1)
		if old > 0:
			split_ratio = clampf(float(old) / float(base), MIN_SPLIT_RATIO, MAX_SPLIT_RATIO)
		else:
			split_ratio = DEFAULT_SPLIT_RATIO
	else:
		split_ratio = DEFAULT_SPLIT_RATIO
	# ツールバーの位置。両方そろって 0 以上なら採用する。
	if cfg.has_section_key("Disp", "ToolbarX") and cfg.has_section_key("Disp", "ToolbarY"):
		var tx := float(cfg.get_value("Disp", "ToolbarX", -1))
		var ty := float(cfg.get_value("Disp", "ToolbarY", -1))
		if tx >= 0.0 and ty >= 0.0:
			toolbar_pos = Vector2(tx, ty)
	toolbar_cols = clampi(int(cfg.get_value("Disp", "ToolbarCols", 0)), 0, 64)
	ui_style = "old" if str(cfg.get_value("Disp", "UiStyle", "new")) == "old" else "new"
	map_align = clampi(int(cfg.get_value("Disp", "MapAlign", 0)), 0, 2)
	log_font_size = clampi(int(cfg.get_value("Disp", "LogFontSize", 0)), 0, 48)
	input_font_size = clampi(int(cfg.get_value("Disp", "InputFontSize", 0)), 0, 48)
	menu_font_size = clampi(int(cfg.get_value("Disp", "MenuFontSize", 20)), 10, 48)
	toolbar_icon_size = clampi(int(cfg.get_value("Disp", "ToolbarIconSize", 0)), 0, 64)
	# フロート窓の位置と大きさ。幅と高さがそろって正なら採用する。
	if cfg.has_section_key("Disp", "LogFloatW") and cfg.has_section_key("Disp", "LogFloatH"):
		var lw := float(cfg.get_value("Disp", "LogFloatW", 0))
		var lh := float(cfg.get_value("Disp", "LogFloatH", 0))
		if lw > 0.0 and lh > 0.0:
			log_float_rect = Rect2(float(cfg.get_value("Disp", "LogFloatX", 0)), float(cfg.get_value("Disp", "LogFloatY", 0)), lw, lh)
	if cfg.has_section_key("Disp", "InputFloatW") and cfg.has_section_key("Disp", "InputFloatH"):
		var iw := float(cfg.get_value("Disp", "InputFloatW", 0))
		var ih := float(cfg.get_value("Disp", "InputFloatH", 0))
		if iw > 0.0 and ih > 0.0:
			input_float_rect = Rect2(float(cfg.get_value("Disp", "InputFloatX", 0)), float(cfg.get_value("Disp", "InputFloatY", 0)), iw, ih)
	# Talk ボタンの位置。両方そろって 0 以上なら採用する。
	if cfg.has_section_key("Disp", "TalkButtonX") and cfg.has_section_key("Disp", "TalkButtonY"):
		var bx := float(cfg.get_value("Disp", "TalkButtonX", -1))
		var by := float(cfg.get_value("Disp", "TalkButtonY", -1))
		if bx >= 0.0 and by >= 0.0:
			talk_button_pos = Vector2(bx, by)
	# リストパネルの位置。両方そろって 0 以上なら採用する。
	if cfg.has_section_key("Disp", "ListX") and cfg.has_section_key("Disp", "ListY"):
		var lx := float(cfg.get_value("Disp", "ListX", -1))
		var ly := float(cfg.get_value("Disp", "ListY", -1))
		if lx >= 0.0 and ly >= 0.0:
			list_pos = Vector2(lx, ly)
	move_repeat_ms = clampi(int(cfg.get_value("Disp", "MoveRepeatMs", DEFAULT_MOVE_REPEAT_MS)), MIN_MOVE_REPEAT_MS, MAX_MOVE_REPEAT_MS)
	var ih := int(cfg.get_value("Disp", "InputHeight", -1))
	input_height = ih if ih >= 0 else -1
	smooth_scroll = bool(cfg.get_value("Disp", "SmoothMapScroll", true))
	scroll_stop = bool(cfg.get_value("Log", "ScrollStop", false))
	log_auto_save = bool(cfg.get_value("Log", "LogAutoSave", false))
	wire_trace = bool(cfg.get_value("Debug", "WireTrace", false))
	log_disp_time = bool(cfg.get_value("Log", "LogDispTime", true))
	log_image_disp = bool(cfg.get_value("Log", "LogImageDisp", true))
	var lsd := str(cfg.get_value("Log", "LogSaveDir", PhiLogFile.DEFAULT_DIR)).strip_edges()
	log_save_dir = lsd if not lsd.is_empty() else PhiLogFile.DEFAULT_DIR
	log_save_html = bool(cfg.get_value("Log", "LogSaveHtml", true))
	log_save_delete_tag = bool(cfg.get_value("Log", "LogSaveDeleteTag", false))
	log_save_text_with_time = bool(cfg.get_value("Log", "LogSaveTextWithTime", true))
	log_delete_filter = bool(cfg.get_value("Log", "LogDeleteFilter", true))
	load_tab_session = bool(cfg.get_value("Tab", "LoadTabSession", true))
	mclick_tab_close = bool(cfg.get_value("Tab", "MClickTabClose", true))
	func_key_magic_fix = bool(cfg.get_value("Shortcut", "FuncKeyMagicFix", false))
	for i in range(7):
		magic_f[i] = str(cfg.get_value("Shortcut", "MagicF%02d" % (i + 1), ""))
	for i in range(5):
		shortcut_f[i] = str(cfg.get_value("Shortcut", "ShortcutF%02d" % (i + 8), ""))
		var cancel := int(cfg.get_value("Shortcut", "ShortcutF%02dListCancel" % (i + 8), 0))
		shortcut_list_cancel[i] = maxi(cancel, 0)
		list_mode_shortcut[i] = str(cfg.get_value("Shortcut", "ListModeShortcutF%02d" % (i + 8), "."))
	alt_g_word = str(cfg.get_value("Shortcut", "AltGWord", DEFAULT_ALT_G_WORD))
	var loud := int(cfg.get_value("Edit", "LoudlyByAsterisk", 0))
	loudly_by_asterisk = clampi(loud, 0, 2)
	party_talk_by_ctrl = bool(cfg.get_value("Edit", "PartyTalkByCtrl", true))
	dialog_for_call = bool(cfg.get_value("Input", "DialogForCall", true))
	dialog_for_return = bool(cfg.get_value("Input", "DialogForReturn", true))
	popup_priv_form = bool(cfg.get_value("Priv", "PopupPrivForm", true))
	sound_play = bool(cfg.get_value("Sound", "SoundPlay", true))
	play_bgm = bool(cfg.get_value("Sound", "PlayBgm", true))
	master_magic_always = bool(cfg.get_value("MasterMagic", "MasterMagicMenu", false))
	play_bgm_deactivate = bool(cfg.get_value("Sound", "PlayBgmDeactivate", false))
	return true


func save_file(path: String = DEFAULT_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("Connection", "Host", host)
	cfg.set_value("Connection", "Port", port)
	cfg.set_value("Skin", "SkinName", skin)
	cfg.set_value("Map", "MapSize", map_size)
	cfg.set_value("Map", "MapStyle", map_style)
	cfg.set_value("Map", "ZoomMode", map_zoom_mode)
	cfg.set_value("Map", "ZoomFixed", map_zoom_fixed)
	cfg.set_value("Map", "DispMagicClientSide", disp_magic)
	cfg.set_value("Map", "SearchHintName", search_hint_name)
	cfg.set_value("Map", "MouseMoveLine", mouse_move_line)
	cfg.set_value("Disp", "WindowWidth", window_width)
	cfg.set_value("Disp", "WindowHeight", window_height)
	cfg.set_value("Disp", "SplitRatio", split_ratio)
	cfg.set_value("Disp", "ToolbarX", toolbar_pos.x)
	cfg.set_value("Disp", "ToolbarY", toolbar_pos.y)
	cfg.set_value("Disp", "ToolbarCols", toolbar_cols)
	cfg.set_value("Disp", "UiStyle", ui_style)
	cfg.set_value("Disp", "MapAlign", map_align)
	cfg.set_value("Disp", "LogFontSize", log_font_size)
	cfg.set_value("Disp", "InputFontSize", input_font_size)
	cfg.set_value("Disp", "MenuFontSize", menu_font_size)
	cfg.set_value("Disp", "ToolbarIconSize", toolbar_icon_size)
	cfg.set_value("Disp", "LogFloatX", log_float_rect.position.x)
	cfg.set_value("Disp", "LogFloatY", log_float_rect.position.y)
	cfg.set_value("Disp", "LogFloatW", log_float_rect.size.x)
	cfg.set_value("Disp", "LogFloatH", log_float_rect.size.y)
	cfg.set_value("Disp", "InputFloatX", input_float_rect.position.x)
	cfg.set_value("Disp", "InputFloatY", input_float_rect.position.y)
	cfg.set_value("Disp", "InputFloatW", input_float_rect.size.x)
	cfg.set_value("Disp", "InputFloatH", input_float_rect.size.y)
	cfg.set_value("Disp", "SmoothMapScroll", smooth_scroll)
	cfg.set_value("Disp", "TalkButtonX", talk_button_pos.x)
	cfg.set_value("Disp", "TalkButtonY", talk_button_pos.y)
	cfg.set_value("Disp", "ListX", list_pos.x)
	cfg.set_value("Disp", "ListY", list_pos.y)
	cfg.set_value("Disp", "MoveRepeatMs", move_repeat_ms)
	cfg.set_value("Disp", "InputHeight", input_height)
	cfg.set_value("Log", "ScrollStop", scroll_stop)
	cfg.set_value("Log", "LogAutoSave", log_auto_save)
	cfg.set_value("Log", "LogDispTime", log_disp_time)
	cfg.set_value("Log", "LogImageDisp", log_image_disp)
	cfg.set_value("Log", "LogSaveDir", log_save_dir)
	cfg.set_value("Log", "LogSaveHtml", log_save_html)
	cfg.set_value("Log", "LogSaveDeleteTag", log_save_delete_tag)
	cfg.set_value("Log", "LogSaveTextWithTime", log_save_text_with_time)
	cfg.set_value("Log", "LogDeleteFilter", log_delete_filter)
	cfg.set_value("Tab", "LoadTabSession", load_tab_session)
	cfg.set_value("Tab", "MClickTabClose", mclick_tab_close)
	cfg.set_value("Shortcut", "FuncKeyMagicFix", func_key_magic_fix)
	for i in range(7):
		cfg.set_value("Shortcut", "MagicF%02d" % (i + 1), magic_f[i])
	for i in range(5):
		cfg.set_value("Shortcut", "ShortcutF%02d" % (i + 8), shortcut_f[i])
		cfg.set_value("Shortcut", "ShortcutF%02dListCancel" % (i + 8), shortcut_list_cancel[i])
		cfg.set_value("Shortcut", "ListModeShortcutF%02d" % (i + 8), list_mode_shortcut[i])
	cfg.set_value("Shortcut", "AltGWord", alt_g_word)
	cfg.set_value("Edit", "LoudlyByAsterisk", loudly_by_asterisk)
	cfg.set_value("Edit", "PartyTalkByCtrl", party_talk_by_ctrl)
	cfg.set_value("Input", "DialogForCall", dialog_for_call)
	cfg.set_value("Input", "DialogForReturn", dialog_for_return)
	cfg.set_value("Priv", "PopupPrivForm", popup_priv_form)
	cfg.set_value("Sound", "SoundPlay", sound_play)
	cfg.set_value("Sound", "PlayBgm", play_bgm)
	cfg.set_value("Sound", "PlayBgmDeactivate", play_bgm_deactivate)
	cfg.set_value("MasterMagic", "MasterMagicMenu", master_magic_always)
	return cfg.save(path) == OK
