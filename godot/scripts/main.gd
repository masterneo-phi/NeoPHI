extends Control
## NeoPHI Godot 版試作のメイン画面(シェル)。
##
## メニューバー・タブ行・ダイアログ類を持つ。
## 1タブ＝1キャラで、地図・ログ・入力欄・接続は
## `PhiCharacter` がタブごとに持つ。ツールバーは各タブの
## 地図の上に浮くパネルとして `PhiCharacter` が持つ。
##
## 接続先とグラフィックスの場所はコマンドライン引数で渡す
## (`--` の後に書く)。グラフィックスの指定が無い時は、実行ファイルの
## あるフォルダ直下 → .app の入ったフォルダ直下 → カレントディレクトリ直下 →
## 開発用の ~/workspace/phi-option-data の順に `chip_tofup` / `chara_tofup` を探す。例:
##   godot --path . -- --host 127.0.0.1 --port 20017 --id guest
##   --chip-dir ~/workspace/phi-option-data/chip_tofup
##   --chara-dir ~/workspace/phi-option-data/chara_tofup

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 20017
const DEFAULT_ID := "guest"

var _assets := GameAssets.new()
var _config := PhiConfig.new()
var _config_path := PhiConfig.DEFAULT_PATH
var _tab_session_path := PhiTabSession.DEFAULT_PATH
var _no_config := false
var _config_loaded := false
var _menu_bar: HBoxContainer = null
var _tab_row: HBoxContainer = null
var _plus_button: Button = null
var _tab_container: VBoxContainer = null
var _applied_font_size := 0
var _applied_chrome_size := 20
var _font: Font = null
var _bold_font: Font = null
var _system_font: SystemFont = null
var _menu_buttons: Array[MenuButton] = []
var _menu_popups: Array[PopupMenu] = []
var _scroll_popup: PopupMenu = null
var _scroll_item := -1
var _disp_magic_popup: PopupMenu = null
var _disp_magic_item := -1
var _loud_popup: PopupMenu = null
var _loud_item := -1
var _autosave_popup: PopupMenu = null
var _autosave_item := -1
var _delete_filter_popup: PopupMenu = null
var _delete_filter_item := -1
var _bgm_popup: PopupMenu = null
var _bgm_item := -1
## 音の司令塔(第5段)。全タブ共有で1つだけ持つ。
var _sound_engine: PhiSoundEngine = null
## 窓のフォーカスを失って BGM を一時停止したか。
var _bgm_focus_paused := false
var _ask_dialog: ConfirmationDialog = null
var _ask_label: Label = null
var _ask_edit: LineEdit = null
var _ask_action := ""
var _ask_numeric := false
var _about_dialog: AcceptDialog = null
var _loud_dialog: ConfirmationDialog = null
var _loud_tab: PhiCharacter = null
var _shortcut_dialog: ConfirmationDialog = null
var _shortcut_magic_edits: Array[LineEdit] = []
var _shortcut_fix_check: CheckBox = null
var _shortcut_free_edits: Array[LineEdit] = []
var _shortcut_list_edits: Array[LineEdit] = []
var _shortcut_alt_edit: LineEdit = null
var _priv_window: PhiPrivWindow = null
var _connect_dialog: ConfirmationDialog = null
var _connect_host_edit: LineEdit = null
var _connect_port_edit: LineEdit = null
var _connect_id_edit: LineEdit = null
var _connect_target: PhiCharacter = null
var _sayall_dialog: ConfirmationDialog = null
var _sayall_edit: LineEdit = null
var _talk_add_dialog: ConfirmationDialog = null
var _talk_add_edit: LineEdit = null
var _talk_add_tab: PhiCharacter = null

## 第4段: タブの一覧と行の部品。行の各タブは
## {tab, button, close, holder}。
var _tabs: Array[PhiCharacter] = []
var _tab_buttons: Array[Dictionary] = []
var _active_index := -1
var _log_filter: PhiLogFilter = null
var _tag_tree := {}
var _master_magic_data := {}
var _master_magic_items := {}
var _master_magic_next_id := 0
var _master_magic_running := false
var _mm_confirm: ConfirmationDialog = null
var _mm_label: Label = null
var _mm_choice := -1
var _mm_text_dialog: ConfirmationDialog = null
var _mm_text_label: Label = null
var _mm_text_edit: LineEdit = null
var _mm_text_choice := -1
var _mm_text_value := ""
var _mm_text_integer := false
var _image_window: Window = null
var _image_list: ItemList = null
var _image_preview: TextureRect = null
var _image_status: Label = null
var _image_opened_once := false
var _image_request: HTTPRequest = null

var _startup_map_size := -1
var _startup_map_style := ""
var _shot_path := ""
var _shot_delay := 0.0
var _elapsed := 0.0
var _shot_done := false
var _keytest: Array[String] = []
var _assets_warning := ""
var _fx_demo := false
var _fx_demo_in := 2.0


func _ready() -> void:
	var args := _user_args()
	_no_config = args.has("no-config")
	if args.has("config"):
		_config_path = str(args["config"])
	if args.has("tab-session"):
		_tab_session_path = str(args["tab-session"])
	if not _no_config:
		_config_loaded = _config.load_file(_config_path)
	_limit_window_to_screens()
	# 保存してある窓の大きさに戻す。--resolution 指定時はそちらを優先する。
	if _config_loaded and not OS.get_cmdline_args().has("--resolution"):
		get_window().size = Vector2i(_config.window_width, _config.window_height)
	_system_font = PhiFont.make_system_font()
	_font = PhiFont.make_ui_font(_system_font)
	# 太字(第3段)。既定フォントに太字バリアントが無いので、
	# FontVariation の embolden で太らせる。
	_bold_font = PhiFont.make_bold_font(_system_font)
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 15
	theme.set_font("font", "Label", _font)
	theme.set_font_size("font_size", "Label", 15)
	self.theme = theme
	_apply_args(args)
	_load_stage4_data()
	# 音の司令塔(第5段)。効果音のルールを読み、BGM の
	# サウンドフォントの場所を決めておく(読み込み自体は
	# 最初の MIDI 再生の時)。
	_sound_engine = PhiSoundEngine.new()
	add_child(_sound_engine)
	_sound_engine.setup(_config, _assets.philly_roots)
	_load_sound_data()
	_build_ui()
	get_window().size_changed.connect(_on_window_size_changed)
	var main_tab := _restore_tabs()
	_activate_tab(main_tab)
	_apply_chrome_size()
	_update_action_states()
	_log_active("system", "NeoPHI Godot 版試作")
	if not _assets_warning.is_empty():
		_log_active("system", _assets_warning)
	_connect_tab(main_tab, str(get_meta("host")), int(get_meta("port")), str(get_meta("char_id")), true)
	_update_action_states()
	if not _keytest.is_empty():
		_run_keytest()


