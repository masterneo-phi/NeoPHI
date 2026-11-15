extends Control
## NeoPHI Godot 版試作のメイン画面。
##
## 地図＋ログ＋入力欄＋状態表示。接続先とグラフィックスの場所はコマンドライン
## 引数で渡す(`--` の後に書く)。グラフィックスの指定が無い時は、実行ファイルの
## あるフォルダ直下 → .app の入ったフォルダ直下 → カレントディレクトリ直下 →
## 開発用の ~/workspace/phi-option-data の順に `chip_tofup` / `chara_tofup` を探す。例:
##   godot --path . -- --host 127.0.0.1 --port 20017 --id guest
##   --chip-dir ~/workspace/phi-option-data/chip_tofup
##   --chara-dir ~/workspace/phi-option-data/chara_tofup

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 20017
const DEFAULT_ID := "guest"

var _session := PhiSession.new()
var _assets := GameAssets.new()
var _config := PhiConfig.new()
var _config_path := PhiConfig.DEFAULT_PATH
var _no_config := false
var _config_loaded := false
var _map_view: MapView = null
var _log: RichTextLabel = null
var _split: HSplitContainer = null
var _split_init_done := false
var _input_box: TextEdit = null
var _status_label: Label = null
var _conn_label: Label = null
var _hint_label: Label = null
var _applied_font_size := 0
var _font: Font = null
var _menu_buttons: Array[MenuButton] = []
var _menu_popups: Array[PopupMenu] = []
var _toolbar_buttons: Array[Button] = []
var _scroll_popup: PopupMenu = null
var _scroll_item := -1
var _ask_dialog: ConfirmationDialog = null
var _ask_label: Label = null
var _ask_edit: LineEdit = null
var _ask_action := ""
var _about_dialog: AcceptDialog = null
var _system_color: Variant = null
var _error_color: Variant = null

var _player_name := ""
var _world := ""
var _area := ""
var _mapset := ""
var _status_text := ""
var _cond_text := ""

var _shot_path := ""
var _shot_delay := 0.0
var _elapsed := 0.0
var _shot_done := false
var _was_open := false
var _keytest: Array[String] = []
var _assets_warning := ""

## 第2段: 移動の繰り返し(Philly classMoveCommand)。
## キーを押してからこの時間(ms)経つと繰り返しが始まる。
const REPEAT_START_MS := 200
## 地図が届かない時の繰り返しの間隔(ms)。Philly の 500ms の
## フォールバック(MOVE_CHECK_INTERVAL)にあたる。
const REPEAT_FALLBACK_MS := 500
## 繰り返し送信の最小間隔(ms)。サーバは1行/0.1秒しか処理しない
## (wphi 仕様 §10.1)ので、それより速く送らない。
const REPEAT_MIN_INTERVAL_MS := 120
## 押したままの移動キー。{code: 物理キー, key: 移動キー, mods: 修飾}。
## 後ろのものほど新しく押したもの。
var _held_moves: Array[Dictionary] = []
var _held_since := 0
var _last_repeat_send := 0
## 最新の地図の大きさ(マスの数 7/5)と様式。移動キー表(北固定/回転)の
## 切替に使う。まだ地図が来ていなければ設定の値を使う。
var _map_dim_now := 0
var _map_style_now := ""
## 第2段: 大声(Philly classCommand::Loud)。
var _loud := false
var _loud_all := false
var _loud_dialog: ConfirmationDialog = null
var _loud_pending := ""
var _loud_pending_party := false
var _loud_popup: PopupMenu = null
var _loud_item := -1
## 第2段: リストの抑え込み(Philly NextListCancel)。次のリストを
## この数だけ、表示もログも出さずに飲み込む。
var _suppress_lists := 0
## 第2段: リストのオーバーレイ表示。
var _list_active := false
var _list_lines: Array[String] = []
var _list_panel: PanelContainer = null
var _list_box: ItemList = null
## 第2段: priv ウィンドウ。_users は #user の一覧({key, name})。
var _users: Array[Dictionary] = []
var _priv_window: Window = null
var _priv_box_holder: VBoxContainer = null
var _priv_boxes: Array[CheckBox] = []
var _priv_log: RichTextLabel = null
var _priv_edit: LineEdit = null
var _priv_opened_once := false
## 第2段: ショートカット設定ダイアログ。
var _shortcut_dialog: ConfirmationDialog = null
var _shortcut_magic_edits: Array[LineEdit] = []
var _shortcut_fix_check: CheckBox = null
var _shortcut_free_edits: Array[LineEdit] = []
var _shortcut_list_edits: Array[LineEdit] = []
var _shortcut_alt_edit: LineEdit = null

## エフェクトの試し表示(--fx-demo)で吹き出しに出す言葉。
const _FX_DEMO_PHRASES := [
	"こんにちは",
	"いらっしゃい",
	"今日はいい天気だね",
	"一緒に冒険しない？",
	"この先の洞窟には強いモンスターがいるから気をつけてね",
]
var _fx_demo := false
var _fx_demo_in := 2.0
var _fx_demo_step := 0
var _demo_chars: Array = []
var _demo_dim := 7


func _ready() -> void:
	var args := _user_args()
	_no_config = args.has("no-config")
	if args.has("config"):
		_config_path = str(args["config"])
	if not _no_config:
		_config_loaded = _config.load_file(_config_path)
	_limit_window_to_screens()
	# 保存してある窓の大きさに戻す。--resolution 指定時はそちらを優先する。
	if _config_loaded and not OS.get_cmdline_args().has("--resolution"):
		get_window().size = Vector2i(_config.window_width, _config.window_height)
	_font = _make_font()
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 15
	theme.set_font("font", "Label", _font)
	theme.set_font_size("font_size", "Label", 15)
	self.theme = theme
	_apply_args(args)
	_build_ui()
	_apply_ui_font_size()
	_apply_scroll_stop()
	_update_action_states()
	_session.event_received.connect(_on_event)
	_session.session_error.connect(_on_session_error)
	_session.session_closed.connect(_on_session_closed)
	_log_message("system", "NeoPHI Godot 版試作")
	if not _assets_warning.is_empty():
		_log_message("system", _assets_warning)
	_connect()
	if not _keytest.is_empty():
		_run_keytest()


func _make_font() -> Font:
	## 日本語の出るシステムフォントを探す。無ければ既定のフォント。
	var names := [
		"Noto Sans CJK JP", "Noto Sans CJK", "Noto Sans JP",
		"Hiragino Sans", "Hiragino Kaku Gothic ProN",
		"Yu Gothic UI", "Yu Gothic", "Meiryo", "MS Gothic",
		"TakaoGothic", "IPAexGothic",
	]
	var font := SystemFont.new()
	font.font_names = names
	return font


