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
## 開発用の ~/workspace/phi-option-data の順に、同梱パック
## (CHIP_PACKS / CHARA_PACKS)を探す。例:
##   godot --path . -- --host 127.0.0.1 --port 20017 --id guest
##   --chip-dir ~/workspace/phi-option-data/chip_tofup
##   --chara-dir ~/workspace/phi-option-data/chara_tofup

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 20017
const DEFAULT_ID := "guest"
## 同梱グラフィックスのパック名(探す順=優先順)。先のパックに
## ある絵が優先され、無い絵は後のパックから補われる。
const CHIP_PACKS := ["chip_tofup", "chip_pcgl", "chip_ryur"]
const CHARA_PACKS := ["chara_tofup", "chara_typecall", "chara_typeoall", "chara_guran", "chara_lanu"]

## 「キャラクター」メニューの項目 ID(第7段)。
const CHARA_MENU_NEW := 1
const CHARA_MENU_NEXT := 2
const CHARA_MENU_PREV := 3
const CHARA_MENU_NONE := 4
const CHARA_MENU_IMPORT := 5
const CHARA_MENU_ENTRY_BASE := 100
## 新規キャラクター作成ダイアログの大きさ。
const REGISTER_DIALOG_SIZE := Vector2i(480, 560)

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
var _italics_font: Font = null
var _bold_italics_font: Font = null
var _system_font: SystemFont = null
var _menu_buttons: Array[MenuButton] = []
var _menu_popups: Array[PopupMenu] = []
var _scroll_popup: PopupMenu = null
var _scroll_item := -1
var _smooth_popup: PopupMenu = null
var _smooth_item := -1
var _disp_magic_popup: PopupMenu = null
var _disp_magic_item := -1
var _log_image_popup: PopupMenu = null
var _log_image_item := -1
var _loud_popup: PopupMenu = null
var _loud_item := -1
var _autosave_popup: PopupMenu = null
var _autosave_item := -1
var _delete_filter_popup: PopupMenu = null
var _delete_filter_item := -1
var _bgm_popup: PopupMenu = null
var _bgm_item := -1
var _se_popup: PopupMenu = null
var _se_item := -1
var _mm_always_popup: PopupMenu = null
var _mm_always_item := -1
var _ui_style_popup: PopupMenu = null
var _ui_style_item := -1
var _map_align_popup: PopupMenu = null
var _ma_center_item := -1
var _ma_left_item := -1
var _ma_right_item := -1
var _master_magic_button: MenuButton = null
var _map_mode_popup: PopupMenu = null
var _m5_item := -1
var _m7_item := -1
var _m11_item := -1
var _mturn_item := -1
var _msolid_item := -1
## 音の司令塔(第5段)。全タブ共有で1つだけ持つ。
var _sound_engine: PhiSoundEngine = null
## 窓のフォーカスを失って BGM を一時停止したか。
var _bgm_focus_paused := false
var _ask_dialog: ConfirmationDialog = null
var _ask_title: Label = null
var _ask_label: Label = null
var _ask_edit: LineEdit = null
var _ask_label2: Label = null
var _ask_edit2: LineEdit = null
var _ask_action := ""
var _ask_numeric := false
var _about_dialog: Window = null
## ダイアログテーマ用の空アイコン(埋め込み側の × を消す)。
static var _empty_icon: Texture2D = null
var _about_opened := false
## 更新チェック (第40段)。GitHub リリースを見に行く。
var _update_http: HTTPRequest = null
var _update_busy := false
var _update_manual := false
var _update_retried := false
var _update_dialog: Window = null
var _update_label: Label = null
var _update_info: Dictionary = {}
var _loud_dialog: ConfirmationDialog = null
var _loud_tab: PhiCharacter = null
## BGM ゲートの前回の状態 (第74段)。開閉が変わった時だけ
## _apply_tab_bgm を呼び直すための覚え。
var _bgm_gate_tab: PhiCharacter = null
var _bgm_gate_suspended := false
var _shortcut_dialog: ConfirmationDialog = null
var _shortcut_inner_box: VBoxContainer = null
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
## 接続ダイアログの「登録済みキャラクター」選択(第7段)。
var _connect_chara_select: OptionButton = null
var _connect_characters: Array = []
## 「キャラクター」メニューと新規作成ダイアログ(第7段)。
var _chara_popup: PopupMenu = null
var _chara_menu_entries: Array = []
## キャラデータ読み込みのフォルダ選択と結果通知。
var _import_dialog: FileDialog = null
var _log_dir_dialog: FileDialog = null
var _import_notice: AcceptDialog = null
var _import_notice_label: Label = null
var _register_dialog: ConfirmationDialog = null
var _register_world_select: OptionButton = null
var _register_address_edit: LineEdit = null
var _register_comment: Label = null
var _register_help: Label = null
var _register_url_button: Button = null
var _register_name_edit: LineEdit = null
var _register_mail_edit: LineEdit = null
var _register_worlds: Array = []
var _register_url := ""
var _sayall_dialog: ConfirmationDialog = null
var _sayall_edit: LineEdit = null
var _talk_add_dialog: ConfirmationDialog = null
var _talk_add_edit: LineEdit = null
var _talk_add_tab: PhiCharacter = null
var _map_size_dialog: ConfirmationDialog = null
var _map_size_mode: OptionButton = null
var _map_size_spin: SpinBox = null
var _display_size_dialog: ConfirmationDialog = null
var _display_menu_spin: SpinBox = null
var _display_icon_spin: SpinBox = null
var _display_repeat_spin: SpinBox = null
var _alt_confirm_dialog: ConfirmationDialog = null
var _alt_confirm_label: Label = null
var _pending_alt_action := ""
## メニュー/ツールバー経由の Call / Return 確認待ち (第25段)。
var _pending_menu_action := ""
var _pending_menu_tab: PhiCharacter = null
## Alt 経由で確認済みの実行は、_do_action 側の確認を素通りさせる。
var _confirm_ok_pass := false
var _transfer_dialog: ConfirmationDialog = null
var _transfer_label: Label = null
var _transfer_tab: PhiCharacter = null
var _unew_panel: PhiUnewPanel = null

## 第4段: タブの一覧と行の部品。行の各タブは
## {tab, button, close, holder}。
var _tabs: Array[PhiCharacter] = []
var _tab_buttons: Array[Dictionary] = []
## 選択中タブの青い地 (遅延生成して共有)。
var _tab_active_box: StyleBoxFlat = null
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
var _eagle_window: PhiEagleWindow = null
var _medit_window: PhiMEditWindow = null
var _medit_tab: PhiCharacter = null
var _sound_test_window: PhiSoundTestWindow = null
var _chip_viewer: PhiChipViewer = null
var _chara_viewer: PhiCharaViewer = null
var _image_list: ItemList = null
var _image_preview: TextureRect = null
var _image_status: Label = null
var _image_opened_once := false
var _image_request: HTTPRequest = null

var _startup_map_size := -1
var _startup_map_style := ""
## 起動時に自動接続するのは、コマンドラインで ID が明示された
## 時だけ (ユーザーの指定 2026-11-17)。設定ファイルの接続先
## だけでは接続しない。
var _startup_connect := false
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
	_italics_font = PhiFont.make_italics_font(_system_font)
	_bold_italics_font = PhiFont.make_bold_italics_font(_system_font)
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
	_hook_macos_about_menu()
	# 起動直後はアプリメニューがまだ組み上がっていないことが
	# あるので、フックは次フレームにもう一度試す (冪等)。
	_hook_macos_about_menu.call_deferred()
	_start_auto_update_check()
	get_window().size_changed.connect(_on_window_size_changed)
	var main_tab := _restore_tabs()
	_activate_tab(main_tab)
	_apply_chrome_size()
	_update_action_states()
	_log_active("system", "NeoPHI " + PhiVersion.VERSION)
	if not _assets_warning.is_empty():
		_log_active("system", _assets_warning)
	if _startup_connect:
		# 明示の自動接続。同じキャラの復元タブがあればそちらに
		# つなぎ、無ければ空タブにつなぐ。
		var host := str(get_meta("host"))
		var port := int(get_meta("port"))
		var char_id := str(get_meta("char_id"))
		var existing := _find_tab_for_character(host, port, char_id)
		if existing != null:
			_activate_tab(existing)
			_connect_tab(existing, host, port, char_id, true)
		elif main_tab.host.is_empty() and main_tab.player_name().is_empty() and main_tab.restored_name.is_empty():
			# 復元タブが無く、空タブが返ってきた時だけそれを使う。
			_connect_tab(main_tab, host, port, char_id, true)
		else:
			var fresh := _create_tab()
			_activate_tab(fresh)
			_connect_tab(fresh, host, port, char_id, true)
	else:
		_log_active("system", "接続待ちです。キャラクターメニューから接続してください")
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


func _style_menu_button(button: MenuButton) -> void:
	## メニューバーのボタンの見た目。地は金属を透かし、
	## ホバー・押下の時だけ薄く色を重ねる。
	button.focus_mode = Control.FOCUS_NONE
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
		# 地は金属を透かし、ホバー・押下だけ薄く重ねて見せる。
		_style_menu_button(button)
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
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_scroll_popup = popup
				_scroll_item = popup.get_item_index(item_id)
			elif action_name == "SmoothScroll":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_smooth_popup = popup
				_smooth_item = popup.get_item_index(item_id)
			elif action_name == "Loud":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_loud_popup = popup
				_loud_item = popup.get_item_index(item_id)
			elif action_name == "DispMagic":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_disp_magic_popup = popup
				_disp_magic_item = popup.get_item_index(item_id)
			elif action_name == "LogImage":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_log_image_popup = popup
				_log_image_item = popup.get_item_index(item_id)
			elif action_name == "LogAutoSave":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_autosave_popup = popup
				_autosave_item = popup.get_item_index(item_id)
			elif action_name == "LogDeleteFilter":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_delete_filter_popup = popup
				_delete_filter_item = popup.get_item_index(item_id)
			elif action_name == "PlayBGM":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_bgm_popup = popup
				_bgm_item = popup.get_item_index(item_id)
			elif action_name == "PlaySE":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_se_popup = popup
				_se_item = popup.get_item_index(item_id)
			elif action_name == "MasterMagicAlways":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_mm_always_popup = popup
				_mm_always_item = popup.get_item_index(item_id)
			elif action_name == "UiStyleFloat":
				popup.add_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_ui_style_popup = popup
				_ui_style_item = popup.get_item_index(item_id)
			elif action_name == "MapAlignCenter" or action_name == "MapAlignLeft" or action_name == "MapAlignRight":
				# マップ配置は排他なのでラジオチェックで出す。
				popup.add_radio_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_map_align_popup = popup
				var align_index := popup.get_item_index(item_id)
				match action_name:
					"MapAlignCenter":
						_ma_center_item = align_index
					"MapAlignLeft":
						_ma_left_item = align_index
					"MapAlignRight":
						_ma_right_item = align_index
			elif action_name == "M5x5" or action_name == "M7x7" or action_name == "M11x11" or action_name == "MTurn" or action_name == "MSolid":
				# 地図モードは排他なのでラジオチェックで出す。
				popup.add_radio_check_item(PhiActions.key_label(str(action["caption"])), item_id)
				_map_mode_popup = popup
				var mode_index := popup.get_item_index(item_id)
				match action_name:
					"M5x5":
						_m5_item = mode_index
					"M7x7":
						_m7_item = mode_index
					"M11x11":
						_m11_item = mode_index
					"MTurn":
						_mturn_item = mode_index
					"MSolid":
						_msolid_item = mode_index
			else:
				popup.add_item(PhiActions.key_label(str(action["caption"])), item_id)
			var index := popup.get_item_index(item_id)
			popup.set_item_metadata(index, action_name)
			popup.set_item_tooltip(index, PhiActions.key_label(str(action["hint"])))
			var accel := PhiActions.accelerator_for(action_name)
			if accel != 0:
				popup.set_item_accelerator(index, accel)
			var icon: Variant = _assets.button_icon(action_name)
			if icon != null:
				popup.set_item_icon(index, icon)
			item_id += 1
		popup.id_pressed.connect(_on_menu_id_pressed.bind(popup))
		if menu_name == "ファイル":
			_build_character_menu(bar)
	_build_master_magic_menu()


func _on_menu_id_pressed(item_id: int, popup: PopupMenu) -> void:
	var index := popup.get_item_index(item_id)
	var action_name := str(popup.get_item_metadata(index))
	_do_action(action_name)


# -- 第7段: キャラクターメニューと登録 -----------------------------------------

func _build_character_menu(bar: HBoxContainer) -> void:
	## 「キャラクター」メニュー(Philly/WPHI と同じくファイルの次)。
	## 中身は開くたびに作り直す(登録済みキャラクターの一覧が
	## 変わるため)。スキンの Menu.txt で off なら出さない。
	var visibility := _assets.menu_visibility()
	if visibility.get("キャラクター", true) == false:
		return
	var button := MenuButton.new()
	button.text = "キャラクター"
	_style_menu_button(button)
	bar.add_child(button)
	_menu_buttons.append(button)
	_chara_popup = button.get_popup()
	_menu_popups.append(_chara_popup)
	_chara_popup.about_to_popup.connect(_rebuild_character_menu)
	_chara_popup.id_pressed.connect(_on_character_menu_pressed)
	_rebuild_character_menu()


func _set_menu_item_icon(popup: PopupMenu, index: int, key: String) -> void:
	## メニュー項目にアイコンを付ける。メタデータにキーを残し、
	## 文字サイズ適用時のアイコン更新(メタデータ経由)にも乗せる。
	popup.set_item_metadata(index, key)
	var icon: Variant = _assets.button_icon_sized(key, maxi(24, _applied_chrome_size))
	if icon != null:
		popup.set_item_icon(index, icon)