func _make_font() -> Font:
	## WPHI と同じフォント stack。PhiFont.make_ui_font に委譲する。
	## 互換のため残している。
	return PhiFont.make_ui_font()


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
	# 画面の外周に金属の外枠を付け、中身はその幅ぶん内側に置く。
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fw := int(OuterFrame.WIDTH)
	margin.add_theme_constant_override("margin_left", fw)
	margin.add_theme_constant_override("margin_right", fw)
	margin.add_theme_constant_override("margin_top", fw)
	margin.add_theme_constant_override("margin_bottom", fw)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)
	_build_menu_bar(root)
	# タブ行(第4段)。メニューバーの下に置く(WPHI 参考)。
	# ツールバーはメニューの下の一列をやめ、各タブの地図の上に
	# 浮くパネルにした(PhiCharacter 側)。
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 2)
	root.add_child(_tab_row)
	_plus_button = Button.new()
	_plus_button.text = "+"
	_plus_button.tooltip_text = "新しいタブ"
	_plus_button.focus_mode = Control.FOCUS_NONE
	_plus_button.pressed.connect(_on_plus_pressed)
	_tab_row.add_child(_plus_button)
	# タブ行と地図・ログの領域の境界に、金属スリットを1本入れる。
	root.add_child(MetalHSlit.new())
	_tab_container = VBoxContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_theme_constant_override("separation", 0)
	root.add_child(_tab_container)
	# 外枠は一番上に重ねる(マウスは通す)。
	var frame := OuterFrame.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)


func _build_menu_bar(root: VBoxContainer) -> void:
	## Philly のメニューバー(ファイル/行動/魔法/表示/ツール)。
	## スキンの Style/Menu.txt で off のメニューは出さない。
	## バーの地は金属テクスチャ(無ければ単色)。ボタンは地を
	## 透かし、ホバー・押下の時だけ薄く色を重ねる。
	var frame := PanelContainer.new()
	root.add_child(frame)
	var metal := UiStyle.metal_texture()
	if metal != null:
		var tex_box := StyleBoxTexture.new()
		tex_box.texture = metal
		tex_box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		frame.add_theme_stylebox_override("panel", tex_box)
	else:
		var flat_box := StyleBoxFlat.new()
		flat_box.bg_color = Color(0.16, 0.16, 0.17)
		frame.add_theme_stylebox_override("panel", flat_box)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	frame.add_child(bar)
	_menu_bar = bar
	var visibility := _assets.menu_visibility()
	for menu in PhiActions.MENUS:
		var menu_name := str(menu["name"])
		if visibility.get(menu_name, true) == false:
			continue
		var button := MenuButton.new()
		button.text = menu_name
		button.focus_mode = Control.FOCUS_NONE
		# 地は金属を透かし、ホバー・押下だけ薄く重ねて見せる。
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var hover_box := StyleBoxFlat.new()
		hover_box.bg_color = Color(1, 1, 1, 0.14)
		UiStyle.round_box(hover_box)
		button.add_theme_stylebox_override("hover", hover_box)
		var pressed_box := StyleBoxFlat.new()
		pressed_box.bg_color = Color(0, 0, 0, 0.30)
		UiStyle.round_box(pressed_box)
		button.add_theme_stylebox_override("pressed", pressed_box)
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
			elif action_name == "DispMagic":
				popup.add_check_item(str(action["caption"]), item_id)
				_disp_magic_popup = popup
				_disp_magic_item = popup.get_item_index(item_id)
			elif action_name == "LogAutoSave":
				popup.add_check_item(str(action["caption"]), item_id)
				_autosave_popup = popup
				_autosave_item = popup.get_item_index(item_id)
			elif action_name == "LogDeleteFilter":
				popup.add_check_item(str(action["caption"]), item_id)
				_delete_filter_popup = popup
				_delete_filter_item = popup.get_item_index(item_id)
			elif action_name == "PlayBGM":
				popup.add_check_item(str(action["caption"]), item_id)
				_bgm_popup = popup
				_bgm_item = popup.get_item_index(item_id)
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
	_build_master_magic_menu()


func _on_menu_id_pressed(item_id: int, popup: PopupMenu) -> void:
	var index := popup.get_item_index(item_id)
	var action_name := str(popup.get_item_metadata(index))
	_do_action(action_name)


func _apply_chrome_size() -> void:
	## アクティブなタブの地図の倍率に比例して、全体の UI の文字を
	## 大きくする。ログ・入力欄などは 6 * zoom、メニューバーと
	## プルダウンメニュー・ツールチップ・タブ行は 7 * zoom(最低 16)。
	## タブの中の文字は、各タブが自分の倍率で付ける。
	var tab := _active_tab()
	if tab == null:
		return
	var zoom := tab.debug_map_zoom()
	var size := PhiFont.ui_size_for_zoom(zoom)
	var chrome_size := PhiFont.chrome_size_for_zoom(zoom)
	if size == _applied_font_size and chrome_size == _applied_chrome_size:
		return
	_applied_font_size = size
	_applied_chrome_size = chrome_size
	# ツールチップの文字もメニューと同じ大きさにする(第3段の追加要望)。
	# ツールチップは重なり表示なので、レイアウトには影響しない。
	var main_theme := theme
	if main_theme != null:
		main_theme.set_font("font", "TooltipLabel", _font)
		main_theme.set_font_size("font_size", "TooltipLabel", chrome_size)
	for button in _menu_buttons:
		button.add_theme_font_size_override("font_size", chrome_size)
	# メニュー項目の間隔はゆったりさせる(WPHI 参考。第3段)。
	if _menu_bar != null:
		_menu_bar.add_theme_constant_override("separation", chrome_size)
	for popup in _menu_popups:
		popup.add_theme_font_size_override("font_size", chrome_size)
		popup.add_theme_font_size_override("font_separator_size", chrome_size)
	for entry in _tab_buttons:
		(entry["button"] as Button).add_theme_font_size_override("font_size", chrome_size)
		(entry["close"] as Button).add_theme_font_size_override("font_size", chrome_size)
	if _plus_button != null:
		_plus_button.add_theme_font_size_override("font_size", chrome_size)
	if _priv_window != null:
		_priv_window.apply_font_size(maxi(size, 15))


func _apply_args(args: Dictionary) -> void:
	## 設定ファイルの値を既定にし、コマンドライン引数で上書きする。
	var host: String = args.get("host", _config.host)
	var port: int = int(args.get("port", str(_config.port)))
	var char_id: String = args.get("id", DEFAULT_ID)
	if args.has("map-size"):
		_startup_map_size = int(args["map-size"])
	var style_arg := str(args.get("map-style", "")).to_lower()
	if style_arg == "turn" or style_arg == "solid":
		_startup_map_style = style_arg
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


# -- 第4段: 設定ファイルとタブセッション --------------------------------------

func _load_stage4_data() -> void:
	## 削除フィルタ・タグ挿入メニュー・超魔法メニューの元を読む。
	## 探す順序: user:// のファイル → Philly の Config/ → 組み込みの既定。
	var filter_text := _load_config_text("LogDeleteRegexp.ini", "")
	if filter_text.is_empty():
		_log_filter = PhiLogFilter.default_filter()
	else:
		_log_filter = PhiLogFilter.new()
		_log_filter.load_text(filter_text)
	_tag_tree = PhiTagMenu.parse(_load_config_text("TagMenu.xml", PhiTagMenu.DEFAULT_XML))
	_master_magic_data = PhiMasterMagic.parse(_load_config_text("MasterMagicMenu.xml", PhiMasterMagic.DEFAULT_XML))


