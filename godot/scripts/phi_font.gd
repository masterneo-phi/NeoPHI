class_name PhiFont
extends RefCounted
## OS 既定の UI フォントを使うための設定。
##
## 方針: 各 OS の既定フォントを最優先にする。Mac では San Francisco
## (SF Pro Text)＋ヒラギノ、Windows では Segoe UI＋BIZ UDPゴシック/
## 游ゴシック、Linux では Noto Sans CJK JP。欧文フォントに無い字は
## フォールバックの日本語フォントで出す。
##
## 以前は WPHI の CSS(`--ui-font`)と同じ順番(Noto Sans JP 最優先)で
## 探していたが、Mac では結局ヒラギノが選ばれて見た目が変わらな
## かったため、OS 既定の方針に変えた(2026-11-15)。
##
## 注意: WPHI の `font-feature-settings: "palt"` は、Godot で有効に
## すると MenuButton の末尾の字(「ファイル」のルなど)が描かれなく
## なるため使わない(2026-11-15 に実機確認)。

## Mac: SF Pro Text が見つかれば欧文はそれになり、無い字は
## フォールバックのヒラギノで出る。SF が見つからなければ
## ヒラギノが主フォントになる(従来どおり)。
const MAC_FONT_NAMES: Array[String] = [
	"SF Pro Text",
	".AppleSystemUIFont",
	"SF Pro",
	"Hiragino Sans",
	"Hiragino Kaku Gothic ProN",
	"Noto Sans JP",
	"Noto Sans CJK JP",
]

const WINDOWS_FONT_NAMES: Array[String] = [
	"Segoe UI Variable Text",
	"Segoe UI",
	"BIZ UDPGothic",
	"Yu Gothic UI",
	"Yu Gothic",
	"Meiryo UI",
	"Meiryo",
	"Noto Sans JP",
	"Noto Sans CJK JP",
]

const LINUX_FONT_NAMES: Array[String] = [
	"Noto Sans JP",
	"Noto Sans CJK JP",
	"Noto Sans CJK",
	"TakaoGothic",
	"IPAexGothic",
]

## 主フォントに無い字(主に日本語)を出すフォールバック。
## OS ごとに最初に見つかったものが使われる。
const CJK_FALLBACK_NAMES: Array[String] = [
	"Hiragino Sans",
	"Hiragino Kaku Gothic ProN",
	"Noto Sans JP",
	"Noto Sans CJK JP",
	"BIZ UDPGothic",
	"Yu Gothic UI",
	"Yu Gothic",
	"Meiryo UI",
	"Meiryo",
	"Noto Sans CJK",
	"TakaoGothic",
	"IPAexGothic",
]


static func primary_font_names() -> Array[String]:
	match OS.get_name():
		"macOS":
			return MAC_FONT_NAMES
		"Windows":
			return WINDOWS_FONT_NAMES
		_:
			return LINUX_FONT_NAMES


## 地図の倍率から UI の文字サイズを決める。第4段で少し小さくし、
## レイアウト変更でもうひと回り小さくした。ログ・入力欄などは 6*zoom。
static func ui_size_for_zoom(zoom: int) -> int:
	return 6 * zoom


## メニューバー・プルダウンメニュー・ツールチップの文字サイズ。
## 7*zoom で、最低 16。
static func chrome_size_for_zoom(zoom: int) -> int:
	return maxi(7 * zoom, 16)


## HP/MP ゲージの数字の大きさ。UI 文字より大きくする
## (小さくすると読めないため)。8*zoom で、最低 14。
static func gauge_size_for_zoom(zoom: int) -> int:
	return maxi(8 * zoom, 14)


## ゲージの下のステータス行(F/W/M/C/GP)の文字の大きさ。
## 7*zoom で、最低 14。
static func status_size_for_zoom(zoom: int) -> int:
	return maxi(7 * zoom, 14)


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
