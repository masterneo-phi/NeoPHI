class_name MapView
extends Control
## 地図を BMP の絵で描く Control。Python 版 map_graphics.py の移植。
##
## 描く順序は行ごと: ベースチップ → 水縁 → 看板 → アイテム → キャラ。
## 1マス 32px、チップシートの1セルは 32x48px、マップ上部に 16px の余白。
## `zoom` 倍で拡大して描く(ニアレストネイバー)。

## チップ画面セルサイズ(px)。
const CHIP_SIZE := 32
## チップシート1セルの高さ(px)。上16px透過。
const CHIP_HEIGHT := 48
## マップの上の余白(px)。一番上の行のチップのはみ出しの分。
const MAP_TOP := CHIP_HEIGHT - CHIP_SIZE
## チップ総数。
const CHIP_COUNT := 32
## チップシート1行あたりの列数。
const CHIPS_PER_ROW := 16

## 看板overlay用チップ。
const BOARD_CHIP_SOFT := 18
const BOARD_CHIP_HARD := 20
const _HARD_BOARD_CHIPS := [0x40, 0x23, 0x48, 0x3D, 0x5B, 0x7B, 0x7C, 0x25] # @#H=[{|%

## アイテムスプライト1枚サイズ(px)。
const ITEM_SPRITE_SIZE := 32
## 防御円チップbyte('x'=14, '%'=15)。
const _CIRCLE_CHIPS := [0x78, 0x25] # x %
## アイテムを床の上端から上げる量(px)。
const ITEM_Y_ABOVE_FLOOR := 8
## キャラを床の上端から上げる量(px)。
const CHARA_Y_ABOVE_FLOOR := 11
## アイテムクリップ高(円内に収める可視高 = 32-11)。
const ITEM_CLIP_H := ITEM_SPRITE_SIZE - 11

## キャラ通常フレーム幅(px)。
const CHARA_W_NORMAL := 16
## キャラ巨大フレーム幅(px)。
const CHARA_W_GIANT := 32
## キャラ1フレーム高(px)。
const CHARA_H := 32

const _DIR_TO_ROW := {"B": 0, "R": 1, "F": 2, "L": 3}
## dir(文字) → 向いている隣接マスへのオフセット。B=北, R=東, F=南, L=西。
const _DIR_FACING_OFFSET := {"B": Vector2i(0, -1), "R": Vector2i(1, 0), "F": Vector2i(0, 1), "L": Vector2i(-1, 0)}
const _DIR_NUM_TO_CHAR := {0: "B", 1: "B", 2: "R", 3: "F", 4: "F", 5: "F", 6: "L", 7: "B"}

## 水縁チップのベースindex。
const WATER_CHIP_BASE := 23
## 水チップのbyte('_')。
const WATER_BYTE := 0x5F

## チップの文字 → チップの絵の番号(wphi の CHIP_BYTE_TO_INDEX と同じ)。
const CHIP_BYTE_TO_INDEX := {
	0x20: [0], # space
	0x3A: [1], # :
	0x2B: [2], # +
	0x54: [1, 3], # T
	0x5F: [4], # _
	0x6F: [5], # o
	0x40: [6], # @
	0x23: [7], # #
	0x48: [8], # H
	0x49: [9], # I
	0x3D: [10], # =
	0x5B: [11], # [
	0x7B: [12], # {
	0x7C: [13], # |
	0x78: [14], # x
	0x25: [15], # %
	0x2F: [16], # /
	0x3E: [17], # >
	0x3F: [31], # ?
	0x73: [0], # s
}

## 絵が無い時にマスを塗る色(チップindexごと)。
const FALLBACK_CHIP_COLORS := {
	0: Color(0.157, 0.157, 0.157),
	1: Color(0.337, 0.478, 0.227),
	2: Color(0.431, 0.549, 0.275),
	3: Color(0.204, 0.361, 0.157),
	4: Color(0.188, 0.376, 0.627),
	5: Color(0.471, 0.376, 0.251),
	6: Color(0.588, 0.588, 0.588),
	7: Color(0.376, 0.376, 0.376),
	8: Color(0.549, 0.314, 0.235),
	9: Color(0.627, 0.549, 0.353),
	10: Color(0.706, 0.627, 0.471),
	11: Color(0.353, 0.431, 0.510),
	12: Color(0.510, 0.353, 0.431),
	13: Color(0.667, 0.667, 0.667),
	14: Color(0.275, 0.510, 0.510),
	15: Color(0.510, 0.275, 0.510),
	16: Color(0.745, 0.706, 0.549),
	17: Color(0.588, 0.431, 0.275),
	31: Color(0.078, 0.078, 0.078),
}
const FALLBACK_CHIP_DEFAULT := Color(0.251, 0.251, 0.251)

## マップの高さ (起伏) の自動生成。パーサがセルに付けた段数
## (-1〜+3) から、既存チップ無改変で色調・縁の影・段面の帯を
## 合成する。パラメータは検証済みサンプル (gfx_lab の
## render_auto_relief.py / render_auto_relief_move2.py) と一致させる。
## 1段の高さ (px)。
const RELIEF_STEP := 8
## 段ごとの上面の色調倍率 (サンプルの TONE。+3 は +2 からの延長)。
const RELIEF_TONES := {-1: 0.80, 1: 1.07, 2: 1.15, 3: 1.22}
## 段面の帯の土色 (サンプルの EARTH)。
const RELIEF_EARTH_R := 98.0
const RELIEF_EARTH_G := 74.0
const RELIEF_EARTH_B := 48.0
## 段差を登るときのホップの浮き (px)。段差1段あたりのピーク量と
## その上限 (複数段を一度に登っても浮きすぎない)。
const RELIEF_HOP_PX_PER_STEP := 5.0
const RELIEF_HOP_MAX_PX := 10.0
## 段差を降りるときの落下曲線の指数。前半は高さを保ち気味に、
## 後半で速く落ちる (q = p^RELIEF_DROP_EXP)。
const RELIEF_DROP_EXP := 2.0
## キャラの足元 (スプライト下端) の、セル上端からのずれ (px)。
## 基準 y = row*32 + 5、スプライト高 32 なので下端は +37。
const CHARA_FOOT := 37

## 浮き数字の色(種類ごと)。Python 版 gui.py の _FLOAT_COLORS と同じ。
const FLOAT_COLORS := {
	"dealt": Color(1.0, 0.824, 0.247),
	"taken": Color(1.0, 0.322, 0.322),
	"heal": Color(0.412, 0.941, 0.682),
	"mp": Color(0.310, 0.765, 0.969),
	"mpdmg": Color(0.310, 0.765, 0.969),
}
## 浮き数字が上がり切るまでの時間(秒)。30コマ × 30ms。
const FLOAT_DURATION := 0.9
## 点滅の1コマの時間(秒)。60ms × 6コマ。
const FLASH_STEP := 0.06
const FLASH_STEPS := 6
## 地図の揺れのパターン。50ms × 6コマ、最後は元に戻ります。
const SHAKE_PATTERN := [Vector2(3, 0), Vector2(-3, 1), Vector2(2, -2), Vector2(-2, 0), Vector2(1, 1), Vector2(0, 0)]
const SHAKE_STEP := 0.05
## 剣の軌跡(対象のみ)のコマ数と間隔、色。
const SLASH_FRAMES := 5
const SLASH_FRAME := 0.036
const SLASH_COLORS := [Color.WHITE, Color.WHITE, Color(0.890, 0.949, 0.992), Color(0.733, 0.871, 0.984), Color(0.565, 0.792, 0.976)]
## 斬撃の軌跡のコマ数と間隔、振り始めの向きと振る角度、色。
const SWING_FRAMES := 6
const SWING_FRAME := 0.03
const SWING_COLORS := [Color.WHITE, Color(0.890, 0.949, 0.992), Color(0.733, 0.871, 0.984), Color(0.565, 0.792, 0.976), Color(0.392, 0.710, 0.965), Color(0.259, 0.647, 0.961)]
const SWING_START := -1.9
const SWING_SWEEP := 2.6
## 風切りの線(円の半径、後れ、太さ)。白い主線の後を、青い線が追います。
const SWING_STREAKS := [[21.0, 0.0, 3.0], [16.0, 0.3, 2.0], [25.0, 0.55, 1.5]]
## 倒れたキャラの消滅: 段階の数と間隔(壁時計ベース)。
const GHOST_STEPS := 8
const GHOST_STEP := 0.08
## `#ex-disp-magic` の1段階の長さ(秒)。Philly は 20ms だが、
## 見えるように少し長くする。3段階で 0.24 秒。
const DISP_MAGIC_PHASE := 0.08
const DISP_MAGIC_PHASES := 3
## サーバー駆動の魔法表示が出たマスで、自前の発動演出を抑える時間。
const DISP_MAGIC_SUPPRESS_WINDOW := 1.0
## 魔法の色 (MP ダメージの点滅など)。
const MAGIC_COLOR := Color(0.310, 0.765, 0.969)
## 魔法弾の歩数と間隔、尾の長さと太さ、回る火花の軌道。
## 魔法弾は「魔法表示」が ON の時だけ飛ぶ (ユーザーの指定)。
## OFF の時は発動の円状オーラだけになる。
const BOLT_STEPS := 10
const BOLT_STEP := 0.028
const BOLT_COLOR := Color(0.310, 0.765, 0.969)
const BOLT_TAIL_LEN := 42.0
const BOLT_TAIL_WIDTH := 7.0
const BOLT_ORBIT_R := 7.0
const BOLT_ORBIT_STEP := 1.1
## 着弾: コマ数と間隔、火花の数、色。
const IMPACT_FRAMES := 6
const IMPACT_FRAME := 0.03
const IMPACT_COLORS := [Color.WHITE, Color(0.882, 0.961, 0.996), Color(0.702, 0.898, 0.988), Color(0.506, 0.831, 0.980), Color(0.310, 0.765, 0.969), Color(0.161, 0.714, 0.965)]
const IMPACT_SPARKS := 8
## 発動: 術師を中心に円状に広がる波の演出。魔法陣 (サーバー駆動
## 表示の発動タイル) は、どちらの設定でもこのオーラに差し替える
## (ユーザーの指定)。持続は1秒弱。中心の閃光 + 遅れて広がる
## リング3重 + 円周の火花。
const CAST_DURATION := 0.9
const CAST_RING_COUNT := 3
const CAST_RING_DELAY := 0.16
const CAST_RING_MAX_R := 34.0
const CAST_COLORS := [Color.WHITE, Color(0.882, 0.961, 0.996), Color(0.702, 0.898, 0.988), Color(0.506, 0.831, 0.980), Color(0.310, 0.765, 0.969), Color(0.161, 0.714, 0.965)]
const CAST_SPARKS := 10
## 吹き出し: 本文の幅(地図の絵の座標)、行数、表示時間。
const BUBBLE_MAX_WIDTH := 132.0
const BUBBLE_MAX_LINES := 3
const BUBBLE_BASE_MS := 2500.0
const BUBBLE_PER_CHAR_MS := 60.0
const BUBBLE_MAX_MS := 8000.0
## 吹き出しは話者ごとに複数保持し、新しい文が来たら古い文を
## 上にずらして残す (速く喋る NPC の台詞が読み飛ばされない
## ように)。保持する最大数。
const BUBBLE_STACK_MAX := 4

## 水縁 quarter 描画テーブル。添字 = quarter(0=TL,1=TR,2=BL,3=BR)。
## 各 quarter で 3bit パターン → [chip_offset, src_quarter]。
const Q_TABLE := [
	{0x00: [1, 0], 0x01: [1, 0], 0x02: [0, 0], 0x03: [0, 0], 0x04: [0, 2], 0x05: [0, 2], 0x06: [2, 3]},
	{0x00: [1, 1], 0x01: [1, 1], 0x02: [0, 1], 0x03: [0, 1], 0x04: [0, 2], 0x05: [0, 2], 0x06: [2, 2]},
	{0x00: [1, 2], 0x01: [1, 2], 0x02: [0, 0], 0x03: [0, 0], 0x04: [0, 3], 0x05: [0, 3], 0x06: [2, 1]},
	{0x00: [1, 3], 0x01: [1, 3], 0x02: [0, 1], 0x03: [0, 1], 0x04: [0, 3], 0x05: [0, 3], 0x06: [2, 0]},
]

## 地図の倍率が変わったことを知らせます。UIの文字サイズの連動に使います。
signal zoom_changed(new_zoom: int)

var zoom := 4
## 倍率の決め方 (設定の [Map] ZoomMode)。0 = 窓に合わせる
## (収まる整数倍率に自動調整)、1 = 固定倍率 (zoom_fixed に固定し、
## 窓が小さくても縮小しない・大きくても拡大しない)。
var zoom_mode := 0
## 固定倍率モードの倍率 (1〜8)。
var zoom_fixed := 3
## 地図の横配置 (第101段)。0=中央、1=左寄せ、2=右寄せ。
## 縦は常時中央。描画と当たり判定で同じ係数を使う。
var map_align := 0
var assets: GameAssets = null
var label_font: Font = null
## 太字フォント(コンパスの様式表示など、目立たせたい文字用)。
var bold_font: Font = null
var mapset := ""
## 自分のキャラの名前。浮き数字の位置決めと詠唱の取り消しに使います。
var player_name := ""
## 拡大の要求フラグ。窓のリサイズと境目のドラッグと地図の大きさの
## 変化(外部からのサイズ変更)でのみ立て、`_update_zoom` が1段階の
## 拡大に使う。レイアウトのフィードバック(文字サイズの変化)では立て
## ないので、拡大→行が伸びる→縮小→行が縮む→拡大、の無限反転は
## 起きない。
var _grow_requested := false
## 拡大の追いかけの期限 (秒)。要求を受けたら、この期限まで
## `_process` がフレームごとに要求を出し直す。タブ切り替え直後の
## 一時的なレイアウトの揺れで要求が消費されたり倍率が落ちても、
## 余地が戻れば続きから追いつく。
var _grow_drive_until := 0.0
## 前に受けた地図の一辺のマス数。地図の大きさの変化を検知する。
var _last_dim := 0


## 外部からのサイズ変更があったことを知らせる。次の `_update_zoom` で、
## 収まるなら1段階だけ拡大する。テストからも呼べる。
func request_zoom_growth() -> void:
	_grow_requested = true
	_grow_drive_until = _now() + 1.0

var _event: Dictionary = {}
## キャラの歩行アニメーションのフレーム (0/1、500ms 切替)。
var _anim_frame := 0
## 接続中かどうか。切断中は歩行アニメーションを止める
## (動いているように見えて、切断に気付かないため。第63段)。
var _session_live := true
## 第64段 (試作): 滑らかなスクロール。前の地図を覚えておき、
## 新しい地図が 1 マス分だけずれている時は、地図全体を
## ドット単位でずらしながら描いて滑らかに見せる。
var smooth_scroll := true
## 魔法弾を飛ばすか (「魔法表示」の設定に連動。PhiCharacter が
## config.disp_magic を反映する)。OFF なら発動オーラだけ。
var magic_bolt := false
## 現在の地図様式 ("solid" = 北固定 / "turn" = 回転)。滑らか
## スクロールは北固定の時だけ効く (第65段、ユーザーの指定)。
var map_style := "solid"


func set_map_style(p_style: String) -> void:
	map_style = p_style
var _prev_cells: Array = []
## 自キャラの表示名 (PhiCharacter が渡す)。地図行の中から
## 自分の行を見分けるのに使う。
var self_name := ""
## 直前に送った移動コマンドの方向 (第119段)。実サーバは
## #ex-pos を送らないので、絶対座標が無い時は自分が出した
## 移動コマンドでずれ方向を決める。(999,999) は「なし」、
## Vector2i.ZERO は「回転など、移動しないフレームが来る」印。
var _pending_move := Vector2i(999, 999)
var _pending_move_at := -100000
var _scroll_from := Vector2.ZERO  # ずれ (セル単位 = プレイヤーの移動方向)
var _scroll_t := 1.0  # 0→1 で進む。1 で完了。
## スクロール前後の中心セルの段数。自キャラの高さずれを
## スクロールの進みに合わせて補間するために覚える。
var _scroll_from_h := 0
var _scroll_to_h := 0
const SCROLL_DURATION := 0.17
## 補間時間の下限 (第128段)。到着間隔がこれより短い時は
## ここで止める (60fps の1フレーム約16.7ms の2倍弱。
## これ未満は補間というより即時切替で、間隔のばらつきが
## そのまま表示の震えになる)。
const MIN_SCROLL_DURATION := 0.03
## 現在のスクロールに使う補間時間。到着間隔で適応する
## (第128段)。初期値は従来どおり。
var _scroll_duration := SCROLL_DURATION
## 直近のスクロール開始時刻 (秒、_now() 基準)。-1 はまだ無い。
var _last_scroll_start := -1.0