func _load_config_text(file_name: String, default_text: String) -> String:
	var user_path := "user://" + file_name
	if FileAccess.file_exists(user_path):
		var data := FileAccess.get_file_as_bytes(user_path)
		if data != null and not data.is_empty():
			return SkinFiles.decode_text_file(data)
	var from_philly := _assets.config_text(file_name)
	if not from_philly.is_empty():
		return from_philly
	return default_text


func _reload_log_filter() -> void:
	var filter_text := _load_config_text("LogDeleteRegexp.ini", "")
	if filter_text.is_empty():
		_log_filter = PhiLogFilter.default_filter()
	else:
		_log_filter = PhiLogFilter.new()
		_log_filter.load_text(filter_text)
	for tab in _tabs:
		tab.set_log_filter(_log_filter)


func _restore_tabs() -> PhiCharacter:
	## 保存してあるタブを未接続で復元し、自動接続するタブを作って返す。
	## 自動接続するタブと同じホスト・ポートの保存項目は重ねない。
	var auto_host := str(get_meta("host"))
	var auto_port := int(get_meta("port"))
	if not _no_config and _config.load_tab_session:
		for entry in PhiTabSession.load_file(_tab_session_path):
			if str(entry["host"]) == auto_host and int(entry["port"]) == auto_port:
				continue
			var restored := _create_tab()
			restored.host = str(entry["host"])
			restored.port = int(entry["port"])
			restored.restored_name = str(entry.get("name", ""))
			_refresh_tab_titles()
	return _create_tab()


func _save_tab_session() -> void:
	## 開いているタブのホスト・ポート・キャラ名を保存する。
	## ID は保存しない。
	if _no_config:
		return
	var states: Array = []
	for tab in _tabs:
		states.append(tab.session_state())
	PhiTabSession.save_file(states, _tab_session_path)


func _connect_tab(tab: PhiCharacter, host: String, port: int, char_id: String, use_startup: bool = false) -> void:
	## タブを接続する。地図の大きさ・様式は、初回の自動接続だけ
	## コマンドライン引数を優先し、あとは設定の値を使う。
	tab.session.map_size = _config.map_size
	tab.session.map_style = _config.map_style
	tab.session.disp_magic = _config.disp_magic
	if use_startup:
		if _startup_map_size > 0:
			tab.session.map_size = _startup_map_size
		if not _startup_map_style.is_empty():
			tab.session.map_style = _startup_map_style
	tab.connect_to(host, port, char_id)
	_update_action_states()


func _log_active(channel: String, text: String) -> void:
	var tab := _active_tab()
	if tab != null:
		tab.log_message(channel, text)


func _update_action_states() -> void:
	## 接続状態に合わせてメニューの有効・無効を変える。
	## ツールバーは各タブ側で合わせる(下の refresh_toolbar_states)。
	var tab := _active_tab()
	var connected := tab != null and tab.is_session_open()
	var loud := tab != null and tab.is_loud()
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
		_loud_popup.set_item_checked(_loud_item, loud)
	if _disp_magic_popup != null and _disp_magic_item >= 0:
		_disp_magic_popup.set_item_checked(_disp_magic_item, _config.disp_magic)
	if _autosave_popup != null and _autosave_item >= 0:
		_autosave_popup.set_item_checked(_autosave_item, _config.log_auto_save)
	if _delete_filter_popup != null and _delete_filter_item >= 0:
		_delete_filter_popup.set_item_checked(_delete_filter_item, _config.log_delete_filter)
	if _bgm_popup != null and _bgm_item >= 0:
		_bgm_popup.set_item_checked(_bgm_item, _config.play_bgm)
	# ツールバーのボタンの状態は、各タブが自分の接続状態で合わせる。
	for t in _tabs:
		t.refresh_toolbar_states()


func _on_window_size_changed() -> void:
	## 窓のリサイズは、地図の拡大のきっかけにする。
	## レイアウトのフィードバックでは立てない(発振を防ぐ)。
	var tab := _active_tab()
	if tab != null and tab.map_view != null:
		tab.map_view.request_zoom_growth()


func _save_config() -> void:
	if _no_config:
		return
	_config.window_width = get_window().size.x
	_config.window_height = get_window().size.y
	_config.save_file(_config_path)


func _quit() -> void:
	_save_config()
	_save_tab_session()
	for tab in _tabs:
		tab.disconnect_graceful()
	get_tree().quit()


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
	# ダイアログ内のツールチップもメニューと同じ大きさにする。
	theme.set_font("font", "TooltipLabel", _font)
	theme.set_font_size("font_size", "TooltipLabel", _applied_chrome_size if _applied_chrome_size > 0 else size)
	return theme


# -- 第4段: タブの管理 ----------------------------------------------------------

func _active_tab() -> PhiCharacter:
	if _active_index < 0 or _active_index >= _tabs.size():
		return null
	return _tabs[_active_index]


func _create_tab() -> PhiCharacter:
	var tab := PhiCharacter.new()
	tab.setup(_assets, _config, _font, _bold_font, _log_filter, _tag_tree)
	tab.set_sound_engine(_sound_engine)
	tab.title_changed.connect(_on_tab_title_changed.bind(tab))
	tab.unread_changed.connect(_on_tab_unread_changed.bind(tab))
	tab.connection_changed.connect(_on_tab_connection_changed.bind(tab))
	tab.zoom_changed.connect(_on_tab_zoom_changed.bind(tab))
	tab.users_changed.connect(_on_tab_users_changed.bind(tab))
	tab.priv_received.connect(_on_tab_priv_received.bind(tab))
	tab.loud_confirm_requested.connect(_on_tab_loud_confirm.bind(tab))
	tab.action_requested.connect(_do_action)
	tab.bgm_changed.connect(_on_tab_bgm_changed.bind(tab))
	tab.screenshot_requested.connect(_save_screenshot)
	_tab_container.add_child(tab)
	_tabs.append(tab)
	_add_tab_row_entry(tab)
	return tab


func _add_tab_row_entry(tab: PhiCharacter) -> void:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 0)
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.text = tab.tab_title()
	button.pressed.connect(_on_tab_button_pressed.bind(tab))
	button.gui_input.connect(_on_tab_button_gui_input.bind(tab))
	holder.add_child(button)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_on_tab_close_pressed.bind(tab))
	holder.add_child(close)
	_tab_row.add_child(holder)
	_tab_row.move_child(_plus_button, _tab_row.get_child_count() - 1)
	_tab_buttons.append({"tab": tab, "button": button, "close": close, "holder": holder})
	_apply_chrome_size()


func _on_tab_button_pressed(tab: PhiCharacter) -> void:
	_activate_tab(tab)


func _on_tab_button_gui_input(event: InputEvent, tab: PhiCharacter) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE and _config.mclick_tab_close:
		_close_tab(tab)
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and not tab.is_session_open():
		_show_connect_dialog(tab)


func _on_tab_close_pressed(tab: PhiCharacter) -> void:
	_close_tab(tab)


func _on_plus_pressed() -> void:
	_show_connect_dialog(null)