func _rebuild_character_menu() -> void:
	## キャラクターメニューの中身を作り直す。
	## 新規作成、登録済みキャラクターの一覧、タブ移動の順。
	if _chara_popup == null:
		return
	_chara_menu_entries = _registered_characters()
	_chara_popup.clear()
	_chara_popup.add_item("新規キャラクター作成...", CHARA_MENU_NEW)
	_set_menu_item_icon(_chara_popup, _chara_popup.item_count - 1, "CreateCharacter")
	_chara_popup.add_item("キャラデータを読み込む...", CHARA_MENU_IMPORT)
	_set_menu_item_icon(_chara_popup, _chara_popup.item_count - 1, "ImportCharacter")
	_chara_popup.add_separator()
	if _chara_menu_entries.is_empty():
		_chara_popup.add_item("（登録済みキャラクターはありません）", CHARA_MENU_NONE)
		_set_menu_item_icon(_chara_popup, _chara_popup.item_count - 1, "CharaEntry")
		_chara_popup.set_item_disabled(_chara_popup.get_item_index(CHARA_MENU_NONE), true)
	else:
		for i in _chara_menu_entries.size():
			_chara_popup.add_item(str(_chara_menu_entries[i]["display_name"]), CHARA_MENU_ENTRY_BASE + i)
			_set_menu_item_icon(_chara_popup, _chara_popup.item_count - 1, "CharaEntry")
	_chara_popup.add_separator()
	_chara_popup.add_item("次のタブ", CHARA_MENU_NEXT)
	_set_menu_item_icon(_chara_popup, _chara_popup.item_count - 1, "NextTab")
	_chara_popup.set_item_accelerator(
		_chara_popup.get_item_index(CHARA_MENU_NEXT), KEY_TAB | KEY_MASK_CTRL)
	_chara_popup.add_item("前のタブ", CHARA_MENU_PREV)
	_set_menu_item_icon(_chara_popup, _chara_popup.item_count - 1, "PrevTab")
	_chara_popup.set_item_accelerator(
		_chara_popup.get_item_index(CHARA_MENU_PREV),
		KEY_TAB | KEY_MASK_CTRL | KEY_MASK_SHIFT)


func _on_character_menu_pressed(item_id: int) -> void:
	match item_id:
		CHARA_MENU_NEW:
			_show_register_dialog()
		CHARA_MENU_IMPORT:
			_show_import_dialog()
		CHARA_MENU_NEXT:
			_switch_tab(1)
		CHARA_MENU_PREV:
			_switch_tab(-1)
		_:
			if item_id >= CHARA_MENU_ENTRY_BASE:
				var idx := item_id - CHARA_MENU_ENTRY_BASE
				if idx < _chara_menu_entries.size():
					var entry: Dictionary = _chara_menu_entries[idx]
					_connect_character(str(entry["host"]), int(entry["port"]), str(entry["id"]), str(entry["display_name"]))


func _character_roots() -> Array:
	## キャラクターの置き場の候補。Philly ルート群 + `user://`。
	var roots: Array = []
	for root in _assets.philly_roots:
		if not roots.has(root):
			roots.append(root)
	roots.append("user://")
	return roots


func _registered_characters() -> Array:
	## 登録済みキャラクターの一覧({display_name, id, host, port, root})。
	return PhiCharacters.scan_roots(_character_roots())


func _on_tab_register_completed(_display_name: String, _tab: PhiCharacter) -> void:
	_save_tab_session()


func _registered_entry_for_id(host: String, port: int, char_id: String) -> Dictionary:
	## 接続先と ID が一致する登録済みキャラ。無ければ空の辞書。
	if char_id.is_empty():
		return {}
	for entry in _registered_characters():
		if str(entry["host"]) == host and int(entry["port"]) == port and str(entry["id"]) == char_id:
			return entry
	return {}


func _on_tab_auto_register_ready(tab: PhiCharacter) -> void:
	## 登録ファイルの無いキャラ (手入力の ID など) が接続に成功し、
	## サーバから名前が届いたので、キャラクター一覧へ登録する
	## (第134段)。これが無いと手入力キャラは一覧に出ず、タブを
	## 閉じると再接続の手段が無くなっていた。書き込むのは従来の
	## `.phirc` の範囲 (ID と接続先) だけで、パスワード等は保存
	## しない。
	var char_id := tab.session.char_id
	if char_id.is_empty() or tab.player_name().is_empty():
		return
	# 同じ接続先+ID の登録が既にあれば、それを尊重して何もしない。
	if not _registered_entry_for_id(tab.host, tab.port, char_id).is_empty():
		return
	var root := PhiCharacters.chara_root(_assets.philly_roots)
	var made := PhiCharacters.make_display_name(tab.player_name(), PhiCharacters.scan_root(root), root)
	if not bool(made["ok"]):
		tab.log_message("error", str(made["error"]))
		return
	var display_name := str(made["display_name"])
	if PhiCharacters.write_phirc(root, display_name, char_id, tab.host, tab.port):
		tab.log_message("system", "キャラクター一覧に登録しました: %s" % display_name)
		tab.set_restored_name(display_name)
		_save_tab_session()
	else:
		tab.log_message("error", "ID ファイル(.phirc)の保存に失敗しました。ID は %s です。必ず控えてください。" % char_id)


func _import_dialog_theme() -> Theme:
	## フォルダ選択ダイアログ用のテーマ。標準の FileDialog は
	## メイン画面のテーマを引き継がず文字が小さくなるため、
	## 画面の倍率に合った文字サイズを各部品に渡す。
	var theme := Theme.new()
	theme.default_font = _font
	var size := _applied_font_size if _applied_font_size > 0 else 15
	theme.default_font_size = size
	for cls in ["Label", "LineEdit", "Button", "CheckBox", "PopupMenu", "OptionButton"]:
		theme.set_font("font", cls, _font)
		theme.set_font_size("font_size", cls, size)
	theme.set_font("font", "Tree", _font)
	theme.set_font_size("font_size", "Tree", size)
	theme.set_font("font", "ItemList", _font)
	theme.set_font_size("font_size", "ItemList", size)
	return theme


func _show_import_dialog() -> void:
	## Philly のキャラデータがあるフォルダを選ばせる。
	if _import_dialog == null:
		_import_dialog = FileDialog.new()
		_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_import_dialog.title = "Philly のフォルダを選択"
		_import_dialog.transparent = true
		_import_dialog.dir_selected.connect(_on_import_dir_selected)
		add_child(_import_dialog)
	_import_dialog.theme = _import_dialog_theme()
	for root_var in _assets.philly_roots:
		var root := str(root_var)
		if not root.is_empty() and DirAccess.open(root) != null:
			_import_dialog.current_dir = ProjectSettings.globalize_path(root)
			break
	var root_size := get_tree().root.size
	var want := Vector2(
		maxf(760.0, root_size.x * 0.62), maxf(520.0, root_size.y * 0.62))
	_import_dialog.popup_centered(Vector2i(UiStyle.fit_popup_size(want, Vector2(root_size))))


func _show_log_dir_dialog() -> void:
	## ログの保存先フォルダを選ばせる (第99段、利用者の要望)。
	## 設定自体は [Log] LogSaveDir に前からあったが、画面から
	## 変える手段が無かった。自動保存・手動保存・WireTrace の
	## 記録はすべてこの保存先に従う。
	if _log_dir_dialog == null:
		_log_dir_dialog = FileDialog.new()
		_log_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_log_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_log_dir_dialog.title = "ログの保存先を選択"
		_log_dir_dialog.transparent = true
		_log_dir_dialog.dir_selected.connect(_on_log_dir_selected)
		add_child(_log_dir_dialog)
	_log_dir_dialog.theme = _import_dialog_theme()
	var current := ProjectSettings.globalize_path(_config.log_save_dir)
	if DirAccess.open(current) != null:
		_log_dir_dialog.current_dir = current
	var root_size := get_tree().root.size
	var want := Vector2(
		maxf(760.0, root_size.x * 0.62), maxf(520.0, root_size.y * 0.62))
	_log_dir_dialog.popup_centered(Vector2i(UiStyle.fit_popup_size(want, Vector2(root_size))))


func _on_log_dir_selected(folder: String) -> void:
	## 選ばれたフォルダを保存先にして、設定に残す。
	_config.log_save_dir = folder
	_save_config()
	_log_active("system", "ログの保存先を変更しました: " + folder)


func _on_import_dir_selected(folder: String) -> void:
	## 選ばれたフォルダ直下の `*.chara` を全部取り込む。
	## 既に登録済みの表示名は上書きしない。
	var dest_root := PhiCharacters.chara_root(_assets.philly_roots)
	var result := PhiCharacters.import_from(folder, dest_root, _registered_characters())
	_rebuild_character_menu()
	var found := int(result["found"])
	var imported := int(result["imported"])
	var skipped := int(result["skipped"])
	var msg := ""
	if found == 0:
		msg = "選択したフォルダにキャラクターデータ (*.chara) が\n見つかりませんでした。"
	elif imported > 0:
		msg = "%d 件のキャラクターを読み込みました。" % imported
		if skipped > 0:
			msg += "\n%d 件は既に登録済みのためスキップしました。" % skipped
	else:
		msg = "見つかった %d 件はすべて既に登録済みでした。" % found
	_log_active("system", msg.replace("\n", ""))
	_show_import_notice(msg)


func _show_import_notice(msg: String) -> void:
	if _import_notice == null:
		_import_notice = AcceptDialog.new()
		_import_notice.theme = _dialog_theme()
		_import_notice.transparent = true
		_import_notice.title = ""
		_import_notice.ok_button_text = "閉じる"
		var box := VBoxContainer.new()
		box.add_child(_dlg_title("キャラデータを読み込む"))
		_import_notice_label = Label.new()
		box.add_child(_import_notice_label)
		_import_notice.add_child(box)
		_draggable_title(box, _import_notice)
		add_child(_import_notice)
	_import_notice_label.text = msg
	_import_notice.popup_centered(Vector2i(420, 170))


func _apply_chrome_size() -> void:
	## メニューバー・プルダウンメニュー・ツールチップ・タブ行の
	## 文字は、設定の固定値 (MenuFontSize) で付ける。かつては
	## アクティブなタブの地図の倍率に連動していたが、タブの
	## 切断・終了で極端に小さくなる事があったため連動を廃止
	## した (ユーザーの指定)。`size` (個室窓の文字) は従来どおり
	## 倍率から決める。タブの中の文字は、各タブが付ける。
	var tab := _active_tab()
	if tab == null:
		return
	var zoom := tab.debug_map_zoom()
	var size := PhiFont.ui_size_for_zoom(zoom)
	var chrome_size := _config.menu_font_size
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
	var check_tex := UiStyle.check_texture(chrome_size)
	# プルダウンメニューのアイコンは元の20pxより少し大きくする
	# (ユーザーの要望)。文字がそれより大きい倍率では文字に合わせる。
	var menu_icon_px := maxi(24, chrome_size)
	for popup in _menu_popups:
		popup.add_theme_font_size_override("font_size", chrome_size)
		popup.add_theme_font_size_override("font_separator_size", chrome_size)
		# テーマ標準のチェック印は小さいので、文字の大きさに
		# 合わせた太い印に差し替える(ユーザーの要望)。
		if check_tex != null:
			popup.add_theme_icon_override("checked", check_tex)
			popup.add_theme_icon_override("radio_checked", check_tex)
		for i in popup.item_count:
			var meta: Variant = popup.get_item_metadata(i)
			if meta == null:
				continue
			var sized_icon: Variant = _assets.button_icon_sized(str(meta), menu_icon_px)
			if sized_icon != null:
				popup.set_item_icon(i, sized_icon)
	for entry in _tab_buttons:
		(entry["button"] as Button).add_theme_font_size_override("font_size", chrome_size)
		(entry["close"] as Button).add_theme_font_size_override("font_size", chrome_size)
	if _plus_button != null:
		_plus_button.add_theme_font_size_override("font_size", chrome_size)
	if _priv_window != null:
		_priv_window.apply_font_size(maxi(size, 15))
	_refresh_dialog_themes()


func _refresh_dialog_themes() -> void:
	## 作り済みのダイアログ/窓へ、現在のテーマを付け直す。
	## テーマは作った時点で固定されるため、フォント設定
	## (MenuFontSize) を変えても、付け直さないと本文の文字が
	## 古い大きさのまま残る (りんぐ報告、2026-11-23)。
	## 個室窓とファイル選択は倍率連動が指定なので対象外。
	var wins: Array[Window] = []
	for win in [_ask_dialog, _transfer_dialog, _import_notice,
			_about_dialog, _update_dialog, _loud_dialog,
			_shortcut_dialog, _connect_dialog, _sayall_dialog,
			_talk_add_dialog, _map_size_dialog, _display_size_dialog,
			_alt_confirm_dialog, _mm_confirm, _mm_text_dialog,
			_image_window, _eagle_window, _medit_window,
			_sound_test_window, _chip_viewer, _chara_viewer,
			_unew_panel]:
		if win != null:
			wins.append(win)
	if _register_dialog != null:
		_register_dialog.theme = _register_dialog_theme()
	if wins.is_empty():
		return
	var dialog_theme := _dialog_theme()
	for win in wins:
		win.theme = dialog_theme


func _apply_args(args: Dictionary) -> void:
	## 設定ファイルの値を既定にし、コマンドライン引数で上書きする。
	var host: String = args.get("host", _config.host)
	var port: int = int(args.get("port", str(_config.port)))
	var char_id: String = args.get("id", DEFAULT_ID)
	_startup_connect = args.has("id") or args.has("keytest")
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
		for pack in CHIP_PACKS:
			var found_chip := _find_asset_dir(pack)
			if not found_chip.is_empty():
				chip_dirs.append(found_chip)
		if chip_dirs.is_empty():
			missing.append("chip_tofup")
	if args.has("chara-dir"):
		for part in str(args["chara-dir"]).split(",", false):
			chara_dirs.append(part)
	else:
		for pack in CHARA_PACKS:
			var found_chara := _find_asset_dir(pack)
			if not found_chara.is_empty():
				chara_dirs.append(found_chara)
		if chara_dirs.is_empty():
			missing.append("chara_tofup")
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
	## 保存してあるタブを未接続で復元する。1 つでも復元できたら
	## そのタブを返し、空タブは作らない (起動時に未接続タブが
	## 勝手に増えないように)。何も無ければ空タブを 1 つ作る。
	var first: PhiCharacter = null
	if not _no_config and _config.load_tab_session:
		for entry in PhiTabSession.load_file(_tab_session_path):
			var restored := _create_tab()
			restored.host = str(entry["host"])
			restored.port = int(entry["port"])
			restored.restored_name = str(entry.get("name", ""))
			# ID はタブセッションに保存してある (第116段)。手入力で
			# つないだキャラは登録ファイルが無いので、これが無いと
			# 復元タブは二度とつなげない。
			restored.session.char_id = str(entry.get("id", ""))
			# 名前が空で ID だけ残っているタブは、ID が一致する
			# 登録済みキャラの表示名で題名を補う。
			if restored.restored_name.is_empty() and not restored.session.char_id.is_empty():
				for reg in _registered_characters():
					if str(reg["host"]) == restored.host and int(reg["port"]) == restored.port \
							and str(reg["id"]) == restored.session.char_id:
						restored.restored_name = _display_name_body(str(reg["display_name"]))
						break
			# 名前が空で保存されていたタブは、接続先が一致する
			# 登録済みキャラが1つだけなら、その名前と ID で
			# 補う (タブの題名が接続先表示のままにならないように)。
			if restored.restored_name.is_empty():
				var host_entry := _registered_entry_for_host(restored.host, restored.port)
				if not host_entry.is_empty():
					restored.restored_name = _display_name_body(str(host_entry["display_name"]))
					restored.session.char_id = str(host_entry["id"])
			# セッションに ID が無い (古い形式で保存された) タブは、
			# 登録済みキャラと一致すれば ID を登録ファイルから
			# 引き直す。これで復元タブも「全キャラを接続」や再接続の
			# 対象になる。
			if restored.session.char_id.is_empty():
				var resolved_id := _resolve_registered_id(restored.host, restored.port, restored.restored_name)
				if not resolved_id.is_empty():
					restored.session.char_id = resolved_id
			if first == null:
				first = restored
			_refresh_tab_titles()
	if first != null:
		return first
	return _create_tab()