static func scroll_duration_for_interval(interval_sec: float) -> float:
	## 地図の到着間隔から補間時間を決める (第128段)。
	## 間隔が不明 (0以下) か遅い時は従来の SCROLL_DURATION、
	## 速い時は間隔に合わせて縮める (下限 MIN_SCROLL_DURATION)。
	## 間隔ちょうどにすれば、次の地図が届く頃に補間が
	## 終わるので、速く歩いても表示が遅れ続けない。
	if interval_sec <= 0.0:
		return SCROLL_DURATION
	return clampf(minf(SCROLL_DURATION, interval_sec), MIN_SCROLL_DURATION, SCROLL_DURATION)


func set_session_live(v: bool) -> void:
	## 接続状態を伝える。切断されたらアニメーションを止め、
	## その場のフレームで固定して描き直す。
	if _session_live == v:
		return
	_session_live = v
	queue_redraw()


func note_move(dir: Vector2i) -> void:
	## 移動コマンドを送った時に PhiCharacter から呼ばれる。
	## dir はプレイヤーの実移動 (画面の北 = (0,-1))。回転など
	## 位置の変わらないコマンドでは Vector2i.ZERO を渡す。
	_pending_move = dir
	_pending_move_at = Time.get_ticks_msec()


func _detect_scroll(new_event: Dictionary) -> void:
	## 新しい地図が前の地図から 1 マス分だけずれているか調べ、
	## ずらして描く準備をする (第64段)。ずれの向きは
	## プレイヤーの移動方向 (北へ動くと新しい地図の (x,y) は
	## 前の地図の (x, y-1) と同じ中身になる)。チップが最大
	## 2 マス分食い違ってもよい (同時に起きた小さな変化)。
	_scroll_t = 1.0
	_prev_cells = []
	if not smooth_scroll or map_style != "solid" or _event.is_empty():
		return
	var dim := grid_dim(int(_event.get("size", 7)))
	if dim != grid_dim(int(new_event.get("size", 7))):
		return
	var old_cells: Array = _event.get("cells", [])
	var new_cells: Array = new_event.get("cells", [])
	if old_cells.size() != dim * dim or new_cells.size() != dim * dim:
		return
	# サーバが絶対座標を付けている時は、ずれはプレイヤーの
	# 実移動で決まる。一面同じ地形だとチップ比較だけでは
	# 向きが決まらず、横移動でも上下に揺れて見えていた
	# (第118段)。動いていない・大きく跳んだ時は滑らか
	# スクロールの対象にしない。
	var candidates: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	# ずれ方向が移動コマンドの印か絶対座標で決まったかどうか。
	# 決まっていない時のチップ比較は、地形が変わっていない
	# フレームを誤って拾わないよう下で別に扱う (第123段)。
	var decided := false
	# 自分が出した移動コマンドが新しい時は、それをずれ方向の
	# 候補にする (第119段)。一面同じ地形や霧の中ではチップ
	# 比較だけでは向きが決まらず、横移動で上下に揺れていた。
	if _pending_move != Vector2i(999, 999) \
			and Time.get_ticks_msec() - _pending_move_at <= 2000:
		var pm := _pending_move
		_pending_move = Vector2i(999, 999)
		if pm == Vector2i.ZERO:
			return  # 回転など: 位置は変わらないので滑らせない
		candidates = [pm]
		decided = true
	if _event.has("pos") and new_event.has("pos"):
		var op: Dictionary = _event["pos"]
		var np: Dictionary = new_event["pos"]
		var d := Vector2i(int(np.get("x", 0)) - int(op.get("x", 0)), int(np.get("y", 0)) - int(op.get("y", 0)))
		if d == Vector2i.ZERO or absi(d.x) + absi(d.y) != 1:
			return
		candidates = [d]
		decided = true
	if not decided:
		# 向き変更や他人の移動では地形は1マスも変わらない。
		# そのフレームをずらし比較に掛けると (0,-1) に必ず
		# 一致してしまい、向きを変えるたびに地図全体が滑って
		# 揺れていた (第123段、実機報告)。地形が完全に同じ
		# なら、滑らせる移動は無かったということにする。
		var same := true
		for i in range(dim * dim):
			if int(new_cells[i].get("chip", 0)) != int(old_cells[i].get("chip", 0)):
				same = false
				break
		if same:
			return
	for sv in candidates:
		var s: Vector2i = sv
		var bad := 0
		for y in range(dim):
			for x in range(dim):
				var ox := x + s.x
				var oy := y + s.y
				if ox < 0 or oy < 0 or ox >= dim or oy >= dim:
					continue
				var nc: Dictionary = new_cells[y * dim + x]
				var oc: Dictionary = old_cells[oy * dim + ox]
				if int(nc.get("chip", 0)) != int(oc.get("chip", 0)):
					bad += 1
					if bad > 2:
						break
			if bad > 2:
				break
		if bad <= 2:
			_prev_cells = old_cells
			_scroll_from = Vector2(s)
			_scroll_t = 0.0
			_note_scroll_start()
			return


func _note_scroll_start(now_s: float = -1.0) -> void:
	## スクロールが始まったことを記録し、補間時間を直前の
	## 到着間隔に追従させる (第128段)。間隔が空いたら従来の
	## SCROLL_DURATION に戻る。now_s はテスト用 (負なら実時刻)。
	var t := now_s if now_s >= 0.0 else _now()
	if _last_scroll_start >= 0.0:
		_scroll_duration = scroll_duration_for_interval(t - _last_scroll_start)
	else:
		_scroll_duration = SCROLL_DURATION
	_last_scroll_start = t
## チップシートは属性の下位2ビット (#mapset-define の番号) ごとに
## 4枚。slot 0 は現在のマップセット、1〜3 は define があればその
## 名前、無ければ既定シート (Python 版と同じ解決)。
var _chip_texs: Array = [null, null, null, null]
var _defines: Dictionary = {}
## 起伏の自動生成のキャッシュ。シートを取り直すたびに捨てる。
## _sheet_images: シートの instance id → Image (RGBA8)。
## _toned_cache: [sheet_id, index, 段数] → 32x48 のバイト列。
## _relief_cache: セルの合成キー → Texture2D。
var _sheet_images: Dictionary = {}
var _toned_cache: Dictionary = {}
var _toned_tex_cache: Dictionary = {}
var _relief_cache: Dictionary = {}
var _items_tex: Texture2D = null

## 浮き数字などの基準点。名前 → 地図の絵の中の座標(中心x、頭の上y)。
var _anchors: Dictionary = {}
var _center_anchor: Variant = null
## 自キャラが向いているマスの基準点 (頭の上)。人形オブジェの
## 台詞の吹き出しを付ける先で、地図が差し替わるたびに作り直す。
var _faced_anchor: Variant = null
## 台詞行やオブジェの発言で覚えた話し手 → 基準点。地図に居ない
## 話し手 (人形オブジェ) の吹き出し用で、地図の差し替えで消す。
var _dialogue_anchors: Dictionary = {}
var _last_charas: Dictionary = {}
var _prev_charas: Dictionary = {}
var _caster_tracker: PhiCombatFx.CasterTracker = null
var _float_seq := 0
var _floats: Array = []
var _flashes: Array = []
var _swings: Array = []
var _slashes: Array = []
var _bolts: Array = []
var _impacts: Array = []
var _casts: Array = []
var _ghosts: Array = []
var _bubbles: Dictionary = {}
var _disp_magics: Array = []
var _recent_disp_hits: Array = []
var _shake_active := false
var _shake_started := 0.0

# -- DM 演出拡張 (FX) の状態。地図フレームの差し替えでは消えない
# よう、_event ではなく MapView 自身が持つ (ワイプ帰還の演出のため)。
var _fx_icons_tex: Texture2D = null
var _fx_texts := {}
var _fx_dark := {}
var _fx_wipe := {}
var _fx_glow := {}
var _fx_img := {}
var _fx_shake_until := 0.0
var _fx_shake_amp := 0.0
var _glow_tex: Texture2D = null

## 地図がまだ届いていない間に地図欄へ出すタイトルロゴ。
const LOGO_PATH := "res://assets/logo.png"
const TITLE_BG := Color(0.06, 0.05, 0.05)
var _title_rect: TextureRect = null

## 地図の周りの余白に出すモノグラム壁紙。タイル状に並べる。
## 絵はタイルの大きさ(512x384)と一致させてあるので、NEAREST の
## まま1:1で描けて補間が要らない。ファイルが無ければ黒い余白。
const WALLPAPER_PATH := "res://assets/wallpaper.png"
const WALLPAPER_TILE := Vector2(512.0, 384.0)
const WALLPAPER_MODULATE := Color(0.8, 0.8, 0.8)
## 壁紙の下地。タイルの暗部の色に合わせた濃紺。
const WALLPAPER_BG := Color(0.075, 0.13, 0.22)
var _wallpaper: Texture2D = null

## 地図の右下に浮かせるコンパスの透け具合と、端からの余白。
## 下の地図が見えて、針の向きも読み取れる程度。
## 大きさはマップチップ1マス分(32px×ズーム)に追従させる。
const COMPASS_ALPHA := 0.6
const COMPASS_MARGIN := 8.0
var compass: CompassView = null
## コンパス下部の様式表示(回転/北固定)の帯とラベル。コンパス本体は
## 半透明(modulate)なので、中に文字を描くと薄れて読みにくい。
## 別コントロールでかぶせれば薄れず、太字+黒の縁取りで読める
## (ユーザーの指定 2026-11-16)。
var _compass_mode_plate: Panel = null
var _compass_mode_label: Label = null


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_caster_tracker = PhiCombatFx.CasterTracker.new()
	_title_rect = TextureRect.new()
	_title_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_title_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_rect.texture = title_texture()
	add_child(_title_rect)
	_wallpaper = wallpaper_texture()
	# コンパスは地図の右下に半透明で浮かせる。マウスは通す
	# (CompassView 側で MOUSE_FILTER_IGNORE)。地図が届くまで隠す。
	compass = CompassView.new()
	compass.modulate = Color(1.0, 1.0, 1.0, COMPASS_ALPHA)
	compass.visible = false
	add_child(compass)
	# 様式表示の帯とラベルはコンパスの上にかぶせる(本体の半透明に
	# 引きずられないよう、別コントロールにする)。
	_compass_mode_plate = Panel.new()
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.0, 0.0, 0.0, 0.68)
	plate_style.set_corner_radius_all(4)
	_compass_mode_plate.add_theme_stylebox_override("panel", plate_style)
	_compass_mode_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_mode_plate.visible = false
	add_child(_compass_mode_plate)
	_compass_mode_label = Label.new()
	_compass_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_compass_mode_label.add_theme_color_override("font_color", Color.WHITE)
	_compass_mode_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_compass_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_mode_label.visible = false
	add_child(_compass_mode_label)
	compass.visibility_changed.connect(_sync_compass_mode_overlay)
	_layout_compass(_compass_px())


func _sync_compass_mode_overlay() -> void:
	## 帯とラベルの表示をコンパス本体に連動させる(スクリーン
	## ショット撮影時の隠蔽など、本体の visible 切替に追従する)。
	var vis := compass != null and compass.visible
	if _compass_mode_plate != null:
		_compass_mode_plate.visible = vis
	if _compass_mode_label != null:
		_compass_mode_label.visible = vis


func _compass_px() -> float:
	## コンパスの大きさ。マップチップ1マス分(32px×ズーム)。
	return float(CHIP_SIZE * zoom)


func _layout_compass(px: float) -> void:
	## コンパスを地図の右下に置く。アンカーを右下に固定し、
	## 大きさと余白ぶんだけ内側へずらす。最小サイズも同じ値に
	## しないと、最小サイズに引っ張られて隅からはみ出す。
	compass.custom_minimum_size = Vector2(px, px)
	compass.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	compass.offset_left = -(px + COMPASS_MARGIN)
	compass.offset_top = -(px + COMPASS_MARGIN)
	compass.offset_right = -COMPASS_MARGIN
	compass.offset_bottom = -COMPASS_MARGIN
	# 様式表示の帯とラベルもコンパスの下端に合わせる。
	if _compass_mode_plate != null and compass != null:
		var font_size := int(clampf(px * 0.17, 8.0, 26.0))
		var plate_h := float(font_size) + 8.0
		for ctl in [_compass_mode_plate, _compass_mode_label]:
			ctl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			ctl.offset_left = -(px + COMPASS_MARGIN)
			ctl.offset_right = -COMPASS_MARGIN
			ctl.offset_bottom = -COMPASS_MARGIN
			ctl.offset_top = -(COMPASS_MARGIN + plate_h)
		var f: Font = bold_font if bold_font != null else label_font
		if f != null:
			_compass_mode_label.add_theme_font_override("font", f)
		_compass_mode_label.add_theme_font_size_override("font_size", font_size)
		_compass_mode_label.add_theme_constant_override("outline_size", maxi(2, font_size / 4))
		_compass_mode_label.text = compass.mode_text()


func _sync_compass_size() -> void:
	## コンパスの大きさを、今のズームのマップチップ1マス分に
	## 合わせ直す。ズームが変わった時に呼ぶ。
	if compass != null:
		_layout_compass(_compass_px())


func set_compass_texture(tex: Texture2D) -> void:
	if compass != null:
		compass.direction_tex = CompassView.rounded_direction_texture(tex)
		compass.queue_redraw()


func set_compass_direction(dir_num: int, p_north_fix: bool) -> void:
	if compass != null:
		compass.set_direction(dir_num, p_north_fix)


func set_compass_mode_style(p_style: String) -> void:
	## コンパス下部の様式表示(回転/北固定)を切り替える。
	if compass != null:
		compass.set_mode_style(p_style)
		# フォントの到着や文言の変化を帯ラベルへ反映する。
		_layout_compass(_compass_px())


## モノグラム壁紙の絵を返す。ファイルが無い場合は null。
func wallpaper_texture() -> Texture2D:
	if ResourceLoader.exists(WALLPAPER_PATH):
		return load(WALLPAPER_PATH) as Texture2D
	return null


## タイトルロゴの絵を返す。ファイルが無い(リポジトリの写しなど)場合は null。
func title_texture() -> Texture2D:
	if ResourceLoader.exists(LOGO_PATH):
		return load(LOGO_PATH) as Texture2D
	return null


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_zoom()
		if _event.is_empty():
			queue_redraw()


func _update_zoom() -> void:
	## 割り当てられた大きさに収まる整数倍率にする。ドット絵が
	## 崩れないよう整数倍に限る。レイアウト前(サイズ0)は今の倍率を保つ。
	## 拡大は、外部からのサイズ変更で要求があった時だけ1段階ずつ。
	## 縮小は収まらなくなったら即座に。要求が無いときは拡大しないので、
	## 文字サイズの連動によるレイアウトのフィードバックでは発振しない。
	var dim := grid_dim(int(_event.get("size", 7)))
	var avail := size
	if avail.x < 1.0 or avail.y < 1.0:
		return
	if zoom_mode == 1:
		# 固定倍率: 窓の大きさに合わせず、指定の整数倍に固定する。
		# 大きな窓に小さな地図 (中央に寄る)、小さな窓に大きな地図
		# (はみ出す) のどちらでもこの倍率のまま描く。
		var fixed := clampi(zoom_fixed, 1, 8)
		if zoom != fixed:
			zoom = fixed
			zoom_changed.emit(zoom)
			_sync_compass_size()
			queue_redraw()
		return
	var zw := int(avail.x / (dim * CHIP_SIZE))
	var zh := int(avail.y / (dim * CHIP_SIZE + MAP_TOP))
	var fit := clampi(mini(zw, zh), 1, 8)
	if fit > zoom:
		if _grow_requested:
			_grow_requested = false
			zoom = zoom + 1
			zoom_changed.emit(zoom)
			_sync_compass_size()
			queue_redraw()
	elif fit < zoom:
		# 縮小するとき、溜まっていた拡大要求は古いので捨てる。
		_grow_requested = false
		zoom = fit
		zoom_changed.emit(zoom)
		_sync_compass_size()
		queue_redraw()


func _mark_self(event: Dictionary, dim: int) -> void:
	## 地図行の中の自キャラに "__self" 印を付ける。滑らか
	## スクロール中に中央へ留めるのはこの行だけ (第120段)。
	## 同じマスに乗った家具などのオブジェ行 (種別 B) まで
	## 留めてしまい、家具が一瞬動いて見えていた。
	var chars: Array = event.get("chars", [])
	var pick: Dictionary = {}
	if not self_name.is_empty():
		for ch_var in chars:
			var ch: Dictionary = ch_var
			ch.erase("__self")
			if PhiTags.strip_tags(str(ch.get("name", ""))).strip_edges() == self_name:
				pick = ch
	if pick.is_empty():
		var cx := dim / 2
		var cy := dim / 2
		for ch_var in chars:
			var ch: Dictionary = ch_var
			ch.erase("__self")
			if int(ch.get("x", -1)) == cx and int(ch.get("y", -1)) == cy \
					and int(ch.get("layer", -1)) == 12:
				pick = ch
	if not pick.is_empty():
		pick["__self"] = true


