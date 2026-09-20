# game.gd
# =============================================================================
# Main gameplay screen — Steps 3/4/7.
#
# Layout: 2-column (sidebar | event panel)
#   Left  — 300 px stat sidebar: title, age, 4 primary stats + bars, info footer
#   Right — expanding event card: category, title, description, choice buttons
#
# Step 7+: Events come from EventManager (fallback pool, 62 events, no-repeat).
# Step 8+: AIService provides AI-generated events when online.
# =============================================================================
extends Control

# ── Sidebar stats config ──────────────────────────────────────────────────────
# has_bar: whether to draw a ProgressBar (money has no cap, so no bar)
const SIDEBAR_STATS: Array[Dictionary] = [
	{"key": "money",      "icon": "💰", "label": "Money",      "has_bar": false, "max": 0.0   },
	{"key": "health",     "icon": "❤",  "label": "Health",     "has_bar": true,  "max": 100.0 },
	{"key": "happiness",  "icon": "😊", "label": "Happiness",  "has_bar": true,  "max": 100.0 },
	{"key": "reputation", "icon": "⭐", "label": "Reputation", "has_bar": true,  "max": 100.0 },
]

# ── Dynamic node references (built in code) ───────────────────────────────────
var _stat_value_labels: Dictionary = {}   # stat_key -> Label
var _stat_bars:         Dictionary = {}   # stat_key -> ProgressBar
var _bar_fill_styles:   Dictionary = {}   # stat_key -> StyleBoxFlat (reused for color update)
var _choice_buttons:    Array[Button]  = []
var _career_lbl:        Label
var _level_lbl:         Label
var _relationship_lbl:  Label
var _stress_lbl:        Label

# ── Unique node refs ──────────────────────────────────────────────────────────
@onready var _age_value:         Label         = %AgeValue
@onready var _stats_container:   VBoxContainer = %StatsContainer
@onready var _info_container:    VBoxContainer = %InfoContainer
@onready var _traits_label:      Label         = %TraitsLabel
@onready var _event_cat_badge:   Label         = %EventCategoryBadge
@onready var _ai_status_badge:   Label         = %AIStatusBadge
@onready var _event_title:       Label         = %EventTitle
@onready var _event_desc:        Label         = %EventDesc
@onready var _choices_container: VBoxContainer = %ChoicesContainer
@onready var _loading_overlay:   ColorRect     = %LoadingOverlay
@onready var _btn_menu:          Button        = %BtnMenu


func _ready() -> void:
	await get_tree().process_frame
	_apply_styles()
	_build_stat_rows()
	_build_info_labels()
	_connect_signals()
	_refresh_stats()
	# Always show overlay while first event loads (hides in _on_event_ready)
	_loading_overlay.show()
	await GameManager.request_next_event()


# =============================================================================
# Signal wiring
# =============================================================================
func _connect_signals() -> void:
	GameState.state_changed.connect(_on_state_changed)
	GameManager.choice_applied.connect(_on_choice_applied)
	GameManager.event_ready.connect(_on_event_ready)
	AIService.ai_status_changed.connect(_on_ai_status_changed)
	_btn_menu.pressed.connect(_on_menu_pressed)
	# Initialise the badge with current status
	_on_ai_status_changed(AIService.is_available())


func _on_state_changed() -> void:
	_refresh_stats()


func _on_choice_applied(choice: Dictionary, effects: Dictionary) -> void:
	# Store result so event_result.gd can read it, then transition
	GameManager.last_choice_result = {
		"choice_text" : choice.get("text", ""),
		"effects"     : effects,
		"time_months" : choice.get("time_months", 6)
	}
	UIManager.change_scene("res://scenes/event_result/event_result.tscn")



func _on_event_ready(event_data: Dictionary) -> void:
	_loading_overlay.hide()
	_set_choices_enabled(true)
	_load_event(event_data)


func _on_ai_status_changed(is_online: bool) -> void:
	_ai_status_badge.text = "🟢 AI Online" if is_online else "🔴 Offline Mode"
	_ai_status_badge.add_theme_color_override(
		"font_color",
		UIManager.C_SUCCESS if is_online else UIManager.C_SUBTEXT
	)


# =============================================================================
# Event loading — populates the event card from a validated event Dictionary
# Called by _ready() (Step 4: hardcoded) and _on_event_ready() (Step 9: AI/fallback)
# =============================================================================
func _load_event(event_data: Dictionary) -> void:
	var cat: String = event_data.get("event_type", "event").to_upper()
	_event_cat_badge.text = "▸ " + cat
	_event_title.text = event_data.get("title", "")
	_event_desc.text  = event_data.get("description", "")
	_populate_choices(event_data.get("choices", []))