func _save_tab_session() -> void:
	## 開いているタブのホスト・ポート・キャラ名・ID を保存する。
	## パスワードは保存しない (ID は第116段から保存する)。
	if _no_config:
		return
	var states: Array = []
	for tab in _tabs:
		states.append(tab.session_state())
	PhiTabSession.save_file(states, _tab_session_path)


func _registered_entry_for_host(host: String, port: int) -> Dictionary:
	## 接続先が一致する登録済みキャラが、ちょうど1つだけの時に
	## それを返す。0個・複数個の時は空の辞書。
	var found: Dictionary = {}
	for entry in _registered_characters():
		if str(entry["host"]) == host and int(entry["port"]) == port:
			if not found.is_empty():
				return {}
			found = entry
	return found


func _registered_id_for(host: String, port: int, chara_name: String) -> String:
	## 登録済みキャラの中から、接続先と名前が一致するものの ID を
	## 返す。表示名は `NN_名前` 形式なので、番号部分を外して比べる。
	## 一致しなければ空文字。
	if chara_name.is_empty():
		return ""
	for entry in _registered_characters():
		if str(entry["host"]) != host or int(entry["port"]) != port:
			continue
		var display := str(entry["display_name"])
		if display == chara_name or _display_name_body(display) == chara_name:
			return str(entry["id"])
	return ""


func _resolve_registered_id(host: String, port: int, chara_name: String) -> String:
	## 復元タブの ID 引き直し (第108段)。名前の完全一致で引けない
	## 場合の受け皿を用意する。セッションに保存される名前は
	## サーバが知らせるログイン名で、登録時の表示名と食い違う
	## ことがある (例: 表示名 `03_Ring` に対してログイン名
	## `Ring material`)。また接続先の表記 (ホスト名/IP) が
	## `.phirc` と食い違うこともある。どちらも「候補が1つだけ」
	## の時に限って引き直すので、取り違えは起きない。
	var exact := _registered_id_for(host, port, chara_name)
	if not exact.is_empty():
		return exact
	var entries := _registered_characters()
	# 接続先が一致する登録済みキャラが1つだけなら、それを使う。
	# (辞書は参照渡しなので、候補の保持に clear() 等で触らない)
	var host_hits: Array = []
	for entry in entries:
		if str(entry["host"]) == host and int(entry["port"]) == port:
			host_hits.append(entry)
	if host_hits.size() == 1:
		return str(host_hits[0]["id"])
	# 名前とポートが一致する登録済みキャラが1つだけなら、それを使う
	# (ホスト表記の揺れの受け皿)。
	if not chara_name.is_empty():
		var name_hits: Array = []
		for entry in entries:
			if int(entry["port"]) != port:
				continue
			var display := str(entry["display_name"])
			if display == chara_name or _display_name_body(display) == chara_name:
				name_hits.append(entry)
		if name_hits.size() == 1:
			return str(name_hits[0]["id"])
	return ""


static func _display_name_body(display: String) -> String:
	## 表示名 `NN_名前` の名前部分。番号が付いていなければそのまま。
	var us := display.find("_")
	if us > 0 and display.substr(0, us).is_valid_int():
		return display.substr(us + 1)
	return display


func _find_tab_for_character(host: String, port: int, char_id: String, display_name: String = "") -> PhiCharacter:
	## 同じキャラのタブがあれば返す。無ければ null。
	## 第 1 優先は接続先と ID の一致。第 2 に、ID を引き直せて
	## いない復元タブでも、接続先と名前が一致し未接続なら
	## そのキャラのタブとみなす (使い回し時に ID を付け直す)。
	if not char_id.is_empty():
		for t in _tabs:
			if t.host == host and t.port == port and t.session.char_id == char_id:
				return t
	if not display_name.is_empty():
		var body := _display_name_body(display_name)
		for t in _tabs:
			if t.host != host or t.port != port or t.is_session_open():
				continue
			var tname := t.player_name() if not t.player_name().is_empty() else t.restored_name
			if tname == display_name or tname == body:
				return t
	return null


func _take_pristine_tab() -> PhiCharacter:
	## まだ何にも使われていない未接続タブがあれば返す。
	## 初回起動時の空タブを最初のキャラ接続で使い回し、
	## 空タブが残り続けないようにする (第67段)。
	for t in _tabs:
		if t.host.is_empty() and t.restored_name.is_empty() \
				and t.session.char_id.is_empty() and not t.is_session_open():
			return t
	return null


func _connect_character(host: String, port: int, char_id: String, display_name: String = "") -> PhiCharacter:
	## キャラへの接続。同じキャラのタブがあればそれを使い回し、
	## 無ければ新しいタブを作る (Philly と同じ挙動)。接続中の
	## タブがあれば、つなぎ直さずに切り替えるだけにする。
	## 同じキャラのタブが無くても、未使用の空タブがあれば
	## それを使い回す (初回起動時の空タブ対策、第67段)。
	var tab := _find_tab_for_character(host, port, char_id, display_name)
	if tab == null:
		tab = _take_pristine_tab()
	if tab == null:
		tab = _create_tab()
	elif tab.session.char_id != char_id:
		# 名前で使い回した復元タブには、選んだキャラの ID を
		# 付け直す (次回からは ID でも一致するようになる)。
		tab.session.char_id = char_id
	_activate_tab(tab)
	if not tab.is_session_open():
		_connect_tab(tab, host, port, char_id)
	if not display_name.is_empty():
		tab.set_restored_name(display_name)
	_save_tab_session()
	return tab


func _connect_tab(tab: PhiCharacter, host: String, port: int, char_id: String, use_startup: bool = false) -> void:
	## タブを接続する。地図の大きさ・様式は、初回の自動接続だけ
	## コマンドライン引数を優先し、あとは設定の値を使う。
	# 11x11 希望でも、接続はまず 7x7 で始める (第68段改)。
	tab.session.desired_map_size = _config.map_size
	tab.session.map_size = 57 if _config.map_size == 121 else _config.map_size
	tab.session.map_style = _config.map_style
	tab.session.disp_magic = _config.disp_magic
	if use_startup:
		if _startup_map_size > 0:
			tab.session.desired_map_size = _startup_map_size
			tab.session.map_size = 57 if _startup_map_size == 121 else _startup_map_size
		if not _startup_map_style.is_empty():
			tab.session.map_style = _startup_map_style
	tab.connect_to(host, port, char_id)
	# 登録ファイルの無いキャラ (手入力の ID など) は、接続に
	# 成功した時点で一覧へ登録する対象にしておく (第134段)。
	# 登録済みのキャラは対象にしない (既存の登録を尊重する)。
	tab.auto_register_pending = _registered_entry_for_id(host, port, char_id).is_empty()
	_update_action_states()


func _connect_all_tabs() -> void:
	## 全キャラを接続(WPHI のファイルメニュー)。前回の接続先と ID が
	## 残っているタブだけをつなぎ直す。
	var count := 0
	for t in _tabs:
		if t.can_reconnect():
			_connect_tab(t, t.host, t.port, t.session.char_id)
			count += 1
	if count == 0:
		_log_active("system", "接続できるタブがありません")
	_update_action_states()


func _disconnect_all_tabs(force: bool) -> void:
	## 全キャラを切断 / 強制切断(WPHI のファイルメニュー)。
	for t in _tabs:
		if t.is_session_open():
			if force:
				t.disconnect_force()
			else:
				t.disconnect_graceful()
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
	if _smooth_popup != null and _smooth_item >= 0:
		_smooth_popup.set_item_checked(_smooth_item, _config.smooth_scroll)
	if _loud_popup != null and _loud_item >= 0:
		_loud_popup.set_item_checked(_loud_item, loud)
	if _disp_magic_popup != null and _disp_magic_item >= 0:
		_disp_magic_popup.set_item_checked(_disp_magic_item, _config.disp_magic)
	if _log_image_popup != null and _log_image_item >= 0:
		_log_image_popup.set_item_checked(_log_image_item, _config.log_image_disp)
	if _autosave_popup != null and _autosave_item >= 0:
		_autosave_popup.set_item_checked(_autosave_item, _config.log_auto_save)
	if _delete_filter_popup != null and _delete_filter_item >= 0:
		_delete_filter_popup.set_item_checked(_delete_filter_item, _config.log_delete_filter)
	if _bgm_popup != null and _bgm_item >= 0:
		_bgm_popup.set_item_checked(_bgm_item, _config.play_bgm)
	if _se_popup != null and _se_item >= 0:
		_se_popup.set_item_checked(_se_item, _config.sound_play)
	if _mm_always_popup != null and _mm_always_item >= 0:
		_mm_always_popup.set_item_checked(_mm_always_item, _config.master_magic_always)
	if _map_mode_popup != null:
		# 地図モードのチェックは設定(現在のモード)に合わせる。
		if _m5_item >= 0:
			_map_mode_popup.set_item_checked(_m5_item, _config.map_size == 40)
		if _m7_item >= 0:
			_map_mode_popup.set_item_checked(_m7_item, _config.map_size == 57)
		if _m11_item >= 0:
			_map_mode_popup.set_item_checked(_m11_item, _config.map_size == 121)
		if _mturn_item >= 0:
			_map_mode_popup.set_item_checked(_mturn_item, _config.map_style == "turn")
		if _msolid_item >= 0:
			_map_mode_popup.set_item_checked(_msolid_item, _config.map_style == "solid")
	if _ui_style_popup != null and _ui_style_item >= 0:
		_ui_style_popup.set_item_checked(_ui_style_item, _config.ui_style == "new")
	if _map_align_popup != null:
		if _ma_center_item >= 0:
			_map_align_popup.set_item_checked(_ma_center_item, _config.map_align == 0)
		if _ma_left_item >= 0:
			_map_align_popup.set_item_checked(_ma_left_item, _config.map_align == 1)
		if _ma_right_item >= 0:
			_map_align_popup.set_item_checked(_ma_right_item, _config.map_align == 2)
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
	var size := _dialog_body_size()
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
	# 角の処理と半透過: 土台はフロート窓と同じ半透過の板
	# (角丸12px+細い縁取り)。地の余白と枠の内容余白は、
	# 既定テーマの値をそのまま使う。
	# ※ 上の余白(28)は Mac では「タイトル帯」として確保され、
	# 中身の枠より上の帯でしか窓を掴めなくなる(ユーザーの報告)。
	# 題名は中身側に出しているので、帯は最小限(6px)にする。
	var frame := UiStyle.window_plate_stylebox()
	frame.content_margin_left = 10
	frame.content_margin_top = 6
	frame.content_margin_right = 10
	frame.content_margin_bottom = 8
	theme.set_stylebox("embedded_border", "Window", frame)
	var frame_dim := UiStyle.window_plate_stylebox()
	frame_dim.bg_color.a = 0.78
	frame_dim.content_margin_left = 10
	frame_dim.content_margin_top = 6
	frame_dim.content_margin_right = 10
	frame_dim.content_margin_bottom = 8
	theme.set_stylebox("embedded_unfocused_border", "Window", frame_dim)
	# 埋め込み側のタイトル帯は使わない: 帯の高さ(title_height 既定36)を
	# 0にし、帯に出る × アイコンも空にする。帯が残ると、Mac では
	# 「枠の上の透明な部分に × と見えないドラッグバーがある」見た目に
	# なる(ユーザーの報告)。閉じる操作と移動は中身側の × と
	# 題名行ドラッグ(PhiWindowDrag)でまかなう。
	if _empty_icon == null:
		var icon_img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		icon_img.fill(Color(0, 0, 0, 0))
		_empty_icon = ImageTexture.create_from_image(icon_img)
	theme.set_icon("close", "Window", _empty_icon)
	theme.set_icon("close_pressed", "Window", _empty_icon)
	theme.set_constant("title_height", "Window", 0)
	var panel := UiStyle.window_plate_stylebox()
	panel.content_margin_left = 8
	panel.content_margin_top = 8
	panel.content_margin_right = 8
	panel.content_margin_bottom = 8
	theme.set_stylebox("panel", "AcceptDialog", panel)
	# ボタンは世界名ヘッダーと同じ金属プレートにする
	# (ユーザーの要望: ボタン部分は金属プレートで分かりやすく)。
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state_name, "Button", UiStyle.metal_button_stylebox(state_name))
	theme.set_color("font_color", "Button", UiStyle.metal_button_font_color("normal"))
	theme.set_color("font_hover_color", "Button", UiStyle.metal_button_font_color("hover"))
	theme.set_color("font_pressed_color", "Button", UiStyle.metal_button_font_color("pressed"))
	theme.set_color("font_disabled_color", "Button", UiStyle.metal_button_font_color("disabled"))
	theme.set_color("font_focus_color", "Button", UiStyle.metal_button_font_color("normal"))
	return theme


func _dialog_body_size() -> int:
	## ダイアログの本文の文字サイズ。リストやステータスパネルと
	## 同じく、全体のフォント設定 (MenuFontSize) に追従させる
	## (りんぐ報告、2026-11-23。倍率連動のまま残っていて、
	## 題名だけが大きく見えていた)。
	return _config.menu_font_size


func _title_font_size() -> int:
	## 題名の文字サイズ。本文より一回り大きくする。固定値(20)に
	## すると、ズームの大きい環境では本文(22)より題名が小さく
	## 見えてしまう(ユーザーの報告)。
	return maxi(18, int(round(float(_dialog_body_size()) * 1.3)))


func _dlg_title_label(text: String, gold: bool = false) -> Label:
	## ダイアログ/ウィンドウの題名ラベル。OS/埋め込み側のタイトル帯は
	## 環境によって地が描かれず文字だけ浮くので、タイトル文字列は
	## 窓に持たせず、中身の先頭にこのラベルを置く。
	var label := Label.new()
	label.text = text
	# 題名は本文より一回り大きく+太字で出す(ユーザーの指定)。
	if _bold_font != null:
		label.add_theme_font_override("font", _bold_font)
	label.add_theme_font_size_override("font_size", _title_font_size())
	if gold:
		label.add_theme_color_override("font_color", Color(0.96, 0.89, 0.70))
	return label


func _dlg_title(text: String, gold: bool = false) -> Control:
	## 題名行そのもの (濃紺の帯つき)。中のラベルは meta "label"。
	var label := _dlg_title_label(text, gold)
	var band := UiStyle.title_band(label)
	band.set_meta("label", label)
	return band