func set_map(event: Dictionary, p_assets: GameAssets, p_mapset: String, defines: Dictionary = {}) -> void:
	_detect_scroll(event)
	_mark_self(event, grid_dim(int(event.get("size", 7))))
	# 中心セルの段数の遷移を覚える (自キャラの高さ補間用)。
	_scroll_from_h = _scroll_to_h
	var ndim := grid_dim(int(event.get("size", 7)))
	var ncells: Array = event.get("cells", [])
	if not ncells.is_empty():
		_scroll_to_h = height_at(ncells, ndim, ndim / 2, ndim / 2)
	_event = event
	_title_rect.visible = false
	if compass != null:
		compass.visible = true
	assets = p_assets
	mapset = p_mapset
	_anim_frame = int(_now() * 2.0) % 2
	_defines = defines.duplicate()
	_items_tex = null
	_fx_icons_tex = null
	_load_chip_texs()
	if assets != null:
		_items_tex = assets.items()
		_fx_icons_tex = assets.skin_image("fx_icons")
	var dim := grid_dim(int(event.get("size", 7)))
	custom_minimum_size = Vector2(dim * CHIP_SIZE, dim * CHIP_SIZE + MAP_TOP)
	if dim != _last_dim:
		_last_dim = dim
		# 地図の大きさの変化は配置の反動ではなく内容の変化なので、
		# 外部からのサイズ変更と同じく拡大を1段階だけ許します。
		request_zoom_growth()
	# フロート表示の基準点と、死亡の残像のもとになるキャラを覚えます。
	_prev_charas = _last_charas
	_last_charas = {}
	_anchors = {}
	_dialogue_anchors = {}
	_center_anchor = null
	_faced_anchor = null
	var head_top := (CHIP_SIZE - CHARA_H) / 2 - CHARA_Y_ABOVE_FLOOR + MAP_TOP
	var ev_cells: Array = event.get("cells", [])
	for ch in event.get("chars", []):
		var cd: Dictionary = ch
		var nm := PhiTags.strip_tags(str(cd.get("name", ""))).strip_edges()
		_last_charas[nm] = cd
		var cx := int(cd.get("x", -1))
		var cy := int(cd.get("y", -1))
		if not (0 <= cx and cx < dim and 0 <= cy and cy < dim):
			continue
		if nm.is_empty():
			continue
		var anchor := Vector2(cx * CHIP_SIZE + CHIP_SIZE / 2,
			cy * CHIP_SIZE + head_top + relief_offset_y(ev_cells, dim, cx, cy))
		_anchors[nm] = anchor
		if cx == dim / 2 and cy == dim / 2:
			_center_anchor = anchor
		if bool(cd.get("__self", false)):
			var off := facing_offset(cd.get("dir", "F"))
			var fx := cx + off.x
			var fy := cy + off.y
			if 0 <= fx and fx < dim and 0 <= fy and fy < dim:
				_faced_anchor = Vector2(fx * CHIP_SIZE + CHIP_SIZE / 2,
					fy * CHIP_SIZE + head_top + relief_offset_y(ev_cells, dim, fx, fy))
	_update_zoom()
	queue_redraw()


## スロットごとのチップシートを取り直す。slot 0 は現在の
## マップセット、1〜3 は _defines に名前があればそれ、無ければ
## 既定シート (assets.chip(""))。シートが無いスロットは null で、
## そのセルの描画は色塗りの代用に落ちる。
func _load_chip_texs() -> void:
	_chip_texs = [null, null, null, null]
	_sheet_images.clear()
	_toned_cache.clear()
	_toned_tex_cache.clear()
	_relief_cache.clear()
	if assets == null:
		return
	_chip_texs[0] = assets.chip(mapset)
	for slot in range(1, 4):
		_chip_texs[slot] = assets.chip(str(_defines.get(slot, "")))


## セルの属性下位2ビットが指すシート。無ければ null。
func _sheet_for(cell: Dictionary) -> Texture2D:
	return _chip_texs[int(cell.get("attr", 0)) & 0x03] as Texture2D


## どれか1枚でもシートが読めていれば true。
func _any_sheet() -> bool:
	for tex in _chip_texs:
		if tex != null:
			return true
	return false


# -- 起伏の自動生成 ---------------------------------------------------

func _sheet_image(sheet: Texture2D) -> Variant:
	## シートの画素 (RGBA8)。色調変換の素。無ければ null。
	var id := sheet.get_instance_id()
	if _sheet_images.has(id):
		return _sheet_images[id]
	var img := sheet.get_image()
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_sheet_images[id] = img
	return img


func _toned_chip_data(sheet: Texture2D, index: int, h: int) -> PackedByteArray:
	## シートのチップ index を段数 h で色調変換した 32x48 RGBA。
	## h = 0 は無変換 (サンプルの toned(0) と同じ)。
	var key := str(sheet.get_instance_id()) + ":" + str(index) + ":" + str(h)
	var cached: Variant = _toned_cache.get(key)
	if cached != null:
		return cached
	var out := PackedByteArray()
	out.resize(CHIP_SIZE * CHIP_HEIGHT * 4)
	var img: Variant = _sheet_image(sheet)
	if img != null:
		var rect := chip_src_rect(index)
		if rect.size.x > 0:
			var region: Image = (img as Image).get_region(rect)
			if region.get_format() != Image.FORMAT_RGBA8:
				region.convert(Image.FORMAT_RGBA8)
			var src := region.get_data()
			out = src
			if h != 0 and src.size() == out.size():
				out = src.duplicate()
				for i in range(0, out.size(), 4):
					if out[i + 3] == 0:
						continue
					var rgb := relief_tone_rgb(float(out[i]), float(out[i + 1]), float(out[i + 2]), h)
					out[i] = clampi(int(round(rgb[0])), 0, 255)
					out[i + 1] = clampi(int(round(rgb[1])), 0, 255)
					out[i + 2] = clampi(int(round(rgb[2])), 0, 255)
	_toned_cache[key] = out
	return out


func _toned_chip_texture(sheet: Texture2D, index: int, h: int) -> Texture2D:
	## 色調変換済みチップのテクスチャ (水縁・看板の流用)。
	var key := "t:" + str(sheet.get_instance_id()) + ":" + str(index) + ":" + str(h)
	var cached: Variant = _toned_tex_cache.get(key)
	if cached != null:
		return cached
	var img := Image.create_from_data(CHIP_SIZE, CHIP_HEIGHT, false,
		Image.FORMAT_RGBA8, _toned_chip_data(sheet, index, h))
	var tex := ImageTexture.create_from_image(img)
	_toned_tex_cache[key] = tex
	return tex


static func _alpha_over(dst: PackedByteArray, src: PackedByteArray) -> void:
	## src を dst の上にアルファ合成する (同サイズ前提)。
	for i in range(0, mini(dst.size(), src.size()), 4):
		var sa := int(src[i + 3])
		if sa == 0:
			continue
		if sa == 255:
			dst[i] = src[i]
			dst[i + 1] = src[i + 1]
			dst[i + 2] = src[i + 2]
			dst[i + 3] = 255
			continue
		var da := int(dst[i + 3])
		var inv := 255 - sa
		var oa := sa + (da * inv) / 255
		if oa == 0:
			dst[i + 3] = 0
			continue
		dst[i] = clampi((int(src[i]) * sa + (int(dst[i]) * da * inv) / 255) / oa, 0, 255)
		dst[i + 1] = clampi((int(src[i + 1]) * sa + (int(dst[i + 1]) * da * inv) / 255) / oa, 0, 255)
		dst[i + 2] = clampi((int(src[i + 2]) * sa + (int(dst[i + 2]) * da * inv) / 255) / oa, 0, 255)
		dst[i + 3] = oa


static func _px_mul(data: PackedByteArray, x: int, y: int, f: float) -> void:
	var i := (y * CHIP_SIZE + x) * 4
	if data[i + 3] == 0:
		return
	data[i] = clampi(int(round(float(data[i]) * f)), 0, 255)
	data[i + 1] = clampi(int(round(float(data[i + 1]) * f)), 0, 255)
	data[i + 2] = clampi(int(round(float(data[i + 2]) * f)), 0, 255)


static func relief_apply_overlays(data: PackedByteArray, base: PackedByteArray,
		north: PackedByteArray, heights: Array, spans: Array) -> void:
	## サンプルの cell_image と同じ順序で影・段面の帯を data に
	## 上書きする。heights = [自, 北, 南, 西, 東] の段数、base は
	## 色調変換だけの自セル (帯の土色の素)、north は北隣の色調
	## 変換済み (唇の素、無ければ空)、spans は列ごとの帯形状。
	var h: int = heights[0]
	var hn: int = heights[1]
	var hs: int = heights[2]
	var hw: int = heights[3]
	var he: int = heights[4]
	var face := hn > h
	# 窪みの底はさらに暗く
	if h == -1 and hn == -1 and hs == -1 and hw == -1 and he == -1:
		for y in range(CHIP_HEIGHT):
			for x in range(CHIP_SIZE):
				_px_mul(data, x, y, 0.93)
	# 側面の陰影 (段面セルでは端のテーパーに任せる)
	if not face:
		if hw < h or (h == -1 and hw > h):
			var f0w := 0.70 if h == -1 else 0.82
			for x in range(12):
				var fw := f0w + (1.0 - f0w) * (float(x) / 11.0)
				for y in range(CHIP_HEIGHT):
					_px_mul(data, x, y, fw)
		if he < h or (h == -1 and he > h):
			var f0e := 0.70 if h == -1 else 0.82
			for x in range(12):
				var fe := f0e + (1.0 - f0e) * (float(x) / 11.0)
				for y in range(CHIP_HEIGHT):
					_px_mul(data, CHIP_SIZE - 1 - x, y, fe)
	# 北縁の柔らかい影
	if hn < h:
		for i in range(11):
			var f := 0.66 + 0.34 * pow(float(i) / 10.0, 1.2)
			for x in range(CHIP_SIZE):
				_px_mul(data, x, 16 + i, f)
	# 窪みの南内縁の光
	if h == -1 and hs > h:
		var light := [1.04, 1.07, 1.10, 1.14, 1.17, 1.20]
		for i in range(light.size()):
			for x in range(CHIP_SIZE):
				_px_mul(data, x, 26 + i, light[i])
	# 段面の帯 (北が高い時、このセルの上部に出る)
	if face and not north.is_empty():
		var shadow_a := [52, 32, 16]
		for x in range(CHIP_SIZE):
			var span: Array = spans[x]
			if span.is_empty():
				continue
			var fb: int = span[0]
			var lip: int = span[1]
			for y in range(fb + 1):
				var di := (y * CHIP_SIZE + x) * 4
				var ni := ((32 + y) * CHIP_SIZE + x) * 4
				if y < lip:
					# 唇: 上段トーンの草
					data[di] = north[ni]
					data[di + 1] = north[ni + 1]
					data[di + 2] = north[ni + 2]
					data[di + 3] = north[ni + 3]
				elif y == lip:
					# 唇の下の影
					data[di] = clampi(int(round(float(north[ni]) * 0.5)), 0, 255)
					data[di + 1] = clampi(int(round(float(north[ni + 1]) * 0.5)), 0, 255)
					data[di + 2] = clampi(int(round(float(north[ni + 2]) * 0.5)), 0, 255)
					data[di + 3] = north[ni + 3]
				else:
					# 土に寄せた暗帯
					var t := float(y - lip - 1) / float(maxi(1, fb - lip - 1))
					var si := ((16 + (y - lip)) * CHIP_SIZE + x) * 4
					var f := 0.92 - 0.20 * t
					var n := relief_noise(x, y)
					data[di] = clampi(int(round((float(base[si]) * 0.5 + RELIEF_EARTH_R * 0.5) * f)) + n, 0, 255)
					data[di + 1] = clampi(int(round((float(base[si + 1]) * 0.5 + RELIEF_EARTH_G * 0.5) * f)) + n, 0, 255)
					data[di + 2] = clampi(int(round((float(base[si + 2]) * 0.5 + RELIEF_EARTH_B * 0.5) * f)) + n, 0, 255)
					data[di + 3] = 255
			# 足元の落ち影
			for d in range(3):
				var y := fb + 1 + d
				if y >= CHIP_HEIGHT:
					continue
				var a: int = int(shadow_a[d])
				var inv := 255 - a
				var di := (y * CHIP_SIZE + x) * 4
				data[di] = (int(data[di]) * inv) / 255
				data[di + 1] = (int(data[di + 1]) * inv) / 255
				data[di + 2] = (int(data[di + 2]) * inv) / 255
				data[di + 3] = maxi(int(data[di + 3]), a + (int(data[di + 3]) * inv) / 255)


func relief_cell_texture(cells: Array, dim: int, col: int, row: int) -> Variant:
	## 起伏合成済みのセル画像 (32x48) のテクスチャ。シートが無い
	## 場合は null (呼び出し側は従来描画に落とす)。
	var idx := row * dim + col
	if idx < 0 or idx >= cells.size():
		return null
	var cell: Dictionary = cells[idx]
	var sheet := _sheet_for(cell)
	if sheet == null:
		return null
	var h := height_at(cells, dim, col, row)
	var hn := height_at(cells, dim, col, row - 1)
	var hs := height_at(cells, dim, col, row + 1)
	var hw := height_at(cells, dim, col - 1, row)
	var he := height_at(cells, dim, col + 1, row)
	var indices := chip_indices(int(cell.get("chip", 0)))
	var north_cell: Dictionary = cells[clampi(row - 1, 0, dim - 1) * dim + col]
	var north_sheet := _sheet_for(north_cell)
	var north_indices := chip_indices(int(north_cell.get("chip", 0)))
	var key := str([sheet.get_instance_id(), indices, h, hn, hs, hw, he,
		north_sheet.get_instance_id() if north_sheet != null else 0, north_indices,
		relief_is_face(cells, dim, col - 1, row), relief_is_face(cells, dim, col + 1, row)])
	var cached: Variant = _relief_cache.get(key)
	if cached != null:
		return cached
	var data := PackedByteArray()
	data.resize(CHIP_SIZE * CHIP_HEIGHT * 4)
	for index in indices:
		_alpha_over(data, _toned_chip_data(sheet, index, h))
	var base := data.duplicate()
	var north := PackedByteArray()
	if north_sheet != null:
		north.resize(CHIP_SIZE * CHIP_HEIGHT * 4)
		for index in north_indices:
			_alpha_over(north, _toned_chip_data(north_sheet, index, hn))
	var spans: Array = []
	for x in range(CHIP_SIZE):
		spans.append(relief_face_span(cells, dim, col, row, x) if hn > h else [])
	relief_apply_overlays(data, base, north, [h, hn, hs, hw, he], spans)
	var img := Image.create_from_data(CHIP_SIZE, CHIP_HEIGHT, false, Image.FORMAT_RGBA8, data)
	var tex := ImageTexture.create_from_image(img)
	_relief_cache[key] = tex
	return tex


func _draw_cell_image(tex: Texture2D, col: int, row: int, z: float, dy_px: int = 0) -> void:
	## 32x48 のセル画像を _draw_chip と同じ位置に描く。
	var dx := col * CHIP_SIZE * z
	var dy := (row * CHIP_SIZE - (CHIP_HEIGHT - CHIP_SIZE) + MAP_TOP + dy_px) * z
	draw_texture_rect_region(tex, Rect2(dx, dy, CHIP_SIZE * z, CHIP_HEIGHT * z),
		Rect2(0, 0, CHIP_SIZE, CHIP_HEIGHT))


## テスト用: 起伏キャッシュの大きさ。
func debug_relief_cache_size() -> int:
	return _relief_cache.size()


## グラキャッシュ初期化の後、持っている絵を読み直す。
## _chip_texs/_items_tex は set_map の時だけ取り直すので、ここで
## 取り直さないと古いテクスチャのままになる。死亡の残像も古い
## テクスチャを持っているので捨てる(0.6秒の演出なので実害は無い)。
## 見えているキャラの絵は、再描画の「前に」作ってキャッシュを
## 温めておく。描画コールバックの中でテクスチャを作ると、Mac の
## Metal ではそのフレームにアップロードされず白く描かれ、次の
## 地図が届くまで白いまま残る(2026-11-15 の報告)。
func reload_cached_textures() -> void:
	_items_tex = null
	_fx_icons_tex = null
	_ghosts.clear()
	_load_chip_texs()
	if assets != null:
		_items_tex = assets.items()
		_fx_icons_tex = assets.skin_image("fx_icons")
		for ch_name in _last_charas:
			var ch: Dictionary = _last_charas[ch_name]
			assets.chara(str(ch.get("name", "")), str(ch.get("gra", "")), int(ch.get("default", 0)))
	queue_redraw()


