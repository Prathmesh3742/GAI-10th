# life_summary.gd
# =============================================================================
# Life Summary screen — final screen of every life.
#
# Flow:
#   1. Populate static data from GameState immediately (never shows blank)
#   2. Show "Reflecting on your journey..." placeholder in narrative section
#   3. Await AIService.generate_life_summary() (up to 15 s + one retry)
#   4. Replace placeholder with AI text, or fallback prose if AI fails/offline
#   5. Animate entrance; "Begin a New Life" → character creation
# =============================================================================
extends Control

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var _content_card:     PanelContainer = %ContentCard
@onready var _age_range_label:  Label          = %AgeRangeLabel
@onready var _player_name_lbl:  Label          = %PlayerNameLabel
@onready var _career_label:     Label          = %CareerLabel
@onready var _stats_grid:       GridContainer  = %StatsGrid
@onready var _narrative_title:  Label          = %NarrativeTitle
@onready var _narrative_label:  Label          = %NarrativeLabel
@onready var _btn_play_again:   Button         = %BtnPlayAgain
@onready var _btn_home:         Button         = %BtnHome


func _ready() -> void:
	await get_tree().process_frame
	_apply_styles()
	_populate_static()
	_animate_entrance()
	_btn_play_again.pressed.connect(_on_play_again)
	_btn_home.pressed.connect(_on_home)
	# Fetch summary (may take up to ~30 s with retry; narrative shows placeholder until done)
	await _fetch_narrative()


# =============================================================================
# Static data — filled synchronously from GameState; never shows blank
# =============================================================================
func _populate_static() -> void:
	var start_age: int = 18
	var final_age: int = int(GameState.age)

	_age_range_label.text = "AGES %d – %d" % [start_age, final_age]
	_player_name_lbl.text = GameState.player_name
	_career_label.text    = "%s  ·  %s" % [GameState.career, GameState.career_level]
	_narrative_label.text = "Reflecting on your journey…"

	_build_stats_grid()


func _build_stats_grid() -> void:
	var rows: Array[Array] = [
		["💰  Money",       UIManager.format_money(GameState.money)],
		["❤  Health",       "%d / 100" % int(GameState.health)],
		["😊  Happiness",   "%d / 100" % int(GameState.happiness)],
		["⭐  Reputation",  "%d / 100" % int(GameState.reputation)],
		["😰  Stress",      "%d / 100" % int(GameState.stress)],
		["📍  Location",    GameState.location],
	]
	for row: Array in rows:
		var key_lbl := Label.new()
		key_lbl.text = row[0]
		key_lbl.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
		key_lbl.add_theme_font_size_override("font_size", 14)
		_stats_grid.add_child(key_lbl)

		var val_lbl := Label.new()
		val_lbl.text = row[1]
		val_lbl.add_theme_color_override("font_color", UIManager.C_TEXT)
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats_grid.add_child(val_lbl)


# =============================================================================
# AI narrative — replaces placeholder when summary arrives
# =============================================================================
func _fetch_narrative() -> void:
	var context: Dictionary = {
		"state": {
			"name"        : GameState.player_name,
			"age"         : GameState.age,
			"career"      : GameState.career,
			"career_level": GameState.career_level,
			"location"    : GameState.location,
			"money"       : GameState.money,
			"health"      : GameState.health,
			"happiness"   : GameState.happiness,
			"stress"      : GameState.stress,
			"reputation"  : GameState.reputation,
		},
		"major_events"  : GameState.major_life_events,
		"recent_choices": GameState.recent_choices,
	}

	var summary: String = await AIService.generate_life_summary(context)

	if summary.is_empty():
		summary = _fallback_narrative()

	# Update narrative title based on whether AI was used
	if AIService.is_available():
		_narrative_title.text = "AI Reflection on your life:"
	else:
		_narrative_title.text = "Reflection on your life:"

	# Fade in the new text
	_narrative_label.modulate.a = 0.0
	_narrative_label.text = summary
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_narrative_label, "modulate:a", 1.0, 0.6)