func _limit_window_to_screens() -> void:
	## 画面より大きな窓は macOS の OpenGL 描画経路で落ちることがあるため、
	## 全画面のうち最大のものを窓サイズの上限にする(全画面化はできる)。
	var max_w := 0
	var max_h := 0
	for i in DisplayServer.get_screen_count():
		var s := DisplayServer.screen_get_size(i)
		max_w = maxi(max_w, s.x)
		max_h = maxi(max_h, s.y)
	if max_w > 0 and max_h > 0:
		get_window().max_size = Vector2i(max_w, max_h)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_build_menu_bar(root)
	_build_toolbar(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	_status_label = Label.new()
	_status_label.text = "未接続"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status_label)
	_conn_label = Label.new()
	_conn_label.text = ""
	top.add_child(_conn_label)

	# 地図とログはドラッグで幅を変えられる分割式。Philly のように
	# ログを広く取れる。初期位置は地図 55%・ログ 45%。
	var middle := HSplitContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 6)
	middle.resized.connect(_on_split_resized)
	root.add_child(middle)
	_split = middle

	_map_view = MapView.new()
	_map_view.label_font = _font
	_map_view.zoom_changed.connect(_on_map_zoom_changed)
	middle.add_child(_map_view)
	_build_list_overlay()

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(280, 0)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.bbcode_enabled = false
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.focus_mode = Control.FOCUS_NONE
	middle.add_child(_log)
	_apply_log_css()

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	root.add_child(bottom)
	_input_box = TextEdit.new()
	_input_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_box.placeholder_text = "入力欄 (Enter で送信、Shift+Enter で改行、Esc で移動キーへ、Tab で入力欄へ)"
	_input_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	bottom.add_child(_input_box)
	_hint_label = Label.new()
	_hint_label.text = "矢印キー: 移動"
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_hint_label)


func _build_menu_bar(root: VBoxContainer) -> void:
	## Philly のメニューバー(ファイル/行動/魔法/表示/ツール)。
	## スキンの Style/Menu.txt で off のメニューは出さない。
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	root.add_child(bar)
	var visibility := _assets.menu_visibility()
	for menu in PhiActions.MENUS:
		var menu_name := str(menu["name"])
		if visibility.get(menu_name, true) == false:
			continue
		var button := MenuButton.new()
		button.text = menu_name
		button.focus_mode = Control.FOCUS_NONE
		bar.add_child(button)
		_menu_buttons.append(button)
		var popup := button.get_popup()
		_menu_popups.append(popup)
		var item_id := 0
		for item in menu["items"]:
			var action_name := str(item)
			if action_name == "-":
				popup.add_separator()
				continue
			var action := PhiActions.get_action(action_name)
			if action.is_empty():
				continue
			if action_name == "LogScrollStop":
				popup.add_check_item(str(action["caption"]), item_id)
				_scroll_popup = popup
				_scroll_item = popup.get_item_index(item_id)
			elif action_name == "Loud":
				popup.add_check_item(str(action["caption"]), item_id)
				_loud_popup = popup
				_loud_item = popup.get_item_index(item_id)
			else:
				popup.add_item(str(action["caption"]), item_id)
			var index := popup.get_item_index(item_id)
			popup.set_item_metadata(index, action_name)
			popup.set_item_tooltip(index, str(action["hint"]))
			var icon: Variant = _assets.button_icon(action_name)
			if icon != null:
				popup.set_item_icon(index, icon)
			item_id += 1
		popup.id_pressed.connect(_on_menu_id_pressed.bind(popup))


func _on_menu_id_pressed(item_id: int, popup: PopupMenu) -> void:
	var index := popup.get_item_index(item_id)
	var action_name := str(popup.get_item_metadata(index))
	_do_action(action_name)


func _build_toolbar(root: VBoxContainer) -> void:
	## Philly のツールバー。スキンにボタン絵があれば絵だけ、無ければ
	## 短い文字で出す。ヒントは Philly の表示名と同じ。
	## ボタンが多いので横スクロールに入れ、窓の幅を押し広げない。
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	scroll.add_child(bar)
	for item in PhiActions.TOOLBAR:
		var action_name := str(item)
		if action_name == "-":
			bar.add_child(VSeparator.new())
			continue
		var action := PhiActions.get_action(action_name)
		if action.is_empty():
			continue
		var button := Button.new()
		button.tooltip_text = str(action["hint"])
		button.focus_mode = Control.FOCUS_NONE
		button.expand_icon = true
		if action_name == "Loud":
			button.toggle_mode = true
		var icon: Variant = _assets.button_icon(action_name)
		if icon != null:
			button.icon = icon
		else:
			button.text = _short_caption(str(action["caption"]))
		button.pressed.connect(_do_action.bind(action_name))
		button.set_meta("action", action_name)
		bar.add_child(button)
		_toolbar_buttons.append(button)


func _short_caption(caption: String) -> String:
	## ツールバー用の短い表示名。`自動装備 [Q,/]` → `自動装備`。
	var bracket := caption.find(" [")
	if bracket >= 0:
		return caption.substr(0, bracket)
	return caption


