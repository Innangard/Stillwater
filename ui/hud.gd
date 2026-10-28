extends CanvasLayer
## On-screen HUD: health bar, currency, weapon slots with cooldowns,
## status effect indicators, floating damage numbers.
##
## Also owns three pieces of "moment feedback" that punctuate combat
## without belonging to any single in-world node:
##   - Perfect-dodge pulse (text + hit-stop on EventBus.player_perfect_dodge)
##   - Long-stun stagger flash (text + hit-stop on EventBus.enemy_staggered
##     when is_long_stun is true)
##   - Boss stagger bar (driven by EventBus.boss_stagger_changed)
##
## NOTE: No class_name — registered as autoload "HUD".

const FLOAT_NUMBER_LIFETIME := 0.85
const FLOAT_NUMBER_RISE := 32.0

# --- Visual language — kept in sync with menu_tabs.gd / inventory_ui.gd /
# kennings_ui.gd / quest_ui.gd. The HUD lives outside the menu stack, but
# the player flips between gameplay and menus constantly, so the shared
# Norse-dark / gold-accent palette makes the menus feel like an extension
# of the HUD rather than a context shift. Same constants, same names. ---
const COLOR_PANEL_BG       := Color(0.10, 0.09, 0.12, 0.92)
const COLOR_PANEL_BORDER   := Color(0.55, 0.50, 0.42, 0.75)
const COLOR_SLOT_BG        := Color(0.13, 0.12, 0.15, 0.95)
const COLOR_SLOT_BG_EMPTY  := Color(0.11, 0.10, 0.13, 0.90)
const COLOR_ENTRY_BORDER   := Color(0.35, 0.33, 0.38, 0.80)
const COLOR_BAR_BG         := Color(0.07, 0.06, 0.09, 0.95)
const COLOR_BAR_BORDER     := Color(0.30, 0.28, 0.26, 0.75)
const COLOR_BODY_TEXT      := Color(0.78, 0.78, 0.78)
const COLOR_DIM_TEXT       := Color(0.55, 0.50, 0.45)
const COLOR_HINT_TEXT      := Color(0.55, 0.55, 0.58)
const COLOR_CURRENCY       := Color(0.95, 0.80, 0.35)
const COLOR_HP_FILL        := Color(0.78, 0.28, 0.30)
const COLOR_NOISE_FILL     := Color(0.92, 0.78, 0.30)
const COLOR_SMELL_FILL     := Color(0.55, 0.35, 0.62)
const COLOR_BOSS_FILL      := Color(0.78, 0.22, 0.28)   # slightly deeper than HP
const COLOR_BOSS_PHASE_FLASH := Color(0.72, 0.32, 0.88) # purple — same phase tint
														# the boss body uses
# Stagger meter fill colors. Building (pale lavender) shifts to "ready"
# (bright purple) the moment the meter hits the threshold — so the
# player has a glance-readable cue that the NEXT successful parry
# triggers the long stun. Sister of COLOR_BOSS_PHASE_FLASH on purpose:
# the stagger meter is "phase change is coming" energy.
const COLOR_STAGGER_FILL   := Color(0.65, 0.50, 0.85)
const COLOR_STAGGER_READY  := Color(0.95, 0.55, 1.00)

# Perfect-dodge / long-stun text colors — distinct from any element
# color so they don't get confused with damage numbers.
const COLOR_DODGE_TEXT     := Color(0.65, 0.95, 1.00)   # icy cyan
const COLOR_STAGGER_TEXT   := Color(0.95, 0.55, 1.00)   # bright purple

# Slot dimensions — 13% smaller than the previous 120x80 (within the
# 10-15% reduction band that gives the bottom-left a lighter footprint
# without losing readability of the two-line "[KEY] Label" + name layout).
const SLOT_SIZE := Vector2(104, 70)
# Prepared slots are visually subordinate — 70% width, same height so
# the row stays aligned. Smaller text and a dimmed modulate complete
# the "ready but not active" read.
const PREPARED_SLOT_SIZE := Vector2(74, 70)
# Base dimming for prepared slots so they visually recede behind the
# active pair. During a swap the dim lifts as the slots "activate."
const PREPARED_DIM := Color(0.6, 0.6, 0.6, 0.75)

# Cooldown overlay — drawn ABOVE slot content at low opacity so it reads
# as a subtle darkening sweep rather than a solid mask. 0.35 alpha keeps
# the equipped weapon name visible through the sweep, which matters when
# a player is glancing at the HUD mid-fight to remember what's on cd.
const COOLDOWN_TINT := Color(0.05, 0.04, 0.08, 0.35)

# --- Hit-stop tuning ---
## Real-time seconds the game slows to HIT_STOP_SCALE when a long stun
## triggers. ~0.15s of 0.10x is the sweet spot from fighting-game
## research: long enough to register as a "thwack", short enough not
## to feel like lag. Perfect-dodge uses a shorter pulse (~0.06s) since
## dodges happen more often and a heavy hit-stop would feel chuggy.
const HIT_STOP_LONG_STUN := 0.15
const HIT_STOP_DODGE := 0.06
const HIT_STOP_SCALE := 0.10

