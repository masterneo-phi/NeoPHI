class_name PhiMouse
extends RefCounted
## 地図上のマウス位置 → 方向カーソルと移動コマンド。
## Philly MapForm.cpp の FormMouseMove と classMoveCommand の対応。
##
## 位置は、描いている地図の範囲の左上を原点とした座標で渡す。
## カーソル名はスキンの `Cursor/<名前>.cur` に対応する。"" は既定カーソル。

const CURSOR_UP := "MouseUp"
const CURSOR_DOWN := "MouseDown"
const CURSOR_LEFT := "MouseLeft"
const CURSOR_RIGHT := "MouseRight"
const CURSOR_UP_LEFT := "MouseUpLeft"
const CURSOR_UP_RIGHT := "MouseUpRight"
const CURSOR_DOWN_LEFT := "MouseDownLeft"
const CURSOR_DOWN_RIGHT := "MouseDownRight"
const CURSOR_TURN_LEFT := "MouseTurnLeft"
const CURSOR_TURN_RIGHT := "MouseTurnRight"
## 方向カーソルの名前の一覧。グラキャッシュ初期化の温めに使う。
const ALL_CURSORS: Array[String] = [
	CURSOR_UP, CURSOR_DOWN, CURSOR_LEFT, CURSOR_RIGHT,
	CURSOR_UP_LEFT, CURSOR_UP_RIGHT, CURSOR_DOWN_LEFT, CURSOR_DOWN_RIGHT,
	CURSOR_TURN_LEFT, CURSOR_TURN_RIGHT,
]

## 回転マップで上部の角を回転ゾーンにする幅。Philly は 50px 固定(1倍時)。
const CORNER_PX := 50.0
## 北固定＋Shift/Ctrl で向く時に無視する中心からの距離。Philly は 20px。
const TURN_DEAD_PX := 20.0


static func cursor_for(local_pos: Vector2, map_size_px: Vector2, north_fix: bool, shift_or_ctrl: bool, zoom: float) -> String:
	## 地図上の位置からカーソル名を決める。
	if local_pos.x < 0.0 or local_pos.y < 0.0 or local_pos.x > map_size_px.x or local_pos.y > map_size_px.y:
		return ""
	var cx := local_pos.x - map_size_px.x * 0.5
	var cy := local_pos.y - map_size_px.y * 0.5
	if cx == 0.0 and cy == 0.0:
		return ""
	if not north_fix and shift_or_ctrl:
		# 回転マップで Shift/Ctrl を押していると、左右半分が回転。
		return CURSOR_TURN_LEFT if local_pos.x < map_size_px.x * 0.5 else CURSOR_TURN_RIGHT
	var theta := atan2(cy, cx)
	var eighth := PI / 8.0
	var cursor: String
	if theta < -7.0 * eighth:
		cursor = CURSOR_LEFT
	elif theta < -5.0 * eighth:
		cursor = CURSOR_UP_LEFT
	elif theta < -3.0 * eighth:
		cursor = CURSOR_UP
	elif theta < -1.0 * eighth:
		cursor = CURSOR_UP_RIGHT
	elif theta < 1.0 * eighth:
		cursor = CURSOR_RIGHT
	elif theta < 3.0 * eighth:
		cursor = CURSOR_DOWN_RIGHT
	elif theta < 5.0 * eighth:
		cursor = CURSOR_DOWN
	elif theta < 7.0 * eighth:
		cursor = CURSOR_DOWN_LEFT
	else:
		cursor = CURSOR_LEFT
	if not north_fix:
		# 回転マップの上部の角は回転カーソル。
		var corner := CORNER_PX * zoom
		if local_pos.y < corner and local_pos.x < corner:
			cursor = CURSOR_TURN_LEFT
		elif local_pos.y < corner and local_pos.x > map_size_px.x - corner:
			cursor = CURSOR_TURN_RIGHT
	return cursor


static func move_keys(cursor_name: String) -> Array[String]:
	## カーソル → 移動キーの列。斜めは縦と横の2つ。
	match cursor_name:
		CURSOR_UP:
			return ["8"]
		CURSOR_DOWN:
			return ["2"]
		CURSOR_LEFT:
			return ["4"]
		CURSOR_RIGHT:
			return ["6"]
		CURSOR_UP_LEFT:
			return ["8", "4"]
		CURSOR_UP_RIGHT:
			return ["8", "6"]
		CURSOR_DOWN_LEFT:
			return ["2", "4"]
		CURSOR_DOWN_RIGHT:
			return ["2", "6"]
		CURSOR_TURN_LEFT:
			return ["7"]
		CURSOR_TURN_RIGHT:
			return ["9"]
	return []


static func move_commands(cursor_name: String, north_fix: bool, mods: String) -> Array[String]:
	## カーソル → 送る行の列。斜めは縦→横の順に2行。
	var out: Array[String] = []
	for key in move_keys(cursor_name):
		out.append(PhiKeys.move_command(key, mods, north_fix))
	return out


static func turn_command(local_pos: Vector2, map_size_px: Vector2, zoom: float) -> String:
	## 北固定で Shift/Ctrl を押したホバーで向く方向の turn 行。
	## 中心の近くは ""(何もしない)。
	var cx := local_pos.x - map_size_px.x * 0.5
	var cy := local_pos.y - map_size_px.y * 0.5
	var dead := TURN_DEAD_PX * zoom
	if absf(cx) <= dead and absf(cy) <= dead:
		return ""
	var theta := atan2(cy, cx)
	var quarter := PI / 4.0
	if theta < -3.0 * quarter:
		return "turn w"
	if theta < -1.0 * quarter:
		return "turn n"
	if theta < 1.0 * quarter:
		return "turn e"
	if theta < 3.0 * quarter:
		return "turn s"
	return "turn w"
