extends SceneTree
## WPHI と同じ UI フォント(PhiFont)のテスト。
##
## 使い方: godot --headless --path . -s tests/test_font.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0


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


func _initialize() -> void:
	_test_stack_order()
	_test_ui_font()
	_test_bold_font()
	_test_glyphs()
	print("test_font: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _test_stack_order() -> void:
	# OS 既定のフォントが最優先。Mac は SF Pro Text＋ヒラギノ、
	# Windows は Segoe UI、Linux は Noto Sans JP。
	_check_eq(PhiFont.MAC_FONT_NAMES[0], "SF Pro Text", "mac first is SF Pro Text")
	_check(PhiFont.MAC_FONT_NAMES.find("SF Pro Text") < PhiFont.MAC_FONT_NAMES.find("Hiragino Sans"), "SF before Hiragino")
	_check_eq(PhiFont.WINDOWS_FONT_NAMES[0], "Segoe UI Variable Text", "win first is Segoe UI Variable Text")
	_check(PhiFont.WINDOWS_FONT_NAMES.find("Segoe UI") < PhiFont.WINDOWS_FONT_NAMES.find("BIZ UDPGothic"), "Segoe before BIZ")
	_check_eq(PhiFont.LINUX_FONT_NAMES[0], "Noto Sans JP", "linux first is Noto Sans JP")
	# この環境は Linux なので、主フォントは Linux の並びになる。
	_check_eq(PhiFont.primary_font_names()[0], "Noto Sans JP", "primary names on linux")
	# フォールバックには日本語フォントが入っている。
	_check(PhiFont.CJK_FALLBACK_NAMES.has("Hiragino Sans"), "fallback has Hiragino")
	_check(PhiFont.CJK_FALLBACK_NAMES.has("Noto Sans CJK JP"), "fallback has Noto CJK")


func _test_ui_font() -> void:
	var sys := PhiFont.make_system_font()
	_check(sys is SystemFont, "system font type")
	_check_eq(sys.font_names[0], "Noto Sans JP", "system font first name")
	var font := PhiFont.make_ui_font(sys)
	_check(font is FontVariation, "ui font is FontVariation")
	var variation := font as FontVariation
	_check(variation.base_font == sys, "ui font wraps system font")
	_check(variation.opentype_features.is_empty(), "ui font has no opentype features (palt drops glyphs)")
	_check_eq(variation.variation_embolden, 0.0, "ui font not emboldened")
	_check_eq(variation.fallbacks.size(), 1, "ui font has one fallback")
	var fallback: Font = variation.fallbacks[0]
	_check(fallback is SystemFont, "fallback is SystemFont")
	_check((fallback as SystemFont).font_names.has("Hiragino Sans"), "fallback names have Hiragino")


func _test_bold_font() -> void:
	var sys := PhiFont.make_system_font()
	var font := PhiFont.make_bold_font(sys)
	var variation := font as FontVariation
	_check(variation.base_font == sys, "bold font wraps system font")
	_check(variation.opentype_features.is_empty(), "bold font has no opentype features")
	_check_eq(variation.variation_embolden, 1.0, "bold font emboldened")
	_check_eq(variation.fallbacks.size(), 1, "bold font has one fallback")


func _test_glyphs() -> void:
	# 日本語の字が幅を持って出る(この環境では Noto Sans CJK JP が見つかる)。
	var font := PhiFont.make_ui_font()
	_check(font.get_string_size("あいう", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 0.0, "jp advances")
	_check(font.get_string_size("NeoPHI", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 0.0, "latin advances")
	_check(font.get_height(16) > 0.0, "font height")
	var bold := PhiFont.make_bold_font()
	_check(bold.get_string_size("あいう", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 0.0, "bold jp advances")
