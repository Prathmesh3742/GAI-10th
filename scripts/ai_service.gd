# ai_service.gd
# =============================================================================
# Autoload NODE — HTTPRequest child MUST live under a Node in the scene tree
# to emit request_completed and be await-able.
#
# Responsibilities:
#   - Load GROQ_API_KEY from config/.env  (never hard-coded)
#   - Build context-rich prompts for event generation and life summary
#   - POST to Groq API (OpenAI-compatible) with 15 s timeout
#   - Parse, validate, and clamp JSON responses
#   - One retry on failure → caller uses fallback
#   - Emit ai_status_changed(bool) so the UI badge stays current
# =============================================================================
extends Node

# ── Signals ───────────────────────────────────────────────────────────────────
signal ai_status_changed(is_online: bool)

# ── API constants ─────────────────────────────────────────────────────────────
const GROQ_ENDPOINT:   String = "https://api.groq.com/openai/v1/chat/completions"
const REQUEST_TIMEOUT: float  = 15.0
const MAX_TOKENS:      int    = 800
# Preference order — first model your account can access wins.
# Covers both the standard free-tier llama models AND the models
# visible on this specific account from the /v1/models log.
const MODEL_PREFERENCE: Array[String] = [
	# Standard Groq free-tier (may or may not be on your account)
	"llama-3.3-70b-versatile",
	"llama-3.1-70b-versatile",
	"llama-3.1-8b-instant",
	"meta-llama/llama-4-scout-17b-16e-instruct",
	"meta-llama/llama-4-maverick-17b-128e-instruct",
	# Models confirmed present on this account
	"openai/gpt-oss-120b",
	"groq/compound",
	"qwen/qwen3.8-27b",
	"openai/gpt-oss-20b",
	"groq/compound-mini",
	"allam-2-7b",
	# Legacy / tool-use models
	"llama3-groq-70b-8192-tool-use-preview",
	"gemma2-9b-it",
]

# ── System prompts ────────────────────────────────────────────────────────────
const SYSTEM_PROMPT_EVENT: String = (
	"You are an event generator for a life simulation game set in modern India.\n"
	+ "Generate a realistic, contextually appropriate life event for the given player.\n\n"
	+ "Output ONLY valid JSON matching this EXACT structure (no markdown, no prose):\n"
	+ "{\n"
	+ "  \"event_type\": \"career\",\n"
	+ "  \"title\": \"Brief Title Here\",\n"
	+ "  \"description\": \"Two or three sentences describing the situation.\",\n"
	+ "  \"choices\": [\n"
	+ "    {\n"
	+ "      \"text\": \"The action the player takes\",\n"
	+ "      \"effects\": {\"money\": 5000, \"health\": -5, \"happiness\": 10, \"stress\": 15, \"reputation\": 5},\n"
	+ "      \"time_months\": 3\n"
	+ "    }\n"
	+ "  ]\n"
	+ "}\n\n"
	+ "Rules:\n"
	+ "- event_type must be one of: career, relationships, finance, health, family, random\n"
	+ "- CRITICAL: You MUST include exactly 2, 3, or 4 choices. Never 1. A response with only 1 choice will be rejected.\n"
	+ "- Effect values are INTEGER deltas (positive = increase, negative = decrease)\n"
	+ "- money delta: -50000 to 50000 (Indian Rupees — realistic amounts)\n"
	+ "- health, happiness, stress, reputation deltas: -25 to 25\n"
	+ "- time_months: integer 1-12\n"
	+ "- Make the event authentic to Indian urban life\n"
	+ "- Event should suit the player's age and career stage"
)

const SYSTEM_PROMPT_SUMMARY: String = (
	"You are a thoughtful narrator for a life simulation game.\n"
	+ "Write a warm, reflective, and poetic summary of the player's life journey.\n\n"
	+ "Output ONLY valid JSON:\n"
	+ "{\"summary\": \"Your summary text here.\"}\n\n"
	+ "Guidelines:\n"
	+ "- 4-6 sentences, second-person voice (\"You began your journey...\")\n"
	+ "- Reflect on the arc of their career and key choices\n"
	+ "- Mention their financial journey and relationships\n"
	+ "- Close with a philosophical note about the life they lived\n"
	+ "- Tone: warm, wise, human — not clinical or generic"
)

# ── Config ────────────────────────────────────────────────────────────────────
var _api_key:   String = ""
var _model:     String = ""   # resolved by _discover_model()
var _is_online: bool   = false

