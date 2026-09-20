# game_manager.gd
# =============================================================================
# Autoload singleton that orchestrates the core game loop.
# Mediates between GameState, EventManager, AIService, and UI scenes.
# UI scenes never call each other directly — they go through GameManager signals.
# =============================================================================
extends Node

# ── Signals consumed by UI scenes ────────────────────────────────────────────
signal event_ready(event_data: Dictionary)
signal choice_applied(choice: Dictionary, effects: Dictionary)
signal game_over_triggered(reason: String)

# ── Internal state ────────────────────────────────────────────────────────────
var _current_event: Dictionary = {}

# ── Result handoff — set by game.gd before navigating to event_result.tscn ───
# event_result.gd reads this in _ready(); reset after reading.
var last_choice_result: Dictionary = {}


func _ready() -> void:
	GameState.game_over.connect(_on_game_over)


# =============================================================================
# Called by game.gd when the screen is ready for the next event.
# await-able: suspends caller while EventManager (and optionally AIService) run.
# =============================================================================
func request_next_event() -> void:
	await EventManager.request_event()


# =============================================================================
# Called by EventManager when a validated event is ready.
# =============================================================================
func on_event_received(event_data: Dictionary) -> void:
	_current_event = event_data
	event_ready.emit(event_data)


# =============================================================================
# Called by game.gd when the player selects a choice button.
# choice_index: 0-based index into _current_event["choices"]
# =============================================================================
func apply_choice(choice_index: int) -> void:
	if _current_event.is_empty():
		push_warning("GameManager: apply_choice called with no current event.")
		return
	var choices: Array = _current_event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		push_error("GameManager: choice_index %d out of bounds." % choice_index)
		return

	var choice: Dictionary  = choices[choice_index]
	var effects: Dictionary = choice.get("effects", {})
	var months: int         = choice.get("time_months", 6)

	GameState.apply_effects(effects)
	GameState.advance_time(months)
	GameState.add_recent_choice(choice.get("text", ""))
	GameState.add_major_event(_current_event.get("title", ""))

	choice_applied.emit(choice, effects)


# =============================================================================
# Scene management helpers
# =============================================================================
func start_new_game(char_data: Dictionary) -> void:
	GameState.initialize(char_data)
	EventManager.reset_life()   # Clears used-event tracker for a fresh playthrough
	UIManager.change_scene("res://scenes/game/game.tscn")


func navigate_to_summary() -> void:
	UIManager.change_scene("res://scenes/life_summary/life_summary.tscn")


# =============================================================================
# Game-over handler
# =============================================================================
func _on_game_over(reason: String) -> void:
	game_over_triggered.emit(reason)
	# Brief pause then transition to summary
	await get_tree().create_timer(1.5).timeout
	navigate_to_summary()
