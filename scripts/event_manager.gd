# event_manager.gd
# =============================================================================
# Autoload Node responsible for:
#   1. Weighted random category selection (engine picks category, AI picks content)
#   2. Requesting events from AIService (Step 8+) or fallback pool on failure
#   3. Validating AI output against the contract schema
#   4. No-repeat tracking for fallback events within a life
# =============================================================================
extends Node

# ── Weighted category table (§5.3) ───────────────────────────────────────────
# Weights must sum to 100. Godot RNG picks the category; AI picks the content.
const CATEGORY_WEIGHTS: Dictionary = {
	"career":        30,
	"relationships": 20,
	"finance":       15,
	"health":        15,
	"family":        10,
	"random":        10,
}

# ── Career ladder (mirrors careers.json) ─────────────────────────────────────
const CAREER_LADDER: Array = [
	"Student", "Intern", "Junior", "Mid-Level", "Senior", "Manager", "Director"
]

# ── Internal state ────────────────────────────────────────────────────────────
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fallback_events: Array     = []
var _fallback_loaded: bool      = false
var _used_fallback_indices: Array = []   # no-repeat tracking within current life


func _ready() -> void:
	_rng.randomize()


# =============================================================================
# reset_life() — called by GameManager on new game start to clear repeat tracking.
# =============================================================================
func reset_life() -> void:
	_used_fallback_indices.clear()


# =============================================================================
# request_event() — public API called by GameManager.
# Step 1–7: goes directly to fallback.
# Step 8+:  tries AIService first, falls back on failure.
# =============================================================================
func request_event() -> void:
	var category: String = select_category()

	if AIService.is_available():
		var context: Dictionary = _build_ai_context(category)
		var ai_event: Dictionary = await AIService.generate_event(context)
		if not ai_event.is_empty():
			GameManager.on_event_received(ai_event)
			return
		push_warning("EventManager: AI event failed — using fallback for '%s'" % category)

	# Fallback path (offline or AI failure)
	var event: Dictionary = _get_fallback_event(category)
	GameManager.on_event_received(event)


# =============================================================================
# select_category() — weighted random selection using Godot RNG.
# The ENGINE decides category; the AI decides content. (Core architecture point.)
# =============================================================================
func select_category() -> String:
	var roll: int    = _rng.randi_range(1, 100)
	var cumulative: int = 0
	for cat: String in CATEGORY_WEIGHTS:
		cumulative += CATEGORY_WEIGHTS[cat]
		if roll <= cumulative:
			return cat
	return "random"


# =============================================================================
# _validate_event() — strict schema validation against the AI output contract.
# Returns true if valid. Used in Step 8+ for AI responses.
# =============================================================================
func _validate_event(event: Dictionary) -> bool:
	# Required top-level keys
	for key: String in ["event_type", "title", "description", "choices"]:
		if not key in event:
			push_warning("EventManager: AI event missing required key: " + key)
			return false

	if not event["choices"] is Array or event["choices"].is_empty():
		push_warning("EventManager: AI event has no choices.")
		return false

	if event["choices"].size() > 4:
		push_warning("EventManager: AI event has too many choices (max 4).")
		return false

	# Validate each choice
	for choice: Dictionary in event["choices"]:
		if not "text" in choice:
			push_warning("EventManager: Choice missing 'text' key.")
			return false
		if not "effects" in choice:
			push_warning("EventManager: Choice missing 'effects' key.")
			return false
		# Clamp effects into valid ranges (protective layer before GameState)
		_clamp_effects(choice["effects"])
		# Validate career_level delta (Step 10: enforce single-rung moves)
		if "career_level_delta" in choice["effects"]:
			choice["effects"]["career_level_delta"] = clamp(
				int(choice["effects"]["career_level_delta"]), -1, 1
			)

	return true

# =============================================================================
# _build_ai_context() — packages GameState into the dict AIService expects.
# =============================================================================
func _build_ai_context(category: String) -> Dictionary:
	var traits_list: Array[String] = []
	for k: String in GameState.personality_traits.keys():
		traits_list.append(k)

	var recent_list: Array[String] = []
	for c: String in GameState.recent_choices:
		recent_list.append(c)

	return {
		"category": category,
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
		"traits"        : traits_list,
		"recent_choices": recent_list,
	}


func _clamp_effects(effects: Dictionary) -> void:
	var bounded: Array = ["health", "happiness", "stress", "reputation", "energy"]
	for stat: String in bounded:
		if stat in effects:
			# Clamp the delta itself to a reasonable range (-50 to +50)
			effects[stat] = clamp(float(effects[stat]), -50.0, 50.0)


# =============================================================================
# _get_fallback_event() — retrieves a fallback event from the JSON pool.
# Avoids repeating events until the entire pool is exhausted (then resets).
# =============================================================================
func _get_fallback_event(preferred_category: String) -> Dictionary:
	if not _fallback_loaded:
		_load_fallback_events()

	if _fallback_events.is_empty():
		return _emergency_event()

	# Prefer events matching the selected category; fall back to any unused event
	var candidates: Array = []
	for i: int in range(_fallback_events.size()):
		if i in _used_fallback_indices:
			continue
		if _fallback_events[i].get("event_type", "") == preferred_category:
			candidates.append(i)

	if candidates.is_empty():
		for i: int in range(_fallback_events.size()):
			if i not in _used_fallback_indices:
				candidates.append(i)

	# Pool exhausted — reset and allow repeats
	if candidates.is_empty():
		_used_fallback_indices.clear()
		for i: int in range(_fallback_events.size()):
			candidates.append(i)

	var chosen: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
	_used_fallback_indices.append(chosen)
	return _fallback_events[chosen].duplicate(true)


func _load_fallback_events() -> void:
	_fallback_loaded = true
	var path: String = "res://data/fallback_events.json"
	if not FileAccess.file_exists(path):
		push_warning("EventManager: fallback_events.json not found.")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("EventManager: Could not open fallback_events.json.")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Array:
		_fallback_events = json.data
	else:
		push_error("EventManager: fallback_events.json is malformed.")
	file.close()


# Emergency hardcoded event — used ONLY if fallback_events.json is missing.
func _emergency_event() -> Dictionary:
	return {
		"event_type" : "random",
		"title"      : "A Moment of Reflection",
		"description": "Nothing dramatic happens today. You find a quiet moment to think about where your life is heading.",
		"choices": [
			{
				"text"       : "Rest and recharge",
				"effects"    : {"energy": 10, "stress": -8},
				"time_months": 1
			},
			{
				"text"       : "Go out and meet new people",
				"effects"    : {"happiness": 8, "energy": -5},
				"time_months": 1
			}
		]
	}