func _activate_tab(tab: PhiCharacter) -> void:
	var idx := _tabs.find(tab)
	if idx < 0:
		return
	_active_index = idx
	for i in range(_tabs.size()):
		var t := _tabs[i]
		t.visible = (i == idx)
		t.set_active(i == idx)
	_refresh_tab_titles()
	_apply_chrome_size()
	_update_action_states()
	# BGM はアクティブなタブの曲だけを鳴らす(第5段)。
	_apply_tab_bgm(tab)
	if _priv_window != null and _priv_window.visible:
		_refresh_priv_window_for_active_tab()
	if _image_window != null and _image_window.visible:
		_refresh_image_window()


func _close_tab(tab: PhiCharacter) -> void:
	var idx := _tabs.find(tab)
	if idx < 0:
		return
	tab.disconnect_graceful()
	for i in range(_tab_buttons.size()):
		if _tab_buttons[i]["tab"] == tab:
			(_tab_buttons[i]["holder"] as Control).queue_free()
			_tab_buttons.remove_at(i)
			break
	_tabs.remove_at(idx)
	tab.queue_free()
	if _tabs.is_empty():
		_activate_tab(_create_tab())
	else:
		_activate_tab(_tabs[clampi(idx, 0, _tabs.size() - 1)])
	_save_tab_session()


func _refresh_tab_titles() -> void:
	for entry in _tab_buttons:
		var tab: PhiCharacter = entry["tab"]
		var button: Button = entry["button"]
		var title := tab.tab_title()
		if tab.unread:
			title = "! " + title
		button.text = title
		button.set_pressed_no_signal(tab == _active_tab())
		# 未接続のタブは薄く出す。
		button.modulate = Color(0.55, 0.55, 0.55) if not tab.is_session_open() and not tab.host.is_empty() else Color(1, 1, 1)
		if tab.host.is_empty() and tab.player_name().is_empty():
			button.modulate = Color(0.55, 0.55, 0.55)


func _switch_tab(delta: int) -> void:
	## Ctrl+Tab / Shift+Ctrl+Tab。Philly の未読優先ではなく、
	## 厳密に前後のタブへ移動する(第4段の判断)。
	if _tabs.size() <= 1:
		return
	var next := (_active_index + delta + _tabs.size()) % _tabs.size()
	_activate_tab(_tabs[next])


func _on_tab_title_changed(_title: String, _tab: PhiCharacter) -> void:
	_refresh_tab_titles()
	_save_tab_session()


func _on_tab_unread_changed(_unread: bool, _tab: PhiCharacter) -> void:
	_refresh_tab_titles()


func _on_tab_connection_changed(_open: bool, tab: PhiCharacter) -> void:
	_refresh_tab_titles()
	if tab == _active_tab():
		_update_action_states()


# -- 第5段: 音 -----------------------------------------------------------------

func _load_sound_data() -> void:
	## 効果音のルールを読む。探す順序は削除フィルタと同じ
	## (user:// → Philly の Config/ → 組み込みの既定)。
	_sound_engine.set_se_texts(
		_load_config_text("SoundRegexp.ini", PhiSeRules.DEFAULT_REGEXP_TEXT),
		_load_config_text("SoundFile.ini", PhiSeRules.DEFAULT_FILE_TEXT))


func _on_tab_bgm_changed(tab: PhiCharacter) -> void:
	_apply_tab_bgm(tab)


func _apply_tab_bgm(tab: PhiCharacter) -> void:
	## アクティブなタブの BGM を鳴らす/止める。
	## 条件がそろわなければ止める。同じ曲が鳴っていれば
	## 再生し直さず、速度だけ合わせる。
	if _sound_engine == null or tab == null or tab != _active_tab():
		return
	if not _config.play_bgm or tab.bgm_name.is_empty() or not tab.is_session_open():
		_sound_engine.bgm_stop()
		return
	var path := tab.bgm_resolved_path()
	if path.is_empty():
		_sound_engine.bgm_stop()
		return
	_sound_engine.bgm_play(path)
	_sound_engine.bgm_set_speed(tab.bgm_speed)


func _on_tab_zoom_changed(_zoom: int, tab: PhiCharacter) -> void:
	if tab == _active_tab():
		_apply_chrome_size()


func _on_tab_users_changed(tab: PhiCharacter) -> void:
	if tab == _active_tab() and _priv_window != null and _priv_window.visible:
		_refresh_priv_window_for_active_tab()


func _on_tab_priv_received(plain: String, tab: PhiCharacter) -> void:
	## priv を受けたら、アクティブなタブの時だけ窓に反映する。
	## バックグラウンドのタブは未読マークだけ(タブ側で付ける)。
	if tab != _active_tab():
		return
	if _priv_window != null and _priv_window.visible:
		_priv_window.append_history(plain)
		return
	if _config.popup_priv_form:
		_show_priv_window()


func _on_tab_loud_confirm(_text: String, _party: bool, tab: PhiCharacter) -> void:
	_loud_tab = tab
	_show_loud_dialog()


# -- アクション ---------------------------------------------------------------

func _do_action(action_name: String) -> void:
	var tab := _active_tab()
	match PhiActions.kind_of(action_name):
		"send":
			if tab == null:
				return
			tab.do_send_action(action_name)
			_remember_map_mode(action_name, tab)
		"ask":
			_ask_text(action_name)
		"priv-window":
			_toggle_priv_window()
		"loud-toggle":
			if tab != null:
				tab.set_loud(not tab.is_loud())
				_update_action_states()
		"shortcut-config":
			_show_shortcut_dialog()
		"connect":
			if tab != null and not tab.is_session_open():
				_show_connect_dialog(tab)
		"disconnect":
			if tab != null:
				tab.disconnect_graceful()
		"exit":
			_quit()
		"reload-config":
			_config.load_file(_config_path)
			_reload_log_filter()
			_load_sound_data()
			for t in _tabs:
				t.apply_scroll_stop()
			_update_action_states()
			if tab != null:
				_apply_tab_bgm(tab)
			_log_active("system", "設定ファイルを読み込みました(スキンと地図の大きさは次回起動から有効です)")
		"reset-config":
			_config.reset()
			_save_config()
			for t in _tabs:
				t.apply_scroll_stop()
			_update_action_states()
			_log_active("system", "初期設定に戻しました(スキンと地図の大きさは次回起動から有効です)")
		"clear-cache":
			_assets.clear_cache()
			# 全タブの地図・パネル・カーソルの絵を読み直す。
			# 古いテクスチャの参照を持ったままにしない(第4段の堅牢化)。
			# ツールバーのアイコンも各タブのこの経路で取り直す。
			for t in _tabs:
				t.reload_cached_textures()
			# メニューのアイコンも同じ経路で取り直す。
			for popup in _menu_popups:
				for i in popup.item_count:
					var meta: Variant = popup.get_item_metadata(i)
					if meta == null:
						continue
					var menu_icon: Variant = _assets.button_icon(str(meta))
					if menu_icon != null:
						popup.set_item_icon(i, menu_icon)
			_log_active("system", "グラフィックスのキャッシュを初期化しました")
		"screenshot":
			_save_screenshot()
		"scroll-toggle":
			_config.scroll_stop = not _config.scroll_stop
			for t in _tabs:
				t.apply_scroll_stop()
			_update_action_states()
			_save_config()
		"disp-magic-toggle":
			# 魔法表示の受け取りを切り替える(第3段)。接続中なら即座に伝える。
			_config.disp_magic = not _config.disp_magic
			if tab != null:
				tab.session.disp_magic = _config.disp_magic
				if tab.is_session_open():
					tab.send_line("#ex-switch ex-disp-magic=" + ("true" if _config.disp_magic else "false"))
			_update_action_states()
			_save_config()
		"new-tab":
			_show_connect_dialog(null)
		"close-tab":
			if tab != null:
				_close_tab(tab)
		"say-all-tabs":
			_show_sayall_dialog()
		"talk-add":
			_show_talk_add_dialog()
		"log-save":
			# 今のログをその場で保存する(手動保存、残り項目)。
			# 保存先と形式は自動保存の設定に従う。
			if tab != null:
				var saved_path := tab.save_log_buffer()
				if saved_path.is_empty():
					_log_active("error", "ログの保存に失敗しました: " + _config.log_save_dir)
				else:
					_log_active("system", "ログを保存しました: " + saved_path)
		"autosave-toggle":
			_config.log_auto_save = not _config.log_auto_save
			_update_action_states()
			_save_config()
		"delete-filter-toggle":
			_config.log_delete_filter = not _config.log_delete_filter
			_update_action_states()
			_save_config()
		"image-window":
			_show_image_window()
		"bgm-toggle":
			# BGM を再生するか(第5段)。Philly の PlayBGM と同じく、
			# on にすると今のキャラの BGM を再生し直し、off に
			# すると止める。
			_config.play_bgm = not _config.play_bgm
			if not _config.play_bgm:
				_sound_engine.bgm_stop()
			elif tab != null:
				_apply_tab_bgm(tab)
			_update_action_states()
			_save_config()
		"open-config-folder":
			OS.shell_open(ProjectSettings.globalize_path("user://"))
		"about":
			_show_about()


