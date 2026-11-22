extends SceneTree
## 第129段: fastmove (高速移動) のクライアント宣言。
## (1) ログイン申告に `#ex-switch fastmove=1` が入る
##     (login_lines / post_register_lines の両方、fx・height の後)。
## (2) サーバからのエコー `#ex-switch fastmove=1` は、既存の
##     fx=1 / height=1 のエコーと同じくパーサが無視する。
##
## 使い方: godot --headless --path . -s tests/test_stage129.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _checks := 0
var _failures := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# -- (1) ログイン申告 --
	var lines := PhiSession.login_lines("X")
	check(lines.has("#ex-switch fastmove=1"), "login_lines に fastmove=1")
	check(lines.find("#ex-switch fastmove=1") > lines.find("#ex-switch height=1"), "login_lines で fastmove は height の後")
	var lines_null := PhiSession.login_lines(null)
	check(lines_null.has("#ex-switch fastmove=1"), "login_lines (世界移動後) に fastmove=1")
	var post := PhiSession.post_register_lines()
	check(post.has("#ex-switch fastmove=1"), "post_register_lines に fastmove=1")
	check(post.find("#ex-switch fastmove=1") > post.find("#ex-switch height=1"), "post_register_lines で fastmove は height の後")

	# -- (2) サーバエコーは無視される --
	var parser := PhiParser.new()
	check(parser.feed(Cp932.encode("#ex-switch fastmove=1")).is_empty(), "fastmove エコーは無視")
	check(parser.feed(Cp932.encode("#ex-switch fx=1")).is_empty(), "fx エコーは無視")
	check(parser.feed(Cp932.encode("#ex-switch height=1")).is_empty(), "height エコーは無視")

	print("test_stage129: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
