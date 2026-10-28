extends CanvasLayer
## Autoloaded kennings management UI. Toggled with "toggle_kennings" (K).
##
## Visual idiom mirrors QuestUI as closely as possible — same panel anchors,
## same gold-on-dark stylebox, same close-hint pattern. This is deliberate:
## these screens belong to the same "menu language" and switching between
## them (once MenuTabs is in) should feel visually continuous.
##
## Layout:
##   - Loadout strip at top: 4 equip slots. Click an empty slot does
##     nothing useful; click a filled slot to unequip.
##   - Scrollable catalog below: every kenning (unlocked + locked).
##     Unlocked entries get an Equip button (or "Equipped ✓"); locked
##     entries are dimmed and show the unlock_hint instead of the
##     effect list.
##   - Bottom hint matches QuestUI's hint style.
##
## NOTE: No class_name — registered as autoload "KenningsUI".

const MAX_EQUIPPED: int = 4  ## Must match KenningManager.MAX_EQUIPPED.

# Same palette as QuestUI / QuestBoard so the three feel like one menu.
const COLOR_TITLE       := Color(0.95, 0.85, 0.40)   # gold heading
const COLOR_PANEL_BG    := Color(0.10, 0.09, 0.12, 0.96)
const COLOR_PANEL_BORDER:= Color(0.55, 0.50, 0.42, 0.85)
const COLOR_ENTRY_BG    := Color(0.14, 0.13, 0.16, 0.8)
const COLOR_ENTRY_BG_LOCKED := Color(0.10, 0.10, 0.12, 0.7)
const COLOR_ENTRY_BORDER:= Color(0.35, 0.33, 0.38, 0.5)
const COLOR_ENTRY_BORDER_EQUIPPED := Color(0.85, 0.70, 0.30, 0.85)
const COLOR_BODY_TEXT   := Color(0.78, 0.78, 0.78)
const COLOR_DIM_TEXT    := Color(0.55, 0.55, 0.55)
const COLOR_FLAVOR_TEXT := Color(0.58, 0.55, 0.62)
const COLOR_SEPARATOR   := Color(0.4, 0.38, 0.34)

# Per-category badge colors — same palette logic as Quest type badges.
const CATEGORY_COLORS := {
	Kenning.Category.OFFENSE:   Color(0.85, 0.40, 0.35),
	Kenning.Category.DEFENSE:   Color(0.55, 0.60, 0.75),
	Kenning.Category.ELEMENTAL: Color(0.85, 0.60, 0.30),
	Kenning.Category.MOBILITY:  Color(0.45, 0.80, 0.65),
	Kenning.Category.UTILITY:   Color(0.75, 0.65, 0.85),
}

const CATEGORY_LABELS := {
	Kenning.Category.OFFENSE:   "OFFENSE",
	Kenning.Category.DEFENSE:   "DEFENSE",
	Kenning.Category.ELEMENTAL: "ELEMENTAL",
	Kenning.Category.MOBILITY:  "MOBILITY",
	Kenning.Category.UTILITY:   "UTILITY",
}


