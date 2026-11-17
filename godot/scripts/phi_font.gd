class_name PhiFont
extends RefCounted
## UI フォントの設定。
##
## 方針: WPHI の CSS(`--ui-font`)とまったく同じ名前・同じ順番で
## 探す(2026-11-16、ユーザーの「WPHI と同じにしたい」で変更)。
## WPHI はフォントを同梱しておらず、環境にあるフォントが
## 使われる。Mac に Noto Sans JP が無ければ欧文は San Francisco、
## 日本語はヒラギノに落ちる(WPHI でも NeoPHI でも同じ)。
##
## 注意: WPHI の `font-feature-settings: "palt"` は、Godot で有効に
## すると MenuButton の末尾の字(「ファイル」のルなど)が描かれなく
## なるため使わない(2026-11-15 に実機確認)。

## WPHI の --ui-font の並び + 無い字のための後続候補。
## 最初に見つかったものが主フォントになり、残りは
## フォールバック側でも同じ並びで探す。
const WPHI_FONT_NAMES: Array[String] = [
	"Noto Sans JP",
	"Noto Sans CJK JP",
	"Segoe UI Variable Text",
	"Segoe UI",
	"BIZ UDPGothic",
	"SF Pro Text",
	".AppleSystemUIFont",
	"SF Pro",
	"Hiragino Sans",
	"Hiragino Kaku Gothic ProN",
	"Yu Gothic UI",
	"Yu Gothic",
	"Meiryo UI",
	"Meiryo",
	"Noto Sans CJK",
	"TakaoGothic",
	"IPAexGothic",
]

## 主フォントに無い字(主に日本語)を出すフォールバック。
## WPHI と同じ並びをそのまま使う。
const CJK_FALLBACK_NAMES: Array[String] = WPHI_FONT_NAMES


static func primary_font_names() -> Array[String]:
	return WPHI_FONT_NAMES


## 地図の倍率から UI の文字サイズを決める。第4段で少し小さくし、
## レイアウト変更でもうひと回り小さくし、さらに全体を2ポイント
## 小さくした(2026-11-16、ユーザーの要望)。ログ・入力欄など。
static func ui_size_for_zoom(zoom: int) -> int:
	return maxi(6 * zoom - 2, 6)


## メニューバー・プルダウンメニュー・ツールチップの文字サイズ。
## ログと同じ大きさに統一した(2026-11-16、ユーザーの要望)。
static func chrome_size_for_zoom(zoom: int) -> int:
	return ui_size_for_zoom(zoom)


## HP/MP ゲージの数字の大きさ。ログと同じ大きさに統一した。
static func gauge_size_for_zoom(zoom: int) -> int:
	return ui_size_for_zoom(zoom)


## ゲージの下のステータス行(F/W/M/C/GP)の文字の大きさ。
## ログと同じ大きさに統一した。
static func status_size_for_zoom(zoom: int) -> int:
	return ui_size_for_zoom(zoom)


static func make_system_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = primary_font_names()
	return font


static func make_fallback_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = CJK_FALLBACK_NAMES
	return font


static func make_ui_font(system_font: SystemFont = null) -> Font:
	## 通常フォント。FontVariation で包むのは太字と対称にするため。
	var base := system_font if system_font != null else make_system_font()
	var variation := FontVariation.new()
	variation.base_font = base
	variation.fallbacks = [make_fallback_font()]
	return variation


static func make_bold_font(system_font: SystemFont = null) -> Font:
	## embolden で太らせた太字フォント。
	## システムフォントに太字バリアントが無い場合でも太く見える。
	var base := system_font if system_font != null else make_system_font()
	var variation := FontVariation.new()
	variation.base_font = base
	variation.fallbacks = [make_fallback_font()]
	variation.variation_embolden = 1.0
	return variation


static func make_italics_font(system_font: SystemFont = null) -> Font:
	## 変形で傾けた疑似イタリックフォント。RichTextLabel の
	## [i] は italics_font を引くので、明示しないと既定テーマの
	## フォント (日本語を持たない) に落ちて傾きも太さも出ない。
	var base := system_font if system_font != null else make_system_font()
	var variation := FontVariation.new()
	variation.base_font = base
	variation.fallbacks = [make_fallback_font()]
	variation.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	return variation


static func make_bold_italics_font(system_font: SystemFont = null) -> Font:
	## 太字+イタリック ([b][i] の重ね掛け用)。
	var base := system_font if system_font != null else make_system_font()
	var variation := FontVariation.new()
	variation.base_font = base
	variation.fallbacks = [make_fallback_font()]
	variation.variation_embolden = 1.0
	variation.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	return variation
