# character_creation.gd
# =============================================================================
# Full character creation screen — Step 2.
# Collects: Name, Gender, Location, Education, and exactly 2 Personality Traits.
# Trait limit is enforced in UI code (remaining CheckButtons disabled once 2 are
# selected) — not left to convention.
# On confirm, calls GameManager.start_new_game(char_data) which calls
# GameState.initialize() and transitions to game.tscn.
# =============================================================================
extends Control

# ── Constants ─────────────────────────────────────────────────────────────────
const MAX_TRAITS: int = 2

const TRAITS: Array[String] = [
	"Ambitious", "Honest", "Kind",
	"Risk-Taker", "Creative", "Social",
	"Adventurous", "Calm", "Selfish"
]
const GENDERS: Array[String] = [
	"Male", "Female", "Non-binary", "Prefer not to say"
]
const LOCATIONS: Array[String] = [
	"Mumbai", "Delhi", "Bangalore", "Chennai",
	"Hyderabad", "Pune", "Kolkata", "Ahmedabad", "Jaipur"
]
const EDUCATIONS: Array[String] = [
	"High School", "Some College", "Bachelor's Degree", "Postgraduate"
]

# ── State ─────────────────────────────────────────────────────────────────────
var _selected_traits: Array[String] = []

# ── Node references (unique-name access) ──────────────────────────────────────
@onready var _content_card:     PanelContainer = %ContentCard
@onready var _btn_back:         Button         = %BtnBack
@onready var _name_input:       LineEdit       = %NameInput
@onready var _gender_option:    OptionButton   = %GenderOption
@onready var _location_option:  OptionButton   = %LocationOption
@onready var _educ_option:      OptionButton   = %EducOption
@onready var _trait_count_lbl:  Label          = %TraitCount
@onready var _trait_hint_lbl:   Label          = %TraitHint
@onready var _traits_grid:      GridContainer  = %TraitsGrid
@onready var _btn_confirm:      Button         = %BtnConfirm


func _ready() -> void:
	# Wait one frame for layout to settle (needed for pivot_offset animation)
	await get_tree().process_frame
	_populate_dropdowns()
	_build_trait_buttons()
	_apply_styles()
	_connect_signals()
	_update_confirm_state()
	_animate_entrance()


# =============================================================================
# Dropdown population
# =============================================================================
func _populate_dropdowns() -> void:
	for g: String in GENDERS:    _gender_option.add_item(g)
	for l: String in LOCATIONS:  _location_option.add_item(l)
	for e: String in EDUCATIONS: _educ_option.add_item(e)


# =============================================================================
# Trait buttons — built dynamically so they can be styled as togglable pills.
# =============================================================================
func _build_trait_buttons() -> void:
	for trait_name: String in TRAITS:
		var btn := Button.new()
		btn.text                   = trait_name
		btn.toggle_mode            = true
		btn.custom_minimum_size    = Vector2(0, 42)
		btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
		btn.alignment              = HORIZONTAL_ALIGNMENT_CENTER
		_traits_grid.add_child(btn)
		_apply_trait_button_style(btn, false)
		# Signal: toggled(bool) + bound args (trait_name, btn)
		btn.toggled.connect(_on_trait_toggled.bind(trait_name, btn))


# =============================================================================
# Trait toggle logic
# Enforces the 2-trait limit in UI code — remaining buttons are disabled
# once 2 are selected; re-enabled when one is deselected.
# =============================================================================
func _on_trait_toggled(is_pressed: bool, trait_name: String, btn: Button) -> void:
	if is_pressed:
		if _selected_traits.size() >= MAX_TRAITS:
			# Cap reached — reject the press silently without firing more signals
			btn.set_pressed_no_signal(false)
			return
		_selected_traits.append(trait_name)
	else:
		_selected_traits.erase(trait_name)

	_refresh_trait_ui()
	_update_confirm_state()