var _player: Node = null

# --- HUD widgets ---
var _health_bar: ProgressBar
var _health_label: Label
var _noise_bar: ProgressBar
var _smell_bar: ProgressBar
var _currency_label: Label
var _weapon_slot_primary: Control
var _weapon_slot_secondary: Control
var _prepared_slot_primary: Control
var _prepared_slot_secondary: Control
var _status_strip: HBoxContainer
var _float_layer: Control

# --- Boss bar ---
var _boss_bar_container: Control
var _boss_bar: ProgressBar
var _boss_stagger_bar: ProgressBar
var _boss_name_label: Label
var _boss_hp_label: Label
var _boss_phase_label: Label

# effect_id -> Control
var _status_widgets: Dictionary = {}

# --- Hit-stop state ---
## Latch — concurrent hit-stop requests are ignored while one is active,
## so a dodge during a stagger (or vice versa) doesn't double-stack the
## time_scale fiddling and leave the engine in a weird state.
var _hit_stop_active: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 5
	_build_ui()

	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.noise_changed.connect(_on_noise_changed)
	EventBus.smell_changed.connect(_on_smell_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.weapon_equipped.connect(_on_weapon_equipped)
	EventBus.player_status_applied.connect(_on_status_applied)
	EventBus.player_status_removed.connect(_on_status_removed)
	EventBus.damage_dealt_visual.connect(_on_damage_dealt)
	EventBus.player_died.connect(_on_player_died)
	EventBus.run_started.connect(_on_run_started.unbind(1))
	EventBus.boss_engaged.connect(_on_boss_engaged)
	EventBus.boss_health_changed.connect(_on_boss_health_changed)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.boss_stagger_changed.connect(_on_boss_stagger_changed)
	EventBus.player_perfect_dodge.connect(_on_perfect_dodge)
	EventBus.enemy_staggered.connect(_on_enemy_staggered)

	_currency_label.text = "%d" % GameState.soul_currency
	_refresh_all_weapon_slots()


func _process(_delta: float) -> void:
	# Hide the in-world HUD whenever any menu overlay is open, so
	# health/weapon widgets don't leak through behind the menu.
	# Also hide on the title screen (no save loaded → current_slot 0)
	# so the gameplay HUD isn't drawn over the menu UI.
	visible = (SaveManager.current_slot > 0) and not (
		InventoryUI.visible or CraftingUI.visible or WorldMap.is_open \
		or QuestUI.visible or KenningsUI.visible or RunesUI.visible
	)
	_update_cooldown_overlays()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	# --- Top-left: vitals card (HP + noise + smell + status strip) ---
	# Wrapped in a single styled PanelContainer so the three bars and the
	# status row read as one "vitals" block — same panel/border language
	# the menus use. Three loose bars (the previous layout) looked like
	# raw Godot defaults next to the menus' stylebox-driven aesthetic.
	var vitals_panel := PanelContainer.new()
	vitals_panel.position = Vector2(20, 20)
	vitals_panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	add_child(vitals_panel)

	var top_left := VBoxContainer.new()
	top_left.add_theme_constant_override("separation", 5)
	vitals_panel.add_child(top_left)

	# Each bar row is a [Label][ProgressBar] grid so the three rows align
	# vertically without us hand-tuning offsets. 44px label column fits
	# "Noise" / "Smell" / "HP" at font_size 11 with breathing room.
	const LABEL_W := 44.0
	const BAR_W := 200.0

	# --- HP row ---
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	top_left.add_child(hp_row)

	var hp_label_tag := Label.new()
	hp_label_tag.text = "HP"
	hp_label_tag.custom_minimum_size = Vector2(LABEL_W, 0)
	hp_label_tag.add_theme_font_size_override("font_size", 11)
	hp_label_tag.add_theme_color_override("font_color", COLOR_HINT_TEXT)
	hp_row.add_child(hp_label_tag)

	_health_bar = _make_styled_bar(BAR_W, 18.0, COLOR_HP_FILL)
	_health_bar.max_value = 100
	_health_bar.value = 100
	hp_row.add_child(_health_bar)

	# Value text overlaid INSIDE the HP bar (Stardew/Hades style) — keeps
	# the row compact and the number is read against its own fill.
	_health_label = Label.new()
	_health_label.text = "100 / 100"
	_health_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 11)
	_health_label.add_theme_color_override("font_color", Color(0.97, 0.92, 0.85))
	_health_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_health_label.add_theme_constant_override("outline_size", 3)
	_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.add_child(_health_label)

	# --- Noise row ---
	var noise_row := HBoxContainer.new()
	noise_row.add_theme_constant_override("separation", 8)
	top_left.add_child(noise_row)

	var noise_tag := Label.new()
	noise_tag.text = "Noise"
	noise_tag.custom_minimum_size = Vector2(LABEL_W, 0)
	noise_tag.add_theme_font_size_override("font_size", 11)
	noise_tag.add_theme_color_override("font_color", COLOR_HINT_TEXT)
	noise_row.add_child(noise_tag)

	_noise_bar = _make_styled_bar(BAR_W, 8.0, COLOR_NOISE_FILL)
	_noise_bar.max_value = 100
	_noise_bar.value = 0
	_noise_bar.tooltip_text = "Noise — louder actions draw nearby ears."
	noise_row.add_child(_noise_bar)

	# --- Smell row ---
	var smell_row := HBoxContainer.new()
	smell_row.add_theme_constant_override("separation", 8)
	top_left.add_child(smell_row)

	var smell_tag := Label.new()
	smell_tag.text = "Smell"
	smell_tag.custom_minimum_size = Vector2(LABEL_W, 0)
	smell_tag.add_theme_font_size_override("font_size", 11)
	smell_tag.add_theme_color_override("font_color", COLOR_HINT_TEXT)
	smell_row.add_child(smell_tag)

	_smell_bar = _make_styled_bar(BAR_W, 8.0, COLOR_SMELL_FILL)
	_smell_bar.max_value = 100
	_smell_bar.value = 0
	_smell_bar.tooltip_text = "Smell — blood and exertion follow you."
	smell_row.add_child(_smell_bar)

	# Status effect icons — bottom row of the vitals card.
	_status_strip = HBoxContainer.new()
	_status_strip.add_theme_constant_override("separation", 4)
	top_left.add_child(_status_strip)

	# --- Top-right: currency ---
	var top_right := HBoxContainer.new()
	top_right.position = Vector2(0, 20)
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -180
	top_right.offset_right = -20
	top_right.alignment = BoxContainer.ALIGNMENT_END
	top_right.add_theme_constant_override("separation", 6)
	add_child(top_right)

	var currency_icon := ColorRect.new()
	currency_icon.custom_minimum_size = Vector2(18, 18)
	currency_icon.color = Color(1.0, 0.85, 0.2)
	top_right.add_child(currency_icon)

	_currency_label = Label.new()
	_currency_label.text = "0"
	_currency_label.add_theme_font_size_override("font_size", 18)
	top_right.add_child(_currency_label)

	# --- Bottom-left: four weapon slots ---
	# offset_top sized for the new 70px-tall slots (was -110 for 80px slots,
	# now -95 = 70 slot height + 25 margin for breathing room above the
	# screen edge). offset_bottom stays at -20 so the row hugs the same
	# corner as before, just trimmer.
	var bottom_left := HBoxContainer.new()
	bottom_left.anchor_top = 1.0
	bottom_left.anchor_bottom = 1.0
	bottom_left.offset_left = 20
	bottom_left.offset_top = -95
	bottom_left.offset_bottom = -20
	bottom_left.add_theme_constant_override("separation", 8)
	add_child(bottom_left)

	_weapon_slot_primary   = _make_weapon_slot("LMB", "Primary", SLOT_SIZE)
	_weapon_slot_secondary = _make_weapon_slot("RMB", "Secondary", SLOT_SIZE)
	bottom_left.add_child(_weapon_slot_primary)
	bottom_left.add_child(_weapon_slot_secondary)

	# Thin separator between active and prepared sets — same divider
	# language the inventory uses between armor and weapons.
	var slot_divider := VSeparator.new()
	slot_divider.add_theme_color_override("separator", COLOR_PANEL_BORDER)
	slot_divider.add_theme_constant_override("separation", 6)
	slot_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left.add_child(slot_divider)

	_prepared_slot_primary   = _make_weapon_slot("Q", "Swap", PREPARED_SLOT_SIZE)
	_prepared_slot_secondary = _make_weapon_slot("", "", PREPARED_SLOT_SIZE)
	_prepared_slot_primary.modulate = PREPARED_DIM
	_prepared_slot_secondary.modulate = PREPARED_DIM
	bottom_left.add_child(_prepared_slot_primary)
	bottom_left.add_child(_prepared_slot_secondary)

	# --- Floating damage number layer ---
	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)

	# --- Boss health bar (top center, hidden by default) ---
	# Wrapped in a PanelContainer matching the vitals card so the boss
	# fight reads as a "card" surfacing at the top of the screen, with
	# the same Norse-dark palette as every other HUD/menu element.
	#
	# Centering pattern: anchor_left = anchor_right = 0.5 collapses the
	# panel's anchor box to a vertical line at screen center. With
	# grow_horizontal = BOTH, the panel computes its minimum size from
	# its content and expands outward symmetrically around that line.
	# This auto-fits long boss names without us hand-tuning offset_left
	# / offset_right, the way the old static 360px-wide layout did.
	_boss_bar_container = PanelContainer.new()
	_boss_bar_container.anchor_left = 0.5
	_boss_bar_container.anchor_right = 0.5
	_boss_bar_container.offset_top = 12
	_boss_bar_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_bar_container.grow_vertical = Control.GROW_DIRECTION_END
	_boss_bar_container.add_theme_stylebox_override("panel", _make_panel_stylebox())
	_boss_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_container.visible = false
	add_child(_boss_bar_container)

	var boss_vbox := VBoxContainer.new()
	boss_vbox.add_theme_constant_override("separation", 4)
	boss_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_container.add_child(boss_vbox)

	_boss_name_label = Label.new()
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_name_label.add_theme_font_size_override("font_size", 16)
	# Gold accent — same color the menu tabs use for active state. The
	# title-row gold is the strongest signal of "menu language" so
	# reusing it on the boss banner makes the moment feel intentional.
	_boss_name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.40))
	_boss_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_name_label.add_theme_constant_override("outline_size", 3)
	boss_vbox.add_child(_boss_name_label)

	_boss_bar = _make_styled_bar(360.0, 18.0, COLOR_BOSS_FILL)
	_boss_bar.max_value = 100
	_boss_bar.value = 100
	boss_vbox.add_child(_boss_bar)

	# --- Stagger meter row, under the HP bar. ---
	# 6px thin bar to read as "secondary track" — HP is the primary
	# 18px gauge, stagger is the supporting tempo gauge. Tag-on-left
	# so it visually parallels the HP/Noise/Smell rows on the vitals
	# card. Always visible during the fight (sits at 0 when empty)
	# so the player understands the threshold geometry — the empty
	# bar IS the lesson "fill me up."
	var boss_stagger_row := HBoxContainer.new()
	boss_stagger_row.alignment = BoxContainer.ALIGNMENT_CENTER
	boss_stagger_row.add_theme_constant_override("separation", 6)
	boss_vbox.add_child(boss_stagger_row)

	var boss_stagger_tag := Label.new()
	boss_stagger_tag.text = "Stagger"
	boss_stagger_tag.add_theme_font_size_override("font_size", 10)
	boss_stagger_tag.add_theme_color_override("font_color", COLOR_HINT_TEXT)
	boss_stagger_row.add_child(boss_stagger_tag)

	_boss_stagger_bar = _make_styled_bar(280.0, 6.0, COLOR_STAGGER_FILL)
	_boss_stagger_bar.max_value = 1.0
	_boss_stagger_bar.value = 0.0
	_boss_stagger_bar.tooltip_text = "Stagger — parry wind-ups to fill. At full, the next parry triggers a long stun."
	boss_stagger_row.add_child(_boss_stagger_bar)

	var boss_info_row := HBoxContainer.new()
	boss_info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	boss_info_row.add_theme_constant_override("separation", 12)
	boss_vbox.add_child(boss_info_row)

	_boss_hp_label = Label.new()
	_boss_hp_label.add_theme_font_size_override("font_size", 12)
	_boss_hp_label.add_theme_color_override("font_color", COLOR_BODY_TEXT)
	boss_info_row.add_child(_boss_hp_label)

	_boss_phase_label = Label.new()
	_boss_phase_label.add_theme_font_size_override("font_size", 12)
	_boss_phase_label.add_theme_color_override("font_color", Color(0.78, 0.62, 0.92))
	boss_info_row.add_child(_boss_phase_label)