var _root: Control
var _panel: PanelContainer
var _title_label: Label
var _loadout_row: HBoxContainer
var _slot_buttons: Array[Button] = []
var _catalog_list: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	# Layer 9 (same as QuestUI) so the unified MenuTabs strip at layer 45
	# floats above all three menus identically.
	layer = 9
	_build_ui()
	visible = false
	EventBus.kenning_unlocked.connect(func(_id): _refresh())
	EventBus.kenning_equipped.connect(func(_id): _refresh())
	EventBus.kenning_unequipped.connect(func(_id): _refresh())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_kennings"):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("toggle_kennings"):
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		_refresh()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Dim background — same alpha as QuestUI.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	_panel = PanelContainer.new()
	# Anchors match inventory_ui.gd's panel (0.15/0.85 horizontal,
	# 0.06/0.94 vertical) so all three menus — Inventory, Kennings, Quests —
	# fill the exact same screen rectangle. MenuTabs swaps between them
	# and the panel chrome shouldn't shift as the player tabs through.
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 0.06
	_panel.anchor_bottom = 0.94
	var ps := StyleBoxFlat.new()
	ps.bg_color = COLOR_PANEL_BG
	ps.border_color = COLOR_PANEL_BORDER
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 0
	ps.content_margin_right = 0
	ps.content_margin_top = 0
	ps.content_margin_bottom = 0
	_panel.add_theme_stylebox_override("panel", ps)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# --- Title ---
	_title_label = Label.new()
	_title_label.text = "KENNINGS"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", COLOR_TITLE)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# Subtitle — sets the tone, also tells the player what this menu is for.
	var subtitle := Label.new()
	subtitle.text = "Names earned. Bear up to four; they walk with you between deaths."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", COLOR_FLAVOR_TEXT)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", COLOR_SEPARATOR)
	vbox.add_child(sep)

	# --- Loadout strip ---
	var loadout_header := Label.new()
	loadout_header.text = "BORNE NAMES"
	loadout_header.add_theme_font_size_override("font_size", 13)
	loadout_header.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	vbox.add_child(loadout_header)

	_loadout_row = HBoxContainer.new()
	_loadout_row.add_theme_constant_override("separation", 10)
	_loadout_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_loadout_row)
	for i in MAX_EQUIPPED:
		var slot := _make_loadout_slot(i)
		_loadout_row.add_child(slot)
		_slot_buttons.append(slot)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", COLOR_SEPARATOR)
	vbox.add_child(sep2)

	# --- Catalog header ---
	var catalog_header := Label.new()
	catalog_header.text = "ALL NAMES"
	catalog_header.add_theme_font_size_override("font_size", 13)
	catalog_header.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	vbox.add_child(catalog_header)

	# --- Scrollable catalog ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_catalog_list = VBoxContainer.new()
	_catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_catalog_list)

	_empty_label = Label.new()
	_empty_label.text = "No names known yet. Begin by walking through the south arch."
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_catalog_list.add_child(_empty_label)

	# --- Bottom hint ---
	var close_hint := Label.new()
	close_hint.text = "[K] or [Esc] to close"
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(close_hint)


## A single loadout slot in the top strip. Click to unequip whatever it
## holds; an empty slot is non-interactive but visually present so the
## player can see how many seats they have.
func _make_loadout_slot(index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 70)
	btn.set_meta("slot_index", index)
	btn.tooltip_text = "Click to release this name."

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.16, 0.15, 0.18, 0.95)
	bg_style.border_color = Color(0.32, 0.30, 0.28, 0.8)
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(4)
	bg_style.content_margin_left = 8
	bg_style.content_margin_right = 8
	bg_style.content_margin_top = 6
	bg_style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", bg_style)
	btn.add_theme_stylebox_override("hover", bg_style)
	btn.add_theme_stylebox_override("pressed", bg_style)

	btn.pressed.connect(func() -> void:
		var equipped: Array = KenningManager.equipped_ids()
		var idx: int = btn.get_meta("slot_index", -1)
		if idx >= 0 and idx < equipped.size():
			KenningManager.unequip(equipped[idx])
	)
	return btn


# ============================================================================
# REFRESH
# ============================================================================

func _refresh() -> void:
	_refresh_loadout()
	_refresh_catalog()


func _refresh_loadout() -> void:
	var equipped: Array = KenningManager.equipped_ids()
	for i in MAX_EQUIPPED:
		var btn: Button = _slot_buttons[i]
		# Wipe previous content (Button's own children for the slot UI).
		for child in btn.get_children():
			child.queue_free()

		if i < equipped.size():
			var k: Kenning = KenningManager.get_kenning(equipped[i])
			if k != null:
				_paint_loadout_slot(btn, k)
				continue
		_paint_empty_loadout_slot(btn, i)


