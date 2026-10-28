extends Control
## The first scene shown on launch. Lets the player pick one of three
## save slots:
##   - Empty slot      → opens the difficulty picker → new game
##   - Existing slot   → shows Continue / Delete buttons
##   - Corrupted slot  → grayed out, deletion still allowed
##
## Visual language: Norse-dark / gold-accent, same constants used by
## the in-game menus (inventory, kennings, quests, HUD) — landing on
## the title shouldn't feel like a different game from the gameplay
## that follows. Programmatic UI to match the rest of the project's
## convention (every other menu is built in code, scene file is a stub).

# --- Palette — mirrors HUD / inventory_ui / kennings_ui. ---
const COLOR_BG_OUTER     := Color(0.05, 0.05, 0.07, 1.0)
const COLOR_PANEL_BG     := Color(0.10, 0.09, 0.12, 0.94)
const COLOR_PANEL_BORDER := Color(0.55, 0.50, 0.42, 0.85)
const COLOR_SLOT_BG      := Color(0.13, 0.12, 0.15, 0.95)
const COLOR_SLOT_BG_EMPTY := Color(0.09, 0.08, 0.11, 0.85)
const COLOR_SLOT_BG_HOVER := Color(0.18, 0.16, 0.20, 0.96)
const COLOR_SLOT_BG_CORRUPT := Color(0.18, 0.10, 0.10, 0.85)
const COLOR_SLOT_BORDER  := Color(0.40, 0.38, 0.34, 0.70)
const COLOR_SLOT_BORDER_ACTIVE := Color(0.95, 0.85, 0.40, 0.95)
const COLOR_TITLE_GOLD   := Color(0.95, 0.85, 0.40)
const COLOR_BODY         := Color(0.82, 0.80, 0.74)
const COLOR_DIM          := Color(0.55, 0.52, 0.46)
const COLOR_FLAVOR       := Color(0.62, 0.58, 0.52)
const COLOR_DANGER       := Color(0.85, 0.35, 0.30)
const COLOR_DANGER_HOVER := Color(1.00, 0.50, 0.40)
const COLOR_DIFF_EASY    := Color(0.55, 0.80, 0.55)
const COLOR_DIFF_NORMAL  := Color(0.90, 0.80, 0.45)
const COLOR_DIFF_HARD    := Color(0.85, 0.40, 0.40)

# --- Layout sizing — tuned so the title page reads at a glance and
# the three slots feel like the main visual anchor of the screen. ---
const PANEL_MAX_WIDTH := 720.0
const PANEL_PADDING := 36.0
const SLOT_HEIGHT := 96.0
const SLOT_GAP := 14.0
const BUTTON_HEIGHT := 44.0

# --- Build state — current view ---
enum View { SLOTS, NEW_GAME_DIFFICULTY, CONFIRM_DELETE }
var _view: int = View.SLOTS
var _focused_slot: int = 0  # Set when in NEW_GAME_DIFFICULTY or CONFIRM_DELETE

# --- UI handles ---
var _root_vbox: VBoxContainer
var _content_vbox: VBoxContainer


func _ready() -> void:
	# The title screen sits OUTSIDE the autoload Control layer, so any
	# residual pause from a previous session's "Save & Quit to Title"
	# would leave us stuck. quit_to_title already clears this, but we
	# unpause defensively in case the player landed here some other way.
	get_tree().paused = false
	# Make the screen focus-grabber-friendly: pressing Esc on slot view
	# does nothing (no parent scene to back out to); inside a sub-view
	# Esc returns to slot list.
	_build_background()
	_build_panel()
	_rebuild()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

