extends CanvasLayer
## Inventory UI. Toggle with I or E (when nothing interactable is nearby).
## Pauses the game while open.
##
## Visual language matches kennings_ui.gd and quest_ui.gd — same panel
## anchors, gold-on-dark stylebox, category-color stripes. The three
## menus tab between each other via menu_tabs.gd, so visual continuity
## matters: every Tab change should feel like a page-flip in the same
## menu, not a context shift to a different game.
##
## Layout:
##   - Title row:        gold "INVENTORY" centered, soul currency on right
##   - Subtitle:         flavor line in muted text
##   - WORN & WIELDED:   single row, 3 armor slots + thin divider + 2
##                        active weapon slots + thin divider + 2
##                        prepared weapon slots. Dark bordered cards that
##                        color-glow when filled.
##   - CARRIED:          6-wide grid of dark-styled item cards, each with
##                        a category-colored left stripe
##   - Detail card:      bordered RichTextLabel with BBCode category badge
##                        and stat bullets
##   - Bottom hint:      "[I] or [Esc] to close" plus interaction summary
##
## Interactions (unchanged from prior version):
##   - SINGLE-click  → select (highlight + show details)
##   - DOUBLE-click  → equip (armor/weapon) or use (consumable)
##   - Click EQUIP slot → unequip
##   - DRAG inventory item → equipment slot: equip
##   - DRAG equipment slot → inventory: unequip
##   - DRAG between equipment slots: swap (when types are compatible)
##
## Drag-and-drop uses set_drag_forwarding so the InventoryUI handles all
## drag logic centrally instead of subclassing Button per slot type.
##
## NOTE: No class_name — autoload "InventoryUI".

const ITEM_SLOT_SIZE := Vector2(76, 88)
# Equipment slot: narrower than items grid because 7 slots share one row
# now, but taller to compensate (the icon gets a 48px box instead of 40px
# so worn/wielded items feel substantial rather than postage-stamp sized).
const EQUIP_SLOT_SIZE := Vector2(96, 112)
const ITEM_COLUMNS := 10
# How wide a single inventory slot's full footprint is, including the
# right-side gap to the next slot. Used by 2H weapons that span two
# cells: the wide button measures 2*SLOT + 1*GAP wide so it sits
# flush with the boundaries of the slot column to its right.
const ITEM_SLOT_H_GAP := 6

# Hover-only flag tints. Modulate values >1 brighten the slot ABOVE the
# stylebox baseline — necessary because plain Color(1, 0.95, 0.4) just
# tints the slot yellow at the same dark luminance as the bg, making it
# hard to spot the selection. Values above 1.0 in modulate are valid;
# they amplify the rendered pixel.
const COLOR_SELECTED := Color(1.6, 1.5, 0.9, 1.0)
const COLOR_DROP_OK := Color(1.0, 1.8, 1.2, 1.0)
const COLOR_DROP_BAD := Color(1.8, 0.9, 0.9, 1.0)

# --- Norse/dark palette — must match kennings_ui.gd and quest_ui.gd. ---
# These three UIs share a "menu language" and the player should feel the
# continuity when they tab between them.
const COLOR_TITLE        := Color(0.95, 0.85, 0.40)   # gold heading
const COLOR_PANEL_BG     := Color(0.10, 0.09, 0.12, 0.96)
const COLOR_PANEL_BORDER := Color(0.55, 0.50, 0.42, 0.85)
const COLOR_ENTRY_BG     := Color(0.14, 0.13, 0.16, 0.8)
const COLOR_ENTRY_BG_EMPTY := Color(0.10, 0.10, 0.12, 0.7)
const COLOR_ENTRY_BORDER := Color(0.35, 0.33, 0.38, 0.5)
const COLOR_BODY_TEXT    := Color(0.78, 0.78, 0.78)
const COLOR_DIM_TEXT     := Color(0.55, 0.55, 0.55)
const COLOR_FLAVOR_TEXT  := Color(0.58, 0.55, 0.62)
const COLOR_SEPARATOR    := Color(0.4, 0.38, 0.34)
const COLOR_CURRENCY     := Color(0.95, 0.80, 0.35)
const COLOR_SECTION_HDR  := Color(0.70, 0.70, 0.70)

# Per-category accent for the left-edge stripe on item-grid slots and for
# detail-card titles. Same pattern the kennings catalog uses; lets the
# player triage items by domain at a glance.
const CATEGORY_COLORS := {
	"melee":      Color(0.85, 0.40, 0.35),
	"ranged":     Color(0.35, 0.55, 0.75),
	"spell":      Color(0.55, 0.40, 0.70),
	"weapon":     Color(0.85, 0.40, 0.35),
	"armor":      Color(0.55, 0.60, 0.75),
	"runestone":  Color(0.80, 0.65, 0.30),
	"consumable": Color(0.45, 0.80, 0.55),
	"reagent":    Color(0.65, 0.80, 0.45),
	"key":        Color(0.90, 0.75, 0.40),
	"misc":       Color(0.65, 0.62, 0.58),
}

var _root_panel: PanelContainer
# Declared as Container (not GridContainer) because we use an
# HFlowContainer to support variable-width cells — specifically so
# two-handed weapons can span two cells of horizontal space. Both
# HFlowContainer and the older GridContainer descend from Container,
# so the looser typing keeps the assignment legal without losing the
# child-iteration / add_child interface this file relies on.
var _items_grid: Container
var _currency_label: Label

# Floating tooltip that follows the mouse — replaces the old static
# detail panel at the bottom. Shows the same BBCode item info but
# right at the cursor so the player's eyes stay on the item grid.
const TOOLTIP_MAX_WIDTH := 340.0
const TOOLTIP_OFFSET := Vector2(16, 16)
var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel

var _equip_helmet: Button
var _equip_chest: Button
var _equip_boots: Button
var _equip_primary: Button
var _equip_secondary: Button
var _equip_prepared_pri: Button
var _equip_prepared_sec: Button

## Deconstruct slot — sits outside the panel border on the bottom-right.
## Items dragged into it are broken down via Item.deconstruct() for
## partial reagent / soul refund. Lives as a sibling of _root_panel
## (not inside its margin tree) so it can sit visually outside the
## panel's framing.
var _decon_slot: Button

# All slot widgets, for highlight management.
var _all_slots: Array[Button] = []

# Currently selected slot (for hover-style highlight that persists).
var _selected_slot: Button = null

var _was_dragging: bool = false
## The slot that's currently tinted as a drop target (green/red). Tracked
## so we can clear it when the cursor leaves — Godot doesn't fire any
## drag-exited signal per Control.
var _tinted_drop_target: Button = null


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 10
	_build_ui()
	visible = false

	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.weapon_equipped.connect(_on_equipment_changed.unbind(2))
	EventBus.armor_equipped.connect(_on_equipment_changed.unbind(1))


