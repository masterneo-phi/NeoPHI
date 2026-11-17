class_name PhiActions
extends RefCounted
## Philly の `Command.cpp` の SetAction() 一覧にあたるアクション表。
## メニューとツールバーはこの表から作る。
##
## kind:
##   "send" … `send` の行(\n 区切り)をそのまま送る。
##   "ask" … 入力ダイアログで言葉を聞き、`template` の %s に入れて送る。
##     `integer` が true なら 0 以上の整数だけ受け付ける。
##   "connect" / "disconnect" / "exit" / "reload-config" /
##   "force-disconnect" / "connect-all" / "disconnect-all" /
##   "force-disconnect-all" … 接続まわり(WPHI のファイルメニュー式)。
##   "reset-config" / "clear-cache" / "screenshot" / "scroll-toggle" /
##   "open-config-folder" / "about" … アプリ側の処理。
##   "priv-window" / "loud-toggle" / "shortcut-config" … 第2段の処理。
##   "say-all-tabs" / "autosave-toggle" /
##   "delete-filter-toggle" / "image-window" … 第4段の処理。
##   "talk-add" / "log-save" … 残り項目(第6段)の処理。
##
## 第1段の範囲外のもの(タブ、CastF/ショートカット、
## 超魔法、隠しコマンド)は入れていない。第2段でプリブ窓と大声と
## ショートカット設定を追加した。第4段でタブとログまわりを追加した。
## 第5段で BGM のトグルを追加した。
## 超魔法メニューは XML から動的に作るので、この表には無い。

