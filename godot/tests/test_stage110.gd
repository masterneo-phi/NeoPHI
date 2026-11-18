extends SceneTree
## 第110段のテスト: 文字キーは常に入力欄へ (ユーザーの指定)。
## 第109段の下書き救済では足りなかった: 新スタイルでは入力欄に
## フォーカスが無いまま打ち始めるのが普通で、日本語入力で
## 「テスト」と打つと最初の t が回転マップのキーとして反応して
## しまう (ユーザー報告)。フォーカス・下書きの有無に関わらず、
## 修飾なし (Shift は可) の文字キーは入力欄へフォーカスを移して
## TextEdit に渡し、送信キーにしない。移動キー (矢印・テンキー)
## と F キーは従来どおりゲーム側のキーとして効く。
##
## 使い方: godot --headless --path . -s tests/test_stage110.gd
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


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _key(keycode: Key, unicode: int = 0, shift: bool = false, alt: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev


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
		_test_text_keys()
		print("test_stage110: ", _checks, " checks, ", _failures, " failures")
		quit(1 if _failures > 0 else 0)


func _test_text_keys() -> void:
	var tab := _tab
	var queue: Array = tab.session.get("_send_queue")
	tab.input_box.text = ""
	tab.input_box.release_focus()
	_check(not tab.input_box.has_focus(), "s110 setup unfocused")
	# 第111段の最終決定: 1文字コマンドは当初の割り当てのまま
	# (変えると今までの操作性が全部壊れる、ユーザーの指示)。
	# 変えるのは Shift を使うものと後付けのものだけ。
	# (1) フォーカスなし + T: 回転キーは廃止 (Option+T の
	# トグルへ)。何も送らない。
	_check(not tab.handle_key(_key(KEY_T, "t".unicode_at(0))), "s110 T does nothing")
	_check_eq(queue, [], "s110 nothing sent for T")
	# (2) T (unicode 無し) も同じ。
	_check(not tab.handle_key(_key(KEY_T, 0)), "s110 T unicode0 does nothing")
	_check_eq(queue, [], "s110 nothing sent for T unicode0")
	# (3) Shift+T: 北固定キーも廃止。
	_check(not tab.handle_key(_key(KEY_T, "T".unicode_at(0), true)), "s110 Shift+T does nothing")
	_check_eq(queue, [], "s110 nothing sent for Shift+T")
	# (4) Z (get) や S (write) など他の1文字コマンドも
	# 当初のとおり効く。
	_check(tab.handle_key(_key(KEY_Z, "z".unicode_at(0))), "s110 Z is the get key")
	_check(tab.handle_key(_key(KEY_S, "s".unicode_at(0))), "s110 S is the write key")
	_check_eq(queue, ["get", "write"], "s110 get/write sent")
	queue.clear()
	# (5) 数字キーもゲーム側のキーのまま。
	_check(tab.handle_key(_key(KEY_1, "1".unicode_at(0))), "s110 Digit1 stays a game key")
	_check_eq(queue, ["1"], "s110 Digit1 sent as before")
	queue.clear()
	# (5.5) Shift+数字のマップサイズは廃止 (Option+数字へ)。
	# フォーカスなしでは何も送らない。入力中 (フォーカス
	# あり) は下の (10) のとおり記号として打てる。
	_check(not tab.handle_key(_key(KEY_5, "%".unicode_at(0), true)), "s110 Shift+Digit5 does nothing")
	_check_eq(queue, [], "s110 nothing sent for Shift+Digit5")
	# (6) F1 は従来どおり魔法キーとして効く (文字キーではない)。
	tab.input_box.release_focus()
	_check(tab.handle_key(_key(KEY_F1)), "s110 F1 still a game key")
	queue.clear()
	# (7) 矢印 (移動) は従来どおり効く。
	_check(tab.handle_key(_key(KEY_UP)), "s110 Up still moves")
	# (8) テンキーも従来どおり (Numpad1 = hit 等)。
	_check(tab.handle_key(_key(KEY_KP_1)), "s110 Numpad1 still a game key")
	queue.clear()
	# (9) フォーカスあり + T: TextEdit 任せ (文字として打てる)。
	# 入力中の誤爆はこの保護と、メニューのアクセラレータを
	# Alt 系のみにしたことで止める (test_stage111)。
	tab.input_box.grab_focus()
	_check(not tab.handle_key(_key(KEY_T, "t".unicode_at(0))), "s110 T focused passes")
	_check_eq(queue, [], "s110 nothing sent focused")
	# (10) フォーカスあり + Shift+5: % として打てる
	# (5x5 マップにはならない)。
	_check(not tab.handle_key(_key(KEY_5, "%".unicode_at(0), true)), "s110 Shift+5 focused passes")
	_check_eq(queue, [], "s110 nothing sent for Shift+5 focused")
	tab.input_box.release_focus()
	# (12) Alt+T (Option+T): 回転と北固定のトグル。
	# 現在が北固定 (solid) なら MTurn、回転 (turn) なら
	# MSolid のアクションが飛ぶ (第111段、ユーザーの指定)。
	var captured: Array = []
	tab.action_requested.connect(func(name: String) -> void: captured.append(name))
	tab.session.map_style = "solid"
	_check(tab.handle_key(_key(KEY_T, 0, false, true)), "s110 Alt+T handled")
	_check_eq(captured, ["MTurn"], "s110 Alt+T toggles to turn")
	captured.clear()
	tab.session.map_style = "turn"
	_check(tab.handle_key(_key(KEY_T, 0, false, true)), "s110 Alt+T handled 2")
	_check_eq(captured, ["MSolid"], "s110 Alt+T toggles to solid")
	tab.session.map_style = "solid"
	# (13) Shift+Alt+5 (Option+Shift+5): 5x5 マップへ。
	# Alt+5 単独は Philly 本来の詠唱 (Main が処理) なので
	# handle_key では何も送らない。
	_check(not tab.handle_key(_key(KEY_5, 0, false, true)), "s110 Alt+5 is cast (Main), not size")
	_check_eq(queue, [], "s110 nothing sent for Alt+5")
	_check(tab.handle_key(_key(KEY_5, 0, true, true)), "s110 Shift+Alt+5 handled")
	_check_eq(queue, ["#ex-map size=40"], "s110 Shift+Alt+5 sends size=40")
	queue.clear()