func _process(_delta: float) -> void:
	if not visible:
		return

	# Tooltip follows mouse — but hide during drags so it doesn't
	# compete with the drag preview and drop-target tints.
	if _tooltip_panel.visible:
		if get_viewport().gui_is_dragging():
			_hide_tooltip()
		else:
			_position_tooltip()

	var dragging: bool = get_viewport().gui_is_dragging()

	# Drag end: restore source slot tints if released over nothing.
	if _was_dragging and not dragging:
		_clear_drop_tints()
	_was_dragging = dragging

	# Drag in progress: if the cursor is no longer over the tinted slot,
	# clear that slot's tint. _can_drop_data fires when over a target;
	# nothing fires when leaving one, so we have to detect it ourselves.
	if dragging and _tinted_drop_target != null:
		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered != _tinted_drop_target:
			# Walk up the tree — buttons have child Controls (icons, labels)
			# that intercept hover, so the "hovered" control might be a
			# descendant of our slot, not the slot itself.
			var still_over: bool = false
			var c: Node = hovered
			while c != null:
				if c == _tinted_drop_target:
					still_over = true
					break
				c = c.get_parent()
			if not still_over:
				_clear_tint_on(_tinted_drop_target)
				_tinted_drop_target = null


func _input(event: InputEvent) -> void:
	# Explicit inventory key (I) always works — except while the map is open.
	if event.is_action_pressed("toggle_inventory"):
		if WorldMap.is_open and not visible:
			return
		_toggle()
		get_viewport().set_input_as_handled()
		return

	# Interact key (E) doubles as an inventory shortcut. While the inventory
	# is open, E closes it. While closed, E only opens it when there's
	# nothing to interact with — otherwise E gets consumed by the nearest
	# interactable's own _process() handler.
	if event.is_action_pressed("interact"):
		if visible:
			_toggle()
			# Clear the just-pressed state so interactables don't immediately
			# fire this same frame after the tree unpauses.
			Input.action_release("interact")
			get_viewport().set_input_as_handled()
			return
		if not EventBus.has_interactable_in_range() and not WorldMap.is_open:
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
		_clear_selection()
		_hide_tooltip()


func _on_inventory_changed() -> void:
	if visible:
		_refresh()

func _on_currency_changed(new_amount: int) -> void:
	if _currency_label:
		_currency_label.text = "✦ %d souls" % new_amount

