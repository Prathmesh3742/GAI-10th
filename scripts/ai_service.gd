# ai_service.gd
# =============================================================================
# Autoload NODE — registered in project.godot as an autoload.
# HTTPRequest MUST live under a Node in the scene tree to emit request_completed
# and be await-able. This is why ai_service is a Node, not a plain script.
#
# Responsibilities:
#   - Load API credentials from config/.env (never hard-coded)
#   - Build prompts for event generation and life summary
#   - POST to Groq API (OpenAI-compatible endpoint)
#   - Parse and validate JSON responses
#   - One retry on failure, then fallback
#   - Emit ai_status_changed(bool) so UI can show Online/Offline badge
#
# NOTE: Full implementation added in Step 8.
#       This stub sets up the Node/HTTPRequest scaffolding correctly
#       so other systems can depend on its interface from Day 1.
# =============================================================================
extends Node

# ── Signals ───────────────────────────────────────────────────────────────────
signal ai_status_changed(is_online: bool)

# ── Groq API constants ────────────────────────────────────────────────────────
const GROQ_ENDPOINT:    String = "https://api.groq.com/openai/v1/chat/completions"
const REQUEST_TIMEOUT:  float  = 15.0    # §7.4: API timeout error case
const MAX_RETRIES:      int    = 1       # one retry before fallback

# ── Config (loaded from config/.env) ─────────────────────────────────────────
var _api_key: String = ""
var _model:   String = "llama-3.3-70b-versatile"
var _is_online: bool = false

# ── HTTPRequest child node ────────────────────────────────────────────────────
var _http: HTTPRequest


func _ready() -> void:
	# Create the child HTTPRequest node.
	# Timeout satisfies the PRD's "API timeout" error case (§7.4).
	_http         = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	add_child(_http)

	_load_config()

	# Emit initial status so UI badge is correct from scene load
	ai_status_changed.emit(_is_online)


# =============================================================================
# _load_config() — reads config/.env; never touches hard-coded values.
# =============================================================================
func _load_config() -> void:
	var path: String = "res://config/.env"
	if not FileAccess.file_exists(path):
		push_warning("AIService: config/.env not found — running in offline mode.")
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("AIService: Cannot read config/.env.")
		return

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.begins_with("#") or line.is_empty():
			continue
		var parts: PackedStringArray = line.split("=", false, 1)
		if parts.size() == 2:
			match parts[0].strip_edges():
				"AI_API_KEY": _api_key = parts[1].strip_edges()
				"AI_MODEL":   _model   = parts[1].strip_edges()
	file.close()

	_is_online = (
		not _api_key.is_empty()
		and _api_key != "YOUR_GROQ_API_KEY_HERE"
	)


# =============================================================================
# Public API
# =============================================================================

func is_online() -> bool:
	return _is_online


# generate_event() — full implementation in Step 8.
# Returns a validated event Dictionary or {} on failure.
func generate_event(_category: String, _context: Dictionary) -> Dictionary:
	push_warning("AIService.generate_event(): AI integration not yet active (Step 8).")
	return {}


# generate_life_summary() — full implementation in Step 8.
# Returns a narrative string. Falls back to _build_fallback_summary() on failure.
func generate_life_summary(state: Dictionary) -> String:
	push_warning("AIService.generate_life_summary(): AI integration not yet active (Step 8).")
	return _build_fallback_summary(state)


# =============================================================================
# Fallback summary — used when generate_life_summary() AI call fails.
# Reads data/fallback_summary.json template; fills in GameState values.
# The Life Summary screen can NEVER render empty regardless of API state.
# =============================================================================
func _build_fallback_summary(state: Dictionary) -> String:
	var path: String = "res://data/fallback_summary.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				file.close()
				return _fill_template(json.data.get("template", ""), state)
			file.close()

	# Absolute last-resort inline fallback
	return (
		"%s lived a remarkable life, reaching the age of %d. "
		% [state.get("player_name", "You"), int(state.get("age", 18))]
		+ "Working as a %s, they faced countless choices that defined who they became. "
		% state.get("career", "free spirit")
		+ "Their journey — full of triumphs and trials — was uniquely their own."
	)


func _fill_template(template: String, state: Dictionary) -> String:
	var traits_list: Array = state.get("personality_traits", {}).keys()
	var traits_str: String = ", ".join(traits_list) if traits_list else "adaptable"
	var events_list: Array = state.get("major_life_events", [])
	var events_str: String = (
		", ".join(events_list.slice(-5)) if events_list else "many memorable moments"
	)
	return (
		template
		.replace("{name}",   state.get("player_name", "You"))
		.replace("{age}",    str(int(state.get("age", 18))))
		.replace("{career}", state.get("career", "adventurer"))
		.replace("{money}",  "₹" + str(int(state.get("money", 0))))
		.replace("{traits}", traits_str)
		.replace("{events}", events_str)
	)