func _make_weapon_slot(input_hint: String, slot_label: String,
		size: Vector2 = SLOT_SIZE) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	panel.set_meta("input_hint", input_hint)
	panel.set_meta("slot_label", slot_label)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Apply the empty-slot stylebox (dim border). _refresh_weapon_slot
	# repaints with a category-colored border once a weapon is equipped,
	# mirroring inventory_ui.gd's _apply_equip_slot_style behaviour so the
	# HUD slot and the inventory slot for the same weapon look like
	# variations of one component, not two different widgets.
	_apply_slot_style(panel, COLOR_ENTRY_BORDER, 1, false)

	# Content holder — a plain Control (NOT a Container) wrapping the
	# slot's inner widgets. We need this because PanelContainer is a
	# Container and auto-fits every direct child to its content rect on
	# every layout pass, which would clobber the cooldown overlay's
	# anchor manipulation (the cd ColorRect needs anchor_bottom in [0,1]
	# to tween its height, but the container would re-fit it back to
	# full size each frame). One Control child of the PanelContainer
	# gives the container something to fit, and that Control's children
	# get to keep their explicit anchors/offsets.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(holder)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 3)
	holder.add_child(vbox)

	var hint := Label.new()
	hint.text = "[%s] %s" % [input_hint, slot_label]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", COLOR_HINT_TEXT)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)

	var name_label := Label.new()
	name_label.text = "— empty —"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)
	panel.set_meta("name_label", name_label)

	# Cooldown overlay — drawn ABOVE slot content (z_index=1, and also
	# added to the tree after vbox so both reasons agree). Lower alpha
	# (COOLDOWN_TINT ≈ 0.35) reads as a subtle darkening sweep rather
	# than a solid mask, so the equipped weapon name stays legible while
	# the cd ticks down — important for at-a-glance reads mid-combat.
	#
	# Initial anchors: anchor_bottom=0 with offset_bottom=0 → zero-height
	# rect pinned to the top of the holder (= invisible overlay = no cd).
	# _set_cooldown_ratio drives anchor_bottom upward to grow the overlay
	# downward as the cooldown progresses.
	var cd := ColorRect.new()
	cd.color = COOLDOWN_TINT
	cd.anchor_left = 0.0
	cd.anchor_right = 1.0
	cd.anchor_top = 0.0
	cd.anchor_bottom = 0.0
	cd.offset_left = 0
	cd.offset_right = 0
	cd.offset_top = 0
	cd.offset_bottom = 0
	cd.z_index = 1
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cd)
	panel.set_meta("cooldown_rect", cd)

	return panel


# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_player_spawned(player: Node) -> void:
	_player = player
	_health_bar.max_value = RunState.max_health
	_health_bar.value = RunState.current_health
	_health_label.text = "%d / %d" % [int(RunState.current_health), int(RunState.max_health)]
	_smell_bar.max_value = RunState.max_smell
	_smell_bar.value = RunState.smell
	_noise_bar.value = 0
	_refresh_all_weapon_slots()
	_currency_label.text = "%d" % GameState.soul_currency


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "%d / %d" % [int(current), int(maximum)]


func _on_noise_changed(current: float, maximum: float) -> void:
	_noise_bar.max_value = maximum
	_noise_bar.value = current


func _on_smell_changed(current: float, maximum: float) -> void:
	_smell_bar.max_value = maximum
	_smell_bar.value = current


func _on_currency_changed(new_amount: int) -> void:
	_currency_label.text = "%d" % new_amount


func _on_weapon_equipped(_weapon: Resource, slot: String) -> void:
	match slot:
		"primary":            _refresh_weapon_slot(_weapon_slot_primary, _primary_for_display())
		"secondary":          _refresh_weapon_slot(_weapon_slot_secondary, RunState.secondary_weapon)
		"prepared_primary":   _refresh_weapon_slot(_prepared_slot_primary, RunState.prepared_primary)
		"prepared_secondary": _refresh_weapon_slot(_prepared_slot_secondary, RunState.prepared_secondary)