func _build_list_overlay() -> void:
	## #list の内容を地図の上に重ねるパネル。普段は隠れている。
	## MapView は mouse_filter=IGNORE だが、子のコントロールは
	## 入力を受け取り、上に描かれる。
	_list_panel = PanelContainer.new()
	_list_panel.visible = false
	_list_panel.position = Vector2(8, 8)
	_map_view.add_child(_list_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_list_panel.add_child(box)
	_list_box = ItemList.new()
	_list_box.select_mode = ItemList.SELECT_SINGLE
	_list_box.allow_reselect = true
	_list_box.item_selected.connect(_on_list_row_selected)
	_list_box.item_activated.connect(_on_list_row_activated)
	box.add_child(_list_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	var ok := Button.new()
	ok.text = "決定"
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(_on_list_ok_pressed)
	buttons.add_child(ok)
	var cancel := Button.new()
	cancel.text = "キャンセル"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_on_list_cancel_pressed)
	buttons.add_child(cancel)


func _apply_log_css() -> void:
	## スキンの Style/Log.css の body の背景色・文字色をログに使う。
	## システムメッセージの色(.class_system_ok/.class_system_ng)も
	## 拾う。CSS が無ければ何もしない。
	var css := _assets.log_css()
	var body: Dictionary = css.get("body", {})
	var bg: Variant = SkinFiles.parse_css_color(str(body.get("background", "")))
	if bg != null:
		var box := StyleBoxFlat.new()
		box.bg_color = bg
		_log.add_theme_stylebox_override("normal", box)
	var fg: Variant = SkinFiles.parse_css_color(str(body.get("color", "")))
	if fg != null:
		_log.add_theme_color_override("default_color", fg)
	var classes: Dictionary = css.get("classes", {})
	var ok: Dictionary = classes.get("class_system_ok", {})
	_system_color = SkinFiles.parse_css_color(str(ok.get("color", "")))
	var ng: Dictionary = classes.get("class_system_ng", {})
	_error_color = SkinFiles.parse_css_color(str(ng.get("color", "")))


func _on_map_zoom_changed(_new_zoom: int) -> void:
	_apply_ui_font_size()


func _apply_ui_font_size() -> void:
	## 地図の倍率に比例して UI の文字を大きくする(8 * zoom)。
	## 入力欄の高さは 3 行分＋余白にし、フォントサイズに連動させる。
	var size := 8 * _map_view.zoom
	if size == _applied_font_size:
		return
	_applied_font_size = size
	# RichTextLabel の既定文字サイズは normal_font_size(他も揃える)。
	_log.add_theme_font_size_override("font_size", size)
	_log.add_theme_font_size_override("normal_font_size", size)
	_log.add_theme_font_size_override("bold_font_size", size)
	_log.add_theme_font_size_override("italics_font_size", size)
	_log.add_theme_font_size_override("bold_italics_font_size", size)
	_log.add_theme_font_size_override("mono_font_size", size)
	_input_box.add_theme_font_size_override("font_size", size)
	_status_label.add_theme_font_size_override("font_size", size)
	_conn_label.add_theme_font_size_override("font_size", size)
	_hint_label.add_theme_font_size_override("font_size", size)
	if _list_box != null:
		_list_box.add_theme_font_size_override("font_size", size)
	if _priv_log != null:
		_priv_log.add_theme_font_size_override("font_size", size)
		_priv_log.add_theme_font_size_override("normal_font_size", size)
		_priv_log.add_theme_font_size_override("bold_font_size", size)
		_priv_log.add_theme_font_size_override("italics_font_size", size)
		_priv_log.add_theme_font_size_override("bold_italics_font_size", size)
		_priv_log.add_theme_font_size_override("mono_font_size", size)
	_input_box.custom_minimum_size = Vector2(0, _font.get_height(size) * 3 + 16)
	for button in _menu_buttons:
		button.add_theme_font_size_override("font_size", size)
	for button in _toolbar_buttons:
		button.add_theme_font_size_override("font_size", size)
		var min_size := Vector2(0, size + 12)
		if button.icon != null:
			min_size.x = size + 12
		button.custom_minimum_size = min_size


func _apply_args(args: Dictionary) -> void:
	## 設定ファイルの値を既定にし、コマンドライン引数で上書きする。
	var host: String = args.get("host", _config.host)
	var port: int = int(args.get("port", str(_config.port)))
	var char_id: String = args.get("id", DEFAULT_ID)
	_session.map_size = int(args.get("map-size", str(_config.map_size)))
	var style_arg := str(args.get("map-style", _config.map_style)).to_lower()
	_session.map_style = style_arg if style_arg == "turn" else "solid"
	_shot_path = args.get("shot", "")
	_shot_delay = float(args.get("shot-delay", "0"))
	_fx_demo = args.has("fx-demo")
	if args.has("keytest"):
		for part in str(args["keytest"]).split(",", false):
			_keytest.append(part.strip_edges())
	var chip_dirs: Array[String] = []
	var chara_dirs: Array[String] = []
	var philly_roots: Array[String] = []
	var missing: Array[String] = []
	if args.has("chip-dir"):
		chip_dirs.append(args["chip-dir"])
	else:
		var found_chip := _find_asset_dir("chip_tofup")
		if found_chip.is_empty():
			missing.append("chip_tofup")
		else:
			chip_dirs.append(found_chip)
	if args.has("chara-dir"):
		for part in str(args["chara-dir"]).split(",", false):
			chara_dirs.append(part)
	else:
		var found_chara := _find_asset_dir("chara_tofup")
		if found_chara.is_empty():
			missing.append("chara_tofup")
		else:
			chara_dirs.append(found_chara)
	if not missing.is_empty():
		_assets_warning = "グラフィックスのフォルダが見つかりません: " + "、".join(missing)
	if args.has("assets-dir"):
		philly_roots.append(args["assets-dir"])
	else:
		# スキンは既定で探す。--assets-dir 指定時はそちらを優先する。
		var skin_name := str(args.get("skin", _config.skin))
		var found_root := GameAssets.find_philly_root(skin_name, _philly_root_bases())
		if not found_root.is_empty():
			philly_roots.append(found_root)
	if philly_roots.is_empty():
		var skin_part := "Skins/" + str(args.get("skin", _config.skin))
		if _assets_warning.is_empty():
			_assets_warning = "スキンフォルダが見つかりません: " + skin_part
		else:
			_assets_warning += "、" + skin_part
	_assets.setup(philly_roots, chip_dirs, chara_dirs, args.get("skin", _config.skin))
	_assets.default_chara_file = args.get("default-chara", "")
	_assets.items_file = args.get("items", "")
	set_meta("host", host)
	set_meta("port", port)
	set_meta("char_id", char_id)


func _find_asset_dir(kind: String) -> String:
	## 既定のグラフィックスフォルダを探す。見つからなければ "" を返す。
	## 探す順序: (1)実行ファイルのあるフォルダ直下、(2)macOS の .app の
	## 場合はバンドルを含むフォルダ直下、(3)カレントディレクトリ直下、
	## (4)開発用の ~/workspace/phi-option-data。
	var exe_path := OS.get_executable_path()
	var exe_dir := exe_path.get_base_dir()
	var candidates: Array[String] = []
	candidates.append(exe_dir.path_join(kind))
	if exe_path.contains(".app/"):
		var bundle_parent := exe_dir.get_base_dir().get_base_dir().get_base_dir()
		candidates.append(bundle_parent.path_join(kind))
	candidates.append(kind)
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		candidates.append(home.path_join("workspace/phi-option-data").path_join(kind))
	for candidate in candidates:
		if DirAccess.open(candidate) != null:
			return candidate
	return ""


func _philly_root_bases() -> Array[String]:
	## Philly ルート(`Skins/<スキン名>/` を含むフォルダ)を探す土台。
	## _find_asset_dir と同じ順序: (1)実行ファイルのあるフォルダ直下、
	## (2).app の場合はバンドルを含むフォルダ直下、(3)カレント直下、
	## (4)開発用フォルダ。
	var bases: Array[String] = []
	var exe_path := OS.get_executable_path()
	var exe_dir := exe_path.get_base_dir()
	bases.append(exe_dir)
	if exe_path.contains(".app/"):
		bases.append(exe_dir.get_base_dir().get_base_dir().get_base_dir())
	bases.append(".")
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		bases.append(home.path_join("workspace/phi-option-data"))
		bases.append(home.path_join("workspace/philly-source/PhillySrc/Philly"))
	return bases


func _user_args() -> Dictionary:
	## `-- --key value --flag` の形の引数を読む。
	var out := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg.begins_with("--"):
			var key := arg.substr(2)
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[key] = args[i + 1]
				i += 2
			else:
				out[key] = "1"
				i += 1
		else:
			i += 1
	return out


func _connect() -> void:
	var host: String = get_meta("host")
	var port: int = get_meta("port")
	var char_id: String = get_meta("char_id")
	_conn_label.text = "%s:%d" % [host, port]
	_log_message("system", "%s:%d に接続します..." % [host, port])
	_session.connect_to(host, port, char_id)
	_update_action_states()


func _update_action_states() -> void:
	## 接続状態に合わせてメニューとツールバーの有効・無効を変える。
	var connected := _session.is_open()
	for popup in _menu_popups:
		for i in popup.item_count:
			var meta: Variant = popup.get_item_metadata(i)
			if meta == null:
				continue
			var action_name := str(meta)
			popup.set_item_disabled(i, not PhiActions.enabled_when(action_name, connected))
	if _scroll_popup != null and _scroll_item >= 0:
		_scroll_popup.set_item_checked(_scroll_item, _config.scroll_stop)
	if _loud_popup != null and _loud_item >= 0:
		_loud_popup.set_item_checked(_loud_item, _loud)
	for button in _toolbar_buttons:
		var action_name := str(button.get_meta("action"))
		button.disabled = not PhiActions.enabled_when(action_name, connected)
		if action_name == "Loud":
			button.set_pressed_no_signal(_loud)


func _apply_scroll_stop() -> void:
	if _log != null:
		_log.scroll_following = not _config.scroll_stop


func _on_split_resized() -> void:
	## 分割位置の初期化。大きさが決まった最初の1回だけ、
	## 保存された位置か、無ければ地図 55% の位置に置く。
	## あとはドラッグした位置を HSplitContainer が保つ。
	if _split_init_done or _split == null or _split.size.x < 320:
		return
	_split_init_done = true
	_split.split_offset = _config.initial_split_offset(int(_split.size.x))


func _save_config() -> void:
	if _no_config:
		return
	_config.window_width = get_window().size.x
	_config.window_height = get_window().size.y
	if _split != null:
		_config.split_offset = _split.split_offset
	_config.save_file(_config_path)


func _quit() -> void:
	_save_config()
	_session.disconnect_graceful()
	get_tree().quit()


func _process(delta: float) -> void:
	_session.poll()
	var now_open := _session.is_open()
	if now_open != _was_open:
		_was_open = now_open
		_update_action_states()
	if _fx_demo:
		_fx_demo_in -= delta
		if _fx_demo_in <= 0.0:
			_fx_demo_tick()
			_fx_demo_in = 2.5
	_repeat_fallback_tick()
	if _shot_path != "" and not _shot_done:
		_elapsed += delta
		if _elapsed >= _shot_delay:
			_shot_done = true
			_take_shot()


func _fx_demo_tick() -> void:
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


func _run_keytest() -> void:
	## テスト用: 指定したキーを実際に押されたものとして流し込む。
	## _input の経路を通るので、移動キーの処理を画面付きで確かめられる。
	## X11 からのキー配送自体は Godot 任せ。
	await get_tree().create_timer(1.0).timeout
	for key_name in _keytest:
		if key_name.begins_with("type:"):
			var text := key_name.substr(5)
			for i in text.length():
				var ev := InputEventKey.new()
				ev.unicode = text.unicode_at(i)
				ev.pressed = true
				Input.parse_input_event(ev)
				await get_tree().create_timer(0.05).timeout
			print("keytest: typed '", text, "' focus=", _input_box.has_focus(), " text=[", _input_box.text, "]")
			continue
		var key_part := key_name
		var modifiers := PackedStringArray()
		if key_name.contains("+"):
			var parts := key_name.split("+")
			key_part = parts[parts.size() - 1]
			modifiers = parts.slice(0, parts.size() - 1)
		var code := OS.find_keycode_from_string(key_part)
		if code == KEY_NONE:
			printerr("keytest: 不明なキー: ", key_name)
			continue
		var press := InputEventKey.new()
		press.keycode = code
		press.pressed = true
		press.shift_pressed = modifiers.has("Shift")
		press.ctrl_pressed = modifiers.has("Ctrl")
		press.alt_pressed = modifiers.has("Alt")
		press.meta_pressed = modifiers.has("Meta")
		Input.parse_input_event(press)
		await get_tree().create_timer(0.35).timeout
		print("keytest: key ", key_name, " focus=", _input_box.has_focus(), " text=[", _input_box.text, "]")
		var release := InputEventKey.new()
		release.keycode = code
		release.pressed = false
		release.shift_pressed = press.shift_pressed
		release.ctrl_pressed = press.ctrl_pressed
		release.alt_pressed = press.alt_pressed
		release.meta_pressed = press.meta_pressed
		Input.parse_input_event(release)
		await get_tree().create_timer(0.1).timeout
		var owner := get_viewport().gui_get_focus_owner()
		print("keytest: after ", key_name, " focus_owner=", owner, " input_focus=", _input_box.has_focus(), " text=[", _input_box.text, "]")


func _take_shot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	if err == OK:
		print("screenshot: ", _shot_path)
	else:
		printerr("screenshot failed: ", error_string(err))
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# 窓からフォーカスが外れたら、押し続けている移動キーを離した扱いにする。
		_held_moves.clear()


func _submit_input_box(party: bool = false) -> void:
	var text := _input_box.text
	_input_box.text = ""
	if text.is_empty():
		return
	_mark_list_answered()
	# TextEdit は複数行を持てる。空行は `/**/` にする(最終行の
	# 空行は除く)。Philly の EditSendNullLine にあたる。
	var lines := text.split("\n")
	for i in range(lines.size()):
		if lines[i].is_empty() and i < lines.size() - 1:
			lines[i] = "/**/"
	text = "\n".join(lines)
	# 大声ボタンが on なら、送る前に確認ダイアログを出す。
	if _loud and not _loud_all:
		_loud_pending = text
		_loud_pending_party = party
		_show_loud_dialog()
		return
	_send_speech_text(text, party)


func _send_speech_text(text: String, party: bool) -> void:
	## 発言を Philly の順序で変換して送る。`/**/` の差し込みや
	## パーティーの `+` は、行頭(入力全体の先頭)だけに付ける。
	if _loud:
		_session.send_text("*" + text)
		return
	var lines := text.split("\n")
	var first := PhiShortcuts.speech_transform(
		lines[0], party, false, false,
		_config.loudly_by_asterisk, _config.party_talk_by_ctrl)
	lines[0] = str(first["text"])
	_session.send_text("\n".join(lines))


func _do_action(action_name: String) -> void:
	match PhiActions.kind_of(action_name):
		"send":
			# Cast1〜Cast7 は次のリストを抑える(Philly NextListCancel)。
			if action_name.length() == 5 and action_name.begins_with("Cast"):
				_suppress_lists = 1
			_mark_list_answered()
			_session.send_text(PhiActions.send_text_for(action_name))
			_remember_map_mode(action_name)
		"ask":
			_ask_text(action_name)
		"priv-window":
			_show_priv_window()
		"loud-toggle":
			_set_loud(not _loud)
		"shortcut-config":
			_show_shortcut_dialog()
		"connect":
			_connect()
		"disconnect":
			_session.disconnect_graceful()
			_on_session_closed()
		"exit":
			_quit()
		"reload-config":
			_config.load_file(_config_path)
			_apply_scroll_stop()
			_update_action_states()
			_log_message("system", "設定ファイルを読み込みました(スキンと地図の大きさは次回起動から有効です)")
		"reset-config":
			_config.reset()
			_save_config()
			_apply_scroll_stop()
			_update_action_states()
			_log_message("system", "初期設定に戻しました(スキンと地図の大きさは次回起動から有効です)")
		"clear-cache":
			_assets.clear_cache()
			_log_message("system", "グラフィックスのキャッシュを初期化しました")
		"screenshot":
			_save_screenshot()
		"scroll-toggle":
			_config.scroll_stop = not _config.scroll_stop
			_apply_scroll_stop()
			_update_action_states()
			_save_config()
		"open-config-folder":
			OS.shell_open(ProjectSettings.globalize_path("user://"))
		"about":
			_show_about()


func _remember_map_mode(action_name: String) -> void:
	## 地図モードの変更は設定に覚えて、次回ログイン時にも使う。
	match action_name:
		"M5x5":
			_config.map_size = 40
		"M7x7":
			_config.map_size = 57
		"MTurn":
			_config.map_style = "turn"
		"MSolid":
			_config.map_style = "solid"
		_:
			return
	_session.map_size = _config.map_size
	_session.map_style = _config.map_style
	_save_config()


func _ask_text(action_name: String) -> void:
	## 言葉を聞いてから送るアクション(Pay/Search/Appear/Disappear)。
	var action := PhiActions.get_action(action_name)
	if action.is_empty():
		return
	if _ask_dialog == null:
		_ask_dialog = ConfirmationDialog.new()
		_ask_dialog.theme = _dialog_theme()
		_ask_dialog.ok_button_text = "送信"
		_ask_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		_ask_label = Label.new()
		box.add_child(_ask_label)
		_ask_edit = LineEdit.new()
		box.add_child(_ask_edit)
		_ask_dialog.add_child(box)
		_ask_dialog.confirmed.connect(_on_ask_confirmed)
		_ask_edit.text_submitted.connect(_on_ask_submitted)
		add_child(_ask_dialog)
	_ask_action = action_name
	_ask_dialog.title = str(action["title"])
	_ask_label.text = str(action["label"])
	_ask_edit.text = ""
	_ask_dialog.popup_centered(Vector2i(320, 120))
	_ask_edit.grab_focus()


func _on_ask_submitted(_text: String) -> void:
	_ask_dialog.hide()
	_on_ask_confirmed()


func _on_ask_confirmed() -> void:
	var answer := _ask_edit.text.strip_edges()
	if answer.is_empty():
		return
	var action := PhiActions.get_action(_ask_action)
	if bool(action.get("integer", false)):
		if not answer.is_valid_int() or int(answer) < 0:
			_log_message("error", "0 以上の整数を入力してください")
			return
		answer = str(int(answer))
	_session.send_text(PhiActions.build_ask_text(_ask_action, answer))


func _save_screenshot() -> void:
	## マップ画像の保存。Philly の ScreenShot/ フォルダ相当に置く。
	await get_tree().process_frame
	await get_tree().process_frame
	var dir := "user://ScreenShot"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "_")
	var path := "%s/NeoPHI_%s.png" % [dir, stamp]
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		_log_message("system", "マップ画像を保存しました: " + path)
	else:
		_log_message("error", "マップ画像の保存に失敗しました: " + error_string(err))