## Full-screen dark background. Could be replaced with a textured
## image later — for now a flat dark fill matches the in-game menu
## panels' look and reads as "nothing else to look at, focus on the
## slot list."
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG_OUTER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## Center-anchored panel container, max-width clamped, that holds the
## title + slot list (or sub-view contents). The same panel + border
## stylebox the other menus use is rebuilt here inline so visually
## you read "this is the menu language" the instant the title fades in.
func _build_panel() -> void:
	# Outer centering container — full-rect anchor, but with margins so
	# the panel never touches the screen edges even at small windows.
	var center := MarginContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_theme_constant_override("margin_left", 40)
	center.add_theme_constant_override("margin_right", 40)
	center.add_theme_constant_override("margin_top", 40)
	center.add_theme_constant_override("margin_bottom", 40)
	add_child(center)

	# A vertical centerer holding the panel. The panel itself uses
	# size_flags to grow up to PANEL_MAX_WIDTH; PanelContainer respects
	# child min sizes, so a content rebuild reshapes the panel cleanly.
	var v_center := VBoxContainer.new()
	v_center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v_center)

	var h_center := HBoxContainer.new()
	h_center.alignment = BoxContainer.ALIGNMENT_CENTER
	v_center.add_child(h_center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_MAX_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	h_center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", int(PANEL_PADDING))
	pad.add_theme_constant_override("margin_right", int(PANEL_PADDING))
	pad.add_theme_constant_override("margin_top", int(PANEL_PADDING))
	pad.add_theme_constant_override("margin_bottom", int(PANEL_PADDING))
	panel.add_child(pad)

	_root_vbox = VBoxContainer.new()
	_root_vbox.add_theme_constant_override("separation", 18)
	pad.add_child(_root_vbox)

	# Title header — stays for every view. The content below it changes
	# based on _view.
	var title := Label.new()
	title.text = "UnLife"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", COLOR_TITLE_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The Island of Dead"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", COLOR_FLAVOR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vbox.add_child(subtitle)

	# Thin gold separator line under the title — same accent the in-
	# game menus use as their visual signature.
	var sep := _make_separator()
	_root_vbox.add_child(sep)

	# Content container — replaced wholesale on view changes.
	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", int(SLOT_GAP))
	_root_vbox.add_child(_content_vbox)


# ============================================================================
# VIEW SWITCHING
# ============================================================================

func _rebuild() -> void:
	# Wipe content children, repopulate per current view. Simpler than
	# managing visibility on three separate containers and is fast at
	# this scale (a few buttons).
	for child in _content_vbox.get_children():
		child.queue_free()

	match _view:
		View.SLOTS:
			_build_slot_list()
		View.NEW_GAME_DIFFICULTY:
			_build_difficulty_picker()
		View.CONFIRM_DELETE:
			_build_delete_confirm()


# ============================================================================
# VIEW: SLOT LIST
# ============================================================================

func _build_slot_list() -> void:
	var heading := Label.new()
	heading.text = "Choose your tale"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", COLOR_BODY)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(heading)

	for slot in range(1, SaveManager.NUM_SLOTS + 1):
		_content_vbox.add_child(_make_slot_card(slot))

	# Quit footer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_content_vbox.add_child(spacer)

	var quit_btn := _make_text_button("Quit Game", COLOR_DIM, COLOR_BODY)
	quit_btn.pressed.connect(_on_quit_pressed)
	_content_vbox.add_child(quit_btn)


## A single slot row. Three shapes: empty (call to action), populated
## (summary + Continue/Delete), corrupted (warning + Delete only).
func _make_slot_card(slot: int) -> Control:
	var summary: Dictionary = SaveManager.get_slot_summary(slot)
	var is_empty: bool = summary.is_empty()
	var is_corrupt: bool = summary.get("corrupt", false)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, SLOT_HEIGHT)
	var bg: Color = COLOR_SLOT_BG_EMPTY if is_empty else (
		COLOR_SLOT_BG_CORRUPT if is_corrupt else COLOR_SLOT_BG
	)
	card.add_theme_stylebox_override("panel", _make_slot_stylebox(bg))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	# Pad inside the card so labels don't ride the border.
	var inner_pad := MarginContainer.new()
	inner_pad.add_theme_constant_override("margin_left", 16)
	inner_pad.add_theme_constant_override("margin_right", 16)
	inner_pad.add_theme_constant_override("margin_top", 12)
	inner_pad.add_theme_constant_override("margin_bottom", 12)
	card.add_child(inner_pad)
	inner_pad.add_child(row)

	# Left column: slot number + descriptive content.
	var left_v := VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 2)
	row.add_child(left_v)

	var slot_num := Label.new()
	slot_num.text = "Slot %d" % slot
	slot_num.add_theme_font_size_override("font_size", 14)
	slot_num.add_theme_color_override("font_color", COLOR_DIM)
	left_v.add_child(slot_num)

	if is_empty:
		var line1 := Label.new()
		line1.text = "[ Empty ]"
		line1.add_theme_font_size_override("font_size", 22)
		line1.add_theme_color_override("font_color", COLOR_BODY)
		left_v.add_child(line1)
		var line2 := Label.new()
		line2.text = "Begin a new tale"
		line2.add_theme_font_size_override("font_size", 13)
		line2.add_theme_color_override("font_color", COLOR_FLAVOR)
		left_v.add_child(line2)
	elif is_corrupt:
		var line1 := Label.new()
		line1.text = "[ Corrupted save ]"
		line1.add_theme_font_size_override("font_size", 22)
		line1.add_theme_color_override("font_color", COLOR_DANGER)
		left_v.add_child(line1)
		var line2 := Label.new()
		line2.text = "Version mismatch — delete to reclaim this slot"
		line2.add_theme_font_size_override("font_size", 13)
		line2.add_theme_color_override("font_color", COLOR_DIM)
		left_v.add_child(line2)
	else:
		var line1 := Label.new()
		line1.text = String(summary.get("scene_display", "Unknown"))
		line1.add_theme_font_size_override("font_size", 20)
		line1.add_theme_color_override("font_color", COLOR_BODY)
		left_v.add_child(line1)

		var diff_int: int = int(summary.get("difficulty", DifficultySettings.Difficulty.NORMAL))
		var diff_color: Color = _color_for_difficulty(diff_int)
		var diff_name: String = DifficultySettings.display_name(diff_int)
		var deaths: int = int(summary.get("death_count", 0))
		var currency: int = int(summary.get("soul_currency", 0))
		var cur_hp: float = float(summary.get("current_health", 0.0))
		var max_hp: float = float(summary.get("max_health", 1.0))
		var timestamp: int = int(summary.get("timestamp", 0))
		# Format a relative-feeling timestamp. Full datetime is overkill
		# for a slot summary; "1d 3h ago" reads at a glance. Falls back
		# to "—" if there's no timestamp recorded (legacy save).
		var when_text: String = _format_relative_time(timestamp) if timestamp > 0 else "—"

		var line2 := RichTextLabel.new()
		line2.bbcode_enabled = true
		line2.fit_content = true
		line2.scroll_active = false
		line2.custom_minimum_size = Vector2(0, 20)
		line2.add_theme_font_size_override("normal_font_size", 13)
		line2.add_theme_color_override("default_color", COLOR_DIM)
		line2.text = "[color=#%s]%s[/color]   •   %d souls   •   %d %s   •   HP %d/%d   •   %s" % [
			diff_color.to_html(false),
			diff_name,
			currency,
			deaths,
			"death" if deaths == 1 else "deaths",
			int(cur_hp),
			int(max_hp),
			when_text,
		]
		left_v.add_child(line2)

	# Right column: action buttons.
	var right_v := VBoxContainer.new()
	right_v.alignment = BoxContainer.ALIGNMENT_CENTER
	right_v.add_theme_constant_override("separation", 6)
	row.add_child(right_v)

	if is_empty:
		var new_btn := _make_text_button("New Game", COLOR_BODY, COLOR_TITLE_GOLD)
		new_btn.custom_minimum_size = Vector2(140, BUTTON_HEIGHT - 6)
		new_btn.pressed.connect(_on_new_game_pressed.bind(slot))
		right_v.add_child(new_btn)
	elif is_corrupt:
		var del_btn := _make_text_button("Delete", COLOR_DANGER, COLOR_DANGER_HOVER)
		del_btn.custom_minimum_size = Vector2(140, BUTTON_HEIGHT - 6)
		del_btn.pressed.connect(_on_delete_pressed.bind(slot))
		right_v.add_child(del_btn)
	else:
		var cont_btn := _make_text_button("Continue", COLOR_BODY, COLOR_TITLE_GOLD)
		cont_btn.custom_minimum_size = Vector2(140, BUTTON_HEIGHT - 6)
		cont_btn.pressed.connect(_on_continue_pressed.bind(slot))
		right_v.add_child(cont_btn)

		var del_btn := _make_text_button("Delete", COLOR_DIM, COLOR_DANGER_HOVER)
		del_btn.custom_minimum_size = Vector2(140, 28)
		del_btn.add_theme_font_size_override("font_size", 12)
		del_btn.pressed.connect(_on_delete_pressed.bind(slot))
		right_v.add_child(del_btn)

	return card