# ── HTTPRequest child ─────────────────────────────────────────────────────────
var _http: HTTPRequest


func _ready() -> void:
	_http         = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	add_child(_http)
	_load_config()
	if not _api_key.is_empty() and _api_key != "YOUR_GROQ_API_KEY_HERE":
		await _discover_model()
	ai_status_changed.emit(_is_online)


# =============================================================================
# _load_config() — reads config/.env; never hard-codes credentials.
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
				"GROQ_API_KEY": _api_key = parts[1].strip_edges()
				"AI_MODEL":     _model   = parts[1].strip_edges()
				"AI_API_KEY":   _api_key = parts[1].strip_edges()  # legacy key name
	file.close()

	_is_online = not _api_key.is_empty() and _api_key != "YOUR_GROQ_API_KEY_HERE"
	if not _is_online:
		push_warning("AIService: GROQ_API_KEY missing or placeholder — offline mode.")


# =============================================================================
# Public API
# =============================================================================

func is_available() -> bool:
	return _is_online and not _model.is_empty()


# =============================================================================
# _discover_model() — queries /v1/models and picks the best available model.
# Silently falls back to MODEL_PREFERENCE[0] if discovery fails.
# =============================================================================
func _discover_model() -> void:
	var headers := PackedStringArray([
		"Authorization: Bearer " + _api_key
	])
	var err: int = _http.request(
		"https://api.groq.com/openai/v1/models",
		headers, HTTPClient.METHOD_GET
	)
	if err != OK:
		_model = MODEL_PREFERENCE[0]
		_is_online = true
		return

	var result: Array = await _http.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		_model = MODEL_PREFERENCE[0]
		_is_online = true
		return

	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		_model = MODEL_PREFERENCE[0]
		_is_online = true
		return

	# Build a set of available model IDs
	var available: Dictionary = {}
	for m: Variant in data.get("data", []):
		if m is Dictionary:
			available[m.get("id", "")] = true

	# Debug: log what the account has (shows in Output panel)
	push_warning("AIService: account has models — " + ", ".join(available.keys()))

	# Pick first preferred model that is actually available
	for preferred: String in MODEL_PREFERENCE:
		if preferred in available:
			_model = preferred
			_is_online = true
			push_warning("AIService: using model '%s'" % _model)
			return

	# Nothing in preference list matched — pick first available CHAT model
	# (excludes Whisper/TTS/embedding which don't support chat completions)
	for key: Variant in available.keys():
		if _is_chat_model(str(key)):
			_model = str(key)
			_is_online = true
			push_warning("AIService: using first available chat model '%s'" % _model)
			return

	# Total failure — stay offline
	push_warning("AIService: no chat-capable models found on this account — offline mode.")
	_is_online = false


## Returns true if the model ID is likely a chat/completion model.
## Filters out Whisper (STT), TTS, embedding, guard, and safety-classifier models.
func _is_chat_model(model_id: String) -> bool:
	var id: String = model_id.to_lower()
	for blocked: String in [
		"whisper", "tts", "embed", "distil-whisper",
		"prompt-guard", "safeguard", "orpheus", "-guard"
	]:
		if blocked in id:
			return false
	return true


## generate_event() — called by EventManager.request_event().
## Returns a validated, clamped event Dictionary, or {} on failure.
func generate_event(context: Dictionary) -> Dictionary:
	if not _is_online:
		return {}

	var messages: Array = _build_event_messages(context)

	# First attempt
	var raw: String = await _attempt(messages)
	if raw.is_empty():
		raw = await _attempt(messages)   # one retry

	if raw.is_empty():
		_set_online(false)
		return {}

	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		push_warning("AIService: response is not a JSON object. Raw (first 400 chars):\n%s" % raw.left(400))
		return {}

	# Sanitise: fill optional missing fields before hard validation
	_sanitize_event(data)

	if not _validate_event(data):
		push_warning("AIService: event failed hard validation. Parsed keys: %s" % str(data.keys()))
		return {}

	_clamp_event_effects(data)
	_set_online(true)
	return data