const ACTIONS := {
	"Open": {"caption": "接続", "hint": "サーバーに接続する", "kind": "connect"},
	"Close": {"caption": "切断", "hint": "サーバーから切断する", "kind": "disconnect"},
	"ForceClose": {"caption": "強制切断", "hint": "サーバーに終了を伝えずに切断する [Pause・Shift+F1]", "kind": "force-disconnect"},
	"OpenAll": {"caption": "全キャラを接続", "hint": "切断中のタブをすべて接続する", "kind": "connect-all"},
	"CloseAll": {"caption": "全キャラを切断", "hint": "すべてのタブを切断する", "kind": "disconnect-all"},
	"ForceCloseAll": {"caption": "全キャラを強制切断", "hint": "すべてのタブを強制切断する [Alt+Pause]", "kind": "force-disconnect-all"},
	"ReadConfigFile": {"caption": "設定ファイル読み込み", "hint": "設定ファイルを読み込む", "kind": "reload-config"},
	"InitializeConfig": {"caption": "初期設定に戻す", "hint": "初期設定に戻す", "kind": "reset-config"},
	"InitializeGraCache": {"caption": "グラキャッシュ初期化", "hint": "キャラグラ・マップチップの初期化", "kind": "clear-cache"},
	"Exit": {"caption": "終了", "hint": "NeoPHI を終了する", "kind": "exit"},
	"Equip": {"caption": "自動装備 [Q,/]", "hint": "自動的に最強装備する [Q,/]", "kind": "send", "send": "equip"},
	"Unequip": {"caption": "装備を外す [W]", "hint": "選択した装備を外す [W]", "kind": "send", "send": "unequip"},
	"Read": {"caption": "看板を読む [A]", "hint": "看板を読む [A]", "kind": "send", "send": "read"},
	"Write": {"caption": "看板を書く [S]", "hint": "看板を書く or 看板を立てる [S]", "kind": "send", "send": "write"},
	"Erase": {"caption": "看板を消す [D]", "hint": "看板を消す or 看板を抜く [D]", "kind": "send", "send": "erase"},
	"Board": {"caption": "看板に注意する [B]", "hint": "看板に注意する(ON/OFF) [B]", "kind": "send", "send": "board"},
	"Get": {"caption": "アイテムを拾う [Z,+]", "hint": "アイテムを拾う [Z、+]", "kind": "send", "send": "get"},
	"Put": {"caption": "アイテムを置く [X,-]", "hint": "アイテムを置く [X、-]", "kind": "send", "send": "put"},
	"Use": {"caption": "アイテムを使う [C,*]", "hint": "アイテムを使う [C、*]", "kind": "send", "send": "use"},
	"Sort": {"caption": "アイテム整理 [V]", "hint": "アイテム整理する [V]", "kind": "send", "send": "sort"},
	"FloorItem": {"caption": "アイテムに注意する [F]", "hint": "落ちているアイテムに注意する(ON/OFF) [F]", "kind": "send", "send": "floor item"},
	"Spells": {"caption": "魔法一覧 [R]", "hint": "所持魔法の一覧を見る [R]", "kind": "send", "send": "spells"},
	"Pay": {"caption": "お金を払う [P]", "hint": "お金を払う [P]", "kind": "ask", "template": "pay %s", "title": "支払い金額", "label": "支払う金額を入力してください", "integer": true},
	"Hit": {"caption": "攻撃する [Space]", "hint": "攻撃する [SPACE]", "kind": "send", "send": "hit"},
	"Talk": {"caption": "話しかける [H]", "hint": "近くの NPC に『hi』と話しかける [H]", "kind": "send", "send": "hi"},
	"Check": {"caption": "ステータスを見る [M,0]", "hint": "ステータスを見る [M、0]", "kind": "send", "send": "check\nlook"},
	"Skills": {"caption": "スキルを見る", "hint": "スキルを見る", "kind": "send", "send": "skills"},
	"WizardEye": {"caption": "Wizard eye", "hint": "世界にいる人を一覧する [Alt+W]", "kind": "send", "send": "cast\nwizard eye"},
	"PartyEye": {"caption": "Party eye", "hint": "パーティーメンバーを一覧する [Alt+P]", "kind": "send", "send": "cast\nparty eye"},
	"EagleEye": {"caption": "Eagle eye", "hint": "周囲の広い範囲のマップを見る [Alt+E]", "kind": "send", "send": "cast\neagle eye"},
	"Identify": {"caption": "Identify", "hint": "前のキャラをジロジロ見て調べる [Alt+I]", "kind": "send", "send": "cast\nidentify"},
	"Search": {"caption": "Search", "hint": "キーワードから看板を検索する [Alt+S]", "kind": "ask", "template": "cast\nsearch\n%s", "title": "看板検索", "label": "検索する言葉を入力してください"},
	"WizardLock": {"caption": "Wizard lock", "hint": "ドアや箱に鍵をかける [Alt+L]", "kind": "send", "send": "cast\nwizard lock\nsee"},
	"Unlock": {"caption": "Unlock", "hint": "自分でかけた鍵を開ける [Alt+U]", "kind": "send", "send": "cast\nunlock\nsee"},
	"Detect": {"caption": "Detect", "hint": "アイテムを鑑定する [Alt+D]", "kind": "send", "send": "cast\ndetect"},
	"Create": {"caption": "Create", "hint": "アイテムを創造する [Alt+C]", "kind": "send", "send": "cast\ncreate"},
	"Analyze": {"caption": "Analyze", "hint": "所持魔法を鑑定する [Alt+A]", "kind": "send", "send": "cast\nanalyze"},
	"Forget": {"caption": "Forget", "hint": "魔法を忘れる [Alt+F]", "kind": "send", "send": "cast\nforget"},
	"Call": {"caption": "Call", "hint": "現在地に魔力刻印を刻む [Alt+B]", "kind": "send", "send": "cast\ncall"},
	"Return": {"caption": "Return", "hint": "魔力刻印位置へ緊急脱出する [Alt+R]", "kind": "send", "send": "cast\nreturn"},
	"WizardLight": {"caption": "Wizard light", "hint": "世界にいる人のレベルを見る [Shift+Alt+W]", "kind": "send", "send": "cast\nwizard light"},
	"EagleEyeText": {"caption": "Eagle eye text", "hint": "周囲の広い範囲のマップを見る（テキスト版） [Shift+Alt+E]", "kind": "send", "send": "#ex-switch eagleeye=text\ncast\neagle eye\n#ex-switch eagleeye=form"},
	"List": {"caption": "List", "hint": "世界にいる人を一覧する [Shift+Alt+L]", "kind": "send", "send": "cast\nlist"},
	"Destroy": {"caption": "Destroy", "hint": "アイテムを破壊する [Shift+Alt+D]", "kind": "send", "send": "cast\ndestroy"},
	"ChargeSpell": {"caption": "Charge spell", "hint": "所持魔法を宝石に封印する [Shift+Alt+C]", "kind": "send", "send": "cast\ncharge spell"},
	"Appear": {"caption": "Appear", "hint": "召還する [Shift+Alt+A]", "kind": "ask", "template": "cast\nappear %s", "title": "召喚", "label": "召喚するNPCの名前を入力してください"},
	"Disappear": {"caption": "Disappear", "hint": "召還獣を還す [Shift+Alt+U]", "kind": "ask", "template": "cast\ndisappear %s", "title": "送喚", "label": "送喚するNPCの名前を入力してください"},
	"Cast": {"caption": "cast", "hint": "魔法を唱える [Enter]", "kind": "send", "send": "cast"},
	"Cast1": {"caption": "cast 1", "hint": "所持魔法1番の魔法を唱える [F1]", "kind": "send", "send": "cast\n1"},
	"Cast2": {"caption": "cast 2", "hint": "所持魔法2番の魔法を唱える [F2]", "kind": "send", "send": "cast\n2"},
	"Cast3": {"caption": "cast 3", "hint": "所持魔法3番の魔法を唱える [F3]", "kind": "send", "send": "cast\n3"},
	"Cast4": {"caption": "cast 4", "hint": "所持魔法4番の魔法を唱える [F4]", "kind": "send", "send": "cast\n4"},
	"Cast5": {"caption": "cast 5", "hint": "所持魔法5番の魔法を唱える [F5]", "kind": "send", "send": "cast\n5"},
	"Cast6": {"caption": "cast 6", "hint": "所持魔法6番の魔法を唱える [F6]", "kind": "send", "send": "cast\n6"},
	"Cast7": {"caption": "cast 7", "hint": "所持魔法7番の魔法を唱える [F7]", "kind": "send", "send": "cast\n7"},
	# 操作メニュー(第2段)
	"NewPrivWindow": {"caption": "新規プリブウィンドウ", "hint": "新しいプリブウィンドウを開く [Shift+F6]", "kind": "priv-window"},
	"Loud": {"caption": "大声", "hint": "世界中の全員に聞こえる大声で話す", "kind": "loud-toggle"},
	"TalkAdd": {"caption": "追加発言", "hint": "発言の前に追加する言葉を設定する", "kind": "talk-add"},
	"ShortcutConfig": {"caption": "ショートカット設定", "hint": "F1〜F12 のショートカットを編集する", "kind": "shortcut-config"},
	"UnewPanel": {"caption": "キャラグラとマップチップを取得する", "hint": "サーバーからキャラグラ・マップチップ・BGMなどのデータを取得する", "kind": "unew-panel"},
	"SoundTest": {"caption": "サウンドテスト", "hint": "効果音とBGMを一覧から試しに鳴らす", "kind": "sound-test"},
	"ChipViewer": {"caption": "マップチップ確認", "hint": "マップチップのシートを番号と対応文字つきで見る", "kind": "chip-viewer"},
	"CharaViewer": {"caption": "キャラグラ確認", "hint": "キャラグラのシートと歩行アニメーションを見る", "kind": "chara-viewer"},
	# タブとログまわり(第4段)。「新しいタブ」「タブを閉じる」は
	# タブの×・新規接続・キャラデータ読み込みで代替できるため、
	# 2026-11-16 のユーザーの指示で仕様から削除した。
	"SayAllTabs": {"caption": "全タブ発言", "hint": "すべてのタブに同じ発言を送る", "kind": "say-all-tabs"},
	"LogAutoSave": {"caption": "ログの自動保存", "hint": "ログを自動でファイルに保存し続ける", "kind": "autosave-toggle"},
	"LogSave": {"caption": "ログを保存", "hint": "今表示しているログをファイルに保存する", "kind": "log-save"},
	"LogSaveDir": {"caption": "ログの保存先...", "hint": "ログを保存するフォルダを指定する", "kind": "log-save-dir"},
	"LogDeleteFilter": {"caption": "削除フィルタ", "hint": "設定した正規表現に合う行をログに表示しない", "kind": "delete-filter-toggle"},
	"ImageWindow": {"caption": "画像一覧", "hint": "ログ中の画像参照の一覧を開く(選ぶと取得して表示)", "kind": "image-window"},
	"M5x5": {"caption": "5x5 マップモード", "hint": "表示する地図を5x5マスにする [Shift+5]", "kind": "send", "send": "#ex-map size=40"},
	"M7x7": {"caption": "7x7 マップモード", "hint": "表示する地図を7x7マスにする [Shift+7]", "kind": "send", "send": "#ex-map size=57"},
	"M9x9": {"caption": "9x9 マップモード", "hint": "表示する地図を9x9マスにする [Shift+9]", "kind": "send", "send": "#ex-map size=81"},
	"MTurn": {"caption": "回転マップモード", "hint": "自分の向きに合わせて地図を回転させる [T]", "kind": "send", "send": "#ex-map style=turn"},
	"MSolid": {"caption": "北固定マップモード", "hint": "北を上に固定して地図を表示する [Shift+T]", "kind": "send", "send": "#ex-map style=solid"},
	"SSMap": {"caption": "マップ画像の保存", "hint": "地図だけの画像を ScreenShot フォルダに保存する", "kind": "screenshot"},
	"LogScrollStop": {"caption": "ログスクロール停止", "hint": "新しい行が来てもログを自動でスクロールしない", "kind": "scroll-toggle"},
	"SmoothScroll": {"caption": "スムーズマップスクロール", "hint": "移動時に地図をドット単位で滑らかにスクロールする(北固定の時だけ)", "kind": "smooth-scroll-toggle"},
	"DispMagic": {"caption": "魔法表示", "hint": "魔法の軌跡や着弾を地図に表示する(サーバーからの表示情報)", "kind": "disp-magic-toggle"},
	"UiStyleFloat": {"caption": "新スタイル (フロート表示)", "hint": "ログと入力欄を地図の上に浮かせて表示する新スタイル。外すと従来の配置 (旧スタイル) になる", "kind": "ui-style-toggle"},
	"MapAlignCenter": {"caption": "マップ配置: 中央", "hint": "地図を画面の中央に表示する (新スタイル)", "kind": "map-align", "align": 0},
	"MapAlignLeft": {"caption": "マップ配置: 左寄せ", "hint": "地図を画面の左に寄せて表示する (新スタイル)", "kind": "map-align", "align": 1},
	"MapAlignRight": {"caption": "マップ配置: 右寄せ", "hint": "地図を画面の右に寄せて表示する (新スタイル)", "kind": "map-align", "align": 2},
	"LogImage": {"caption": "ログに画像を表示", "hint": "ログ中の画像タグを画像そのもので表示する", "kind": "image-toggle"},
	"PlayBGM": {"caption": "BGM を再生する", "hint": "サーバーから指定されたBGM(MIDI)を再生する", "kind": "bgm-toggle"},
	"PlaySE": {"caption": "効果音を再生する", "hint": "ログに合わせて効果音 (SoundRegexp.ini / SoundFile.ini) を再生する", "kind": "se-toggle"},
	"MasterMagicAlways": {"caption": "超魔法メニューを常に出す", "hint": "マスター (EXP 99999999) でなくても超魔法メニューを表示する", "kind": "master-magic-toggle"},
	"OpenConfigFolder": {"caption": "設定フォルダを開く", "hint": "設定フォルダを開く", "kind": "open-config-folder"},
	"CheckUpdate": {"caption": "更新を確認", "hint": "GitHub の最新リリースを確認する", "kind": "update-check"},
	"VersionInfo": {"caption": "NeoPHI " + PhiVersion.VERSION, "hint": "バージョン情報を表示する", "kind": "about"},
}