# ============================================================================
# VIEW: DIFFICULTY PICKER
# ============================================================================

func _build_difficulty_picker() -> void:
	var heading := Label.new()
	heading.text = "Choose your hardship — Slot %d" % _focused_slot
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", COLOR_BODY)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(heading)

	var subtitle := Label.new()
	subtitle.text = "This choice persists for the life of this save."
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", COLOR_FLAVOR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_content_vbox.add_child(spacer)

	for diff in [
		DifficultySettings.Difficulty.EASY,
		DifficultySettings.Difficulty.NORMAL,
		DifficultySettings.Difficulty.HARD,
	]:
		_content_vbox.add_child(_make_difficulty_card(diff))

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	_content_vbox.add_child(spacer2)

	var back := _make_text_button("Back", COLOR_DIM, COLOR_BODY)
	back.pressed.connect(_on_back_to_slots)
	_content_vbox.add_child(back)


func _make_difficulty_card(diff: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 76)
	card.add_theme_stylebox_override("panel", _make_slot_stylebox(COLOR_SLOT_BG))

	var inner_pad := MarginContainer.new()
	inner_pad.add_theme_constant_override("margin_left", 16)
	inner_pad.add_theme_constant_override("margin_right", 16)
	inner_pad.add_theme_constant_override("margin_top", 10)
	inner_pad.add_theme_constant_override("margin_bottom", 10)
	card.add_child(inner_pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	inner_pad.add_child(row)

	var left_v := VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 2)
	row.add_child(left_v)

	var name_label := Label.new()
	name_label.text = DifficultySettings.display_name(diff)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", _color_for_difficulty(diff))
	left_v.add_child(name_label)

	var flavor := Label.new()
	flavor.text = DifficultySettings.flavor_text(diff)
	flavor.add_theme_font_size_override("font_size", 13)
	flavor.add_theme_color_override("font_color", COLOR_FLAVOR)
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.add_child(flavor)

	var choose_btn := _make_text_button("Choose", COLOR_BODY, COLOR_TITLE_GOLD)
	choose_btn.custom_minimum_size = Vector2(120, BUTTON_HEIGHT - 6)
	choose_btn.pressed.connect(_on_difficulty_chosen.bind(diff))
	row.add_child(choose_btn)

	return card


