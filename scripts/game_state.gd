# game_state.gd
# =============================================================================
# Central state singleton.
# Registered as an autoload NODE — not a Resource.
# Rationale: live game state needs to be a single, always-present instance that
# can emit signals. Resource is reserved (if used at all) only for the save-file
# data shape.
#
# ALL stat reads/writes go through this script. No shadow state elsewhere.
# =============================================================================
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────
signal state_changed
signal game_over(reason: String)

# ── Player Identity ───────────────────────────────────────────────────────────
var player_name: String = ""
var gender: String = ""
var location: String = ""

# ── Core Stats ────────────────────────────────────────────────────────────────
# Clamped to [0, 100]: health, happiness, stress, reputation, energy
# money: floors at 0 (no debt in v1 — simple/deterministic per §5.13)
var age: float = 18.0           # fractional years (months preserved as .x)
var money: float = 5000.0       # ₹; floor 0, no upper cap
var health: float = 100.0       # 0–100 clamped
var happiness: float = 70.0     # 0–100 clamped
var reputation: float = 30.0    # 0–100 clamped
var energy: float = 80.0        # 0–100 clamped
var stress: float = 20.0        # 0–100 clamped

# ── Career ────────────────────────────────────────────────────────────────────
var education: String = "High School"
var career: String = "Student"
var career_level: String = "Student"   # must stay on ladder from careers.json

# ── Relationships ────────────────────────────────────────────────────────────
var relationship_status: String = "Single"
var relationships: Array = []          # [{name, type, score}]

# ── History & Personality ─────────────────────────────────────────────────────
var major_life_events: Array = []      # permanent, never pruned
var recent_choices: Array = []         # rolling window, max 5 — sent to AI
var personality_traits: Dictionary = {} # trait_name -> score (0–100)

# ── Flags ─────────────────────────────────────────────────────────────────────
var is_low_funds: bool = false
var is_game_active: bool = false


# =============================================================================
# Initialization — called by GameManager.start_new_game()
# =============================================================================
func initialize(char_data: Dictionary) -> void:
	player_name = char_data.get("name", "Player")
	gender       = char_data.get("gender", "Other")
	location     = char_data.get("location", "Mumbai")
	education    = char_data.get("education", "High School")

	# Build trait dict: {"Ambitious": 50, "Honest": 50, ...}
	personality_traits = {}
	for trait_name: String in char_data.get("traits", []):
		personality_traits[trait_name] = 50

	# Reset all numeric stats to starting values
	age               = 18.0
	money             = 5000.0
	health            = 100.0
	happiness         = 70.0
	reputation        = 30.0
	energy            = 80.0
	stress            = 20.0
	career            = "Student"
	career_level      = "Student"
	relationship_status = "Single"
	major_life_events = []
	recent_choices    = []
	relationships     = []
	is_low_funds      = false
	is_game_active    = true

	state_changed.emit()


# =============================================================================
# apply_effects() — the ONLY entry point for stat mutations.
# Called by GameManager after EventManager validates the AI/fallback effects.
#
# Clamping rules:
#   health, happiness, stress, reputation, energy  →  clamp(0, 100)
#   money                                          →  max(0)  [no debt]
#   personality_traits                             →  clamp(0, 100) per trait
# =============================================================================
func apply_effects(effects: Dictionary) -> void:
	if "health"     in effects: health     = clampf(health     + float(effects["health"]),     0.0, 100.0)
	if "happiness"  in effects: happiness  = clampf(happiness  + float(effects["happiness"]),  0.0, 100.0)
	if "stress"     in effects: stress     = clampf(stress     + float(effects["stress"]),     0.0, 100.0)
	if "reputation" in effects: reputation = clampf(reputation + float(effects["reputation"]), 0.0, 100.0)
	if "energy"     in effects: energy     = clampf(energy     + float(effects["energy"]),     0.0, 100.0)

	# Money: floor at 0; low-funds flag triggers narrative hints elsewhere
	if "money" in effects:
		money        = maxf(0.0, money + float(effects["money"]))
		is_low_funds = money < 1000.0

	# Personality trait adjustments (supplied as delta dict by EventManager)
	if "traits" in effects and effects["traits"] is Dictionary:
		for t: String in effects["traits"]:
			if t in personality_traits:
				personality_traits[t] = clampf(personality_traits[t] + float(effects["traits"][t]), 0.0, 100.0)

	state_changed.emit()
	_check_game_over_conditions()