func _remember_map_mode(action_name: String, tab: PhiCharacter) -> void:
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
	tab.session.map_size = _config.map_size
	tab.session.map_style = _config.map_style
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
		_ask_edit.text_changed.connect(_on_ask_text_changed)
		add_child(_ask_dialog)
	_ask_action = action_name
	_ask_numeric = bool(action.get("integer", false))
	_ask_dialog.title = str(action["title"])
	_ask_label.text = str(action["label"])
	_ask_edit.text = ""
	_ask_dialog.popup_centered(Vector2i(320, 120))
	_ask_edit.grab_focus()


func _on_ask_submitted(_text: String) -> void:
	_ask_dialog.hide()
	_on_ask_confirmed()


func _on_ask_text_changed(_new_text: String) -> void:
	## 数字を入れる欄(Pay)では、入力中に全角数字を半角に直す。
	if _ask_numeric:
		_convert_edit_digits(_ask_edit)


func _convert_edit_digits(edit: LineEdit) -> void:
	## 全角数字を半角に直し、キャレット位置を保つ。
	var converted := PhiDigits.to_half_width_digits(edit.text)
	if converted != edit.text:
		var caret := edit.caret_column
		edit.text = converted
		edit.caret_column = mini(caret, converted.length())


func _on_ask_confirmed() -> void:
	var answer := _ask_edit.text.strip_edges()
	if answer.is_empty():
		return
	var action := PhiActions.get_action(_ask_action)
	if bool(action.get("integer", false)):
		# 送信時にも念のため全角数字を半角に直す。
		answer = PhiDigits.to_half_width_digits(answer)
		if not answer.is_valid_int() or int(answer) < 0:
			_log_active("error", "0 以上の整数を入力してください")
			return
		answer = str(int(answer))
	var tab := _active_tab()
	if tab != null:
		tab.send_text(PhiActions.build_ask_text(_ask_action, answer))


func _show_about() -> void:
	if _about_dialog == null:
		_about_dialog = AcceptDialog.new()
		_about_dialog.theme = _dialog_theme()
		_about_dialog.title = "バージョン情報"
		_about_dialog.ok_button_text = "閉じる"
		var label := Label.new()
		label.text = PhiVersion.about_text()
		_about_dialog.add_child(label)
		add_child(_about_dialog)
	_about_dialog.popup_centered()


# -- 第2段: 大声 ------------------------------------------------------------

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


func _loud_target() -> PhiCharacter:
	if _loud_tab != null and is_instance_valid(_loud_tab):
		return _loud_tab
	return _active_tab()


func _on_loud_yes() -> void:
	var tab := _loud_target()
	if tab != null:
		tab.confirm_loud()
	_update_action_states()


func _on_loud_no() -> void:
	var tab := _loud_target()
	if tab != null:
		tab.cancel_loud()
	_update_action_states()


func _on_loud_custom_action(action: StringName) -> void:
	if action == "all":
		var tab := _loud_target()
		if tab != null:
			tab.confirm_loud_all()
		_loud_dialog.hide()
		_update_action_states()


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
	_log_active("system", "ショートカット設定を保存しました")


# -- 第2段: priv ウィンドウ(第4段で1窓共用＋トグル＋自分除外) -----------------

func _build_priv_window() -> void:
	_priv_window = PhiPrivWindow.new()
	_priv_window.theme = _dialog_theme()
	_priv_window.set_tag_tree(_tag_tree)
	_priv_window.send_requested.connect(_send_priv)
	_priv_window.refresh_requested.connect(_on_priv_refresh_pressed)
	add_child(_priv_window)
	_priv_window.apply_font_size(maxi(_applied_font_size, 15))


func _show_priv_window() -> void:
	if _priv_window == null:
		_build_priv_window()
	_refresh_priv_window_for_active_tab()
	_priv_window.show_window()


func _toggle_priv_window() -> void:
	## Shift+F6 とメニューはトグル動作。開いていれば隠す。
	if _priv_window != null and _priv_window.visible:
		_priv_window.hide()
		return
	_show_priv_window()


func _refresh_priv_window_for_active_tab() -> void:
	if _priv_window == null:
		return
	var tab := _active_tab()
	if tab == null:
		return
	_priv_window.rebuild_recipients(tab.users(), tab.player_name())
	_priv_window.set_history(tab.priv_history())


func _on_priv_refresh_pressed() -> void:
	var tab := _active_tab()
	if tab != null:
		tab.send_line("#ulist")


func _send_priv() -> void:
	var tab := _active_tab()
	if tab == null:
		return
	var text := _priv_window.send_text().strip_edges()
	if text.is_empty():
		return
	_priv_window.clear_send_text()
	var recipients := _priv_window.checked_entries()
	if recipients.is_empty():
		_priv_window.log_line("宛先がありません", true)
		return
	var sent_names: Array[String] = []
	for recipient in recipients:
		var no := PhiShortcuts.user_number(str(recipient["key"]))
		if no < 0:
			_priv_window.log_line("宛先が見つかりません: " + str(recipient["name"]), true)
			(recipient["box"] as CheckBox).button_pressed = false
			continue
		tab.send_line("priv %d %s" % [no, text])
		sent_names.append(str(recipient["name"]))
	if not sent_names.is_empty():
		var line := "[送信 → " + ", ".join(sent_names) + "] " + text
		tab.add_priv_history(line)
		_priv_window.append_history(line)
	_priv_window.update_title()


# -- 第4段: 接続ダイアログ ----------------------------------------------------