func _show_about() -> void:
	if _about_dialog == null:
		_about_dialog = AcceptDialog.new()
		_about_dialog.theme = _dialog_theme()
		_about_dialog.title = "バージョン情報"
		_about_dialog.ok_button_text = "閉じる"
		var label := Label.new()
		label.text = "NeoPHI Godot 版試作\n\nPhilly と wphi の仕様をもとに作っている PHI クライアントです。\nGodot " + str(Engine.get_version_info()["string"])
		_about_dialog.add_child(label)
		add_child(_about_dialog)
	_about_dialog.popup_centered()


func _dialog_theme() -> Theme:
	## 別ウィンドウのダイアログはメイン画面のテーマを引き継がないので、
	## 日本語フォント入りのテーマを別に作る。
	var theme := Theme.new()
	theme.default_font = _font
	var size := _applied_font_size if _applied_font_size > 0 else 15
	theme.default_font_size = size
	theme.set_font("font", "Label", _font)
	theme.set_font_size("font_size", "Label", size)
	theme.set_font("font", "LineEdit", _font)
	theme.set_font_size("font_size", "LineEdit", size)
	theme.set_font("font", "Button", _font)
	theme.set_font_size("font_size", "Button", size)
	theme.set_font("font", "CheckBox", _font)
	theme.set_font_size("font_size", "CheckBox", size)
	theme.set_font("font", "RichTextLabel", _font)
	theme.set_font_size("normal_font_size", "RichTextLabel", size)
	return theme