func _draggable_title(box: Container, window: Window) -> void:
	## ダイアログの題名行 (box の先頭) をドラッグハンドルにする。
	## 埋め込み側のタイトル帯は消してあるので、これが無い確認
	## ダイアログは掴む場所が無く動かせなかった (第17段)。
	if box.get_child_count() > 0 and box.get_child(0) is Control:
		PhiWindowDrag.attach(box.get_child(0) as Control, window)


func _register_dialog_theme() -> Theme:
	## 新規作成ダイアログ専用のテーマ。土台とボタンは _dialog_theme()
	## と同じ(半透過の地+金属プレートのボタン)。金属テクスチャの板は
	## ウィンドウの地(panel)ではなく中身の枠(PanelContainer)に貼る。
	## panel にテクスチャを貼る方式は Mac で地が描かれなかったため。
	## ここの panel は枠の後ろに透ける単色(テクスチャ中央の色)にする。
	var theme := _dialog_theme()
	var tex := UiStyle.dialog_texture(REGISTER_DIALOG_SIZE)
	if tex == null:
		return theme
	var center := Color(0.16, 0.145, 0.125, 0.95)
	var img := tex.get_image()
	if img != null and img.get_width() > 0 and img.get_height() > 0:
		center = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		center.a = 0.95
	for style_name in ["embedded_border", "embedded_unfocused_border"]:
		var frame := StyleBoxFlat.new()
		frame.bg_color = center
		frame.set_corner_radius_all(UiStyle.FLOAT_RADIUS)
		frame.content_margin_left = 10
		frame.content_margin_top = 6
		frame.content_margin_right = 10
		frame.content_margin_bottom = 8
		theme.set_stylebox(style_name, "Window", frame)
	var panel := StyleBoxFlat.new()
	panel.bg_color = center
	panel.set_corner_radius_all(UiStyle.FLOAT_RADIUS)
	panel.content_margin_left = 8
	panel.content_margin_top = 8
	panel.content_margin_right = 8
	panel.content_margin_bottom = 8
	theme.set_stylebox("panel", "AcceptDialog", panel)
	theme.set_color("title_color", "Window", Color(0.96, 0.89, 0.70))
	return theme


# -- 第4段: タブの管理 ----------------------------------------------------------

func _active_tab() -> PhiCharacter:
	if _active_index < 0 or _active_index >= _tabs.size():
		return null
	return _tabs[_active_index]


func _create_tab() -> PhiCharacter:
	var tab := PhiCharacter.new()
	tab.italics_font = _italics_font
	tab.bold_italics_font = _bold_italics_font
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
	tab.eagle_eye_received.connect(_on_tab_eagle_eye.bind(tab))
	tab.edit_requested.connect(_on_tab_edit_requested.bind(tab))
	tab.transfer_confirm_requested.connect(_on_tab_transfer_confirm.bind(tab))
	tab.status_changed.connect(_on_tab_status_changed.bind(tab))
	tab.register_completed.connect(_on_tab_register_completed.bind(tab))
	tab.auto_register_ready.connect(_on_tab_auto_register_ready.bind(tab))
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


## タブのドラッグ並べ替え (第70段、Philly 仕様)。
var _tab_drag_tab: PhiCharacter = null
var _tab_drag_start_x := 0.0
var _tab_dragging := false


func _on_tab_button_gui_input(event: InputEvent, tab: PhiCharacter) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		_update_tab_drag(mm, tab)
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if mb.double_click and not tab.is_session_open():
				_show_connect_dialog(tab)
				return
			_tab_drag_tab = tab
			_tab_drag_start_x = mb.global_position.x
			_tab_dragging = false
		elif _tab_drag_tab == tab:
			_end_tab_drag()
		return
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE and _config.mclick_tab_close:
		_close_tab(tab)


func _update_tab_drag(mm: InputEventMouseMotion, tab: PhiCharacter) -> void:
	## 押し始めてから 6px 以上動いたらドラッグとみなし、
	## ポインタの位置に合わせてその場で並べ替える。
	if _tab_drag_tab != tab or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	if not _tab_dragging:
		if absf(mm.global_position.x - _tab_drag_start_x) <= 6.0:
			return
		_tab_dragging = true
		_set_tab_drag_visual(tab, true)
	var target := _tab_drop_index(mm.global_position.x)
	if target != _tabs.find(tab):
		_move_tab(tab, target)


func _end_tab_drag() -> void:
	if _tab_drag_tab != null:
		_set_tab_drag_visual(_tab_drag_tab, false)
	_tab_drag_tab = null
	_tab_dragging = false


func _set_tab_drag_visual(tab: PhiCharacter, on: bool) -> void:
	for e in _tab_buttons:
		if e["tab"] == tab:
			(e["button"] as Button).modulate.a = 0.55 if on else 1.0
			return


func _tab_drop_index(global_x: float) -> int:
	## ポインタの x から、タブを差し込む位置を求める。
	for i in range(_tab_buttons.size()):
		var holder := _tab_buttons[i]["holder"] as Control
		if global_x < holder.get_global_rect().get_center().x:
			return i
	return maxi(_tab_buttons.size() - 1, 0)


func _move_tab(tab: PhiCharacter, to_index: int) -> void:
	## タブの並び順を変える。並びはタブの保存にも反映される。
	var from := _tabs.find(tab)
	if from < 0:
		return
	var eidx := -1
	for i in range(_tab_buttons.size()):
		if _tab_buttons[i]["tab"] == tab:
			eidx = i
			break
	if eidx < 0:
		return
	to_index = clampi(to_index, 0, _tabs.size() - 1)
	if from == to_index:
		return
	var active := _active_tab()
	_tabs.remove_at(from)
	_tabs.insert(to_index, tab)
	var entry: Dictionary = _tab_buttons[eidx]
	_tab_buttons.remove_at(eidx)
	_tab_buttons.insert(to_index, entry)
	_tab_row.move_child(entry["holder"] as Control, to_index)
	_tab_row.move_child(_plus_button, _tab_row.get_child_count() - 1)
	_tab_container.move_child(tab, to_index)
	_active_index = _tabs.find(active)
	_refresh_tab_titles()
	_save_tab_session()


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
	_update_master_magic_visibility()
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
	if _tab_drag_tab == tab:
		_end_tab_drag()
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


func _active_tab_box() -> StyleBoxFlat:
	## 選択中タブ用の青い地 (共有して使い回す)。
	if _tab_active_box == null:
		_tab_active_box = StyleBoxFlat.new()
		_tab_active_box.bg_color = Color(0.16, 0.36, 0.88)
		_tab_active_box.set_corner_radius_all(4)
		_tab_active_box.content_margin_left = 8
		_tab_active_box.content_margin_right = 8
		_tab_active_box.content_margin_top = 3
		_tab_active_box.content_margin_bottom = 3
	return _tab_active_box


func _refresh_tab_titles() -> void:
	for entry in _tab_buttons:
		var tab: PhiCharacter = entry["tab"]
		var button: Button = entry["button"]
		var title := tab.tab_title()
		if tab.unread:
			title = "! " + title
		button.text = title
		button.set_pressed_no_signal(tab == _active_tab())
		# 選択中のタブは青くして見分けやすくする。
		if tab == _active_tab():
			button.add_theme_stylebox_override("normal", _active_tab_box())
			button.add_theme_stylebox_override("hover", _active_tab_box())
			button.add_theme_stylebox_override("pressed", _active_tab_box())
			button.add_theme_color_override("font_color", Color.WHITE)
			button.add_theme_color_override("font_hover_color", Color.WHITE)
			button.add_theme_color_override("font_pressed_color", Color.WHITE)
		else:
			button.remove_theme_stylebox_override("normal")
			button.remove_theme_stylebox_override("hover")
			button.remove_theme_stylebox_override("pressed")
			button.remove_theme_color_override("font_color")
			button.remove_theme_color_override("font_hover_color")
			button.remove_theme_color_override("font_pressed_color")
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


func _on_tab_transfer_confirm(host: String, port: int, tab: PhiCharacter) -> void:
	## 世界移動 (違うホスト) の確認。Python 版 GUI の文面と同じ。
	_transfer_tab = tab
	if _transfer_dialog == null:
		_transfer_dialog = ConfirmationDialog.new()
		_transfer_dialog.theme = _dialog_theme()
		_transfer_dialog.transparent = true
		_transfer_dialog.title = ""
		_transfer_dialog.ok_button_text = "移動する"
		_transfer_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		_transfer_dialog.add_child(box)
		box.add_child(_dlg_title("世界移動"))
		_transfer_label = Label.new()
		box.add_child(_transfer_label)
		_transfer_dialog.confirmed.connect(_on_transfer_ok)
		_transfer_dialog.canceled.connect(_on_transfer_cancel)
		_draggable_title(box, _transfer_dialog)
		add_child(_transfer_dialog)
	_transfer_label.text = "別のホスト %s:%d へキャラIDを送って移動しますか？" % [host, port]
	_transfer_dialog.popup_centered()


func _on_transfer_ok() -> void:
	if _transfer_tab != null:
		_transfer_tab.answer_transfer(true)
	_transfer_tab = null


func _on_transfer_cancel() -> void:
	if _transfer_tab != null:
		_transfer_tab.answer_transfer(false)
	_transfer_tab = null


func _on_tab_eagle_eye(event: Dictionary, assets: GameAssets, mapset: String, zoom: float, defines: Dictionary, tab: PhiCharacter) -> void:
	## Eagle Eye の広域マップ窓を開く (無ければ作る)。どのタブで
	## 唱えても同じ窓を使い、題名にタブ名を出す。
	if _eagle_window == null:
		_eagle_window = PhiEagleWindow.new()
		_eagle_window.theme = _dialog_theme()
		_eagle_window.transparent = true
		_eagle_window.title_font = _bold_font
		_eagle_window.title_size = _title_font_size()
		_eagle_window.image_saved.connect(func(path: String) -> void:
			_log_active("system", "イーグルアイの画像を保存しました: " + path))
		add_child(_eagle_window)
	_eagle_window.title_size = _title_font_size()
	_eagle_window.show_event(event, assets, mapset, zoom, tab.tab_title(), defines)


func _on_tab_edit_requested(mode: String, tab: PhiCharacter) -> void:
	## 看板編集の窓 (タブごとにサーバの編集状態があるので、
	## 窓は使い回しつつ持ち主のタブを覚える)。
	if mode == "multi":
		_medit_tab = tab
		if _medit_window == null:
			_medit_window = PhiMEditWindow.new()
			_medit_window.theme = _dialog_theme()
			_medit_window.transparent = true
			_medit_window.title_font = _bold_font
			_medit_window.body_font = _font
			_medit_window.bold_font = _bold_font
			_medit_window.italics_font = _italics_font
			_medit_window.bold_italics_font = _bold_italics_font
			_medit_window.title_size = _title_font_size()
			_medit_window.send_requested.connect(_on_medit_send)
			_medit_window.cancel_requested.connect(_on_medit_cancel)
			add_child(_medit_window)
		# テーマ (下部の説明文やボタン) も表示のたびに付け直す。
		_medit_window.theme = _dialog_theme()
		_medit_window.title_size = _title_font_size()
		_medit_window.body_size = _dialog_body_size()
		_medit_window.show_editor(tab.tab_title())
	elif mode == "end":
		if _medit_window != null and _medit_tab == tab:
			_medit_window.close_silent()
			_medit_tab = null
			tab.log_message("system", "エディタを閉じました。")


func _on_medit_send(lines: Array) -> void:
	var tab := _medit_tab
	_medit_tab = null
	if tab == null:
		return
	for line in lines:
		tab.send_line(str(line))
	tab.send_line(".")


func _on_medit_cancel() -> void:
	var tab := _medit_tab
	_medit_tab = null
	if tab != null:
		tab.send_line(".!")


func _dir_file_names(dir_path: String, extensions: Array) -> Array[String]:
	## フォルダ直下のファイル名 (拡張子つき) を集める。
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir():
			for ext in extensions:
				if name.to_lower().ends_with("." + str(ext)):
					out.append(name)
					break
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _sound_names(subdir: String, extensions: Array) -> Array[String]:
	## Philly ルートの sound/<subdir>/ にあるファイル名の和集合。
	var seen := {}
	var out: Array[String] = []
	for root in _assets.philly_roots:
		for name in _dir_file_names(root.path_join("sound").path_join(subdir), extensions):
			if not seen.has(name):
				seen[name] = true
				out.append(name)
	out.sort()
	return out


func _show_sound_test() -> void:
	## サウンドテスト窓 (ツール、第18段)。
	if _sound_test_window == null:
		_sound_test_window = PhiSoundTestWindow.new()
		_sound_test_window.theme = _dialog_theme()
		_sound_test_window.transparent = true
		_sound_test_window.title_font = _bold_font
		_sound_test_window.title_size = _title_font_size()
		add_child(_sound_test_window)
	_sound_test_window.title_size = _title_font_size()
	_sound_test_window.setup(_sound_engine, _assets.philly_roots,
		_sound_names("se", ["wav"]), _sound_names("bgm", ["mid", "midi"]),
		_config.sound_play, _config.play_bgm)
	_sound_test_window.show_viewer()


func _mapset_names() -> Array[String]:
	## チップフォルダにある <mapset>.bmp の名前の和集合。
	var seen := {}
	var out: Array[String] = []
	for dir_path in _assets.chip_dirs:
		for name in _dir_file_names(dir_path, ["bmp"]):
			var base := name.get_basename()
			if not seen.has(base.to_lower()):
				seen[base.to_lower()] = true
				out.append(base)
	out.sort()
	return out


func _show_chip_viewer() -> void:
	## マップチップ確認窓 (ツール、第18段)。
	if _chip_viewer == null:
		_chip_viewer = PhiChipViewer.new()
		_chip_viewer.theme = _dialog_theme()
		_chip_viewer.transparent = true
		_chip_viewer.title_font = _bold_font
		_chip_viewer.title_size = _title_font_size()
		_chip_viewer.body_font = _font
		add_child(_chip_viewer)
	_chip_viewer.title_size = _title_font_size()
	var current := ""
	var tab := _active_tab()
	if tab != null:
		current = str(tab.get("_mapset"))
	_chip_viewer.setup(_assets, _mapset_names(), current)
	_chip_viewer.show_viewer()


func _chara_names() -> Array[String]:
	## キャラフォルダにある <名前>.bmp の名前の和集合。
	## LANU 系も含む (キャラグラとしては通常どおり読めるため)。
	var seen := {}
	var out: Array[String] = []
	for dir_path in _assets.chara_dirs:
		for name in _dir_file_names(dir_path, ["bmp"]):
			var base := name.get_basename()
			if not seen.has(base.to_lower()):
				seen[base.to_lower()] = true
				out.append(base)
	out.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
	return out


