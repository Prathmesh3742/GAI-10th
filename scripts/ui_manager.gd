# ui_manager.gd
# =============================================================================
# Autoload Node that handles:
#   1. Scene transitions with a fade overlay
#   2. Shared button styling helpers (called by all scenes)
#
# All scene changes go through UIManager.change_scene() to ensure consistent
# transitions. UI scripts never call get_tree().change_scene_to_file() directly.
# =============================================================================
extends Node

const FADE_DURATION: float = 0.28   # seconds per fade half

# ── Shared dark palette (used by all scenes) ──────────────────────────────────
const C_BG         := Color(0.055, 0.063, 0.086, 1.0)   # #0E1016 background
const C_CARD       := Color(0.122, 0.137, 0.188, 1.0)   # #1F2330 card panels
const C_ACCENT     := Color(0.384, 0.400, 0.945, 1.0)   # #6266F1 primary action
const C_ACCENT_H   := Color(0.459, 0.475, 0.965, 1.0)   # hover
const C_ACCENT_P   := Color(0.318, 0.333, 0.882, 1.0)   # pressed
const C_DANGER     := Color(0.859, 0.278, 0.278, 1.0)   # destructive / exit
const C_DANGER_H   := Color(0.902, 0.376, 0.376, 1.0)
const C_DANGER_P   := Color(0.780, 0.220, 0.220, 1.0)
const C_SUCCESS    := Color(0.196, 0.659, 0.420, 1.0)   # positive delta
const C_WARNING    := Color(0.902, 0.706, 0.243, 1.0)   # caution
const C_MUTED      := Color(0.180, 0.204, 0.271, 1.0)   # secondary buttons
const C_MUTED_H    := Color(0.220, 0.247, 0.318, 1.0)
const C_MUTED_P    := Color(0.145, 0.165, 0.224, 1.0)
const C_TEXT       := Color(0.949, 0.957, 0.984, 1.0)   # #F2F4FB primary text
const C_SUBTEXT    := Color(0.588, 0.620, 0.694, 1.0)   # #969EB1 secondary text


# =============================================================================
# change_scene() — fade-out → change → fade-in.
# Async (uses await internally); callers do NOT need to await it.
# =============================================================================
func change_scene(path: String) -> void:
	# Create full-screen black overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 100
	get_tree().root.add_child(overlay)

	# Fade out
	var tw1 := create_tween()
	tw1.tween_property(overlay, "color:a", 1.0, FADE_DURATION)
	await tw1.finished

	get_tree().change_scene_to_file(path)
	await get_tree().process_frame

	# Fade in on new scene
	var tw2 := create_tween()
	tw2.tween_property(overlay, "color:a", 0.0, FADE_DURATION)
	await tw2.finished
	overlay.queue_free()


# =============================================================================
# style_button() — applies a consistent StyleBoxFlat theme to a Button.
# Called by every scene's _apply_styles() — avoids duplicate styling code.
# =============================================================================
func style_button(
		btn: Button,
		bg: Color,
		bg_hover: Color,
		bg_pressed: Color,
		text_color: Color = C_TEXT,
		corner_radius: int = 10
) -> void:
	var normal   := _make_stylebox(bg,         corner_radius)
	var hover    := _make_stylebox(bg_hover,   corner_radius)
	var pressed  := _make_stylebox(bg_pressed, corner_radius)
	var disabled := _make_stylebox(bg.darkened(0.3), corner_radius)
	disabled.bg_color.a = 0.4

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus",    normal)

	btn.add_theme_color_override("font_color",          text_color)
	btn.add_theme_color_override("font_hover_color",    text_color)
	btn.add_theme_color_override("font_pressed_color",  text_color.lightened(0.15))
	btn.add_theme_color_override("font_disabled_color", text_color.darkened(0.5))
	btn.add_theme_font_size_override("font_size", 16)


# =============================================================================
# make_card_style() — returns a StyleBoxFlat for card/panel backgrounds.
# =============================================================================
func make_card_style(
		bg: Color = C_CARD,
		corner_radius: int = 16,
		border_color: Color = Color(1, 1, 1, 0.07),
		border_width: int = 1
) -> StyleBoxFlat:
	var style := _make_stylebox(bg, corner_radius)
	style.border_color  = border_color
	style.border_width_left   = border_width
	style.border_width_right  = border_width
	style.border_width_top    = border_width
	style.border_width_bottom = border_width
	return style


# =============================================================================
# format_money() — shared currency formatter.
# =============================================================================
func format_money(amount: float) -> String:
	var i: int = int(amount)
	if i >= 10_000_000:
		return "₹%.1fCr" % (i / 10_000_000.0)
	elif i >= 100_000:
		return "₹%.1fL" % (i / 100_000.0)
	elif i >= 1000:
		return "₹%.1fK" % (i / 1000.0)
	return "₹%d" % i


# =============================================================================
# delta_string() — returns a "+15" or "-5" string for the result screen.
# =============================================================================
func delta_string(value: float, prefix: String = "") -> String:
	if value > 0:
		return "+%s%s" % [prefix, str(int(value))]
	return "%s%s" % [prefix, str(int(value))]


# ── Private helpers ───────────────────────────────────────────────────────────
func _make_stylebox(bg: Color, corner: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color                    = bg
	s.corner_radius_top_left      = corner
	s.corner_radius_top_right     = corner
	s.corner_radius_bottom_left   = corner
	s.corner_radius_bottom_right  = corner
	s.content_margin_left         = 16.0
	s.content_margin_right        = 16.0
	s.content_margin_top          = 12.0
	s.content_margin_bottom       = 12.0
	return s