func _input(event: InputEvent) -> void:
	## キー処理は _input で先に受ける。_unhandled_key_input だと、矢印キーや
	## Tab が GUI のフォーカス移動に奪われて届かないことがある。
	## 順序: (1)クリックでフォーカス解除 (2)キーを離した (3)エコー無視
	## (4)Esc (5)Tab (6)Enter (7)Alt+G・Shift+F6 (8)入力欄に
	## フォーカスがあれば残りは TextEdit 任せ (9)F1〜F12
	## (10)リストのキー (11)移動キー (12)その他の送信キー。
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null:
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if _input_box != null and _input_box.has_focus() and not _input_box.get_global_rect().has_point(mouse_event.position):
				_input_box.release_focus()
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	# (2)離したキーは、押し続けの移動キーから外す。
	if not key_event.pressed:
		_release_held_move(key_event)
		return
	# (3)OS のキー繰り返しは無視する。繰り返しは地図の到着で刻む。
	if key_event.echo:
		return
	var code := PhiKeys.code_name(key_event.physical_keycode)
	if code.is_empty():
		code = PhiKeys.code_name(key_event.keycode)
	if not _keytest.is_empty():
		print("key: keycode=", key_event.keycode, " physical=", key_event.physical_keycode, " code=[", code, "] focus=", _input_box.has_focus())
	var shift := key_event.shift_pressed
	var ctrl := key_event.ctrl_pressed
	var alt := key_event.alt_pressed
	var meta := key_event.meta_pressed
	var is_escape := key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE
	# (4)Esc は入力欄からフォーカスを外す。入力欄にフォーカスが無く
	# リストが出ていれば、リストを取り消す(Philly と同じく `.` を送る)。
	if is_escape:
		if _input_box.has_focus():
			_input_box.release_focus()
			get_viewport().set_input_as_handled()
		elif _list_active:
			_send_list_answer(".")
			get_viewport().set_input_as_handled()
		return
	# (5)Tab は入力欄へのフォーカスを切り替える
	if code == "Tab":
		if _input_box.has_focus():
			_input_box.release_focus()
		else:
			_input_box.grab_focus()
		get_viewport().set_input_as_handled()
		return
	# (6)Enter。入力欄にフォーカスがあれば送信する。Shift+Enter は
	# そのまま TextEdit に渡し、改行を入れる。Ctrl+Enter は
	# パーティー発言(Philly PartyTalkByCtrl)。
	# 入力欄にフォーカスが無くリストが出ていれば、選んだ行を送る。
	var is_enter := key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER or key_event.physical_keycode == KEY_ENTER or key_event.physical_keycode == KEY_KP_ENTER
	if is_enter:
		if _input_box.has_focus():
			if not shift:
				_submit_input_box(ctrl)
				get_viewport().set_input_as_handled()
			return
		if _list_active and not shift and not ctrl and not alt:
			_send_list_selected()
			get_viewport().set_input_as_handled()
			return
	# (7)Alt+G(あいさつ)と Shift+F6(priv ウィンドウ)は、
	# フォーカスに関わらず効く。
	if alt and not shift and not ctrl and code == "KeyG":
		_session.send_line(_config.alt_g_word)
		get_viewport().set_input_as_handled()
		return
	if shift and not ctrl and not alt and code == "F6":
		_show_priv_window()
		get_viewport().set_input_as_handled()
		return
	# (8)入力欄にフォーカスがあれば、残りのキーは TextEdit 任せ。
	if _input_box.has_focus():
		return
	# (9)F1〜F7 は呪文、F8〜F12 は自由ショートカット。修飾キー無しの時だけ。
	if not shift and not ctrl and not alt and not meta:
		if code.begins_with("F") and code.length() <= 3 and code.substr(1).is_valid_int():
			var fno := int(code.substr(1))
			if fno >= 1 and fno <= 7:
				_on_magic_key(fno)
				get_viewport().set_input_as_handled()
				return
			if fno >= 8 and fno <= 12:
				_on_shortcut_key(fno)
				get_viewport().set_input_as_handled()
				return
	# (10)リストが出ている間のキー(Philly KeyBindListMode)。
	if _list_active and _handle_list_key(code, shift, ctrl, alt):
		get_viewport().set_input_as_handled()
		return
	# (11)移動キー。押した時点で1歩送り、押し続けの記録にも入れる。
	var moved: Variant = PhiKeys.move_input(code, shift, ctrl, alt, meta, true)
	if moved != null:
		_press_held_move(key_event, str(moved[0]), str(moved[1]))
		_session.send_line(PhiKeys.move_command(str(moved[0]), str(moved[1]), _north_fix_now()))
		get_viewport().set_input_as_handled()
		return
	# (12)その他の送信キー(攻撃・看板など)。繰り返しはしない。
	var send := PhiKeys.key_send(code, shift, ctrl, alt, meta, true)
	if not send.is_empty():
		_session.send_text(send)
		get_viewport().set_input_as_handled()


