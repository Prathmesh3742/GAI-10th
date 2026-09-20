# main_menu.gd
# =============================================================================
# Main menu screen — the first scene the player sees.
# Applies all visual styling programmatically via UIManager helpers.
# =============================================================================
extends Control

# ── Node references (unique-name access) ──────────────────────────────────────
@onready var _btn_new_life:    Button       = %BtnNewLife
@onready var _btn_continue:    Button       = %BtnContinue
@onready var _btn_how_to_play: Button       = %BtnHowToPlay
@onready var _btn_settings:    Button       = %BtnSettings
@onready var _btn_exit:        Button       = %BtnExit
@onready var _content_card:    PanelContainer = %ContentCard
@onready var _lbl_version:     Label        = %VersionLabel


func _ready() -> void:
	# Wait one frame so layout engine has computed ContentCard.size
	# (needed for correct pivot_offset in the entrance animation)
	await get_tree().process_frame

	_apply_styles()
	_connect_buttons()
	_check_continue_availability()
	_animate_entrance()


# =============================================================================
# Styling — all visual properties applied here; nothing hard-coded in the .tscn
# =============================================================================
func _apply_styles() -> void:
	# Background already set in .tscn; reinforce via UIManager palette
	$Background.color = UIManager.C_BG

	# Card panel
	var card_style: StyleBoxFlat = UIManager.make_card_style(
		UIManager.C_CARD, 20,
		Color(1, 1, 1, 0.08), 1
	)
	_content_card.add_theme_stylebox_override("panel", card_style)

	# Title
	%Title.add_theme_color_override("font_color", UIManager.C_TEXT)
	%Title.add_theme_font_size_override("font_size", 40)

	# Subtitle
	%Subtitle.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	%Subtitle.add_theme_font_size_override("font_size", 15)

	# Primary action button (New Life — accent colour)
	UIManager.style_button(
		_btn_new_life,
		UIManager.C_ACCENT, UIManager.C_ACCENT_H, UIManager.C_ACCENT_P,
		UIManager.C_TEXT, 12
	)
	_btn_new_life.add_theme_font_size_override("font_size", 17)

	# Secondary action buttons
	for btn: Button in [_btn_continue, _btn_how_to_play, _btn_settings]:
		UIManager.style_button(
			btn,
			UIManager.C_MUTED, UIManager.C_MUTED_H, UIManager.C_MUTED_P,
			UIManager.C_TEXT, 12
		)
		btn.add_theme_font_size_override("font_size", 17)

	# Danger button (Exit)
	UIManager.style_button(
		_btn_exit,
		UIManager.C_DANGER, UIManager.C_DANGER_H, UIManager.C_DANGER_P,
		UIManager.C_TEXT, 12
	)
	_btn_exit.add_theme_font_size_override("font_size", 17)

	# Version label
	_lbl_version.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	_lbl_version.add_theme_font_size_override("font_size", 12)


# =============================================================================
# Button signal connections
# =============================================================================
func _connect_buttons() -> void:
	_btn_new_life.pressed.connect(_on_new_life)
	_btn_continue.pressed.connect(_on_continue)
	_btn_how_to_play.pressed.connect(_on_how_to_play)
	_btn_settings.pressed.connect(_on_settings)
	_btn_exit.pressed.connect(_on_exit)


func _check_continue_availability() -> void:
	var has: bool = SaveManager.has_save()
	_btn_continue.disabled = not has
	# Visual dim when disabled (stylebox handles colour; dim modulate for extra clarity)
	if not has:
		_btn_continue.modulate.a = 0.45


# =============================================================================
# Entrance animation — pop-in scale + fade
# =============================================================================
func _animate_entrance() -> void:
	_content_card.pivot_offset = _content_card.size / 2.0
	_content_card.scale        = Vector2(0.93, 0.93)
	_content_card.modulate.a   = 0.0

	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.set_parallel(true)
	tw.tween_property(_content_card, "modulate:a", 1.0, 0.45)
	tw.tween_property(_content_card, "scale",      Vector2(1.0, 1.0), 0.45)


# =============================================================================
# Button handlers
# =============================================================================
func _on_new_life() -> void:
	# If a save exists, prompt before overwriting
	if SaveManager.has_save():
		_show_confirm_new_game()
	else:
		UIManager.change_scene("res://scenes/character_creation/character_creation.tscn")


func _on_continue() -> void:
	if SaveManager.load_game():
		UIManager.change_scene("res://scenes/game/game.tscn")
	else:
		_show_alert("Load Failed", "Could not load the save file. It may be corrupted.")


func _on_how_to_play() -> void:
	_show_alert(
		"How to Play",
		"AI LIFE SIMULATOR\n\n"
		+ "• You begin life at age 18 with a character you create.\n"
		+ "• Each turn, an AI generates a life event based on your current stats.\n"
		+ "• Choose from 2–4 options — each affects your stats and story.\n"
		+ "• Your personality traits evolve as you make choices.\n"
		+ "• The simulation runs until age 80, your health fails, or you end it.\n"
		+ "• At the end, an AI writes a unique summary of your life journey.\n\n"
		+ "Stats:  Money  |  Health  |  Happiness  |  Reputation\n"
		+ "        Energy  |  Stress  |  Career  |  Relationships\n\n"
		+ "Tip: Balance risk and stability — going all-in rarely ends well."
	)


func _on_settings() -> void:
	_show_alert(
		"Settings",
		"Settings panel coming in a future step.\n\n"
		+ "Current build: v0.1.0 — Milestone 1 (Steps 1–5)\n"
		+ "Engine: Godot 4  |  AI Provider: Groq (offline until Step 8)"
	)


func _on_exit() -> void:
	get_tree().quit()


# =============================================================================
# Dialog helpers
# =============================================================================
func _show_alert(title: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title       = title
	dialog.dialog_text = message
	dialog.min_size    = Vector2(520, 100)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)


func _show_confirm_new_game() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title       = "Start New Life?"
	dialog.dialog_text = (
		"You have an existing save.\n"
		+ "Starting a new life will overwrite it permanently.\n\n"
		+ "Are you sure?"
	)
	dialog.min_size = Vector2(400, 100)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		SaveManager.delete_save()
		UIManager.change_scene("res://scenes/character_creation/character_creation.tscn")
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
