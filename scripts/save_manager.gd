# save_manager.gd
# =============================================================================
# Autoload Node that handles JSON-based save and load of full GameState.
# save_game.json is written to user:// (OS-specific app data directory).
# =============================================================================
extends Node

const SAVE_PATH: String = "user://save_game.json"


# =============================================================================
# save_game() — serializes GameState to user://save_game.json.
# Returns true on success.
# =============================================================================
func save_game() -> bool:
	var data: Dictionary  = GameState.to_dict()
	var json_str: String  = JSON.stringify(data, "\t")

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: Failed to open '%s' for writing. Error: %s"
			% [SAVE_PATH, FileAccess.get_open_error()])
		return false

	file.store_string(json_str)
	file.close()
	return true


# =============================================================================
# load_game() — reads and deserializes save_game.json into GameState.
# Returns true on success.
# =============================================================================
func load_game() -> bool:
	if not has_save():
		push_warning("SaveManager: No save file found at '%s'." % SAVE_PATH)
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: Failed to open '%s' for reading. Error: %s"
			% [SAVE_PATH, FileAccess.get_open_error()])
		return false

	var raw: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var err: int = json.parse(raw)
	if err != OK:
		push_error("SaveManager: JSON parse error in save file: %s" % json.get_error_message())
		return false

	if not json.data is Dictionary:
		push_error("SaveManager: Save file root is not a Dictionary.")
		return false

	GameState.from_dict(json.data)
	return true


# =============================================================================
# has_save() — used by main_menu.gd to gate the Continue button.
# =============================================================================
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# =============================================================================
# delete_save() — called on New Game when an old save exists.
# =============================================================================
func delete_save() -> void:
	if has_save():
		var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		if err != OK:
			push_error("SaveManager: Failed to delete save file.")