func _on_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"message":
			var channel := str(event.get("channel", "log"))
			var raw := str(event.get("text", ""))
			var plain := PhiTags.plain_text(raw)
			_log_message(channel, plain)
			if channel == "log":
				_map_view.spawn_floats(plain)
				_map_view.spawn_combat_fx(plain)
				_map_view.spawn_death_fx(plain)
				_map_view.show_log_bubble(raw, plain)
			elif channel in ["talk", "priv"]:
				var from_ := str(event.get("from", ""))
				if not from_.is_empty():
					var body := PhiBubbles.bubble_body(plain)
					if not body.is_empty():
						_map_view.show_bubble(from_, body)
				if channel == "priv":
					_on_priv_received(plain)
		"status":
			_update_status(event)
		"notice":
			if event.has("name"):
				_player_name = str(event["name"])
				_map_view.player_name = _player_name
			if event.has("world"):
				_world = str(event["world"])
			if event.has("area"):
				_area = str(event["area"])
			if event.has("mapset"):
				_mapset = str(event["mapset"])
			_update_status_label()
		"cond":
			_cond_text = _cond_string(event)
			_update_status_label()
		"map":
			_demo_chars = event.get("chars", [])
			_demo_dim = MapView.grid_dim(int(event.get("size", 7)))
			_map_dim_now = int(event.get("size", 0))
			if event.has("style"):
				_map_style_now = str(event["style"])
			_map_view.set_map(event, _assets, _mapset)
			_repeat_on_map()
		"eagleEye":
			_log_message("system", "EagleEye %dx%d" % [int(event.get("width", 0)), int(event.get("height", 0))])
		"list":
			_show_list(event)
		"userList":
			_users.clear()
			for user in event.get("users", []):
				_users.append({"key": str(user.get("key", "")), "name": str(user.get("name", ""))})
			_rebuild_priv_recipients()
		"edit":
			_log_message("system", "編集モード: %s" % str(event.get("mode", "")))
		"worldTransfer":
			_log_message("system", "世界移動の要求がありました(試作では未対応): %s" % str(event.get("server", "")))
		"connection":
			_log_message("system", "サーバから切断されました")
		"mode":
			pass


func _on_session_error(message: String) -> void:
	_log_message("error", message)


func _on_session_closed() -> void:
	_conn_label.text = "切断"
	_log_message("system", "接続が閉じました")
	_held_moves.clear()
	_hide_list_overlay()
	_update_action_states()


func _log_message(channel: String, text: String) -> void:
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
	if color != null:
		_log.push_color(color)
	for line in text.split("\n"):
		_log.add_text(prefix + line + "\n")
	if color != null:
		_log.pop()


func _update_status(event: Dictionary) -> void:
	if event.has("name"):
		_player_name = str(event["name"])
		_map_view.player_name = _player_name
	var parts: Array[String] = []
	if event.has("hp"):
		var hp := "HP %s" % str(event["hp"])
		if event.has("maxHp"):
			hp += "/%s" % str(event["maxHp"])
		parts.append(hp)
	if event.has("mp"):
		var mp := "MP %s" % str(event["mp"])
		if event.has("maxMp"):
			mp += "/%s" % str(event["maxMp"])
		parts.append(mp)
	if event.has("exp"):
		parts.append("Exp %s" % str(event["exp"]))
	if event.has("gp"):
		parts.append("GP %s" % str(event["gp"]))
	_status_text = " ".join(parts)
	_update_status_label()


func _cond_string(event: Dictionary) -> String:
	var names: Array[String] = []
	for key in ["poison", "palsy", "panic", "confuse", "berserk", "silence", "blind"]:
		if bool(event.get(key, false)):
			names.append(key)
	if names.is_empty():
		return ""
	return "状態異常: " + ", ".join(names)


func _update_status_label() -> void:
	var parts: Array[String] = []
	if not _player_name.is_empty():
		parts.append(_player_name)
	if not _status_text.is_empty():
		parts.append(_status_text)
	if not _world.is_empty():
		parts.append(_world)
	if not _area.is_empty():
		parts.append(_area)
	if not _cond_text.is_empty():
		parts.append(_cond_text)
	_status_label.text = "  ".join(parts) if not parts.is_empty() else "未接続"


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
	_log_message("system", "--- リスト ---")
	for line in _list_lines:
		_log_message("log", line)


func _mark_list_answered() -> void:
	## リストに答えた(送った)扱いにして、オーバーレイを閉じる。
	_hide_list_overlay()


func _show_list_overlay() -> void:
	## 地図の上にリストを重ねる。幅は地図の幅、高さは行数に合わせる。
	_list_box.clear()
	for line in _list_lines:
		_list_box.add_item(line)
	if not _list_lines.is_empty():
		_list_box.select(0)
	var size := maxi(_applied_font_size, 15)
	var row_h := maxi(_font.get_height(size) + 6, 24)
	var rows := mini(_list_lines.size(), 9)
	var panel_w := clampf(_map_view.size.x - 16.0, 200.0, 560.0)
	var panel_h := rows * row_h + 52.0
	_list_panel.size = Vector2(panel_w, panel_h)
	_list_box.custom_minimum_size = Vector2(panel_w - 16.0, rows * row_h)
	_list_panel.visible = true


func _hide_list_overlay() -> void:
	_list_active = false
	if _list_panel != null:
		_list_panel.visible = false


func _on_list_row_selected(_index: int) -> void:
	pass


func _on_list_row_activated(index: int) -> void:
	## ダブルクリック(または Enter)で、その行の番号を送る。
	_send_list_row(index)


func _on_list_ok_pressed() -> void:
	_send_list_selected()


func _on_list_cancel_pressed() -> void:
	_send_list_answer(".")


func _send_list_selected() -> void:
	var selected := _list_box.get_selected_items()
	if selected.is_empty():
		return
	_send_list_row(selected[0])


func _send_list_row(index: int) -> void:
	if index < 0 or index >= _list_lines.size():
		return
	_send_list_answer(PhiShortcuts.list_number(_list_lines[index], index))


func _send_list_answer(answer: String) -> void:
	_session.send_line(answer)
	_hide_list_overlay()


func _handle_list_key(code: String, shift: bool, ctrl: bool, alt: bool) -> bool:
	## リストが出ている間のキー。扱ったら true。
	## 数字(1〜9)はその行の番号、0/`.`/←/→ は取り消し(`.`)、
	## `-` は全部(`-`)、↑/↓ はカーソル移動、Space は無視する。
	if shift or ctrl or alt:
		return false
	if code == "ArrowUp":
		_list_move_selection(-1)
		return true
	if code == "ArrowDown":
		_list_move_selection(1)
		return true
	if code == "Space":
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


func _list_move_selection(delta: int) -> void:
	var selected := _list_box.get_selected_items()
	var current := selected[0] if not selected.is_empty() else 0
	var next := clampi(current + delta, 0, _list_lines.size() - 1)
	_list_box.select(next)
	_list_box.ensure_current_is_visible()