## テスト用: 基準点の表を返します。
func debug_anchors() -> Dictionary:
	return _anchors


## テスト用: 中心の基準点を返します。
func debug_center_anchor() -> Variant:
	return _center_anchor


## テスト用: 自キャラが向いているマスの基準点を返します。
func debug_faced_anchor() -> Variant:
	return _faced_anchor


## テスト用: 台詞行で覚えた基準点の表を返します。
func debug_dialogue_anchors() -> Dictionary:
	return _dialogue_anchors


## テスト用: 残像の数を返します。
func debug_event_empty() -> bool:
	return _event.is_empty()


## マウス移動ガイド線の先のセル (Philly MouseMoveLine)。
## (-1,-1) の間は描かない。
var guide_cell := Vector2i(-1, -1)


func set_guide_cell(cell: Vector2i) -> void:
	if guide_cell == cell:
		return
	guide_cell = cell
	queue_redraw()


func player_cell() -> Vector2i:
	## 自キャラのいるセル (盤面の中心)。
	var dim := grid_dim(int(_event.get("size", 7)))
	return Vector2i(dim / 2, dim / 2)


func cell_at_local(local_pos: Vector2) -> Vector2i:
	## ローカル座標 → 盤面のセル。盤外は (-1,-1)。
	var rect := drawn_map_rect()
	if not rect.has_point(local_pos):
		return Vector2i(-1, -1)
	var board := (local_pos - rect.position) / float(zoom)
	var dim := grid_dim(int(_event.get("size", 7)))
	var cell := Vector2i(floori(board.x / CHIP_SIZE), floori((board.y - MAP_TOP) / CHIP_SIZE))
	if cell.x < 0 or cell.y < 0 or cell.x >= dim or cell.y >= dim:
		return Vector2i(-1, -1)
	return cell


func chara_name_at(local_pos: Vector2) -> String:
	## ローカル座標の点にいるキャラの名前。いなければ ""。
	var cell := cell_at_local(local_pos)
	if cell.x < 0:
		return ""
	for nm in _last_charas:
		var cd: Dictionary = _last_charas[nm]
		if int(cd.get("x", -1)) == cell.x and int(cd.get("y", -1)) == cell.y:
			return nm
	return ""


var _hint_label: Label = null


func show_hover_hint(cname: String, local_pos: Vector2, font_size: int) -> void:
	## キャラ名のヒントをマウス位置のそばに出す
	## (Philly SearchHintName)。名前が空なら隠す。
	if cname.is_empty():
		if _hint_label != null:
			_hint_label.visible = false
		return
	if _hint_label == null:
		_hint_label = Label.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.55)
		style.set_corner_radius_all(4)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		_hint_label.add_theme_stylebox_override("normal", style)
		_hint_label.add_theme_color_override("font_color", Color.WHITE)
		_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_hint_label)
	if bold_font != null:
		_hint_label.add_theme_font_override("font", bold_font)
	_hint_label.add_theme_font_size_override("font_size", font_size)
	_hint_label.text = cname
	_hint_label.visible = true
	var font := bold_font if bold_font != null else label_font
	var w := 12.0
	if font != null:
		w += font.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := local_pos + Vector2(14, 14)
	pos.x = minf(pos.x, maxf(0.0, size.x - w - 2.0))
	pos.y = minf(pos.y, maxf(0.0, size.y - float(font_size + 6) - 2.0))
	_hint_label.position = pos


func _align_factor() -> float:
	## 横配置の係数。余白を左にどれだけ残すか。
	match map_align:
		1:
			return 0.0
		2:
			return 1.0
	return 0.5


func drawn_map_rect() -> Rect2:
	## 描いている地図の範囲(コントロール内の座標)。マウスの当たり判定用。
	var dim := grid_dim(int(_event.get("size", 7)))
	var z := float(zoom)
	var w := dim * CHIP_SIZE * z
	var h := (dim * CHIP_SIZE + MAP_TOP) * z
	# 固定倍率で地図が窓より大きい時は、中心 (自キャラ) が
	# 見えるよう原点を負側にも許す。通常モードでは倍率が
	# 収まるよう調整されるため従来どおり 0 で止める。
	var ox := floorf((size.x - w) * _align_factor())
	var oy := floorf((size.y - h) * 0.5)
	if zoom_mode != 1:
		ox = maxf(0.0, ox)
		oy = maxf(0.0, oy)
	return Rect2(ox, oy, w, h)


func debug_disp_magic_count() -> int:
	return _disp_magics.size()


func debug_recent_disp_hit_count() -> int:
	return _recent_disp_hits.size()


func debug_bolt_count() -> int:
	return _bolts.size()


func debug_impact_count() -> int:
	return _impacts.size()


func debug_cast_count() -> int:
	return _casts.size()


func debug_ghost_count() -> int:
	return _ghosts.size()


static func grid_dim(size: int) -> int:
	return size if size == 5 or size == 7 or size == 9 or size == 11 else 7


static func chip_indices(chip_byte: int) -> Array:
	## チップのバイト → 描くチップの番号の配列。知らないバイトは 0。
	if CHIP_BYTE_TO_INDEX.has(chip_byte):
		return CHIP_BYTE_TO_INDEX[chip_byte]
	return [0]


static func chip_src_rect(index: int) -> Rect2:
	## チップシート上の index → 矩形。範囲外は空の矩形。
	if index < 0 or index >= CHIP_COUNT:
		return Rect2()
	var col := index % CHIPS_PER_ROW
	var row := index / CHIPS_PER_ROW
	return Rect2(col * CHIP_SIZE, row * CHIP_HEIGHT, CHIP_SIZE, CHIP_HEIGHT)


static func facing_offset(dir_value: Variant) -> Vector2i:
	## キャラ dir(文字) → 向いている隣接マスへのオフセット。
	## 知らない値は F(南) に倒す (dir_to_row の既定と同じ)。
	return _DIR_FACING_OFFSET.get(str(dir_value), Vector2i(0, 1))


static func dir_to_row(dir_value: Variant) -> int:
	## キャラdir(文字/数値) → シート行(0-3)。既定は F(2, 正面)。
	if dir_value is int:
		var ch: String = _DIR_NUM_TO_CHAR.get(dir_value & 7, "F")
		return _DIR_TO_ROW[ch]
	return _DIR_TO_ROW.get(str(dir_value), _DIR_TO_ROW["F"])


static func is_giant(gigant: Variant) -> bool:
	return str(gigant) == "*"


static func is_big(gigant: Variant) -> bool:
	## 2x2 の大きな敵 (サーバの大きさ印 'B'、PHIDM_NEO v1.3〜)。
	## gigant ('*') とは別で、体が基準マスから東・南へ 2x2 に広がる。
	return str(gigant) == "B"


static func char_draw_row(ch: Dictionary, dim: int) -> int:
	## キャラを描く行パス。2x2 の敵は足元が南の行にあるため、
	## 基準マスの次の行で描く (重なり順を足元に合わせる)。
	var row := int(ch.get("y", 0)) + (1 if is_big(ch.get("gigant")) else 0)
	return mini(row, dim - 1)


static func arrange_row(chars: Array) -> Array:
	## 1行のキャラを描く順と、横にずらす量(px)。(x, layer) の順に描く。
	var ordered := chars.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("x", 0)) != int(b.get("x", 0)):
			return int(a.get("x", 0)) < int(b.get("x", 0))
		return int(a.get("layer", 0)) < int(b.get("layer", 0)))
	var out: Array = []
	var i := 0
	while i < ordered.size():
		var j := i
		while j < ordered.size() and int(ordered[j].get("x", 0)) == int(ordered[i].get("x", 0)):
			j += 1
		var cell := ordered.slice(i, j)
		i = j
		if cell.size() == 2:
			var a: Dictionary = cell[0]
			var b: Dictionary = cell[1]
			var ga := is_giant(a.get("gigant"))
			var gb := is_giant(b.get("gigant"))
			if not ga and not gb:
				out.append([a, -8])
				out.append([b, 8])
				continue
			if ga != gb:
				var big: Dictionary = a if ga else b
				var small: Dictionary = b if ga else a
				out.append([big, 0])
				out.append([small, 8])
				continue
		for ch in cell:
			out.append([ch, 0])
	return out


static func cell_height(cell: Dictionary) -> int:
	## セルの段数 (-1〜+3)。印の無いセルは 0。
	return int(cell.get("height", 0))


static func height_at(cells: Array, dim: int, col: int, row: int) -> int:
	## セル (col,row) の段数。範囲外は端のセルの高さで延長する
	## (サンプルの height_at と同じ。画面端で段差が誤爆しない)。
	var c := clampi(col, 0, dim - 1)
	var r := clampi(row, 0, dim - 1)
	var idx := r * dim + c
	if idx < 0 or idx >= cells.size():
		return 0
	return cell_height(cells[idx])


static func relief_offset_y(cells: Array, dim: int, col: int, row: int) -> int:
	## そのセルの高さぶんの描画 y ずれ (px)。高いほど上へ。
	return -RELIEF_STEP * height_at(cells, dim, col, row)


static func relief_scroll_dy(from_h: int, to_h: int, p: float) -> float:
	## スクロール中に段差を渡る自キャラの高さずれ (px)。p は
	## 地図のイーズ済み進み具合 (0〜1)。端点では両端の段高に
	## ちょうど一致する。
	## 登り: 線形補間に放物線の浮き (ホップ) を加える。浮きは
	## 中盤 (p=0.5) で最大、段差1段あたり RELIEF_HOP_PX_PER_STEP、
	## RELIEF_HOP_MAX_PX で頭打ち。
	## 降り: 補間係数を p^RELIEF_DROP_EXP にして、前半は高さを
	## 保ち気味に後半でストンと落ちる (行き過ぎはしない)。
	var dh := to_h - from_h
	if dh > 0:
		var hop := minf(RELIEF_HOP_PX_PER_STEP * float(dh),
			RELIEF_HOP_MAX_PX)
		return -float(RELIEF_STEP) * lerpf(float(from_h), float(to_h), p) \
			- hop * 4.0 * p * (1.0 - p)
	if dh < 0:
		var q := pow(p, RELIEF_DROP_EXP)
		return -float(RELIEF_STEP) * lerpf(float(from_h), float(to_h), q)
	return -float(RELIEF_STEP) * float(from_h)


static func relief_is_face(cells: Array, dim: int, col: int, row: int) -> bool:
	## 北の隣が高い = このセルの上部に段面の帯が出る。
	return height_at(cells, dim, col, row - 1) > height_at(cells, dim, col, row)


static func relief_involved(cells: Array, dim: int, col: int, row: int) -> bool:
	## 起伏の自動生成が要るセルか。自他の段数と、左右の段面の
	## テーパー (隣の段面の有無) に関わるセルだけが対象で、
	## 高さの無い地図では全セル false になり従来描画と一致する。
	if height_at(cells, dim, col, row) != 0:
		return true
	if height_at(cells, dim, col, row - 1) != 0 or height_at(cells, dim, col, row + 1) != 0:
		return true
	if height_at(cells, dim, col - 1, row) != 0 or height_at(cells, dim, col + 1, row) != 0:
		return true
	return relief_is_face(cells, dim, col - 1, row) or relief_is_face(cells, dim, col + 1, row)


static func relief_face_span(cells: Array, dim: int, col: int, row: int, x: int) -> Array:
	## 段面の帯の列 x の形状 [下端行 fb, 唇の厚み lip]。帯が出ない
	## 列 (端の先端) は空配列。サンプルの式そのまま。
	var s := 1.0
	if not relief_is_face(cells, dim, col - 1, row):
		s = minf(s, pow((float(x) + 1.0) / 10.0, 1.1))
	if not relief_is_face(cells, dim, col + 1, row):
		s = minf(s, pow((float(CHIP_SIZE - x)) / 10.0, 1.1))
	var fb := int(round(3.0 + 9.0 * s))
	var lip := int(round(3.0 * s))
	if fb <= lip + 1:
		return []
	return [fb, lip]


static func relief_noise(x: int, y: int) -> int:
	## サンプルの帯のざらつき (決定的なハッシュ)。
	return ((x * 73856093) ^ (y * 19349663)) % 13 - 6


static func relief_tone_rgb(r: float, g: float, b: float, h: int) -> Array:
	## サンプル (render_auto_relief.py の toned()) の色調変換。
	## 戻り値は [r, g, b] (0〜255、未クランプの丸め前)。
	## 暗いピクセル (輝度 0.30 未満) でのみ、丘側には小さな加算
	## 成分、窪地には追加の彩度落としを混ぜる (全チップ評価で
	## 暗いチップの段差が乗算だけでは消えたため)。Field の草
	## (輝度 ≈ 0.5) では補正は 0 で、サンプルと完全一致する。
	var f := float(RELIEF_TONES.get(h, 1.0))
	var nr := r * f
	var ng := g * f
	var nb := b * f
	if h == -1:
		var lum := 0.35 * nr + 0.5 * ng + 0.15 * nb
		nr = nr * 0.85 + lum * 0.15
		ng = ng * 0.85 + lum * 0.15
		nb = nb * 0.9 + lum * 0.1 + 4.0
	var lum2 := (0.35 * nr + 0.5 * ng + 0.15 * nb) / 255.0
	var dark := clampf((0.30 - lum2) / 0.30, 0.0, 1.0)
	dark = pow(dark, 1.5)
	if dark > 0.0:
		if h > 0:
			var add := 7.0 * float(h) * dark
			nr += add
			ng += add
			nb += add * 0.9
		elif h == -1:
			var lum3 := 0.35 * nr + 0.5 * ng + 0.15 * nb
			var mix := 0.35 * dark
			nr = lerpf(nr, lum3, mix)
			ng = lerpf(ng, lum3, mix)
			nb = lerpf(nb, lum3, mix) + 3.0 * dark
	return [nr, ng, nb]


static func char_pass(ch: Dictionary, cells: Array, dim: int, dy_px: float) -> int:
	## キャラを描く行パス。高さの絡まないキャラは従来の
	## char_draw_row と同じ (高さ 0 の地図では描画が完全一致)。
	## 高さのあるセルでは足元基準にする: 表示上の足元
	## (スプライト下端 + 高さずれ) の属する行で描く。行単位の
	## ままだと、段差の入口で段面の帯がキャラを横切って一瞬
	## 奥に隠れる (サンプルで実証され、足元基準で解消済み)。
	var base := char_draw_row(ch, dim)
	var cx := int(ch.get("x", 0))
	var cy := int(ch.get("y", 0))
	if height_at(cells, dim, cx, cy) == 0 and dy_px == 0.0:
		return base
	var foot_row := cy + (1 if is_big(ch.get("gigant")) else 0)
	var foot := foot_row * CHIP_SIZE + CHARA_FOOT + int(round(dy_px))
	return clampi(foot / CHIP_SIZE, 0, dim - 1)


static func chara_src_rect(dir_value: Variant, gigant: Variant, anim_frame: int = 0, large: bool = false) -> Rect2:
	## キャラスプライトのソース矩形。
	## 96px幅レイアウト: [小frame0=16][小frame1=16][大frame0=32][大frame1=32]。
	var row := dir_to_row(dir_value)
	var frame := anim_frame & 1
	var sy := row * CHARA_H
	if large or is_giant(gigant) or is_big(gigant):
		return Rect2(CHARA_W_NORMAL * 2 + frame * CHARA_W_GIANT, sy, CHARA_W_GIANT, CHARA_H)
	return Rect2(frame * CHARA_W_NORMAL, sy, CHARA_W_NORMAL, CHARA_H)


static func water_quarter_patterns(water: Array, wy: int, wx: int) -> Array[int]:
	## 水セルの周りの水有無から各 quarter の3bitパターンを計算する。
	return [
		water[wy][wx] | (water[wy][wx + 1] << 1) | (water[wy + 1][wx] << 2),
		water[wy][wx + 2] | (water[wy][wx + 1] << 1) | (water[wy + 1][wx + 2] << 2),
		water[wy + 2][wx] | (water[wy + 2][wx + 1] << 1) | (water[wy + 1][wx] << 2),
		water[wy + 2][wx + 2] | (water[wy + 2][wx + 1] << 1) | (water[wy + 1][wx + 2] << 2),
	]


static func water_quarter_chip(q_index: int, pattern: int) -> Variant:
	## quarter のパターンから描画する水縁チップを解決する。
	## [chipIndex, srcQuarter] か、overlay不要なら null。
	var entry: Variant = (Q_TABLE[q_index] as Dictionary).get(pattern)
	if entry == null:
		return null
	return [WATER_CHIP_BASE + entry[0], entry[1]]