func _populate_choices(choices: Array) -> void:
	# Clear existing
	for btn: Button in _choice_buttons:
		btn.queue_free()
	_choice_buttons.clear()

	for i: int in range(choices.size()):
		var choice: Dictionary = choices[i]
		var btn := Button.new()
		btn.text                  = "  " + choice.get("text", "Choice %d" % (i + 1))
		btn.custom_minimum_size   = Vector2(0, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
		_choices_container.add_child(btn)
		_choice_buttons.append(btn)
		UIManager.style_button(
			btn,
			UIManager.C_MUTED, UIManager.C_MUTED_H, UIManager.C_ACCENT_P,
			UIManager.C_TEXT, 10
		)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_choice_pressed.bind(i))


func _on_choice_pressed(index: int) -> void:
	_set_choices_enabled(false)    # prevent double-click
	GameManager.apply_choice(index)


func _set_choices_enabled(enabled: bool) -> void:
	for btn: Button in _choice_buttons:
		btn.disabled = not enabled


# =============================================================================
# Menu button — save + return to main menu
# =============================================================================
func _on_menu_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Game Menu"
	dialog.dialog_text = (
		"%s  •  AGE %d\n\nSave and return to the main menu?"
		% [GameState.player_name, int(GameState.age)]
	)
	dialog.get_ok_button().text = "Save & Exit to Menu"
	dialog.add_button("End My Life  →", true, &"end_life")
	dialog.min_size = Vector2(400, 120)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		SaveManager.save_game()
		UIManager.change_scene("res://scenes/main_menu/main_menu.tscn")
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"end_life":
			dialog.hide()
			GameManager.navigate_to_summary()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)


# =============================================================================
# _refresh_stats() — called on GameState.state_changed
# Updates every live display element from GameState values.
# =============================================================================
func _refresh_stats() -> void:
	# Age
	var years:  int = int(GameState.age)
	var months: int = int((GameState.age - years) * 12.0)
	_age_value.text = "AGE  %d" % years if months == 0 else "AGE  %d yr %d mo" % [years, months]

	# Primary stat labels + bars
	for stat: Dictionary in SIDEBAR_STATS:
		var key: String = stat["key"]
		if key not in _stat_value_labels:
			continue
		var value: float = float(GameState.get(key))
		if stat["has_bar"]:
			_stat_value_labels[key].text = str(int(value))
			_stat_bars[key].value        = value
			_bar_fill_styles[key].bg_color = _bar_color(key, value)
		else:
			# Money — use shared formatter from UIManager
			_stat_value_labels[key].text = UIManager.format_money(value)

	# Info footer
	_career_lbl.text       = "Career      %s" % GameState.career
	_level_lbl.text        = "Level         %s" % GameState.career_level
	_relationship_lbl.text = "Status       %s" % GameState.relationship_status
	_stress_lbl.text       = "Stress        %d / 100" % int(GameState.stress)

	# Traits row
	var trait_keys: Array = GameState.personality_traits.keys()
	_traits_label.text = "  ·  ".join(trait_keys) if not trait_keys.is_empty() else "—"


# =============================================================================
# Dynamic sidebar builders
# =============================================================================

func _build_stat_rows() -> void:
	for stat: Dictionary in SIDEBAR_STATS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_stats_container.add_child(row)

		# Icon + name label
		var name_lbl := Label.new()
		name_lbl.text = "%s %s" % [stat["icon"], stat["label"]]
		name_lbl.custom_minimum_size = Vector2(90, 0)
		name_lbl.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
		name_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(name_lbl)

		if stat["has_bar"]:
			var bar := ProgressBar.new()
			bar.min_value             = 0.0
			bar.max_value             = stat["max"]
			bar.value                 = 70.0
			bar.show_percentage       = false
			bar.custom_minimum_size   = Vector2(0, 8)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical   = Control.SIZE_SHRINK_CENTER

			# Background style
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(0.137, 0.157, 0.220, 1.0)
			bg.set_corner_radius_all(4)
			bar.add_theme_stylebox_override("background", bg)

			# Fill style — stored so we can change only the color in _refresh_stats()
			var fill := StyleBoxFlat.new()
			fill.set_corner_radius_all(4)
			fill.bg_color = UIManager.C_ACCENT
			bar.add_theme_stylebox_override("fill", fill)

			_stat_bars[stat["key"]]       = bar
			_bar_fill_styles[stat["key"]] = fill
			row.add_child(bar)

		# Value label
		var val_lbl := Label.new()
		val_lbl.custom_minimum_size     = Vector2(36 if stat["has_bar"] else 0, 0)
		val_lbl.size_flags_horizontal   = Control.SIZE_SHRINK_END if stat["has_bar"] else Control.SIZE_EXPAND_FILL
		val_lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_color_override("font_color", UIManager.C_TEXT)
		val_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(val_lbl)
		_stat_value_labels[stat["key"]] = val_lbl


