extends SceneTree
## 第7段のテスト: 新規キャラクター作成とキャラクター管理。
## resist.ini の読解、名前・メール・IP の検証(PhillyNewCharacter)、
## 表示名の生成、`.phirc` の往復、作成セッションの状態機械
## (PhillySrc/NewCharacter/プロトコル.txt のトレースと照合)。
##
## 使い方: godot --headless --path . -s tests/test_stage7.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0

## 実行ごとに一意な作業フォルダ(前回の残りで結果が変わらないように)。
var _work := ""


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		failures_add(label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		failures_add(label + " (got " + str(a) + ", want " + str(b) + ")")


func failures_add(label: String) -> void:
	_failures += 1
	printerr("FAIL: ", label)


func _initialize() -> void:
	_work = "/tmp/neophi-stage7-" + str(Time.get_ticks_usec())
	_test_resist_parse()
	_test_check_name()
	_test_check_mail()
	_test_password()
	_test_split_ip_port()
	_test_display_name()
	_test_phirc()
	_test_register_trace()
	_test_register_reprompts()
	print("test_stage7: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _test_resist_parse() -> void:
	var text := "[Metro Planetarium]\n"
	text += "Address=59.106.178.128\n"
	text += "Port=20033\n"
	text += "URL=http://metro.tofup.net/\n"
	text += "Line1=遥か遠い昔、栄華を極めた古代都市があった。\n"
	text += "Line2=今は永遠に朽ちない外壁のみがその名残を残す。\n"
	text += "Line4=番号が飛んだらここで止まる\n"
	text += "\n"
	text += ";コメント行\n"
	text += "[NoPort World]\n"
	text += "Address=\"192.0.2.1\"\n"
	text += "Line1=説明だけの世界\n"
	var worlds := PhiResist.parse(text)
	_check_eq(worlds.size(), 2, "resist world count")
	var w0: Dictionary = worlds[0]
	_check_eq(str(w0["name"]), "Metro Planetarium", "resist name")
	_check_eq(str(w0["address"]), "59.106.178.128", "resist address")
	_check_eq(int(w0["port"]), 20033, "resist port")
	_check_eq(str(w0["url"]), "http://metro.tofup.net/", "resist url")
	_check_eq(str(w0["comment"]), "遥か遠い昔、栄華を極めた古代都市があった。\n今は永遠に朽ちない外壁のみがその名残を残す。", "resist comment stops at gap")
	_check_eq(bool(w0["address_input"]), false, "resist address_input false")
	var w1: Dictionary = worlds[1]
	_check_eq(int(w1["port"]), 20017, "resist port default")
	_check_eq(str(w1["address"]), "192.0.2.1", "resist quoted value")
	_check_eq(str(w1["comment"]), "説明だけの世界", "resist comment single")
	# CRLF でも読める。
	var crlf := PhiResist.parse("[A]\r\nAddress=1.2.3.4\r\nPort=20001\r\n")
	_check_eq(crlf.size(), 1, "resist crlf count")
	_check_eq(int(crlf[0]["port"]), 20001, "resist crlf port")
	# アドレス指定の世界は parse には含まれない( load_worlds で足す)。
	_check_eq(PhiResist.parse("").size(), 0, "resist empty")


func _test_check_name() -> void:
	_check_eq(PhiCharacters.check_name("Hero"), "", "name ok")
	_check_eq(PhiCharacters.check_name("ab"), "", "name ok 2 chars")
	_check_eq(PhiCharacters.check_name("a".repeat(31)), "", "name ok 31 chars")
	_check(PhiCharacters.check_name("a").contains("短すぎます"), "name too short")
	_check(PhiCharacters.check_name("").contains("短すぎます"), "name empty too short")
	_check(PhiCharacters.check_name("a".repeat(32)).contains("長すぎます"), "name too long")
	_check(PhiCharacters.check_name("あいう").contains("全角文字"), "name fullwidth")
	_check(PhiCharacters.check_name(" Hero").contains("最初の文字がスペース"), "name leading space")
	_check(PhiCharacters.check_name("Hero ").contains("最後の文字がスペース"), "name trailing space")
	_check(PhiCharacters.check_name("#Hero").contains("「#」から始まる"), "name leading sharp")
	_check(PhiCharacters.check_name("He/*ro").contains("「/*」が入る"), "name tag open")
	_check(PhiCharacters.check_name("He*/ro").contains("「*/」が入る"), "name tag close")
	# 判定の順序: 短い名前は他の問題より先に短さで落ちる。
	_check(PhiCharacters.check_name("#").contains("短すぎます"), "name order short first")
	# 半角カタカナは1バイト扱い(Philly の cp932 基準)。
	_check_eq(PhiCharacters.check_name("ｱｲ"), "", "name halfwidth katakana ok")


func _test_check_mail() -> void:
	var ok1 := PhiCharacters.check_mail("user@example.com")
	_check_eq(bool(ok1["ok"]), true, "mail ok")
	_check_eq(str(ok1["mail"]), "user@example.com", "mail unchanged")
	var ok2 := PhiCharacters.check_mail("user")
	_check_eq(str(ok2["mail"]), "user@", "mail appends at")
	var ok3 := PhiCharacters.check_mail("")
	_check_eq(str(ok3["mail"]), "@", "mail empty becomes at")
	var ng := PhiCharacters.check_mail("あ@example.com")
	_check_eq(bool(ng["ok"]), false, "mail fullwidth ng")
	_check(str(ng["error"]).contains("全角文字"), "mail fullwidth message")


func _test_password() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var pw := PhiCharacters.make_password(rng)
	_check_eq(pw.length(), 6, "password length")
	var charset_ok := true
	for i in pw.length():
		var c := pw.unicode_at(i)
		if not ((c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)):
			charset_ok = false
	_check(charset_ok, "password charset")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 12345
	_check_eq(PhiCharacters.make_password(rng2), pw, "password deterministic with seed")


func _test_split_ip_port() -> void:
	var a := PhiCharacters.split_ip_port("127.0.0.1:20021")
	_check_eq(bool(a["ok"]), true, "split ok")
	_check_eq(str(a["ip"]), "127.0.0.1", "split ip")
	_check_eq(int(a["port"]), 20021, "split port")
	var b := PhiCharacters.split_ip_port("127.0.0.1")
	_check_eq(int(b["port"]), 20017, "split default port")
	var c := PhiCharacters.split_ip_port("10.0.0.1:abc")
	_check_eq(bool(c["ok"]), true, "split bad port still ok")
	_check_eq(int(c["port"]), 20017, "split bad port default")
	_check_eq(bool(PhiCharacters.split_ip_port("localhost")["ok"]), false, "split hostname ng")
	_check_eq(bool(PhiCharacters.split_ip_port("1.2.3")["ok"]), false, "split short ip ng")
	_check_eq(bool(PhiCharacters.split_ip_port("")["ok"]), false, "split empty ng")
	_check(str(PhiCharacters.split_ip_port("localhost")["error"]).contains("IP アドレスが不正です"), "split error message")


func _test_display_name() -> void:
	_check_eq(PhiCharacters.sanitize_display_name("A B:C/D"), "A-B-C-D", "sanitize spaces and separators")
	_check_eq(PhiCharacters.sanitize_display_name("a\nb\rc"), "abc", "sanitize strips newlines")
	_check_eq(PhiCharacters.sanitize_display_name("a\\b*c?d\"e<f>g|h,i;j"), "a-b-c-d-e-f-g-h-i-j", "sanitize all separators")
	_check_eq(PhiCharacters.sanitize_display_name("Hero"), "Hero", "sanitize plain")
	var entries: Array = [
		{"display_name": "01_X"},
		{"display_name": "02_Y"},
		{"display_name": "04_Z"},
	]
	_check_eq(PhiCharacters.empty_no(entries), 3, "empty no finds gap")
	_check_eq(PhiCharacters.empty_no([]), 1, "empty no first")
	_check_eq(PhiCharacters.empty_no([{"display_name": "AB_X"}]), 1, "empty no ignores non-numeric")
	DirAccess.make_dir_recursive_absolute(_work)
	var root := _work + "/disp"
	DirAccess.make_dir_recursive_absolute(root)
	var made := PhiCharacters.make_display_name("Hero", entries, root)
	_check_eq(bool(made["ok"]), true, "display name ok")
	_check_eq(str(made.get("display_name", "")), "03_Hero", "display name with gap number")
	_check_eq(bool(made.get("is_new", true)), false, "display name not new")
	var made_first := PhiCharacters.make_display_name("Hero", [], root)
	_check_eq(str(made_first.get("display_name", "")), "01_Hero", "display name first")
	_check_eq(bool(made_first.get("is_new", false)), true, "display name is new")
	# フォルダが既にあると重なりで落ちる(Philly と同じ)。
	DirAccess.make_dir_recursive_absolute(root + "/01_Hero.chara")
	var clash := PhiCharacters.make_display_name("Hero", [], root)
	_check_eq(bool(clash["ok"]), false, "display name folder clash")
	_check(str(clash.get("error", "")).contains("重なってしまいます"), "display name clash message")
	# 上限(32件)で落ちる。
	var full: Array = []
	for i in PhiCharacters.MAX_CHARACTER_COUNT:
		full.append({"display_name": "%02d_C%d" % [i + 1, i]})
	var over := PhiCharacters.make_display_name("Hero", full, root)
	_check_eq(bool(over["ok"]), false, "display name over limit")
	_check(str(over.get("error", "")).contains("上限"), "display name limit message")


func _test_phirc() -> void:
	# 往復: 書いて読み直す。
	var root := _work + "/phirc"
	DirAccess.make_dir_recursive_absolute(root)
	_check(PhiCharacters.write_phirc(root, "01_Hero", "ABCDE12345abc123", "192.0.2.1", 20021), "phirc write ok")
	var data := FileAccess.get_file_as_bytes(root + "/01_Hero.chara/.phirc")
	_check(not data.is_empty(), "phirc file exists")
	var parsed := PhiCharacters.parse_phirc_text(Cp932.decode(data))
	_check_eq(str(parsed.get("id", "")), "ABCDE12345abc123", "phirc roundtrip id")
	_check_eq(str(parsed.get("host", "")), "192.0.2.1", "phirc roundtrip host")
	_check_eq(int(parsed.get("port", 0)), 20021, "phirc roundtrip port")
	# 区切りの変種(WPHI read_philly の例)。
	_check_eq(int(PhiCharacters.parse_phirc_text("XYZ\n192.0.2.2 9001\n").get("port", 0)), 9001, "phirc space separator")
	_check_eq(int(PhiCharacters.parse_phirc_text("XYZ\n192.0.2.2\t9002\n").get("port", 0)), 9002, "phirc tab separator")
	_check_eq(str(PhiCharacters.parse_phirc_text("XYZ\r\n192.0.2.2:9003\r\n").get("host", "")), "192.0.2.2", "phirc crlf host")
	# 読めないものは空。
	_check(PhiCharacters.parse_phirc_text("ONLY_ID\n").is_empty(), "phirc one line ng")
	_check(PhiCharacters.parse_phirc_text("\n192.0.2.2:9000\n").is_empty(), "phirc empty id ng")
	_check(PhiCharacters.parse_phirc_text("XYZ\n192.0.2.2\n").is_empty(), "phirc no port ng")
	_check(PhiCharacters.parse_phirc_text("XYZ\n192.0.2.2:abc\n").is_empty(), "phirc bad port ng")
	# 走査: 有効なものだけ、大小文字不問、表示名順。
	PhiCharacters.write_phirc(root, "02_Mage", "ID2222", "192.0.2.2", 20017)
	DirAccess.make_dir_recursive_absolute(root + "/03_Broken.chara")
	DirAccess.make_dir_recursive_absolute(root + "/04_Upper.Chara")
	var upper := FileAccess.open(root + "/04_Upper.Chara/.phirc", FileAccess.WRITE)
	upper.store_buffer(Cp932.encode("ID4444\n192.0.2.4:20019\n"))
	upper.close()
	DirAccess.make_dir_recursive_absolute(root + "/notchara")
	var scanned := PhiCharacters.scan_root(root)
	_check_eq(scanned.size(), 3, "scan count")
	if scanned.size() == 3:
		_check_eq(str(scanned[0].get("display_name", "")), "01_Hero", "scan sorted 1")
		_check_eq(str(scanned[1].get("display_name", "")), "02_Mage", "scan sorted 2")
		_check_eq(str(scanned[2].get("display_name", "")), "04_Upper", "scan case-insensitive ext")
		_check_eq(str(scanned[2].get("root", "")), root, "scan keeps root")


func _test_register_trace() -> void:
	# プロトコル.txt の RECV 列を流し、SEND 列と発行 ID を照合する。
	_check_eq(PhiRegister.login_lines(), ["#open newuser", "#version-cli 05107100", "#map-iv 15", "#status-iv 30", "#ex-switch eagleeye=form", "#map"], "register login lines")
	var reg := PhiRegister.new("test3", "hMCo2S", "@")
	var recv_lines: Array[String] = [
		" This phi server is based on v5y rel.5c AnblickMasse (No Skill) with 日本語. ",
		"         /*color=teal*/Tofup Server Edition v5.3/*.*/ /*color=blue*/'Black Kitten'/*.*/ modified by NEO. ",
		"",
		" Welcome to the world of Phantasmal Island(PHI).",
		"",
		"DM > First, you must create your account.",
		"DM > Please enter your name (within 31 letters):",
		"#version-dm v5x:011:0005:35",
		"#version-srv 05115000",
		"You > test3",
		"DM > Please enter your password (within 6 letters):",
		"You > hMCo2S",
		"DM > Plese enter your E-Mail address:",
		"You > @",
		"     ID    : TEST00001hMCo2S",
		"     Name  : Test3",
		"     E-mail: @",
		"DM > OK ? [y/n]",
		"You > y",
		"#set-user-id TEST00001hMCo2S",
	]
	var sent: Array[String] = []
	for line in recv_lines:
		sent.append_array(reg.feed(line))
	_check_eq(sent, ["test3", "hMCo2S", "@", "y"], "register trace sends")
	_check(reg.done, "register trace done")
	_check(not reg.failed, "register trace not failed")
	_check_eq(reg.issued_id, "TEST00001hMCo2S", "register trace issued id")
	# 成功後はもう応答しない。
	_check_eq(reg.feed("DM > Please enter your name (within 31 letters):"), [], "register silent after done")


func _test_register_reprompts() -> void:
	var reg := PhiRegister.new("Hero", "abc123", "h@x")
	# 再入力プロンプト("re-enter")にも応答する。
	_check_eq(reg.feed("DM > Please re-enter your name (within 31 letters):"), ["Hero"], "register re-enter name")
	_check_eq(reg.feed("DM > Please re-enter your password (within 6 letters):"), ["abc123"], "register re-enter password")
	# 初期グラ選択(サーバに初期グラがある時)には先頭を選ぶ。
	_check_eq(reg.feed("DM > Please select initial charactor graphic:"), ["0"], "register graphic prompt")
	_check_eq(reg.feed("DM > Please re-select initial charactor graphic:"), ["0"], "register graphic reprompt")
	# 上限: 名前プロンプトは通算3回まで。4回目で失敗になる。
	var reg2 := PhiRegister.new("Hero", "abc123", "h@x")
	_check_eq(reg2.feed("DM > Please enter your name (within 31 letters):"), ["Hero"], "register limit 1")
	_check_eq(reg2.feed("DM > Please re-enter your name (within 31 letters):"), ["Hero"], "register limit 2")
	_check_eq(reg2.feed("DM > Please re-enter your name (within 31 letters):"), ["Hero"], "register limit 3")
	_check_eq(reg2.feed("DM > Please re-enter your name (within 31 letters):"), [], "register limit 4 no answer")
	_check(reg2.failed, "register limit failed")
	_check(not reg2.done, "register limit not done")
	# 無関係な行には応答しない。
	var reg3 := PhiRegister.new("Hero", "abc123", "h@x")
	_check_eq(reg3.feed("DM > Hero は魔法を唱えている..."), [], "register ignores other dm lines")
	_check_eq(reg3.feed("#name Hero"), [], "register ignores sharp lines")
	_check_eq(reg3.feed(""), [], "register ignores empty")