func _on_status_applied(effect: Resource, stacks: int) -> void:
	if effect == null or not (effect is StatusEffect):
		return
	var fx: StatusEffect = effect
	if _status_widgets.has(fx.effect_id):
		_update_status_widget(_status_widgets[fx.effect_id], fx, stacks)
		return
	var w: Control = _make_status_widget(fx, stacks)
	_status_widgets[fx.effect_id] = w
	_status_strip.add_child(w)


func _on_status_removed(effect: Resource) -> void:
	if effect == null or not (effect is StatusEffect):
		return
	var fx: StatusEffect = effect
	if not _status_widgets.has(fx.effect_id):
		return
	var w: Control = _status_widgets[fx.effect_id]
	_status_widgets.erase(fx.effect_id)
	_status_strip.remove_child(w)
	w.queue_free()


func _on_damage_dealt(target: Node, amount: float, info: Dictionary) -> void:
	if not is_instance_valid(target) or amount <= 0.0:
		return
	_spawn_damage_number(target, amount, info)


func _on_player_died() -> void:
	_health_bar.value = 0
	_health_label.text = "0 / %d" % int(RunState.max_health)
	for id in _status_widgets.keys():
		var w: Control = _status_widgets[id]
		_status_strip.remove_child(w)
		w.queue_free()
	_status_widgets.clear()
	_hide_boss_bar()


func _on_run_started() -> void:
	for id in _status_widgets.keys():
		var w: Control = _status_widgets[id]
		_status_strip.remove_child(w)
		w.queue_free()
	_status_widgets.clear()
	_refresh_all_weapon_slots()
	_hide_boss_bar()


func _on_boss_engaged(boss_name: String, current_hp: float, max_hp: float) -> void:
	_boss_name_label.text = boss_name
	_boss_bar.max_value = max_hp
	_boss_bar.value = current_hp
	_boss_hp_label.text = "%d / %d" % [int(current_hp), int(max_hp)]
	_boss_phase_label.text = "Phase 1"
	# Reset the fill stylebox color in case a previous fight ended
	# mid-phase-flash and left the bar tinted purple. Cheap; idempotent.
	var fill_box: StyleBoxFlat = _boss_bar.get_meta("fill_stylebox")
	fill_box.bg_color = _boss_bar.get_meta("fill_color")
	# Reset the stagger bar too — fresh fight starts empty, even if the
	# previous fight ended mid-meter (which can happen if the boss died
	# from chip damage and the player never landed the long-stun parry).
	_boss_stagger_bar.value = 0
	var stagger_fill: StyleBoxFlat = _boss_stagger_bar.get_meta("fill_stylebox")
	stagger_fill.bg_color = COLOR_STAGGER_FILL
	_boss_bar_container.visible = true