func _show_connect_dialog(target: PhiCharacter) -> void:
	## 新しいタブ(target == null)か、未接続のタブへの接続を聞く。
	## ID は常に入力欄が空で、保存しない。
	_connect_target = target
	if _connect_dialog == null:
		_connect_dialog = ConfirmationDialog.new()
		_connect_dialog.theme = _dialog_theme()
		_connect_dialog.title = "接続"
		_connect_dialog.ok_button_text = "接続"
		_connect_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		_connect_dialog.add_child(box)
		var host_row := HBoxContainer.new()
		host_row.add_theme_constant_override("separation", 6)
		box.add_child(host_row)
		var host_label := Label.new()
		host_label.text = "ホスト"
		host_label.custom_minimum_size = Vector2(64, 0)
		host_row.add_child(host_label)
		_connect_host_edit = LineEdit.new()
		_connect_host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host_row.add_child(_connect_host_edit)
		var port_row := HBoxContainer.new()
		port_row.add_theme_constant_override("separation", 6)
		box.add_child(port_row)
		var port_label := Label.new()
		port_label.text = "ポート"
		port_label.custom_minimum_size = Vector2(64, 0)
		port_row.add_child(port_label)
		_connect_port_edit = LineEdit.new()
		_connect_port_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_connect_port_edit.text_changed.connect(_on_connect_port_changed)
		port_row.add_child(_connect_port_edit)
		var id_row := HBoxContainer.new()
		id_row.add_theme_constant_override("separation", 6)
		box.add_child(id_row)
		var id_label := Label.new()
		id_label.text = "ID"
		id_label.custom_minimum_size = Vector2(64, 0)
		id_row.add_child(id_label)
		_connect_id_edit = LineEdit.new()
		_connect_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		id_row.add_child(_connect_id_edit)
		_connect_dialog.confirmed.connect(_on_connect_confirmed)
		_connect_id_edit.text_submitted.connect(_on_connect_submitted)
		add_child(_connect_dialog)
	if target != null and not target.host.is_empty():
		_connect_host_edit.text = target.host
		_connect_port_edit.text = str(target.port)
	else:
		_connect_host_edit.text = _config.host
		_connect_port_edit.text = str(_config.port)
	_connect_id_edit.text = ""
	_connect_dialog.popup_centered(Vector2i(360, 180))
	_connect_id_edit.grab_focus()


func _on_connect_submitted(_text: String) -> void:
	_connect_dialog.hide()
	_on_connect_confirmed()


func _on_connect_port_changed(_new_text: String) -> void:
	## ポート欄では、入力中に全角数字を半角に直す。
	_convert_edit_digits(_connect_port_edit)


func _on_connect_confirmed() -> void:
	var host := _connect_host_edit.text.strip_edges()
	var port_text := PhiDigits.to_half_width_digits(_connect_port_edit.text.strip_edges())
	var char_id := _connect_id_edit.text.strip_edges()
	var tab := _connect_target
	if tab != null and not is_instance_valid(tab):
		tab = null
	if host.is_empty() or char_id.is_empty() or not port_text.is_valid_int():
		_log_active("error", "ホスト・ポート・ID を正しく入力してください")
		return
	var port := int(port_text)
	if port < 1 or port > 65535:
		_log_active("error", "ポートは 1〜65535 の整数で入力してください")
		return
	if tab == null:
		tab = _create_tab()
	_activate_tab(tab)
	_connect_tab(tab, host, port, char_id)
	_save_tab_session()


# -- 第4段: 全タブ発言 --------------------------------------------------------

func _show_sayall_dialog() -> void:
	if _sayall_dialog == null:
		_sayall_dialog = ConfirmationDialog.new()
		_sayall_dialog.theme = _dialog_theme()
		_sayall_dialog.title = "全タブ発言"
		_sayall_dialog.ok_button_text = "送信"
		_sayall_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		_sayall_dialog.add_child(box)
		var label := Label.new()
		label.text = "すべてのタブに同じ発言を送ります。"
		box.add_child(label)
		_sayall_edit = LineEdit.new()
		box.add_child(_sayall_edit)
		_sayall_dialog.confirmed.connect(_on_sayall_confirmed)
		_sayall_edit.text_submitted.connect(_on_sayall_submitted)
		add_child(_sayall_dialog)
	_sayall_edit.text = ""
	_sayall_dialog.popup_centered(Vector2i(360, 140))
	_sayall_edit.grab_focus()


func _on_sayall_submitted(_text: String) -> void:
	_sayall_dialog.hide()
	_on_sayall_confirmed()


func _on_sayall_confirmed() -> void:
	var text := _sayall_edit.text.strip_edges()
	if text.is_empty():
		return
	for tab in _tabs:
		if tab.is_session_open():
			tab.send_text(text)


# -- 追加発言(TalkAdd、残り項目) ----------------------------------------------
## Philly の EditTalkAdd。入力した言葉はアクティブなタブの
## 追加発言になり、実行中だけ保持する(保存しない)。
## 入力欄で ↓ を押すと呼び出せ、送信後は次の下書きに
## 先に入る。文言は Philly のダイアログの案内そのまま。

func _show_talk_add_dialog() -> void:
	var tab := _active_tab()
	if tab == null:
		return
	_talk_add_tab = tab
	if _talk_add_dialog == null:
		_talk_add_dialog = ConfirmationDialog.new()
		_talk_add_dialog.theme = _dialog_theme()
		_talk_add_dialog.title = "追加発言"
		_talk_add_dialog.ok_button_text = "設定"
		_talk_add_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		_talk_add_dialog.add_child(box)
		var label := Label.new()
		label.text = "発言の前に追加する言葉を入力してください"
		box.add_child(label)
		_talk_add_edit = LineEdit.new()
		box.add_child(_talk_add_edit)
		_talk_add_dialog.confirmed.connect(_on_talk_add_confirmed)
		_talk_add_edit.text_submitted.connect(_on_talk_add_submitted)
		add_child(_talk_add_dialog)
	_talk_add_edit.text = tab.talk_add_text()
	_talk_add_dialog.popup_centered(Vector2i(360, 140))
	_talk_add_edit.grab_focus()
	_talk_add_edit.caret_column = _talk_add_edit.text.length()


func _on_talk_add_submitted(_text: String) -> void:
	_talk_add_dialog.hide()
	_on_talk_add_confirmed()


func _on_talk_add_confirmed() -> void:
	## 末尾の空白も言葉の一部としてありうるので、切り詰めない。
	if _talk_add_tab != null and is_instance_valid(_talk_add_tab):
		_talk_add_tab.set_talk_add(_talk_add_edit.text)


# -- 第4段: 超魔法メニュー ------------------------------------------------------

func _build_master_magic_menu() -> void:
	## Philly の MasterMagicMenu.xml から「超魔法」メニューを作る。
	## Menu.txt の on/off に従う。項目が無ければ出さない。
	var visibility := _assets.menu_visibility()
	if visibility.get("超魔法", true) == false:
		return
	var menus: Array = _master_magic_data.get("menus", [])
	if menus.is_empty():
		return
	var caption := str(_master_magic_data.get("caption", ""))
	if caption.is_empty():
		caption = "超魔法"
	var button := MenuButton.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	_menu_bar.add_child(button)
	_menu_buttons.append(button)
	var popup := button.get_popup()
	_menu_popups.append(popup)
	_master_magic_items.clear()
	_master_magic_next_id = 0
	for menu in menus:
		_add_master_magic_menu(popup, menu)
	popup.id_pressed.connect(_on_master_magic_pressed)