func _show_chara_viewer() -> void:
	## キャラグラ確認窓 (ツール、第18段)。
	if _chara_viewer == null:
		_chara_viewer = PhiCharaViewer.new()
		_chara_viewer.theme = _dialog_theme()
		_chara_viewer.transparent = true
		_chara_viewer.title_font = _bold_font
		_chara_viewer.title_size = _title_font_size()
		_chara_viewer.body_font = _font
		add_child(_chara_viewer)
	_chara_viewer.title_size = _title_font_size()
	_chara_viewer.setup(_assets, _chara_names())
	_chara_viewer.show_viewer()


func _apply_tab_bgm(tab: PhiCharacter) -> void:
	## アクティブなタブの BGM を鳴らす/止める。
	## 条件がそろわなければ止める。同じ曲が鳴っていれば
	## 再生し直さず、速度だけ合わせる。
	if _sound_engine == null or tab == null or tab != _active_tab():
		return
	if not _config.play_bgm or tab.bgm_name.is_empty() or not tab.is_session_open():
		_sound_engine.bgm_stop()
		return
	if tab.bgm_suspended():
		# 重い処理の間は止めずに一時停止する (第74段)。
		# 曲の位置を保ち、落ち着いたら続きから再開する。
		_sound_engine.bgm_pause()
		return
	var path := tab.bgm_resolved_path()
	if path.is_empty():
		_sound_engine.bgm_stop()
		return
	if _sound_engine.bgm_state() == "paused" \
			and _sound_engine.bgm_current_path() == path:
		_sound_engine.bgm_resume()
	else:
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
	## アプリの窓が前面でない時は、タスクバー (Dock) の点滅で知らせる。
	if not get_window().has_focus():
		DisplayServer.window_request_attention()
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
			if _needs_action_confirm(action_name):
				# Call / Return はメニュー・ツールバー経由でも
				# 確認を挟む (Philly DialogForCall/DialogForReturn)。
				_show_action_confirm(tab, action_name)
				return
			tab.do_send_action(action_name)
			_remember_map_mode(action_name, tab)
		"ask":
			_ask_text(action_name)
		"ask2":
			_ask_text(action_name)
		"v6-bag":
			if tab != null:
				tab.toggle_v6_bag()
		"v6-trade":
			if tab != null:
				tab.toggle_v6_trade()
		"v6-quests":
			if tab != null:
				tab.toggle_v6_quests()
		"map-size-dialog":
			_show_map_size_dialog()
		"display-size-dialog":
			_show_display_size_dialog()
		"priv-window":
			_toggle_priv_window()
		"loud-toggle":
			if tab != null:
				tab.set_loud(not tab.is_loud())
				_update_action_states()
		"shortcut-config":
			_show_shortcut_dialog()
		"sound-test":
			_show_sound_test()
		"chip-viewer":
			_show_chip_viewer()
		"chara-viewer":
			_show_chara_viewer()
		"unew-panel":
			# Unew 方式のデータ取得パネル(第8段)。窓は使い回す。
			if _unew_panel == null:
				_unew_panel = PhiUnewPanel.new(_assets.philly_roots)
				_unew_panel.theme = _dialog_theme()
				_unew_panel.transparent = true
				_unew_panel.title_font = _bold_font
				_unew_panel.body_size = _dialog_body_size()
				add_child(_unew_panel)
			else:
				_unew_panel.body_size = _dialog_body_size()
				_unew_panel.set_roots(_assets.philly_roots)
			_unew_panel.show_window()
		"connect":
			if tab != null and not tab.is_session_open():
				if tab.can_reconnect():
					# そのタブのキャラで直接つなぎ直す
					# (Philly の「接続」)。ダイアログは出さない。
					_connect_tab(tab, tab.host, tab.port, tab.session.char_id)
				else:
					_show_connect_dialog(tab)
		"disconnect":
			if tab != null:
				tab.disconnect_graceful()
		"force-disconnect":
			if tab != null:
				tab.disconnect_force()
		"connect-all":
			_connect_all_tabs()
		"disconnect-all":
			_disconnect_all_tabs(false)
		"force-disconnect-all":
			_disconnect_all_tabs(true)
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
					var menu_icon: Variant = _assets.button_icon_sized(str(meta), maxi(24, _applied_chrome_size))
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
		"smooth-scroll-toggle":
			# スムーズマップスクロール (第65段)。北固定の時だけ
			# MapView 側で効く。外すと従来どおり切り替わる。
			_config.smooth_scroll = not _config.smooth_scroll
			for t in _tabs:
				t.apply_smooth_scroll()
			_update_action_states()
			_save_config()
		"ui-style-toggle":
			# 表示スタイル (第101段、0.5.0)。新スタイルはログと
			# 入力欄が地図の上に浮く。切替は1つに統一し、両方の
			# 窓がまとめて切り替わる (ユーザーの指定)。
			_config.ui_style = "old" if _config.ui_style == "new" else "new"
			for t in _tabs:
				t.apply_ui_style()
			_update_action_states()
			_save_config()
		"map-align":
			# マップ配置 (第101段)。中央/左寄せ/右寄せ。
			_config.map_align = int(PhiActions.get_action(action_name).get("align", 0))
			for t in _tabs:
				t.apply_map_align()
			_update_action_states()
			_save_config()
		"layout-to-all-tabs":
			# 窓配置を全タブにそろえる (第107段、ユーザーの要望)。
			# アクティブなタブの窓の位置・大きさを正として設定へ
			# 書き戻し、全タブへ反映する。フォント設定は元々
			# 全タブ共通なので、付け直しだけ行う。
			if tab != null:
				tab.sync_float_rects_to_config()
				for t in _tabs:
					t.apply_float_layout_from_config()
				_save_config()
				_log_active("system", "窓の配置を全タブにそろえました")
		"disp-magic-toggle":
			# 魔法表示の受け取りを切り替える(第3段)。接続中なら即座に伝える。
			_config.disp_magic = not _config.disp_magic
			if tab != null:
				tab.session.disp_magic = _config.disp_magic
				if tab.is_session_open():
					tab.send_line("#ex-switch ex-disp-magic=" + ("true" if _config.disp_magic else "false"))
			# 魔法弾の有無も「魔法表示」に連動する (全タブへ反映)。
			for t in _tabs:
				t.apply_magic_effect()
			_update_action_states()
			_save_config()
		"image-toggle":
			# ログへの画像埋め込み表示 (第48段、Philly LogImageDisp)。
			# on にしたら、既にログにある画像も取りに行って出し直す。
			_config.log_image_disp = not _config.log_image_disp
			_update_action_states()
			_save_config()
			for t in _tabs:
				t.refresh_log_images()
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
		"log-save-dir":
			_show_log_dir_dialog()
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
		"se-toggle":
			# 効果音を再生するか。BGM とは独立 (止めたりしない)。
			_config.sound_play = not _config.sound_play
			_update_action_states()
			_save_config()
		"master-magic-toggle":
			# 超魔法メニューをマスターでなくても出すか (WPHI の
			# masterMagicMenu 設定)。
			_config.master_magic_always = not _config.master_magic_always
			_update_action_states()
			_update_master_magic_visibility()
			_save_config()
		"open-config-folder":
			OS.shell_open(ProjectSettings.globalize_path("user://"))
		"update-check":
			_check_update(true)
		"about":
			_show_about()


func _remember_map_mode(action_name: String, tab: PhiCharacter) -> void:
	## 地図モードの変更は設定に覚えて、次回ログイン時にも使う。
	match action_name:
		"M5x5":
			_config.map_size = 40
			if _config.map_style != "turn":
				# 5x5 は北固定にできない (常に向きで回る) ので、
				# 様式も回転へ自動で切り替える (ユーザーの指定)。
				# 接続中はサーバへも style=turn を送る。
				_config.map_style = "turn"
				if tab.is_session_open():
					tab.do_send_action("MTurn")
		"M7x7":
			_config.map_size = 57
		"M11x11":
			_config.map_size = 121
		"MTurn":
			_config.map_style = "turn"
		"MSolid":
			_config.map_style = "solid"
		_:
			return
	tab.session.map_size = _config.map_size
	tab.session.map_style = _config.map_style
	_save_config()
	_update_action_states()
	tab.refresh_compass_mode()


func _ask_text(action_name: String) -> void:
	## 言葉を聞いてから送るアクション(Pay/Search/Appear/Disappear)。
	var action := PhiActions.get_action(action_name)
	if action.is_empty():
		return
	if _ask_dialog == null:
		_ask_dialog = ConfirmationDialog.new()
		_ask_dialog.theme = _dialog_theme()
		_ask_dialog.transparent = true
		_ask_dialog.title = ""
		_ask_dialog.ok_button_text = "送信"
		_ask_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		var ask_band := _dlg_title("")
		_ask_title = ask_band.get_meta("label") as Label
		box.add_child(ask_band)
		_ask_label = Label.new()
		box.add_child(_ask_label)
		_ask_edit = LineEdit.new()
		box.add_child(_ask_edit)
		_ask_label2 = Label.new()
		box.add_child(_ask_label2)
		_ask_edit2 = LineEdit.new()
		box.add_child(_ask_edit2)
		_ask_dialog.add_child(box)
		_ask_dialog.confirmed.connect(_on_ask_confirmed)
		_ask_edit.text_submitted.connect(_on_ask_submitted)
		_ask_edit2.text_submitted.connect(_on_ask2_submitted)
		_ask_edit.text_changed.connect(_on_ask_text_changed)
		_draggable_title(box, _ask_dialog)
		add_child(_ask_dialog)
	# テーマと題名の大きさは作った時点で固定されるので、
	# 出すたびに現在のフォント設定で付け直す (Pay などの
	# 説明文が古い大きさのまま残らないように)。
	_ask_dialog.theme = _dialog_theme()
	_ask_title.add_theme_font_size_override("font_size", _title_font_size())
	_ask_action = action_name
	_ask_numeric = bool(action.get("integer", false))
	_ask_title.text = str(action["title"])
	_ask_label.text = str(action["label"])
	_ask_edit.text = ""
	var is_ask2 := PhiActions.kind_of(action_name) == "ask2"
	_ask_label2.visible = is_ask2
	_ask_edit2.visible = is_ask2
	if is_ask2:
		_ask_label2.text = str(action.get("label2", ""))
		_ask_edit2.text = ""
	_ask_dialog.popup_centered(Vector2i(320, 170) if is_ask2 else Vector2i(320, 120))
	_ask_edit.grab_focus()


func _on_ask_submitted(_text: String) -> void:
	# 2欄ダイアログでは、1欄目の Enter は2欄目へ移るだけにする。
	if PhiActions.kind_of(_ask_action) == "ask2":
		_ask_edit2.grab_focus()
		return
	_ask_dialog.hide()
	_on_ask_confirmed()


func _on_ask2_submitted(_text: String) -> void:
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
	if PhiActions.kind_of(_ask_action) == "ask2":
		var answer2 := _ask_edit2.text.strip_edges()
		if answer2.is_empty():
			return
		var tab2 := _active_tab()
		if tab2 != null:
			tab2.send_text(PhiActions.build_ask2_text(_ask_action, answer, answer2))
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


# -- 第40段: 更新チェック ---------------------------------------------------

func _start_auto_update_check() -> void:
	## 起動時の自動チェック。配布版 (エディタでない実行) でのみ行う。
	## テストやプローブ (エディタ実行) ではネットワークに出ない。
	if OS.has_feature("editor"):
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 3.0
	timer.timeout.connect(func() -> void: _check_update(false))
	add_child(timer)
	timer.start()


func _check_update(manual: bool) -> void:
	## GitHub の最新リリースを確認する。新しいものがあれば窓を出す。
	## 手動 (メニュー) の時は、最新だった/失敗したこともログで知らせる。
	if _update_busy:
		return
	if _update_http == null:
		_update_http = HTTPRequest.new()
		_update_http.timeout = 15.0
		_update_http.request_completed.connect(_on_update_response)
		add_child(_update_http)
	_update_busy = true
	_update_manual = manual
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: NeoPHI/" + PhiVersion.VERSION,
	])
	var err := _update_http.request(PhiUpdate.API_URL, headers)
	if err != OK:
		_update_busy = false
		if manual:
			_log_active("system", "更新を確認できませんでした")
		else:
			_schedule_update_retry()


func _schedule_update_retry() -> void:
	## 自動チェックが失敗した時 (起動直後の回線不調など) に、
	## 30 秒後にもう一度だけ確認する (第102段、0.5.0)。
	if _update_retried:
		return
	_update_retried = true
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 30.0
	timer.timeout.connect(func() -> void: _check_update(false))
	add_child(timer)
	timer.start()


func _on_update_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_update_busy = false
	var manual := _update_manual
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if manual:
			_log_active("system", "更新を確認できませんでした")
		else:
			_schedule_update_retry()
		return
	var info := PhiUpdate.parse_latest(body.get_string_from_utf8())
	if info.is_empty():
		if manual:
			_log_active("system", "更新を確認できませんでした")
		else:
			_schedule_update_retry()
		return
	_update_retried = false
	if PhiUpdate.is_newer(str(info["tag"]), PhiVersion.VERSION):
		_update_info = info
		_show_update_dialog()
	elif manual:
		_log_active("system", "NeoPHI " + PhiVersion.VERSION + " は最新です")


func _show_update_dialog() -> void:
	## 更新のお知らせ窓。About と同じ作り (通常 Window + 枠プレート +
	## 題名帯ドラッグ)。「ダウンロードページを開く」で GitHub の
	## リリースページをブラウザで開く。
	if _update_dialog == null:
		_update_dialog = Window.new()
		_update_dialog.visible = false
		_update_dialog.theme = _dialog_theme()
		_update_dialog.transparent = true
		_update_dialog.title = ""
		_update_dialog.transient = true
		_update_dialog.min_size = Vector2i(440, 240)
		_update_dialog.close_requested.connect(func() -> void: _update_dialog.hide())
		var frame := UiStyle.window_frame()
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		_update_dialog.add_child(frame)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		frame.add_child(box)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		box.add_child(UiStyle.title_band(head))
		head.add_child(_dlg_title_label("更新のお知らせ"))
		var head_spacer := Control.new()
		head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(head_spacer)
		var head_close := Button.new()
		head_close.text = "×"
		head_close.focus_mode = Control.FOCUS_NONE
		head_close.pressed.connect(func() -> void: _update_dialog.hide())
		head.add_child(head_close)
		PhiWindowDrag.attach(head, _update_dialog)
		_update_label = Label.new()
		_update_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_update_label.custom_minimum_size = Vector2(400, 0)
		box.add_child(_update_label)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 8)
		buttons.alignment = BoxContainer.ALIGNMENT_END
		box.add_child(buttons)
		var open_button := Button.new()
		open_button.text = "GitHub のリリースページを開く"
		open_button.focus_mode = Control.FOCUS_NONE
		open_button.pressed.connect(_on_update_open_page)
		buttons.add_child(open_button)
		var close_button := Button.new()
		close_button.text = "閉じる"
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.pressed.connect(func() -> void: _update_dialog.hide())
		buttons.add_child(close_button)
		add_child(_update_dialog)
	var tag := str(_update_info.get("tag", ""))
	var rel_name := str(_update_info.get("name", ""))
	var shown := tag
	if not rel_name.is_empty() and rel_name != tag:
		shown = tag + " (" + rel_name + ")"
	_update_label.text = "新しいバージョン " + shown + " が公開されています。\n現在のバージョンは " + PhiVersion.VERSION + " です。\nGitHub のリリースページから新しい NeoPHI を入手してください。"
	var frame_min := (_update_dialog.get_child(0) as Control).get_combined_minimum_size()
	var need := Vector2i(frame_min) + Vector2i(30, 24)
	var root_size := get_window().size
	need.x = mini(need.x, maxi(root_size.x - 16, 340))
	need.y = mini(need.y, maxi(root_size.y - 16, 240))
	_update_dialog.min_size = need
	if _update_dialog.visible:
		_update_dialog.grab_focus()
	else:
		_update_dialog.popup_centered(need)