func _build_info_labels() -> void:
	_career_lbl       = _make_info_lbl()
	_level_lbl        = _make_info_lbl()
	_relationship_lbl = _make_info_lbl()
	_stress_lbl       = _make_info_lbl()
	for lbl: Label in [_career_lbl, _level_lbl, _relationship_lbl, _stress_lbl]:
		_info_container.add_child(lbl)


func _make_info_lbl() -> Label:
	var lbl := Label.new()
	lbl.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	lbl.add_theme_font_size_override("font_size", 13)
	return lbl


# ── Bar colour coding ─────────────────────────────────────────────────────────
func _bar_color(key: String, value: float) -> Color:
	match key:
		"health":
			if value > 65.0: return UIManager.C_SUCCESS
			elif value > 35.0: return UIManager.C_WARNING
			else: return UIManager.C_DANGER
		"happiness":
			if value > 55.0: return UIManager.C_SUCCESS
			elif value > 25.0: return UIManager.C_WARNING
			else: return UIManager.C_DANGER
		_:
			return UIManager.C_ACCENT   # reputation → indigo


# =============================================================================
# _apply_styles() — full visual setup applied on _ready()
# =============================================================================
func _apply_styles() -> void:
	var sidebar    := $OuterMargin/MainLayout/Sidebar
	var event_pnl  := $OuterMargin/MainLayout/EventPanel

	$Background.color = UIManager.C_BG

	# Panel cards
	var card := UIManager.make_card_style(UIManager.C_CARD, 16, Color(1, 1, 1, 0.07), 1)
	sidebar.add_theme_stylebox_override("panel", card)
	event_pnl.add_theme_stylebox_override("panel", card)

	# Sidebar header
	%GameTitle.add_theme_color_override("font_color", UIManager.C_ACCENT)
	%GameTitle.add_theme_font_size_override("font_size", 13)

	_age_value.add_theme_color_override("font_color", UIManager.C_TEXT)
	_age_value.add_theme_font_size_override("font_size", 14)

	UIManager.style_button(
		_btn_menu, UIManager.C_MUTED, UIManager.C_MUTED_H, UIManager.C_MUTED_P,
		UIManager.C_TEXT, 6
	)
	_btn_menu.add_theme_font_size_override("font_size", 12)

	# "STATS" section label
	%StatsSectionLabel.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	%StatsSectionLabel.add_theme_font_size_override("font_size", 11)

	# Traits label
	_traits_label.add_theme_color_override("font_color", UIManager.C_ACCENT)
	_traits_label.add_theme_font_size_override("font_size", 13)

	# Event area
	_event_cat_badge.add_theme_color_override("font_color", UIManager.C_ACCENT)
	_event_cat_badge.add_theme_font_size_override("font_size", 12)

	_ai_status_badge.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	_ai_status_badge.add_theme_font_size_override("font_size", 11)

	_event_title.add_theme_color_override("font_color", UIManager.C_TEXT)
	_event_title.add_theme_font_size_override("font_size", 28)

	_event_desc.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	_event_desc.add_theme_font_size_override("font_size", 15)

	%ChoicePrompt.add_theme_color_override("font_color", UIManager.C_TEXT)
	%ChoicePrompt.add_theme_font_size_override("font_size", 14)

	# Separators — shared style
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(1.0, 1.0, 1.0, 0.08)
	var sc := $OuterMargin/MainLayout/Sidebar/SideMargin/SidebarContent
	var ec := $OuterMargin/MainLayout/EventPanel/EventContentMargin/EventContent
	for sep: HSeparator in [
		sc.get_node("Sep_A"), sc.get_node("Sep_B"), sc.get_node("Sep_C"),
		ec.get_node("Sep_E")
	]:
		sep.add_theme_stylebox_override("separator", sep_style)

	# Loading overlay label
	$LoadingOverlay/LoadingCenter/LoadingVBox/LoadingLabel \
		.add_theme_color_override("font_color", UIManager.C_TEXT)
	$LoadingOverlay/LoadingCenter/LoadingVBox/LoadingLabel \
		.add_theme_font_size_override("font_size", 16)
