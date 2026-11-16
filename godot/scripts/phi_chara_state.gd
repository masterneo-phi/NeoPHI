class_name PhiCharaState
extends RefCounted
## `#m57 O` の状態コード → Items.bmp の状態アイコン。
## Philly MakeMap.cpp の DrawCharaGraEffectUnder/Over の対応表。
##
## 位置は [セル番号, dx, dy] で、基準点はキャラの描画位置の
## 左上 (x*32+横ずらし, y*32+5)。下に描くものと上に描くものがある。

## 作業中の状態コード(Philly の DrawCharaGraEffectOver)。
## get/put/use/unequip/read/write/看板タイトル/detect/create/destroy/
## analyze/forget/charge spell/ガス化。
const WORK_STATUSES := [0x30, 0x31, 0x32, 0x34, 0x41, 0x42, 0x46, 0x61, 0x62, 0x63, 0x65, 0x67, 0x68, 0x75, 0x76, 0x92]


static func under_icon(status: int) -> Variant:
	## キャラの下に描くアイコン。無ければ null。
	## 0x20=詠唱準備、0x21=詠唱中、0x22=詠唱完了。
	match status:
		0x20:
			return [8, 0, 5]
		0x21, 0x22:
			return [13, 0, 5]
	return null


static func over_icon(status: int, dir: String, anim_frame: int) -> Variant:
	## キャラの上に描くアイコン。無ければ null。
	## 0x01=攻撃(向きで絵と位置が変わる)、0x70=睡眠(2コマで交互)、
	## 作業中はどれも同じ絵。
	match status:
		0x01:
			match dir:
				"F":
					return [11, 0, 11]
				"B":
					return [9, 0, 1]
				"L":
					return [12, -3, 5]
				"R":
					return [10, 3, 5]
			return [11, 0, 11]
		0x70:
			return [14 + (anim_frame & 1), 0, -9]
	if status in WORK_STATUSES:
		return [16, 0, 0]
	return null