# ============================================================================
# VIEW: DELETE CONFIRM
# ============================================================================

func _build_delete_confirm() -> void:
	var heading := Label.new()
	heading.text = "Delete Slot %d?" % _focused_slot
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", COLOR_DANGER)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(heading)

	var msg := Label.new()
	msg.text = "This will permanently erase the save. There is no undo."
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_color", COLOR_BODY)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_vbox.add_child(msg)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	_content_vbox.add_child(spacer)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_content_vbox.add_child(row)

	var cancel := _make_text_button("Cancel", COLOR_BODY, COLOR_TITLE_GOLD)
	cancel.custom_minimum_size = Vector2(160, BUTTON_HEIGHT)
	cancel.pressed.connect(_on_back_to_slots)
	row.add_child(cancel)

	var confirm := _make_text_button("Yes, delete", COLOR_DANGER, COLOR_DANGER_HOVER)
	confirm.custom_minimum_size = Vector2(160, BUTTON_HEIGHT)
	confirm.pressed.connect(_on_delete_confirmed)
	row.add_child(confirm)


# ============================================================================
# BUTTON HANDLERS
# ============================================================================

func _on_new_game_pressed(slot: int) -> void:
	_focused_slot = slot
	_view = View.NEW_GAME_DIFFICULTY
	_rebuild()


