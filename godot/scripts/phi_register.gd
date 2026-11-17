class_name PhiRegister
extends RefCounted
## 新規キャラクター作成の会話(Philly 本体の classNewCharacter の
## RecvLoop の移植)。状態機械だけの純粋な実装で、通信は持たない。
##
## `feed()` に解読済みの受信行を渡すと、送るべき行の配列を返す。
## サーバのプロンプトは英語でそのまま届く(実サーバ phi_dm の文言):
## - 名前: "enter your name" を含む行(再入力は "re-enter" になる)
## - パスワード: "enter your password" を含む行(同上)
## - メール: "enter your E-Mail" を含む行(サーバ側の綴りは "Plese")
## - 初期グラ選択: "select initial charactor graphic" を含む行
##   (サーバに初期グラが設定されている時だけ来る。先頭のものを選ぶ)
## - 確認: "DM > OK ? [y/n]" で始まる行 → `y`
## 同じプロンプトの再表示には再応答するが、種別ごとに上限回数まで。
## `#set-user-id <ID>` が来たら成功で、`issued_id` に ID が入る。

## プロンプト種別ごとの応答の上限。これを超えたら失敗とする。
const MAX_ANSWERS := 3

const PROMPT_NAME := "enter your name"
const PROMPT_PASSWORD := "enter your password"
const PROMPT_MAIL := "enter your E-Mail"
const PROMPT_GRAPHIC := "select initial charactor graphic"
const PROMPT_OK := "DM > OK ? [y/n]"
const SET_USER_ID := "#set-user-id"

var char_name := ""
var password := ""
var mail := ""
## 発行された ID。成功時にだけ入る。
var issued_id := ""
## 成功したか。
var done := false
## 応答上限を超えて失敗したか。
var failed := false

var _answers := {"name": 0, "password": 0, "mail": 0, "graphic": 0, "confirm": 0}


func _init(p_name: String = "", p_password: String = "", p_mail: String = "") -> void:
	char_name = p_name
	password = p_password
	mail = p_mail


static func login_lines() -> Array[String]:
	## 作成セッションのログイン行(プロトコル.txt の SEND 列)。
	## 通常ログインと違い `#map-iv 15` / `#status-iv 30` で、
	## 末尾に `#map` を送る。
	return [
		"#open newuser",
		"#version-cli 05107100",
		"#map-iv 15",
		"#status-iv 30",
		"#ex-switch eagleeye=form",
		"#map",
	]


func feed(line: String) -> Array[String]:
	## 受信行1行を渡し、送るべき行の配列を受け取る。
	var out: Array[String] = []
	if done or failed:
		return out
	if line.begins_with(SET_USER_ID):
		var id := line.substr(SET_USER_ID.length()).strip_edges()
		if not id.is_empty():
			issued_id = id
			done = true
		return out
	if not line.begins_with("DM > "):
		return out
	var kind := ""
	var answer := ""
	if line.contains(PROMPT_NAME):
		kind = "name"
		answer = char_name
	elif line.contains(PROMPT_PASSWORD):
		kind = "password"
		answer = password
	elif line.contains(PROMPT_MAIL):
		kind = "mail"
		answer = mail
	elif line.contains(PROMPT_GRAPHIC):
		kind = "graphic"
		answer = "0"
	elif line.begins_with(PROMPT_OK):
		kind = "confirm"
		answer = "y"
	if kind.is_empty():
		return out
	_answers[kind] = int(_answers[kind]) + 1
	if int(_answers[kind]) > MAX_ANSWERS:
		failed = true
		return out
	out.append(answer)
	return out
