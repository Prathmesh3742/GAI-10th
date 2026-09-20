# event_result.gd
# =============================================================================
# PLACEHOLDER — Full implementation in Step 5.
# =============================================================================
extends Control

@onready var _btn_back: Button = %BtnBack


func _ready() -> void:
	_apply_styles()
	_btn_back.pressed.connect(func() -> void:
		UIManager.change_scene("res://scenes/main_menu/main_menu.tscn")
	)


func _apply_styles() -> void:
	$Background.color = UIManager.C_BG
	$CenterContainer/VBox/Title.add_theme_color_override("font_color", UIManager.C_TEXT)
	$CenterContainer/VBox/Title.add_theme_font_size_override("font_size", 28)
	$CenterContainer/VBox/Subtitle.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	UIManager.style_button(
		_btn_back,
		UIManager.C_MUTED, UIManager.C_MUTED_H, UIManager.C_MUTED_P
	)