func _on_continue_pressed(slot: int) -> void:
	# Load and transition. SaveManager handles all the state plumbing.
	SaveManager.start_loaded_slot(slot)


func _on_delete_pressed(slot: int) -> void:
	_focused_slot = slot
	_view = View.CONFIRM_DELETE
	_rebuild()


func _on_delete_confirmed() -> void:
	SaveManager.delete_save(_focused_slot)
	_focused_slot = 0
	_view = View.SLOTS
	_rebuild()


func _on_difficulty_chosen(diff: int) -> void:
	# Starts the game in the focused slot at the chosen difficulty.
	SaveManager.start_new_game(_focused_slot, diff)


func _on_back_to_slots() -> void:
	_focused_slot = 0
	_view = View.SLOTS
	_rebuild()


func _on_quit_pressed() -> void:
	get_tree().quit()


# Esc returns to slot list from sub-views (delete confirm, difficulty
# picker). Doing nothing on the slot view itself — there's no parent
# view to back out to, and intercepting Esc with a "really quit?"
# prompt would be over-engineered for what it's worth.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _view != View.SLOTS:
		_on_back_to_slots()
		get_viewport().set_input_as_handled()


# ============================================================================
# STYLE HELPERS
# ============================================================================

func _make_panel_stylebox() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL_BG
	sb.border_color = COLOR_PANEL_BORDER
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


func _make_slot_stylebox(bg: Color) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = COLOR_SLOT_BORDER
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb


func _make_separator() -> Control:
	# Thin gold underline. ColorRect not HSeparator so the color matches
	# the gold accent exactly without theme-override gymnastics.
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(COLOR_TITLE_GOLD.r, COLOR_TITLE_GOLD.g, COLOR_TITLE_GOLD.b, 0.45)
	return sep


## Builds a Button with custom color states. Buttons are used a lot
## here and styling them via theme overrides per-button is verbose;
## this centralizes the pattern.
func _make_text_button(text: String, color: Color, hover_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.add_theme_color_override("font_pressed_color", hover_color)
	btn.add_theme_color_override("font_focus_color", hover_color)
	# Subtle hoverable stylebox — dark fill with a hover state, no
	# rounded corners (matches the in-game menu button feel). We define
	# all four state styleboxes so the button never falls back to the
	# default Godot bevel.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.12, 0.15, 0.92)
	normal.border_color = COLOR_SLOT_BORDER
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COLOR_SLOT_BG_HOVER
	hover.border_color = COLOR_SLOT_BORDER_ACTIVE
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.20, 0.18, 0.14, 0.96)
	pressed.border_color = COLOR_TITLE_GOLD
	var focus := hover.duplicate() as StyleBoxFlat
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	return btn


func _color_for_difficulty(diff: int) -> Color:
	match diff:
		DifficultySettings.Difficulty.EASY:   return COLOR_DIFF_EASY
		DifficultySettings.Difficulty.NORMAL: return COLOR_DIFF_NORMAL
		DifficultySettings.Difficulty.HARD:   return COLOR_DIFF_HARD
	return COLOR_DIM


## "1d 3h ago" style relative time. Strikes the balance between
## "useful at a glance" and "doesn't need a locale-aware date library."
## Just past a week reverts to a precise date so old saves still read
## informatively (otherwise "31d ago" gets noisy fast).
func _format_relative_time(unix_ts: int) -> String:
	var now: int = int(Time.get_unix_time_from_system())
	var delta: int = max(0, now - unix_ts)
	if delta < 60:
		return "just now"
	if delta < 3600:
		return "%dm ago" % (delta / 60.0)
	if delta < 86400:
		var hours: int = delta / 3600
		var mins: int = (delta % 3600) / 60
		if mins > 0:
			return "%dh %dm ago" % [hours, mins]
		return "%dh ago" % hours
	if delta < 86400 * 7:
		var days: int = delta / 86400
		var rem_hours: int = (delta % 86400) / 3600
		if rem_hours > 0:
			return "%dd %dh ago" % [days, rem_hours]
		return "%dd ago" % days
	# Older than a week — fall back to a date string. Time.get_datetime_dict
	# returns local time; format as YYYY-MM-DD which is unambiguous.
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix_ts)
	return "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