# =============================================================================
# Time advancement — called by GameManager after a choice is applied.
# =============================================================================
func advance_time(months: int) -> void:
	age += months / 12.0
	state_changed.emit()
	_check_game_over_conditions()


# =============================================================================
# History helpers
# =============================================================================
func add_recent_choice(choice_text: String) -> void:
	recent_choices.append(choice_text)
	if recent_choices.size() > 5:
		recent_choices.pop_front()   # maintain rolling window of 5

func add_major_event(event_title: String) -> void:
	if not event_title.is_empty():
		major_life_events.append(event_title)


# =============================================================================
# Career mutation — called ONLY by EventManager after ladder validation.
# Never call this directly from AI output.
# =============================================================================
func set_career(new_career: String, new_level: String) -> void:
	career       = new_career
	career_level = new_level
	state_changed.emit()

func set_relationship_status(new_status: String) -> void:
	relationship_status = new_status
	state_changed.emit()


# =============================================================================
# Context snapshot — sent to AI (§5.7).
# Deliberately minimal: only what the AI needs for contextual narrative.
# Keeps token usage low.
# =============================================================================
func get_context() -> Dictionary:
	return {
		"age"          : int(age),
		"career"       : career,
		"career_level" : career_level,
		"money"        : int(money),
		"health"       : int(health),
		"happiness"    : int(happiness),
		"stress"       : int(stress),
		"relationship" : relationship_status,
		"location"     : location,
		"traits"       : personality_traits.keys(),
		"recent_events": recent_choices.slice(-5)
	}


# =============================================================================
# Serialization — used exclusively by SaveManager.
# =============================================================================
func to_dict() -> Dictionary:
	return {
		"player_name"        : player_name,
		"gender"             : gender,
		"location"           : location,
		"age"                : age,
		"money"              : money,
		"health"             : health,
		"happiness"          : happiness,
		"reputation"         : reputation,
		"energy"             : energy,
		"stress"             : stress,
		"education"          : education,
		"career"             : career,
		"career_level"       : career_level,
		"relationship_status": relationship_status,
		"major_life_events"  : major_life_events,
		"recent_choices"     : recent_choices,
		"personality_traits" : personality_traits,
		"relationships"      : relationships
	}

func from_dict(data: Dictionary) -> void:
	player_name         = data.get("player_name",         "")
	gender              = data.get("gender",              "")
	location            = data.get("location",            "")
	age                 = data.get("age",                 18.0)
	money               = data.get("money",               5000.0)
	health              = data.get("health",              100.0)
	happiness           = data.get("happiness",           70.0)
	reputation          = data.get("reputation",          30.0)
	energy              = data.get("energy",              80.0)
	stress              = data.get("stress",              20.0)
	education           = data.get("education",           "High School")
	career              = data.get("career",              "Student")
	career_level        = data.get("career_level",        "Student")
	relationship_status = data.get("relationship_status", "Single")
	major_life_events   = data.get("major_life_events",   [])
	recent_choices      = data.get("recent_choices",      [])
	personality_traits  = data.get("personality_traits",  {})
	relationships       = data.get("relationships",       [])
	is_low_funds        = money < 1000.0
	is_game_active      = true
	state_changed.emit()


# =============================================================================
# Game-over condition checks — private
# =============================================================================
func _check_game_over_conditions() -> void:
	if not is_game_active:
		return
	if age >= 80.0:
		is_game_active = false
		game_over.emit("You lived a full life and reached old age.")
	elif health <= 0.0:
		is_game_active = false
		game_over.emit("Your health failed you.")
