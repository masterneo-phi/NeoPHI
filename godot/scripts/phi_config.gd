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
## [Map] MapSize (40=5x5, 57=7x7), MapStyle (solid/turn)。
## [Disp] WindowWidth, WindowHeight … 起動時の窓の大きさ。
## [Disp] SplitOffset … 地図とログの分割位置(地図側の幅ピクセル)。
##   0 以下なら未設定で、初回は地図 55%・ログ 45% にする。
## [Log] ScrollStop … ログの自動スクロールを止めるか。
## [Shortcut] FuncKeyMagicFix, MagicF01〜F07, ShortcutF08〜F12,
##   ShortcutF08ListCancel〜F12, ListModeShortcutF08〜F12, AltGWord …
##   Philly.ini 互換。F1〜F7 の魔法名(31文字まで)と F8〜F12 の自由な
##   文字列(48文字まで。`\n` で改行)。ID は保存しない。
## [Edit] LoudlyByAsterisk, PartyTalkByCtrl … 行頭 `*` の扱いと
##   Ctrl+Enter のパーティー発言。
## [Priv] PopupPrivForm … priv を受けたら priv ウィンドウを出すか。

const DEFAULT_PATH := "user://NeoPHI.ini"

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 20017
const DEFAULT_SKIN := "Mine"
const DEFAULT_MAP_SIZE := 57
const DEFAULT_MAP_STYLE := "solid"
const DEFAULT_WINDOW_WIDTH := 1280
const DEFAULT_WINDOW_HEIGHT := 1024
## 魔法ショートカットの名前の長さの上限(Philly と同じ)。
const MAX_MAGIC_LEN := 31
## 自由ショートカットの文字列の長さの上限(Philly と同じ)。
const MAX_SHORTCUT_LEN := 48
const DEFAULT_ALT_G_WORD := "おやすみなさいませ"
## 分割位置が未設定のとき、地図に割り当てる幅の割合。残りがログ。
const DEFAULT_MAP_WIDTH_RATIO := 0.55

var host := DEFAULT_HOST
var port := DEFAULT_PORT
var skin := DEFAULT_SKIN
var map_size := DEFAULT_MAP_SIZE
var map_style := DEFAULT_MAP_STYLE
var window_width := DEFAULT_WINDOW_WIDTH
var window_height := DEFAULT_WINDOW_HEIGHT
var split_offset := -1
var scroll_stop := false
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
## priv を受けたら priv ウィンドウを出すか(Philly PopupPrivForm)。
var popup_priv_form := true


func initial_split_offset(total_width: int) -> int:
	## 起動時の分割位置(地図側の幅)。保存値があればそれ、無ければ
	## 地図 55%・ログ 45% の位置を返す。
	if split_offset > 0:
		return split_offset
	return int(round(total_width * DEFAULT_MAP_WIDTH_RATIO))


func reset() -> void:
	host = DEFAULT_HOST
	port = DEFAULT_PORT
	skin = DEFAULT_SKIN
	map_size = DEFAULT_MAP_SIZE
	map_style = DEFAULT_MAP_STYLE
	window_width = DEFAULT_WINDOW_WIDTH
	window_height = DEFAULT_WINDOW_HEIGHT
	split_offset = -1
	scroll_stop = false
	func_key_magic_fix = false
	magic_f = ["", "", "", "", "", "", ""]
	shortcut_f = ["", "", "", "", ""]
	shortcut_list_cancel = [0, 0, 0, 0, 0]
	list_mode_shortcut = [".", ".", ".", ".", "."]
	alt_g_word = DEFAULT_ALT_G_WORD
	loudly_by_asterisk = 0
	party_talk_by_ctrl = true
	popup_priv_form = true


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
	map_size = ms if ms == 40 or ms == 57 else DEFAULT_MAP_SIZE
	var mst := str(cfg.get_value("Map", "MapStyle", DEFAULT_MAP_STYLE)).strip_edges().to_lower()
	map_style = mst if mst == "solid" or mst == "turn" else DEFAULT_MAP_STYLE
	var ww := int(cfg.get_value("Disp", "WindowWidth", DEFAULT_WINDOW_WIDTH))
	window_width = ww if ww >= 320 else DEFAULT_WINDOW_WIDTH
	var wh := int(cfg.get_value("Disp", "WindowHeight", DEFAULT_WINDOW_HEIGHT))
	window_height = wh if wh >= 240 else DEFAULT_WINDOW_HEIGHT
	var so := int(cfg.get_value("Disp", "SplitOffset", -1))
	split_offset = so if so > 0 else -1
	scroll_stop = bool(cfg.get_value("Log", "ScrollStop", false))
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
	popup_priv_form = bool(cfg.get_value("Priv", "PopupPrivForm", true))
	return true


func save_file(path: String = DEFAULT_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("Connection", "Host", host)
	cfg.set_value("Connection", "Port", port)
	cfg.set_value("Skin", "SkinName", skin)
	cfg.set_value("Map", "MapSize", map_size)
	cfg.set_value("Map", "MapStyle", map_style)
	cfg.set_value("Disp", "WindowWidth", window_width)
	cfg.set_value("Disp", "WindowHeight", window_height)
	cfg.set_value("Disp", "SplitOffset", split_offset)
	cfg.set_value("Log", "ScrollStop", scroll_stop)
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
	cfg.set_value("Priv", "PopupPrivForm", popup_priv_form)
	return cfg.save(path) == OK
