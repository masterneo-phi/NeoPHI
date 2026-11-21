extends SceneTree
## 第122段: DM 演出拡張 (FX)。
## (1) ログイン申告に `#ex-switch fx=1` が入る。
## (2) パーサが `#fx` 行をイベント化し、未知の kind を無視する。
## (3) 地図フレームの C 行末尾の cn マスク (状態異常・バフ) を読む。
## (4) FNV-1a ハッシュが既知ベクトルと一致する。
## (5) PhiCharaState のアイコン割り当てと MapView の演出状態。

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
	# -- (1) ログイン申告 --
	check(PhiSession.login_lines("X").has("#ex-switch fx=1"), "login_lines に fx=1")
	check(PhiSession.post_register_lines().has("#ex-switch fx=1"), "post_register_lines に fx=1")

	# -- (2) #fx パーサ --
	var parser := PhiParser.new()
	var evs := parser.feed(Cp932.encode("#fx text C 200 4000 第四章"))
	check(evs.size() == 1 and evs[0].get("type") == "fx" and evs[0].get("kind") == "text", "fx text イベント")
	check(evs.size() == 1 and evs[0].get("pos") == "C" and int(evs[0].get("size", 0)) == 200 and int(evs[0].get("dur", 0)) == 4000 and evs[0].get("text") == "第四章", "fx text の引数 (本文に空白なし)")
	evs = parser.feed(Cp932.encode("#fx text B 100 2000 第 4 章 始まり"))
	check(evs.size() == 1 and evs[0].get("text") == "第 4 章 始まり", "fx text の本文は残り全部 (空白を含む)")
	evs = parser.feed(Cp932.encode("#fx dark 80 3000 1"))
	check(evs.size() == 1 and int(evs[0].get("level", -1)) == 80 and int(evs[0].get("mode", -1)) == 1, "fx dark の引数")
	evs = parser.feed(Cp932.encode("#fx wipe C on"))
	check(evs.size() == 1 and evs[0].get("pattern") == "C" and evs[0].get("dir") == "on", "fx wipe の引数")
	evs = parser.feed(Cp932.encode("#fx img M crest 0123abcd 5000"))
	check(evs.size() == 1 and evs[0].get("where") == "M" and evs[0].get("name") == "crest" and evs[0].get("hash") == "0123abcd" and int(evs[0].get("dur", 0)) == 5000, "fx img の引数")
	evs = parser.feed(Cp932.encode("#fx imgdata crest 1234 0123abcd"))
	check(evs.size() == 1 and int(evs[0].get("total", 0)) == 1234, "fx imgdata の引数")
	evs = parser.feed(Cp932.encode("#fx imgchunk crest 0 QUJD"))
	check(evs.size() == 1 and int(evs[0].get("seq", -1)) == 0 and evs[0].get("data") == "QUJD", "fx imgchunk の引数")
	evs = parser.feed(Cp932.encode("#fx imgend crest"))
	check(evs.size() == 1 and evs[0].get("name") == "crest", "fx imgend")
	evs = parser.feed(Cp932.encode("#fx shake 6 800"))
	check(evs.size() == 1 and int(evs[0].get("amp", 0)) == 6 and int(evs[0].get("dur", 0)) == 800, "fx shake の引数")
	evs = parser.feed(Cp932.encode("#fx glow 1500"))
	check(evs.size() == 1 and int(evs[0].get("dur", 0)) == 1500, "fx glow の引数")
	evs = parser.feed(Cp932.encode("#fx textoff all"))
	check(evs.size() == 1 and evs[0].get("pos") == "all", "fx textoff")
	evs = parser.feed(Cp932.encode("#fx nosuchkind 1 2 3"))
	check(evs.is_empty(), "未知の kind は無視")
	evs = parser.feed(Cp932.encode("#fx dark 80"))
	check(evs.is_empty(), "引数不足は無視")

	# -- (3) cn マスク --
	var p121 := PhiParser.new()
	p121._parse_m121_o(_m121_o_line("000000"))
	check(p121._map_chars.size() == 1 and int(p121._map_chars[0].get("cn", -1)) == 0, "m121 cn なし=0")
	var p121b := PhiParser.new()
	p121b._parse_m121_o(_m121_o_line("000802"))
	check(p121b._map_chars.size() == 1 and int(p121b._map_chars[0].get("cn", -1)) == 0x802, "m121 cn を読む (毒+シェル)")
	var p57 := PhiParser.new()
	p57._parse_m57_o(_m57_o_line("080001"))
	check(p57._map_chars.size() == 1 and int(p57._map_chars[0].get("cn", -1)) == 0x80001, "m57 cn を読む (麻痺+コート)")
	var p57b := PhiParser.new()
	p57b._parse_m57_o(_m57_o_line(""))
	check(p57b._map_chars.size() == 1 and int(p57b._map_chars[0].get("cn", -1)) == 0, "m57 cn なし=0")

	# -- (4) FNV-1a --
	check(PhiFx.fnv1a(PackedByteArray()) == 2166136261, "fnv1a 空")
	check(PhiFx.fnv1a("a".to_ascii_buffer()) == 0xe40c292c, "fnv1a 'a'")
	check(PhiFx.fnv1a("hello".to_ascii_buffer()) == 0x4f9f2cab, "fnv1a 'hello'")
	check(PhiFx.hash_hex("hello".to_ascii_buffer()) == "4f9f2cab", "hash_hex")
	check(PhiFx.cache_path("crest", "4f9f2cab") == "user://fx_cache/crest.4f9f2cab.bmp", "cache_path")

	# -- (5) アイコン割り当てと演出状態 --
	var cn := (1 << 11) | (1 << 1) | (1 << 17)
	check(PhiCharaState.fx_icons_for(cn) == [11, 17, 1], "アイコン順 (異常→バフ)")
	check(PhiCharaState.fx_has_buff(cn), "バフありでオーラ点灯")
	check(not PhiCharaState.fx_has_buff(1 << 11), "異常だけではオーラなし")
	check(PhiCharaState.fx_icons_for(0).is_empty(), "マスク0はアイコンなし")
	check(PhiCharaState.fx_icons_for((1 << 19) | (1 << 20) | (1 << 21)).is_empty(), "内部状態 (19-21) は出さない")

	var mv := MapView.new()
	root.add_child(mv)
	mv.apply_fx({"kind": "text", "pos": "C", "size": 200, "dur": 4000, "text": "第四章"})
	check(mv._fx_texts.has("C") and mv._fx_texts["C"].get("text") == "第四章", "MapView text 状態")
	mv.apply_fx({"kind": "textoff", "pos": "C"})
	check(not mv._fx_texts.has("C"), "MapView textoff")
	mv.apply_fx({"kind": "dark", "level": 80, "dur": 3000, "mode": 1})
	check(int(mv._fx_dark.get("level", 0)) == 80, "MapView dark 状態")
	mv.apply_fx({"kind": "dark", "level": 0, "dur": 0, "mode": 0})
	check(mv._fx_dark.is_empty(), "MapView dark 解除")
	mv.apply_fx({"kind": "wipe", "pattern": "C", "dir": "on"})
	check(mv._fx_wipe.get("pattern") == "C", "MapView wipe 状態")
	mv.apply_fx({"kind": "shake", "amp": 6, "dur": 800})
	check(mv._fx_shake_until > 0.0 and mv._fx_shake_amp == 6.0, "MapView shake 状態")
	mv.apply_fx({"kind": "glow", "dur": 1500})
	check(not mv._fx_glow.is_empty(), "MapView glow 状態")
	mv.apply_fx({"kind": "clear"})
	check(mv._fx_texts.is_empty() and mv._fx_dark.is_empty(), "MapView clear")
	mv.free()

	print("stage122 checks=", _checks, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _put(raw: PackedByteArray, off: int, s: String) -> void:
	var b := s.to_ascii_buffer()
	for i in b.size():
		raw[off + i] = b[i]


func _m121_o_line(mask_hex: String) -> PackedByteArray:
	## `#m121 O` の C 行 (名前開始位置 base からの固定オフセット)。
	var raw := PackedByteArray()
	raw.resize(120)
	for i in raw.size():
		raw[i] = 0x20
	_put(raw, 0, "#m121 O C0001:5 5 F ")
	var base := 20
	_put(raw, base, "Tester")
	_put(raw, base + 32, "00")
	_put(raw, base + 35, "human")
	raw[base + 51] = 0x23 # '#'
	_put(raw, base + 53, "00")
	if not mask_hex.is_empty():
		_put(raw, base + 56, mask_hex)
	return raw


func _m57_o_line(mask_hex: String) -> PackedByteArray:
	## `#m57 O` の C 行 (固定位置)。
	var raw := PackedByteArray()
	raw.resize(90)
	for i in raw.size():
		raw[i] = 0x20
	_put(raw, 0, "#m57 O C")
	_put(raw, 8, "0001")
	raw[13] = 0x35 # '5'
	raw[15] = 0x35
	raw[17] = 0x46 # 'F'
	_put(raw, 19, "Tester")
	_put(raw, 51, "00")
	_put(raw, 54, "human")
	raw[70] = 0x23
	_put(raw, 72, "00")
	if not mask_hex.is_empty():
		_put(raw, 75, mask_hex)
	return raw