func _on_equipment_changed() -> void:
	if visible:
		_refresh_equipment()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	# Dim background — same alpha as the kennings/quests UI so the
	# darkness behind feels uniform between tabs.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Switch from CenterContainer/fixed-size to anchored 0.15/0.85 — same
	# anchors as quest_ui and kennings_ui. Top anchor pushed to 0.06
	# (instead of 0.08) because the inventory has the most content of the
	# three; the extra ~30px gives the items grid a third visible row
	# without scrolling for small inventories. The MenuTabs strip sits
	# above at y=6..42, leaving a 6px breathing gap to the panel top.
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

	# --- Title row: gold "INVENTORY" centered, with the soul currency
	# pinned to the right edge in the same gold tone the quest UI uses
	# for soul-cost displays.
	#
	# Layout uses a single Control with two anchored children rather than
	# an HBox-with-spacers, because anchoring child Controls inside an
	# HBox spacer is fragile in Godot 4 (the spacer's rect isn't a stable
	# anchor parent until the layout settles). A plain Control with
	# manual anchor children is rock-solid and uses less layout work.
	var title_row := Control.new()
	title_row.custom_minimum_size = Vector2(0, 28)
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title_row)

	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.0
	title.anchor_bottom = 1.0
	title.offset_left = 0
	title.offset_right = 0
	title.offset_top = 0
	title.offset_bottom = 0
	title_row.add_child(title)

	_currency_label = Label.new()
	_currency_label.text = "✦ %d souls" % GameState.soul_currency
	_currency_label.add_theme_font_size_override("font_size", 14)
	_currency_label.add_theme_color_override("font_color", COLOR_CURRENCY)
	_currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_currency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Anchor to the right edge of the title_row Control. offset_left
	# being -160 reserves 160px of width for the label.
	_currency_label.anchor_left = 1.0
	_currency_label.anchor_right = 1.0
	_currency_label.anchor_top = 0.0
	_currency_label.anchor_bottom = 1.0
	_currency_label.offset_left = -160
	_currency_label.offset_right = 0
	_currency_label.offset_top = 0
	_currency_label.offset_bottom = 0
	title_row.add_child(_currency_label)

	# Subtitle — tone-setting one-liner, same place quests/kennings put
	# their "Names earned..." / "Tasks taken..." subtitle.
	var subtitle := Label.new()
	subtitle.text = "What you carry. What you wear. What you may yet use."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", COLOR_FLAVOR_TEXT)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", COLOR_SEPARATOR)
	vbox.add_child(sep)

	# --- EQUIPMENT section ---
	var equip_header := Label.new()
	equip_header.text = "WORN & WIELDED"
	equip_header.add_theme_font_size_override("font_size", 13)
	equip_header.add_theme_color_override("font_color", COLOR_SECTION_HDR)
	vbox.add_child(equip_header)

	# Single equipment bar: [helmet][chest][boots] | [primary][secondary][Q][F]
	#
	# Combined into one row (was two stacked rows). The visual story is
	# "what I'm wearing FROM head to foot, then what I'm wielding in my
	# hands and ready" — a left-to-right reading order rather than a
	# top-and-then-bottom grid. Frees one full row of vertical space for
	# the items grid below.
	#
	# The thin VSeparator between boots and primary-weapon is the divider
	# the player asked for. It reads as a small "and now the wielded
	# half" beat without needing a label, similar to how a hyphen splits
	# parts of a compound noun without being a heading.
	var equip_row := HBoxContainer.new()
	equip_row.add_theme_constant_override("separation", 8)
	equip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(equip_row)

	_equip_helmet = _make_equip_slot("Helm",  "helmet")
	_equip_chest  = _make_equip_slot("Cloak", "chest")
	_equip_boots  = _make_equip_slot("Tread", "boots")
	equip_row.add_child(_equip_helmet)
	equip_row.add_child(_equip_chest)
	equip_row.add_child(_equip_boots)

	# Vertical divider between worn-armor and wielded-weapons. Custom min
	# width gives it a bit of breathing room (16px gap instead of the
	# default 4) so the divider feels like a section break rather than
	# just another slot's edge.
	var equip_divider := VSeparator.new()
	equip_divider.add_theme_color_override("separator", COLOR_SEPARATOR)
	equip_divider.add_theme_constant_override("separation", 16)
	equip_row.add_child(equip_divider)

	_equip_primary   = _make_equip_slot("[LMB] Primary",   "primary")
	_equip_secondary = _make_equip_slot("[RMB] Secondary", "secondary")

	# Divider between active and prepared weapon pairs — same visual
	# language as the armor/weapon divider above.
	var equip_divider2 := VSeparator.new()
	equip_divider2.add_theme_color_override("separator", COLOR_SEPARATOR)
	equip_divider2.add_theme_constant_override("separation", 16)

	_equip_prepared_pri = _make_equip_slot("[Q] Prepared",  "prepared_primary")
	_equip_prepared_sec = _make_equip_slot("Prepared",      "prepared_secondary")
	equip_row.add_child(_equip_primary)
	equip_row.add_child(_equip_secondary)
	equip_row.add_child(equip_divider2)
	equip_row.add_child(_equip_prepared_pri)
	equip_row.add_child(_equip_prepared_sec)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", COLOR_SEPARATOR)
	vbox.add_child(sep2)

	# --- ITEMS section ---
	var items_header := Label.new()
	items_header.text = "CARRIED"
	items_header.add_theme_font_size_override("font_size", 13)
	items_header.add_theme_color_override("font_color", COLOR_SECTION_HDR)
	vbox.add_child(items_header)

	var items_scroll := ScrollContainer.new()
	items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(items_scroll)

	# Use HFlowContainer (not GridContainer) so individual items can have
	# varying widths — specifically so two-handed weapons can be a single
	# button that spans two cells of horizontal space. GridContainer
	# would clip them; HFlowContainer wraps to the next row when the
	# current row's total minimum-width exceeds the container's available
	# width, which is exactly the behavior we want when a 2H weapon
	# "overflows" the would-be column count.
	_items_grid = HFlowContainer.new()
	_items_grid.add_theme_constant_override("h_separation", ITEM_SLOT_H_GAP)
	_items_grid.add_theme_constant_override("v_separation", 6)
	_items_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_scroll.add_child(_items_grid)

	var sep3 := HSeparator.new()
	sep3.add_theme_color_override("separator", COLOR_SEPARATOR)
	vbox.add_child(sep3)

	# --- Bottom hint — same format as kennings/quests "[K] or [Esc] to close".
	var close_hint := Label.new()
	close_hint.text = "[I] or [Esc] to close   ·   hover to inspect   ·   double-click to equip/use   ·   drag to move"
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(close_hint)

	_all_slots.append_array([
		_equip_helmet, _equip_chest, _equip_boots,
		_equip_primary, _equip_secondary,
		_equip_prepared_pri, _equip_prepared_sec,
	])

	# --- Deconstruct slot ---------------------------------------------
	# Sits OUTSIDE the inventory panel on its bottom-right. Players drag
	# items into it to break them down for partial reagent/soul refund
	# (see Item.deconstruct()). It is a sibling of _root_panel — not
	# inside the panel's margin/vbox tree — so it can render in the
	# visual gutter beyond the panel border.
	#
	# Anchoring: pinned to the same fractional bottom-right corner as the
	# panel (0.85 / 0.94), then OFFSET 12px right and aligned to the
	# panel's bottom edge. The offset_left starts where the panel ends;
	# offset_top is the slot's height back from the bottom anchor. This
	# keeps the slot visually grouped with the panel (corner-adjacent)
	# regardless of viewport size.
	_decon_slot = Button.new()
	_decon_slot.custom_minimum_size = ITEM_SLOT_SIZE
	_decon_slot.set_meta("kind", "decon")
	_decon_slot.anchor_left = 0.85
	_decon_slot.anchor_right = 0.85
	_decon_slot.anchor_top = 0.94
	_decon_slot.anchor_bottom = 0.94
	_decon_slot.offset_left = 12
	_decon_slot.offset_right = 12 + ITEM_SLOT_SIZE.x
	_decon_slot.offset_top = -ITEM_SLOT_SIZE.y
	_decon_slot.offset_bottom = 0
	# Visually distinct: muted-red border, dim cinder-toned background.
	# Stylebox built per-state so hover/pressed feel responsive but the
	# slot stays clearly "this is destructive."
	var ds_base := StyleBoxFlat.new()
	ds_base.bg_color = Color(0.18, 0.10, 0.10, 0.9)
	ds_base.border_color = Color(0.70, 0.30, 0.25, 0.9)
	ds_base.set_border_width_all(2)
	ds_base.set_corner_radius_all(5)
	var ds_hover := ds_base.duplicate() as StyleBoxFlat
	ds_hover.bg_color = Color(0.24, 0.12, 0.12, 0.95)
	ds_hover.border_color = Color(0.95, 0.45, 0.32, 1.0)
	_decon_slot.add_theme_stylebox_override("normal", ds_base)
	_decon_slot.add_theme_stylebox_override("hover", ds_hover)
	_decon_slot.add_theme_stylebox_override("pressed", ds_hover)
	_decon_slot.add_theme_stylebox_override("focus", ds_hover)
	# Inner label — short, vertical, centered.
	var decon_label := Label.new()
	decon_label.text = "BREAK\nDOWN"
	decon_label.add_theme_font_size_override("font_size", 11)
	decon_label.add_theme_color_override("font_color", Color(0.95, 0.65, 0.55, 1))
	decon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	decon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	decon_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	decon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decon_slot.add_child(decon_label)
	# Tooltip explains the cost/return policy — players see this on hover
	# without having to discover-by-doing.
	_decon_slot.tooltip_text = ("Drag an item here to break it down.\n"
		+ "Returns about half of the item's crafting materials\n"
		+ "(or souls, for bought items). Some materials may be lost.")
	# Wire drag-and-drop receiver hooks. The slot is drop-only —
	# _get_drag_data_decon always returns null (nothing draggable
	# lives in this slot), can_drop and drop handle the receiving end.
	_decon_slot.set_drag_forwarding(
		_get_drag_data_decon.bind(_decon_slot),
		_can_drop_data_decon.bind(_decon_slot),
		_drop_data_decon.bind(_decon_slot),
	)
	add_child(_decon_slot)
	_all_slots.append(_decon_slot)

	# --- Floating tooltip (follows cursor, replaces old detail panel) ---
	_build_tooltip()


func _build_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 100
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.08, 0.07, 0.10, 0.96)
	ts.border_color = Color(0.55, 0.50, 0.42, 0.90)
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
	var pos: Vector2 = mouse_pos + TOOLTIP_OFFSET
	if pos.x + tip_size.x > vp_size.x:
		pos.x = mouse_pos.x - tip_size.x - TOOLTIP_OFFSET.x
	if pos.y + tip_size.y > vp_size.y:
		pos.y = mouse_pos.y - tip_size.y - TOOLTIP_OFFSET.y
	_tooltip_panel.position = pos


func _show_tooltip_for_item(item: Item, is_equipped: bool) -> void:
	_tooltip_label.text = _format_detail_bbcode(item, is_equipped)
	_tooltip_panel.visible = true
	_tooltip_panel.reset_size()
	_position_tooltip()


func _hide_tooltip() -> void:
	_tooltip_panel.visible = false

