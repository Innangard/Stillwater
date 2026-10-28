extends Node
## Sets up the input map programmatically on startup.
## Runs before any scene loads (first autoload).
## Rebindings can later be applied via a settings menu without editing project.godot.
##
## Also owns the global fullscreen toggle (F11 / Alt+Enter) AND runtime
## enforcement of the content-stretch settings. Living here keeps display-mode
## handling in one place — same autoload that owns the input map.
##
## Why enforce stretch settings at runtime when they're set in project.godot?
## Two reasons:
##   1. Godot 4 strips display settings from project.godot on editor save when
##      they match the engine default. So a setting like `stretch/scale_mode=
##      "fractional"` might silently disappear because "fractional" is the
##      default — and you can't tell from looking at project.godot what's
##      actually configured vs what's defaulting.
##   2. The Window's content_scale_* properties (set via this script) override
##      whatever was loaded from project.godot, so we get a single, explicit
##      source of truth that's visible in this file.

# Process even when the tree is paused, so fullscreen toggle works from any
# menu state (inventory, pause, dialogue, death screen, etc).
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_add_key_action("move_up",      [KEY_W, KEY_UP])
	_add_key_action("move_down",    [KEY_S, KEY_DOWN])
	_add_key_action("move_left",    [KEY_A, KEY_LEFT])
	_add_key_action("move_right",   [KEY_D, KEY_RIGHT])
	_add_key_action("dash",         [KEY_SPACE])
	_add_key_action("sneak",        [KEY_SHIFT])
	_add_key_action("interact",     [KEY_E])
	_add_key_action("swap_weapons", [KEY_Q])
	_add_key_action("toggle_runes",    [KEY_R])
	_add_key_action("pause",        [KEY_ESCAPE])
	_add_key_action("toggle_inventory", [KEY_I])
	_add_key_action("toggle_map",       [KEY_M, KEY_TAB])
	_add_key_action("toggle_quest_log", [KEY_J])
	_add_key_action("toggle_kennings",  [KEY_K])
	_add_key_action("toggle_fullscreen", [KEY_F11])
	_add_mouse_action("attack_melee",  MOUSE_BUTTON_LEFT)
	_add_mouse_action("attack_ranged", MOUSE_BUTTON_RIGHT)

	_enforce_content_scale()


## Apply content-scale settings directly on the main Window. Godot reads
## these from project.godot at startup, but setting them here is both a
## fallback (in case the project.godot values are stripped) and a single
## visible source of truth.
##
## CONTENT_SCALE_MODE_CANVAS_ITEMS: 2D CanvasItems scale smoothly with the
##   window, preserving the rendering resolution as a "design" size. Pixel
##   sprites stay crisp; layouts (HUD, menus) scale with the window.
##
## CONTENT_SCALE_ASPECT_EXPAND: the viewport expands to fill the window in
##   both dimensions. Wider windows reveal more world horizontally; taller
##   windows reveal more vertically. NO LETTERBOXING. This is the key
##   property — without it, a 16:10 or 21:9 monitor in fullscreen would
##   get black bars to preserve the 16:9 aspect.
##
## content_scale_size: the "design resolution" used as the reference for
##   scaling calculations. 1280x720 matches our viewport_width/height in
##   project.godot.
func _enforce_content_scale() -> void:
	var w: Window = get_window()
	if w == null:
		return
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(1280, 720)
	w.content_scale_factor = 1.0


# Global fullscreen toggle. Handled in _input (not _unhandled_input) so it
# fires even when a UI control has focus — players expect F11 to always work.
# Alt+Enter is handled separately because it's a chord, not an action.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	# Alt+Enter chord — only fire on the Enter keydown, not on Alt itself,
	# and only on the initial press (echo == false) so holding Enter doesn't
	# flicker the window mode.
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo \
				and key_event.alt_pressed \
				and key_event.keycode == KEY_ENTER:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()


## Toggle between maximized-windowed and borderless fullscreen.
##
## Why MAXIMIZED instead of WINDOWED as the "out" state? Because the
## initial window mode (project.godot) is MAXIMIZED, and switching back
## to a tiny 1280x720 windowed mode after going fullscreen feels wrong —
## the user would have to manually maximize the window again every time
## they alt-tabbed. Maximized → fullscreen → maximized is the symmetric
## toggle they actually want.
##
## Why WINDOW_MODE_FULLSCREEN (borderless) instead of EXCLUSIVE_FULLSCREEN?
## For a 2D game, borderless fullscreen is universally better:
##   - Faster alt-tabbing (the OS doesn't have to change video modes)
##   - Doesn't change the monitor's resolution
##   - Works correctly across multi-monitor setups
##   - No "monitor goes black for a second" flicker on toggle
## EXCLUSIVE_FULLSCREEN is for 3D games rendering at a non-native res.
func _toggle_fullscreen() -> void:
	var current_mode := DisplayServer.window_get_mode()
	var is_fullscreen: bool = (
		current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# Param renamed from `name` because Node has a built-in `name` property —
# Godot warns when local names shadow base-class members, even in static
# free functions like these. `action_name` is unambiguous.
func _add_key_action(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action_name, ev)


# `button` typed as MouseButton (enum) rather than int so the assignment
# to `ev.button_index` (also MouseButton-typed) doesn't warn.
func _add_mouse_action(action_name: String, button: MouseButton) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action_name, ev)