func _fallback_narrative() -> String:
	var years:  int    = int(GameState.age) - 18
	var career: String = GameState.career
	var money:  String = UIManager.format_money(GameState.money)

	var traits_list: Array = GameState.personality_traits.keys()
	var trait_str:   String = ", ".join(traits_list) if not traits_list.is_empty() else "resilient"

	return (
		"You lived %d remarkable years, carving out a life as a %s. "
		% [years, career]
		+ "Known for being %s, every choice you made — the bold leaps and the cautious steps alike "
		% trait_str
		+ "— wove together the unique tapestry of who you became. "
		+ "With %s to your name and a story worth telling, " % money
		+ "your journey through this world was entirely, beautifully your own."
	)


# =============================================================================
# Play Again
# =============================================================================
func _on_play_again() -> void:
	UIManager.change_scene("res://scenes/character_creation/character_creation.tscn")


func _on_home() -> void:
	UIManager.change_scene("res://scenes/main_menu/main_menu.tscn")


# =============================================================================
# Styling
# =============================================================================
func _apply_styles() -> void:
	var mc: VBoxContainer = (
		$ScrollContainer/CenterContainer/ContentCard/MarginContainer/MainContent
	)

	$Background.color = UIManager.C_BG

	_content_card.add_theme_stylebox_override("panel",
		UIManager.make_card_style(UIManager.C_CARD, 20, Color(1, 1, 1, 0.08), 1))

	# Header
	mc.get_node("Header/HeaderLabel").add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	mc.get_node("Header/HeaderLabel").add_theme_font_size_override("font_size", 11)

	_age_range_label.add_theme_color_override("font_color", UIManager.C_ACCENT)
	_age_range_label.add_theme_font_size_override("font_size", 13)

	# Player name — big and prominent
	_player_name_lbl.add_theme_color_override("font_color", UIManager.C_TEXT)
	_player_name_lbl.add_theme_font_size_override("font_size", 32)

	_career_label.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	_career_label.add_theme_font_size_override("font_size", 16)

	# Stats section title
	mc.get_node("StatsTitle").add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	mc.get_node("StatsTitle").add_theme_font_size_override("font_size", 12)

	# Narrative section
	_narrative_title.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	_narrative_title.add_theme_font_size_override("font_size", 12)

	_narrative_label.add_theme_color_override("font_color", UIManager.C_TEXT)
	_narrative_label.add_theme_font_size_override("font_size", 16)

	# Separators
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(1.0, 1.0, 1.0, 0.08)
	for sep_name: String in ["Sep1", "Sep2", "Sep3"]:
		mc.get_node(sep_name).add_theme_stylebox_override("separator", sep_style)

	# Button row — Home (secondary) + Play Again (primary)
	UIManager.style_button(
		_btn_home,
		UIManager.C_MUTED, UIManager.C_MUTED_H, UIManager.C_ACCENT_P,
		UIManager.C_TEXT, 12
	)
	_btn_home.add_theme_font_size_override("font_size", 15)

	UIManager.style_button(
		_btn_play_again,
		UIManager.C_ACCENT, UIManager.C_ACCENT_H, UIManager.C_ACCENT_P,
		UIManager.C_TEXT, 12
	)
	_btn_play_again.add_theme_font_size_override("font_size", 17)


# =============================================================================
# Entrance animation
# =============================================================================
func _animate_entrance() -> void:
	_content_card.pivot_offset = _content_card.size / 2.0
	_content_card.scale        = Vector2(0.96, 0.96)
	_content_card.modulate.a   = 0.0
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.set_parallel(true)
	tw.tween_property(_content_card, "modulate:a", 1.0, 0.4)
	tw.tween_property(_content_card, "scale",      Vector2(1.0, 1.0), 0.4)