func _make_equip_slot(label_text: String, slot_id: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = EQUIP_SLOT_SIZE
	btn.set_meta("slot_id", slot_id)
	btn.set_meta("kind", "equip")
	btn.gui_input.connect(_on_slot_gui_input.bind(btn))
	btn.mouse_entered.connect(_on_slot_hovered.bind(btn))
	btn.mouse_exited.connect(_on_slot_unhovered)

	btn.set_drag_forwarding(
		_get_drag_data_equip.bind(btn),
		_can_drop_data_equip.bind(btn),
		_drop_data_equip.bind(btn),
	)

	# Apply the initial "empty slot" stylebox. _set_equip_slot will
	# repaint this with a category-colored border whenever something gets
	# equipped, and back to neutral when unequipped. This mirrors the
	# kenning loadout slots' pattern; they shared the same bug where an
	# empty slot kept the previous border, so the painter is always
	# called explicitly on BOTH branches (filled and empty).
	_apply_equip_slot_style(btn, COLOR_ENTRY_BORDER, 1)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	btn.add_child(vbox)

	var hint := Label.new()
	hint.text = label_text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)

	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(52, 52)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	var color_rect := ColorRect.new()
	color_rect.custom_minimum_size = Vector2(48, 48)
	color_rect.color = Color(0.16, 0.15, 0.18)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(color_rect)
	btn.set_meta("color_rect", color_rect)

	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(44, 44)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.visible = false
	icon_container.add_child(texture_rect)
	btn.set_meta("texture_rect", texture_rect)

	var name_label := Label.new()
	name_label.text = "— empty —"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.45))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)
	btn.set_meta("name_label", name_label)

	return btn


## Apply a stylebox to an equip slot Button. Centralized so the filled
## and empty painter paths produce identical box shapes — only the
## border color/width differs. Same lesson learned in the kennings UI:
## if you reuse a Button across states, every visual property has to be
## set on every painter path, not just the "filled" one.
func _apply_equip_slot_style(btn: Button, border_color: Color, border_width: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.13, 0.12, 0.15, 0.95)
	s.border_color = border_color
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(4)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", s)
	# Hover gets a slightly brighter border + bg so the affordance reads.
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.17, 0.16, 0.19, 0.96)
	sh.border_color = Color(
		minf(border_color.r + 0.15, 1.0),
		minf(border_color.g + 0.15, 1.0),
		minf(border_color.b + 0.15, 1.0),
		border_color.a,
	)
	sh.set_border_width_all(border_width)
	sh.set_corner_radius_all(4)
	sh.content_margin_left = 6
	sh.content_margin_right = 6
	sh.content_margin_top = 6
	sh.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sh)


# ============================================================================
# REFRESH
# ============================================================================

func _refresh() -> void:
	_refresh_equipment()
	_refresh_items_grid()
	_currency_label.text = "✦ %d souls" % GameState.soul_currency


func _refresh_equipment() -> void:
	_set_equip_slot(_equip_helmet,    RunState.helmet)
	_set_equip_slot(_equip_chest,     RunState.chest)
	_set_equip_slot(_equip_boots,     RunState.boots)
	# Weapon slots route through _slot_contents so two-handed weapons
	# mirror into the opposite slot — _slot_contents handles the
	# "primary is two-handed → fill secondary too" logic (and vice
	# versa) so both equipped slots render filled. Same for prepared.
	_set_equip_slot(_equip_primary,       _slot_contents("primary"))
	_set_equip_slot(_equip_secondary,     _slot_contents("secondary"))
	_set_equip_slot(_equip_prepared_pri,  _slot_contents("prepared_primary"))
	_set_equip_slot(_equip_prepared_sec,  _slot_contents("prepared_secondary"))


func _set_equip_slot(slot: Button, equipped: Resource) -> void:
	if slot == null:
		return
	var color_rect: ColorRect = slot.get_meta("color_rect")
	var texture_rect: TextureRect = slot.get_meta("texture_rect")
	var name_label: Label = slot.get_meta("name_label")

	if equipped == null:
		# Empty: restore neutral stylebox AND placeholder visuals. Same
		# kennings-UI lesson — every visual must be set on every state
		# transition because the Button itself is reused.
		_apply_equip_slot_style(slot, COLOR_ENTRY_BORDER, 1)
		color_rect.color = Color(0.16, 0.15, 0.18)
		color_rect.visible = true
		texture_rect.visible = false
		name_label.text = "— empty —"
		name_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.45))
		return

	# Filled: category-colored border + brighter name color so the
	# equipped state reads as "live" at a glance.
	var cat: String = _category_for(equipped)
	var accent: Color = CATEGORY_COLORS.get(cat, Color(0.85, 0.70, 0.30))
	_apply_equip_slot_style(slot, accent, 2)

	if equipped is Item:
		var i: Item = equipped
		var display_name: String = i.item_name
		name_label.text = display_name
		name_label.add_theme_color_override("font_color", accent)
		if "icon" in i and i.icon:
			texture_rect.texture = i.icon
			texture_rect.visible = true
			color_rect.visible = false
		else:
			color_rect.color = i.placeholder_color
			color_rect.visible = true
			texture_rect.visible = false


func _refresh_items_grid() -> void:
	# Synchronous remove so child count is accurate immediately
	# (queue_free is deferred to end-of-frame, which caused our earlier resize bug).
	for child in _items_grid.get_children():
		_items_grid.remove_child(child)
		child.queue_free()
	_selected_slot = null

	for slot_data in RunState.inventory:
		_items_grid.add_child(_make_item_button(slot_data.item, slot_data.count))

	# Pad with empty slots so the grid feels stable as the player's
	# inventory shrinks and grows. We count *cells consumed* — a 2H
	# weapon button takes 2 cells of layout width even though it's
	# one child — so the visible row-count stays close to constant
	# regardless of how many 2H weapons the player is hauling.
	var cells_used := 0
	for slot_data in RunState.inventory:
		if slot_data.item is Weapon and (slot_data.item as Weapon).two_handed:
			cells_used += 2
		else:
			cells_used += 1
	var min_cells := ITEM_COLUMNS * 4   # 4 rows visible at minimum
	while cells_used < min_cells:
		_items_grid.add_child(_make_empty_item_slot())
		cells_used += 1