func _on_boss_health_changed(current_hp: float, max_hp: float) -> void:
	_boss_bar.max_value = max_hp
	_boss_bar.value = current_hp
	_boss_hp_label.text = "%d / %d" % [int(current_hp), int(max_hp)]


func _on_boss_phase_changed(phase: int) -> void:
	_boss_phase_label.text = "Phase %d" % phase
	# Flash the bar purple briefly for phase transition. We tween the
	# fill stylebox's bg_color directly (stashed in meta by _make_styled_bar)
	# rather than _boss_bar.modulate — modulate would tint the dark
	# background stylebox too, muddying the flash. This keeps the bg
	# crisp and only the filled portion pulses purple.
	var fill_box: StyleBoxFlat = _boss_bar.get_meta("fill_stylebox")
	var base_color: Color = _boss_bar.get_meta("fill_color")
	fill_box.bg_color = COLOR_BOSS_PHASE_FLASH
	var tween := _boss_bar.create_tween()
	tween.tween_property(fill_box, "bg_color", base_color, 0.6)


## Boss stagger meter update. The boss emits this whenever its stagger
## value changes — gain on parry, decay each frame, reset on long-stun
## trigger. We just mirror current/threshold into the bar and switch
## the fill color the moment the meter is "ready," so the player sees
## "build it → hold it → spend it."
func _on_boss_stagger_changed(current: float, threshold: float) -> void:
	# If the boss bar isn't visible (e.g. signal fired before _engaged
	# latch flipped, which shouldn't happen but defensively guard),
	# ignore — we'll get the right value when boss_engaged fires.
	if not _boss_bar_container.visible:
		return
	_boss_stagger_bar.max_value = maxf(threshold, 0.001)
	_boss_stagger_bar.value = current
	var at_threshold: bool = threshold > 0.0 and current >= threshold
	var fill_box: StyleBoxFlat = _boss_stagger_bar.get_meta("fill_stylebox")
	fill_box.bg_color = COLOR_STAGGER_READY if at_threshold else COLOR_STAGGER_FILL


func _on_boss_defeated(_boss_name: String) -> void:
	_boss_hp_label.text = "DEFEATED"
	_boss_phase_label.text = ""
	_boss_bar.value = 0
	# Fade out after a moment.
	var tween := _boss_bar_container.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(_boss_bar_container, "modulate:a", 0.0, 1.0)
	tween.tween_callback(_hide_boss_bar)


func _hide_boss_bar() -> void:
	_boss_bar_container.visible = false
	_boss_bar_container.modulate.a = 1.0


## Perfect-dodge feedback. Three pieces fire together so the player FEELS
## the dodge: a "Perfect!" text-punch at the player's position, a brief
## hit-stop (~0.06s of 0.10x time scale), and a light screen-shake.
## Player.gd already does the gameplay reward (refunds 30% of dash
## cooldown and emits its own screen-shake) — this is purely the
## satisfaction layer.
func _on_perfect_dodge() -> void:
	if is_instance_valid(_player) and _player is Node2D:
		_spawn_world_text((_player as Node2D).global_position + Vector2(0, -34),
			"Perfect!", COLOR_DODGE_TEXT, 18, 0.65, 32.0)
	_apply_hit_stop(HIT_STOP_DODGE, HIT_STOP_SCALE)


## Enemy-staggered feedback. Only the LONG-stun trigger gets the full
## HUD treatment (text + hit-stop + heavier shake) — that's the rare,
## earned beat after building the meter and landing the third parry.
## Regular short stuns happen many times per fight and are signaled
## just by the enemy's own stars-overhead drawing; piling text and
## hit-stop on every parry would feel chuggy.
func _on_enemy_staggered(enemy: Node, _duration: float, is_long_stun: bool) -> void:
	if not is_long_stun:
		return
	if is_instance_valid(enemy) and enemy is Node2D:
		_spawn_world_text((enemy as Node2D).global_position + Vector2(0, -44),
			"Staggered!", COLOR_STAGGER_TEXT, 22, 0.85, 26.0)
	_apply_hit_stop(HIT_STOP_LONG_STUN, HIT_STOP_SCALE)
	EventBus.request_screen_shake.emit(6.0, 0.2)


## Brief slow-motion pulse to give weight to a hit moment. Implemented
## via Engine.time_scale with a real-time timer (ignore_time_scale=true
## so the timer fires in wall-clock seconds even though the engine is
## running slow). The latch prevents stacked triggers from racing each
## other to restore time_scale and leaving the game permanently slowed.
func _apply_hit_stop(real_seconds: float, time_scale: float) -> void:
	if _hit_stop_active:
		return
	_hit_stop_active = true
	var prev_scale: float = Engine.time_scale
	Engine.time_scale = time_scale
	# Timer args: (time, process_always, process_in_physics, ignore_time_scale).
	#   process_always=true — keeps the timer ticking if a menu opens mid-pulse.
	#   ignore_time_scale=true — wall-clock seconds, so the slow-mo actually ends.
	var timer := get_tree().create_timer(real_seconds, true, false, true)
	await timer.timeout
	Engine.time_scale = prev_scale
	_hit_stop_active = false