func _paint_empty_loadout_slot(btn: Button, slot_index: int) -> void:
	# Restore the neutral stylebox. Without this, a slot that PREVIOUSLY
	# held a kenning would keep that kenning's tier_color on its border
	# even after the kenning is released — the slot button is reused
	# (never recreated), so its theme overrides persist across refreshes.
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.16, 0.15, 0.18, 0.95)
	bg_style.border_color = Color(0.32, 0.30, 0.28, 0.8)
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(4)
	bg_style.content_margin_left = 8
	bg_style.content_margin_right = 8
	bg_style.content_margin_top = 6
	bg_style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", bg_style)
	btn.add_theme_stylebox_override("hover", bg_style)
	btn.add_theme_stylebox_override("pressed", bg_style)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(v)

	var num_label := Label.new()
	num_label.text = "Seat %d" % (slot_index + 1)
	num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_label.add_theme_font_size_override("font_size", 10)
	num_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.48))
	num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(num_label)

	var empty_label := Label.new()
	empty_label.text = "— empty —"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.add_theme_font_size_override("font_size", 13)
	empty_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.45))
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(empty_label)


func _paint_loadout_slot(btn: Button, k: Kenning) -> void:
	# Repaint stylebox with the kenning's tier_color edge so the loadout
	# strip visually maps to the catalog entry color.
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.16, 0.15, 0.18, 0.95)
	bg_style.border_color = k.tier_color
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(4)
	bg_style.content_margin_left = 8
	bg_style.content_margin_right = 8
	bg_style.content_margin_top = 6
	bg_style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", bg_style)
	btn.add_theme_stylebox_override("hover", bg_style)
	btn.add_theme_stylebox_override("pressed", bg_style)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	btn.add_child(v)

	var name_label := Label.new()
	name_label.text = k.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", k.tier_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_label)

	var cat_label := Label.new()
	cat_label.text = CATEGORY_LABELS.get(k.category, "")
	cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cat_label.add_theme_font_size_override("font_size", 9)
	cat_label.add_theme_color_override("font_color", CATEGORY_COLORS.get(k.category, Color.WHITE))
	cat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cat_label)

	var unequip_hint := Label.new()
	unequip_hint.text = "click to release"
	unequip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unequip_hint.add_theme_font_size_override("font_size", 9)
	unequip_hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	unequip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(unequip_hint)


func _refresh_catalog() -> void:
	# Clear existing entries (preserve the empty_label).
	for child in _catalog_list.get_children():
		if child != _empty_label:
			child.queue_free()

	# Filter out any kenning marked hidden_when_locked while it's still
	# locked. Boss kennings and other "surprise" unlocks use this so the
	# catalog doesn't spoil their existence. Once unlocked, the kenning
	# appears in the list normally — the flag only suppresses the locked
	# state. We don't fight back-and-forth visibility: once seen, always
	# seen.
	var raw: Array[Kenning] = KenningManager.all_kennings()
	var entries: Array[Kenning] = []
	for k in raw:
		if k.hidden_when_locked and not KenningManager.is_unlocked(k.kenning_id):
			continue
		entries.append(k)

	_empty_label.visible = entries.is_empty()
	if entries.is_empty():
		return

	for k in entries:
		_add_catalog_entry(k)