## generate_life_summary() — called by life_summary.gd.
## Returns a narrative String, or "" on failure (caller shows fallback text).
func generate_life_summary(context: Dictionary) -> String:
	if not _is_online:
		return _build_fallback_summary(context.get("state", {}))

	var messages: Array = _build_summary_messages(context)
	var raw: String     = await _attempt(messages)
	if raw.is_empty():
		raw = await _attempt(messages)

	if raw.is_empty():
		_set_online(false)
		return _build_fallback_summary(context.get("state", {}))

	_set_online(true)
	var data: Variant = JSON.parse_string(raw)
	if data is Dictionary:
		var summary: String = data.get("summary", "")
		if not summary.is_empty():
			return summary
	# model may have returned a plain string for some reason
	return raw if not raw.is_empty() else _build_fallback_summary(context.get("state", {}))


# =============================================================================
# HTTP helpers
# =============================================================================

func _attempt(messages: Array) -> String:
	var body: String = JSON.stringify({
		"model"           : _model,
		"messages"        : messages,
		"max_tokens"      : MAX_TOKENS,
		"temperature"     : 0.8,
		"response_format" : {"type": "json_object"}
	})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _api_key
	])
	var err: int = _http.request(GROQ_ENDPOINT, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("AIService: HTTP request failed to start (err=%d)" % err)
		return ""
	var result: Array = await _http.request_completed
	return _parse_response(result)


func _parse_response(result: Array) -> String:
	var status: int = result[0]
	var code:   int = result[1]
	var body:   PackedByteArray = result[3]

	if status != HTTPRequest.RESULT_SUCCESS:
		push_warning("AIService: request error — HTTPRequest.Result=%d" % status)
		return ""
	if code != 200:
		var raw_body: String = body.get_string_from_utf8()
		push_warning("AIService: Groq returned HTTP %d — body: %s" % [code, raw_body.left(300)])
		return ""

	var text: String   = body.get_string_from_utf8()
	var outer: Variant = JSON.parse_string(text)
	if not (outer is Dictionary):
		return ""

	var choices: Array = outer.get("choices", [])
	if choices.is_empty():
		return ""
	var content: String = choices[0].get("message", {}).get("content", "")
	return _strip_markdown_fence(content)


## Strips ```json ... ``` or ``` ... ``` wrappers some models add around JSON.
func _strip_markdown_fence(text: String) -> String:
	var s: String = text.strip_edges()
	if s.begins_with("```"):
		# Remove first line (```json or ```)
		var first_newline: int = s.find("\n")
		if first_newline != -1:
			s = s.substr(first_newline + 1)
		# Remove trailing ```
		if s.ends_with("```"):
			s = s.left(s.length() - 3)
	return s.strip_edges()


# =============================================================================
# Validation & clamping
# =============================================================================

## Hard validation — only rejects if the structure is unfixable.
## Optional fields (time_months, effects) are filled by _sanitize_event() first.
func _validate_event(data: Dictionary) -> bool:
	# Must have top-level keys
	if not data.has_all(["event_type", "title", "description", "choices"]):
		return false
	var choices: Variant = data.get("choices", null)
	if not (choices is Array):
		return false
	if choices.size() < 2 or choices.size() > 6:
		return false
	for c: Variant in choices:
		if not (c is Dictionary):
			return false
		# Only 'text' is truly required after sanitisation
		if not c.has("text") or str(c["text"]).strip_edges().is_empty():
			return false
	return true


## Sanitise — fills missing optional fields so valid-but-incomplete responses still work.
func _sanitize_event(data: Dictionary) -> void:
	# Ensure event_type is one of the valid categories
	const VALID_TYPES: Array[String] = ["career","relationships","finance","health","family","random"]
	if data.get("event_type", "") not in VALID_TYPES:
		data["event_type"] = "random"

	# Sanitise each choice
	var choices: Variant = data.get("choices", [])
	if not (choices is Array):
		return
	for c: Variant in choices:
		if not (c is Dictionary):
			continue
		# Default time_months to 6 if missing or zero
		if not c.has("time_months") or int(c.get("time_months", 0)) <= 0:
			c["time_months"] = 6
		# Default effects to empty dict if missing or wrong type
		if not c.has("effects") or not (c["effects"] is Dictionary):
			c["effects"] = {}


func _clamp_event_effects(data: Dictionary) -> void:
	const BOUNDED: Array[String] = ["health", "happiness", "stress", "reputation", "energy"]
	for choice: Variant in data.get("choices", []):
		if not (choice is Dictionary):
			continue
		var effects: Dictionary = choice.get("effects", {})
		for key: String in effects.keys():
			var val: int = int(effects[key])
			if key == "money":
				effects[key] = clampi(val, -50000, 50000)
			elif key in BOUNDED:
				effects[key] = clampi(val, -25, 25)


# =============================================================================
# Prompt builders
# =============================================================================

func _build_event_messages(context: Dictionary) -> Array:
	var category: String = context.get("category", "random")
	var s: Dictionary    = context.get("state", {})
	var traits: Array    = context.get("traits", [])
	var recent: Array    = context.get("recent_choices", [])

	var user_msg: String = (
		"Player: %s  |  Age: %d  |  Career: %s (%s)  |  Location: %s\n"
		% [s.get("name","Player"), int(s.get("age",18)),
		   s.get("career","Student"), s.get("career_level","Entry"),
		   s.get("location","Mumbai")]
		+ "Stats: Health %d, Happiness %d, Stress %d, Reputation %d, Money ₹%d\n"
		% [int(s.get("health",70)), int(s.get("happiness",70)),
		   int(s.get("stress",30)), int(s.get("reputation",50)),
		   int(s.get("money",5000))]
		+ "Personality traits: %s\n" % (", ".join(traits) if not traits.is_empty() else "None")
		+ "Recent choices: %s\n"   % (", ".join(recent)  if not recent.is_empty()  else "None yet")
		+ "\nGenerate a realistic **%s** life event for this player." % category
	)
	return [
		{"role": "system", "content": SYSTEM_PROMPT_EVENT},
		{"role": "user",   "content": user_msg}
	]


func _build_summary_messages(context: Dictionary) -> Array:
	var s: Dictionary    = context.get("state", {})
	var events: Array    = context.get("major_events", [])
	var choices: Array   = context.get("recent_choices", [])

	var user_msg: String = (
		"Player: %s  |  Final Age: %d  |  Career: %s (%s)\n"
		% [s.get("name","Player"), int(s.get("age",18)),
		   s.get("career","Student"), s.get("career_level","Entry")]
		+ "Final Stats: Money ₹%d, Health %d, Happiness %d, Stress %d, Reputation %d\n"
		% [int(s.get("money",0)), int(s.get("health",50)),
		   int(s.get("happiness",50)), int(s.get("stress",50)),
		   int(s.get("reputation",50))]
		+ "Major life events: %s\n"  % (", ".join(events.slice(-8))  if not events.is_empty()  else "None recorded")
		+ "Notable choices: %s\n"    % (", ".join(choices.slice(-8)) if not choices.is_empty() else "None recorded")
		+ "\nWrite a poetic, reflective life summary for this player."
	)
	return [
		{"role": "system", "content": SYSTEM_PROMPT_SUMMARY},
		{"role": "user",   "content": user_msg}
	]


# =============================================================================
# Fallback summary — used when API is unavailable. Never returns empty.
# =============================================================================
func _build_fallback_summary(state: Dictionary) -> String:
	# Try fallback_summary.json template first
	var path: String = "res://data/fallback_summary.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				file.close()
				return _fill_template(json.data.get("template", ""), state)
			file.close()

	# Inline last-resort fallback
	var traits_list: Array = state.get("personality_traits", {}).keys()
	var traits_str: String = ", ".join(traits_list) if not traits_list.is_empty() else "resilient"
	return (
		"%s lived a remarkable life, reaching the age of %d. "
		% [state.get("player_name", "You"), int(state.get("age", 18))]
		+ "Working as a %s and known for being %s, "
		% [state.get("career", "free spirit"), traits_str]
		+ "they faced countless choices that shaped who they became. "
		+ "Their journey — full of triumphs and trials — was uniquely and beautifully their own."
	)


func _fill_template(template: String, state: Dictionary) -> String:
	var traits_list: Array = state.get("personality_traits", {}).keys()
	var events_list: Array = state.get("major_life_events", [])
	return (
		template
		.replace("{name}",   state.get("player_name", "You"))
		.replace("{age}",    str(int(state.get("age", 18))))
		.replace("{career}", state.get("career", "adventurer"))
		.replace("{money}",  "₹" + str(int(state.get("money", 0))))
		.replace("{traits}", ", ".join(traits_list) if not traits_list.is_empty() else "adaptable")
		.replace("{events}", ", ".join(events_list.slice(-5)) if not events_list.is_empty() else "many memorable moments")
	)


# =============================================================================
# Status helper
# =============================================================================
func _set_online(online: bool) -> void:
	if _is_online != online:
		_is_online = online
		ai_status_changed.emit(online)