func _refresh_trait_ui() -> void:
	var count: int = _selected_traits.size()

	# Counter label + colour
	_trait_count_lbl.text = "%d / 2" % count
	_trait_count_lbl.add_theme_color_override(
		"font_color",
		UIManager.C_SUCCESS if count == MAX_TRAITS else UIManager.C_SUBTEXT
	)

	# Hint text
	match count:
		0: _trait_hint_lbl.text = "Select 2 traits that define your character."
		1: _trait_hint_lbl.text = "Great — select 1 more trait."
		2: _trait_hint_lbl.text = "Perfect. Your traits are locked in."

	# Restyle each trait button; disable unchosen ones when cap is reached
	for child: Node in _traits_grid.get_children():
		if not child is Button:
			continue
		var tbtn: Button = child as Button
		var is_sel: bool = tbtn.button_pressed
		_apply_trait_button_style(tbtn, is_sel)
		tbtn.disabled = (count >= MAX_TRAITS and not is_sel)


func _apply_trait_button_style(btn: Button, selected: bool) -> void:
	if selected:
		UIManager.style_button(
			btn,
			UIManager.C_ACCENT, UIManager.C_ACCENT_H, UIManager.C_ACCENT_P,
			UIManager.C_TEXT, 10
		)
	else:
		UIManager.style_button(
			btn,
			UIManager.C_MUTED, UIManager.C_MUTED_H, UIManager.C_MUTED_P,
			UIManager.C_SUBTEXT, 10
		)
	btn.add_theme_font_size_override("font_size", 14)


# =============================================================================
# Confirm button state — enabled only when name ≥ 2 chars AND 2 traits chosen
# =============================================================================
func _update_confirm_state() -> void:
	var name_ok:   bool = _name_input.text.strip_edges().length() >= 2
	var traits_ok: bool = _selected_traits.size() == MAX_TRAITS
	_btn_confirm.disabled = not (name_ok and traits_ok)


# =============================================================================
# Signal connections
# =============================================================================
func _connect_signals() -> void:
	_btn_back.pressed.connect(func() -> void:
		UIManager.change_scene("res://scenes/main_menu/main_menu.tscn")
	)
	_btn_confirm.pressed.connect(_on_confirm)
	_name_input.text_changed.connect(func(_t: String) -> void:
		_update_confirm_state()
	)


# =============================================================================
# Confirm → hand off to GameManager
# =============================================================================
func _on_confirm() -> void:
	var char_data: Dictionary = {
		"name"      : _name_input.text.strip_edges(),
		"gender"    : GENDERS[_gender_option.selected],
		"location"  : LOCATIONS[_location_option.selected],
		"education" : EDUCATIONS[_educ_option.selected],
		"traits"    : _selected_traits.duplicate()
	}
	GameManager.start_new_game(char_data)


