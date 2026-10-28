extends CanvasLayer
## Rune collection UI. Toggle with R.
## Pauses the game while open.
##
## Displays all RunestoneItems the player has collected, separate from the
## main inventory. Each rune is a grid tile; hovering shows a tooltip that
## follows the mouse. In a future pass, runes will provide passive stat
## bonuses — this screen is where the player reads what each rune does.
##
## Visual language matches the other menus — same panel anchors, gold-on-dark
## stylebox, shared Norse palette. Tabs between the other menus via MenuTabs.
##
## NOTE: No class_name — registered as autoload "RunesUI".

const ITEM_SLOT_SIZE := Vector2(80, 92)
const ITEM_COLUMNS := 8

# --- Norse/dark palette — must match inventory_ui.gd / kennings_ui.gd. ---
const COLOR_TITLE        := Color(0.95, 0.85, 0.40)
const COLOR_PANEL_BG     := Color(0.10, 0.09, 0.12, 0.96)
const COLOR_PANEL_BORDER := Color(0.55, 0.50, 0.42, 0.85)
const COLOR_ENTRY_BG     := Color(0.14, 0.13, 0.16, 0.8)
const COLOR_ENTRY_BG_EMPTY := Color(0.10, 0.10, 0.12, 0.7)
const COLOR_ENTRY_BORDER := Color(0.35, 0.33, 0.38, 0.5)
const COLOR_BODY_TEXT    := Color(0.78, 0.78, 0.78)
const COLOR_DIM_TEXT     := Color(0.55, 0.55, 0.55)
const COLOR_FLAVOR_TEXT  := Color(0.58, 0.55, 0.62)
const COLOR_SEPARATOR    := Color(0.4, 0.38, 0.34)
const COLOR_SECTION_HDR  := Color(0.70, 0.70, 0.70)
const COLOR_RUNE_ACCENT  := Color(0.80, 0.65, 0.30)

# Tooltip panel constants.
const TOOLTIP_MAX_WIDTH := 320.0
const TOOLTIP_OFFSET := Vector2(16, 16)

var _root_panel: PanelContainer
var _items_grid: HFlowContainer
var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 10
	_build_ui()
	visible = false

	EventBus.inventory_changed.connect(_on_inventory_changed)


func _process(_delta: float) -> void:
	if not visible:
		return
	# Tooltip follows mouse.
	if _tooltip_panel.visible:
		_position_tooltip()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_runes"):
		if WorldMap.is_open and not visible:
			return
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if visible and event.is_action_pressed("pause"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		_refresh()
	else:
		_hide_tooltip()


func _on_inventory_changed() -> void:
	if visible:
		_refresh()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_root_panel = PanelContainer.new()
	_root_panel.anchor_left = 0.15
	_root_panel.anchor_right = 0.85
	_root_panel.anchor_top = 0.06
	_root_panel.anchor_bottom = 0.94
	var ps := StyleBoxFlat.new()
	ps.bg_color = COLOR_PANEL_BG
	ps.border_color = COLOR_PANEL_BORDER
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(6)
	_root_panel.add_theme_stylebox_override("panel", ps)
	add_child(_root_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_root_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# --- Title ---
	var title := Label.new()
	title.text = "RUNES"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Carved marks of power. Each rune shapes the bearer."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", COLOR_FLAVOR_TEXT)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", COLOR_SEPARATOR)
	vbox.add_child(sep)

	var header := Label.new()
	header.text = "COLLECTED"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", COLOR_SECTION_HDR)
	vbox.add_child(header)

	var items_scroll := ScrollContainer.new()
	items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(items_scroll)

	_items_grid = HFlowContainer.new()
	_items_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_grid.add_theme_constant_override("h_separation", 6)
	_items_grid.add_theme_constant_override("v_separation", 6)
	items_scroll.add_child(_items_grid)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", COLOR_SEPARATOR)
	vbox.add_child(sep2)

	# --- Bottom hint ---
	var close_hint := Label.new()
	close_hint.text = "[R] or [Esc] to close   ·   hover to inspect"
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(close_hint)

	# --- Tooltip (floats above everything, follows cursor) ---
	_build_tooltip()


func _build_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 100
	_tooltip_panel.custom_minimum_size = Vector2(0, 0)
	# Anchor-free: position is set manually in _position_tooltip.
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.08, 0.07, 0.10, 0.96)
	ts.border_color = COLOR_RUNE_ACCENT
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(5)
	ts.content_margin_left = 12
	ts.content_margin_right = 12
	ts.content_margin_top = 10
	ts.content_margin_bottom = 10
	_tooltip_panel.add_theme_stylebox_override("panel", ts)
	add_child(_tooltip_panel)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.custom_minimum_size = Vector2(TOOLTIP_MAX_WIDTH, 0)
	_tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	_tooltip_label.add_theme_color_override("default_color", COLOR_BODY_TEXT)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_label)


func _position_tooltip() -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tip_size: Vector2 = _tooltip_panel.size
	# Default: lower-right of cursor. Flip if it would go off screen.
	var pos: Vector2 = mouse_pos + TOOLTIP_OFFSET
	if pos.x + tip_size.x > vp_size.x:
		pos.x = mouse_pos.x - tip_size.x - TOOLTIP_OFFSET.x
	if pos.y + tip_size.y > vp_size.y:
		pos.y = mouse_pos.y - tip_size.y - TOOLTIP_OFFSET.y
	_tooltip_panel.position = pos


# ============================================================================
# REFRESH
# ============================================================================

