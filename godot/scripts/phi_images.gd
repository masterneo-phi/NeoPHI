class_name PhiImages
extends RefCounted
## 画像参照の抜き出しと、取得してよいかの判定。画像表示窓の土台。
##
## セキュリティ: 外部ホストへの画像取得はしない。接続中のゲーム
## サーバと同じホストの URL だけ、ユーザーが明示的にクリックした
## 時に限り、サイズ上限つきで取得する。自動取得はしない。
## ここでは判定だけを行い、取得そのものは窓側で行う。

## 取得する画像の大きさの上限(バイト)。
const MAX_IMAGE_BYTES := 2 * 1024 * 1024

const _URL_TAIL_TRIM := ".,;:!?)]}'\""


static func extract_refs(raw_text: String) -> Array[String]:
	## 行から画像の参照(URL)を、現れた順に重複なく抜く。
	## `/*img=URL*/`・`/*image=URL*/` のタグと、裸の URL が対象。
	## タグの中の URL は裸の URL としては拾わない。
	var found: Array = []
	var lower := raw_text.to_lower()
	var spans: Array = []
	for prefix in ["/*img=", "/*image="]:
		var pos := 0
		while true:
			var start := lower.find(prefix, pos)
			if start < 0:
				break
			var close := raw_text.find("*/", start + prefix.length())
			if close < 0:
				break
			spans.append([start, close + 2])
			var body := raw_text.substr(start + prefix.length(), close - (start + prefix.length())).strip_edges()
			if not body.is_empty():
				var url := body.split(" ", false, 1)[0].strip_edges()
				found.append([start, url])
			pos = close + 2
	var re := RegEx.new()
	re.compile("https?://[^\\s<>\"']+")
	for m in re.search_all(raw_text):
		var mstart := m.get_start()
		var inside := false
		for span in spans:
			if mstart >= int(span[0]) and mstart < int(span[1]):
				inside = true
				break
		if inside:
			continue
		found.append([mstart, _trim_url_tail(m.get_string())])
	found.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var out: Array[String] = []
	var seen := {}
	for pair in found:
		_add_ref(out, seen, str(pair[1]))
	return out


static func _add_ref(out: Array[String], seen: Dictionary, url: String) -> void:
	if url.is_empty() or seen.has(url):
		return
	seen[url] = true
	out.append(url)


static func _trim_url_tail(url: String) -> String:
	var out := url
	while not out.is_empty() and _URL_TAIL_TRIM.contains(out[out.length() - 1]):
		out = out.substr(0, out.length() - 1)
	return out


static func parse_url(url: String) -> Dictionary:
	## URL を {scheme, host, port, path} に分ける。読めなければ {}。
	## userinfo(`@` を含む authority)は受け付けない。
	var scheme_end := url.find("://")
	if scheme_end <= 0:
		return {}
	var scheme := url.substr(0, scheme_end).to_lower()
	var rest := url.substr(scheme_end + 3)
	var slash := rest.find("/")
	var authority := rest if slash < 0 else rest.substr(0, slash)
	var path := "" if slash < 0 else rest.substr(slash)
	if authority.is_empty() or authority.contains("@"):
		return {}
	var host := authority
	var port := 0
	var colon := authority.rfind(":")
	if colon >= 0:
		var port_text := authority.substr(colon + 1)
		if port_text.is_valid_int():
			port = int(port_text)
			host = authority.substr(0, colon)
		elif port_text.is_empty():
			host = authority.substr(0, colon)
		else:
			return {}
	if host.is_empty():
		return {}
	return {"scheme": scheme, "host": host, "port": port, "path": path}


static func can_fetch(url: String, server_host: String) -> bool:
	## 取得してよい URL か。http/https で、ホストが接続中の
	## ゲームサーバと一致するものだけ。
	if server_host.is_empty():
		return false
	var parsed := parse_url(url)
	if parsed.is_empty():
		return false
	if str(parsed["scheme"]) != "http" and str(parsed["scheme"]) != "https":
		return false
	return str(parsed["host"]).to_lower() == server_host.to_lower()