func _make_item_button(item: Item, count: int) -> Button:
	var btn := Button.new()
	# Two-handed weapons physically span two slot cells, so the player
	# can see at a glance that the item takes both hands and can't be
	# paired with anything else. Width is 2*slot + 1*h_gap so the wider
	# button's right edge aligns with where the next slot's right edge
	# would have been — the grid stays visually aligned.
	if item is Weapon and (item as Weapon).two_handed:
		btn.custom_minimum_size = Vector2(
			ITEM_SLOT_SIZE.x * 2 + ITEM_SLOT_H_GAP,
			ITEM_SLOT_SIZE.y,
		)
	else:
		btn.custom_minimum_size = ITEM_SLOT_SIZE
	btn.set_meta("kind", "item")
	btn.set_meta("item", item)
	btn.gui_input.connect(_on_slot_gui_input.bind(btn))
	btn.mouse_entered.connect(_on_slot_hovered.bind(btn))
	btn.mouse_exited.connect(_on_slot_unhovered)

	btn.set_drag_forwarding(
		_get_drag_data_item.bind(btn),
		_can_drop_data_item.bind(btn),
		_drop_data_item.bind(btn),
	)

	# Item slots get a dark stylebox to match the kennings catalog
	# entries. The category-colored stripe lives in the inner HBox below
	# rather than the stylebox border, because the stripe needs to span
	# the full slot height — borders bleed at the corners and don't read
	# cleanly when the stripe is only 3px wide.
	var cat: String = _category_for(item)
	var accent: Color = CATEGORY_COLORS.get(cat, COLOR_ENTRY_BORDER)
	_apply_item_slot_style(btn, COLOR_ENTRY_BORDER, 1)
	btn.set_meta("accent", accent)

	# Layout: HBox with [3px stripe][VBox of content].
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

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(44, 44)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	var color_rect := ColorRect.new()
	color_rect.custom_minimum_size = Vector2(40, 40)
	color_rect.color = item.placeholder_color
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(color_rect)

	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(36, 36)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(texture_rect)

	if "icon" in item and item.icon:
		texture_rect.texture = item.icon
		color_rect.visible = false
	else:
		texture_rect.visible = false

	var name_label := Label.new()
	name_label.text = item.item_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", COLOR_BODY_TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	if count > 1:
		var count_label := Label.new()
		count_label.text = "×%d" % count
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 10)
		count_label.add_theme_color_override("font_color", accent)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(count_label)

	return btn


## Symmetric to _apply_equip_slot_style. Item slots use a flatter dark
## body with a thin gray border; the visible accent comes from the
## colored vertical stripe inside the slot (see _make_item_button).
func _apply_item_slot_style(btn: Button, border_color: Color, border_width: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_ENTRY_BG
	s.border_color = border_color
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(4)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.18, 0.17, 0.20, 0.9)
	sh.border_color = Color(
		minf(border_color.r + 0.20, 1.0),
		minf(border_color.g + 0.20, 1.0),
		minf(border_color.b + 0.20, 1.0),
		minf(border_color.a + 0.20, 1.0),
	)
	sh.set_border_width_all(maxi(border_width, 1))
	sh.set_corner_radius_all(4)
	sh.content_margin_left = 4
	sh.content_margin_right = 4
	sh.content_margin_top = 4
	sh.content_margin_bottom = 4
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sh)


func _make_empty_item_slot() -> Control:
	# Padding tiles fill the grid to a minimum count so the layout
	# doesn't reflow when the player goes from 8 items to 2. They wear
	# a faded version of the real slot stylebox so the grid reads as
	# "this is a slot you don't have an item in" rather than dead space.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = ITEM_SLOT_SIZE
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_ENTRY_BG_EMPTY
	s.border_color = Color(0.22, 0.21, 0.24, 0.4)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", s)
	# A faint dotted-feel midpoint label so empty slots have visual weight
	# instead of being totally blank.
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
# CLICK / HOVER
# ============================================================================

## Single-click and double-click both arrive as InputEventMouseButton through
## gui_input. We branch on event.double_click.
func _on_slot_gui_input(event: InputEvent, slot: Button) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if mb.double_click:
		_on_slot_double_clicked(slot)
	else:
		_on_slot_clicked(slot)


func _on_slot_clicked(slot: Button) -> void:
	_select_slot(slot)
	_update_tooltip_for(slot)


func _on_slot_double_clicked(slot: Button) -> void:
	var kind: String = slot.get_meta("kind", "")
	match kind:
		"item":
			_activate_inventory_item(slot.get_meta("item"))
		"equip":
			# Double-click on equipment slot unequips it.
			_unequip_slot(slot.get_meta("slot_id"))


func _activate_inventory_item(item: Item) -> void:
	if item is Armor:
		RunState.equip_armor(item)
		return
	if item is Weapon:
		# Drop into the first compatible empty slot. Players who want a
		# specific slot can drag-and-drop instead.
		_auto_equip_weapon(item)
		return
	if item is ConsumableItem:
		var player: Node = get_tree().get_first_node_in_group("player")
		if not player:
			return
		var consumable: ConsumableItem = item
		if consumable.on_use(player):
			RunState.remove_one_from_inventory(item)


func _auto_equip_weapon(w: Weapon) -> void:
	# 2H equipping requires the OTHER slot be empty. If the incoming
	# weapon is two-handed, we unequip both slots first so the equip
	# can succeed. If the incoming weapon is one-handed but a 2H
	# weapon currently occupies either slot, that 2H weapon has to go
	# first too — same enforcement, same fix.
	#
	# This matches the player's mental model of "click a weapon to
	# wield it." Without this, clicking a greataxe while holding a
	# dagger + bow would no-op silently, which is the wrong
	# affordance.
	if w.two_handed:
		# Both slots must be empty for the 2H to fit; clear them.
		if RunState.primary_weapon != null:
			RunState.unequip_weapon_slot("primary")
		if RunState.secondary_weapon != null:
			RunState.unequip_weapon_slot("secondary")
		RunState.equip_primary(w)
		return
	# Incoming is 1H. If a 2H weapon is in either slot, free that slot.
	if RunState.primary_weapon != null and RunState.primary_weapon.two_handed:
		RunState.unequip_weapon_slot("primary")
	if RunState.secondary_weapon != null and RunState.secondary_weapon.two_handed:
		RunState.unequip_weapon_slot("secondary")
	# Primary first, then secondary, then overwrite primary.
	if RunState.primary_weapon == null:
		RunState.equip_primary(w)
	elif RunState.secondary_weapon == null:
		RunState.equip_secondary(w)
	else:
		RunState.equip_primary(w)


func _unequip_slot(slot_id: String) -> void:
	match slot_id:
		"helmet", "chest", "boots":
			RunState.unequip_armor(slot_id)
		"primary", "secondary", "prepared_primary", "prepared_secondary":
			# Resolve so an unequip on a two-handed mirror slot acts on
			# the actual home slot. Without this, clicking the mirrored
			# secondary slot (when primary holds a two-handed weapon)
			# would call unequip_weapon_slot("secondary") — a no-op,
			# since RunState.secondary_weapon is already null.
			RunState.unequip_weapon_slot(_resolve_equip_slot(slot_id))


# --- Hover / selection visuals ---

func _on_slot_hovered(slot: Button) -> void:
	# Don't show tooltip while dragging — the drag preview is the feedback.
	if get_viewport().gui_is_dragging():
		return
	_update_tooltip_for(slot)

func _on_slot_unhovered() -> void:
	_hide_tooltip()


func _select_slot(slot: Button) -> void:
	# Selection persists across hover-out so the user can examine items
	# at their own pace.
	_clear_selection()
	_selected_slot = slot
	slot.modulate = COLOR_SELECTED


func _clear_selection() -> void:
	if _selected_slot and is_instance_valid(_selected_slot):
		_selected_slot.modulate = Color.WHITE
	_selected_slot = null


