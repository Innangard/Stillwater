extends CanvasLayer
## In-game pause menu. Opens on Esc when no other menu is open and the
## tree isn't already paused. Three actions: resume, save, save & quit
## to title.
##
## ── Why an autoload? ────────────────────────────────────────────────────
## Same pattern the other menu UIs follow (InventoryUI, CraftingUI, etc.):
## the pause menu needs to be available regardless of which world scene
## the player is in, and the autoload keeps a single instance alive
## across scene transitions. The title screen scene specifically skips
## opening this — see _can_open below — because Esc on the title screen
## has its own meaning.
##
## ── Esc disambiguation ──────────────────────────────────────────────────
## "pause" maps to KEY_ESCAPE, and several other UIs also consume it
## (Inventory, Kennings, Quests, Crafting, Map, Dialogue all close on
## Esc). We have to NOT compete with those — opening the pause menu
## while one of them is up would create a confusing double-menu stack.
## Solution: gate open on "no menu visible AND tree not paused." Every
## existing menu pauses the tree when it opens, so that single check
## handles all of them at once.
##
## NOTE: No class_name — registered as autoload "PauseMenu".

const COLOR_DIM_OVERLAY  := Color(0.0, 0.0, 0.0, 0.55)
const COLOR_PANEL_BG     := Color(0.10, 0.09, 0.12, 0.96)
const COLOR_PANEL_BORDER := Color(0.55, 0.50, 0.42, 0.85)
const COLOR_TITLE_GOLD   := Color(0.95, 0.85, 0.40)
const COLOR_BODY         := Color(0.82, 0.80, 0.74)
const COLOR_DIM          := Color(0.55, 0.52, 0.46)
const COLOR_DANGER       := Color(0.85, 0.40, 0.40)
const COLOR_SLOT_BORDER  := Color(0.40, 0.38, 0.34, 0.70)
const COLOR_SLOT_BORDER_ACTIVE := Color(0.95, 0.85, 0.40, 0.95)
const COLOR_SLOT_BG_HOVER := Color(0.18, 0.16, 0.20, 0.96)

var _root: Control
var _panel: PanelContainer
var _status_label: Label

# Brief on-screen acknowledgement after the Save button is pressed.
# Tweens away after a second, so the player has confirmation without
# the menu growing a permanent status row.
var _ack_tween: Tween


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	# Layer 9 — above the HUD (5) and dialog (8), below SceneTransition
	# (50) so a fade-out covers the pause menu cleanly during the quit-
	# to-title transition. Below the inventory/quests menus (10+ via
	# their build), which we WON'T overlap with anyway because we gate
	# _can_open on those being closed.
	layer = 9
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Block clicks falling through to the world. STOP would also block
	# clicks from reaching our own buttons, so use PASS — only the dim
	# rect actually swallows clicks; the rest goes through to children.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dim background — lets the world stay visible behind the panel
	# (you can see where you are while paused), but darkens it enough
	# that the panel is the clear focal point.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = COLOR_DIM_OVERLAY
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	# Centered panel.
	var center_h := HBoxContainer.new()
	center_h.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_h.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(center_h)

	var center_v := VBoxContainer.new()
	center_v.alignment = BoxContainer.ALIGNMENT_CENTER
	center_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_h.add_child(center_v)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(420, 0)
	_panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	center_v.add_child(_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 32)
	pad.add_theme_constant_override("margin_right", 32)
	pad.add_theme_constant_override("margin_top", 28)
	pad.add_theme_constant_override("margin_bottom", 28)
	_panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	pad.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_TITLE_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(COLOR_TITLE_GOLD.r, COLOR_TITLE_GOLD.g, COLOR_TITLE_GOLD.b, 0.40)
	vbox.add_child(sep)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer1)

	# Buttons.
	var resume := _make_button("Resume", COLOR_BODY, COLOR_TITLE_GOLD)
	resume.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume)

	var save := _make_button("Save", COLOR_BODY, COLOR_TITLE_GOLD)
	save.pressed.connect(_on_save_pressed)
	vbox.add_child(save)

	var quit := _make_button("Save & Quit to Title", COLOR_DANGER, COLOR_TITLE_GOLD)
	quit.pressed.connect(_on_quit_to_title_pressed)
	vbox.add_child(quit)

	# Status row — invisible until a save fires, then shows briefly.
	# Keeps the panel layout stable (label is always there, just empty).
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", COLOR_DIM)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size = Vector2(0, 18)
	vbox.add_child(_status_label)

	var hint := Label.new()
	hint.text = "[Esc] to resume"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COLOR_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


# ============================================================================
# OPEN / CLOSE
# ============================================================================

## Permissions gate. We refuse to open if:
##   - The pause menu itself is already visible (no-op via _can_open in
##     _input — though we double-check here defensively).
##   - The tree is already paused (some other menu has it).
##   - The current scene is the title screen (Esc has its own meaning
##     there — back out of sub-views).
##   - No save slot is active (we're between sessions; opening would
##     let the player "save" with no slot to write to). In practice
##     this should be impossible during gameplay, but defensive.
func _can_open() -> bool:
	if visible:
		return false
	if get_tree().paused:
		return false
	if SaveManager.current_slot <= 0:
		return false
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return false
	if current_scene.scene_file_path == SaveManager.TITLE_SCENE_PATH:
		return false
	return true


func _open() -> void:
	visible = true
	_status_label.text = ""
	get_tree().paused = true


func _close() -> void:
	visible = false
	get_tree().paused = false


# Input — listen for Esc to open AND to close ourselves. Other UIs
# handle their own Esc-closes, so we only fire here when nothing else
# has consumed it.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if visible:
		_close()
		get_viewport().set_input_as_handled()
	elif _can_open():
		_open()
		get_viewport().set_input_as_handled()


# ============================================================================
# BUTTON HANDLERS
# ============================================================================

func _on_resume_pressed() -> void:
	_close()


func _on_save_pressed() -> void:
	# Save while paused — RunState/GameState/player position all snapshot
	# fine in a paused state because nothing's moving. The auto-save on
	# scene transition takes precedence over a manual save in terms of
	# "this is the canonical save point," but giving the player an
	# explicit save button removes the worry of "will my progress stick
	# if I close the window right now?"
	var ok: bool = SaveManager.save_game()
	_show_status("Saved." if ok else "Save failed.", ok)


func _on_quit_to_title_pressed() -> void:
	# Hide ourselves BEFORE the scene swap so the title screen comes up
	# clean. SaveManager.quit_to_title unpauses the tree and changes
	# scene, but our `visible` flag would otherwise persist across the
	# change (autoload, single instance) and the player would briefly
	# see the pause panel layered over the title screen.
	visible = false
	SaveManager.quit_to_title()


# ============================================================================
# UI HELPERS
# ============================================================================

func _make_button(text: String, color: Color, hover_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.add_theme_color_override("font_pressed_color", hover_color)
	btn.add_theme_color_override("font_focus_color", hover_color)
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
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover.duplicate())
	return btn


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


## Brief ack message that fades out. Tweens use unscaled time (process
## mode is ALWAYS on the autoload) so it works while paused.
func _show_status(text: String, ok: bool) -> void:
	_status_label.add_theme_color_override(
		"font_color",
		COLOR_BODY if ok else COLOR_DANGER,
	)
	_status_label.text = text
	_status_label.modulate.a = 1.0
	if _ack_tween != null and _ack_tween.is_valid():
		_ack_tween.kill()
	_ack_tween = create_tween()
	_ack_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_ack_tween.tween_interval(1.4)
	_ack_tween.tween_property(_status_label, "modulate:a", 0.0, 0.5)
