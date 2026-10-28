extends CanvasLayer
## Unified tab strip overlay that floats above ALL four menu screens —
## Inventory, Kennings, Quests, Map. Stardew-style: the strip is visible
## whenever any of those menus is open; clicking a tab closes whichever
## is currently open and opens the target. Hotkeys (I/K/J/M/Esc) keep
## working as they did before.
##
## Design choices and trade-offs:
##   - Mouse-click only. Hotkeys could intercept here too, but they'd
##     fight each menu's own `_input`/`_unhandled_input` handlers and the
##     resulting "who handled it first" web is fragile. Tabs ARE the
##     unified affordance; hotkeys remain per-menu.
##   - Layer 45 so the strip floats above WorldMap (layer 40), which
##     otherwise paints a full-screen background that would eat clicks.
##     Still below SceneTransition (layer 50) so a fade-out covers it.
##   - The four target UIs aren't modified. We call each one's existing
##     `_toggle()` to flip them. Close current, then open target — never
##     the other way around, so the tree-paused state stays consistent
##     and the player never sees two menus drawn over each other.
##
## NOTE: No class_name — registered as autoload "MenuTabs".

const TAB_WIDTH: float = 144.0
const TAB_HEIGHT: float = 36.0
const TAB_GAP: float = 4.0
const STRIP_TOP_PADDING: float = 6.0

# Same gold accent used by every menu title — keeps the whole "menu
# language" feeling like one thing.
const COLOR_ACTIVE_BG := Color(0.20, 0.18, 0.14, 0.96)
const COLOR_ACTIVE_BORDER := Color(0.95, 0.85, 0.40, 0.95)
const COLOR_ACTIVE_TEXT := Color(0.95, 0.85, 0.40)
const COLOR_INACTIVE_BG := Color(0.10, 0.09, 0.12, 0.92)
const COLOR_INACTIVE_BORDER := Color(0.40, 0.38, 0.34, 0.55)
const COLOR_INACTIVE_TEXT := Color(0.75, 0.72, 0.65)
const COLOR_INACTIVE_HOVER_BG := Color(0.18, 0.16, 0.18, 0.95)

## Each tab definition: { id, label, hotkey_label }
const TABS: Array = [
	{ "id": "inventory", "label": "Inventory", "hotkey": "I" },
	{ "id": "runes",     "label": "Runes",     "hotkey": "R" },
	{ "id": "kennings",  "label": "Kennings",  "hotkey": "K" },
	{ "id": "quests",    "label": "Quests",    "hotkey": "J" },
	{ "id": "map",       "label": "Map",       "hotkey": "M" },
]


var _root: Control
var _strip: HBoxContainer
var _tab_buttons: Dictionary = {}  # tab_id -> Button


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 45
	_build_ui()
	visible = false


func _process(_delta: float) -> void:
	# Show the strip whenever any of the four panels is open. Polling is
	# simple and cheap (four bool reads per frame); doing this with
	# signals would mean adding "panel_opened/closed" signals to each
	# autoload, which is more invasive than is worth it for four reads.
	var any_open: bool = _is_open("inventory") or _is_open("runes") \
		or _is_open("kennings") or _is_open("quests") or _is_open("map")
	visible = any_open
	if any_open:
		_update_active_styling()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	# Full-screen Control with no mouse capture so clicks fall through
	# to the strip's child buttons only — the rest of the screen is
	# still owned by whichever menu panel is below us.
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Top-center anchored strip. Width is computed from tab count so it
	# auto-recenters if we add tabs later.
	var strip_width: float = (TAB_WIDTH * TABS.size()) + (TAB_GAP * (TABS.size() - 1))
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", int(TAB_GAP))
	_strip.anchor_left = 0.5
	_strip.anchor_right = 0.5
	_strip.offset_left = -strip_width * 0.5
	_strip.offset_right = strip_width * 0.5
	_strip.offset_top = STRIP_TOP_PADDING
	_strip.offset_bottom = STRIP_TOP_PADDING + TAB_HEIGHT
	_root.add_child(_strip)

	for tab in TABS:
		var btn := _make_tab_button(tab["id"], tab["label"], tab["hotkey"])
		_strip.add_child(btn)
		_tab_buttons[tab["id"]] = btn