## メニューバー。"-" は区切り線。
const MENUS := [
	{"name": "ファイル", "items": ["Open", "Close", "ForceClose", "OpenAll", "CloseAll", "ForceCloseAll", "-", "ReadConfigFile", "InitializeConfig", "InitializeGraCache", "-", "Exit"]},
	{"name": "操作", "items": ["NewPrivWindow", "Loud", "TalkAdd", "SayAllTabs"]},
	{"name": "行動", "items": ["Equip", "Unequip", "-", "Talk", "Read", "Write", "Erase", "Board", "-", "Get", "Put", "Use", "Sort", "FloorItem", "-", "Spells", "Pay", "Hit", "Check", "Skills"]},
	{"name": "魔法", "items": ["WizardEye", "PartyEye", "EagleEye", "Identify", "Search", "WizardLock", "Unlock", "Detect", "Create", "Analyze", "Forget", "Call", "Return", "-", "WizardLight", "EagleEyeText", "List", "Destroy", "ChargeSpell", "Appear", "Disappear", "-", "Cast", "Cast1", "Cast2", "Cast3", "Cast4", "Cast5", "Cast6", "Cast7"]},
	{"name": "表示", "items": ["M9x9", "M7x7", "M5x5", "MSolid", "MTurn", "MapAlignCenter", "MapAlignLeft", "MapAlignRight", "-", "UiStyleFloat", "-", "SSMap", "LogScrollStop", "SmoothScroll", "DispMagic", "LogImage", "PlayBGM", "PlaySE", "MasterMagicAlways", "-", "LogAutoSave", "LogSave", "LogSaveDir", "LogDeleteFilter", "ImageWindow"]},
	{"name": "ツール", "items": ["UnewPanel", "SoundTest", "ChipViewer", "CharaViewer", "ShortcutConfig", "OpenConfigFolder", "CheckUpdate", "VersionInfo"]},
]