static func chip_quarter_src_rect(chip_index: int, quarter: int) -> Rect2:
	## チップindex + quarter(0=TL,1=TR,2=BL,3=BR) → シート上の16×16矩形。
	var base := chip_src_rect(chip_index)
	if base.size.x <= 0:
		return Rect2()
	var half := CHIP_SIZE / 2
	return Rect2(
		base.position.x + (quarter & 1) * half,
		base.position.y + (CHIP_HEIGHT - CHIP_SIZE) + ((quarter >> 1) & 1) * half,
		half, half)


static func build_water_grid(cells: Array, dim: int) -> Array:
	## 水有無の (dim+2)×(dim+2) 配列を作る(枠=0)。
	var water: Array = []
	for r in range(dim + 2):
		var row: Array = []
		for c in range(dim + 2):
			row.append(0)
		water.append(row)
	for r in range(dim):
		for c in range(dim):
			var idx := r * dim + c
			if idx < cells.size() and int(cells[idx].get("chip", 0)) == WATER_BYTE:
				water[r + 1][c + 1] = 1
	return water


## 余白全体を濃紺で塗り、壁紙があればタイル状に並べる。
func _draw_wallpaper() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WALLPAPER_BG)
	if _wallpaper == null:
		return
	var y := 0.0
	while y < size.y:
		var x := 0.0
		while x < size.x:
			draw_texture_rect(_wallpaper, Rect2(x, y, WALLPAPER_TILE.x, WALLPAPER_TILE.y), false, WALLPAPER_MODULATE)
			x += WALLPAPER_TILE.x
		y += WALLPAPER_TILE.y


func _draw_cell_row(cells: Array, dim: int, z: float, row: int, water: Variant) -> void:
	## 1行分のセル (ベースチップ・水縁・看板・アイテム) を描く。
	## 滑らかスクロールの「前の地図」パスと共用する (第64段)。
	var half := CHIP_SIZE / 2
	# 起伏の対象セル (この行)。高さの無い地図では全て false で、
	# 以下の分岐は全て従来どおりになる。
	var relief: Array = []
	var rheights: Array = []
	for col in range(dim):
		relief.append(relief_involved(cells, dim, col, row))
		rheights.append(height_at(cells, dim, col, row))
	# 1. ベースチップ
	for col in range(dim):
		var idx := row * dim + col
		if idx >= cells.size():
			continue
		var cell: Dictionary = cells[idx]
		var sheet := _sheet_for(cell)
		if sheet == null:
			_fallback_cell(cell, col, row, z)
			continue
		if relief[col]:
			var rtex: Variant = relief_cell_texture(cells, dim, col, row)
			if rtex != null:
				_draw_cell_image(rtex, col, row, z)
				continue
		for chip_index in chip_indices(int(cell.get("chip", 0))):
			_draw_chip(sheet, chip_index, col, row, z)
	# 1.5 水縁overlay
	if water != null:
		for col in range(dim):
			var idx := row * dim + col
			if idx >= cells.size():
				continue
			var cell: Dictionary = cells[idx]
			if int(cell.get("chip", 0)) != WATER_BYTE:
				continue
			var sheet := _sheet_for(cell)
			if sheet == null:
				continue
			var patterns := water_quarter_patterns(water, row, col)
			var cell_x := col * CHIP_SIZE
			var cell_y := row * CHIP_SIZE + MAP_TOP
			for q in range(4):
				var hit: Variant = water_quarter_chip(q, patterns[q])
				if hit == null:
					continue
				var dx := (cell_x + (q & 1) * half) * z
				var dy := (cell_y + ((q >> 1) & 1) * half) * z
				if relief[col]:
					# 起伏セルでは色調済みチップから quarter を取る。
					var qtex := _toned_chip_texture(sheet, int(hit[0]), int(rheights[col]))
					var qrect := Rect2((q & 1) * half,
						(CHIP_HEIGHT - CHIP_SIZE) + ((q >> 1) & 1) * half, half, half)
					draw_texture_rect_region(qtex, Rect2(dx, dy, half * z, half * z), qrect)
					continue
				var rect := chip_quarter_src_rect(hit[0], hit[1])
				if rect.size.x <= 0:
					continue
				draw_texture_rect_region(sheet, Rect2(dx, dy, half * z, half * z), rect)
	# 2. 看板overlay
	for col in range(dim):
		var idx := row * dim + col
		if idx >= cells.size():
			continue
		var cell: Dictionary = cells[idx]
		if (int(cell.get("attr", 0)) & 0x08) == 0:
			continue
		var sheet := _sheet_for(cell)
		if sheet != null:
			if relief[col]:
				var btex := _toned_chip_texture(sheet,
					_board_chip_index(int(cell.get("chip", 0))), int(rheights[col]))
				_draw_cell_image(btex, col, row, z, -RELIEF_STEP * int(rheights[col]))
			else:
				_draw_chip(sheet, _board_chip_index(int(cell.get("chip", 0))), col, row, z)
	# 3. アイテムoverlay
	for col in range(dim):
		var idx := row * dim + col
		if idx >= cells.size():
			continue
		var cell: Dictionary = cells[idx]
		if (int(cell.get("attr", 0)) & 0x70) == 0:
			continue
		_draw_item(cell, col, row, z,
			-RELIEF_STEP * int(rheights[col]) if relief[col] else 0)