func _update_tooltip_for(slot: Button) -> void:
	var kind: String = slot.get_meta("kind", "")
	if kind == "item":
		var item: Item = slot.get_meta("item", null)
		if item != null:
			_show_tooltip_for_item(item, false)
		else:
			_hide_tooltip()
	elif kind == "equip":
		var slot_id: String = slot.get_meta("slot_id", "")
		var equipped: Resource = _slot_contents(slot_id)
		if equipped is Item:
			_show_tooltip_for_item(equipped, true)
		elif equipped == null:
			# Show a small tooltip for empty slots.
			_tooltip_label.text = "[color=#%s]The %s slot is empty.[/color]\n[color=#%s][i]Drop a compatible item here.[/i][/color]" % [
				COLOR_DIM_TEXT.to_html(false),
				_slot_label(slot_id),
				COLOR_FLAVOR_TEXT.to_html(false),
			]
			_tooltip_panel.visible = true
			_tooltip_panel.reset_size()
			_position_tooltip()
		else:
			_hide_tooltip()
	else:
		_hide_tooltip()


## Single formatter for both inventory items and equipped-slot contents.
## Every item type shows BOTH its description AND its mechanical stats.
func _format_detail_bbcode(item: Item, is_equipped: bool) -> String:
	var cat: String = _category_for(item)
	var accent: Color = CATEGORY_COLORS.get(cat, COLOR_BODY_TEXT)
	var lines: Array[String] = []

	# Title row: category badge + name.
	var name_str: String = item.item_name
	lines.append("[color=#%s][%s][/color]  [color=#%s][b]%s[/b][/color]" % [
		accent.to_html(false), cat.to_upper(),
		accent.to_html(false), name_str,
	])

	# Description — shown for ALL item types.
	if item.description != "":
		lines.append("[color=#%s]%s[/color]" % [
			COLOR_BODY_TEXT.to_html(false), item.description,
		])

	# Mechanical detail bullets — varies by item type.
	var bullets: Array[String] = []
	if item is ShieldWeapon:
		var s: ShieldWeapon = item
		var block_pct: int = int((1.0 - s.melee_damage_reduction) * 100)
		bullets.append("Blocks %d%% melee damage" % block_pct)
		bullets.append("Destroys projectiles on contact")
		var speed_pct: int = int((1.0 - s.movement_speed_multiplier) * 100)
		if speed_pct > 0:
			bullets.append("-%d%% move speed while blocking" % speed_pct)
		if s.max_health_bonus > 0:
			bullets.append("+%d max HP (passive)" % int(s.max_health_bonus))
		if not s.element_multipliers.is_empty():
			for elem_key in s.element_multipliers:
				var elem_mult: float = float(s.element_multipliers[elem_key])
				var elem_name: String = _element_name(int(elem_key))
				var extra_pct: int = int((1.0 - elem_mult) * 100)
				if extra_pct > 0:
					bullets.append("+%d%% %s block" % [extra_pct, elem_name])
	elif item is MeleeWeapon:
		var m: MeleeWeapon = item
		bullets.append("Damage %d  ·  cooldown %.2fs" % [int(m.base_damage), m.cooldown])
		if m.two_handed:
			bullets.append("Two-handed")
		if m.element != Weapon.Element.PHYSICAL:
			bullets.append("%s damage" % _element_name(m.element))
		if m.knockback > 300:
			bullets.append("Heavy knockback")
		if m.wielder_speed_multiplier != 1.0:
			var pct: int = int((m.wielder_speed_multiplier - 1.0) * 100)
			var prefix: String = "+" if pct > 0 else ""
			bullets.append("%s%d%% move speed while held" % [prefix, pct])
	elif item is RangedWeapon:
		var r: RangedWeapon = item
		bullets.append("Damage %d  ·  cooldown %.2fs" % [int(r.base_damage), r.cooldown])
		if r.projectile_count > 1:
			bullets.append("%d projectiles  ·  %.0f° spread" % [r.projectile_count, r.spread_degrees])
		if r.pierce > 0:
			bullets.append("Pierces %d target%s" % [r.pierce, "s" if r.pierce > 1 else ""])
		if r.element != Weapon.Element.PHYSICAL:
			bullets.append("%s damage" % _element_name(r.element))
	elif item is Weapon:
		var w: Weapon = item
		bullets.append("Damage %d  ·  cooldown %.2fs" % [int(w.base_damage), w.cooldown])

	if item is Armor:
		var a: Armor = item
		if a.damage_reduction > 0:
			bullets.append("%.0f flat damage reduction" % a.damage_reduction)
		if a.damage_taken_multiplier < 1.0:
			var pct: int = int((1.0 - a.damage_taken_multiplier) * 100)
			bullets.append("%d%% damage resistance" % pct)
		elif a.damage_taken_multiplier > 1.0:
			var pct: int = int((a.damage_taken_multiplier - 1.0) * 100)
			bullets.append("+%d%% damage taken (tradeoff)" % pct)
		if a.melee_damage_multiplier != 1.0:
			var pct: int = int((a.melee_damage_multiplier - 1.0) * 100)
			var prefix: String = "+" if pct > 0 else ""
			bullets.append("%s%d%% melee damage" % [prefix, pct])
		if a.ranged_damage_multiplier != 1.0:
			var pct: int = int((a.ranged_damage_multiplier - 1.0) * 100)
			var prefix: String = "+" if pct > 0 else ""
			bullets.append("%s%d%% ranged damage" % [prefix, pct])
		if a.move_speed_multiplier != 1.0:
			var pct: int = int((a.move_speed_multiplier - 1.0) * 100)
			var prefix: String = "+" if pct > 0 else ""
			bullets.append("%s%d%% move speed" % [prefix, pct])
		if a.max_health_bonus > 0:
			bullets.append("+%d max HP" % int(a.max_health_bonus))
		if a.noise_weight > 0:
			bullets.append("+%.0f noise while moving" % a.noise_weight)
		if not a.element_multipliers.is_empty():
			for elem_key in a.element_multipliers:
				var elem_mult: float = float(a.element_multipliers[elem_key])
				var elem_name: String = _element_name(int(elem_key))
				if elem_mult < 1.0:
					var pct: int = int((1.0 - elem_mult) * 100)
					bullets.append("+%d%% %s resist" % [pct, elem_name])
				elif elem_mult > 1.0:
					var pct: int = int((elem_mult - 1.0) * 100)
					bullets.append("-%d%% %s resist (weakness)" % [pct, elem_name])

	for b in bullets:
		lines.append("  [color=#%s]• %s[/color]" % [
			COLOR_BODY_TEXT.to_html(false), b,
		])

	# Action hint.
	var action_hint: String = ""
	if is_equipped:
		action_hint = "Double-click to unequip, or drag back to inventory."
	elif item is ConsumableItem:
		action_hint = "Double-click to use."
	elif item is Armor or item is Weapon:
		action_hint = "Double-click to equip, or drag onto a slot."
	if action_hint != "":
		lines.append("[color=#%s][i]%s[/i][/color]" % [
			COLOR_FLAVOR_TEXT.to_html(false), action_hint,
		])

	return "\n".join(lines)