## ツールバーに並べるアクション。"-" は区切り。
const TOOLBAR := ["Open", "Close", "-", "Equip", "Unequip", "Read", "Write", "Erase", "Get", "Put", "Use", "-", "Spells", "Hit", "Check", "NewPrivWindow", "Loud", "-", "Cast", "M9x9", "M7x7", "M5x5", "MSolid", "MTurn", "-", "SSMap", "-", "PlayBGM", "LogAutoSave"]


## メニュー項目の右端に表示するショートカット（アクセラレータ）。
## 実際のキー処理は従来どおり各所の _input にあり、これは表示と
## メニューを開いている間の発動用。修飾は KEY_MASK_* との OR で表す。
const ACCELERATORS := {
	"Cast1": KEY_F1, "Cast2": KEY_F2, "Cast3": KEY_F3, "Cast4": KEY_F4,
	"Cast5": KEY_F5, "Cast6": KEY_F6, "Cast7": KEY_F7,
	"M5x5": KEY_5 | KEY_MASK_SHIFT, "M7x7": KEY_7 | KEY_MASK_SHIFT,
	"M9x9": KEY_9 | KEY_MASK_SHIFT,
	"MTurn": KEY_T, "MSolid": KEY_T | KEY_MASK_SHIFT,
	"Talk": KEY_H,
	"NewPrivWindow": KEY_F6 | KEY_MASK_SHIFT,
	"ForceClose": KEY_F1 | KEY_MASK_SHIFT,
	"ForceCloseAll": KEY_PAUSE | KEY_MASK_ALT,
	"WizardEye": KEY_W | KEY_MASK_ALT, "PartyEye": KEY_P | KEY_MASK_ALT,
	"EagleEye": KEY_E | KEY_MASK_ALT, "Identify": KEY_I | KEY_MASK_ALT,
	"Search": KEY_S | KEY_MASK_ALT, "WizardLock": KEY_L | KEY_MASK_ALT,
	"Unlock": KEY_U | KEY_MASK_ALT, "Detect": KEY_D | KEY_MASK_ALT,
	"Create": KEY_C | KEY_MASK_ALT, "Analyze": KEY_A | KEY_MASK_ALT,
	"Forget": KEY_F | KEY_MASK_ALT, "Call": KEY_B | KEY_MASK_ALT,
	"Return": KEY_R | KEY_MASK_ALT,
	"WizardLight": KEY_W | KEY_MASK_ALT | KEY_MASK_SHIFT,
	"EagleEyeText": KEY_E | KEY_MASK_ALT | KEY_MASK_SHIFT,
	"List": KEY_L | KEY_MASK_ALT | KEY_MASK_SHIFT,
	"Destroy": KEY_D | KEY_MASK_ALT | KEY_MASK_SHIFT,
	"ChargeSpell": KEY_C | KEY_MASK_ALT | KEY_MASK_SHIFT,
	"Appear": KEY_A | KEY_MASK_ALT | KEY_MASK_SHIFT,
	"Disappear": KEY_U | KEY_MASK_ALT | KEY_MASK_SHIFT,
}