func _on_update_open_page() -> void:
	OS.shell_open(PhiUpdate.page_url(_update_info))
	_update_dialog.hide()


func _show_about() -> void:
	## バージョン情報。AcceptDialog だと Mac 実機で開かない事象が
	## あったため、開く実績のある通常の Window(priv 窓や取得
	## パネルと同じ作り)で出す(2026-11-16 の報告を受けて変更)。
	## 生成に失敗した残骸が残っていたら作り直す。
	if _about_dialog != null and not _about_dialog.is_inside_tree():
		_about_dialog.queue_free()
		_about_dialog = null
		_about_opened = false
	if _about_dialog == null:
		_about_dialog = Window.new()
		_about_dialog.visible = false
		_about_dialog.theme = _dialog_theme()
		_about_dialog.transparent = true
		_about_dialog.title = ""
		_about_dialog.transient = true
		_about_dialog.min_size = Vector2i(400, 220)
		_about_dialog.close_requested.connect(func() -> void: _about_dialog.hide())
		# 中身は枠プレートで包む(題名や×が枠の中に収まるように)。
		var about_frame := UiStyle.window_frame()
		about_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		_about_dialog.add_child(about_frame)
		var about_box := VBoxContainer.new()
		about_box.add_theme_constant_override("separation", 8)
		about_frame.add_child(about_box)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		about_box.add_child(UiStyle.title_band(head))
		head.add_child(_dlg_title_label("バージョン情報"))
		var head_spacer := Control.new()
		head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(head_spacer)
		var head_close := Button.new()
		head_close.text = "×"
		head_close.focus_mode = Control.FOCUS_NONE
		head_close.pressed.connect(func() -> void: _about_dialog.hide())
		head.add_child(head_close)
		# 題名行を掴んで動かせるようにする。
		PhiWindowDrag.attach(head, _about_dialog)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		about_box.add_child(row)
		var icon := _about_icon_texture()
		if icon != null:
			var icon_view := TextureRect.new()
			icon_view.texture = icon
			icon_view.custom_minimum_size = Vector2(96, 96)
			icon_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon_view)
		var label := Label.new()
		label.text = PhiVersion.about_text()
		row.add_child(label)
		# 閉じる手段は右上の × だけにする(ユーザーの指定)。
		# 以前あった下部の「閉じる」ボタンは、Mac で帯ぶん中身が
		# 押し下げられて隠れてしまったため廃止した。
		add_child(_about_dialog)
	# 大きさは中身に合わせ、開くたびに中央へ置く。固定値
	# (440x260)だと、文字の大きい環境で右と下が切れてしまう
	# (ユーザーの報告)。初回だけ popup_centered にすると、
	# 起動直後の窓サイズ復元と重なった時に変な大きさ・位置で
	# 固定されてしまうことがあるため、毎回計算して示す。
	var frame_min := (_about_dialog.get_child(0) as Control).get_combined_minimum_size()
	var need := Vector2i(frame_min) + Vector2i(30, 24)
	if need.x < 200 or need.y < 120:
		need = Vector2i(440, 260)
	var root_size := get_window().size
	need.x = mini(need.x, maxi(root_size.x - 16, 320))
	need.y = mini(need.y, maxi(root_size.y - 16, 240))
	_about_dialog.min_size = need
	_about_dialog.size = need
	_about_dialog.position = Vector2i(
		maxi(0, (root_size.x - need.x) / 2),
		maxi(0, (root_size.y - need.y) / 2))
	_about_dialog.show()
	_about_opened = true


func _about_icon_texture() -> Texture2D:
	## About ダイアログに出すアイコン。アプリアイコン→ロゴの順に
	## 探し、無ければアイコン無しで済ませる(防御的読み込み)。
	for path in ["res://assets/icon.png", "res://assets/logo.png"]:
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				return tex
	return null


func _hook_macos_about_menu() -> void:
	## macOS のアプリケーションメニュー(画面左上の NeoPHI メニュー)の
	## 「About NeoPHI」は、Godot の既定では押しても何も起きない。
	## バージョン情報ダイアログを開くよう、項目のコールバックを
	## 差し替える。macOS 以外、または項目が見つからなければ何もしない
	## (Hide / Quit など他の項目には触らない)。
	if not OS.has_feature("macos"):
		return
	if not NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU):
		return
	if not NativeMenu.has_system_menu(NativeMenu.APPLICATION_MENU_ID):
		return
	var menu := NativeMenu.get_system_menu(NativeMenu.APPLICATION_MENU_ID)
	for i in NativeMenu.get_item_count(menu):
		var item_text := NativeMenu.get_item_text(menu, i)
		# 項目名は OS の言語で変わる(英語 "About NeoPHI" /
		# 日本語 "NeoPHIについて")ので、両方に照合する。
		if item_text.begins_with("About") or item_text.contains("について"):
			NativeMenu.set_item_callback(menu, i, Callable(self, "_on_macos_about_item"))
			return


func _on_macos_about_item(_tag: Variant) -> void:
	_show_about()


# -- 第2段: 大声 ------------------------------------------------------------

func _show_loud_dialog() -> void:
	if _loud_dialog == null:
		_loud_dialog = ConfirmationDialog.new()
		_loud_dialog.theme = _dialog_theme()
		_loud_dialog.transparent = true
		_loud_dialog.title = ""
		_loud_dialog.ok_button_text = "はい"
		_loud_dialog.cancel_button_text = "いいえ"
		var loud_box := VBoxContainer.new()
		loud_box.add_theme_constant_override("separation", 4)
		_loud_dialog.add_child(loud_box)
		loud_box.add_child(_dlg_title("大声で発言"))
		var label := Label.new()
		label.text = "大声で発言します。\nこの世界にいる全員に聞こえます。\nよろしいですか？"
		# 折り返しを on にすると高さの計算が膨らんで画面いっぱいに
		# なってしまうので、改行だけの固定文にして幅を明示する。
		label.custom_minimum_size = Vector2(400, 0)
		loud_box.add_child(label)
		_loud_dialog.add_button("すべて大声", false, "all")
		_loud_dialog.confirmed.connect(_on_loud_yes)
		_loud_dialog.canceled.connect(_on_loud_no)
		_loud_dialog.custom_action.connect(_on_loud_custom_action)
		_draggable_title(loud_box, _loud_dialog)
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
	# 中身が全部見える高さで開く(説明文がスクロールの下に隠れて
	# 「全部出ていない」ように見えるのを防ぐ)。内側の箱の必要
	# 高さ+ダイアログの枠(帯+ボタン+余白 ≒ 108)で決める。
	# 初回はレイアウト前で測れないので 720 を仮の値にする。
	# ウィンドウに収まらない時だけスクロールに任せる。
	var inner_h := 720.0
	if _shortcut_inner_box != null and _shortcut_inner_box.size.x >= 500.0:
		inner_h = _shortcut_inner_box.get_combined_minimum_size().y
	var win := get_window().size
	var w := clampi(620, 320, maxi(win.x - 16, 320))
	var h := clampi(int(inner_h) + 108, 480, maxi(win.y - 16, 320))
	_shortcut_dialog.popup_centered(Vector2i(w, h))


func _build_shortcut_dialog() -> void:
	_shortcut_dialog = ConfirmationDialog.new()
	_shortcut_dialog.theme = _dialog_theme()
	_shortcut_dialog.transparent = true
	_shortcut_dialog.title = ""
	_shortcut_dialog.ok_button_text = "保存"
	_shortcut_dialog.cancel_button_text = "やめる"
	_shortcut_dialog.confirmed.connect(_on_shortcut_dialog_confirmed)
	var shortcut_box := VBoxContainer.new()
	shortcut_box.add_theme_constant_override("separation", 4)
	_shortcut_dialog.add_child(shortcut_box)
	shortcut_box.add_child(_dlg_title("ショートカット設定"))
	# 題名の帯を掴んで動かせるようにする (他のダイアログと同じ
	# 方式。帯は PanelContainer で、外側の VBox に付けると
	# クリックが帯に飲まれて届かない)。
	_draggable_title(shortcut_box, _shortcut_dialog)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shortcut_box.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	_shortcut_inner_box = box
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
	var magic_note := Label.new()
	magic_note.text = "F1〜F7を押すと、その番号の魔法を唱えます(入力欄にフォーカスがある間は効きません)。通常は番号で送ります。「魔法名で送る」を有効にすると、上の魔法名で送ります。魔法メニューの各魔法にも Alt+W などのキーが割り当てられています(メニューに表示されます。こちらはフォーカスに関わらず効きます)。"
	magic_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	magic_note.modulate = Color(0.75, 0.75, 0.75)
	box.add_child(magic_note)
	var free_title := Label.new()
	free_title.text = "F8〜F12 の自由ショートカット(\\n で改行)"
	box.add_child(free_title)
	var free_note := Label.new()
	free_note.text = "押すと、入力した文字列をそのまま送ります。リスト表示中に押した場合は「リスト」の文字列を送ります。"
	free_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	free_note.modulate = Color(0.75, 0.75, 0.75)
	box.add_child(free_note)
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
	_priv_window.title_font = _bold_font
	_priv_window.title_size = _title_font_size()
	_priv_window.transparent = true
	_priv_window.set_tag_tree(_tag_tree)
	_priv_window.send_requested.connect(_send_priv)
	_priv_window.refresh_requested.connect(_on_priv_refresh_pressed)
	add_child(_priv_window)
	_priv_window.apply_font_size(maxi(_applied_font_size, 15))


func _show_priv_window() -> void:
	if _priv_window == null:
		_build_priv_window()
	_priv_window.title_size = _title_font_size()
	_refresh_priv_window_for_active_tab()
	_priv_window.show_window()
	# 開いたら宛先の一覧を取り直す (リスト更新ボタンと同じ
	# #ulist)。最初に開いた時、宛先が空のままにならないように。
	var tab := _active_tab()
	if tab != null and tab.is_session_open():
		tab.send_line("#ulist")


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
	## 手入力の ID は入力欄が空から始まる。登録済みキャラクターを
	## 選んだ時だけ、`.phirc` の ID が入力欄に入る。手入力で接続に
	## 成功したキャラは、サーバから届いた名前で一覧へ登録する
	## (第134段)。
	_connect_target = target
	if _connect_dialog == null:
		_connect_dialog = ConfirmationDialog.new()
		_connect_dialog.theme = _dialog_theme()
		_connect_dialog.transparent = true
		_connect_dialog.title = ""
		_connect_dialog.ok_button_text = "接続"
		_connect_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		_connect_dialog.add_child(box)
		box.add_child(_dlg_title("接続"))
		var chara_row := HBoxContainer.new()
		chara_row.add_theme_constant_override("separation", 6)
		box.add_child(chara_row)
		var chara_label := Label.new()
		chara_label.text = "登録済み"
		chara_label.custom_minimum_size = Vector2(64, 0)
		chara_row.add_child(chara_label)
		_connect_chara_select = OptionButton.new()
		_connect_chara_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_connect_chara_select.item_selected.connect(_on_connect_chara_selected)
		chara_row.add_child(_connect_chara_select)
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
		_draggable_title(box, _connect_dialog)
		add_child(_connect_dialog)
	_connect_characters = _registered_characters()
	_connect_chara_select.clear()
	_connect_chara_select.add_item("（手入力）")
	for entry in _connect_characters:
		_connect_chara_select.add_item(str(entry["display_name"]))
	_connect_chara_select.select(0)
	if target != null and not target.host.is_empty():
		_connect_host_edit.text = target.host
		_connect_port_edit.text = str(target.port)
	else:
		_connect_host_edit.text = _config.host
		_connect_port_edit.text = str(_config.port)
	_connect_id_edit.text = ""
	if target != null and not target.host.is_empty():
		# 登録済みキャラと一致するタブは、その ID を入れておき、
		# そのまま接続できるようにする (手入力した ID は従来
		# どおり入れない)。
		var target_name := target.player_name()
		if target_name.is_empty():
			target_name = target.restored_name
		var resolved := _resolve_registered_id(target.host, target.port, target_name)
		if resolved.is_empty() and not target.session.char_id.is_empty():
			# 手入力でつないだタブは登録ファイルから引けないので、
			# タブセッションに残っている ID をそのまま入れる。
			resolved = target.session.char_id
		if not resolved.is_empty():
			_connect_id_edit.text = resolved
	_connect_dialog.popup_centered(Vector2i(380, 230))
	_connect_id_edit.grab_focus()


func _on_connect_chara_selected(idx: int) -> void:
	## 登録済みキャラクターを選んだら、接続先と ID を入力欄に入れる。
	if idx <= 0 or idx - 1 >= _connect_characters.size():
		return
	var entry: Dictionary = _connect_characters[idx - 1]
	_connect_host_edit.text = str(entry["host"])
	_connect_port_edit.text = str(entry["port"])
	_connect_id_edit.text = str(entry["id"])


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
		# 行き先のタブが決まっていない接続は、同じキャラのタブが
		# あれば使い回す (Philly と同じ)。表示名は登録済みキャラと
		# 一致すればそれを使う。
		var display_name := ""
		for entry in _connect_characters:
			if str(entry["host"]) == host and int(entry["port"]) == port and str(entry["id"]) == char_id:
				display_name = str(entry["display_name"])
				break
		_connect_character(host, port, char_id, display_name)
		return
	_activate_tab(tab)
	_connect_tab(tab, host, port, char_id)
	# 登録済みキャラと一致すれば、ログインまでのタブの題名に
	# 表示名を付ける (キャラメニューからの接続と同じ)。
	for entry in _connect_characters:
		if str(entry["host"]) == host and int(entry["port"]) == port and str(entry["id"]) == char_id:
			tab.set_restored_name(str(entry["display_name"]))
			break
	_save_tab_session()


