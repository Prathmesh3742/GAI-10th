# event_result.gd
# =============================================================================
# Event Result screen — Milestone 1 completion (Step 5).
#
# Reads GameManager.last_choice_result (set by game.gd before navigating here).
# Displays:
#   • The choice the player made (in quotes)
#   • Time elapsed
#   • Each changed stat as a colour-coded +/- delta row
#   • A snapshot of current GameState values
#   • "Continue" button → back to game.tscn for the next event
# =============================================================================
extends Control

# ── Stat display metadata ─────────────────────────────────────────────────────
const STAT_META: Dictionary = {
	"money"      : {"icon": "💰", "label": "Money"},
	"health"     : {"icon": "❤",  "label": "Health"},
	"happiness"  : {"icon": "😊", "label": "Happiness"},
	"stress"     : {"icon": "😰", "label": "Stress"},
	"reputation" : {"icon": "⭐", "label": "Reputation"},
	"energy"     : {"icon": "⚡", "label": "Energy"},
}

# Stats where a HIGHER value is WORSE (positive delta = bad = red)
const INVERSE_STATS: Array[String] = ["stress"]

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var _content_card:      PanelContainer = %ContentCard
@onready var _age_label:         Label          = %AgeLabel
@onready var _choice_text:       Label          = %ChoiceText
@onready var _time_label:        Label          = %TimeLabel
@onready var _effects_container: VBoxContainer  = %EffectsContainer
@onready var _snapshot_label:    Label          = %SnapshotLabel
@onready var _btn_continue:      Button         = %BtnContinue


func _ready() -> void:
	await get_tree().process_frame
	_apply_styles()
	_load_result()
	_animate_entrance()


# =============================================================================
# Load result data from GameManager handoff
# =============================================================================
func _load_result() -> void:
	var result: Dictionary = GameManager.last_choice_result
	GameManager.last_choice_result = {}   # consume and clear

	# Header — current age (GameState already updated by apply_choice)
	_age_label.text = "NOW AGE %d" % int(GameState.age)

	if result.is_empty():
		# Fallback: navigated here without a prior choice (shouldn't happen normally)
		_choice_text.text  = "Your journey continues..."
		_time_label.text   = ""
		_snapshot_label.text = ""
		_btn_continue.pressed.connect(_on_continue)
		return

	# Choice text — displayed in quotes for emphasis
	_choice_text.text = "\"%s\"" % result.get("choice_text", "")

	# Time label
	_time_label.text = _build_time_text(result.get("time_months", 1))

	# Effect delta rows
	_build_effects(result.get("effects", {}))

	# Snapshot of current state
	_build_snapshot()

	# Wire continue button
	_btn_continue.pressed.connect(_on_continue)


# =============================================================================
# Effect rows — one row per changed stat, colour-coded +/-
# =============================================================================
func _build_effects(effects: Dictionary) -> void:
	var had_any := false

	# Preserve a consistent display order matching STAT_META key order
	for key: String in STAT_META:
		if key not in effects:
			continue
		var value: float = float(effects[key])
		if value == 0.0:
			continue

		had_any = true
		var meta: Dictionary = STAT_META[key]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_effects_container.add_child(row)

		# Stat icon + name
		var name_lbl := Label.new()
		name_lbl.text = "%s  %s" % [meta["icon"], meta["label"]]
		name_lbl.custom_minimum_size = Vector2(140, 0)
		name_lbl.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
		name_lbl.add_theme_font_size_override("font_size", 15)
		row.add_child(name_lbl)

		# Spacer pushes delta to right
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		# Delta label
		var delta_lbl := Label.new()
		delta_lbl.text = _format_delta(key, value)
		delta_lbl.add_theme_color_override("font_color", _effect_color(key, value))
		delta_lbl.add_theme_font_size_override("font_size", 16)
		delta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(delta_lbl)

	if not had_any:
		# Nothing changed — show a neutral row
		var lbl := Label.new()
		lbl.text = "No immediate changes."
		lbl.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
		lbl.add_theme_font_size_override("font_size", 14)
		_effects_container.add_child(lbl)


# =============================================================================
# Snapshot — current GameState after the effects were applied
# =============================================================================
func _build_snapshot() -> void:
	var parts: Array[String] = []
	parts.append(UIManager.format_money(GameState.money))
	parts.append("❤ %d" % int(GameState.health))
	parts.append("😊 %d" % int(GameState.happiness))
	parts.append("😰 %d stress" % int(GameState.stress))
	if GameState.career != "Student":
		parts.append(GameState.career)
	_snapshot_label.text = "  ·  ".join(parts)