func _draw() -> void:
	if _event.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), TITLE_BG)
		return
	var dim := grid_dim(int(_event.get("size", 7)))
	var cells: Array = _event.get("cells", [])
	var chars: Array = _event.get("chars", [])
	var z := float(zoom)
	# 割り当てより小さく描けるときは中央に寄せる。揺れは全体に掛けます。
	# 配置は整数ピクセルに丸める。小数位置だと線形補間でチップの
	# 端が隣の絵と混ざり、セルの境に黒い線が出ることがある。
	var shake := _shake_offset(z)
	var raw_ox := (size.x - dim * CHIP_SIZE * z) * _align_factor()
	var raw_oy := (size.y - (dim * CHIP_SIZE + MAP_TOP) * z) * 0.5
	if zoom_mode != 1:
		# 固定倍率の時は原点を負側にも許し、地図を中央に保つ
		# (drawn_map_rect と一致させる)。
		raw_ox = maxf(0.0, raw_ox)
		raw_oy = maxf(0.0, raw_oy)
	var ox := floorf(raw_ox + shake.x)
	var oy := floorf(raw_oy + shake.y)
	# 第64段: 滑らかスクロールのずれ (画面ピクセル)。イーズ
	# アウトで 0 へ戻す。前の地図は「ずれ - 1マス」の位置に
	# 描き、はみ出す端の行・列を覆う。自キャラだけは中央に
	# 留めるため、逆向きにずらして描く。
	var scrolling := _scroll_t < 1.0 and not _prev_cells.is_empty()
	var so := Vector2.ZERO
	if scrolling:
		so = _scroll_from * float(CHIP_SIZE) * z * pow(1.0 - _scroll_t, 3.0)
	# 地図の周りの余白にはモノグラム壁紙を敷く(無ければ黒)。
	_draw_wallpaper()
	draw_set_transform(Vector2(ox + so.x, oy + so.y), 0.0, Vector2.ONE)
	# 地図の背景は塗らない。セルの絵が全面を覆い、上の張り出しの
	# 隙間からは後ろの壁紙が見える(黒く塗ると帯になって目立つ)。
	var water: Variant = null
	if _any_sheet():
		water = build_water_grid(cells, dim)
	var half := CHIP_SIZE / 2

	if scrolling:
		# 前の地図を後ろに敷く (端のはみ出し側を覆う)。
		var pwater: Variant = null
		if _any_sheet():
			pwater = build_water_grid(_prev_cells, dim)
		draw_set_transform(Vector2(ox, oy) + so - _scroll_from * float(CHIP_SIZE) * z, 0.0, Vector2.ONE)
		for prow in range(dim):
			_draw_cell_row(_prev_cells, dim, z, prow, pwater)
		draw_set_transform(Vector2(ox + so.x, oy + so.y), 0.0, Vector2.ONE)

	for row in range(dim):
		_draw_cell_row(cells, dim, z, row, water)
		# 4. キャラ(この行)。高さのあるセルでは足元基準の行で
		# 描き、高さぶん y をずらす。
		var row_chars: Array = []
		for ch in chars:
			if char_pass(ch, cells, dim, _chara_dy(ch, cells, dim, scrolling)) == row \
					and 0 <= int(ch.get("x", -1)) and int(ch.get("x", -1)) < dim:
				row_chars.append(ch)
		for pair in arrange_row(row_chars):
			var ch: Dictionary = pair[0]
			var po := Vector2(0.0, _chara_dy(ch, cells, dim, scrolling) * z)
			if scrolling and bool(ch.get("__self", false)):
				po += -so  # 自キャラは中央に留める
			_draw_state_icon(ch, pair[1], z, true, po)
			_draw_fx_aura(ch, pair[1], z, po)
			_draw_chara(ch, pair[1], z, null, Color.WHITE, po)
			_draw_state_icon(ch, pair[1], z, false, po)
			_draw_fx_icons(ch, pair[1], z, po)
		# 4.5 残像(この行)。ずらさず、この行のキャラの上に重ねます。
		_draw_ghosts(row, dim, z)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if scrolling:
		# スクロール中は地図の四角の外へはみ出したセル・キャラの
		# 描画を壁紙で覆い隠す (第65段、ユーザーの要望)。ただし
		# 覆うのはここまで (セルとキャラ) で、ラベル・吹き出し・
		# 演出は壁紙より手前に描く。最後に覆うと、上の線より上に
		# 出た吹き出し等が一瞬壁紙の後ろに隠れてちらつくため
		# (第67段、ユーザーの指摘「一瞬壁紙が前に来ている」)。
		# 上の余白帯 (MAP_TOP) は内側に含める (帯まで隠す版は
		# 張り出しが最後にぱっと現れてちらついたため戻した)。
		_mask_outside_grid(_scroll_mask_rect(ox, oy, dim, z))
	draw_set_transform(Vector2(ox + so.x, oy + so.y), 0.0, Vector2.ONE)
	# 5. キャラ名ラベル(中心の自キャラは除外)。同じマスは後勝ち。
	_draw_labels(chars, dim, z)
	# 6. 戦闘の演出(点滅・斬撃・魔法弾・着弾・浮き数字・吹き出し)。
	_draw_effects(dim, z)
	# 7. マウス移動ガイド線 (Philly MouseMoveLine)。自セルから
	# マウスのセルへ目安の線を引く。
	if guide_cell.x >= 0:
		var pc := player_cell()
		if guide_cell != pc:
			var from := Vector2(pc.x * CHIP_SIZE + CHIP_SIZE / 2, MAP_TOP + pc.y * CHIP_SIZE + CHIP_SIZE / 2) * z
			var to := Vector2(guide_cell.x * CHIP_SIZE + CHIP_SIZE / 2, MAP_TOP + guide_cell.y * CHIP_SIZE + CHIP_SIZE / 2) * z
			draw_line(from, to, Color(1, 1, 1, 0.55), 2.0)
			draw_circle(to, 4.0, Color(1, 1, 1, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 8. DM 演出拡張 (FX) のオーバーレイ (暗転→発光→画像→文字→
	# ワイプの順。ワイプが最前面)。
	_draw_fx_overlays()


func _chara_dy(ch: Dictionary, cells: Array, dim: int, scrolling: bool) -> float:
	## キャラの高さずれ (px、拡大前)。自キャラはスクロール中に
	## 中心セルの段数の間を、地図のイーズと同じ進み具合で補間
	## する (relief_scroll_dy: 登りはホップ、降りは後半に落ちる
	## 曲線)。それ以外は自セルの段数。
	if bool(ch.get("__self", false)):
		if scrolling and _scroll_from_h != _scroll_to_h:
			var p := 1.0 - pow(1.0 - _scroll_t, 3.0)
			return relief_scroll_dy(_scroll_from_h, _scroll_to_h, p)
		return -float(RELIEF_STEP) * float(_scroll_to_h)
	return float(relief_offset_y(cells, dim,
		int(ch.get("x", 0)), int(ch.get("y", 0))))


func _scroll_mask_rect(ox: float, oy: float, dim: int, z: float) -> Rect2:
	## スクロール中のマスクの内側 = 地図の四角 (上の余白帯
	## MAP_TOP を含む)。
	return Rect2(ox, oy, dim * float(CHIP_SIZE) * z,
		(dim * float(CHIP_SIZE) + MAP_TOP) * z)


func _outside_strips(rect: Rect2, bounds: Vector2) -> Array:
	## rect の外側 (上下左右) の帯。マスクの描画範囲に使う。
	var strips: Array = []
	var top := Rect2(0, 0, bounds.x, rect.position.y)
	if top.size.y > 0:
		strips.append(top)
	var bottom := Rect2(0, rect.end.y, bounds.x, bounds.y - rect.end.y)
	if bottom.size.y > 0:
		strips.append(bottom)
	var left := Rect2(0, rect.position.y, rect.position.x, rect.size.y)
	if left.size.x > 0:
		strips.append(left)
	var right := Rect2(rect.end.x, rect.position.y, bounds.x - rect.end.x, rect.size.y)
	if right.size.x > 0:
		strips.append(right)
	return strips


func _mask_outside_grid(rect: Rect2) -> void:
	## 地図の四角の外側を壁紙で塗り直す (位相は _draw_wallpaper
	## と同じく原点から敷く)。
	for strip_v in _outside_strips(rect, size):
		var strip: Rect2 = strip_v
		draw_rect(strip, WALLPAPER_BG)
		if _wallpaper == null:
			continue
		var tex_size := Vector2(_wallpaper.get_size())
		var tx := floorf(strip.position.x / WALLPAPER_TILE.x) * WALLPAPER_TILE.x
		while tx < strip.end.x:
			var ty := floorf(strip.position.y / WALLPAPER_TILE.y) * WALLPAPER_TILE.y
			while ty < strip.end.y:
				var tile := Rect2(tx, ty, WALLPAPER_TILE.x, WALLPAPER_TILE.y)
				var inter := tile.intersection(strip)
				if inter.size.x > 0 and inter.size.y > 0:
					var src := Rect2(
						(inter.position - tile.position) / WALLPAPER_TILE * tex_size,
						inter.size / WALLPAPER_TILE * tex_size)
					draw_texture_rect_region(_wallpaper, inter, src, WALLPAPER_MODULATE)
				ty += WALLPAPER_TILE.y
			tx += WALLPAPER_TILE.x


func _draw_chip(tex: Texture2D, index: int, col: int, row: int, z: float) -> void:
	var rect := chip_src_rect(index)
	if rect.size.x <= 0:
		return
	var overhang := CHIP_HEIGHT - CHIP_SIZE
	var dx := col * CHIP_SIZE * z
	var dy := (row * CHIP_SIZE - overhang + MAP_TOP) * z
	draw_texture_rect_region(tex, Rect2(dx, dy, rect.size.x * z, rect.size.y * z), rect)


func _fallback_cell(cell: Dictionary, col: int, row: int, z: float) -> void:
	var indices := chip_indices(int(cell.get("chip", 0)))
	var color: Color = FALLBACK_CHIP_COLORS.get(indices[0], FALLBACK_CHIP_DEFAULT)
	var h := cell_height(cell)
	if h != 0:
		# 絵が無いセルの代用色にも段の色調だけは付ける。
		var f := float(RELIEF_TONES.get(h, 1.0))
		color = Color(minf(color.r * f, 1.0), minf(color.g * f, 1.0), minf(color.b * f, 1.0), color.a)
	draw_rect(Rect2(col * CHIP_SIZE * z, (row * CHIP_SIZE + MAP_TOP) * z, CHIP_SIZE * z, CHIP_SIZE * z), color)


func _board_chip_index(chip_byte: int) -> int:
	return BOARD_CHIP_HARD if chip_byte in _HARD_BOARD_CHIPS else BOARD_CHIP_SOFT


func _draw_item(cell: Dictionary, col: int, row: int, z: float, dy_px: int = 0) -> void:
	var no := (int(cell.get("attr", 0)) & 0x70) >> 4
	var dst_x := col * CHIP_SIZE
	var dst_y := row * CHIP_SIZE + MAP_TOP + dy_px
	if _items_tex == null:
		draw_rect(Rect2((dst_x + 8) * z, (dst_y + 8) * z, 16 * z, 16 * z), Color(1.0, 1.0, 0.78))
		return
	var s := ITEM_SPRITE_SIZE
	var src_x := no * s
	var draw_y := dst_y - ITEM_Y_ABOVE_FLOOR
	if int(cell.get("chip", 0)) in _CIRCLE_CHIPS:
		var src_y := 5 if no == 5 or no == 6 else 0
		draw_texture_rect_region(_items_tex,
			Rect2(dst_x * z, draw_y * z, s * z, ITEM_CLIP_H * z),
			Rect2(src_x, src_y, s, ITEM_CLIP_H))
	else:
		draw_texture_rect_region(_items_tex,
			Rect2(dst_x * z, draw_y * z, s * z, s * z),
			Rect2(src_x, 0, s, s))


func _draw_chara(ch: Dictionary, dx: int, z: float, tex_override: Texture2D = null, modulate := Color.WHITE, po := Vector2.ZERO) -> void:
	var rect := chara_src_rect(ch.get("dir", "F"), ch.get("gigant", "#"), _anim_frame)
	var sw := rect.size.x
	var sh := rect.size.y
	var base_x := int(ch.get("x", 0)) * CHIP_SIZE + (CHIP_SIZE - int(sw)) / 2 + dx
	var base_y := int(ch.get("y", 0)) * CHIP_SIZE + (CHIP_SIZE - CHARA_H) / 2 - CHARA_Y_ABOVE_FLOOR + MAP_TOP
	# 2x2 の敵は大きな絵を 2 倍に描き、基準マスから東・南の
	# 4 マスを覆う。base は基準マスの通常位置のまま (絵の上端が
	# 基準行の上端、足元が南行の足元に一致する)。
	var dw := sw * (2.0 if is_big(ch.get("gigant")) else 1.0)
	var dh := sh * (2.0 if is_big(ch.get("gigant")) else 1.0)
	var tex: Texture2D = tex_override
	if tex == null and assets != null:
		tex = assets.chara(str(ch.get("name", "")), str(ch.get("gra", "")), int(ch.get("default", 0)))
	if tex == null:
		draw_rect(Rect2(base_x * z + po.x, base_y * z + po.y, dw * z, dh * z), Color.YELLOW)
		_draw_placeholder_initial(ch, base_x, base_y, int(dw), int(dh), z)
		return
	var magnify: Variant = ch.get("magnify")
	if magnify != null:
		var m: Dictionary = magnify
		var d := _magnified_dst(base_x, base_y, m)
		draw_texture_rect_region(tex, Rect2(d[0] * z + po.x, d[1] * z + po.y, d[2] * z, d[3] * z), rect, modulate)
		return
	draw_texture_rect_region(tex, Rect2(base_x * z + po.x, base_y * z + po.y, dw * z, dh * z), rect, modulate)


func _magnified_dst(base_x: int, base_y: int, m: Dictionary) -> Array[int]:
	var dx := base_x - (int(m.get("w", 0)) - CHARA_H) / 2
	var dy := base_y - (((int(m.get("h", 0)) - CHARA_H) * 5) / 6 + int(m.get("z", 0)))
	return [dx, dy, int(m.get("w", 0)), int(m.get("h", 0))]


func _draw_placeholder_initial(ch: Dictionary, base_x: int, base_y: int, sw: float, sh: float, z: float) -> void:
	if label_font == null:
		return
	var chara_name := PhiTags.strip_tags(str(ch.get("name", ""))).strip_edges()
	if chara_name.is_empty():
		return
	var initial := chara_name.substr(0, 1)
	var font_size := int(12 * z)
	var ts := label_font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var cx := (base_x + sw / 2.0) * z - ts.x / 2.0
	var cy := (base_y + sh / 2.0) * z + (label_font.get_ascent(font_size) - label_font.get_descent(font_size)) / 2.0
	draw_string(label_font, Vector2(cx, cy), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)


func _draw_state_icon(ch: Dictionary, dx: int, z: float, under: bool, po := Vector2.ZERO) -> void:
	## キャラの状態アイコン(第3段)。Philly はキャラの下→本体→上の順に描く。
	var status := int(ch.get("status", 0))
	var icon: Variant
	if under:
		icon = PhiCharaState.under_icon(status)
	else:
		var anim := int(_now() * 2.0) % 2 if _session_live else _anim_frame
		icon = PhiCharaState.over_icon(status, str(ch.get("dir", "F")), anim)
	if icon == null:
		return
	var cell: int = icon[0]
	var ix := (int(ch.get("x", 0)) * CHIP_SIZE + dx + int(icon[1])) * z + po.x
	var iy := (int(ch.get("y", 0)) * CHIP_SIZE + 5 + int(icon[2])) * z + po.y
	if _items_tex != null and cell * 32 + 32 <= _items_tex.get_width():
		draw_texture_rect_region(_items_tex, Rect2(ix, iy, 32.0 * z, 32.0 * z), Rect2(cell * 32, 0, 32, 32))
	else:
		# 絵が無ければ小さな枠で代用する
		draw_rect(Rect2(ix + 6.0 * z, iy + 6.0 * z, 20.0 * z, 20.0 * z), Color(1, 1, 1, 0.25), false, maxf(1.0, z))


# -- DM 演出拡張 (FX) -------------------------------------------------

func apply_fx(ev: Dictionary) -> void:
	## パーサからの FX イベントを演出状態へ反映する (画像系は
	## PhiCharacter が捌くのでここには来ない)。
	var now := _now()
	match str(ev.get("kind", "")):
		"text":
			var dur := int(ev.get("dur", 0))
			_fx_texts[str(ev.get("pos", "C"))] = {
				"text": str(ev.get("text", "")),
				"size": int(ev.get("size", 100)),
				"started": now,
				"until": (now + dur / 1000.0) if dur > 0 else 0.0,
			}
		"textoff":
			var pos := str(ev.get("pos", "all"))
			if pos == "all":
				_fx_texts.clear()
			else:
				_fx_texts.erase(pos)
		"dark":
			var dur := int(ev.get("dur", 0))
			if int(ev.get("level", 0)) <= 0 and dur == 0:
				_fx_dark = {}
			else:
				_fx_dark = {
					"level": int(ev.get("level", 0)),
					"mode": int(ev.get("mode", 0)),
					"started": now,
					"until": (now + dur / 1000.0) if dur > 0 else 0.0,
				}
		"wipe":
			_fx_wipe = {
				"pattern": str(ev.get("pattern", "C")),
				"dir": str(ev.get("dir", "on")),
				"started": now,
			}
		"shake":
			_fx_shake_amp = float(int(ev.get("amp", 0)))
			_fx_shake_until = now + int(ev.get("dur", 0)) / 1000.0
		"glow":
			_fx_glow = {"started": now, "dur": int(ev.get("dur", 0)) / 1000.0}
		"clear":
			_fx_texts.clear()
			_fx_dark = {}
			_fx_img = {}
	queue_redraw()


func show_fx_image(tex: Texture2D, dur_ms: int) -> void:
	## サーバ画像 (マップ表示) を出す。dur は表示開始から数える。
	var now := _now()
	_fx_img = {"tex": tex, "started": now,
		"until": (now + dur_ms / 1000.0) if dur_ms > 0 else 0.0}
	queue_redraw()


func _fx_any_active() -> bool:
	return not _fx_texts.is_empty() or not _fx_dark.is_empty() \
		or not _fx_wipe.is_empty() or not _fx_glow.is_empty() \
		or not _fx_img.is_empty() or _now() < _fx_shake_until


func _fx_prune(now: float) -> void:
	for pos in _fx_texts.keys():
		var until := float(_fx_texts[pos].get("until", 0.0))
		if until > 0.0 and now > until + 0.2:
			_fx_texts.erase(pos)
	if not _fx_dark.is_empty():
		var duntil := float(_fx_dark.get("until", 0.0))
		if duntil > 0.0 and now > duntil:
			_fx_dark = {}
	if not _fx_glow.is_empty():
		if now - float(_fx_glow.get("started", 0.0)) >= float(_fx_glow.get("dur", 0.0)):
			_fx_glow = {}
	if not _fx_img.is_empty():
		var iuntil := float(_fx_img.get("until", 0.0))
		if iuntil > 0.0 and now > iuntil:
			_fx_img = {}
	if not _fx_wipe.is_empty() and str(_fx_wipe.get("dir", "on")) == "off":
		if now - float(_fx_wipe.get("started", 0.0)) >= 1.0:
			_fx_wipe = {}


func _draw_fx_overlays() -> void:
	var now := _now()
	_fx_prune(now)
	var full := Rect2(Vector2.ZERO, size)
	# 暗転 (定常は短くフェードイン、明滅は周期1秒で往復)。
	if not _fx_dark.is_empty():
		var lv := float(int(_fx_dark.get("level", 0))) / 100.0
		var a := lv
		if int(_fx_dark.get("mode", 0)) == 1:
			a = lv * (0.5 + 0.5 * sin((now - float(_fx_dark["started"])) * TAU))
		else:
			a *= clampf((now - float(_fx_dark["started"])) / 0.25, 0.0, 1.0)
		draw_rect(full, Color(0, 0, 0, clampf(a, 0.0, 1.0)))
	# 放射状発光 (ふわりと光って自動でフェードアウト)。
	if not _fx_glow.is_empty():
		var dur := maxf(0.01, float(_fx_glow.get("dur", 0.0)))
		var t := (now - float(_fx_glow.get("started", 0.0))) / dur
		if t < 1.0:
			var mrect := drawn_map_rect()
			var side := maxf(mrect.size.x, mrect.size.y) * 1.5
			draw_texture_rect(_glow_texture(),
				Rect2(mrect.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)),
				false, Color(1, 1, 1, sin(PI * t) * 0.85))
	# サーバ画像 (マップ中央)。
	if not _fx_img.is_empty():
		var tex: Texture2D = _fx_img["tex"]
		var mrect2 := drawn_map_rect()
		draw_texture(tex, mrect2.get_center() - Vector2(tex.get_width(), tex.get_height()) * 0.5)
	# マップ上文字。
	_draw_fx_texts(now)
	# ワイプ (最前面)。
	if not _fx_wipe.is_empty():
		_draw_fx_wipe(now)


func _glow_texture() -> Texture2D:
	## 放射グラデーション (白〜金系の中心から透明へ)。初回に生成。
	if _glow_tex != null:
		return _glow_tex
	var side := 256
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var center := Vector2(side, side) * 0.5
	for y in side:
		for x in side:
			var d := Vector2(x, y).distance_to(center) / (side * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.95, 0.8, a * a))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


const FX_TEXT_BASE_PX := 32.0
const FX_TEXT_MIN_PX := 8


static func fx_text_font_size(font: Font, text: String, size_pct: int,
		avail_width: float) -> int:
	## FX 文字の実フォントサイズ。名目は基準 32px に対する % で
	## 決まるが、文字列幅が avail_width (マップ描画幅) を超える
	## 場合は、全文が収まるよう比例で縮小する (shrink-to-fit)。
	## 収まっている場合は名目サイズそのままで、従来の見た目を
	## 変えない。下限は従来の名目側クランプと同じ 8px: 実在の
	## 章タイトル (64px 時で最大約 672px) でも 7x7 (224px) で
	## 約 21px に収まるため通常は当たらず、当たるような極端な
	## 長文ではそれ未満は判読不能なので切り捨てを許す。
	var nominal := maxi(FX_TEXT_MIN_PX,
		int(FX_TEXT_BASE_PX * size_pct / 100.0))
	if font == null or text.is_empty() or avail_width <= 0.0:
		return nominal
	var w := font.get_string_size(text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, nominal).x
	if w <= avail_width:
		return nominal
	var fitted := maxi(FX_TEXT_MIN_PX, int(nominal * avail_width / w))
	# ヒンティング等で比例計算より僅かに広くなる場合の詰め。
	while fitted > FX_TEXT_MIN_PX and font.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > avail_width:
		fitted -= 1
	return fitted


func _draw_fx_texts(now: float) -> void:
	## 位置スロットごとの文字 (C/L/R/T/B)。サイズは画面固定で
	## 基準 32px に対する %。マップ幅に収まらない長文は全文が
	## 読めるよう縮小する (fx_text_font_size)。フェードイン/
	## アウトは各 0.2 秒。
	if _fx_texts.is_empty() or label_font == null:
		return
	var mrect := drawn_map_rect()
	for pos in _fx_texts.keys():
		var entry: Dictionary = _fx_texts[pos]
		var started := float(entry.get("started", 0.0))
		var until := float(entry.get("until", 0.0))
		var alpha := clampf((now - started) / 0.2, 0.0, 1.0)
		if until > 0.0:
			alpha = minf(alpha, clampf((until - now) / 0.2, 0.0, 1.0))
		if alpha <= 0.0:
			continue
		var text := str(entry.get("text", ""))
		var width := mrect.size.x - (16.0 if pos in ["L", "R"] else 0.0)
		var font_size := fx_text_font_size(label_font, text,
			int(entry.get("size", 100)), width)
		var ascent := label_font.get_ascent(font_size)
		var baseline := 0.0
		var origin_x := mrect.position.x
		var align := HORIZONTAL_ALIGNMENT_CENTER
		match pos:
			"C":
				baseline = mrect.get_center().y + ascent * 0.5
			"T":
				baseline = mrect.position.y + 8.0 + ascent
			"B":
				baseline = mrect.end.y - 8.0
			"L":
				baseline = mrect.get_center().y + ascent * 0.5
				origin_x = mrect.position.x + 8.0
				align = HORIZONTAL_ALIGNMENT_LEFT
			"R":
				baseline = mrect.get_center().y + ascent * 0.5
				align = HORIZONTAL_ALIGNMENT_RIGHT
			_:
				baseline = mrect.get_center().y + ascent * 0.5
		draw_string(label_font, Vector2(origin_x, baseline), text,
			align, width, font_size, Color(1, 1, 1, alpha))


func _draw_fx_wipe(now: float) -> void:
	## ワイプ (1 秒固定)。on = 覆う方向、off = 逆再生で開く方向。
	## on の完了状態は off が来るまで保持する。
	var p := clampf((now - float(_fx_wipe.get("started", 0.0))) / 1.0, 0.0, 1.0)
	var c := p if str(_fx_wipe.get("dir", "on")) == "on" else 1.0 - p
	if c <= 0.0:
		return
	var black := Color(0, 0, 0, 1)
	var center := size * 0.5
	match str(_fx_wipe.get("pattern", "C")):
		"L":
			draw_rect(Rect2(0, 0, size.x * c, size.y), black)
		"R":
			draw_rect(Rect2(size.x * (1.0 - c), 0, size.x * c, size.y), black)
		"O":
			# 外周から: 中央の四角い穴が閉じていく。
			var hole := (1.0 - c) * maxf(size.x, size.y) * 1.42
			var hx := center.x - hole * 0.5
			var hy := center.y - hole * 0.5
			draw_rect(Rect2(0, 0, size.x, hy), black)
			draw_rect(Rect2(0, hy + hole, size.x, size.y - hy - hole), black)
			draw_rect(Rect2(0, hy, hx, hole), black)
			draw_rect(Rect2(hx + hole, hy, size.x - hx - hole, hole), black)
		"S":
			# 渦巻き: 中心から回りながら広がる扇の掃引で近似する。
			if c >= 0.999:
				draw_rect(Rect2(Vector2.ZERO, size), black)
			else:
				var radius := center.length()
				var sweep := c * TAU * 2.0
				var steps := maxi(4, int(sweep / 0.1))
				for i in steps:
					var a0 := sweep * float(i) / float(steps)
					var a1 := sweep * float(i + 1) / float(steps)
					var pts := PackedVector2Array([center,
						center + Vector2(cos(a0), sin(a0)) * radius,
						center + Vector2(cos(a1), sin(a1)) * radius])
					draw_colored_polygon(pts, black)
		_:
			# "C": 中央から円が広がる。
			draw_circle(center, center.length() * c, black)


func _draw_fx_aura(ch: Dictionary, dx: int, z: float, po := Vector2.ZERO) -> void:
	## バフの共通オーラ (キャラの下に敷く)。バフが 1 つでも
	## 有効なら点灯し、パルスする。
	if _fx_icons_tex == null:
		return
	var cn := int(ch.get("cn", 0))
	if not PhiCharaState.fx_has_buff(cn):
		return
	var pulse := 0.5 + 0.25 * sin(_now() * 3.0)
	var ix := (int(ch.get("x", 0)) * CHIP_SIZE + dx - 4) * z + po.x
	var iy := (int(ch.get("y", 0)) * CHIP_SIZE + 5 - 4) * z + po.y
	draw_texture_rect_region(_fx_icons_tex,
		Rect2(ix, iy, 40.0 * z, 40.0 * z),
		Rect2(PhiCharaState.FX_AURA_CELL * 32, 0, 32, 32),
		Color(1, 1, 1, pulse))


func _draw_fx_icons(ch: Dictionary, dx: int, z: float, po := Vector2.ZERO) -> void:
	## 状態異常・バフのアイコン (キャラの頭上に横並び、最大6個)。
	if _fx_icons_tex == null:
		return
	var icons := PhiCharaState.fx_icons_for(int(ch.get("cn", 0)))
	if icons.is_empty():
		return
	var n := mini(icons.size(), 6)
	var cell_px := 16.0
	var base_x := int(ch.get("x", 0)) * CHIP_SIZE + dx + CHIP_SIZE * 0.5 - n * cell_px * 0.5
	var base_y := int(ch.get("y", 0)) * CHIP_SIZE + 5 - 18
	for i in n:
		draw_texture_rect_region(_fx_icons_tex,
			Rect2((base_x + i * cell_px) * z + po.x, base_y * z + po.y,
				cell_px * z, cell_px * z),
			Rect2(int(icons[i]) * 32, 0, 32, 32))


func _draw_labels(chars: Array, dim: int, z: float) -> void:
	# キャラ名は太字で、背景に半透明のマスクを敷いて読めるようにする
	# (ユーザーの指定)。
	var name_font: Font = bold_font if bold_font != null else label_font
	if name_font == null:
		return
	var cx := dim / 2
	var cy := dim / 2
	var per_cell := {}
	var big_cells := {}
	for ch in chars:
		var x := int(ch.get("x", -1))
		var y := int(ch.get("y", -1))
		if not (0 <= x and x < dim and 0 <= y and y < dim):
			continue
		if x == cx and y == cy:
			continue
		var chara_name := PhiTags.strip_tags(str(ch.get("name", ""))).strip_edges()
		if chara_name.is_empty():
			continue
		per_cell[Vector2i(x, y)] = chara_name
		if is_big(ch.get("gigant")):
			big_cells[Vector2i(x, y)] = true
	var font_size := PhiFont.ui_size_for_zoom(int(z))
	var mask := _name_mask_style(z)
	var lcells: Array = _event.get("cells", [])
	for cell_key in per_cell:
		var cell_pos: Vector2i = cell_key
		var chara_name: String = per_cell[cell_key]
		# 2x2 の敵は名前を 2 マス分の中心に置く。
		var center_off := CHIP_SIZE / 2 if big_cells.has(cell_key) else 0
		var x := (cell_pos.x * CHIP_SIZE + CHIP_SIZE / 2 + center_off) * z
		var y := (cell_pos.y * CHIP_SIZE + int(CHIP_SIZE * 0.6) + MAP_TOP
			+ relief_offset_y(lcells, dim, cell_pos.x, cell_pos.y)) * z
		var ts := name_font.get_string_size(chara_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var pos := Vector2(x - ts.x / 2.0, y + name_font.get_ascent(font_size))
		var pad_x := 5.0 * z
		var pad_y := 1.5 * z
		var ascent := name_font.get_ascent(font_size)
		var descent := name_font.get_descent(font_size)
		draw_style_box(mask, Rect2(
			pos.x - pad_x, pos.y - ascent - pad_y,
			ts.x + pad_x * 2.0, ascent + descent + pad_y * 2.0))
		draw_string(name_font, pos, chara_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


var _name_mask: StyleBoxFlat = null


func _name_mask_style(z: float) -> StyleBoxFlat:
	## キャラ名の背景マスク (半透明の黒、角丸)。
	if _name_mask == null:
		_name_mask = StyleBoxFlat.new()
		_name_mask.bg_color = Color(0, 0, 0, 0.45)
	_name_mask.set_corner_radius_all(maxi(2, int(3.0 * z)))
	return _name_mask


# -- 戦闘の演出 ---------------------------------------------------------------

func _process(_delta: float) -> void:
	# 拡大の追いかけ: 期限までは、収まる余地がある時に要求を
	# 出し直して1段階ずつ収まる倍率へ近づける。
	if _now() <= _grow_drive_until and size.x >= 1.0 and size.y >= 1.0:
		var gdim := grid_dim(int(_event.get("size", 7)))
		var gfit := clampi(mini(int(size.x / (gdim * CHIP_SIZE)), int(size.y / (gdim * CHIP_SIZE + MAP_TOP))), 1, 8)
		if gfit > zoom:
			_grow_requested = true
			_update_zoom()
	# キャラの歩行アニメーション: 500ms ごとにフレームを切り替え、
	# 地図が表示中なら描き直す (Python 版の _anim_tick と同じ)。
	# 切断中は切り替えない (止まって見えるようにする)。
	if _session_live and not _event.is_empty() and is_visible_in_tree():
		var frame := int(_now() * 2.0) % 2
		if frame != _anim_frame:
			_anim_frame = frame
			queue_redraw()
	# 滑らかスクロールを進める (第64段)。補間時間は到着
	# 間隔に適応した _scroll_duration を使う (第128段)。
	if _scroll_t < 1.0:
		_scroll_t = minf(1.0, _scroll_t + _delta / _scroll_duration)
		queue_redraw()
	if _floats.is_empty() and _flashes.is_empty() and _swings.is_empty() and _slashes.is_empty() and _bolts.is_empty() and _impacts.is_empty() and _casts.is_empty() and _ghosts.is_empty() and _bubbles.is_empty() and _disp_magics.is_empty() and not _shake_active and not _fx_any_active():
		return
	_expire_effects()
	queue_redraw()


func _expire_effects() -> void:
	var now := _now()
	_floats = _floats.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < FLOAT_DURATION)
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < FLASH_STEP * FLASH_STEPS)
	_swings = _swings.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < SWING_FRAME * SWING_FRAMES)
	_slashes = _slashes.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < SLASH_FRAME * SLASH_FRAMES)
	var kept_bolts: Array = []
	for b in _bolts:
		if now - float(b["spawned"]) >= BOLT_STEP * BOLT_STEPS:
			_impacts.append({"center": b["end"], "spawned": now})
		else:
			kept_bolts.append(b)
	_bolts = kept_bolts
	_impacts = _impacts.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < IMPACT_FRAME * IMPACT_FRAMES)
	_casts = _casts.filter(func(f: Dictionary) -> bool: return now - float(f["spawned"]) < CAST_DURATION)
	_ghosts = _ghosts.filter(func(g: Dictionary) -> bool: return int((now - float(g["spawned"])) / GHOST_STEP) < GHOST_STEPS)
	_disp_magics = _disp_magics.filter(func(d: Dictionary) -> bool: return now - float(d["spawned"]) < DISP_MAGIC_PHASE * DISP_MAGIC_PHASES)
	_recent_disp_hits = _recent_disp_hits.filter(func(h: Dictionary) -> bool: return now - float(h["spawned"]) < DISP_MAGIC_SUPPRESS_WINDOW)
	for speaker in _bubbles.keys():
		var kept: Array = []
		for entry in _bubbles[speaker]:
			if now < float(entry["expire"]):
				kept.append(entry)
		if kept.is_empty():
			_bubbles.erase(speaker)
		else:
			_bubbles[speaker] = kept
	if _shake_active and now - _shake_started >= SHAKE_STEP * SHAKE_PATTERN.size():
		_shake_active = false


