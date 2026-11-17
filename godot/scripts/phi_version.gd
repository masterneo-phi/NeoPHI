class_name PhiVersion
extends RefCounted
## NeoPHI のバージョン番号。番号の定義はここだけ。
## メニューの項目と About ダイアログは、ここを見て表示する。

const VERSION := "0.5.0"
## 作者名。About ダイアログにだけ出す(メニューの項目名には
## 入れない。項目名は「NeoPHI <番号>」だけにする決まり)。
const AUTHOR := "Master NEO"


## About ダイアログの本文。1行目が名前と番号、2行目が作者、
## 3行目がエンジン。
static func about_text() -> String:
	return "NeoPHI\nPhantasmal Island Client\nバージョン " + VERSION + "\n作者 " + AUTHOR + "\nGodot " + str(Engine.get_version_info()["string"])
