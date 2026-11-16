class_name PhiCharacter
extends VBoxContainer
## 1キャラ分の画面と接続。タブ1つに1つ(第4段)。
##
## 中段は2列。左列は世界名ヘッダー・地図・状態パネル、
## 右列はログ・入力欄。コンパスは地図の右下に浮かせる。
## 2列の境目はドラッグで動かせる(比率で保持)。
## 入力履歴・ログの記録も持つ。タブを切り替えても、ここに
## あるものはそのタブのものとして保たれる。
##
## 全体にかかるもの(メニュー・タブ行・ダイアログ類・
## priv ウィンドウ・画像窓)はメイン画面が持ち、シグナルで
## やり取りする。ツールバーはこのタブの地図の上に浮く
## パネルとして持ち、ボタンを押すとシグナルでメイン画面に
## 渡して実行してもらう。

signal title_changed(title: String)
signal unread_changed(unread: bool)
signal connection_changed(open: bool)
signal zoom_changed(zoom: int)
signal users_changed
signal priv_received(plain: String)
signal loud_confirm_requested(text: String, party: bool)
signal action_requested(action_name: String)
signal bgm_changed

## 第2段: 移動の繰り返し(Philly classMoveCommand)。
const REPEAT_START_MS := 200
const REPEAT_FALLBACK_MS := 500
const REPEAT_MIN_INTERVAL_MS := 120
## ログの記録の上限(コピー・自動保存の元)。超えたら古い方から捨てる。
const MAX_LOG_LINES := 2000
## ログの最小の高さ。入力欄を広げても、この高さは残す。
const MIN_LOG_HEIGHT := 120
## 世界名ヘッダーの帯の地の色(シルバー)と文字の色。
const WORLD_HEADER_BG := Color(0.75, 0.75, 0.75)
const WORLD_HEADER_FG := Color(0.12, 0.12, 0.12)
## ログ列の上の帯に出す文字と、その色(控えめな灰色)。
const LOG_TOP_TEXT := "Log Window"
const LOG_TOP_FG := Color(0.55, 0.56, 0.60)

## ログ中の URL の色(リンク化、残り項目)。地が暗いスキンでも
## 読める明るい青にする。
const LOG_LINK_COLOR := "5599ff"
## URL の末尾から落とす句読点など(PhiImages と同じ流儀に、
## 和文の句読点を足したもの。本文の「。」がリンクに混ざると
## ブラウザで開けなくなるため)。
const _URL_TAIL_TRIM := ".,;:!?)]}'\"。、！？）」』"
## 画像の参照の記録の上限。
const MAX_IMAGE_REFS := 100

## エフェクトの試し表示(--fx-demo)で吹き出しに出す言葉。
const _FX_DEMO_PHRASES := [
	"こんにちは",
	"いらっしゃい",
	"今日はいい天気だね",
	"一緒に冒険しない？",
	"この先の洞窟には強いモンスターがいるから気をつけてね",
]

var session := PhiSession.new()
var map_view: MapView = null
var log_view: RichTextLabel = null
var input_box: TextEdit = null
## ログと入力欄の上下の分割。境目で入力欄の高さを変える。
var input_split: VSplitContainer = null
## ログ列の上の帯(「Log Window」の見出し)。世界名ヘッダーと
## 同じ高さにして、ログの上端と地図の上端をそろえる。
var _log_top_spacer: Control = null
var status_panel: StatusPanel = null
var split: HSplitContainer = null
## 地図の列の上の、世界名・エリア名の1行ヘッダー。
var world_header: Label = null

## 接続先。空のホストは「まだどこにもつないでいないタブ」。
var host := ""
var port := 0
## タブセッションから復元したキャラ名。ログインするまで題名に使う。
var restored_name := ""
var unread := false

var _assets: GameAssets = null
var _config: PhiConfig = null
var _font: Font = null
var _bold_font: Font = null
var _log_filter: PhiLogFilter = null
var _tag_tree := {}
var _system_color: Variant = null
var _error_color: Variant = null
var _is_active := false
var _was_open := false
var _applied_size := 0

var _player_name := ""
var _world := ""
var _area := ""
var _mapset := ""
var _users: Array[Dictionary] = []
var _priv_history: Array[String] = []
var _log_lines: Array[Dictionary] = []
var _image_refs: Array[Dictionary] = []
var _save_failed := false

## サーバーから通知された BGM のファイル名(第5段。`.mid` 補完済み)。
## 切断で空に戻る。鳴らすかどうかの判断はメイン画面がする。
var bgm_name := ""
## BGM の再生速度(%)(第5段)。
var bgm_speed := 100
## 音の司令塔(全タブ共有)。メイン画面が setup の後に渡す。
var _sound_engine: PhiSoundEngine = null

var _mouse_held := false
var _mouse_hold_cursor := ""
var _mouse_hold_since := 0
var _mouse_last_repeat := 0
var _mouse_last_pos := Vector2.ZERO
var _mouse_cursor_now := ""
var _mouse_turn_dir := ""

var _held_moves: Array[Dictionary] = []
var _held_since := 0
var _last_repeat_send := 0
var _map_dim_now := 0
var _map_style_now := ""
var _loud := false
var _loud_all := false
var _loud_pending := ""
var _loud_pending_party := false
var _suppress_lists := 0
var _list_active := false
var _list_lines: Array[String] = []
## リストのチェック状態(行番号 → true)。ページごとに持ち、
## 新しいリストが来たら消す(残り項目)。
var _list_checks: Dictionary = {}
## 直近のリストのマウス押下がチェック欄の中だったか。
var _list_press_in_check := false
## チェック印のアイコン(実行時に描く。チェックあり・なし)。
static var _check_icon_on: Texture2D = null
static var _check_icon_off: Texture2D = null
var _list_panel: PanelContainer = null
var _list_box: ItemList = null
var _list_header: Label = null
var _list_cancel_button: Button = null
var _list_dragging := false
var _list_drag_offset := Vector2.ZERO
## 入力欄の角丸の地(大声の黄地から戻す時に使う)。
var _input_normal_box: StyleBox = null
var _input_focus_box: StyleBox = null
var _toolbar_panel: PanelContainer = null
var _toolbar_buttons: Array[Button] = []
var _toolbar_dragging := false
var _toolbar_drag_offset := Vector2.ZERO
var _last_command := ""
var _history_boundary := 0
## 追加発言(TalkAdd)。実行中だけの保持で、保存はしない。
var _talk_add := ""
var _tag_popup: PopupMenu = null
var _tag_next_id := 0
var _copy_popup: PopupMenu = null
var _demo_chars: Array = []
var _demo_dim := 7
var _fx_demo_step := 0


func setup(p_assets: GameAssets, p_config: PhiConfig, p_font: Font, p_bold_font: Font, p_log_filter: PhiLogFilter, p_tag_tree: Dictionary) -> void:
	_assets = p_assets
	_config = p_config
	_font = p_font
	_bold_font = p_bold_font
	_log_filter = p_log_filter
	_tag_tree = p_tag_tree
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_apply_log_css()
	session.event_received.connect(_on_event)
	session.session_error.connect(_on_session_error)
	session.session_closed.connect(_on_session_closed)


func set_log_filter(filter: PhiLogFilter) -> void:
	_log_filter = filter


func set_sound_engine(engine: PhiSoundEngine) -> void:
	_sound_engine = engine


func bgm_resolved_path() -> String:
	## 通知された BGM のファイルの場所。見つからなければ ""。
	if bgm_name.is_empty() or _assets == null:
		return ""
	return PhiSoundPaths.resolve_bgm(bgm_name, _assets.philly_roots)


func set_active(active: bool) -> void:
	_is_active = active
	if active:
		set_unread(false)
		if map_view != null:
			map_view.request_zoom_growth()
		# ツールバーの位置は全タブ共通(設定の保持値)にそろえる。
		if _toolbar_panel != null:
			_toolbar_panel.position = _toolbar_home_position()
			_clamp_toolbar_panel()
		_on_split_resized()


func is_active_tab() -> bool:
	return _is_active


func set_unread(value: bool) -> void:
	if unread == value:
		return
	unread = value
	unread_changed.emit(unread)


func tab_title() -> String:
	if not _player_name.is_empty():
		return _player_name
	if not restored_name.is_empty():
		return restored_name
	if not host.is_empty():
		return "%s:%d" % [host, port]
	return "未接続"


func session_state() -> Dictionary:
	return {"host": host, "port": port, "name": _player_name}


func is_session_open() -> bool:
	return session.is_open()


func users() -> Array[Dictionary]:
	return _users.duplicate()


func priv_history() -> Array[String]:
	return _priv_history.duplicate()


func add_priv_history(line: String) -> void:
	_priv_history.append(line)


func log_buffer() -> Array[Dictionary]:
	return _log_lines.duplicate()


func image_refs() -> Array[Dictionary]:
	return _image_refs.duplicate()


func is_loud() -> bool:
	return _loud


func list_active() -> bool:
	return _list_active


func history_boundary() -> int:
	return _history_boundary


func talk_add_text() -> String:
	return _talk_add


func set_talk_add(value: String) -> void:
	## 追加発言を設定する(Philly の EditTalkAdd)。実行中だけの
	## 保持で、設定ファイルには保存しない(Philly も保存しない)。
	## 下書きが空なら、入力欄にも入れてキャレットを末尾に置く
	## (Philly のダイアログの OK と同じ振る舞い)。
	_talk_add = value
	if value.is_empty() or input_box == null:
		return
	_history_boundary = PhiInputHistory.clamp_boundary(input_box.text, _history_boundary)
	if not PhiInputHistory.draft_of(input_box.text, _history_boundary).is_empty():
		return
	_fill_draft_with_talk_add()


func _fill_draft_with_talk_add() -> void:
	## 下書き部分を追加発言で置き換え、キャレットを末尾に置く。
	## 下書きが空の時だけ呼ぶ(境界は動かさない)。
	if _talk_add.is_empty():
		return
	if not input_box.text.is_empty() and not input_box.text.ends_with("\n"):
		input_box.text += "\n"
		_history_boundary = input_box.text.length()
	input_box.text += _talk_add
	var last := maxi(input_box.get_line_count() - 1, 0)
	input_box.set_caret_line(last, true, true, 0, false)
	input_box.set_caret_column(input_box.get_line(last).length())