func _shake_offset(z: float) -> Vector2:
	var off := Vector2.ZERO
	if _shake_active:
		var step := int((_now() - _shake_started) / SHAKE_STEP)
		if step < SHAKE_PATTERN.size():
			off = SHAKE_PATTERN[step] * z
	# FX の画面振動 (終了時刻まで、振幅はズーム 1.0 時の px)。
	var now := _now()
	if now < _fx_shake_until and _fx_shake_amp > 0.0:
		off += Vector2(sin(now * 91.0), cos(now * 113.0)) * _fx_shake_amp * z
	return off


func _float_position(target: Variant) -> Variant:
	## フロートを出す位置(地図の絵の中の座標)を決めます。
	if target == null or str(target) == player_name or target == "あなた" or target == "自分":
		return _center_anchor
	return _anchors.get(str(target))


static func _sprite_center(anchor: Vector2) -> Vector2:
	## キャラの絵の中心を、地図の絵の中の座標で返します。
	return Vector2(anchor.x, anchor.y + 16.0)


func spawn_floats(text: String) -> void:
	## ログの行から数字を抜き、地図に浮かべます。
	var now := _now()
	for line in text.split("\n"):
		for ev in PhiFloatText.parse_floats(line):
			var pos: Variant = _float_position(ev["target"])
			if pos == null:
				continue
			_float_seq += 1
			var kind: String = ev["kind"]
			# 攻撃の数字でも、自分が受けた時は赤にします
			if kind == "dealt" and _center_anchor != null and pos == _center_anchor:
				kind = "taken"
			var label := "+%d" % int(ev["amount"]) if kind in ["heal", "mp"] else str(ev["amount"])
			_floats.append({
				"pos": pos, "label": label, "color": FLOAT_COLORS[kind],
				"xoff": float((_float_seq % 3) - 1) * 4.0, "spawned": now,
			})
			if kind in ["dealt", "taken", "mpdmg"]:
				_flashes.append({"pos": pos, "color": _flash_color(kind), "spawned": now})
				if kind == "taken":
					_shake_active = true
					_shake_started = now


static func _flash_color(kind: String) -> Color:
	match kind:
		"taken":
			return Color(1.0, 0.322, 0.322)
		"mpdmg":
			return MAGIC_COLOR
	return Color.WHITE


func spawn_combat_fx(text: String) -> void:
	## 戦闘の演出を出します。詠唱の行は、魔法の見分けに覚えます。
	var now := _now()
	for line in text.split("\n"):
		var chant: Variant = PhiCombatFx.parse_chant(line)
		if chant != null:
			_caster_tracker.note(chant, now)
			continue
		if PhiCombatFx.parse_chant_stop(line):
			_caster_tracker.clear(player_name)
			continue
		var attack: Variant = PhiCombatFx.parse_attack(line)
		if attack != null:
			_combat_fx(attack, now)


func _combat_fx(attack: Dictionary, now: float) -> void:
	## 攻撃1回に、斬撃の軌跡か魔法の演出を出します。
	## 魔法の発動は常に術師の周りの円状オーラ。魔法弾は
	## 「魔法表示」が ON の時だけ、対象へ飛ばします。
	var target_pos: Variant = _float_position(attack["target"])
	if target_pos == null:
		return
	if _caster_tracker.consume(str(attack["attacker"]), now):
		# サーバー駆動の魔法表示が同じマスを直前に出した時は、
		# 自前の演出も出さない(Philly の表示と二重になるため)。
		if _disp_magic_covers_target(str(attack["target"]), now):
			return
		var attacker_pos: Variant = _float_position(attack["attacker"])
		if attacker_pos != null:
			_casts.append({"center": _sprite_center(attacker_pos), "spawned": now})
			if magic_bolt:
				if attacker_pos != target_pos:
					_bolts.append({"start": _sprite_center(attacker_pos), "end": _sprite_center(target_pos), "spawned": now})
				else:
					_impacts.append({"center": _sprite_center(target_pos), "spawned": now})
	else:
		var attacker_pos2: Variant = _float_position(attack["attacker"])
		if attacker_pos2 != null:
			_swings.append({"from": _sprite_center(attacker_pos2), "to": _sprite_center(target_pos), "spawned": now})
		else:
			# 攻撃する人が見えなければ、対象に軌跡だけ出します
			_slashes.append({"center": _sprite_center(target_pos), "spawned": now})


func spawn_disp_magic(data: Dictionary) -> void:
	## `#ex-disp-magic` の表示を出す(第3段)。終点のマスを覚え、
	## 直後の自前の演出を抑えるのにも使う。
	## 発動タイル (魔法陣) は描かず、代わりに術師の位置へ
	## 円状オーラを出す (ユーザーの指定、設定によらず差し替え)。
	var now := _now()
	_disp_magics.append({"data": data, "spawned": now})
	var end: Dictionary = data["end"]
	_recent_disp_hits.append({"cell": Vector2i(int(end["x"]), int(end["y"])), "spawned": now})
	for c in PhiDispMagic.phase_cells(data, 0):
		if int(c[1]) == PhiDispMagic.CELL_CAST:
			var at: Vector2 = c[0]
			_casts.append({"center": at + Vector2(16.0, 16.0), "spawned": now})
	queue_redraw()


func _disp_magic_covers_target(target: String, now: float) -> bool:
	## 対象のいるマスを、サーバー駆動の魔法表示が最近出したか。
	var cell := Vector2i(-1, -1)
	var dim := grid_dim(int(_event.get("size", 7)))
	if target == player_name or target == "あなた" or target == "自分":
		cell = Vector2i(dim / 2, dim / 2)
	else:
		var ch: Variant = _last_charas.get(target)
		if ch == null:
			return false
		cell = Vector2i(int(ch.get("x", -1)), int(ch.get("y", -1)))
	return PhiDispMagic.bolt_suppressed(_recent_disp_hits, cell, now, DISP_MAGIC_SUPPRESS_WINDOW)


func _draw_disp_magic(dm: Dictionary, z: float, now: float) -> void:
	var age := now - float(dm["spawned"])
	var phase := int(age / DISP_MAGIC_PHASE)
	if phase >= DISP_MAGIC_PHASES:
		return
	var cells := PhiDispMagic.phase_cells(dm["data"], phase)
	for c in cells:
		var at: Vector2 = c[0]
		var cell: int = c[1]
		if cell == PhiDispMagic.CELL_CAST:
			# 魔法陣は出さない (発動は円状オーラに差し替え済み)。
			continue
		if _items_tex != null and cell * 32 + 32 <= _items_tex.get_width():
			draw_texture_rect_region(_items_tex, Rect2(at.x * z, at.y * z, 32.0 * z, 32.0 * z), Rect2(cell * 32, 0, 32, 32))
		else:
			draw_circle(Vector2(at.x + 16.0, at.y + 16.0) * z, 12.0 * z, Color(0.4, 0.8, 1.0, 0.7))


func spawn_death_fx(text: String) -> void:
	## 死亡の行から、倒れたキャラのゆっくり消える演出を出します。
	var victim: Variant = PhiCombatFx.parse_kill(text)
	if victim == null:
		return
	if victim == "あなた" and not player_name.is_empty():
		victim = player_name
	var ch: Variant = _last_charas.get(victim)
	if ch == null:
		ch = _prev_charas.get(victim)
	if ch == null or assets == null:
		return
	var tex: Variant = assets.chara(str(ch.get("name", "")), str(ch.get("gra", "")), int(ch.get("default", 0)))
	if tex == null:
		return
	_ghosts = _ghosts.filter(func(g: Dictionary) -> bool: return g["name"] != victim)
	_ghosts.append({"name": victim, "chara": ch, "tex": tex, "spawned": _now()})
	queue_redraw()


func show_log_bubble(raw_text: String, plain: String) -> void:
	## NPCの発言や action の行、台詞行、オブジェの発言を、
	## 吹き出しで出します。
	var names: Array = _anchors.keys()
	if not player_name.is_empty():
		names.append(player_name)
	var found: Variant = null
	if "/*act*/" in raw_text:
		found = PhiBubbles.bubble_from_action_line(plain, names)
	if found == null:
		found = PhiBubbles.bubble_from_log_line(plain, names)
	if found == null:
		# 地図に居ない話し手 (人形オブジェ) の 名前 > 本文 の行。
		# 正面のマスの基準点に吹き出しを付ける。
		found = PhiBubbles.bubble_from_object_speech_line(plain)
		if found != null:
			if _faced_anchor == null:
				found = null
			else:
				_dialogue_anchors[str(found[0])] = _faced_anchor
	if found == null:
		# Metro 表記の台詞行 (DM > 名前「台詞」)。話し手が地図に
		# 居ればその基準点、居なければ (人形オブジェ) 正面の
		# マスの基準点に吹き出しを付ける。
		found = PhiBubbles.bubble_from_dialogue_line(plain)
		if found != null and not (str(found[0]) in names):
			if _faced_anchor == null:
				found = null
			else:
				_dialogue_anchors[str(found[0])] = _faced_anchor
	if found != null:
		show_bubble(found[0], found[1])


func _bubble_position(speaker: String) -> Variant:
	## 吹き出しを出す位置 (地図の絵の中の座標)。キャラの基準点が
	## 無ければ、台詞行やオブジェの発言で覚えた正面マスの基準点を
	## 使う。
	var pos: Variant = _float_position(speaker)
	if pos != null:
		return pos
	return _dialogue_anchors.get(speaker)


func show_bubble(speaker: String, body: String) -> void:
	## 話し手の頭の上に、発言の吹き出しを出します。同じ話し手の
	## 前の文は消さずに上に積んで残し、それぞれ自分の表示時間を
	## 全うします。同じ文の繰り返しは、寿命だけ延ばします。
	var ms := minf(BUBBLE_MAX_MS, BUBBLE_BASE_MS + BUBBLE_PER_CHAR_MS * body.length())
	var entry := {"text": body, "expire": _now() + ms / 1000.0}
	var stack: Array = _bubbles.get(speaker, [])
	if not stack.is_empty() and str(stack[stack.size() - 1].get("text", "")) == body:
		stack[stack.size() - 1] = entry
	else:
		stack.append(entry)
		while stack.size() > BUBBLE_STACK_MAX:
			stack.pop_front()
	_bubbles[speaker] = stack
	queue_redraw()