# -- 第7段: 新規キャラクター作成ダイアログ --------------------------------------
## PhillyNewCharacter の移植。世界は resist.ini の一覧から選び、
## 名前とメールを入れて「作成」で専用タブが作成セッションを始める。
## パスワードは自動生成で、ユーザーは入力しない。

const REGISTER_HELP_NAME := "ゲーム内のキャラクターの名前です。\n使える文字は半角英数のみ、文字数は2～31文字です。\nPHIでは他の人の名前と重複することがあります。\n重複を必要以上に恐れる必要はありません。\n他のプレイヤーの名前には、英語、造語、ローマ字など様々な物があります。\n名前は一度作成したら変更することはできません。"
const REGISTER_HELP_MAIL := "メールアドレスの入力は必要ありません。\n入力しておくと、キャラクターのIDを紛失してしまった場合の本人確認に有効です。\nメールアドレスは一般のプレイヤーには公開されません。\nメールアドレスは後から変更することも可能です。"
const REGISTER_HELP_ADDRESS := "世界のIPアドレス、ポート番号を入力します。\n入力形式は「IPアドレス:ポート番号」です。"


func _build_register_dialog() -> void:
	_register_dialog = ConfirmationDialog.new()
	_register_dialog.theme = _register_dialog_theme()
	_register_dialog.transparent = true
	_register_dialog.title = ""
	_register_dialog.ok_button_text = "作成"
	_register_dialog.cancel_button_text = "キャンセル"
	# 土台の金属テクスチャは中身の枠に貼る。ウィンドウの地(panel)に
	# テクスチャを貼る方式は Mac で地が描かれなかったため。
	var frame := PanelContainer.new()
	var tex := UiStyle.dialog_texture(REGISTER_DIALOG_SIZE)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 18
		sb.texture_margin_top = 18
		sb.texture_margin_right = 18
		sb.texture_margin_bottom = 18
		sb.content_margin_left = 16
		sb.content_margin_top = 12
		sb.content_margin_right = 16
		sb.content_margin_bottom = 12
		frame.add_theme_stylebox_override("panel", sb)
	_register_dialog.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	frame.add_child(box)
	var register_title := _dlg_title("PHIキャラクターの新規作成", true)
	box.add_child(register_title)
	# 題名の帯そのものを掴んで動かせるようにする。枠(PanelContainer)
	# に付けると帯がクリックを飲んで届かない(ショートカット設定と
	# 同じ落とし穴)。
	PhiWindowDrag.attach(register_title, _register_dialog)
	var world_row := HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 6)
	box.add_child(world_row)
	var world_label := Label.new()
	world_label.text = "世界"
	world_label.custom_minimum_size = Vector2(64, 0)
	world_row.add_child(world_label)
	_register_world_select = OptionButton.new()
	_register_world_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_register_world_select.item_selected.connect(_on_register_world_selected)
	world_row.add_child(_register_world_select)
	var address_row := HBoxContainer.new()
	address_row.add_theme_constant_override("separation", 6)
	box.add_child(address_row)
	var address_label := Label.new()
	address_label.text = "アドレス"
	address_label.custom_minimum_size = Vector2(64, 0)
	address_row.add_child(address_label)
	_register_address_edit = LineEdit.new()
	_register_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_register_address_edit.focus_entered.connect(_on_register_address_focus)
	address_row.add_child(_register_address_edit)
	_register_url_button = Button.new()
	_register_url_button.text = "ホームページを開く"
	_register_url_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_register_url_button.focus_mode = Control.FOCUS_NONE
	_register_url_button.pressed.connect(_on_register_url_pressed)
	box.add_child(_register_url_button)
	_register_comment = Label.new()
	_register_comment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 最小幅も与える(幅1pxで折り返す前提の高さ計算で膨らまないように)。
	_register_comment.custom_minimum_size = Vector2(400, 84)
	_register_comment.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(_register_comment)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "名前"
	name_label.custom_minimum_size = Vector2(64, 0)
	name_row.add_child(name_label)
	_register_name_edit = LineEdit.new()
	_register_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_register_name_edit.focus_entered.connect(_on_register_name_focus)
	name_row.add_child(_register_name_edit)
	var mail_row := HBoxContainer.new()
	mail_row.add_theme_constant_override("separation", 6)
	box.add_child(mail_row)
	var mail_label := Label.new()
	mail_label.text = "メール"
	mail_label.custom_minimum_size = Vector2(64, 0)
	mail_row.add_child(mail_label)
	_register_mail_edit = LineEdit.new()
	_register_mail_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_register_mail_edit.focus_entered.connect(_on_register_mail_focus)
	mail_row.add_child(_register_mail_edit)
	_register_help = Label.new()
	_register_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_register_help.custom_minimum_size = Vector2(400, 110)
	_register_help.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_register_help.modulate = Color(0.78, 0.78, 0.78)
	box.add_child(_register_help)
	var note := Label.new()
	note.text = "パスワードは自動で生成され、発行される ID に含まれます。"
	box.add_child(note)
	_register_dialog.confirmed.connect(_on_register_confirmed)
	add_child(_register_dialog)


func _show_register_dialog() -> void:
	## 世界の一覧(resist.ini)を読み直してから開く。
	if _register_dialog == null:
		_build_register_dialog()
	_register_worlds = PhiResist.load_worlds(_assets.philly_roots)
	_register_world_select.clear()
	for world in _register_worlds:
		_register_world_select.add_item(str(world["name"]))
	_register_world_select.select(0)
	_register_name_edit.text = ""
	_register_mail_edit.text = "@"
	_on_register_world_selected(0)
	_on_register_name_focus()
	_register_dialog.popup_centered(REGISTER_DIALOG_SIZE)
	_register_name_edit.grab_focus()


func _on_register_world_selected(idx: int) -> void:
	## 世界を選んだら、アドレス欄と説明と URL をその世界に合わせる。
	## アドレス欄が編集できるのはアドレス指定の世界だけ。
	if idx < 0 or idx >= _register_worlds.size():
		return
	var world: Dictionary = _register_worlds[idx]
	_register_address_edit.text = "%s:%d" % [str(world["address"]), int(world["port"])]
	_register_address_edit.editable = bool(world["address_input"])
	_register_comment.text = str(world["comment"])
	_register_url = str(world["url"])
	_register_url_button.disabled = not (_register_url.begins_with("http://") or _register_url.begins_with("https://"))


func _on_register_url_pressed() -> void:
	if _register_url.begins_with("http://") or _register_url.begins_with("https://"):
		OS.shell_open(_register_url)


func _on_register_name_focus() -> void:
	_register_help.text = REGISTER_HELP_NAME


func _on_register_mail_focus() -> void:
	_register_help.text = REGISTER_HELP_MAIL


func _on_register_address_focus() -> void:
	_register_help.text = REGISTER_HELP_ADDRESS


func _on_register_confirmed() -> void:
	## 検証(PhillyNewCharacter の CheckName / CheckMail / SplitIpPort /
	## MakeDisplayName)を通ったら、専用タブで作成セッションを始める。
	## 検証に落ちたら理由をログに出してダイアログを開き直す。
	var char_name := _register_name_edit.text
	var name_error := PhiCharacters.check_name(char_name)
	if not name_error.is_empty():
		_log_active("error", name_error.replace("\n", " "))
		_register_dialog.popup_centered(REGISTER_DIALOG_SIZE)
		return
	var mail_result := PhiCharacters.check_mail(_register_mail_edit.text)
	if not bool(mail_result["ok"]):
		_log_active("error", str(mail_result["error"]).replace("\n", " "))
		_register_dialog.popup_centered(REGISTER_DIALOG_SIZE)
		return
	var mail := str(mail_result["mail"])
	_register_mail_edit.text = mail
	var world: Dictionary = _register_worlds[_register_world_select.selected]
	var host := ""
	var port := PhiCharacters.DEFAULT_PORT
	if bool(world["address_input"]):
		var split := PhiCharacters.split_ip_port(_register_address_edit.text.strip_edges())
		if not bool(split["ok"]):
			_log_active("error", str(split["error"]))
			_register_dialog.popup_centered(REGISTER_DIALOG_SIZE)
			return
		host = str(split["ip"])
		port = int(split["port"])
	else:
		host = str(world["address"])
		port = int(world["port"])
	var root := PhiCharacters.chara_root(_assets.philly_roots)
	var made := PhiCharacters.make_display_name(char_name, PhiCharacters.scan_root(root), root)
	if not bool(made["ok"]):
		_log_active("error", str(made["error"]))
		_register_dialog.popup_centered(REGISTER_DIALOG_SIZE)
		return
	var password := PhiCharacters.make_password()
	# 未使用の空タブがあればそれで作成する (第67段)。
	var tab := _take_pristine_tab()
	if tab == null:
		tab = _create_tab()
	_activate_tab(tab)
	tab.connect_register(host, port, char_name, password, mail, str(made["display_name"]), root)
	_save_tab_session()


# -- 第4段: 全タブ発言 --------------------------------------------------------

func _show_sayall_dialog() -> void:
	if _sayall_dialog == null:
		_sayall_dialog = ConfirmationDialog.new()
		_sayall_dialog.theme = _dialog_theme()
		_sayall_dialog.transparent = true
		_sayall_dialog.title = ""
		_sayall_dialog.ok_button_text = "送信"
		_sayall_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		_sayall_dialog.add_child(box)
		box.add_child(_dlg_title("全タブ発言"))
		var label := Label.new()
		label.text = "すべてのタブに同じ発言を送ります。"
		box.add_child(label)
		_sayall_edit = LineEdit.new()
		box.add_child(_sayall_edit)
		_sayall_dialog.confirmed.connect(_on_sayall_confirmed)
		_sayall_edit.text_submitted.connect(_on_sayall_submitted)
		_draggable_title(box, _sayall_dialog)
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
		_talk_add_dialog.transparent = true
		_talk_add_dialog.title = ""
		_talk_add_dialog.ok_button_text = "設定"
		_talk_add_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		_talk_add_dialog.add_child(box)
		box.add_child(_dlg_title("追加発言"))
		var label := Label.new()
		label.text = "発言の前に追加する言葉を入力してください"
		box.add_child(label)
		_talk_add_edit = LineEdit.new()
		box.add_child(_talk_add_edit)
		_talk_add_dialog.confirmed.connect(_on_talk_add_confirmed)
		_talk_add_edit.text_submitted.connect(_on_talk_add_submitted)
		_draggable_title(box, _talk_add_dialog)
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


# -- マップサイズ設定 -----------------------------------------------------------
## 地図の倍率の決め方。窓に合わせる (収まる整数倍率に自動調整) か、
## 固定倍率 (窓が小さくても縮めない・大きくても広げない) かを選ぶ。
## 固定倍率は整数倍のみ (ドット絵が崩れないため)。

func _show_map_size_dialog() -> void:
	if _map_size_dialog == null:
		_map_size_dialog = ConfirmationDialog.new()
		_map_size_dialog.theme = _dialog_theme()
		_map_size_dialog.transparent = true
		_map_size_dialog.title = ""
		_map_size_dialog.ok_button_text = "設定"
		_map_size_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		_map_size_dialog.add_child(box)
		box.add_child(_dlg_title("マップサイズ設定"))
		var mode_label := Label.new()
		mode_label.text = "地図の大きさの決め方"
		box.add_child(mode_label)
		_map_size_mode = OptionButton.new()
		_map_size_mode.add_item("窓に合わせる", 0)
		_map_size_mode.add_item("固定倍率", 1)
		box.add_child(_map_size_mode)
		var spin_label := Label.new()
		spin_label.text = "固定倍率 (1〜8 の整数倍)"
		box.add_child(spin_label)
		_map_size_spin = SpinBox.new()
		_map_size_spin.min_value = 1
		_map_size_spin.max_value = 8
		_map_size_spin.step = 1
		box.add_child(_map_size_spin)
		_map_size_dialog.confirmed.connect(_on_map_size_confirmed)
		_draggable_title(box, _map_size_dialog)
		add_child(_map_size_dialog)
	_map_size_mode.selected = _config.map_zoom_mode
	_map_size_spin.value = _config.map_zoom_fixed
	_map_size_dialog.popup_centered(Vector2i(320, 190))


func _on_map_size_confirmed() -> void:
	_config.map_zoom_mode = _map_size_mode.selected
	_config.map_zoom_fixed = int(_map_size_spin.value)
	for t in _tabs:
		t.apply_map_zoom()
	_save_config()


# -- フォント・アイコンのサイズ設定 ----------------------------------------------
## メニュー・タブのフォントサイズ (窓・倍率に連動しない固定値) と、
## コマンドパレットのアイコンサイズを設定する。第128段で
## 移動キーの繰り返し間隔もここに足した。

func _show_display_size_dialog() -> void:
	if _display_size_dialog == null:
		_display_size_dialog = ConfirmationDialog.new()
		_display_size_dialog.theme = _dialog_theme()
		_display_size_dialog.transparent = true
		_display_size_dialog.title = ""
		_display_size_dialog.ok_button_text = "設定"
		_display_size_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		_display_size_dialog.add_child(box)
		box.add_child(_dlg_title("フォント・アイコンのサイズ"))
		var menu_label := Label.new()
		menu_label.text = "メニュー・タブのフォントサイズ (10〜48)"
		box.add_child(menu_label)
		_display_menu_spin = SpinBox.new()
		_display_menu_spin.min_value = 10
		_display_menu_spin.max_value = 48
		_display_menu_spin.step = 1
		box.add_child(_display_menu_spin)
		var icon_label := Label.new()
		icon_label.text = "コマンドパレットのアイコンサイズ (0 は元の大きさ、12〜64)"
		box.add_child(icon_label)
		_display_icon_spin = SpinBox.new()
		_display_icon_spin.min_value = 0
		_display_icon_spin.max_value = 64
		_display_icon_spin.step = 1
		box.add_child(_display_icon_spin)
		var repeat_label := Label.new()
		repeat_label.text = "移動キーの繰り返し間隔 (%d〜%dms、0 はサーバの応答ペース)" % [PhiConfig.MIN_MOVE_REPEAT_MS, PhiConfig.MAX_MOVE_REPEAT_MS]
		box.add_child(repeat_label)
		_display_repeat_spin = SpinBox.new()
		_display_repeat_spin.min_value = PhiConfig.MIN_MOVE_REPEAT_MS
		_display_repeat_spin.max_value = PhiConfig.MAX_MOVE_REPEAT_MS
		_display_repeat_spin.step = 1
		box.add_child(_display_repeat_spin)
		_display_size_dialog.confirmed.connect(_on_display_size_confirmed)
		_draggable_title(box, _display_size_dialog)
		add_child(_display_size_dialog)
	_display_menu_spin.value = _config.menu_font_size
	_display_icon_spin.value = _config.toolbar_icon_size
	_display_repeat_spin.value = _config.move_repeat_ms
	_display_size_dialog.popup_centered(Vector2i(360, 280))