func _try_talk_add_recall(code: String, shift: bool, ctrl: bool, alt: bool, meta: bool) -> bool:
	## 追加発言の呼び出し(Philly の InputEditKeyDown の VK_DOWN)。
	## 修飾キー無しの ↓ で、キャレットが最終行にあり、その行が
	## 下書きの行なら、行を追加発言で置き換える。扱ったら true。
	if code != "ArrowDown" or shift or ctrl or alt or meta:
		return false
	if _talk_add.is_empty():
		return false
	if input_box.get_caret_line() != input_box.get_line_count() - 1:
		return false
	var text := input_box.text
	var lines := text.split("\n")
	var last_start := text.length() - lines[lines.size() - 1].length()
	if last_start < _history_boundary:
		return false
	input_box.text = text.substr(0, last_start) + _talk_add
	_history_boundary = PhiInputHistory.clamp_boundary(input_box.text, _history_boundary)
	var last := maxi(input_box.get_line_count() - 1, 0)
	input_box.set_caret_line(last, true, true, 0, false)
	input_box.set_caret_column(input_box.get_line(last).length())
	return true


func _process(_delta: float) -> void:
	session.poll()
	var now_open := session.is_open()
	if now_open != _was_open:
		_was_open = now_open
		refresh_toolbar_states()
		connection_changed.emit(now_open)
	_repeat_fallback_tick()
	_mouse_repeat_fallback_tick()


func clear_held_input() -> void:
	_held_moves.clear()
	_mouse_held = false
	_list_dragging = false
	_end_toolbar_drag()
	_mouse_cursor_now = ""
	Input.set_custom_mouse_cursor(null)


func reload_cached_textures() -> void:
	## グラキャッシュ初期化の後、このタブの絵を全部読み直す。
	## 地図のチップ・アイテム・残像・地図のコンパス・状態パネル・
	## マウスカーソルは、それぞれ古いテクスチャを持っているので、
	## 同じ経路で取り直して再描画する。
	if map_view != null:
		map_view.reload_cached_textures()
		map_view.set_compass_texture(_assets.skin_image("Direction"))
	if status_panel != null:
		status_panel.hpmp_tex = _assets.skin_image("HpMpBar")
		status_panel.queue_redraw()
	# 方向カーソルの絵も温めておく。次にマウスが動いた時に
	# 描画中ではなくここで作ったものが出る。
	for cursor_name in PhiMouse.ALL_CURSORS:
		_assets.cursor_texture(cursor_name)
	# ツールバーのアイコンも同じ経路で取り直す。
	for button in _toolbar_buttons:
		var icon: Variant = _assets.button_icon(str(button.get_meta("action")))
		if icon != null:
			button.icon = icon
	_mouse_cursor_now = ""
	Input.set_custom_mouse_cursor(null)


# -- 画面の組み立て ----------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 4)
	# 中段は2列だけ: 地図列｜ログ列。右列(情報欄)は廃止し、
	# ログ列が右端まで広がる。境目には金属の溝を描く分割を使う。
	var middle := MetalHSplit.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 6)
	middle.resized.connect(_on_split_resized)
	middle.dragged.connect(_on_split_dragged)
	add_child(middle)
	split = middle

	# 左列: 世界名ヘッダー・地図・状態パネル。
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 4)
	middle.add_child(left_col)
	world_header = Label.new()
	world_header.clip_text = true
	world_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 世界名の行は、地図列の幅いっぱいのシルバーの帯にする。
	# 地に合わせて文字は濃い色。帯の高さは文字の高さのまま
	# (上下の余白は付けない。ログとの上端合わせに響くため)。
	var header_box := StyleBoxFlat.new()
	UiStyle.round_box(header_box)
	header_box.bg_color = WORLD_HEADER_BG
	header_box.content_margin_left = 6
	header_box.content_margin_right = 6
	header_box.content_margin_top = 0
	header_box.content_margin_bottom = 0
	world_header.add_theme_stylebox_override("normal", header_box)
	world_header.add_theme_color_override("font_color", WORLD_HEADER_FG)
	left_col.add_child(world_header)
	map_view = MapView.new()
	map_view.label_font = _font
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.zoom_changed.connect(_on_map_zoom_changed)
	left_col.add_child(map_view)
	map_view.compass.label_font = _font
	map_view.set_compass_texture(_assets.skin_image("Direction"))
	_build_list_overlay()
	_build_toolbar_overlay()
	status_panel = StatusPanel.new()
	status_panel.label_font = _font
	status_panel.bold_font = _bold_font
	status_panel.hpmp_tex = _assets.skin_image("HpMpBar")
	left_col.add_child(status_panel)

	# ログ列: 見出し・ログ・入力欄。見出しの帯は世界名ヘッダーと
	# 同じ高さで、ログの上端と地図の上端がそろうようにする。
	# 帯には「Log Window」の文字を中央寄せで控えめに出す。
	# 上下の境目をドラッグして入力欄の高さを変えられ、
	# 高さは設定に保持する。入力欄の幅はログの列と同期した
	# まま変えない。
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 4)
	middle.add_child(right_col)
	var log_top_label := Label.new()
	log_top_label.text = LOG_TOP_TEXT
	log_top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	log_top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_top_label.add_theme_color_override("font_color", LOG_TOP_FG)
	_log_top_spacer = log_top_label
	right_col.add_child(_log_top_spacer)
	input_split = MetalVSplit.new()
	input_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input_split.add_theme_constant_override("separation", 6)
	input_split.resized.connect(_on_input_split_resized)
	input_split.dragged.connect(_on_input_split_dragged)
	right_col.add_child(input_split)
	log_view = RichTextLabel.new()
	log_view.custom_minimum_size = Vector2(280, MIN_LOG_HEIGHT)
	# URL のリンク化のため BBCode を有効にする。出す行は
	# bbcode_line() でエスケープしてから渡すので、サーバや
	# 他人の発言に含まれる [ ] がタグとして解釈される事は無い。
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.focus_mode = Control.FOCUS_NONE
	log_view.gui_input.connect(_on_log_gui_input)
	log_view.meta_clicked.connect(_on_log_meta_clicked)
	input_split.add_child(log_view)
	input_box = TextEdit.new()
	input_box.placeholder_text = "入力欄 (Enter で送信、Shift+Enter で改行、Esc で移動キーへ、Tab で入力欄へ)"
	input_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_box.text_changed.connect(_on_input_text_changed)
	input_box.gui_input.connect(_on_input_gui_input)
	input_split.add_child(input_box)
	# 入力欄の枠は角丸にする(地はテーマのものを複製して使う。
	# 大声をやめた時に戻せるよう、複製を持っておく)。
	for slot in ["normal", "focus"]:
		var base_box := input_box.get_theme_stylebox(slot) as StyleBoxFlat
		if base_box != null:
			var rounded_box := base_box.duplicate() as StyleBoxFlat
			UiStyle.round_box(rounded_box)
			input_box.add_theme_stylebox_override(slot, rounded_box)
			if slot == "normal":
				_input_normal_box = rounded_box
			else:
				_input_focus_box = rounded_box

	refresh_ui_font_size()
	_update_side_info()
	apply_scroll_stop()


static func _round_panel(panel: PanelContainer) -> void:
	## フロートパネルの地を角丸にする(テーマの地は共有なので、
	## 複製してから角を丸める)。
	var base := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if base != null:
		var rounded := base.duplicate() as StyleBoxFlat
		UiStyle.round_box(rounded)
		panel.add_theme_stylebox_override("panel", rounded)


