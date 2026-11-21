class_name PhiFx
extends RefCounted
## DM 演出拡張 (FX) の共通部品: サーバ画像のハッシュとキャッシュ。
##
## ハッシュは FNV-1a 32bit (キャッシュキーと転送の完全性確認用で、
## セキュリティ用途ではない)。サーバ側と同一の計算にする。

static func fnv1a(data: PackedByteArray) -> int:
	var h := 2166136261
	for b in data:
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


static func hash_hex(data: PackedByteArray) -> String:
	return "%08x" % fnv1a(data)


static func cache_path(img_name: String, hash_str: String) -> String:
	## キャッシュファイルの場所。hash が変われば別ファイルになる。
	return "user://fx_cache/%s.%s.bmp" % [img_name, hash_str]