func _add_master_magic_menu(parent: PopupMenu, menu: Dictionary) -> void:
	var sub := PopupMenu.new()
	sub.name = "mm_sub_%d" % _master_magic_next_id
	_master_magic_next_id += 1
	sub.id_pressed.connect(_on_master_magic_pressed)
	parent.add_child(sub)
	_menu_popups.append(sub)
	parent.add_submenu_item(str(menu.get("caption", "")), sub.name)
	var hint := str(menu.get("hint", ""))
	if not hint.is_empty():
		parent.set_item_tooltip(parent.get_item_index(parent.item_count - 1), hint)
	var items: Array = menu.get("items", [])
	for item in items:
		var item_dict: Dictionary = item
		if bool(item_dict.get("separator", false)):
			sub.add_separator()
			continue
		var id := _master_magic_next_id
		_master_magic_next_id += 1
		sub.add_item(str(item_dict.get("caption", "")), id)
		_master_magic_items[id] = item_dict
		var item_hint := str(item_dict.get("hint", ""))
		if not item_hint.is_empty():
			sub.set_item_tooltip(sub.get_item_index(id), item_hint)


func _on_master_magic_pressed(item_id: int) -> void:
	if _master_magic_running:
		return
	var node: Dictionary = _master_magic_items.get(item_id, {})
	if node.is_empty():
		return
	var tab := _active_tab()
	if tab == null or not tab.is_session_open():
		return
	_run_master_magic(tab, node)


func _run_master_magic(tab: PhiCharacter, node: Dictionary) -> void:
	## 項目の step を順番に実行する。`<send>` は5個まで有効。
	## ダイアログでやめたら、残りの step は実行しない。
	_master_magic_running = true
	var int_value := ""
	var string_value := ""
	var steps: Array = PhiMasterMagic.effective_steps(node.get("steps", []))
	for step_var in steps:
		if not is_instance_valid(tab):
			break
		var step: Dictionary = step_var
		match str(step.get("kind", "")):
			"send":
				var text := PhiMasterMagic.substitute(str(step.get("text", "")), int_value, string_value)
				tab.mark_list_answered()
				tab.send_text(text)
			"ok_dialog":
				if not await _ask_mm_yes_no(str(step.get("text", ""))):
					break
			"int_dialog":
				var value: Variant = await _ask_mm_text(str(step.get("text", "")), true)
				if value == null:
					break
				int_value = value
			"string_dialog":
				var svalue: Variant = await _ask_mm_text(str(step.get("text", "")), false)
				if svalue == null:
					break
				string_value = svalue
	_master_magic_running = false


func _ask_mm_yes_no(text: String) -> bool:
	if _mm_confirm == null:
		_mm_confirm = ConfirmationDialog.new()
		_mm_confirm.theme = _dialog_theme()
		_mm_confirm.title = "超魔法"
		_mm_confirm.ok_button_text = "はい"
		_mm_confirm.cancel_button_text = "いいえ"
		_mm_label = Label.new()
		_mm_confirm.add_child(_mm_label)
		_mm_confirm.confirmed.connect(_on_mm_confirmed)
		_mm_confirm.canceled.connect(_on_mm_canceled)
		add_child(_mm_confirm)
	_mm_label.text = text
	_mm_choice = -1
	_mm_confirm.popup_centered(Vector2i(420, 160))
	while _mm_choice < 0:
		await get_tree().process_frame
	return _mm_choice == 1


func _on_mm_confirmed() -> void:
	_mm_choice = 1


func _on_mm_canceled() -> void:
	_mm_choice = 0


func _ask_mm_text(text: String, integer: bool) -> Variant:
	## 文字列(または整数)を聞く。やめたら null、整数の入力が
	## おかしければエラーを出して null(残りの step は止める)。
	if _mm_text_dialog == null:
		_mm_text_dialog = ConfirmationDialog.new()
		_mm_text_dialog.theme = _dialog_theme()
		_mm_text_dialog.title = "超魔法"
		_mm_text_dialog.ok_button_text = "OK"
		_mm_text_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		_mm_text_label = Label.new()
		box.add_child(_mm_text_label)
		_mm_text_edit = LineEdit.new()
		box.add_child(_mm_text_edit)
		_mm_text_dialog.add_child(box)
		_mm_text_dialog.confirmed.connect(_on_mm_text_confirmed)
		_mm_text_dialog.canceled.connect(_on_mm_text_canceled)
		_mm_text_edit.text_submitted.connect(_on_mm_text_submitted)
		_mm_text_edit.text_changed.connect(_on_mm_text_changed)
		add_child(_mm_text_dialog)
	_mm_text_label.text = text
	_mm_text_edit.text = ""
	_mm_text_integer = integer
	_mm_text_choice = -1
	_mm_text_value = ""
	_mm_text_dialog.popup_centered(Vector2i(420, 160))
	_mm_text_edit.grab_focus()
	while _mm_text_choice < 0:
		await get_tree().process_frame
	if _mm_text_choice == 0:
		return null
	if integer:
		var value := PhiDigits.to_half_width_digits(_mm_text_value.strip_edges())
		if not value.is_valid_int():
			_log_active("error", "整数を入力してください")
			return null
		return str(int(value))
	return _mm_text_value


func _on_mm_text_changed(_new_text: String) -> void:
	## 整数を入れる欄では、入力中に全角数字を半角に直す。
	if _mm_text_integer:
		_convert_edit_digits(_mm_text_edit)


func _on_mm_text_confirmed() -> void:
	_mm_text_value = _mm_text_edit.text
	_mm_text_choice = 1


func _on_mm_text_canceled() -> void:
	_mm_text_choice = 0


func _on_mm_text_submitted(_text: String) -> void:
	_mm_text_dialog.hide()
	_on_mm_text_confirmed()


# -- 第4段: 画像表示窓 ---------------------------------------------------------

func _build_image_window() -> void:
	_image_window = Window.new()
	_image_window.theme = _dialog_theme()
	_image_window.title = "画像一覧"
	_image_window.transient = true
	_image_window.min_size = Vector2i(480, 360)
	_image_window.visible = false
	_image_window.close_requested.connect(_on_image_window_close_requested)
	add_child(_image_window)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	_image_window.add_child(box)
	_image_list = ItemList.new()
	_image_list.custom_minimum_size = Vector2(0, 120)
	_image_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_image_list.item_selected.connect(_on_image_selected)
	box.add_child(_image_list)
	_image_preview = TextureRect.new()
	_image_preview.custom_minimum_size = Vector2(0, 200)
	_image_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_image_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_image_preview)
	_image_status = Label.new()
	_image_status.text = ""
	box.add_child(_image_status)
	var refresh := Button.new()
	refresh.text = "更新"
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.pressed.connect(_refresh_image_window)
	box.add_child(refresh)


func _on_image_window_close_requested() -> void:
	_cancel_image_fetch()
	_image_window.hide()