func _add_catalog_entry(k: Kenning) -> void:
	var unlocked: bool = KenningManager.is_unlocked(k.kenning_id)
	var equipped: bool = KenningManager.is_equipped(k.kenning_id)

	var entry := PanelContainer.new()
	var es := StyleBoxFlat.new()
	if equipped:
		es.bg_color = Color(0.14, 0.13, 0.16, 0.85)
		es.border_color = COLOR_ENTRY_BORDER_EQUIPPED
		es.set_border_width_all(2)
	elif unlocked:
		es.bg_color = COLOR_ENTRY_BG
		es.border_color = COLOR_ENTRY_BORDER
		es.set_border_width_all(1)
	else:
		es.bg_color = COLOR_ENTRY_BG_LOCKED
		es.border_color = Color(0.22, 0.21, 0.24, 0.5)
		es.set_border_width_all(1)
	es.set_corner_radius_all(4)
	es.content_margin_left = 14
	es.content_margin_right = 14
	es.content_margin_top = 10
	es.content_margin_bottom = 10
	entry.add_theme_stylebox_override("panel", es)
	_catalog_list.add_child(entry)

	# Locked entries get a slight desaturation so the eye skips them at scan.
	if not unlocked:
		entry.modulate = Color(0.65, 0.65, 0.65, 1.0)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	entry.add_child(hbox)

	# Left edge: a colored stripe matching the kenning's tier_color. It's
	# the same affordance the loadout-slot border uses, so the player can
	# match an equipped kenning to its catalog entry at a glance.
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(4, 0)
	stripe.color = k.tier_color if unlocked else Color(0.35, 0.32, 0.32)
	stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(stripe)

	# Info column: name + epithet + effects + flavor.
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hbox.add_child(info)

	# Title row: category badge + kenning name + tradeoff/equipped flags.
	var cat_color: Color = CATEGORY_COLORS.get(k.category, Color.WHITE)
	var cat_str: String = "[%s]" % CATEGORY_LABELS.get(k.category, "")
	var tradeoff_str: String = "  [color=#bb8855](tradeoff)[/color]" if k.has_tradeoff() else ""
	var equipped_str: String = "  [color=#ffcc55]✓ borne[/color]" if equipped else ""
	var locked_lock: String = " 🔒" if not unlocked else ""

	var name_label := RichTextLabel.new()
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	name_label.add_theme_font_size_override("normal_font_size", 15)
	# Locked: dim the name a touch too.
	var name_color: String = k.tier_color.to_html(false) if unlocked else "888888"
	# Six placeholders, six args. Previously had a stray seventh %s at the
	# end that left the format string un-substituted (count mismatch fails
	# silently in GDScript). The locked icon piggybacks on the display
	# name to avoid needing its own slot.
	name_label.text = "[color=#%s]%s[/color] [color=#%s]%s[/color]%s%s" % [
		cat_color.to_html(false), cat_str,
		name_color, k.display_name + locked_lock,
		tradeoff_str, equipped_str,
	]
	info.add_child(name_label)

	# Epithet — italicized in muted color. Always shown if present.
	if k.epithet != "":
		var ep := Label.new()
		ep.text = "— %s" % k.epithet
		ep.add_theme_font_size_override("font_size", 11)
		ep.add_theme_color_override("font_color", COLOR_FLAVOR_TEXT)
		ep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(ep)

	# Description (only shown when unlocked — locked names should feel
	# mysterious until you've earned them).
	if unlocked and k.description != "":
		var desc := Label.new()
		desc.text = k.description
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", COLOR_BODY_TEXT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)

	# Effects list — unlocked entries show the mechanical bullet list;
	# locked entries show the unlock_hint instead.
	if unlocked:
		var lines: Array[String] = k.format_effect_lines()
		for line in lines:
			var fx := Label.new()
			fx.text = "  • " + line
			fx.add_theme_font_size_override("font_size", 12)
			# Tradeoff lines (anything that LOOKS bad) get faintly amber
			# so the player notices them on scan. This is a lightweight
			# heuristic — text starting with "+%d%% damage taken" or
			# "-%d%% speed" etc. is obviously a downside.
			fx.add_theme_color_override("font_color", _color_for_effect_line(line, k))
			info.add_child(fx)

		# Flavor text — italicized in dim color, shown last. Only on unlocked.
		if k.flavor_text != "":
			var flavor := Label.new()
			flavor.text = "“%s”" % k.flavor_text
			flavor.add_theme_font_size_override("font_size", 11)
			flavor.add_theme_color_override("font_color", COLOR_FLAVOR_TEXT)
			flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(flavor)
	else:
		# Locked: just show the hint, with a small key icon.
		var hint := Label.new()
		hint.text = "🔒  " + k.unlock_hint
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.65, 0.60, 0.50))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(hint)

	# Right column: action button (Equip / Equipped / locked-out).
	var action_col := VBoxContainer.new()
	action_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_col.custom_minimum_size = Vector2(110, 0)
	hbox.add_child(action_col)

	if unlocked and not equipped:
		var equip_btn := _make_action_button("Equip", Color(0.25, 0.55, 0.35), Color(0.30, 0.65, 0.42))
		# Disable if loadout full — but still show the button, so the
		# player understands why nothing happens. The KenningManager
		# returns false and toasts the "only 4 at once" message.
		var loadout_full: bool = KenningManager.equipped_ids().size() >= MAX_EQUIPPED
		if loadout_full:
			equip_btn.disabled = true
			equip_btn.text = "Seats full"
		equip_btn.pressed.connect(func():
			KenningManager.equip(k.kenning_id)
		)
		action_col.add_child(equip_btn)
	elif unlocked and equipped:
		var unequip_btn := _make_action_button("Release", Color(0.45, 0.25, 0.25), Color(0.55, 0.30, 0.30))
		unequip_btn.pressed.connect(func():
			KenningManager.unequip(k.kenning_id)
		)
		action_col.add_child(unequip_btn)
	else:
		# Locked entries get a small disabled "—" indicator rather than
		# a button. Less eye-noise; the hint already tells the story.
		var locked_indicator := Label.new()
		locked_indicator.text = "locked"
		locked_indicator.add_theme_font_size_override("font_size", 12)
		locked_indicator.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
		locked_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		action_col.add_child(locked_indicator)