## Human-readable element name for tooltip display.
static func _element_name(elem: int) -> String:
	match elem:
		Weapon.Element.PHYSICAL:  return "Physical"
		Weapon.Element.FIRE:      return "Fire"
		Weapon.Element.ICE:       return "Ice"
		Weapon.Element.LIGHTNING: return "Lightning"
		Weapon.Element.POISON:    return "Poison"
		Weapon.Element.HOLY:      return "Holy"
		Weapon.Element.DARK:      return "Dark"
	return "Unknown"


## Resolve the category string used by the color map. Most items expose
## a `category` String; Weapon subclasses set theirs to "melee"/"ranged"/
## "spell". Falls back to "misc" if nothing maps cleanly.
func _category_for(res: Resource) -> String:
	if res is Item:
		var c: String = (res as Item).category
		if c != "" and c != "misc":
			return c
		# Item base category is "misc" by default; surface a more
		# meaningful one if we can infer from subclass.
		if res is Weapon:
			return (res as Weapon).category
		if res is Armor:
			return "armor"
		if res is ConsumableItem:
			return "consumable"
	return "misc"


# ============================================================================
# DRAG & DROP
# ============================================================================
##
## Drag flow:
##   1. _get_drag_data_* builds a payload with {item, source_kind, source_id}
##      and creates a small preview node (Godot will follow the cursor with it).
##   2. _can_drop_data_* tints the target green/red while hovering.
##   3. _drop_data_* performs the actual equip/unequip/swap.
##
## A note on "set_drag_forwarding": this Godot 4 method routes a Control's
## drag-and-drop hooks through callables on the parent (or any other object).
## It lets us write all this in one script instead of one Button subclass per
## slot type. The callables receive (at_position, [extra_args], data) — we
## bind the slot reference as the extra arg.

func _get_drag_data_item(_at_position: Vector2, slot: Button) -> Variant:
	var item: Item = slot.get_meta("item", null)
	if item == null:
		return null
	# Hide source while dragging so it's clear what's moving.
	slot.modulate = Color(1, 1, 1, 0.4)
	
	# Pass the icon texture if it exists
	var tex: Texture2D = item.icon if "icon" in item else null
	slot.set_drag_preview(_make_drag_preview(item.placeholder_color, item.item_name, tex))
	return {"item": item, "source": "inventory"}


func _can_drop_data_item(_at_position: Vector2, data: Variant, slot: Button) -> bool:
	# Items grid only accepts drops from equipment slots (i.e., unequip).
	# Inventory→inventory reordering isn't supported yet.
	if not (data is Dictionary):
		return false
	var ok: bool = data.get("source") == "equip"
	_tint_drop_target(slot, ok)
	return ok


func _drop_data_item(_at_position: Vector2, data: Variant, _slot: Button) -> void:
	# Restore tints. The slot param isn't used because items-grid drops
	# go through the same unequip path regardless of which slot was hit.
	_clear_drop_tints()
	if not (data is Dictionary):
		return
	var source_id: String = data.get("source_id", "")
	if source_id != "":
		_unequip_slot(source_id)


func _get_drag_data_equip(_at_position: Vector2, slot: Button) -> Variant:
	var slot_id: String = slot.get_meta("slot_id", "")
	var contents: Resource = _slot_contents(slot_id)
	if contents == null:
		return null
	# Visual cue on the source while drag is active.
	slot.modulate = Color(1, 1, 1, 0.4)
	
	var col: Color = (contents as Item).placeholder_color if contents is Item else Color.WHITE
	var display_name: String = (contents as Item).item_name if contents is Item else ""
	var tex: Texture2D = contents.icon if "icon" in contents else null
	
	slot.set_drag_preview(_make_drag_preview(col, display_name, tex))
	# Encode the *resolved* slot id in source_id so subsequent
	# unequip-via-drop acts on the actual home slot. For a two-handed
	# weapon mirrored from primary into secondary, dragging from the
	# secondary slot reports source_id="primary" — the drop handler
	# can then unequip cleanly even though the user grabbed the mirror.
	return {"item": contents, "source": "equip", "source_id": _resolve_equip_slot(slot_id)}


func _can_drop_data_equip(_at_position: Vector2, data: Variant, slot: Button) -> bool:
	if not (data is Dictionary):
		return false
	var item: Resource = data.get("item")
	var slot_id: String = slot.get_meta("slot_id", "")
	var ok: bool = RunState.can_equip_to_slot(slot_id, item)
	_tint_drop_target(slot, ok)
	return ok


func _drop_data_equip(_at_position: Vector2, data: Variant, slot: Button) -> void:
	_clear_drop_tints()
	if not (data is Dictionary):
		return
	var item: Resource = data.get("item")
	var slot_id: String = slot.get_meta("slot_id", "")
	var source: String = data.get("source", "")
	var source_id: String = data.get("source_id", "")

	# If it's an equip→equip move (i.e., a swap), clear the source first
	# so we don't end up with the same item in two slots.
	if source == "equip" and source_id != slot_id:
		_unequip_slot(source_id)

	# Then equip into the target. equip_to_slot returns false if the
	# type is wrong — _can_drop_data_equip should have prevented this,
	# but defending is cheap.
	RunState.equip_to_slot(slot_id, item)


# --- Deconstruct slot drag callbacks ---
#
# These three mirror the pattern of the inventory/equip callbacks
# above, but the slot is drop-only (the player never picks something
# UP from it; broken-down items vanish). The accept rule is: source
# must be "inventory" (not from equipment slots — players have to
# explicitly unequip first, which preserves the equip-slot's drag
# affordance for actual swaps) AND the item must be deconstructible.
#
# Currency_cost recipes (buy-style) qualify too — Item.can_deconstruct
# returns true if ANY of inputs / requires_weapon / currency_cost is
# non-trivial. So a bought reagent dropped here refunds souls.

func _get_drag_data_decon(_at_position: Vector2, _slot: Button) -> Variant:
	# Never draggable. Returning null tells Godot "this control isn't
	# a drag source," same as if no callback were attached.
	return null


func _can_drop_data_decon(_at_position: Vector2, data: Variant, slot: Button) -> bool:
	if not (data is Dictionary):
		return false
	# Only inventory items can be dropped into decon. Equipped items have
	# to be unequipped first (a deliberate friction — destroying an
	# equipped item is the kind of mistake worth one extra click of
	# confirmation).
	if data.get("source") != "inventory":
		_tint_drop_target(slot, false)
		return false
	var item: Item = data.get("item")
	var ok: bool = item != null and item.can_deconstruct()
	_tint_drop_target(slot, ok)
	return ok


func _drop_data_decon(_at_position: Vector2, data: Variant, _slot: Button) -> void:
	_clear_drop_tints()
	if not (data is Dictionary):
		return
	var item: Item = data.get("item")
	if item == null or not item.can_deconstruct():
		return
	var salvage: Dictionary = item.deconstruct()
	_show_salvage_toast(item, salvage)
	# The inventory grid will redraw via the inventory_changed signal
	# that RunState.remove_one_from_inventory fires; we don't need to
	# explicitly refresh here.