# ============================================================================
# WEAPON SLOTS
# ============================================================================

func _refresh_all_weapon_slots() -> void:
	_refresh_weapon_slot(_weapon_slot_primary,   _primary_for_display())
	_refresh_weapon_slot(_weapon_slot_secondary, RunState.secondary_weapon)
	_refresh_weapon_slot(_prepared_slot_primary,   RunState.prepared_primary)
	_refresh_weapon_slot(_prepared_slot_secondary, RunState.prepared_secondary)


## Primary slot displays bare hands when nothing is equipped — communicates
## the unarmed-melee fallback. Other slots show empty.
func _primary_for_display() -> Resource:
	if RunState.primary_weapon != null:
		return RunState.primary_weapon
	# Lazy-load to avoid a hard dependency at script-parse time.
	return load("res://weapons/instances/player_weapons/bare_hands.tres")


func _refresh_weapon_slot(slot: Control, resource: Resource) -> void:
	if slot == null:
		return
	var name_label: Label = slot.get_meta("name_label")
	if resource == null:
		name_label.text = "— empty —"
		name_label.add_theme_color_override("font_color", COLOR_DIM_TEXT)
		_apply_slot_style(slot, COLOR_ENTRY_BORDER, 1, false)
		return
	var w: Weapon = resource
	name_label.text = w.weapon_name
	var ec: Color = Weapon.element_color(w.element)
	name_label.add_theme_color_override("font_color", ec)
	_apply_slot_style(slot, ec, 2, true)


func _update_cooldown_overlays() -> void:
	if not is_instance_valid(_player):
		return
	var p: Player = _player
	_set_cooldown_ratio(_weapon_slot_primary,   p.get_primary_cooldown_ratio())
	_set_cooldown_ratio(_weapon_slot_secondary, p.get_secondary_cooldown_ratio())

	# Prepared slots: during a swap, fill the overlay as a progress
	# indicator (1.0 = swap just started, sweeps to 0.0 = complete).
	# When not swapping, the overlay is clear (0.0).
	var swap_progress: float = p.get_swap_progress()
	_set_cooldown_ratio(_prepared_slot_primary, swap_progress)
	_set_cooldown_ratio(_prepared_slot_secondary, swap_progress)

	# Animate prepared slot dim: brighten during swap to draw the eye
	# toward the incoming weapons, then snap back to dim on completion.
	var dim: Color = PREPARED_DIM if swap_progress == 0.0 else Color.WHITE
	_prepared_slot_primary.modulate = dim
	_prepared_slot_secondary.modulate = dim


func _set_cooldown_ratio(slot: Control, ratio: float) -> void:
	if slot == null:
		return
	var cd: ColorRect = slot.get_meta("cooldown_rect")
	# Use set_anchor with keep_offset=true. The default property setter
	# (cd.anchor_bottom = X) calls set_anchor with keep_offset=false,
	# which preserves the visual rect by adjusting offset_bottom to
	# compensate — so the overlay's on-screen height wouldn't change.
	# Passing keep_offset=true leaves the offset alone, so the new
	# anchor value drives the visual height as intended.
	cd.set_anchor(SIDE_BOTTOM, clampf(ratio, 0.0, 1.0), true)


# ============================================================================
# STYLEBOX HELPERS
# Shared painter functions that keep the HUD's panels / bars / slots
# producing the same visual language as the menu UIs. Centralized so a
# tweak to the palette propagates everywhere without hunting for
# inline StyleBoxFlat constructions.
# ============================================================================

## Stylebox for the outer "card" panels (vitals card, currency card).
## Matches the panel stylebox the menu UIs use for their detail cards —
## dark warm bg, dim warm border, gentle 6px rounded corners.
func _make_panel_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_PANEL_BG
	s.border_color = COLOR_PANEL_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Build a ProgressBar pre-styled with a dark stylebox background and a