# -- 第2段: 移動の繰り返しと北固定 ----------------------------------------

func _north_fix_now() -> bool:
	## 移動キー表を北固定にするか。Philly は「地図の大きさが 57 で
	## 様式が回転でない時」に北固定表を使う。地図イベントの size は
	## マスの数(7 が 57、5 が 40)なので、7 と比べる。
	var dim := _map_dim_now if _map_dim_now > 0 else MapView.grid_dim(_session.map_size)
	var style := _map_style_now if not _map_style_now.is_empty() else _session.map_style
	return dim == 7 and style != "turn"


func _press_held_move(key_event: InputEventKey, key: String, mods: String) -> void:
	## 移動キーを押し続けの記録に入れる。同じキーがあれば入れ直す。
	## 押すキーの組み合わせが変わると、繰り返しの待ち時間をやり直す
	## (Philly の MovekeyBak)。
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


func _release_held_move(key_event: InputEventKey) -> void:
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
	## (Philly の MapRecv)。
	_repeat_send_if_ready()


func _repeat_fallback_tick() -> void:
	## 地図が届かない場所でも、500ms ごとに繰り返す
	## (Philly の MOVE_CHECK_INTERVAL)。
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
	# リストが出ている間と、入力欄にフォーカスがある間は繰り返さない。
	if _list_active or _input_box.has_focus():
		return
	var now := Time.get_ticks_msec()
	if now - _held_since < REPEAT_START_MS:
		return
	if _last_repeat_send > 0 and now - _last_repeat_send < REPEAT_MIN_INTERVAL_MS:
		return
	var held: Dictionary = _held_moves[_held_moves.size() - 1]
	_session.send_line(PhiKeys.move_command(str(held["key"]), str(held["mods"]), _north_fix_now()))
	_last_repeat_send = now


# -- 第2段: F1〜F12 --------------------------------------------------------

func _on_magic_key(no: int) -> void:
	## F1〜F7。次のリストを抑えてから呪文を送る
	## (Philly の Cast1〜Cast7 + NextListCancel)。
	var text := PhiShortcuts.magic_text(no, _config.func_key_magic_fix, _config.magic_f[no - 1])
	if text.is_empty():
		return
	_suppress_lists = 1
	_mark_list_answered()
	_session.send_text(text)


func _on_shortcut_key(no: int) -> void:
	## F8〜F12。リストの間はリスト用文字列、それ以外は自由文字列を送る。
	## リストの間でなければ、設定された数だけ次のリストを抑える。
	var idx := no - 8
	var text := PhiShortcuts.shortcut_text(_config.shortcut_f[idx], _config.list_mode_shortcut[idx], _list_active)
	if text.is_empty():
		return
	if not _list_active:
		_suppress_lists = _config.shortcut_list_cancel[idx]
	_mark_list_answered()
	_session.send_text(text)


# -- 第2段: 大声 ------------------------------------------------------------

func _set_loud(on: bool) -> void:
	_loud = on
	if not on:
		_loud_all = false
	# 大声の間は入力欄の背景を黄色にする(Philly EditLoudColor)。
	# 字も黒にして、黄色の上で読めるようにする。
	if on:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 0)
		_input_box.add_theme_stylebox_override("normal", box)
		_input_box.add_theme_stylebox_override("focus", box)
		_input_box.add_theme_color_override("font_color", Color(0, 0, 0))
		_input_box.add_theme_color_override("caret_color", Color(0, 0, 0))
		_input_box.add_theme_color_override("font_placeholder_color", Color(0.25, 0.25, 0.25))
	else:
		_input_box.remove_theme_stylebox_override("normal")
		_input_box.remove_theme_stylebox_override("focus")
		_input_box.remove_theme_color_override("font_color")
		_input_box.remove_theme_color_override("caret_color")
		_input_box.remove_theme_color_override("font_placeholder_color")
	_update_action_states()


func _show_loud_dialog() -> void:
	if _loud_dialog == null:
		_loud_dialog = ConfirmationDialog.new()
		_loud_dialog.theme = _dialog_theme()
		_loud_dialog.title = "大声で発言"
		_loud_dialog.ok_button_text = "はい"
		_loud_dialog.cancel_button_text = "いいえ"
		var label := Label.new()
		label.text = "大声で発言します。\nこの世界にいる全員に聞こえます。\nよろしいですか？"
		# 折り返しを on にすると高さの計算が膨らんで画面いっぱいに
		# なってしまうので、改行だけの固定文にして幅を明示する。
		label.custom_minimum_size = Vector2(400, 0)
		_loud_dialog.add_child(label)
		_loud_dialog.add_button("すべて大声", false, "all")
		_loud_dialog.confirmed.connect(_on_loud_yes)
		_loud_dialog.canceled.connect(_on_loud_no)
		_loud_dialog.custom_action.connect(_on_loud_custom_action)
		add_child(_loud_dialog)
	_loud_dialog.popup_centered(Vector2i(440, 170))
	# 既定のフォーカスは「いいえ」にする(Philly と同じ)。
	var cancel_button := _loud_dialog.get_cancel_button()
	if cancel_button != null:
		cancel_button.grab_focus()


func _on_loud_yes() -> void:
	_session.send_text("*" + _loud_pending)
	_loud_pending = ""
	_set_loud(false)


func _on_loud_no() -> void:
	_loud_pending = ""
	_set_loud(false)


func _on_loud_custom_action(action: StringName) -> void:
	if action == "all":
		_loud_all = true
		_session.send_text("*" + _loud_pending)
		_loud_pending = ""
		_loud_dialog.hide()
		_update_action_states()


# -- 第2段: priv ウィンドウ --------------------------------------------------

func _show_priv_window() -> void:
	if _priv_window == null:
		_build_priv_window()
	_rebuild_priv_recipients()
	if not _priv_opened_once:
		_priv_opened_once = true
		_priv_window.popup_centered(Vector2i(420, 380))
	else:
		_priv_window.show()


func _build_priv_window() -> void:
	_priv_window = Window.new()
	_priv_window.theme = _dialog_theme()
	_priv_window.title = "宛先がありません"
	_priv_window.transient = true
	_priv_window.min_size = Vector2i(360, 300)
	# Window は既定で表示されるので、作った直後は隠しておく。
	# そうしないと、初回の popup_centered を経ずに (0,0) に出てしまう。
	_priv_window.visible = false
	add_child(_priv_window)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	_priv_window.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 110)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_priv_box_holder = VBoxContainer.new()
	_priv_box_holder.add_theme_constant_override("separation", 2)
	scroll.add_child(_priv_box_holder)
	var refresh := Button.new()
	refresh.text = "リスト更新"
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.pressed.connect(_on_priv_refresh_pressed)
	box.add_child(refresh)
	_priv_log = RichTextLabel.new()
	_priv_log.bbcode_enabled = false
	_priv_log.scroll_following = true
	_priv_log.selection_enabled = true
	_priv_log.custom_minimum_size = Vector2(0, 120)
	_priv_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_priv_log)
	_apply_ui_font_size_for_priv()
	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override("separation", 6)
	box.add_child(send_row)
	_priv_edit = LineEdit.new()
	_priv_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_priv_edit.placeholder_text = "priv の言葉"
	send_row.add_child(_priv_edit)
	_priv_edit.text_submitted.connect(_on_priv_text_submitted)
	var send_button := Button.new()
	send_button.text = "送信"
	send_button.pressed.connect(_on_priv_send_pressed)
	send_row.add_child(send_button)