func _on_display_size_confirmed() -> void:
	_config.menu_font_size = int(_display_menu_spin.value)
	_config.toolbar_icon_size = int(_display_icon_spin.value)
	_config.move_repeat_ms = int(_display_repeat_spin.value)
	_apply_chrome_size()
	for t in _tabs:
		t.refresh_ui_font_size()
		t.refresh_toolbar_icon_size()
	_save_config()


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
	_master_magic_button = button
	var popup := button.get_popup()
	_menu_popups.append(popup)
	_master_magic_items.clear()
	_master_magic_next_id = 0
	for menu in menus:
		_add_master_magic_menu(popup, menu)
	popup.id_pressed.connect(_on_master_magic_pressed)
	_update_master_magic_visibility()


## 超魔法メニューを出すかどうか (仕様書 §9.1 / WPHI と同じ判定)。
## アクティブなタブがあり、そのキャラがマスター (EXP 99999999)
## の時だけ出す。設定「超魔法メニューを常に出す」が on なら
## マスターでなくても出す。
func _update_master_magic_visibility() -> void:
	if _master_magic_button == null:
		return
	var show := false
	var tab := _active_tab()
	if tab != null:
		show = _config.master_magic_always \
			or tab.current_exp() == PhiMasterMagic.MASTER_EXP
	_master_magic_button.visible = show


func _on_tab_status_changed(tab: PhiCharacter) -> void:
	## EXP が変わったら (マスターになった等) 超魔法の出し分けを更新。
	if tab == _active_tab():
		_update_master_magic_visibility()


func _master_magic_icon_key(caption: String) -> String:
	## 超魔法のカテゴリ名からアイコンのキーを決める。
	if caption.contains("移動"):
		return "MMMove"
	if caption.contains("停止"):
		return "MMWorldStop"
	if caption.contains("創造"):
		return "MMCreate"
	if caption.contains("操作"):
		return "MMOperate"
	if caption.contains("通常"):
		return "MMNormal"
	return "MasterMagic"


func _add_master_magic_menu(parent: PopupMenu, menu: Dictionary) -> void:
	var sub := PopupMenu.new()
	sub.name = "mm_sub_%d" % _master_magic_next_id
	_master_magic_next_id += 1
	sub.id_pressed.connect(_on_master_magic_pressed)
	parent.add_child(sub)
	_menu_popups.append(sub)
	parent.add_submenu_item(str(menu.get("caption", "")), sub.name)
	var icon_key := _master_magic_icon_key(str(menu.get("caption", "")))
	_set_menu_item_icon(parent, parent.item_count - 1, icon_key)
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
		# 呪文の項目にもカテゴリのアイコンを付ける。
		_set_menu_item_icon(sub, sub.item_count - 1, icon_key)
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
				# list="no" の send (cast など) へサーバが返す
				# リストは、後続の send が詠唱で答えるので
				# 表示しない (魔法一覧に無いマスター魔法では
				# 選ぶ事もできず、窓が残ってしまう)。
				if str(step.get("list", "")) == "no":
					tab.suppress_next_list()
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
		_mm_confirm.transparent = true
		_mm_confirm.title = ""
		_mm_confirm.ok_button_text = "はい"
		_mm_confirm.cancel_button_text = "いいえ"
		var mm_box := VBoxContainer.new()
		mm_box.add_theme_constant_override("separation", 4)
		_mm_confirm.add_child(mm_box)
		mm_box.add_child(_dlg_title("超魔法"))
		_mm_label = Label.new()
		mm_box.add_child(_mm_label)
		_mm_confirm.confirmed.connect(_on_mm_confirmed)
		_mm_confirm.canceled.connect(_on_mm_canceled)
		_draggable_title(mm_box, _mm_confirm)
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
		_mm_text_dialog.transparent = true
		_mm_text_dialog.title = ""
		_mm_text_dialog.ok_button_text = "OK"
		_mm_text_dialog.cancel_button_text = "やめる"
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.add_child(_dlg_title("超魔法"))
		_mm_text_label = Label.new()
		box.add_child(_mm_text_label)
		_mm_text_edit = LineEdit.new()
		box.add_child(_mm_text_edit)
		_mm_text_dialog.add_child(box)
		_mm_text_dialog.confirmed.connect(_on_mm_text_confirmed)
		_mm_text_dialog.canceled.connect(_on_mm_text_canceled)
		_mm_text_edit.text_submitted.connect(_on_mm_text_submitted)
		_mm_text_edit.text_changed.connect(_on_mm_text_changed)
		_draggable_title(box, _mm_text_dialog)
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
	_image_window.transparent = true
	_image_window.title = ""
	_image_window.transient = true
	_image_window.min_size = Vector2i(480, 360)
	_image_window.visible = false
	_image_window.close_requested.connect(_on_image_window_close_requested)
	add_child(_image_window)
	# 中身は枠プレートで包む(題名や×が枠の中に収まるように)。
	var image_frame := UiStyle.window_frame()
	image_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image_window.add_child(image_frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	image_frame.add_child(box)
	var image_head := HBoxContainer.new()
	image_head.add_theme_constant_override("separation", 6)
	box.add_child(UiStyle.title_band(image_head))
	image_head.add_child(_dlg_title_label("画像一覧"))
	var image_spacer := Control.new()
	image_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_head.add_child(image_spacer)
	var image_close := Button.new()
	image_close.text = "×"
	image_close.focus_mode = Control.FOCUS_NONE
	image_close.pressed.connect(_on_image_window_close_requested)
	image_head.add_child(image_close)
	# 題名行を掴んで動かせるようにする。
	PhiWindowDrag.attach(image_head, _image_window)
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
	# 更新ボタンは横いっぱいに広げず、右寄せの自然な幅にする。
	var refresh_row := HBoxContainer.new()
	refresh_row.add_theme_constant_override("separation", 6)
	box.add_child(refresh_row)
	var refresh_spacer := Control.new()
	refresh_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_row.add_child(refresh_spacer)
	var refresh := Button.new()
	refresh.text = "更新"
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.pressed.connect(_refresh_image_window)
	refresh_row.add_child(refresh)


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
	return PhiImages.decode_image(data)


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
	var code := PhiKeys.code_name_for(key_event.keycode, key_event.physical_keycode, key_event.unicode)
	# 送受信トレースが有効なら、届いたキーも記録する (第85段、
	# 診断用)。IME の変換中に横取りしない判定より前に残す
	# (変換に紛れて届くキーも見えるように)。
	var ime_text := DisplayServer.ime_get_text()
	if tab.session != null and tab.session.wire_trace:
		tab.session.trace_text("KEY kc=%d phys=%d uni=%d code=%s shift=%s ctrl=%s alt=%s ime=%s" % [key_event.keycode, key_event.physical_keycode, key_event.unicode, code, str(key_event.shift_pressed), str(key_event.ctrl_pressed), str(key_event.alt_pressed), str(not ime_text.is_empty())])
	# IME の変換中は、キーをすべて入力欄 (IME) に任せる。変換確定の
	# Enter などをショートカットや送信と取り違えないため (第79段)。
	if not ime_text.is_empty():
		return
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
	# 強制切断のキー(WPHI と同じ割り当て)。Pause / Shift+F1 は
	# アクティブなタブを、Alt+Pause は全タブを強制切断する。
	# フォーカスに関わらず効く。ただし確定文字 (unicode) を持つ
	# イベントは文字入力であり、切断キーにはしない (第88段。
	# IME の確定が Pause 等の物理コードで届くことがあるため)。
	if code == "Pause" and not ctrl and not meta and key_event.unicode == 0:
		if alt:
			_disconnect_all_tabs(true)
		elif tab.is_session_open():
			tab.disconnect_force()
		get_viewport().set_input_as_handled()
		return
	if code == "F1" and shift and not ctrl and not alt and not meta and key_event.unicode == 0:
		if tab.is_session_open():
			tab.disconnect_force()
		get_viewport().set_input_as_handled()
		return
	# Alt / Shift+Alt の魔法キー(Philly KeyBindAlt / KeyBindShiftAlt)。
	# Alt+G と同じくフォーカスに関わらず効く。Alt+数字は Philly
	# 本来の所持魔法 1〜7 の詠唱 (マップサイズは Option+Shift+
	# 数字へ移したため、数字が空いた)。
	if alt and not ctrl and not meta:
		if not shift and code.begins_with("Digit"):
			var digit_no := int(code.trim_prefix("Digit"))
			if digit_no >= 1 and digit_no <= 7:
				tab.on_magic_key(digit_no)
				get_viewport().set_input_as_handled()
				return
		var alt_action := PhiActions.alt_action_for(code, shift)
		if not alt_action.is_empty():
			_dispatch_alt_action(tab, alt_action)
			get_viewport().set_input_as_handled()
			return
	if tab.handle_key(key_event):
		get_viewport().set_input_as_handled()


func _ensure_confirm_dialog() -> void:
	## Call / Return の確認ダイアログ (Alt 経由とメニュー経由で共用)。
	if _alt_confirm_dialog != null:
		return
	_alt_confirm_dialog = ConfirmationDialog.new()
	_alt_confirm_dialog.theme = _dialog_theme()
	_alt_confirm_dialog.transparent = true
	_alt_confirm_dialog.title = ""
	_alt_confirm_dialog.ok_button_text = "はい"
	_alt_confirm_dialog.cancel_button_text = "いいえ"
	var alt_box := VBoxContainer.new()
	alt_box.add_theme_constant_override("separation", 4)
	_alt_confirm_dialog.add_child(alt_box)
	alt_box.add_child(_dlg_title("確認"))
	_alt_confirm_label = Label.new()
	alt_box.add_child(_alt_confirm_label)
	_alt_confirm_dialog.confirmed.connect(_on_alt_confirm_ok)
	_alt_confirm_dialog.canceled.connect(_on_confirm_canceled)
	_draggable_title(alt_box, _alt_confirm_dialog)
	add_child(_alt_confirm_dialog)


func _needs_action_confirm(action_name: String) -> bool:
	## メニュー・ツールバー経由の Call / Return に確認が要るか。
	if _confirm_ok_pass:
		return false
	if action_name == "Call":
		return _config.dialog_for_call
	if action_name == "Return":
		return _config.dialog_for_return
	return false


func _show_action_confirm(tab: PhiCharacter, action_name: String) -> void:
	_pending_menu_action = action_name
	_pending_menu_tab = tab
	_ensure_confirm_dialog()
	_alt_confirm_label.text = str(PhiActions.ALT_CONFIRMS.get(action_name, ""))
	_alt_confirm_dialog.popup_centered()


func _on_confirm_canceled() -> void:
	_pending_menu_action = ""
	_pending_menu_tab = null
	_pending_alt_action = ""


func _dispatch_alt_action(tab: PhiCharacter, action_name: String) -> void:
	## Alt 系の魔法キーの実行。Call / Return は確認ダイアログを挟み、
	## それ以外は次のリストを抑えてからメニューと同じ経路で実行する。
	if PhiActions.ALT_CONFIRMS.has(action_name):
		_pending_alt_action = action_name
		_ensure_confirm_dialog()
		_alt_confirm_label.text = str(PhiActions.ALT_CONFIRMS[action_name])
		_alt_confirm_dialog.popup_centered()
		return
	_run_alt_action(tab, action_name)


func _run_alt_action(tab: PhiCharacter, action_name: String) -> void:
	tab.set_suppress_lists(1)
	tab.mark_list_answered()
	_confirm_ok_pass = true
	_do_action(action_name)
	_confirm_ok_pass = false


func _on_alt_confirm_ok() -> void:
	# メニュー・ツールバー経由の確認待ちがあればそちらを送る
	# (リスト抑えは付けない。Alt 経由とは実行経路が違う)。
	if not _pending_menu_action.is_empty():
		var mtab := _pending_menu_tab
		var maction := _pending_menu_action
		_pending_menu_action = ""
		_pending_menu_tab = null
		if mtab != null:
			mtab.do_send_action(maction)
			_remember_map_mode(maction, mtab)
		return
	var tab := _active_tab()
	if tab != null and not _pending_alt_action.is_empty():
		_run_alt_action(tab, _pending_alt_action)
	_pending_alt_action = ""


func _process(delta: float) -> void:
	# BGM ゲートの開閉に追随する (第74段)。重い処理の間は
	# 一時停止し、落ち着いたら再開する。
	var gate_tab := _active_tab()
	if gate_tab != null:
		var susp: bool = gate_tab.bgm_suspended()
		if gate_tab != _bgm_gate_tab or susp != _bgm_gate_suspended:
			_bgm_gate_tab = gate_tab
			_bgm_gate_suspended = susp
			_apply_tab_bgm(gate_tab)
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
	## フロート類(ツールバー・コンパス・リスト)と開いている
	## サブウィンドウは写さない(ユーザーの要望)。
	var tab := _active_tab()
	if tab != null:
		tab.set_map_overlays_visible(false)
	var hidden_windows: Array[Window] = []
	for child in get_children():
		if child is Window and (child as Window).visible:
			hidden_windows.append(child as Window)
			(child as Window).hide()
	await get_tree().process_frame
	await get_tree().process_frame
	var dir := "user://ScreenShot"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "_")
	var path := "%s/NeoPHI_%s.png" % [dir, stamp]
	var img := get_viewport().get_texture().get_image()
	if img == null:
		# 描画できない環境 (ヘッドレス等) では画像が取れない。
		if tab != null:
			tab.set_map_overlays_visible(true)
		for win in hidden_windows:
			win.show()
		_log_active("error", "マップ画像を取得できませんでした")
		return
	# 「マップ画像の保存」なので、アクティブタブの地図の範囲だけを
	# 切り取る(以前は窓全体を保存してしまっていた)。
	if tab != null and tab.map_view != null:
		var region := UiStyle.viewport_region(
			Vector2i(img.get_width(), img.get_height()),
			get_viewport().get_visible_rect().size,
			tab.map_view.get_global_rect()
		)
		if region.size.x > 0 and region.size.y > 0:
			img = img.get_region(region)
	var err := img.save_png(path)
	if tab != null:
		tab.set_map_overlays_visible(true)
	for win in hidden_windows:
		win.show()
	if err == OK:
		_log_active("system", "マップ画像を保存しました: " + path)
	else:
		_log_active("error", "マップ画像の保存に失敗しました: " + error_string(err))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_WM_ABOUT:
		# macOS のアプリメニュー「About NeoPHI」が押された時の通知。
		# 既定ではこの通知が来るだけで何も表示されないので、
		# バージョン情報ダイアログを開く。
		_show_about()
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