## Build a human-readable summary of what came back from a deconstruct
## and show it as a transient toast. Picks one of three message
## shapes depending on whether anything was salvaged:
##   - nothing → "The X crumbles. Nothing useful comes out."
##   - one thing → "The X yields: 2 Cold-Iron Filing."
##   - multiple → "The X yields: 2 Cold-Iron Filing, 1 Peat-Pitch, 60 souls."
## The toast tint shifts subtly by salvage value: muted when nothing,
## warm gold when something. Lets the player feel a single-glance
## difference between a wasted decon and a productive one.
func _show_salvage_toast(source_item: Item, salvage: Dictionary) -> void:
	var parts: Array[String] = []
	for entry in salvage["items"]:
		var count: int = entry["count"]
		var nm: String = entry["item"].item_name
		parts.append("%d %s" % [count, nm])
	for w in salvage["weapons"]:
		# Weapons return at most one per decon (binary roll), so the
		# count prefix would always be "1 ×" — skip it for cleaner read.
		parts.append((w as Weapon).weapon_name)
	if salvage["souls"] > 0:
		parts.append("%d souls" % salvage["souls"])

	var msg: String
	var tint: Color
	if parts.is_empty():
		msg = "The %s crumbles. Nothing useful comes out." % source_item.item_name
		tint = Color(0.30, 0.18, 0.18, 0.85)
	else:
		msg = "The %s yields: %s." % [source_item.item_name, ", ".join(parts)]
		tint = Color(0.42, 0.32, 0.18, 0.85)
	Toast.show_message(msg, tint)


# --- Helpers ---

func _make_drag_preview(col: Color, drop_label: String, tex: Texture2D = null) -> Control:
	# A small floating preview that sticks to the cursor during drag.
	# Godot calls this on the ROOT of the cursor — keep it lightweight.
	var preview := PanelContainer.new()
	preview.modulate = Color(1, 1, 1, 0.85)
	
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(64, 72)
	preview.add_child(v)
	
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(40, 40)
	v.add_child(icon_container)
	
	# Use texture if present, fallback to ColorRect if not
	if tex:
		var texture_rect := TextureRect.new()
		texture_rect.texture = tex
		texture_rect.custom_minimum_size = Vector2(32, 32)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_container.add_child(texture_rect)
	else:
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.color = col
		icon_container.add_child(icon)
		
	var lbl := Label.new()
	lbl.text = drop_label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	v.add_child(lbl)
	
	return preview


func _tint_drop_target(slot: Button, ok: bool) -> void:
	# Subtle outline-style cue: brighten or darken the slot's modulate.
	# We restore it when the cursor leaves the slot or the drag ends.
	slot.modulate = COLOR_DROP_OK if ok else COLOR_DROP_BAD
	_tinted_drop_target = slot


## Restore one slot's modulate without touching others. Used when the cursor
## leaves a tinted slot mid-drag (so the red/green tint doesn't stick).
func _clear_tint_on(slot: Button) -> void:
	if not is_instance_valid(slot):
		return
	# If this is the source slot of the current drag, it was set to 0.4
	# alpha — the drag-end branch will restore it. Otherwise restore now.
	if get_viewport().gui_is_dragging():
		# Mid-drag: only restore if it's NOT the source slot. We can detect
		# the source by its alpha (~0.4). Fudge a little for floats.
		if abs(slot.modulate.a - 0.4) < 0.05:
			return
	slot.modulate = Color.WHITE
	# Re-apply selection highlight if it lives on this slot.
	if _selected_slot == slot:
		slot.modulate = COLOR_SELECTED


func _clear_drop_tints() -> void:
	for s in _all_slots:
		if is_instance_valid(s):
			s.modulate = Color.WHITE
	for child in _items_grid.get_children():
		if child is Button:
			(child as Button).modulate = Color.WHITE
	# Re-apply selection if anything was selected.
	if _selected_slot and is_instance_valid(_selected_slot):
		_selected_slot.modulate = COLOR_SELECTED
	_tinted_drop_target = null


func _slot_contents(slot_id: String) -> Resource:
	match slot_id:
		"helmet":    return RunState.helmet
		"chest":     return RunState.chest
		"boots":     return RunState.boots
		"primary":
			if RunState.primary_weapon == null \
					and RunState.secondary_weapon is Weapon \
					and (RunState.secondary_weapon as Weapon).two_handed:
				return RunState.secondary_weapon
			return RunState.primary_weapon
		"secondary":
			if RunState.secondary_weapon == null \
					and RunState.primary_weapon is Weapon \
					and (RunState.primary_weapon as Weapon).two_handed:
				return RunState.primary_weapon
			return RunState.secondary_weapon
		"prepared_primary":
			# Two-handed mirroring for prepared set — same logic as active.
			if RunState.prepared_primary == null \
					and RunState.prepared_secondary is Weapon \
					and (RunState.prepared_secondary as Weapon).two_handed:
				return RunState.prepared_secondary
			return RunState.prepared_primary
		"prepared_secondary":
			if RunState.prepared_secondary == null \
					and RunState.prepared_primary is Weapon \
					and (RunState.prepared_primary as Weapon).two_handed:
				return RunState.prepared_primary
			return RunState.prepared_secondary
	return null


## Resolves a logical (UI) slot id to the physical (RunState) slot id
## where the displayed weapon actually lives. For two-handed weapons
## displayed in the mirror slot, this returns the "real home" slot;
## otherwise it's the identity function.
##
## Used by every operation that needs to mutate RunState based on a UI
## interaction (unequip on double-click, drag source bookkeeping). If
## we passed the raw slot id straight through, a click on the mirrored
## slot would no-op (RunState.<that slot>.weapon is null), and the
## visual feedback would lie about being interactable.
func _resolve_equip_slot(slot_id: String) -> String:
	# Active weapon pair mirroring.
	if slot_id == "secondary" \
			and RunState.secondary_weapon == null \
			and RunState.primary_weapon is Weapon \
			and (RunState.primary_weapon as Weapon).two_handed:
		return "primary"
	if slot_id == "primary" \
			and RunState.primary_weapon == null \
			and RunState.secondary_weapon is Weapon \
			and (RunState.secondary_weapon as Weapon).two_handed:
		return "secondary"
	# Prepared weapon pair mirroring — same logic.
	if slot_id == "prepared_secondary" \
			and RunState.prepared_secondary == null \
			and RunState.prepared_primary is Weapon \
			and (RunState.prepared_primary as Weapon).two_handed:
		return "prepared_primary"
	if slot_id == "prepared_primary" \
			and RunState.prepared_primary == null \
			and RunState.prepared_secondary is Weapon \
			and (RunState.prepared_secondary as Weapon).two_handed:
		return "prepared_secondary"
	return slot_id


func _slot_label(slot_id: String) -> String:
	match slot_id:
		"helmet":             return "Helmet"
		"chest":              return "Chest"
		"boots":              return "Boots"
		"primary":            return "Primary weapon"
		"secondary":          return "Secondary weapon"
		"prepared_primary":   return "Prepared primary"
		"prepared_secondary": return "Prepared secondary"
	return slot_id
