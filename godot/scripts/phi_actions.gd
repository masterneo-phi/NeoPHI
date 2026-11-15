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
##   "reset-config" / "clear-cache" / "screenshot" / "scroll-toggle" /
##   "open-config-folder" / "about" … アプリ側の処理。
##   "priv-window" / "loud-toggle" / "shortcut-config" … 第2段の処理。
##
## 第1段の範囲外のもの(タブ、BGM、CastF/ショートカット、
## 超魔法、隠しコマンド)は入れていない。第2段でプリブ窓と大声と
## ショートカット設定を追加した。

const ACTIONS := {
	"Open": {"caption": "接続", "hint": "サーバーに接続する", "kind": "connect"},
	"Close": {"caption": "切断", "hint": "サーバーから切断する", "kind": "disconnect"},
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
	"Cast1": {"caption": "cast 1", "hint": "所持魔法1番の魔法を唱える", "kind": "send", "send": "cast\n1"},
	"Cast2": {"caption": "cast 2", "hint": "所持魔法2番の魔法を唱える", "kind": "send", "send": "cast\n2"},
	"Cast3": {"caption": "cast 3", "hint": "所持魔法3番の魔法を唱える", "kind": "send", "send": "cast\n3"},
	"Cast4": {"caption": "cast 4", "hint": "所持魔法4番の魔法を唱える", "kind": "send", "send": "cast\n4"},
	"Cast5": {"caption": "cast 5", "hint": "所持魔法5番の魔法を唱える", "kind": "send", "send": "cast\n5"},
	"Cast6": {"caption": "cast 6", "hint": "所持魔法6番の魔法を唱える", "kind": "send", "send": "cast\n6"},
	"Cast7": {"caption": "cast 7", "hint": "所持魔法7番の魔法を唱える", "kind": "send", "send": "cast\n7"},
	# 操作メニュー(第2段)
	"NewPrivWindow": {"caption": "新規プリブウィンドウ", "hint": "新しいプリブウィンドウを開く [Shift+F6]", "kind": "priv-window"},
	"Loud": {"caption": "大声", "hint": "世界中の全員に聞こえる大声で話す", "kind": "loud-toggle"},
	"ShortcutConfig": {"caption": "ショートカット設定", "hint": "F1〜F12 のショートカットを編集する", "kind": "shortcut-config"},
	"M5x5": {"caption": "5x5 マップモード", "hint": "5x5 マップモードにする [Shift+5]", "kind": "send", "send": "#ex-map size=40"},
	"M7x7": {"caption": "7x7 マップモード", "hint": "7x7 マップモードにする [Shift+7]", "kind": "send", "send": "#ex-map size=57"},
	"MTurn": {"caption": "回転マップモード", "hint": "回転マップモードにする [T]", "kind": "send", "send": "#ex-map style=turn"},
	"MSolid": {"caption": "北固定マップモード", "hint": "北固定マップモードにする [Shift+T]", "kind": "send", "send": "#ex-map style=solid"},
	"SSMap": {"caption": "マップ画像の保存", "hint": "マップ画面の写真を撮って保存する", "kind": "screenshot"},
	"LogScrollStop": {"caption": "ログスクロール停止", "hint": "ログを追加時のスクロールを止める", "kind": "scroll-toggle"},
	"OpenConfigFolder": {"caption": "設定フォルダを開く", "hint": "設定フォルダを開く", "kind": "open-config-folder"},
	"VersionInfo": {"caption": "バージョン情報", "hint": "バージョン情報を表示する", "kind": "about"},
}

## メニューバー。"-" は区切り線。
const MENUS := [
	{"name": "ファイル", "items": ["Open", "Close", "-", "ReadConfigFile", "InitializeConfig", "InitializeGraCache", "-", "Exit"]},
	{"name": "操作", "items": ["NewPrivWindow", "Loud"]},
	{"name": "行動", "items": ["Equip", "Unequip", "-", "Read", "Write", "Erase", "Board", "-", "Get", "Put", "Use", "Sort", "FloorItem", "-", "Spells", "Pay", "Hit", "Check", "Skills"]},
	{"name": "魔法", "items": ["WizardEye", "PartyEye", "EagleEye", "Identify", "Search", "WizardLock", "Unlock", "Detect", "Create", "Analyze", "Forget", "Call", "Return", "-", "WizardLight", "EagleEyeText", "List", "Destroy", "ChargeSpell", "Appear", "Disappear", "-", "Cast", "Cast1", "Cast2", "Cast3", "Cast4", "Cast5", "Cast6", "Cast7"]},
	{"name": "表示", "items": ["M5x5", "M7x7", "MTurn", "MSolid", "-", "SSMap", "LogScrollStop"]},
	{"name": "ツール", "items": ["ShortcutConfig", "OpenConfigFolder", "VersionInfo"]},
]

## ツールバーに並べるアクション。"-" は区切り。
const TOOLBAR := ["Open", "Close", "-", "Equip", "Unequip", "Read", "Write", "Erase", "Get", "Put", "Use", "-", "Spells", "Hit", "Check", "NewPrivWindow", "Loud", "-", "Cast", "M5x5", "M7x7", "MTurn", "MSolid", "-", "SSMap"]


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
		"disconnect", "send", "ask", "priv-window", "loud-toggle":
			return connected
		_:
			return true