func _apply_ui_font_size_for_priv() -> void:
	if _priv_log == null:
		return
	var size := maxi(_applied_font_size, 15)
	_priv_log.add_theme_font_size_override("font_size", size)
	_priv_log.add_theme_font_size_override("normal_font_size", size)
	_priv_log.add_theme_font_size_override("bold_font_size", size)
	_priv_log.add_theme_font_size_override("italics_font_size", size)
	_priv_log.add_theme_font_size_override("bold_italics_font_size", size)
	_priv_log.add_theme_font_size_override("mono_font_size", size)


func _rebuild_priv_recipients() -> void:
	if _priv_box_holder == null:
		return
	var checked: Dictionary = {}
	for box in _priv_boxes:
		if box.button_pressed:
			checked[str(box.get_meta("key"))] = true
	for box in _priv_boxes:
		box.queue_free()
	_priv_boxes.clear()
	for user in _users:
		var box := CheckBox.new()
		box.text = str(user["name"])
		box.set_meta("key", str(user["key"]))
		box.button_pressed = bool(checked.get(str(user["key"]), false))
		box.toggled.connect(_on_priv_recipient_toggled)
		_priv_box_holder.add_child(box)
		_priv_boxes.append(box)
	_update_priv_title()


func _on_priv_recipient_toggled(_pressed: bool) -> void:
	_update_priv_title()


func _update_priv_title() -> void:
	if _priv_window == null:
		return
	var names: Array[String] = []
	for box in _priv_boxes:
		if box.button_pressed:
			names.append(box.text)
	_priv_window.title = ", ".join(names) if not names.is_empty() else "宛先がありません"


func _on_priv_refresh_pressed() -> void:
	_session.send_line("#ulist")


func _on_priv_text_submitted(_text: String) -> void:
	_send_priv()


func _on_priv_send_pressed() -> void:
	_send_priv()


func _send_priv() -> void:
	var text := _priv_edit.text.strip_edges()
	if text.is_empty():
		return
	_priv_edit.text = ""
	var recipients: Array[Dictionary] = []
	for box in _priv_boxes:
		if box.button_pressed:
			recipients.append({"key": str(box.get_meta("key")), "name": box.text, "box": box})
	if recipients.is_empty():
		_priv_log_line("宛先がありません", true)
		return
	var sent_names: Array[String] = []
	for recipient in recipients:
		var no := PhiShortcuts.user_number(str(recipient["key"]))
		if no < 0:
			_priv_log_line("宛先が見つかりません: " + str(recipient["name"]), true)
			(recipient["box"] as CheckBox).button_pressed = false
			continue
		_session.send_line("priv %d %s" % [no, text])
		sent_names.append(str(recipient["name"]))
	if not sent_names.is_empty():
		_priv_log_line("[送信 → " + ", ".join(sent_names) + "] " + text, false)
	_update_priv_title()


func _on_priv_received(plain: String) -> void:
	## priv を受けたら、priv ウィンドウの履歴に残す。
	## 設定が on ならウィンドウも出す(キーボードは奪わない)。
	if _priv_window == null:
		_build_priv_window()
	_priv_log_line(plain, false)
	if _config.popup_priv_form and not _priv_window.visible:
		_show_priv_window()


func _priv_log_line(text: String, is_error: bool) -> void:
	if _priv_log == null:
		return
	if is_error:
		_priv_log.push_color(Color(1, 0.25, 0.25))
	_priv_log.add_text(text + "\n")
	if is_error:
		_priv_log.pop()


# -- 第2段: ショートカット設定ダイアログ ---------------------------------------

func _show_shortcut_dialog() -> void:
	if _shortcut_dialog == null:
		_build_shortcut_dialog()
	for i in range(7):
		_shortcut_magic_edits[i].text = _config.magic_f[i]
	_shortcut_fix_check.button_pressed = _config.func_key_magic_fix
	for i in range(5):
		_shortcut_free_edits[i].text = _config.shortcut_f[i]
		_shortcut_list_edits[i].text = _config.list_mode_shortcut[i]
	_shortcut_alt_edit.text = _config.alt_g_word
	_shortcut_dialog.popup_centered(Vector2i(560, 560))


func _build_shortcut_dialog() -> void:
	_shortcut_dialog = ConfirmationDialog.new()
	_shortcut_dialog.theme = _dialog_theme()
	_shortcut_dialog.title = "ショートカット設定"
	_shortcut_dialog.ok_button_text = "保存"
	_shortcut_dialog.cancel_button_text = "やめる"
	_shortcut_dialog.confirmed.connect(_on_shortcut_dialog_confirmed)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_shortcut_dialog.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	var magic_title := Label.new()
	magic_title.text = "F1〜F7 の呪文(魔法名、31文字まで)"
	box.add_child(magic_title)
	_shortcut_magic_edits.clear()
	for i in range(7):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var key_label := Label.new()
		key_label.text = "F%d" % (i + 1)
		key_label.custom_minimum_size = Vector2(32, 0)
		row.add_child(key_label)
		var edit := LineEdit.new()
		edit.max_length = PhiConfig.MAX_MAGIC_LEN
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		_shortcut_magic_edits.append(edit)
	_shortcut_fix_check = CheckBox.new()
	_shortcut_fix_check.text = "魔法名で送る(上の名前を使う)"
	box.add_child(_shortcut_fix_check)
	var free_title := Label.new()
	free_title.text = "F8〜F12 の自由ショートカット(\\n で改行)"
	box.add_child(free_title)
	_shortcut_free_edits.clear()
	_shortcut_list_edits.clear()
	for i in range(5):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var key_label := Label.new()
		key_label.text = "F%d" % (i + 8)
		key_label.custom_minimum_size = Vector2(32, 0)
		row.add_child(key_label)
		var edit := LineEdit.new()
		edit.max_length = PhiConfig.MAX_SHORTCUT_LEN
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		_shortcut_free_edits.append(edit)
		var list_label := Label.new()
		list_label.text = "リスト"
		row.add_child(list_label)
		var list_edit := LineEdit.new()
		list_edit.max_length = PhiConfig.MAX_SHORTCUT_LEN
		list_edit.custom_minimum_size = Vector2(64, 0)
		row.add_child(list_edit)
		_shortcut_list_edits.append(list_edit)
	var alt_row := HBoxContainer.new()
	alt_row.add_theme_constant_override("separation", 6)
	box.add_child(alt_row)
	var alt_label := Label.new()
	alt_label.text = "Alt+G"
	alt_label.custom_minimum_size = Vector2(48, 0)
	alt_row.add_child(alt_label)
	_shortcut_alt_edit = LineEdit.new()
	_shortcut_alt_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alt_row.add_child(_shortcut_alt_edit)
	add_child(_shortcut_dialog)


func _on_shortcut_dialog_confirmed() -> void:
	for i in range(7):
		_config.magic_f[i] = _shortcut_magic_edits[i].text
	_config.func_key_magic_fix = _shortcut_fix_check.button_pressed
	for i in range(5):
		_config.shortcut_f[i] = _shortcut_free_edits[i].text
		_config.list_mode_shortcut[i] = _shortcut_list_edits[i].text
	_config.alt_g_word = _shortcut_alt_edit.text
	_save_config()
	_log_message("system", "ショートカット設定を保存しました")