# =============================================================================
# Styling — applied entirely in code via UIManager helpers
# =============================================================================
func _apply_styles() -> void:
	var mc  := $CenterContainer/ContentCard/MarginContainer/MainContent
	var fs  := mc.get_node("FormSection")
	var ts  := mc.get_node("TraitsSection")

	# Background
	$Background.color = UIManager.C_BG

	# Card panel
	_content_card.add_theme_stylebox_override("panel",
		UIManager.make_card_style(UIManager.C_CARD, 20, Color(1, 1, 1, 0.08), 1))

	# Header
	%HeaderTitle.add_theme_color_override("font_color", UIManager.C_TEXT)
	%HeaderTitle.add_theme_font_size_override("font_size", 22)
	UIManager.style_button(_btn_back,
		UIManager.C_MUTED, UIManager.C_MUTED_H, UIManager.C_MUTED_P,
		UIManager.C_TEXT, 8)
	_btn_back.add_theme_font_size_override("font_size", 14)

	# Separators
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(1.0, 1.0, 1.0, 0.08)
	mc.get_node("Sep1").add_theme_stylebox_override("separator", sep_style)
	mc.get_node("Sep2").add_theme_stylebox_override("separator", sep_style)

	# Form field labels (smaller, muted)
	for lbl_path: String in [
		"NameRow/NameLabel",
		"TwoColRow/GenderCol/GenderLabel",
		"TwoColRow/LocationCol/LocationLabel",
		"EducRow/EducCol/EducLabel"
	]:
		var lbl: Label = fs.get_node(lbl_path)
		lbl.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
		lbl.add_theme_font_size_override("font_size", 12)

	# Name input
	_style_line_edit(_name_input)

	# Option buttons
	for ob: OptionButton in [_gender_option, _location_option, _educ_option]:
		_style_option_button(ob)

	# Traits section heading
	var traits_lbl: Label = ts.get_node("TraitsHeader/TraitsLabel")
	traits_lbl.add_theme_color_override("font_color", UIManager.C_TEXT)
	traits_lbl.add_theme_font_size_override("font_size", 16)

	_trait_count_lbl.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	_trait_count_lbl.add_theme_font_size_override("font_size", 14)

	_trait_hint_lbl.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	_trait_hint_lbl.add_theme_font_size_override("font_size", 13)

	# Confirm button (disabled initially — styled here so it looks right when enabled)
	UIManager.style_button(_btn_confirm,
		UIManager.C_ACCENT, UIManager.C_ACCENT_H, UIManager.C_ACCENT_P,
		UIManager.C_TEXT, 12)
	_btn_confirm.add_theme_font_size_override("font_size", 17)


# ── Input field styling helpers ───────────────────────────────────────────────
func _style_line_edit(le: LineEdit) -> void:
	var bg := Color(0.086, 0.098, 0.137, 1.0)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = Color(0.235, 0.259, 0.349, 1.0)
	normal.set_border_width_all(1)
	normal.border_width_bottom = 2
	normal.set_corner_radius_all(8)
	normal.content_margin_left   = 14.0
	normal.content_margin_right  = 14.0
	normal.content_margin_top    = 10.0
	normal.content_margin_bottom = 10.0

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = UIManager.C_ACCENT
	focus.border_width_bottom = 2

	le.add_theme_stylebox_override("normal",              normal)
	le.add_theme_stylebox_override("focus",               focus)
	le.add_theme_color_override("font_color",             UIManager.C_TEXT)
	le.add_theme_color_override("font_placeholder_color", UIManager.C_SUBTEXT)
	le.add_theme_color_override("caret_color",            UIManager.C_ACCENT)
	le.add_theme_font_size_override("font_size",          15)


func _style_option_button(ob: OptionButton) -> void:
	var bg := Color(0.086, 0.098, 0.137, 1.0)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = Color(0.235, 0.259, 0.349, 1.0)
	normal.set_border_width_all(1)
	normal.border_width_bottom = 2
	normal.set_corner_radius_all(8)
	normal.content_margin_left   = 14.0
	normal.content_margin_right  = 14.0
	normal.content_margin_top    = 10.0
	normal.content_margin_bottom = 10.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = UIManager.C_ACCENT

	ob.add_theme_stylebox_override("normal",       normal)
	ob.add_theme_stylebox_override("hover",        hover)
	ob.add_theme_stylebox_override("pressed",      hover)
	ob.add_theme_stylebox_override("focus",        normal)
	ob.add_theme_color_override("font_color",      UIManager.C_TEXT)
	ob.add_theme_font_size_override("font_size",   15)


# =============================================================================
# Entrance animation — pop-in scale + fade (same as main_menu)
# =============================================================================
func _animate_entrance() -> void:
	_content_card.pivot_offset = _content_card.size / 2.0
	_content_card.scale        = Vector2(0.95, 0.95)
	_content_card.modulate.a   = 0.0
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.set_parallel(true)
	tw.tween_property(_content_card, "modulate:a", 1.0, 0.4)
	tw.tween_property(_content_card, "scale",      Vector2(1.0, 1.0), 0.4)
