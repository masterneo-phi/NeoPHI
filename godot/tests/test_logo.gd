extends SceneTree
## タイトルロゴの埋め込み(地図欄の表示・起動絵・アイコン)のテスト。
##
## 使い方: godot --headless --path . -s tests/test_logo.gd
## 終了コード 0 = 全一致、1 = 不一致あり。

var _failures := 0
var _checks := 0


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _check_eq(a: Variant, b: Variant, label: String) -> void:
	_checks += 1
	if a != b:
		_failures += 1
		printerr("FAIL: ", label, " (got ", a, ", want ", b, ")")


func _test_logo() -> void:
	# プロジェクト設定: アイコンと起動絵がロゴを指している。
	_check_eq(ProjectSettings.get_setting("application/config/icon"), "res://assets/icon.png", "icon setting")
	_check_eq(ProjectSettings.get_setting("application/boot_splash/image"), "res://assets/logo.png", "splash setting")
	# ロゴとアイコンの絵が読めて、想定の大きさである。
	_check(ResourceLoader.exists("res://assets/logo.png"), "logo exists")
	_check(ResourceLoader.exists("res://assets/icon.png"), "icon exists")
	var logo := load("res://assets/logo.png") as Texture2D
	_check(logo != null, "logo loads")
	if logo != null:
		_check_eq(logo.get_size(), Vector2(1440, 960), "logo size")
	var icon := load("res://assets/icon.png") as Texture2D
	_check(icon != null, "icon loads")
	if icon != null:
		_check_eq(icon.get_size(), Vector2(512, 512), "icon size")
	# 地図が無い間はタイトルが出て、地図が届くと消える。
	var view := MapView.new()
	_check(view.title_texture() != null, "title texture")
	_check(view.get("_title_rect") != null, "title rect exists")
	_check((view.get("_title_rect") as TextureRect).visible, "title visible before map")
	view.set_map({"size": 7, "cells": [], "chars": []}, null, "")
	_check(not (view.get("_title_rect") as TextureRect).visible, "title hidden after map")
	view.free()


func _initialize() -> void:
	_test_logo()
	print("test_logo: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)