func _build_list_overlay() -> void:
	## #list の内容を地図の上に重ねるパネル。普段は隠れている。
	_list_panel = PanelContainer.new()
	_round_panel(_list_panel)
	_list_panel.visible = false
	_list_panel.position = Vector2(8, 8)
	map_view.add_child(_list_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_list_panel.add_child(box)
	# 上部の見出し。リストの種類名を出し、ドラッグの取っ手にもなる。
	_list_header = Label.new()
	_list_header.text = "リスト"
	_list_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_list_header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_list_header.gui_input.connect(_on_list_header_gui_input)
	box.add_child(_list_header)
	_list_box = ItemList.new()
	_list_box.select_mode = ItemList.SELECT_SINGLE
	_list_box.allow_reselect = true
	_list_box.item_activated.connect(_on_list_row_activated)
	_list_box.gui_input.connect(_on_list_box_gui_input)
	box.add_child(_list_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	# 決定ボタンは置かない。決定は項目のダブルクリック
	# (または Enter)で行う。残すのはキャンセルだけ。
	_list_cancel_button = Button.new()
	_list_cancel_button.text = "キャンセル"
	_list_cancel_button.focus_mode = Control.FOCUS_NONE
	_list_cancel_button.pressed.connect(_on_list_cancel_pressed)
	buttons.add_child(_list_cancel_button)


func _build_toolbar_overlay() -> void:
	## ツールバー。地図の上に浮くパネルに、Philly のツールバーの
	## 並びを、種類(区切りのグループ)ごとに1段ずつ並べる。
	## パネルの地(ボタンでない所)のドラッグで地図の中を動かせ、
	## 位置は設定に保持する(全タブ共通。既定は左上)。
	## ボタンの実行はメイン画面の _do_action に任せる。
	_toolbar_panel = PanelContainer.new()
	_round_panel(_toolbar_panel)
	_toolbar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_toolbar_panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
	map_view.add_child(_toolbar_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toolbar_panel.add_child(rows)
	var row: HBoxContainer = null
	for item in PhiActions.TOOLBAR:
		var action_name := str(item)
		if action_name == "-":
			row = null
			continue
		var action := PhiActions.get_action(action_name)
		if action.is_empty():
			continue
		if row == null:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(row)
		var button := Button.new()
		button.tooltip_text = str(action["hint"])
		button.focus_mode = Control.FOCUS_NONE
		button.expand_icon = true
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if action_name == "Loud":
			button.toggle_mode = true
		var icon: Variant = _assets.button_icon(action_name)
		if icon != null:
			button.icon = icon
		else:
			button.text = _short_caption(str(action["caption"]))
		button.pressed.connect(_on_toolbar_button_pressed.bind(action_name))
		button.set_meta("action", action_name)
		row.add_child(button)
		_toolbar_buttons.append(button)
	_toolbar_panel.gui_input.connect(_on_toolbar_panel_gui_input)
	_toolbar_panel.position = _toolbar_home_position()
	_fit_toolbar_panel()
	refresh_toolbar_states()


static func _short_caption(caption: String) -> String:
	## ツールバー用の短い表示名。`自動装備 [Q,/]` → `自動装備`。
	var bracket := caption.find(" [")
	if bracket >= 0:
		return caption.substr(0, bracket)
	return caption


func _on_toolbar_button_pressed(action_name: String) -> void:
	## ツールバーのボタンの実行はメイン画面に任せる。
	action_requested.emit(action_name)


func refresh_toolbar_states() -> void:
	## ツールバーのボタンの有効・無効と、大声ボタンの押下状態を、
	## このタブの接続状態に合わせる。
	var connected := is_session_open()
	for button in _toolbar_buttons:
		var action_name := str(button.get_meta("action"))
		button.disabled = not PhiActions.enabled_when(action_name, connected)
		if action_name == "Loud":
			button.set_pressed_no_signal(is_loud())


func _toolbar_home_position() -> Vector2:
	## ツールバーの置き場所。設定に保持した位置があればそれ、
	## 無ければ地図の左上。
	if _config != null and _config.toolbar_pos.x >= 0.0 and _config.toolbar_pos.y >= 0.0:
		return _config.toolbar_pos
	return Vector2(8, 8)


func _fit_toolbar_panel() -> void:
	## パネルの大きさを中身に合わせ、地図からはみ出していたら
	## 中に戻す。地図の大きさがまだ決まっていない時は戻さない。
	if _toolbar_panel == null or map_view == null:
		return
	_toolbar_panel.size = _toolbar_panel.get_combined_minimum_size()
	_clamp_toolbar_panel()


func _clamp_toolbar_panel() -> void:
	## パネルが地図の外に出ていたら中へ戻す。パネルが地図より
	## 大きい軸では全体は収まらないので、左上(基準点)だけが
	## 地図の中に残るよう寄せるに留める(過渡的に小さな地図で
	## 保持した位置まで動かしてしまわないため)。
	if _toolbar_panel == null or map_view == null:
		return
	if map_view.size.x <= 0.0 or map_view.size.y <= 0.0:
		return
	var pos := _toolbar_panel.position
	var lim_x := maxf(0.0, map_view.size.x - _toolbar_panel.size.x) if _toolbar_panel.size.x <= map_view.size.x else map_view.size.x
	var lim_y := maxf(0.0, map_view.size.y - _toolbar_panel.size.y) if _toolbar_panel.size.y <= map_view.size.y else map_view.size.y
	_toolbar_panel.position = Vector2(clampf(pos.x, 0.0, lim_x), clampf(pos.y, 0.0, lim_y))


func _move_toolbar_panel(target_global: Vector2) -> void:
	## パネルを地図ビューの中に収まる位置へ動かす(リストと同じ)。
	if _toolbar_panel == null or map_view == null:
		return
	var local: Vector2 = map_view.get_global_transform().affine_inverse() * target_global
	var max_pos := Vector2(maxf(0.0, map_view.size.x - _toolbar_panel.size.x), maxf(0.0, map_view.size.y - _toolbar_panel.size.y))
	_toolbar_panel.position = Vector2(clampf(local.x, 0.0, max_pos.x), clampf(local.y, 0.0, max_pos.y))


func _on_toolbar_panel_gui_input(event: InputEvent) -> void:
	## パネルの地のドラッグでパネルを動かす。ボタンの上の
	## クリックはボタンが受けるので、ここには来ない。
	## 離すのはマウスのボタン処理でも拾う(地の外で離しても止まる)。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_toolbar_dragging = true
			_toolbar_drag_offset = event.global_position - _toolbar_panel.global_position
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
		else:
			_end_toolbar_drag()


func _end_toolbar_drag() -> void:
	## ドラッグの終わりに、位置を設定へ覚える(保存はメイン画面が
	## 終了時などに行う。分割比率と同じ扱い)。
	if not _toolbar_dragging:
		return
	_toolbar_dragging = false
	if _toolbar_panel != null and _config != null:
		_config.toolbar_pos = _toolbar_panel.position


func _apply_list_font_size(size: int) -> void:
	## リストの文字・見出し・ボタンに、同じ UI 文字サイズを付ける。
	## ボタンは押しやすい高さも付ける。
	if _list_box != null:
		_list_box.add_theme_font_size_override("font_size", size)
	if _list_header != null:
		_list_header.add_theme_font_size_override("font_size", size)
		if _bold_font != null:
			_list_header.add_theme_font_override("font", _bold_font)
	if _list_cancel_button != null:
		_list_cancel_button.add_theme_font_size_override("font_size", size)
		_list_cancel_button.custom_minimum_size = Vector2(0, size + 16)


## リストの種類名を、開くきっかけになったコマンドから決める。
## プロンプト文が分かるときは、補助に使う。
static func list_title_for_command(command: String, prompt := "") -> String:
	match command.strip_edges().to_lower():
		"cast":
			return "魔法リスト"
		"equip", "unequip":
			return "装備リスト"
		"get", "put", "use":
			return "アイテムリスト"
	if prompt.contains("魔法") or prompt.contains("呪文"):
		return "魔法リスト"
	if prompt.contains("装備"):
		return "装備リスト"
	if prompt.contains("アイテム"):
		return "アイテムリスト"
	return "リスト"


func _note_sent(text: String) -> void:
	## 送った文の先頭の言葉を覚える。あとで届くリストの
	## 種類名を決めるのに使う。リストへの答えは記録しない。
	var first := text.split("\n")[0].strip_edges()
	if first.is_empty():
		return
	_last_command = first.split(" ")[0]


func _on_list_header_gui_input(event: InputEvent) -> void:
	## 見出しのドラッグでパネルを動かす。離すのはマウスの
	## ボタン処理でも拾う(見出しの外で離しても止まる)。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_list_dragging = true
			_list_drag_offset = event.global_position - _list_panel.global_position
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
		else:
			_list_dragging = false


func _move_list_panel(target_global: Vector2) -> void:
	## パネルを地図ビューの中に収まる位置へ動かす。
	if _list_panel == null or map_view == null:
		return
	var local: Vector2 = map_view.get_global_transform().affine_inverse() * target_global
	var max_pos := Vector2(maxf(0.0, map_view.size.x - _list_panel.size.x), maxf(0.0, map_view.size.y - _list_panel.size.y))
	_list_panel.position = Vector2(clampf(local.x, 0.0, max_pos.x), clampf(local.y, 0.0, max_pos.y))


func _apply_log_css() -> void:
	## スキンの Style/Log.css の body の背景色・文字色をログに使う。
	var css := _assets.log_css()
	var body: Dictionary = css.get("body", {})
	var bg: Variant = SkinFiles.parse_css_color(str(body.get("background", "")))
	if bg != null:
		var box := StyleBoxFlat.new()
		UiStyle.round_box(box)
		box.bg_color = bg
		log_view.add_theme_stylebox_override("normal", box)
	var fg: Variant = SkinFiles.parse_css_color(str(body.get("color", "")))
	if fg != null:
		log_view.add_theme_color_override("default_color", fg)
	var classes: Dictionary = css.get("classes", {})
	var ok: Dictionary = classes.get("class_system_ok", {})
	_system_color = SkinFiles.parse_css_color(str(ok.get("color", "")))
	var ng: Dictionary = classes.get("class_system_ng", {})
	_error_color = SkinFiles.parse_css_color(str(ng.get("color", "")))


func _on_map_zoom_changed(new_zoom: int) -> void:
	refresh_ui_font_size()
	zoom_changed.emit(new_zoom)


func refresh_ui_font_size() -> void:
	## 地図の倍率に比例して、このタブの UI の文字を大きくする。
	## メニュー・ツールバーなどの全体の大きさはメイン画面が付ける。
	if map_view == null:
		return
	var size := PhiFont.ui_size_for_zoom(map_view.zoom)
	if size == _applied_size:
		return
	_applied_size = size
	log_view.add_theme_font_size_override("font_size", size)
	log_view.add_theme_font_size_override("normal_font_size", size)
	log_view.add_theme_font_size_override("bold_font_size", size)
	log_view.add_theme_font_size_override("italics_font_size", size)
	log_view.add_theme_font_size_override("bold_italics_font_size", size)
	log_view.add_theme_font_size_override("mono_font_size", size)
	input_box.add_theme_font_size_override("font_size", size)
	if world_header != null:
		world_header.add_theme_font_size_override("font_size", size)
	# ログ列の上の帯を、世界名ヘッダーの高さに合わせる
	# (ログの上端と地図の上端をそろえるため)。帯の文字も
	# ヘッダーと同じ文字サイズにする。
	if _log_top_spacer != null and world_header != null:
		_log_top_spacer.custom_minimum_size = Vector2(0, world_header.get_combined_minimum_size().y)
		if _log_top_spacer is Label:
			(_log_top_spacer as Label).add_theme_font_size_override("font_size", size)
	if status_panel != null:
		status_panel.set_ui_sizes(PhiFont.gauge_size_for_zoom(map_view.zoom), PhiFont.status_size_for_zoom(map_view.zoom))
	if _list_box != null:
		_apply_list_font_size(size)
	# ツールバーのボタンも UI 文字サイズに追従させる
	# (アイコン付きは 6*zoom + 16 の正方形)。
	for button in _toolbar_buttons:
		button.add_theme_font_size_override("font_size", size)
		var min_size := Vector2(0, size + 12)
		if button.icon != null:
			min_size = Vector2(size + 16, size + 16)
		button.custom_minimum_size = min_size
	_fit_toolbar_panel()
	# 入力欄の最小の高さは今の文字で2行ぶん。高さ自体は
	# 保持した値(無ければ3行ぶん)に合わせる。
	if input_box != null:
		input_box.custom_minimum_size = Vector2(0, _font.get_height(size) * 2 + 16)
	_apply_input_height()
	var chrome_size := PhiFont.chrome_size_for_zoom(map_view.zoom)
	for popup in [_tag_popup, _copy_popup]:
		if popup != null:
			popup.add_theme_font_size_override("font_size", chrome_size)
			popup.add_theme_font_size_override("font_separator_size", chrome_size)


func apply_scroll_stop() -> void:
	if log_view != null:
		log_view.scroll_following = not _config.scroll_stop


func _on_split_resized() -> void:
	## 境目を比率で保つ。窓の幅が変わっても、地図とログの割合は同じ。
	if split == null:
		return
	var w := split.size.x
	if w < 1.0:
		return
	var off := _config.split_offset_for(int(w), split.get_theme_constant("separation"))
	if off != split.split_offset:
		split.split_offset = off
	# 地図の大きさが変わったら、ツールバーがはみ出さないよう戻す。
	_clamp_toolbar_panel()


func _on_split_dragged(offset: int) -> void:
	## 境目をドラッグしたら比率を更新し、拡大のきっかけにする。
	if split == null or split.size.x <= 0:
		return
	_config.split_ratio = clampf(float(offset) / split.size.x, PhiConfig.MIN_SPLIT_RATIO, PhiConfig.MAX_SPLIT_RATIO)
	if map_view != null:
		map_view.request_zoom_growth()


func _min_input_height() -> int:
	## 入力欄の最小の高さ(今の文字で2行ぶん)。
	return _font.get_height(PhiFont.ui_size_for_zoom(map_view.zoom)) * 2 + 16


func _default_input_height() -> int:
	## 入力欄の既定の高さ(今の文字で3行ぶん)。
	## 保持した高さが無い時に使う。
	return _font.get_height(PhiFont.ui_size_for_zoom(map_view.zoom)) * 3 + 16


func _input_split_gap() -> float:
	## ログと入力欄の間の実際のすきま。テーマの separation と
	## 実測がずれることがあるので、配置済みなら子の位置から測る。
	if input_split != null and log_view != null and input_box != null and input_split.size.y > 0.0:
		var gap := input_box.position.y - (log_view.position.y + log_view.size.y)
		if gap >= 0.0:
			return gap
	if input_split != null:
		return float(input_split.get_theme_constant("separation"))
	return 0.0


func _apply_input_height() -> void:
	## 入力欄の高さを、保持した値(無ければ既定)に合わせる。
	## ログの最小の高さと入力欄の最小の高さは必ず残す。
	## 窓や列の高さが変わっても、入力欄の高さの方が保たれる。
	if input_split == null or input_box == null or map_view == null:
		return
	var total := input_split.size.y
	if total <= 0.0:
		return
	var sep := _input_split_gap()
	var desired := float(_config.input_height) if _config.input_height >= 0 else float(_default_input_height())
	var min_h := float(_min_input_height())
	var max_h := maxf(min_h, total - sep - float(MIN_LOG_HEIGHT))
	var clamped := clampf(desired, min_h, max_h)
	var off := int(round(total - sep - clamped))
	if off != input_split.split_offset:
		input_split.split_offset = off


func _on_input_split_resized() -> void:
	# 配置が済んでから合わせる(すきまの実測は子の位置が
	# 決まっていないと取れないため、フレームの終わりに回す)。
	call_deferred("_apply_input_height")


func _on_input_split_dragged(offset: int) -> void:
	## 境目をドラッグしたら、決まった入力欄の高さを設定に覚える
	## (保存はメイン画面が終了時などに行う。分割比率と同じ扱い)。
	if input_split == null:
		return
	var sep := _input_split_gap()
	var h := int(round(input_split.size.y - sep - float(offset)))
	_config.input_height = maxi(h, 0)


# -- 接続 --------------------------------------------------------------------

func connect_to(p_host: String, p_port: int, p_char_id: String) -> void:
	## 地図の大きさ・様式・魔法表示は、呼ぶ側(_connect_tab)が
	## セッションに付けてある。
	host = p_host
	port = p_port
	restored_name = ""
	_save_failed = false
	log_message("system", "%s:%d に接続します..." % [host, port])
	session.connect_to(host, port, p_char_id)
	title_changed.emit(tab_title())


func disconnect_graceful() -> void:
	session.disconnect_graceful()
	_on_session_closed()


func send_line(line: String) -> void:
	_note_sent(line)
	session.send_line(line)


func send_text(text: String) -> void:
	_note_sent(text)
	session.send_text(text)


func _on_session_error(message: String) -> void:
	log_message("error", message)


func _on_session_closed() -> void:
	log_message("system", "接続が閉じました")
	_held_moves.clear()
	_hide_list_overlay()
	# BGM は切断で止める(Philly と同じく曲名も空に戻す)。
	if not bgm_name.is_empty():
		bgm_name = ""
		bgm_speed = 100
		bgm_changed.emit()
	_was_open = false
	refresh_toolbar_states()
	connection_changed.emit(false)
	title_changed.emit(tab_title())

# -- 受信イベント ------------------------------------------------------------

func _on_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"message":
			var channel := str(event.get("channel", "log"))
			var raw := str(event.get("text", ""))
			var plain := PhiTags.plain_text(raw)
			_collect_image_refs(raw)
			log_message(channel, plain, raw)
			# 効果音(第5段)。ログ行ごとに照合する。削除フィルタで
			# 表示されない行でも鳴る(Philly と同じく表示とは独立)。
			if _sound_engine != null:
				for se_line in plain.split("\n"):
					_sound_engine.play_se_for_line(se_line)
			if not _is_active:
				set_unread(true)
			if channel == "log":
				map_view.spawn_floats(plain)
				map_view.spawn_combat_fx(plain)
				map_view.spawn_death_fx(plain)
				map_view.show_log_bubble(raw, plain)
			elif channel in ["talk", "priv"]:
				var from_ := str(event.get("from", ""))
				if not from_.is_empty():
					var body := PhiBubbles.bubble_body(plain)
					if not body.is_empty():
						map_view.show_bubble(from_, body)
				if channel == "priv":
					add_priv_history(plain)
					priv_received.emit(plain)
		"status":
			_update_status(event)
		"notice":
			if event.has("name"):
				_player_name = str(event["name"])
				map_view.player_name = _player_name
				title_changed.emit(tab_title())
			if event.has("world"):
				_world = str(event["world"])
			if event.has("area"):
				_area = str(event["area"])
			if event.has("mapset"):
				_mapset = str(event["mapset"])
			_update_side_info()
		"cond":
			if status_panel != null:
				status_panel.set_conditions(bool(event.get("poison", false)), bool(event.get("panic", false)))
		"dispMagic":
			map_view.spawn_disp_magic(event["data"])
		"bgm":
			# BGM 通知(第5段)。同じ曲名なら何もしない(Philly と
			# 同じく再生し直さない)。鳴らす判断はメイン画面。
			var new_bgm := str(event.get("name", ""))
			if new_bgm != bgm_name:
				bgm_name = new_bgm
				bgm_changed.emit()
		"bgmSpeed":
			var new_speed := int(event.get("speed", 100))
			if new_speed != bgm_speed:
				bgm_speed = new_speed
				bgm_changed.emit()
		"map":
			_demo_chars = event.get("chars", [])
			_demo_dim = MapView.grid_dim(int(event.get("size", 7)))
			_map_dim_now = int(event.get("size", 0))
			if event.has("style"):
				_map_style_now = str(event["style"])
			map_view.set_map(event, _assets, _mapset)
			map_view.set_compass_direction(int(event.get("dir", 0)), north_fix_now())
			_repeat_on_map()
		"eagleEye":
			log_message("system", "EagleEye %dx%d" % [int(event.get("width", 0)), int(event.get("height", 0))])
		"list":
			_show_list(event)
		"userList":
			_users.clear()
			for user in event.get("users", []):
				_users.append({"key": str(user.get("key", "")), "name": str(user.get("name", ""))})
			users_changed.emit()
		"edit":
			log_message("system", "編集モード: %s" % str(event.get("mode", "")))
		"worldTransfer":
			log_message("system", "世界移動の要求がありました(試作では未対応): %s" % str(event.get("server", "")))
		"connection":
			log_message("system", "サーバから切断されました")
		"mode":
			pass


func _collect_image_refs(raw: String) -> void:
	## 行から画像の参照を集める。取得はしない(窓で選んだ時だけ)。
	for url in PhiImages.extract_refs(raw):
		_image_refs.append({"url": url, "line": PhiTags.plain_text(raw).strip_edges()})
	while _image_refs.size() > MAX_IMAGE_REFS:
		_image_refs.remove_at(0)


func log_message(channel: String, text: String, raw: String = "") -> void:
	## ログに1件(複数行あり)を出す。削除フィルタに合う行は出さない。
	## 出した行は記録に残し、自動保存が on ならファイルにも書く。
	if raw.is_empty():
		raw = text
	var prefix := ""
	var color: Variant = null
	match channel:
		"talk":
			prefix = "[発言] "
		"priv":
			prefix = "[priv] "
		"system":
			prefix = "[お知らせ] "
			color = _system_color
		"error":
			prefix = "[お知らせ] "
			color = _error_color
	var plain_lines := text.split("\n")
	var raw_lines := raw.split("\n")
	var use_filter := _config.log_delete_filter and _log_filter != null and channel in ["log", "talk", "priv"]
	if color != null:
		log_view.push_color(color)
	for i in range(plain_lines.size()):
		var plain_line: String = plain_lines[i]
		var raw_line := raw_lines[mini(i, raw_lines.size() - 1)]
		if use_filter and _log_filter.matches(plain_line):
			continue
		var display := prefix + plain_line
		log_view.append_text(bbcode_line(display) + "\n")
		_log_lines.append({"display": display, "raw": raw_line, "prefix": prefix})
		_save_log_line(prefix, plain_line, raw_line)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	if color != null:
		log_view.pop()


func _save_log_line(prefix: String, plain_line: String, raw_line: String) -> void:
	if not _config.log_auto_save:
		return
	var body := plain_line if _config.log_save_delete_tag else raw_line
	var line := prefix + body
	if not _config.log_save_html and _config.log_save_text_with_time:
		line = PhiLogFile.format_text_line(line, true, Time.get_time_string_from_system(false))
	var char_name := _player_name
	if char_name.is_empty():
		char_name = "%s_%d" % [host, port] if not host.is_empty() else "character"
	var ok := PhiLogFile.append_line(_config.log_save_dir, char_name, _config.log_save_html, line)
	if not ok and not _save_failed:
		_save_failed = true
		log_view.append_text(bbcode_line("[お知らせ] ログの自動保存に失敗しました: " + _config.log_save_dir) + "\n")


## 今のログ記録をその場でファイルに書き出す(手動保存、残り項目)。
## 行の作り方は自動保存と同じ(接頭辞＋、タグ削除の設定に従う)。
## テキストで時刻入りが on なら、保存時刻の印を全行に付ける
## (自動保存が書く時刻は「ファイルに書いた時刻」なので揃える)。
## 成功したらパス、失敗したら "" を返す。
func save_log_buffer() -> String:
	var lines: Array[String] = []
	var stamp := Time.get_time_string_from_system(false)
	for entry in _log_lines:
		var display := str(entry["display"])
		var prefix := str(entry.get("prefix", ""))
		var plain := display.substr(prefix.length())
		var body := plain if _config.log_save_delete_tag else str(entry["raw"])
		var line := prefix + body
		if not _config.log_save_html and _config.log_save_text_with_time:
			line = PhiLogFile.format_text_line(line, true, stamp)
		lines.append(line)
	var char_name := _player_name
	if char_name.is_empty():
		char_name = "%s_%d" % [host, port] if not host.is_empty() else "character"
	return PhiLogFile.save_buffer(_config.log_save_dir, char_name, _config.log_save_html, lines)


# -- ログの URL リンク化(残り項目) -------------------------------------------
## 表示だけの処理。記録(_log_lines)や保存・コピーの元になる
## 文字列は従来どおりプレーンなままにする。RichTextLabel の
## get_parsed_text() / get_selected_text() は BBCode を取り除いた
## 文字列を返すので、コピー変種も壊れない。

static func escape_bbcode(text: String) -> String:
	## `[` と `]` をリテラルとして出すためのエスケープ。
	## 置換文字列にも括弧が入るので、1回の走査で組み立てる。
	var out := ""
	for i in text.length():
		var ch := text[i]
		if ch == "[":
			out += "[lb]"
		elif ch == "]":
			out += "[rb]"
		else:
			out += ch
	return out


static func url_spans(text: String) -> Array:
	## 行中の URL の [開始位置, URL] の一覧。末尾の句読点は
	## URL に含めない(PhiImages の抽出と同じ流儀)。
	var spans: Array = []
	var regex := RegEx.new()
	if regex.compile("https?://[^\\s<>\"'\\]]+") != OK:
		return spans
	for found in regex.search_all(text):
		var url := found.get_string()
		while not url.is_empty() and _URL_TAIL_TRIM.contains(url[url.length() - 1]):
			url = url.substr(0, url.length() - 1)
		if url.is_empty() or url == "http://" or url == "https://":
			continue
		spans.append([found.get_start(), url])
	return spans


static func bbcode_line(text: String) -> String:
	## ログ表示用に、テキストをエスケープし、URL をクリック
	## 可能なリンクにする。URL が無ければエスケープだけ。
	var spans := url_spans(text)
	if spans.is_empty():
		return escape_bbcode(text)
	var out := ""
	var pos := 0
	for span in spans:
		var start: int = span[0]
		var url: String = span[1]
		out += escape_bbcode(text.substr(pos, start - pos))
		out += "[url=" + url + "][color=#" + LOG_LINK_COLOR + "][u]" + escape_bbcode(url) + "[/u][/color][/url]"
		pos = start + url.length()
	out += escape_bbcode(text.substr(pos))
	return out


func _on_log_meta_clicked(meta: Variant) -> void:
	## リンクのクリックでブラウザを開く。開くのは http/https
	## だけ(リンクは自前で作るので、それ以外は来ない想定)。
	var url := str(meta)
	if url.begins_with("http://") or url.begins_with("https://"):
		OS.shell_open(url)


func _update_status(event: Dictionary) -> void:
	if event.has("name"):
		_player_name = str(event["name"])
		map_view.player_name = _player_name
		title_changed.emit(tab_title())
	if status_panel != null:
		status_panel.set_status(event)
	_update_side_info()


func _update_side_info() -> void:
	## 地図の上の世界名ヘッダーを出す(右列の情報欄は廃止した)。
	if world_header != null:
		world_header.text = place_text(_world, _area)


## 世界名とエリア名を1行にする。未接続の時は空。
static func place_text(world: String, area: String) -> String:
	if not world.is_empty() and not area.is_empty():
		return "%s / %s" % [world, area]
	if not world.is_empty():
		return world
	return area


# -- リスト ------------------------------------------------------------------

func _show_list(event: Dictionary) -> void:
	# リストの終わり(#ex-list-mode-end)で、表示を閉じる。
	if not bool(event.get("active", false)):
		_hide_list_overlay()
		return
	var lines: Array = event.get("lines", [])
	if lines.is_empty():
		return
	# 抑え込み中(F1〜F7 やショートカット直後)は、表示もログも出さない。
	if _suppress_lists > 0:
		_suppress_lists -= 1
		return
	_list_lines.clear()
	for line in lines:
		_list_lines.append(PhiTags.plain_text(str(line)))
	_list_active = true
	_show_list_overlay()
	log_message("system", "--- リスト ---")
	for line in _list_lines:
		log_message("log", line)


func mark_list_answered() -> void:
	## リストに答えた(送った)扱いにして、オーバーレイを閉じる。
	_hide_list_overlay()


func _show_list_overlay() -> void:
	## 地図の上にリストを重ねる。幅は地図の幅、高さは行数に合わせる。
	## 位置は前回のまま(ドラッグした位置を保つ)。窓が縮んで
	## はみ出していたら、地図の中へ戻す。
	## チェックはページごとに持ち、新しいリストでは消す。
	_list_checks.clear()
	_list_press_in_check = false
	_list_box.clear()
	for i in range(_list_lines.size()):
		_list_box.add_item(_list_lines[i], check_icon(false))
	if not _list_lines.is_empty():
		_list_box.select(0)
	_list_header.text = list_title_for_command(_last_command)
	var size := maxi(_applied_size, 15)
	var row_h := maxi(_font.get_height(size) + 6, 24)
	var rows := mini(_list_lines.size(), 9)
	var panel_w := clampf(map_view.size.x - 16.0, 200.0, 560.0)
	var panel_h := rows * row_h + (size + 12) + (size + 16) + 20.0
	_list_panel.size = Vector2(panel_w, panel_h)
	_list_box.custom_minimum_size = Vector2(panel_w - 16.0, rows * row_h)
	_list_panel.visible = true
	_move_list_panel(_list_panel.global_position)


func _hide_list_overlay() -> void:
	_list_active = false
	_list_dragging = false
	if _list_panel != null:
		_list_panel.visible = false


# -- リストの複数チェック(残り項目) ------------------------------------------
## Philly のチェックリストに相当する仕組み。プロトコル上の根拠:
## サーバの analyze_numbers は空白区切りの複数番号(昇順)と範囲を
## 受け付け、「続き」の番号を答えると次のページが来る。Philly の
## OK は、チェックした項目の絶対番号を昇順に空白区切りで送り、
## 続きの番号が含まれていればそれだけを送る。
## NeoPHI はページ単位の表示のままなので、チェックもページ単位
## (ページをめくると消える)。Philly のような全ページ蓄積表示と
## 前ページへのジャンプは入れていない。

## チェック欄として扱う、行の左端からの幅(px)。
const LIST_CHECK_AREA := 30.0


static func check_icon(checked: bool) -> Texture2D:
	if _check_icon_on == null:
		_make_check_icons()
	return _check_icon_on if checked else _check_icon_off


static func _make_check_icons() -> void:
	var off := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	var on := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	var border := Color(0.72, 0.72, 0.72)
	for img in [off, on]:
		for x in range(3, 17):
			img.set_pixel(x, 3, border)
			img.set_pixel(x, 16, border)
		for y in range(3, 17):
			img.set_pixel(3, y, border)
			img.set_pixel(16, y, border)
	var green := Color(0.35, 0.95, 0.45)
	_plot_check_line(on, Vector2(5, 10), Vector2(8, 13), green)
	_plot_check_line(on, Vector2(8, 13), Vector2(15, 5), green)
	_check_icon_off = ImageTexture.create_from_image(off)
	_check_icon_on = ImageTexture.create_from_image(on)


static func _plot_check_line(img: Image, a: Vector2, b: Vector2, color: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	if steps <= 0:
		steps = 1
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		for dx in range(2):
			for dy in range(2):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, color)


static func is_more_list_line(line: String) -> bool:
	## サーバの「続きがある」行か(`[ 9] ... and more.`)。
	return line.contains("... and more")


static func compose_checked_answer(lines: Array, checked: Array) -> String:
	## チェックした項目への答えを Philly の OK と同じ規則で作る。
	## 続き行が含まれていれば、その番号だけ(ページ送り)。
	## それ以外は絶対番号を小さい順に空白区切りで並べる。
	## チェックが無ければ ""(呼び出し側は従来の決定に落とす)。
	if checked.is_empty():
		return ""
	var sorted: Array = checked.duplicate()
	sorted.sort()
	for index in sorted:
		var i := int(index)
		if i < 0 or i >= lines.size():
			continue
		if is_more_list_line(str(lines[i])):
			return PhiShortcuts.list_number(str(lines[i]), i)
	var numbers: Array[String] = []
	for index in sorted:
		var i := int(index)
		if i < 0 or i >= lines.size():
			continue
		numbers.append(PhiShortcuts.list_number(str(lines[i]), i))
	return " ".join(numbers)


func list_checked_indices() -> Array[int]:
	var out: Array[int] = []
	for key in _list_checks.keys():
		out.append(int(key))
	out.sort()
	return out


func _toggle_list_check(index: int) -> void:
	if index < 0 or index >= _list_lines.size():
		return
	if _list_checks.has(index):
		_list_checks.erase(index)
		_list_box.set_item_icon(index, check_icon(false))
	else:
		_list_checks[index] = true
		_list_box.set_item_icon(index, check_icon(true))


func _clear_list_checks() -> void:
	for key in _list_checks.keys():
		_list_box.set_item_icon(int(key), check_icon(false))
	_list_checks.clear()


func _invert_list_checks() -> void:
	## このページの全項目のチェックを反転する(Philly の +/-)。
	for i in range(_list_lines.size()):
		_toggle_list_check(i)


func _toggle_selected_and_move(delta: int) -> void:
	var selected := _list_box.get_selected_items()
	if not selected.is_empty():
		_toggle_list_check(selected[0])
	_list_move_selection(delta)


func _on_list_box_gui_input(event: InputEvent) -> void:
	## 行の左端(チェック欄)を押したらチェックを切り替える。
	## それ以外の場所は従来どおり、クリック=選択だけ。
	## チェック欄でのダブルクリックは決定にしない。
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var index := _list_box.get_item_at_position(mb.position)
	_list_press_in_check = index >= 0 and mb.position.x < LIST_CHECK_AREA
	if _list_press_in_check:
		_toggle_list_check(index)


func _send_list_decision() -> bool:
	## チェックがあれば、チェックした項目への答えを送る。
	## 送ったら true(呼び出し側は従来の決定をしない)。
	if not _list_active:
		return false
	var answer := compose_checked_answer(_list_lines, list_checked_indices())
	if answer.is_empty():
		return false
	_send_list_answer(answer)
	return true


func _on_list_row_activated(index: int) -> void:
	## ダブルクリック(または Enter)で決定する。シングルクリックは
	## 選択(ハイライト)だけ。チェック欄でのダブルクリックは
	## 決定にしない。チェックがあればチェックした項目が優先。
	if _list_press_in_check:
		_list_press_in_check = false
		return
	if _send_list_decision():
		return
	_send_list_row(index)


func _on_list_cancel_pressed() -> void:
	_send_list_answer(".")


func _send_list_selected() -> void:
	## Enter での決定。チェックがあればチェックした項目への
	## 答えが優先し、無ければ選択行を送る(従来どおり)。
	if _send_list_decision():
		return
	var selected := _list_box.get_selected_items()
	if selected.is_empty():
		return
	_send_list_row(selected[0])


func _send_list_row(index: int) -> void:
	## リスト表示中だけ送る(閉じた後の遅れたイベントでは送らない)。
	if not _list_active:
		return
	if index < 0 or index >= _list_lines.size():
		return
	_send_list_answer(PhiShortcuts.list_number(_list_lines[index], index))


func _send_list_answer(answer: String) -> void:
	session.send_line(answer)
	_hide_list_overlay()


func handle_list_key(code: String, shift: bool, ctrl: bool, alt: bool) -> bool:
	## リストが出ている間のキー。扱ったら true。
	## 修飾キー無しは従来どおり(Philly KeyBindListMode の修飾なし)。
	## Shift/Ctrl はチェック操作(Philly の Shift/Ctrl の場合分け)。
	if alt:
		return false
	if shift or ctrl:
		return _handle_list_check_key(code)
	if code == "ArrowUp":
		_list_move_selection(-1)
		return true
	if code == "ArrowDown":
		_list_move_selection(1)
		return true
	if code == "Space":
		# 選択行のチェックを切り替えて、選択を1つ下へ(Philly)。
		_toggle_selected_and_move(1)
		return true
	if code == "Digit0" or code == "Numpad0" or code == "Period" or code == "NumpadDecimal" or code == "ArrowLeft" or code == "ArrowRight":
		_send_list_answer(".")
		return true
	if code == "Minus" or code == "NumpadSubtract" or code == "NumpadAdd":
		_send_list_answer("-")
		return true
	if code.begins_with("Digit") and code.length() == 6:
		var digit := code[5]
		if digit >= "1" and digit <= "9":
			_send_list_row(int(digit) - 1)
			return true
	if code.begins_with("Numpad") and code.length() == 7:
		var num_digit := code[6]
		if num_digit >= "1" and num_digit <= "9":
			_send_list_row(int(num_digit) - 1)
			return true
	return false


func _handle_list_check_key(code: String) -> bool:
	## Shift/Ctrl を押しながらのリストのキー(Philly の
	## KeyBindListMode の Shift/Ctrl の場合分け)。
	## 数字 1〜8 はその行のチェック切替、0 と . は全消し、
	## +/- は全反転、↑↓ は選択行のチェック切替＋移動。
	if code == "Digit0" or code == "Numpad0" or code == "Period" or code == "NumpadDecimal":
		_clear_list_checks()
		return true
	if code == "Minus" or code == "NumpadSubtract" or code == "NumpadAdd":
		_invert_list_checks()
		return true
	if code == "ArrowUp":
		_toggle_selected_and_move(-1)
		return true
	if code == "ArrowDown":
		_toggle_selected_and_move(1)
		return true
	var digit := _list_digit_of(code)
	if digit >= 1 and digit <= 8:
		_toggle_list_check(digit - 1)
		return true
	return false


static func _list_digit_of(code: String) -> int:
	## "Digit1"〜"Digit9" / "Numpad1"〜"Numpad9" の数字。違えば -1。
	if code.length() == 6 and code.begins_with("Digit"):
		var d := code[5]
		if d >= "1" and d <= "9":
			return int(d)
	if code.length() == 7 and code.begins_with("Numpad"):
		var d2 := code[6]
		if d2 >= "1" and d2 <= "9":
			return int(d2)
	return -1


func _list_move_selection(delta: int) -> void:
	var selected := _list_box.get_selected_items()
	var current := selected[0] if not selected.is_empty() else 0
	var next := clampi(current + delta, 0, _list_lines.size() - 1)
	_list_box.select(next)
	_list_box.ensure_current_is_visible()


# -- 移動の繰り返しと北固定 --------------------------------------------------

func north_fix_now() -> bool:
	## 移動キー表を北固定にするか。Philly は「地図の大きさが 57 で
	## 様式が回転でない時」に北固定表を使う。地図イベントの size は
	## マスの数(7 が 57、5 が 40)なので、7 と比べる。
	var dim := _map_dim_now if _map_dim_now > 0 else MapView.grid_dim(session.map_size)
	var style := _map_style_now if not _map_style_now.is_empty() else session.map_style
	return dim == 7 and style != "turn"


func press_held_move(key_event: InputEventKey, key: String, mods: String) -> void:
	var physical := int(key_event.physical_keycode)
	if physical == 0:
		physical = int(key_event.keycode)
	for i in range(_held_moves.size()):
		if int(_held_moves[i]["code"]) == physical:
			_held_moves.remove_at(i)
			break
	_held_moves.append({"code": physical, "key": key, "mods": mods})
	_held_since = Time.get_ticks_msec()
	_last_repeat_send = 0


func release_held_move(key_event: InputEventKey) -> void:
	var physical := int(key_event.physical_keycode)
	if physical == 0:
		physical = int(key_event.keycode)
	for i in range(_held_moves.size()):
		if int(_held_moves[i]["code"]) == physical:
			_held_moves.remove_at(i)
			break
	if not _held_moves.is_empty():
		_held_since = Time.get_ticks_msec()
		_last_repeat_send = 0


func _repeat_on_map() -> void:
	## 地図が届いたら、押し続けている移動キーの次の一歩を送る
	## (Philly の MapRecv)。マウスの長押しも同じ。
	_repeat_send_if_ready()
	_mouse_repeat_send_if_ready()


func _repeat_fallback_tick() -> void:
	if _held_moves.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _held_since < REPEAT_START_MS:
		return
	if _last_repeat_send > 0 and now - _last_repeat_send < REPEAT_FALLBACK_MS:
		return
	_repeat_send_if_ready()


func _repeat_send_if_ready() -> void:
	if _held_moves.is_empty():
		return
	if _list_active or input_box.has_focus():
		return
	var now := Time.get_ticks_msec()
	if now - _held_since < REPEAT_START_MS:
		return
	if _last_repeat_send > 0 and now - _last_repeat_send < REPEAT_MIN_INTERVAL_MS:
		return
	var held: Dictionary = _held_moves[_held_moves.size() - 1]
	session.send_line(PhiKeys.move_command(str(held["key"]), str(held["mods"]), north_fix_now()))
	_last_repeat_send = now


# -- F1〜F12 -----------------------------------------------------------------

func on_magic_key(no: int) -> void:
	## F1〜F7。次のリストを抑えてから呪文を送る
	## (Philly の Cast1〜Cast7 + NextListCancel)。
	var text := PhiShortcuts.magic_text(no, _config.func_key_magic_fix, _config.magic_f[no - 1])
	if text.is_empty():
		return
	_suppress_lists = 1
	mark_list_answered()
	_note_sent(text)
	session.send_text(text)


func on_shortcut_key(no: int) -> void:
	## F8〜F12。リストの間はリスト用文字列、それ以外は自由文字列を送る。
	var idx := no - 8
	var text := PhiShortcuts.shortcut_text(_config.shortcut_f[idx], _config.list_mode_shortcut[idx], _list_active)
	if text.is_empty():
		return
	if not _list_active:
		_suppress_lists = _config.shortcut_list_cancel[idx]
	mark_list_answered()
	_note_sent(text)
	session.send_text(text)


func set_suppress_lists(count: int) -> void:
	_suppress_lists = count

# -- 大声 --------------------------------------------------------------------

## 大声の確認ダイアログはメイン画面が持つ。タブは保留中の文を持ち、
## ダイアログの結果をメイン画面から受ける。
signal screenshot_requested


func set_loud(on: bool) -> void:
	_loud = on
	if not on:
		_loud_all = false
	# 大声の間は入力欄の背景を黄色にする(Philly EditLoudColor)。
	if on:
		var box := StyleBoxFlat.new()
		UiStyle.round_box(box)
		box.bg_color = Color(1, 1, 0)
		input_box.add_theme_stylebox_override("normal", box)
		input_box.add_theme_stylebox_override("focus", box)
		input_box.add_theme_color_override("font_color", Color(0, 0, 0))
		input_box.add_theme_color_override("caret_color", Color(0, 0, 0))
		input_box.add_theme_color_override("font_placeholder_color", Color(0.25, 0.25, 0.25))
	else:
		# 角丸の地に戻す(用意できていない時はテーマの地に戻す)。
		if _input_normal_box != null:
			input_box.add_theme_stylebox_override("normal", _input_normal_box)
		else:
			input_box.remove_theme_stylebox_override("normal")
		if _input_focus_box != null:
			input_box.add_theme_stylebox_override("focus", _input_focus_box)
		else:
			input_box.remove_theme_stylebox_override("focus")
		input_box.remove_theme_color_override("font_color")
		input_box.remove_theme_color_override("caret_color")
		input_box.remove_theme_color_override("font_placeholder_color")


func confirm_loud() -> void:
	_note_sent("*" + _loud_pending)
	session.send_text("*" + _loud_pending)
	_loud_pending = ""
	input_box.release_focus()
	set_loud(false)
	_advance_history()


func cancel_loud() -> void:
	_loud_pending = ""
	input_box.release_focus()
	set_loud(false)


func confirm_loud_all() -> void:
	_loud_all = true
	_note_sent("*" + _loud_pending)
	session.send_text("*" + _loud_pending)
	_loud_pending = ""
	input_box.release_focus()
	_advance_history()


# -- 入力欄の送信と履歴 ------------------------------------------------------

func _on_input_text_changed() -> void:
	## 編集で文が短くなったら、履歴の境界を文の長さに寄せる。
	_history_boundary = PhiInputHistory.clamp_boundary(input_box.text, _history_boundary)


func submit_input(party: bool = false) -> void:
	## 下書き部分だけを送り、送った文は履歴として残す。
	## 大声の確認が必要なら、送らずにダイアログを頼む。
	_history_boundary = PhiInputHistory.clamp_boundary(input_box.text, _history_boundary)
	var draft := PhiInputHistory.draft_of(input_box.text, _history_boundary)
	if draft.is_empty():
		return
	# 送ったら入力欄のフォーカスを外す。外さないと矢印キーが
	# TextEdit に奪われ、移動できなくなる。
	input_box.release_focus()
	mark_list_answered()
	# 空行は `/**/` にする(最終行の空行は除く)。
	# Philly の EditSendNullLine にあたる。下書きだけに適用する。
	var lines := draft.split("\n")
	for i in range(lines.size()):
		if lines[i].is_empty() and i < lines.size() - 1:
			lines[i] = "/**/"
	var text := "\n".join(lines)
	if _loud and not _loud_all:
		_loud_pending = text
		_loud_pending_party = party
		loud_confirm_requested.emit(text, party)
		return
	_send_speech_text(text, party)
	_advance_history()


func _send_speech_text(text: String, party: bool) -> void:
	## 発言を Philly の順序で変換して送る。`/**/` の差し込みや
	## パーティーの `+` は、行頭(入力全体の先頭)だけに付ける。
	if _loud:
		_note_sent("*" + text)
		session.send_text("*" + text)
		return
	var lines := text.split("\n")
	var first := PhiShortcuts.speech_transform(
		lines[0], party, false, false,
		_config.loudly_by_asterisk, _config.party_talk_by_ctrl)
	lines[0] = str(first["text"])
	_note_sent("\n".join(lines))
	session.send_text("\n".join(lines))


func _advance_history() -> void:
	## 送った文を履歴に入れ、境界を末尾まで進める。
	## キャレットを末尾に置き、表示も末尾までスクロールする。
	## 追加発言があれば、新しい下書きとして先に入れておく
	## (Philly の送信後の AddLine(TalkAdd))。
	var result := PhiInputHistory.advance(input_box.text, _history_boundary)
	input_box.text = str(result["text"])
	_history_boundary = int(result["boundary"])
	var last := maxi(input_box.get_line_count() - 1, 0)
	input_box.set_caret_line(last, true, true, 0, false)
	input_box.set_caret_column(input_box.get_line(last).length())
	_fill_draft_with_talk_add()


func clear_input_history() -> void:
	## 履歴部分だけを消し、下書きは残す。
	var result := PhiInputHistory.clear_history(input_box.text, _history_boundary)
	input_box.text = str(result["text"])
	_history_boundary = int(result["boundary"])
	var last := maxi(input_box.get_line_count() - 1, 0)
	input_box.set_caret_line(last, true, true, 0, false)
	input_box.set_caret_column(input_box.get_line(last).length())


func send_greeting() -> void:
	session.send_line(_config.alt_g_word)


func do_send_action(action_name: String) -> void:
	## メニュー・ツールバーの送信アクション(Cast1〜Cast7 は
	## 次のリストを抑える。Philly NextListCancel)。
	if action_name.length() == 5 and action_name.begins_with("Cast"):
		_suppress_lists = 1
	mark_list_answered()
	var action_text := PhiActions.send_text_for(action_name)
	_note_sent(action_text)
	session.send_text(action_text)


# -- 入力欄の右クリックメニュー(タグ挿入) -------------------------------------

func _on_input_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	_show_tag_popup()


func _show_tag_popup() -> void:
	if _tag_popup == null:
		_build_tag_popup()
	var pos := Vector2i(get_global_mouse_position())
	_tag_popup.popup(Rect2i(pos, Vector2i(1, 1)))


func _build_tag_popup() -> void:
	_tag_popup = PopupMenu.new()
	_tag_popup.id_pressed.connect(_on_tag_popup_pressed.bind(_tag_popup))
	add_child(_tag_popup)
	_tag_next_id = 0
	var children: Array = _tag_tree.get("children", [])
	for child in children:
		_add_tag_node(_tag_popup, child)
	_tag_popup.add_separator()
	_add_tag_action(_tag_popup, "切り取り", "cut")
	_add_tag_action(_tag_popup, "コピー", "copy")
	_add_tag_action(_tag_popup, "貼り付け", "paste")
	_add_tag_action(_tag_popup, "すべて選択", "select_all")
	_tag_popup.add_separator()
	_add_tag_action(_tag_popup, "履歴をクリア", "clear_history")
	var chrome_size := PhiFont.chrome_size_for_zoom(map_view.zoom)
	_tag_popup.add_theme_font_size_override("font_size", chrome_size)
	_tag_popup.add_theme_font_size_override("font_separator_size", chrome_size)


func _add_tag_node(parent: PopupMenu, node: Dictionary) -> void:
	var caption := PhiTagMenu.strip_mnemonic(str(node.get("caption", "")))
	if str(node.get("kind", "")) == "item":
		var id := _tag_next_id
		_tag_next_id += 1
		parent.add_item(caption, id)
		parent.set_item_metadata(parent.get_item_index(id), {"tag": str(node.get("tag", "")), "closetag": str(node.get("closetag", ""))})
		return
	var sub := PopupMenu.new()
	sub.name = "tag_sub_%d" % _tag_next_id
	_tag_next_id += 1
	sub.id_pressed.connect(_on_tag_popup_pressed.bind(sub))
	parent.add_child(sub)
	var chrome_size := PhiFont.chrome_size_for_zoom(map_view.zoom)
	sub.add_theme_font_size_override("font_size", chrome_size)
	sub.add_theme_font_size_override("font_separator_size", chrome_size)
	parent.add_submenu_item(caption, sub.name)
	var children: Array = node.get("children", [])
	for child in children:
		_add_tag_node(sub, child)


func _add_tag_action(parent: PopupMenu, caption: String, action: String) -> void:
	var id := _tag_next_id
	_tag_next_id += 1
	parent.add_item(caption, id)
	parent.set_item_metadata(parent.get_item_index(id), {"action": action})


func _on_tag_popup_pressed(id: int, popup: PopupMenu) -> void:
	var meta: Variant = popup.get_item_metadata(popup.get_item_index(id))
	if meta == null:
		return
	var data: Dictionary = meta
	if data.has("action"):
		match str(data["action"]):
			"cut":
				input_box.cut()
			"copy":
				input_box.copy()
			"paste":
				input_box.paste()
			"select_all":
				input_box.select_all()
			"clear_history":
				clear_input_history()
		return
	_insert_tag(str(data.get("tag", "")), str(data.get("closetag", "")))


func _insert_tag(tag: String, closetag: String) -> void:
	## 選択範囲があればタグで囲み、無ければタグを入れて
	## キャレットをタグと閉じタグの間に置く。
	input_box.grab_focus()
	var selected := input_box.get_selected_text()
	if not selected.is_empty():
		input_box.insert_text_at_caret(tag + selected + closetag)
		return
	var line := input_box.get_caret_line()
	var col := input_box.get_caret_column()
	input_box.insert_text_at_caret(tag + closetag)
	input_box.set_caret_line(line)
	input_box.set_caret_column(col + tag.length())


# -- ログの右クリックメニュー(コピー変種) -------------------------------------

func _on_log_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	_show_copy_popup()


func _show_copy_popup() -> void:
	if _copy_popup == null:
		_copy_popup = PopupMenu.new()
		_copy_popup.add_item("タグ付きでコピー", 0)
		_copy_popup.add_item("タグ無しでコピー", 1)
		_copy_popup.add_item("時刻を削除してコピー", 2)
		_copy_popup.add_item("名前を削除してコピー", 3)
		_copy_popup.add_item("タグを無効化してコピー", 4)
		_copy_popup.id_pressed.connect(_on_copy_popup_pressed)
		add_child(_copy_popup)
		var chrome_size := PhiFont.chrome_size_for_zoom(map_view.zoom)
		_copy_popup.add_theme_font_size_override("font_size", chrome_size)
		_copy_popup.add_theme_font_size_override("font_separator_size", chrome_size)
	var pos := Vector2i(get_global_mouse_position())
	_copy_popup.popup(Rect2i(pos, Vector2i(1, 1)))


func _on_copy_popup_pressed(id: int) -> void:
	var selected := log_view.get_selected_text()
	var text := selected if not selected.is_empty() else log_view.get_parsed_text()
	var result := ""
	match id:
		0:
			result = PhiLogCopy.with_tags(text, _log_lines)
		1:
			result = PhiLogCopy.strip_tags(text)
		2:
			result = PhiLogCopy.strip_time(text)
		3:
			result = PhiLogCopy.strip_name(text)
		4:
			result = PhiLogCopy.disable_tags(text)
	DisplayServer.clipboard_set(result)


# -- マウス操作(第3段) ---------------------------------------------------------

func _map_global_rect() -> Rect2:
	## 描いている地図の範囲(画面の座標)。
	if map_view == null or map_view.debug_event_empty():
		return Rect2()
	var local := map_view.drawn_map_rect()
	return Rect2(map_view.get_global_rect().position + local.position, local.size)


func _over_map(pos: Vector2) -> bool:
	return _map_global_rect().has_point(pos)


func _mouse_mods() -> String:
	## 今押している修飾キーから、移動キー表の修飾を決める。
	if Input.is_key_pressed(KEY_SHIFT):
		return "shift"
	if Input.is_key_pressed(KEY_CTRL):
		return "ctrl"
	return "none"


func _mouse_cursor_at(pos: Vector2) -> String:
	## 位置の方向カーソル名。地図の外や中心は ""。
	var rect := _map_global_rect()
	if rect.size.x <= 0.0 or not rect.has_point(pos):
		return ""
	var shift_ctrl := Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
	return PhiMouse.cursor_for(pos - rect.position, rect.size, north_fix_now(), shift_ctrl, float(map_view.zoom))


func _apply_mouse_cursor(cursor_name: String) -> void:
	## 方向カーソルを出す。スキンの .cur が無ければ既定カーソル。
	if cursor_name.is_empty():
		Input.set_custom_mouse_cursor(null)
		return
	var cursor: Variant = _assets.cursor_texture(cursor_name)
	if cursor == null:
		Input.set_custom_mouse_cursor(null)
		return
	Input.set_custom_mouse_cursor(cursor["texture"], Input.CURSOR_ARROW, cursor["hotspot"])


func _over_toolbar_panel(pos: Vector2) -> bool:
	return _toolbar_panel != null and _toolbar_panel.get_global_rect().has_point(pos)


func handle_mouse_button(ev: InputEventMouseButton) -> void:
	if ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			# 入力欄の外を左クリックしたらフォーカスを外す。
			if input_box != null and input_box.has_focus() and not input_box.get_global_rect().has_point(ev.position):
				input_box.release_focus()
			_start_mouse_hold(ev)
		else:
			_mouse_held = false
			_list_dragging = false
			_end_toolbar_drag()
	elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		# 右クリックは攻撃(Philly の MapForm)。ツールバーの上は除く。
		if _over_map(ev.position) and not _over_toolbar_panel(ev.position):
			session.send_line("hit")
			get_viewport().set_input_as_handled()
	elif ev.button_index == MOUSE_BUTTON_MIDDLE and ev.pressed:
		# 中クリックはマップ画像の保存(Philly の SSMap)。
		# ツールバーの上は除く。
		if _over_map(ev.position) and not _over_toolbar_panel(ev.position):
			screenshot_requested.emit()
			get_viewport().set_input_as_handled()


func _start_mouse_hold(ev: InputEventMouseButton) -> void:
	## 地図の長押し移動を始める。押した時点で1歩送る。
	_mouse_held = false
	if not _over_map(ev.position):
		return
	if _list_panel != null and _list_panel.visible and _list_panel.get_global_rect().has_point(ev.position):
		# リストの上のクリックはリスト任せ。
		return
	if _over_toolbar_panel(ev.position):
		# ツールバーの上のクリックはツールバー任せ。
		return
	var cursor := _mouse_cursor_at(ev.position)
	if cursor.is_empty():
		return
	_mouse_held = true
	_mouse_hold_cursor = cursor
	_mouse_hold_since = Time.get_ticks_msec()
	_mouse_last_repeat = 0
	_mouse_send_step()


func _mouse_send_step() -> void:
	## 今のカーソル方向へ1歩(斜めは2行)送る。
	if _mouse_hold_cursor.is_empty():
		return
	var commands := PhiMouse.move_commands(_mouse_hold_cursor, north_fix_now(), _mouse_mods())
	if commands.is_empty():
		return
	session.send_text("\n".join(commands))


func _mouse_repeat_send_if_ready() -> void:
	## 地図が届いた時の、長押し移動の次の一歩(Philly の MapRecv)。
	if not _mouse_held:
		return
	if _list_active or input_box.has_focus():
		return
	var now := Time.get_ticks_msec()
	if now - _mouse_hold_since < REPEAT_START_MS:
		return
	if _mouse_last_repeat > 0 and now - _mouse_last_repeat < REPEAT_MIN_INTERVAL_MS:
		return
	# 押している間にマウスが動いたら、方向を追いかける。
	var cursor := _mouse_cursor_at(_mouse_last_pos)
	if not cursor.is_empty():
		_mouse_hold_cursor = cursor
	_mouse_send_step()
	_mouse_last_repeat = now


func _mouse_repeat_fallback_tick() -> void:
	## 地図が届かない場所でも、500ms ごとに繰り返す。
	if not _mouse_held:
		return
	var now := Time.get_ticks_msec()
	if now - _mouse_hold_since < REPEAT_START_MS:
		return
	if _mouse_last_repeat > 0 and now - _mouse_last_repeat < REPEAT_FALLBACK_MS:
		return
	_mouse_repeat_send_if_ready()


func handle_mouse_motion(ev: InputEventMouseMotion) -> void:
	_mouse_last_pos = ev.position
	if _toolbar_dragging and _toolbar_panel != null:
		_move_toolbar_panel(ev.position - _toolbar_drag_offset)
		return
	if _list_dragging and _list_panel != null and _list_panel.visible:
		_move_list_panel(ev.position - _list_drag_offset)
		return
	var cursor := _mouse_cursor_at(ev.position)
	if cursor != _mouse_cursor_now:
		_mouse_cursor_now = cursor
		_apply_mouse_cursor(cursor)
	# 北固定で Shift/Ctrl を押したホバーは、その方向を向く。
	# 向きが変わった時だけ送る(Philly の NorthFixTurn)。
	var turn_cmd := ""
	if north_fix_now() and not _mouse_held and (ev.shift_pressed or ev.ctrl_pressed):
		var rect := _map_global_rect()
		if rect.has_point(ev.position):
			turn_cmd = PhiMouse.turn_command(ev.position - rect.position, rect.size, float(map_view.zoom))
	if turn_cmd.is_empty():
		_mouse_turn_dir = ""
	elif turn_cmd != _mouse_turn_dir:
		_mouse_turn_dir = turn_cmd
		session.send_line(turn_cmd)


# -- キー処理 ------------------------------------------------------------------

func handle_key(key_event: InputEventKey) -> bool:
	## キー処理。扱ったら true。Ctrl+Tab・Shift+F6・Alt+G は
	## 全体にかかるのでメイン画面が先に取り、ここには来ない。
	## 順序: (3)Esc (4)Tab (5)Enter (7)入力欄フォーカス時は
	## TextEdit 任せ (8)F1〜F12 (9)リストのキー (10)移動キー
	## (11)その他の送信キー。Ctrl+C はログの選択をそのまま写す。
	var code := PhiKeys.code_name(key_event.physical_keycode)
	if code.is_empty():
		code = PhiKeys.code_name(key_event.keycode)
	var shift := key_event.shift_pressed
	var ctrl := key_event.ctrl_pressed
	var alt := key_event.alt_pressed
	var meta := key_event.meta_pressed
	var is_escape := key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE
	# (3)Esc は入力欄からフォーカスを外す。入力欄にフォーカスが無く
	# リストが出ていれば、リストを取り消す(Philly と同じく `.` を送る)。
	if is_escape:
		if input_box.has_focus():
			input_box.release_focus()
		elif _list_active:
			_send_list_answer(".")
		return true
	# (4)Tab は入力欄へのフォーカスを切り替える
	if code == "Tab":
		if input_box.has_focus():
			input_box.release_focus()
		else:
			input_box.grab_focus()
		return true
	# (5)Enter。入力欄にフォーカスがあれば送信する。Shift+Enter は
	# そのまま TextEdit に渡し、改行を入れる。Ctrl+Enter は
	# パーティー発言(Philly PartyTalkByCtrl)。
	# 入力欄にフォーカスが無くリストが出ていれば、選んだ行を送る。
	var is_enter := key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER or key_event.physical_keycode == KEY_ENTER or key_event.physical_keycode == KEY_KP_ENTER
	if is_enter:
		if input_box.has_focus():
			if not shift:
				submit_input(ctrl)
				return true
			return false
		if _list_active and not alt and not meta:
			# 修飾キー無し・Shift・Ctrl の Enter はどれも決定
			# (Philly の KeyBindListMode の OK)。
			_send_list_selected()
			return true
	# Ctrl+C は、入力欄にフォーカスが無ければログの選択を写す。
	if ctrl and not shift and not alt and code == "KeyC" and not input_box.has_focus():
		var selected := log_view.get_selected_text()
		if not selected.is_empty():
			DisplayServer.clipboard_set(selected)
			return true
	# (6)追加発言の呼び出しと、(7)入力欄フォーカス時は TextEdit 任せ。
	# ↓ の呼び出しは TextEdit のキャレット移動より先に見る。
	if input_box.has_focus():
		if _try_talk_add_recall(code, shift, ctrl, alt, meta):
			return true
		return false
	# (8)F1〜F7 は呪文、F8〜F12 は自由ショートカット。修飾キー無しの時だけ。
	if not shift and not ctrl and not alt and not meta:
		if code.begins_with("F") and code.length() <= 3 and code.substr(1).is_valid_int():
			var fno := int(code.substr(1))
			if fno >= 1 and fno <= 7:
				on_magic_key(fno)
				return true
			if fno >= 8 and fno <= 12:
				on_shortcut_key(fno)
				return true
	# (9)リストが出ている間のキー(Philly KeyBindListMode)。
	if _list_active and handle_list_key(code, shift, ctrl, alt):
		return true
	# (10)移動キー。押した時点で1歩送り、押し続けの記録にも入れる。
	var moved: Variant = PhiKeys.move_input(code, shift, ctrl, alt, meta, true)
	if moved != null:
		press_held_move(key_event, str(moved[0]), str(moved[1]))
		session.send_line(PhiKeys.move_command(str(moved[0]), str(moved[1]), north_fix_now()))
		return true
	# (11)その他の送信キー(攻撃・看板など)。繰り返しはしない。
	var send := PhiKeys.key_send(code, shift, ctrl, alt, meta, true)
	if not send.is_empty():
		session.send_text(send)
		return true
	return false


# -- エフェクトの試し表示 ------------------------------------------------------

func fx_demo_tick() -> void:
	## 試し表示: 地図のキャラを使い、戦闘のログと発言を定期的に出します。
	## モックサーバは戦闘ログを出さないので、ここで合成します。
	## --fx-demo の時だけ動き、通常のプレイには影響しません。
	if _demo_chars.is_empty():
		return
	var names: Array[String] = []
	var foes: Array[String] = []
	var center_names: Array[String] = []
	var center := Vector2i(_demo_dim / 2, _demo_dim / 2)
	for ch in _demo_chars:
		var nm := PhiTags.strip_tags(str(ch.get("name", ""))).strip_edges()
		if nm.is_empty():
			continue
		names.append(nm)
		if Vector2i(int(ch.get("x", -1)), int(ch.get("y", -1))) == center:
			center_names.append(nm)
		else:
			foes.append(nm)
	if names.is_empty():
		return
	var me := _player_name
	if me.is_empty() and not center_names.is_empty():
		me = center_names[0]
	if me.is_empty():
		me = names[0]
	var foe := foes[0] if not foes.is_empty() else me
	var speaker: String = names[_fx_demo_step % names.size()]
	var phrase: String = _FX_DEMO_PHRASES[_fx_demo_step % _FX_DEMO_PHRASES.size()]
	match _fx_demo_step % 6:
		0:
			_on_event({"type": "message", "channel": "talk", "text": "%s > %s" % [speaker, phrase], "from": speaker})
		1:
			_on_event({"type": "message", "channel": "log", "text": "DM > %s は %s を ロングソード で攻撃した. [42 hp]" % [me, foe]})
		2:
			_on_event({"type": "message", "channel": "log", "text": "DM > %s は魔法を唱えている... " % foe})
			_on_event({"type": "message", "channel": "log", "text": "DM > %s は %s を Harm で攻撃した. [35 hp]" % [foe, me]})
		3:
			_on_event({"type": "message", "channel": "log", "text": "DM > %s は %s を キュアー で回復した. [28 hp]" % [foe, me]})
		4:
			_on_event({"type": "message", "channel": "log", "text": "DM > %s は %s に殺された. " % [foe, me]})
		5:
			_on_event({"type": "message", "channel": "log", "text": "%s > %s" % [speaker, phrase]})
	_fx_demo_step += 1


# -- 参照とデバッグ ------------------------------------------------------------

func player_name() -> String:
	return _player_name


func debug_input_text() -> String:
	return input_box.text


func debug_input_focus() -> bool:
	return input_box.has_focus()


func debug_log_text() -> String:
	return log_view.get_parsed_text()


func debug_map_zoom() -> int:
	return map_view.zoom


func debug_map_size() -> Vector2:
	return map_view.size