# =============================================================================
# Continue → back to game.tscn (loads next event)
# =============================================================================
func _on_continue() -> void:
	UIManager.change_scene("res://scenes/game/game.tscn")


# =============================================================================
# Formatting helpers
# =============================================================================
func _format_delta(key: String, value: float) -> String:
	if key == "money":
		if value >= 0.0:
			return "+" + UIManager.format_money(value)
		else:
			return "−" + UIManager.format_money(absf(value))
	var delta_prefix: String = "+" if value > 0.0 else ""
	return "%s%d" % [delta_prefix, int(value)]


func _effect_color(key: String, value: float) -> Color:
	# For inverse stats (stress), flip good/bad colouring
	var positive_is_good: bool = key not in INVERSE_STATS
	if value > 0.0:
		return UIManager.C_SUCCESS if positive_is_good else UIManager.C_DANGER
	elif value < 0.0:
		return UIManager.C_DANGER  if positive_is_good else UIManager.C_SUCCESS
	return UIManager.C_SUBTEXT


func _build_time_text(months: int) -> String:
	if months <= 0:
		return ""
	var m:    int = int(months)
	var yrs:  int = floori(m / 12.0)
	var mths: int = m - (yrs * 12)
	if yrs == 0:
		return "%d month%s passed." % [mths, "s" if mths != 1 else ""]
	if mths == 0:
		return "%d year%s passed." % [yrs, "s" if yrs != 1 else ""]
	return "%d year%s and %d month%s passed." % [
		yrs, "s" if yrs != 1 else "",
		mths, "s" if mths != 1 else ""
	]


# =============================================================================
# Styling
# =============================================================================
func _apply_styles() -> void:
	var mc := $CenterContainer/ContentCard/MarginContainer/MainContent

	$Background.color = UIManager.C_BG

	# Card
	_content_card.add_theme_stylebox_override("panel",
		UIManager.make_card_style(UIManager.C_CARD, 20, Color(1, 1, 1, 0.08), 1))

	# Header
	mc.get_node("Header/HeaderLabel").add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	mc.get_node("Header/HeaderLabel").add_theme_font_size_override("font_size", 12)

	_age_label.add_theme_color_override("font_color", UIManager.C_ACCENT)
	_age_label.add_theme_font_size_override("font_size", 14)

	# Choice text — accent colour, large
	_choice_text.add_theme_color_override("font_color", UIManager.C_TEXT)
	_choice_text.add_theme_font_size_override("font_size", 20)

	# Time label
	_time_label.add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	_time_label.add_theme_font_size_override("font_size", 13)

	# Effects section title
	mc.get_node("EffectsTitle").add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	mc.get_node("EffectsTitle").add_theme_font_size_override("font_size", 12)

	# Snapshot section
	mc.get_node("SnapshotTitle").add_theme_color_override("font_color", UIManager.C_SUBTEXT)
	mc.get_node("SnapshotTitle").add_theme_font_size_override("font_size", 12)

	_snapshot_label.add_theme_color_override("font_color", UIManager.C_TEXT)
	_snapshot_label.add_theme_font_size_override("font_size", 14)

	# Separators
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(1.0, 1.0, 1.0, 0.08)
	for sep_name: String in ["Sep1", "Sep2", "Sep3"]:
		mc.get_node(sep_name).add_theme_stylebox_override("separator", sep_style)

	# Continue button
	UIManager.style_button(_btn_continue,
		UIManager.C_ACCENT, UIManager.C_ACCENT_H, UIManager.C_ACCENT_P,
		UIManager.C_TEXT, 12)
	_btn_continue.add_theme_font_size_override("font_size", 17)


# =============================================================================
# Entrance animation
# =============================================================================
func _animate_entrance() -> void:
	_content_card.pivot_offset = _content_card.size / 2.0
	_content_card.scale        = Vector2(0.95, 0.95)
	_content_card.modulate.a   = 0.0
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.set_parallel(true)
	tw.tween_property(_content_card, "modulate:a", 1.0, 0.35)
	tw.tween_property(_content_card, "scale",      Vector2(1.0, 1.0), 0.35)