func _show_image_window() -> void:
	if _image_window == null:
		_build_image_window()
	if not _image_opened_once:
		_image_opened_once = true
		_image_window.popup_centered(Vector2i(560, 480))
	else:
		_image_window.show()
	_refresh_image_window()


func _refresh_image_window() -> void:
	if _image_window == null or not _image_window.visible:
		return
	_cancel_image_fetch()
	_image_list.clear()
	_image_preview.texture = null
	var tab := _active_tab()
	if tab == null:
		_image_status.text = "タブがありません"
		return
	var refs := tab.image_refs()
	for ref in refs:
		var idx := _image_list.add_item(str(ref["url"]))
		_image_list.set_item_metadata(idx, ref)
	_image_status.text = "%d 件の参照" % refs.size()


func _on_image_selected(index: int) -> void:
	var ref: Dictionary = _image_list.get_item_metadata(index)
	var url := str(ref.get("url", ""))
	var tab := _active_tab()
	# 接続中のゲームサーバと同じホストの URL だけ、クリックした時に
	# 限り取得する。それ以外はテキスト表示だけ(自動取得はしない)。
	if tab == null or not PhiImages.can_fetch(url, tab.host):
		_image_preview.texture = null
		_image_status.text = "取得しません(接続中のサーバと違うホストのURLです)"
		return
	_fetch_image(url)


func _fetch_image(url: String) -> void:
	_cancel_image_fetch()
	var req := HTTPRequest.new()
	req.body_size_limit = PhiImages.MAX_IMAGE_BYTES
	req.max_redirects = 0
	req.timeout = 15.0
	req.request_completed.connect(_on_image_request_completed)
	add_child(req)
	_image_request = req
	_image_status.text = "取得中: " + url
	var err := req.request(url, ["User-Agent: NeoPHI"])
	if err != OK:
		_image_status.text = "要求できません: " + error_string(err)
		_cancel_image_fetch()


func _cancel_image_fetch() -> void:
	if _image_request != null and is_instance_valid(_image_request):
		_image_request.cancel_request()
		_image_request.queue_free()
	_image_request = null


func _on_image_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var req := _image_request
	_image_request = null
	if req != null and is_instance_valid(req):
		req.queue_free()
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		_image_status.text = "大きすぎます(2MiBまで)"
		return
	if result == HTTPRequest.RESULT_TIMEOUT:
		_image_status.text = "タイムアウトしました"
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_image_status.text = "取得できませんでした(結果 %d)" % result
		return
	if response_code != 200:
		_image_status.text = "HTTP %d" % response_code
		return
	var img := _decode_image(body)
	if img == null:
		_image_status.text = "画像として読めませんでした"
		return
	_image_preview.texture = ImageTexture.create_from_image(img)
	_image_status.text = "%d x %d" % [img.get_width(), img.get_height()]


func _decode_image(data: PackedByteArray) -> Image:
	var img := Image.new()
	if img.load_png_from_buffer(data) == OK:
		return img
	img = Image.new()
	if img.load_jpg_from_buffer(data) == OK:
		return img
	img = Image.new()
	if img.load_webp_from_buffer(data) == OK:
		return img
	img = Image.new()
	if img.load_bmp_from_buffer(data) == OK:
		return img
	if img.has_method("load_gif_from_buffer"):
		img = Image.new()
		if int(img.call("load_gif_from_buffer", data)) == OK:
			return img
	return null


# -- 入力 ----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	## キー処理は _input で先に受ける。_unhandled_key_input だと、矢印キーや
	## Tab が GUI のフォーカス移動に奪われて届かないことがある。
	## 全体にかかるキー(Ctrl+Tab・Shift+F6・Alt+G)はここで取り、
	## 残りはアクティブなタブに渡す。
	var tab := _active_tab()
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null:
		if tab != null:
			tab.handle_mouse_button(mouse_event)
		return
	var motion_event := event as InputEventMouseMotion
	if motion_event != null:
		if tab != null:
			tab.handle_mouse_motion(motion_event)
		return
	var key_event := event as InputEventKey
	if key_event == null or tab == null:
		return
	# (1)離したキーは、押し続けの移動キーから外す。
	if not key_event.pressed:
		tab.release_held_move(key_event)
		return
	# (2)OS のキー繰り返しは無視する。繰り返しは地図の到着で刻む。
	if key_event.echo:
		return
	var code := PhiKeys.code_name(key_event.physical_keycode)
	if code.is_empty():
		code = PhiKeys.code_name(key_event.keycode)
	if not _keytest.is_empty():
		print("key: keycode=", key_event.keycode, " physical=", key_event.physical_keycode, " code=[", code, "] focus=", tab.debug_input_focus())
	var shift := key_event.shift_pressed
	var ctrl := key_event.ctrl_pressed
	var alt := key_event.alt_pressed
	var meta := key_event.meta_pressed
	# Ctrl+Tab / Shift+Ctrl+Tab で前後のタブへ移動する。
	if code == "Tab" and ctrl and not alt and not meta:
		_switch_tab(-1 if shift else 1)
		get_viewport().set_input_as_handled()
		return
	# Alt+G(あいさつ)と Shift+F6(priv ウィンドウ)は、
	# フォーカスに関わらず効く。
	if alt and not shift and not ctrl and code == "KeyG":
		tab.send_greeting()
		get_viewport().set_input_as_handled()
		return
	if shift and not ctrl and not alt and code == "F6":
		_toggle_priv_window()
		get_viewport().set_input_as_handled()
		return
	if tab.handle_key(key_event):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _fx_demo:
		_fx_demo_in -= delta
		if _fx_demo_in <= 0.0:
			var tab := _active_tab()
			if tab != null:
				tab.fx_demo_tick()
			_fx_demo_in = 2.5
	if _shot_path != "" and not _shot_done:
		_elapsed += delta
		if _elapsed >= _shot_delay:
			_shot_done = true
			_take_shot()


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
			var tab0 := _active_tab()
			print("keytest: typed '", text, "' focus=", tab0.debug_input_focus() if tab0 != null else false, " text=[", tab0.debug_input_text() if tab0 != null else "", "]")
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
		var tab1 := _active_tab()
		print("keytest: key ", key_name, " focus=", tab1.debug_input_focus() if tab1 != null else false, " text=[", tab1.debug_input_text() if tab1 != null else "", "]")
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
		var tab2 := _active_tab()
		print("keytest: after ", key_name, " focus_owner=", owner, " input_focus=", tab2.debug_input_focus() if tab2 != null else false, " text=[", tab2.debug_input_text() if tab2 != null else "", "]")


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
		_log_active("system", "マップ画像を保存しました: " + path)
	else:
		_log_active("error", "マップ画像の保存に失敗しました: " + error_string(err))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# 窓からフォーカスが外れたら、押し続けている移動キーを離した扱いにする。
		for tab in _tabs:
			tab.clear_held_input()
		# BGM は、非アクティブ時も鳴らす設定でなければ一時停止する
		# (第5段。Philly の PlayBgmDeactivate=off の振る舞い)。
		if _sound_engine != null and _config.play_bgm and not _config.play_bgm_deactivate and _sound_engine.bgm_state() == "playing":
			_sound_engine.bgm_pause()
			_bgm_focus_paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _bgm_focus_paused:
			_bgm_focus_paused = false
			_sound_engine.bgm_resume()