## solid-color fill stylebox. Replaces the previous `modulate`-based
## coloring which tinted both bg and fill together and looked muddy.
##
## The bar carries two metas so callers can animate the fill color
## without rebuilding the stylebox:
##   fill_stylebox  -> StyleBoxFlat (the fill resource; mutate bg_color)
##   fill_color     -> Color (the base color; used to restore after a flash)
func _make_styled_bar(width: float, height: float, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.min_value = 0
	bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = COLOR_BAR_BG
	bg.border_color = COLOR_BAR_BORDER
	bg.set_border_width_all(1)
	# Corners scale with height — chunky on the 18px HP bar, subtle on
	# the 8px noise/smell bars where a 4px radius would dominate.
	var r: int = max(2, int(height * 0.25))
	bg.set_corner_radius_all(r)
	bar.add_theme_stylebox_override("background", bg)

	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(r)
	# Subtle inner border tint of the same hue so the fill reads as a
	# filled gem rather than a flat painted bar.
	fg.border_color = Color(
		minf(fill_color.r + 0.10, 1.0),
		minf(fill_color.g + 0.10, 1.0),
		minf(fill_color.b + 0.10, 1.0),
		1.0,
	)
	fg.set_border_width_all(1)
	bar.add_theme_stylebox_override("fill", fg)

	# Expose the fill stylebox so callers can animate its bg_color
	# directly (the right way to flash a phase change). Tweening
	# modulate also tints the bar's dark background, which looked muddy
	# for the boss bar's phase-2 purple flash.
	bar.set_meta("fill_stylebox", fg)
	bar.set_meta("fill_color", fill_color)
	return bar


## Paint a weapon slot's panel stylebox. `filled` switches between the
## empty/equipped background tints so an unequipped slot looks visibly
## dormant compared to an active one — same affordance the inventory's
## empty-slot stylebox provides.
##
## Mirrors inventory_ui.gd's _apply_equip_slot_style but trimmed: the
## HUD slot isn't interactive, so we don't paint a hover stylebox.
func _apply_slot_style(panel: Control, border_color: Color, border_width: int, filled: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_SLOT_BG if filled else COLOR_SLOT_BG_EMPTY
	s.border_color = border_color
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(4)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", s)


# ============================================================================
# STATUS WIDGETS
# ============================================================================

func _make_status_widget(fx: StatusEffect, stacks: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(40, 40)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = fx.tint_color if fx.tint_color.a > 0.0 else Color(0.4, 0.4, 0.4, 1.0)
	bg.color.a = 0.85
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	var stack_label := Label.new()
	stack_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack_label.add_theme_font_size_override("font_size", 14)
	stack_label.add_theme_color_override("font_color", Color.WHITE)
	stack_label.text = "%d" % stacks if stacks > 1 else fx.display_name.substr(0, 1)
	stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stack_label)
	panel.set_meta("stack_label", stack_label)
	panel.set_meta("effect", fx)
	panel.tooltip_text = "%s ×%d" % [fx.display_name, stacks]

	return panel


func _update_status_widget(widget: Control, fx: StatusEffect, stacks: int) -> void:
	var stack_label: Label = widget.get_meta("stack_label")
	stack_label.text = "%d" % stacks if stacks > 1 else fx.display_name.substr(0, 1)
	widget.tooltip_text = "%s ×%d" % [fx.display_name, stacks]


# ============================================================================
# FLOATING DAMAGE NUMBERS / WORLD-SPACE TEXT
# ============================================================================

func _spawn_damage_number(target: Node, amount: float, info: Dictionary) -> void:
	if not (target is Node2D):
		return
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return

	var world_pos: Vector2 = (target as Node2D).global_position + Vector2(0, -20)
	var screen_pos: Vector2 = (world_pos - camera.get_screen_center_position()) \
		* camera.zoom \
		+ get_viewport().get_visible_rect().size * 0.5

	var label := Label.new()
	label.text = "%d" % int(round(amount))
	label.add_theme_font_size_override("font_size", 16)
	var elem: int = info.get("element", 0)
	label.add_theme_color_override("font_color", Weapon.element_color(elem))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.position = screen_pos + Vector2(randf_range(-12, 12), 0)
	label.z_index = 100
	_float_layer.add_child(label)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - FLOAT_NUMBER_RISE,
		FLOAT_NUMBER_LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_NUMBER_LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


## Spawn a punchy world-space text indicator at a given world position.
## Used by the dodge / long-stun feedback paths. Differs from the damage
## number path by adding a "punch" scale-down on appearance (initial
## scale 1.25 → 1.0 over 0.12s) which makes the text feel like an
## emphatic stamp rather than a drift-by float. Tweens use the float
## layer so they survive any cleanup of the underlying target.
func _spawn_world_text(world_pos: Vector2, text: String, color: Color,
		font_size: int, lifetime: float, rise: float) -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	var screen_pos: Vector2 = (world_pos - camera.get_screen_center_position()) \
		* camera.zoom \
		+ get_viewport().get_visible_rect().size * 0.5

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 100
	label.scale = Vector2(1.25, 1.25)
	# Position at a rough estimate; corrected below once size is known.
	label.position = screen_pos
	_float_layer.add_child(label)
	# Re-center now that the label has measured itself (Label.size is
	# only valid after add_child has triggered its first layout). Pivot
	# to center so the scale tween expands/contracts from the middle of
	# the text instead of the top-left corner.
	label.position = screen_pos - label.size * 0.5
	label.pivot_offset = label.size * 0.5

	var tween := label.create_tween()
	tween.set_parallel(true)
	# Scale punch — 1.25 → 1.0 over the first 0.12s. TRANS_BACK gives
	# a tiny overshoot for that "stamp" feel.
	tween.tween_property(label, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Rise like a damage number, full lifetime.
	tween.tween_property(label, "position:y", label.position.y - rise, lifetime) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fade across the full lifetime, easing in so most of the text is
	# visible for most of the time, fading just at the tail.
	tween.tween_property(label, "modulate:a", 0.0, lifetime) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)