func _draw_ghosts(row: int, dim: int, z: float) -> void:
	if _ghosts.is_empty():
		return
	var now := _now()
	for g in _ghosts:
		var gch: Dictionary = g["chara"]
		if int(gch.get("y", -1)) != row:
			continue
		var gx := int(gch.get("x", -1))
		if not (0 <= gx and gx < dim):
			continue
		# 描き直しが重くても、壁時計どおりの速さで薄くします
		var step := int((now - float(g["spawned"])) / GHOST_STEP)
		if step >= GHOST_STEPS:
			continue
		var alpha := 1.0 - float(step) / GHOST_STEPS
		var gcells: Array = _event.get("cells", [])
		var gdy := float(relief_offset_y(gcells, dim, gx, int(gch.get("y", 0))))
		_draw_chara(gch, 0, z, g["tex"], Color(1, 1, 1, alpha), Vector2(0.0, gdy * z))


func _draw_effects(dim: int, z: float) -> void:
	var now := _now()
	for f in _flashes:
		_draw_flash(f, z, now)
	for s in _swings:
		_draw_swing(s, z, now)
	for s in _slashes:
		_draw_slash(s, z, now)
	for b in _bolts:
		_draw_bolt(b, z, now)
	for im in _impacts:
		_draw_impact(im, z, now)
	for im in _casts:
		_draw_cast(im, z, now)
	for dm in _disp_magics:
		_draw_disp_magic(dm, z, now)
	for f in _floats:
		_draw_float(f, z, now)
	_draw_bubbles(dim, z)


func _draw_flash(f: Dictionary, z: float, now: float) -> void:
	var step := int((now - float(f["spawned"])) / FLASH_STEP)
	if step >= FLASH_STEPS or step % 2 == 1:
		return
	var pos: Vector2 = f["pos"]
	var c: Color = f["color"]
	# stipple の代わりに、半透明で塗ります
	draw_rect(Rect2((pos.x - 16.0) * z, pos.y * z, 32.0 * z, 32.0 * z), Color(c.r, c.g, c.b, 0.5))


func _draw_swing(s: Dictionary, z: float, now: float) -> void:
	## 攻撃する人から、対象の向きへ斬撃の軌跡を走らせます。
	var step := int((now - float(s["spawned"])) / SWING_FRAME)
	if step >= SWING_FRAMES:
		return
	var from_c: Vector2 = s["from"]
	var to_c: Vector2 = s["to"]
	var facing := -PI / 2.0
	if to_c != from_c:
		facing = atan2(to_c.y - from_c.y, to_c.x - from_c.x)
	# 軌跡の中心は、体の中心から対象の向きへ少し寄せます
	var pivot := from_c + Vector2(6.0 * cos(facing), 6.0 * sin(facing))
	var start := facing + SWING_START
	var front := start + SWING_SWEEP * step / float(SWING_FRAMES - 1)
	var px := pivot.x * z
	var py := pivot.y * z
	for i in SWING_STREAKS.size():
		var st: Array = SWING_STREAKS[i]
		var end := maxf(front - float(st[1]), start + 0.12)
		var pts := PhiCombatFx.streak_points(px, py, z, float(st[0]), start, end, float(st[2]))
		var color_step := mini(step + (0 if i == 0 else 1), SWING_FRAMES - 1)
		draw_colored_polygon(pts, SWING_COLORS[color_step])


func _draw_slash(s: Dictionary, z: float, now: float) -> void:
	## 対象のキャラに、剣の軌跡を重ねます。
	var step := int((now - float(s["spawned"])) / SLASH_FRAME)
	if step >= SLASH_FRAMES:
		return
	var c: Vector2 = s["center"]
	var cx := c.x * z
	var cy := c.y * z
	var scale := pow(1.04, step)
	var main := PhiCombatFx.slash_points(cx, cy, z)
	var echo := PhiCombatFx.slash_points(cx + 3.0 * z, cy - 3.0 * z, z, 0.7)
	draw_colored_polygon(_scaled_points(main, cx, cy, scale), SLASH_COLORS[step])
	draw_colored_polygon(_scaled_points(echo, cx, cy, scale), SLASH_COLORS[mini(step + 1, SLASH_FRAMES - 1)])


static func _scaled_points(pts: PackedVector2Array, cx: float, cy: float, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(cx + (p.x - cx) * scale, cy + (p.y - cy) * scale))
	return out


func _draw_cast(im: Dictionary, z: float, now: float) -> void:
	## 魔法の発動アニメーション。術師を中心に、円状の波が
	## 同心円に広がり、広がるにつれて薄れて消えます。
	## 中心の閃光、少しずつ遅れて広がるリング3重、円周上を
	## 外へ流れる火花で組みます。対象側には何も出しません。
	var age := now - float(im["spawned"])
	if age < 0.0 or age >= CAST_DURATION:
		return
	var t := age / CAST_DURATION
	var c: Vector2 = im["center"]
	var center := Vector2(c.x * z, c.y * z)
	var base: Color = CAST_COLORS[mini(int(t * CAST_COLORS.size()), CAST_COLORS.size() - 1)]
	# 波の本体: 先行する輪の内側を、薄い色で満たします。
	var lead := _cast_ring_progress(age, 0)
	if lead > 0.0:
		var body := Color(base.r, base.g, base.b, 0.16 * (1.0 - lead))
		draw_circle(center, _cast_ring_radius(lead) * z, body)
	# 中心の閃光: 最初に強く光り、縮みながら消えます。
	var flash_a := pow(1.0 - t, 1.5)
	if flash_a > 0.01:
		var halo := Color(base.r, base.g, base.b, 0.55 * flash_a)
		draw_circle(center, lerpf(15.0, 7.0, t) * z, halo)
		draw_circle(center, lerpf(9.0, 4.0, t) * z, Color(1, 1, 1, 0.9 * flash_a))
	# リング: 遅れて出る輪ほど、遅れて広がり遅れて消えます。
	for i in CAST_RING_COUNT:
		var p := _cast_ring_progress(age, i)
		if p <= 0.0 or p >= 1.0:
			continue
		var ring := Color(base.r, base.g, base.b, 0.95 * (1.0 - p))
		var width := maxf(1.0, lerpf(3.2, 1.2, p) * z)
		draw_arc(center, _cast_ring_radius(p) * z, 0.0, TAU, 64, ring, width, true)
	# 円周の火花: 先行する輪の円周上に乗り、外を向いて流れます。
	if lead > 0.0 and lead < 1.0:
		var spark := Color(base.r, base.g, base.b, 0.9 * (1.0 - lead))
		var r := _cast_ring_radius(lead) * z
		for i in CAST_SPARKS:
			var angle := i * TAU / CAST_SPARKS + age * 1.2
			var sx := center.x + r * cos(angle)
			var sy := center.y + r * sin(angle)
			var len := lerpf(7.0, 3.0, lead)
			draw_colored_polygon(PhiCombatFx.radial_spark_points(sx, sy, z, angle, len, 1.2), spark)


static func _cast_ring_progress(age: float, index: int) -> float:
	## リング index の進み具合 (0..1)。後の輪ほど遅れて始まり、
	## 残りの時間で広がり切ります。
	var start := CAST_RING_DELAY * float(index)
	if age <= start:
		return 0.0
	return clampf((age - start) / (CAST_DURATION - start), 0.0, 1.0)


static func _cast_ring_radius(progress: float) -> float:
	## 輪の半径。最初は速く、広がるにつれてゆるやかに (ease-out)。
	var p := clampf(progress, 0.0, 1.0)
	return lerpf(4.0, CAST_RING_MAX_R, 1.0 - (1.0 - p) * (1.0 - p))


func _draw_bolt(b: Dictionary, z: float, now: float) -> void:
	## 術師から対象へ、尾を引く魔法弾を飛ばします。
	var step := int((now - float(b["spawned"])) / BOLT_STEP)
	if step >= BOLT_STEPS:
		return
	var start: Vector2 = b["start"]
	var end: Vector2 = b["end"]
	var x0 := start.x * z
	var y0 := start.y * z
	var x1 := end.x * z
	var y1 := end.y * z
	var dx := (x1 - x0) / BOLT_STEPS
	var dy := (y1 - y0) / BOLT_STEPS
	var hx := x0 + dx * (step + 1)
	var hy := y0 + dy * (step + 1)
	var dist := Vector2(dx, dy).length()
	var ux := 1.0
	var uy := 0.0
	if dist > 0.000001:
		ux = dx / dist
		uy = dy / dist
	# 尾は、進んだ分だけ後ろへ伸ばし、長さに上限を付けます
	var traveled := Vector2(hx - x0, hy - y0).length()
	var tail_len := minf(traveled, BOLT_TAIL_LEN * z)
	var tx := hx - ux * tail_len
	var ty := hy - uy * tail_len
	draw_colored_polygon(PhiCombatFx.comet_tail_points(hx, hy, tx, ty, z, BOLT_TAIL_WIDTH), BOLT_COLOR)
	var inner_len := tail_len * 0.55
	draw_colored_polygon(PhiCombatFx.comet_tail_points(hx, hy, hx - ux * inner_len, hy - uy * inner_len, z, BOLT_TAIL_WIDTH * 0.45), Color.WHITE)
	draw_circle(Vector2(hx, hy), 5.0 * z, BOLT_COLOR)
	draw_circle(Vector2(hx, hy), 2.0 * z, Color.WHITE)
	# 火花は、弾の周りを回ります
	var phases := [0.0, PI]
	var spark_colors := [Color.WHITE, Color(0.702, 0.898, 0.988)]
	for i in 2:
		var angle: float = step * BOLT_ORBIT_STEP + phases[i]
		var sx := hx + BOLT_ORBIT_R * z * cos(angle)
		var sy := hy + BOLT_ORBIT_R * z * sin(angle)
		draw_circle(Vector2(sx, sy), 1.5 * z, spark_colors[i])


func _draw_impact(im: Dictionary, z: float, now: float) -> void:
	## 着弾の閃光をしぼめ、輪を広げ、火花を散らして消します。
	var step := int((now - float(im["spawned"])) / IMPACT_FRAME)
	if step >= IMPACT_FRAMES:
		return
	var c: Vector2 = im["center"]
	var cx := c.x * z
	var cy := c.y * z
	var color: Color = IMPACT_COLORS[step]
	if step < 3:
		var r := (9.0 - 2.0 * step) * z
		draw_circle(Vector2(cx, cy), r, color)
	var r1 := (4.0 + 4.0 * step) * z
	var width1 := maxf(1.0, 2.0 * z - floorf(step * z / 2.0))
	draw_arc(Vector2(cx, cy), r1, 0.0, TAU, 64, color, width1, true)
	if step >= 1:
		var r2 := (4.0 + 3.0 * (step - 1)) * z
		draw_arc(Vector2(cx, cy), r2, 0.0, TAU, 64, color, z, true)
	for i in IMPACT_SPARKS:
		var angle := i * PI * 2.0 / IMPACT_SPARKS
		draw_colored_polygon(PhiCombatFx.radial_spark_points(cx, cy, z, angle, 6.0 + 3.0 * step, 1.2), color)


func _draw_float(f: Dictionary, z: float, now: float) -> void:
	if label_font == null:
		return
	var age := now - float(f["spawned"])
	if age >= FLOAT_DURATION:
		return
	var pos: Vector2 = f["pos"]
	var label: String = f["label"]
	# 浮き数字は地図の倍率に比例させる。Python 版の 7pt 相当
	# (28*z/3)より一回り大きくし、読み取りやすくする。
	# 第4段で 12*zoom から 11*zoom に、レイアウト変更で
	# 10*zoom に少しずつ小さくし、全体の2ポイント縮小に合わせて
	# 10*zoom-2 にした。
	var font_size := int(round(10.0 * z)) - 2
	var rise := age * z / 0.03
	var x := pos.x * z + float(f["xoff"]) * z
	var y := pos.y * z + 4.0 * z - rise
	var ts := label_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var bx := x - ts.x / 2.0
	var c: Color = f["color"]
	for off in [Vector2(-z, 0), Vector2(z, 0), Vector2(0, -z), Vector2(0, z)]:
		draw_string(label_font, Vector2(bx, y) + off, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	draw_string(label_font, Vector2(bx, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)


func _draw_bubbles(dim: int, z: float) -> void:
	if label_font == null or _bubbles.is_empty():
		return
	# Tk のポイント数(6pt)をピクセル数に直します(96dpi で ×4/3)。
	var font_size := int(round(8.0 * z)) - 2
	var pad := 4.0 * z
	var map_w := dim * CHIP_SIZE * z
	var max_text := minf(BUBBLE_MAX_WIDTH * z, map_w - 2.0 * pad)
	if max_text <= 0.0:
		return
	var line_height := label_font.get_height(font_size)
	var ascent := label_font.get_ascent(font_size)
	var occupied: Array = []
	for speaker in _bubbles:
		var pos: Variant = _bubble_position(speaker)
		if pos == null:
			continue
		var measure := func(t: String) -> float:
			return label_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var cx: float = pos.x * z
		var tail_h := 6.0 * z
		var tail_w := 5.0 * z
		# しっぽの先は頭の少し上、箱はその上に置きます
		var tip_y: float = pos.y * z - z
		var stack: Array = _bubbles[speaker]
		# まず各文の大きさを測る (古い順)
		var entries: Array = []
		for item in stack:
			var lines := PhiBubbles.wrap_bubble_lines(str(item["text"]), measure, max_text, BUBBLE_MAX_LINES)
			if lines.is_empty():
				continue
			var text_w := 0.0
			for ln in lines:
				text_w = maxf(text_w, float(measure.call(ln)))
			entries.append({"lines": lines, "w": text_w + 2.0 * pad,
				"h": line_height * lines.size() + 2.0 * pad})
		if entries.is_empty():
			continue
		var gap := 2.0 * z
		var total_h := 0.0
		var max_w := 0.0
		for e in entries:
			total_h += float(e["h"])
			max_w = maxf(max_w, float(e["w"]))
		total_h += gap * float(entries.size() - 1)
		# 積み上げ全体の置き場所。基本は一番新しい文の箱が頭の上に
		# 来る位置。画面の上に収まらない時は、全体を下へずらして
		# 全ての文が見えるようにする (古い文が上に潰れない)。
		var bottom_y := tip_y - tail_h
		var top_y := bottom_y - total_h
		var shifted := false
		if top_y < 0.0:
			top_y = 0.0
			bottom_y = top_y + total_h
			shifted = true
		var stack_x := clampf(cx - max_w / 2.0, 0.0, maxf(map_w - max_w, 0.0))
		# 他の話し手の吹き出しと重なっていたら、上へずらす
		for occ in occupied:
			if stack_x < float(occ[0]) + float(occ[2]) and float(occ[0]) < stack_x + max_w \
					and top_y < float(occ[1]) + float(occ[3]) and float(occ[1]) < bottom_y:
				var new_top := float(occ[1]) - gap - total_h
				if new_top >= 0.0:
					top_y = new_top
					bottom_y = top_y + total_h
					shifted = true
		var y := top_y
		for ei in entries.size():
			var e: Dictionary = entries[ei]
			var w: float = e["w"]
			var h: float = e["h"]
			var lines: Array = e["lines"]
			var is_newest := ei == entries.size() - 1
			var x0 := clampf(cx - w / 2.0, 0.0, maxf(map_w - w, 0.0))
			var y0 := y
			var y1 := y0 + h
			var stacked := not is_newest or shifted
			var tip_x := minf(maxf(cx, x0 + 1.0), x0 + w - 1.0)
			var base_x := minf(maxf(cx, x0 + tail_w), x0 + w - tail_w)
			# 上にずらした時は、しっぽは短く下向きにだけ出します
			var tail_tip_y := y1 + tail_h if stacked else tip_y
			var outline := PhiBubbles.bubble_outline(x0, y0, x0 + w, y1, 6.0 * z, base_x, tail_w, tip_x, tail_tip_y)
			draw_colored_polygon(outline, Color.WHITE)
			var border := PackedVector2Array(outline)
			border.append(outline[0])
			draw_polyline(border, Color.BLACK, z, true)
			for li in lines.size():
				var by := y0 + pad + ascent + li * line_height
				draw_string(label_font, Vector2(x0 + pad, by), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
			y = y1 + gap
		occupied.append([stack_x, top_y, max_w, total_h + tail_h])