func _make_tab_button(tab_id: String, label_text: String, hotkey: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(TAB_WIDTH, TAB_HEIGHT)
	btn.set_meta("tab_id", tab_id)
	btn.text = "%s   [%s]" % [label_text, hotkey]
	btn.add_theme_font_size_override("font_size", 13)

	# Three styles applied below in _apply_tab_style; this just establishes
	# them in stylebox slots so changes don't recreate the buttons.
	_apply_tab_style(btn, false)

	btn.pressed.connect(func() -> void:
		_on_tab_clicked(tab_id)
	)
	return btn


## Repaint a tab's styleboxes for either the active or inactive state.
## Called from _update_active_styling each frame the strip is visible,
## so a click that changes which menu is open is reflected immediately
## without us needing to wire signals.
func _apply_tab_style(btn: Button, is_active: bool) -> void:
	var bg_color: Color = COLOR_ACTIVE_BG if is_active else COLOR_INACTIVE_BG
	var border_color: Color = COLOR_ACTIVE_BORDER if is_active else COLOR_INACTIVE_BORDER
	var text_color: Color = COLOR_ACTIVE_TEXT if is_active else COLOR_INACTIVE_TEXT
	var border_width: int = 2 if is_active else 1

	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.border_color = border_color
	s.border_width_left = border_width
	s.border_width_right = border_width
	s.border_width_top = border_width
	# Active tab "merges" into the panel below — flat bottom edge,
	# rounded only on top. Inactive tabs round all corners so they read
	# as separate, raised pills.
	if is_active:
		s.corner_radius_top_left = 6
		s.corner_radius_top_right = 6
		s.corner_radius_bottom_left = 0
		s.corner_radius_bottom_right = 0
		# Hide the bottom border for the active tab so it visually flows
		# into whatever menu panel is below it.
		s.border_width_bottom = 0
	else:
		s.set_corner_radius_all(4)
		s.border_width_bottom = border_width
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", COLOR_ACTIVE_TEXT)

	# Hover state for inactive tabs — slightly brighter bg so a player
	# scanning the strip can see which one their cursor is over.
	var s_hover := StyleBoxFlat.new()
	s_hover.bg_color = COLOR_INACTIVE_HOVER_BG if not is_active else bg_color
	s_hover.border_color = COLOR_ACTIVE_BORDER if not is_active else border_color
	s_hover.border_width_left = border_width
	s_hover.border_width_right = border_width
	s_hover.border_width_top = border_width
	s_hover.border_width_bottom = 0 if is_active else border_width
	if is_active:
		s_hover.corner_radius_top_left = 6
		s_hover.corner_radius_top_right = 6
	else:
		s_hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", s_hover)


func _update_active_styling() -> void:
	# Determine which tab is currently active — at most one (the first
	# panel we find that's open). If more than one is open simultaneously
	# (shouldn't happen, but defend), the priority order matches TABS.
	var active_id: String = ""
	for tab in TABS:
		if _is_open(tab["id"]):
			active_id = tab["id"]
			break
	for tab_id in _tab_buttons:
		_apply_tab_style(_tab_buttons[tab_id], tab_id == active_id)


# ============================================================================
# TAB CLICKING
# ============================================================================

func _on_tab_clicked(target_id: String) -> void:
	# If the clicked tab is already active, treat the click as "close
	# this menu" — feels natural in a tabbed UI (you can't click into
	# nowhere). The user can also still hit Esc.
	if _is_open(target_id):
		_toggle(target_id)
		return

	# Close whichever menu is currently open. Always close BEFORE
	# opening the target — opening first would briefly leave both
	# visible, and the tree pause state would flicker.
	for tab in TABS:
		if _is_open(tab["id"]):
			_toggle(tab["id"])
			break

	# Open the target.
	_toggle(target_id)


# ============================================================================
# PANEL DISPATCH — these adapt our generic tab ids to each autoload's
# specific visibility property and toggle method.
# ============================================================================

func _is_open(tab_id: String) -> bool:
	match tab_id:
		"inventory": return InventoryUI.visible
		"runes":     return RunesUI.visible
		"kennings":  return KenningsUI.visible
		"quests":    return QuestUI.visible
		# WorldMap exposes is_open instead of relying on the CanvasLayer
		# `visible` flag, because it manages its own pause cycle and the
		# `visible` flag is set as a side-effect of is_open. is_open IS
		# the source of truth there.
		"map":       return WorldMap.is_open
	return false


func _toggle(tab_id: String) -> void:
	# Each panel UI has its own _toggle() method that handles
	# visibility + tree pause. We call them directly. They're "private
	# by convention" in GDScript (the leading underscore is style only).
	match tab_id:
		"inventory": InventoryUI._toggle()
		"runes":     RunesUI._toggle()
		"kennings":  KenningsUI._toggle()
		"quests":    QuestUI._toggle()
		"map":       WorldMap._toggle()