func _refresh() -> void:
	_hide_tooltip()
	for child in _items_grid.get_children():
		_items_grid.remove_child(child)
		child.queue_free()

	for slot_data in RunState.rune_collection:
		_items_grid.add_child(_make_rune_button(slot_data.item, slot_data.count))

	# Pad with empty slots.
	var cells_used: int = RunState.rune_collection.size()
	var min_cells: int = ITEM_COLUMNS * 4
	while cells_used < min_cells:
		_items_grid.add_child(_make_empty_slot())
		cells_used += 1


func _make_rune_button(rune: RunestoneItem, count: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = ITEM_SLOT_SIZE
	btn.mouse_entered.connect(_on_rune_hovered.bind(rune, count))
	btn.mouse_exited.connect(_hide_tooltip)

	var accent: Color = RunestoneItem.conduit_color(rune.conduit)
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_ENTRY_BG
	s.border_color = COLOR_ENTRY_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.18, 0.17, 0.20, 0.9)
	sh.border_color = Color(
		minf(accent.r + 0.20, 1.0),
		minf(accent.g + 0.20, 1.0),
		minf(accent.b + 0.20, 1.0),
		1.0)
	sh.set_border_width_all(2)
	sh.set_corner_radius_all(4)
	sh.content_margin_left = 4
	sh.content_margin_right = 4
	sh.content_margin_top = 4
	sh.content_margin_bottom = 4
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sh)

	# Layout: [stripe][content]
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 3)
	btn.add_child(hbox)

	var stripe := ColorRect.new()
	stripe.color = accent
	stripe.custom_minimum_size = Vector2(3, 0)
	stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(stripe)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 2)
	hbox.add_child(inner)

	# Rune symbol display — large, centered.
	if rune.rune_symbol != "":
		var sym := Label.new()
		sym.text = rune.rune_symbol
		sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sym.add_theme_font_size_override("font_size", 22)
		sym.add_theme_color_override("font_color", accent)
		sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(sym)

	# Icon fallback if no rune_symbol.
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(36, 36) if rune.rune_symbol == "" else Vector2(0, 0)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rune.rune_symbol == "":
		inner.add_child(icon_container)
		if "icon" in rune and rune.icon:
			var tex_rect := TextureRect.new()
			tex_rect.texture = rune.icon
			tex_rect.custom_minimum_size = Vector2(32, 32)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_container.add_child(tex_rect)
		else:
			var cr := ColorRect.new()
			cr.custom_minimum_size = Vector2(32, 32)
			cr.color = rune.placeholder_color
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_container.add_child(cr)

	var name_label := Label.new()
	name_label.text = rune.item_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", COLOR_BODY_TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(name_label)

	if count > 1:
		var count_label := Label.new()
		count_label.text = "×%d" % count
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 10)
		count_label.add_theme_color_override("font_color", accent)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(count_label)

	return btn


func _make_empty_slot() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = ITEM_SLOT_SIZE
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_ENTRY_BG_EMPTY
	s.border_color = Color(0.22, 0.21, 0.24, 0.4)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", s)
	var mid := CenterContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(mid)
	var dot := Label.new()
	dot.text = "·"
	dot.add_theme_font_size_override("font_size", 24)
	dot.add_theme_color_override("font_color", Color(0.35, 0.33, 0.36))
	mid.add_child(dot)
	return panel


# ============================================================================
# TOOLTIP
# ============================================================================

func _on_rune_hovered(rune: RunestoneItem, count: int) -> void:
	_tooltip_label.text = _format_rune_tooltip(rune, count)
	_tooltip_panel.visible = true
	# Force layout so size is correct for positioning.
	_tooltip_panel.reset_size()
	_position_tooltip()


func _hide_tooltip() -> void:
	_tooltip_panel.visible = false


func _format_rune_tooltip(rune: RunestoneItem, count: int) -> String:
	var accent: Color = RunestoneItem.conduit_color(rune.conduit)
	var accent_hex: String = accent.to_html(false)
	var lines: Array[String] = []

	# Title: symbol + name + conduit tier.
	var sym: String = rune.rune_symbol + " " if rune.rune_symbol != "" else ""
	var count_str: String = " ×%d" % count if count > 1 else ""
	var conduit_name: String = RunestoneItem.conduit_display_name(rune.conduit)
	lines.append("[color=#%s][b]%s%s%s[/b][/color]" % [
		accent_hex, sym, rune.item_name, count_str])

	# Stat bonus line — the core info.
	var bonus_text: String = rune.format_bonus()
	if count > 1:
		# Show per-rune AND total.
		var is_flat: bool = rune.rune_stat == RunestoneItem.RuneStat.DASH_CHARGES \
			or rune.rune_stat == RunestoneItem.RuneStat.RUNE_REROLLS
		var total: float = rune.bonus_value * count
		var stat_name: String = RunestoneItem.stat_display_name(rune.rune_stat)
		if is_flat:
			bonus_text = "+%d %s (×%d = +%d total)" % [
				int(rune.bonus_value), stat_name, count, int(total)]
		else:
			bonus_text = "+%.0f%% %s (×%d = +%.0f%% total)" % [
				rune.bonus_value, stat_name, count, total]
	lines.append("[color=#%s]%s[/color]" % [
		COLOR_BODY_TEXT.to_html(false), bonus_text])

	# Description / flavor.
	if rune.description != "":
		# The description now includes the stat line, so extract just the
		# flavor part after the period.
		var desc: String = rune.description
		var dot_pos: int = desc.find(". ")
		if dot_pos >= 0:
			desc = desc.substr(dot_pos + 2)
		if desc != "":
			lines.append("[color=#%s][i]%s[/i][/color]" % [
				COLOR_FLAVOR_TEXT.to_html(false), desc])

	# Conduit tier label.
	lines.append("[color=#%s]%s conduit[/color]" % [accent_hex, conduit_name])

	return "\n".join(lines)
