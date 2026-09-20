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
	var months: int         = int(choice.get("time_months", 6))

	GameState.apply_effects(effects)
	GameState.advance_time(months)
	GameState.add_recent_choice(choice.get("text", ""))
	GameState.add_major_event(_current_event.get("title", ""))

	# Career progression — enforces single-rung ladder moves.
	# AI events may include:
	#   "career_level_delta": 1   (promotion)   or -1 (demotion)
	#   "career_name": "Engineer" (career change, used with delta)
	_apply_career_change(effects)

	choice_applied.emit(choice, effects)


# Career ladder — mirrors careers.json progression order.
const CAREER_LADDER: Array[String] = [
	"Student", "Intern", "Junior", "Mid-Level",
	"Senior", "Manager", "Director", "Executive"
]

func _apply_career_change(effects: Dictionary) -> void:
	if not effects.has("career_level_delta"):
		return
	var delta: int = clampi(int(effects["career_level_delta"]), -1, 1)
	if delta == 0:
		return

	var current_idx: int = CAREER_LADDER.find(GameState.career_level)
	if current_idx == -1:
		current_idx = 0
	var new_idx: int = clampi(current_idx + delta, 0, CAREER_LADDER.size() - 1)
	var new_level: String = CAREER_LADDER[new_idx]

	# Use AI-provided career name if given, otherwise keep existing
	var new_career: String = effects.get("career_name", GameState.career)
	if not (new_career is String) or new_career.strip_edges().is_empty():
		new_career = GameState.career

	if new_level != GameState.career_level or new_career != GameState.career:
		GameState.set_career(new_career, new_level)
		GameState.add_major_event(
			"%s → %s (%s)" % [GameState.player_name, new_career, new_level]
		)


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