static func accelerator_for(action_name: String) -> int:
	return int(ACCELERATORS.get(action_name, 0))


## Alt キーの魔法ショートカット(Philly KeyBindAlt)。キーは PhiKeys の
## コード名("KeyW" など)。Alt+数字(所持魔法 1〜7)は呼び出し側で扱う。
const ALT_ACTIONS := {
	"KeyA": "Analyze", "KeyB": "Call", "KeyC": "Create", "KeyD": "Detect",
	"KeyE": "EagleEye", "KeyF": "Forget", "KeyI": "Identify",
	"KeyL": "WizardLock", "KeyP": "PartyEye", "KeyR": "Return",
	"KeyS": "Search", "KeyU": "Unlock", "KeyW": "WizardEye",
}
## Shift+Alt キーの魔法ショートカット(Philly KeyBindShiftAlt)。
const SHIFT_ALT_ACTIONS := {
	"KeyA": "Appear", "KeyC": "ChargeSpell", "KeyD": "Destroy",
	"KeyE": "EagleEyeText", "KeyL": "List", "KeyU": "Disappear",
	"KeyW": "WizardLight",
}

## Alt キー経由のときだけ確認ダイアログを出すアクションと、その文言
## (Philly KeyBindAlt の確認文)。
const ALT_CONFIRMS := {
	"Call": "現在の位置を call します。\nReturn や死んでしまって再接続するときはこの位置になります。\nよろしいですか？",
	"Return": "call 位置に帰還します。\n持っているアイテムを失う可能性があります。\nよろしいですか？",
}

