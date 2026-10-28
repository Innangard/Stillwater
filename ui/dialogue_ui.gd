extends CanvasLayer
## Autoloaded dialogue display. Public API:
##   DialogueUI.show_dialogue(dialogue, station_name, recipes)
##
## Shows lines one at a time at the bottom of the screen. Pauses the game.
## Clicking ANYWHERE advances to the next line; after the last line the
## dialog closes.
##
## If station_name is non-empty, a craft/shop button appears from the
## very first line. The player can click it at any time to open the
## CraftingUI without finishing the dialogue. Closing the CraftingUI also
## closes the dialogue.
##
## NOTE: No class_name (autoload "DialogueUI").

signal dialogue_finished

var _root: Control
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _bottom_row: HBoxContainer
var _advance_hint: Label
var _craft_btn: Button

var _current_dialogue: Dialogue = null
var _station_name: String = ""
var _station_recipes: Array[Recipe] = []
var _line_index: int = 0
var _waiting_for_crafting_close: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 8
	_build_ui()
	visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _waiting_for_crafting_close:
		return

	var is_advance_input := (
		event.is_action_pressed("interact")
		or event.is_action_pressed("ui_accept")
		or (event is InputEventMouseButton
			and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	)
	if not is_advance_input:
		return

	# If click is on the craft button, let the Button handle it.
	if _craft_btn.visible and event is InputEventMouseButton:
		var btn_rect: Rect2 = _craft_btn.get_global_rect()
		if btn_rect.has_point((event as InputEventMouseButton).position):
			return

	# Advance dialogue or close.
	_advance()
	get_viewport().set_input_as_handled()


# ---------- Public ----------

func show_dialogue(dialogue: Dialogue, station_name: String = "", recipes: Array[Recipe] = []) -> void:
	var has_dialogue: bool = dialogue != null and not dialogue.lines.is_empty()
	var has_station: bool = station_name != ""
	if not has_dialogue and not has_station:
		return

	_current_dialogue = dialogue
	_station_name = station_name
	_station_recipes = recipes
	_line_index = 0
	_waiting_for_crafting_close = false
	visible = true
	_panel.visible = true
	get_tree().paused = true

	# Station button — visible from the start if this NPC has a station.
	if has_station:
		_craft_btn.text = station_name
		_craft_btn.visible = true
	else:
		_craft_btn.visible = false

	if has_dialogue:
		_render_current_line()
	else:
		# Station-only NPC with no dialogue lines.
		_speaker_label.visible = false
		_text_label.text = ""
		_advance_hint.text = "[Click elsewhere] leave"


# ---------- UI ----------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 60
	_panel.offset_right = -60
	_panel.offset_top = -180
	_panel.offset_bottom = -40
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.10, 0.96)
	panel_style.border_color = Color(0.55, 0.50, 0.42, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_top = 0
	panel_style.content_margin_bottom = 0
	_panel.add_theme_stylebox_override("panel", panel_style)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 14)
	_speaker_label.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	vbox.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 15)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_label)

	_bottom_row = HBoxContainer.new()
	_bottom_row.add_theme_constant_override("separation", 12)
	vbox.add_child(_bottom_row)

	# Craft / Shop button — visible from line 1 when the NPC has a station.
	_craft_btn = Button.new()
	_craft_btn.text = "Craft"
	_craft_btn.visible = false
	_craft_btn.pressed.connect(_on_craft_pressed)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.55, 0.40, 0.9)
	btn_style.set_corner_radius_all(3)
	btn_style.content_margin_left = 14
	btn_style.content_margin_right = 14
	btn_style.content_margin_top = 4
	btn_style.content_margin_bottom = 4
	_craft_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.30, 0.65, 0.48, 0.95)
	btn_hover.set_corner_radius_all(3)
	btn_hover.content_margin_left = 14
	btn_hover.content_margin_right = 14
	btn_hover.content_margin_top = 4
	btn_hover.content_margin_bottom = 4
	_craft_btn.add_theme_stylebox_override("hover", btn_hover)
	_craft_btn.add_theme_font_size_override("font_size", 14)
	_bottom_row.add_child(_craft_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_row.add_child(spacer)

	_advance_hint = Label.new()
	_advance_hint.text = "[Click] continue"
	_advance_hint.add_theme_font_size_override("font_size", 11)
	_advance_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_bottom_row.add_child(_advance_hint)


func _render_current_line() -> void:
	if _current_dialogue == null \
		or _line_index < 0 \
		or _line_index >= _current_dialogue.lines.size():
		_close()
		return

	var line: DialogueLine = _current_dialogue.lines[_line_index]
	if line == null:
		_advance()
		return

	if line.speaker == "":
		_speaker_label.visible = false
	else:
		_speaker_label.visible = true
		_speaker_label.text = line.speaker
	_text_label.text = line.text

	if _line_index >= _current_dialogue.lines.size() - 1:
		_advance_hint.text = "[Click] close"
	else:
		_advance_hint.text = "[Click] continue"


func _advance() -> void:
	_line_index += 1
	_render_current_line()


func _on_craft_pressed() -> void:
	_craft_btn.visible = false
	_panel.visible = false
	_waiting_for_crafting_close = true

	CraftingUI.open_station(_station_name, _station_recipes)
	if not CraftingUI.crafting_closed.is_connected(_on_crafting_closed):
		CraftingUI.crafting_closed.connect(_on_crafting_closed, CONNECT_ONE_SHOT)


func _on_crafting_closed() -> void:
	_waiting_for_crafting_close = false
	_close()


func _close() -> void:
	_panel.visible = true
	_craft_btn.visible = false
	_waiting_for_crafting_close = false
	visible = false
	get_tree().paused = false
	_current_dialogue = null
	_station_name = ""
	_station_recipes = []
	_line_index = 0
	dialogue_finished.emit()