func _make_action_button(label: String, base_col: Color, hover_col: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 13)
	var s := StyleBoxFlat.new()
	s.bg_color = base_col
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	var sh := StyleBoxFlat.new()
	sh.bg_color = hover_col
	sh.set_corner_radius_all(3)
	sh.content_margin_left = 14
	sh.content_margin_right = 14
	sh.content_margin_top = 6
	sh.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", sh)
	# Disabled state: a muted version of the base color, so a "Seats full"
	# button still LOOKS like a button rather than a dead box.
	var sd := StyleBoxFlat.new()
	sd.bg_color = Color(base_col.r * 0.5, base_col.g * 0.5, base_col.b * 0.5, 0.7)
	sd.set_corner_radius_all(3)
	sd.content_margin_left = 14
	sd.content_margin_right = 14
	sd.content_margin_top = 6
	sd.content_margin_bottom = 6
	btn.add_theme_stylebox_override("disabled", sd)
	return btn


## Decide what color to render a single effect line in. Bullets that
## represent a DRAWBACK (more damage taken, less speed, less damage) get
## an amber tint so the player sees them flagged at a glance, instead of
## buried in a list of green-feeling green text. This is a lightweight
## heuristic that reads the string — works because format_effect_lines()
## emits a consistent format.
func _color_for_effect_line(line: String, _k: Kenning) -> Color:
	# Penalty heuristic: positive % damage taken, negative % damage dealt
	# or speed, negative HP, positive cooldown.
	# format_effect_lines puts the % in a clear position; check substrings.
	if line.contains("+") and line.contains("damage taken"):
		return Color(0.85, 0.60, 0.30)
	if line.contains("-") and line.contains("damage dealt"):
		return Color(0.85, 0.60, 0.30)
	if line.contains("-") and line.contains("move speed"):
		return Color(0.85, 0.60, 0.30)
	if line.contains("-") and line.contains("max HP"):
		return Color(0.85, 0.60, 0.30)
	if line.contains("-") and line.contains("dash cooldown"):
		# "-X% dash cooldown" in our formatter actually means cooldown got
		# LONGER (we inverted the sign for display). So this IS a penalty.
		return Color(0.85, 0.60, 0.30)
	return COLOR_BODY_TEXT