## 系統魔法のアクション (Philly の AutoUnequipSystemMagic の対象、
## Python 版 keys.py の _magic)。値は装備し直す候補かどうか:
## true = reequip (唱えた後に外した武器を装備し直す候補)、
## false = keep (外したまま)。装備し直すかは設定 (AutoEquip) で決まる。
const SYSTEM_MAGIC := {
	"Analyze": false, "Create": false, "Detect": false,
	"Forget": false, "Destroy": false, "ChargeSpell": false,
	"Call": true, "EagleEye": true, "EagleEyeText": true,
	"Identify": true, "List": true, "PartyEye": true,
	"Return": true, "Unlock": true, "WizardEye": true,
	"WizardLight": true, "WizardLock": true,
}


static func is_system_magic(action_name: String) -> bool:
	return SYSTEM_MAGIC.has(action_name)


static func system_magic_reequip(action_name: String) -> bool:
	return bool(SYSTEM_MAGIC.get(action_name, false))


static func alt_action_for(code: String, shift: bool) -> String:
	if shift:
		return str(SHIFT_ALT_ACTIONS.get(code, ""))
	return str(ALT_ACTIONS.get(code, ""))


static func get_action(action_name: String) -> Dictionary:
	var found: Variant = ACTIONS.get(action_name)
	if found == null:
		return {}
	return found


static func kind_of(action_name: String) -> String:
	return str(get_action(action_name).get("kind", ""))


static func send_text_for(action_name: String) -> String:
	## "send" アクションが送る行。違えば ""。
	if kind_of(action_name) != "send":
		return ""
	return str(get_action(action_name).get("send", ""))


static func is_fixed_spell_text(text: String) -> bool:
	## 固定魔法の送信文か。`cast` の行の次に、詠唱 (コマンドでも
	## `#` 行でもない行) が続いていれば、サーバが出す魔法選択
	## リストはその詠唱で答え済みになる。`cast` 単体 (自分で
	## リストから選ぶ) は対象にしない。
	var lines := text.split("\n")
	for i in range(lines.size() - 1):
		if lines[i].strip_edges() == "cast":
			var chant := lines[i + 1].strip_edges()
			if not chant.is_empty() and not chant.begins_with("#"):
				return true
	return false


static func build_ask_text(action_name: String, answer: String) -> String:
	## "ask" アクションの入力を入れた送信文。違えば ""。
	if kind_of(action_name) != "ask":
		return ""
	return str(get_action(action_name).get("template", "")).replace("%s", answer)


static func enabled_when(action_name: String, connected: bool) -> bool:
	## 接続状態に対する有効・無効(Philly のカテゴリに相当)。
	## 接続は切断時のみ、切断と送信系は接続時のみ、その他は常に有効。
	match kind_of(action_name):
		"connect":
			return not connected
		"disconnect", "force-disconnect", "send", "ask", "priv-window", "loud-toggle", "say-all-tabs":
			return connected
		_:
			return true
