class_name PhiDigits
extends RefCounted
## 全角の数字を半角に直す。日本語IMEのまま数字を入れると
## 全角数字(１２３)になり、サーバが数として読めないため、
## 数字を入れる欄(pay・int_dialog・ポート欄)で使う。
## 日本語の文字はそのままにする。


## 全角数字(０〜９)・全角マイナス(－)・全角ピリオド(．)を
## 半角に直す。それ以外の文字は変えない。
static func to_half_width_digits(text: String) -> String:
	var chars := PackedStringArray()
	for i in range(text.length()):
		var code := text.unicode_at(i)
		if code >= 0xFF10 and code <= 0xFF19:
			chars.append(String.chr(code - 0xFF10 + 0x30))
		elif code == 0xFF0D:
			chars.append("-")
		elif code == 0xFF0E:
			chars.append(".")
		else:
			chars.append(text.substr(i, 1))
	return "".join(chars)
